defmodule Chainex.Chain.Executor do
  @moduledoc """
  Executes chain steps and manages the execution flow.
  """
  
  alias Chainex.Chain
  alias Chainex.Chain.VariableResolver
  alias Chainex.LLM
  
  @type variables :: %{atom() => any()} | %{String.t() => any()}
  
  @doc """
  Executes a chain with the given variables.
  """
  @spec execute(Chain.t(), variables()) :: {:ok, any()} | {:error, any()}
  def execute(%Chain{} = chain, variables) do
    with {:ok, validated_vars} <- validate_required_variables(chain, variables),
         {:ok, initial_input} <- prepare_initial_input(chain, validated_vars) do
      execute_steps(chain.steps, initial_input, chain, validated_vars)
    end
  end
  
  @doc """
  Executes a list of steps sequentially.
  """
  @spec execute_steps([Chain.step()], any(), Chain.t(), variables()) :: {:ok, any()} | {:error, any()}
  def execute_steps([], current_input, _chain, _variables) do
    {:ok, current_input}
  end
  
  def execute_steps([step | rest], current_input, chain, variables) do
    case execute_step(step, current_input, chain, variables) do
      {:ok, result} ->
        execute_steps(rest, result, chain, variables)
      {:error, _} = error ->
        error
    end
  end
  
  # Execute individual step types
  
  defp execute_step({:llm, provider, opts}, input, chain, variables) do
    with {:ok, messages} <- build_messages(chain, input, variables),
         {:ok, llm_opts} <- prepare_llm_options(chain, opts, variables) do
      # Use the existing LLM module's chat function
      case LLM.chat(messages, Keyword.put(llm_opts, :provider, provider)) do
        {:ok, response} -> {:ok, response.content}
        error -> error
      end
    end
  end
  
  defp execute_step({:transform, function, _opts}, input, _chain, variables) do
    try do
      result = case :erlang.fun_info(function, :arity) do
        {:arity, 1} -> function.(input)
        {:arity, 2} -> function.(input, variables)
        _ -> {:error, "Transform function must have arity 1 or 2"}
      end
      
      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
  
  defp execute_step({:prompt, template, _opts}, input, _chain, variables) do
    # Merge input into variables for template resolution
    merged_vars = Map.put(variables, :input, input)
    
    case template do
      %Chainex.Prompt{} = prompt ->
        # Handle Prompt struct - validate first
        case Chainex.Prompt.validate(prompt) do
          :ok ->
            case Chainex.Prompt.render(prompt, merged_vars) do
              {:ok, resolved} -> {:ok, resolved}
              error -> error
            end
          error -> error
        end
        
      template_string when is_binary(template_string) ->
        # Handle string template
        case VariableResolver.resolve(template_string, merged_vars) do
          {:ok, resolved} -> {:ok, resolved}
          error -> error
        end
        
      template_function when is_function(template_function) ->
        # Handle function template
        try do
          case :erlang.fun_info(template_function, :arity) do
            {:arity, 1} -> 
              {:ok, template_function.(input)}
            {:arity, 2} -> 
              {:ok, template_function.(input, variables)}
            _ -> 
              {:error, "Prompt function must have arity 1 or 2"}
          end
        rescue
          e -> {:error, Exception.message(e)}
        end
        
      _ ->
        {:error, "Invalid prompt template type"}
    end
  end
  
  defp execute_step({:tool, name, params}, input, chain, variables) do
    tools = Keyword.get(chain.options, :tools, [])
    
    case find_tool(tools, name) do
      nil ->
        {:error, "Tool not found: #{name}"}
      
      tool ->
        # Resolve parameters with variables
        merged_vars = Map.put(variables, :input, input)
        resolved_params = resolve_tool_params(params, merged_vars)
        
        Chainex.Tool.call(tool, resolved_params)
    end
  end
  
  defp execute_step({:parse, parser_type, opts}, input, _chain, _variables) do
    schema = Keyword.get(opts, :schema)
    
    case parser_type do
      :json ->
        parse_json(input, schema)
      
      :struct when is_atom(schema) ->
        parse_struct(input, schema)
      
      parser when is_function(parser) ->
        apply_parser(parser, input)
      
      _ ->
        {:error, "Unknown parser type: #{parser_type}"}
    end
  end
  
  # Helper functions
  
  defp validate_required_variables(chain, variables) do
    required = Keyword.get(chain.options, :required_variables, [])
    
    missing = Enum.filter(required, fn var ->
      not Map.has_key?(variables, var) and not Map.has_key?(variables, to_string(var))
    end)
    
    if Enum.empty?(missing) do
      {:ok, variables}
    else
      {:error, "Missing required variables: #{inspect(missing)}"}
    end
  end
  
  defp prepare_initial_input(chain, variables) do
    # If there's a user prompt, resolve it as the initial input
    if chain.user_prompt do
      VariableResolver.resolve(chain.user_prompt, variables)
    else
      {:ok, nil}
    end
  end
  
  defp build_messages(chain, input, variables) do
    messages = []
    
    # Add system message if present
    messages = if chain.system_prompt do
      case VariableResolver.resolve(chain.system_prompt, variables) do
        {:ok, resolved} ->
          messages ++ [%{role: :system, content: resolved}]
        {:error, _} = error ->
          error
      end
    else
      messages
    end
    
    # Check if we had an error from system prompt resolution
    case messages do
      {:error, _} = error ->
        error
      
      message_list ->
        # Add user message
        user_content = case input do
          nil -> ""
          content -> to_string(content)
        end
        
        messages = message_list ++ [%{role: :user, content: user_content}]
        
        {:ok, messages}
    end
  end
  
  defp prepare_llm_options(chain, step_opts, _variables) do
    # Merge chain options with step-specific options
    chain_opts = chain.options
    tools = Keyword.get(chain_opts, :tools, [])
    
    opts = step_opts
    |> Keyword.put_new(:tools, tools)
    |> Keyword.put_new(:temperature, 0.7)
    |> Keyword.put_new(:max_tokens, 1000)
    
    {:ok, opts}
  end
  
  defp find_tool(tools, name) when is_atom(name) do
    Enum.find(tools, fn tool ->
      tool.name == to_string(name) or tool.name == name
    end)
  end
  
  defp find_tool(tools, name) when is_binary(name) do
    Enum.find(tools, fn tool ->
      to_string(tool.name) == name
    end)
  end
  
  defp resolve_tool_params(params, variables) do
    Enum.map(params, fn {key, value} ->
      resolved_value = case value do
        "{{" <> _ = template ->
          case VariableResolver.resolve(template, variables) do
            {:ok, resolved} -> resolved
            _ -> value
          end
        value ->
          value
      end
      
      {key, resolved_value}
    end)
    |> Enum.into(%{})
  end
  
  defp parse_json(input, nil) when is_binary(input) do
    Jason.decode(input)
  end
  
  defp parse_json(input, schema) when is_binary(input) and is_map(schema) do
    with {:ok, data} <- Jason.decode(input) do
      validate_schema(data, schema)
    end
  end
  
  defp parse_json(input, _schema) do
    {:error, "Input must be a string for JSON parsing, got: #{inspect(input)}"}
  end
  
  defp parse_struct(input, module) when is_binary(input) do
    with {:ok, data} <- Jason.decode(input) do
      try do
        struct_data = string_keys_to_atoms(data)
        {:ok, struct(module, struct_data)}
      rescue
        e -> {:error, Exception.message(e)}
      end
    end
  end
  
  defp parse_struct(input, module) when is_map(input) do
    try do
      struct_data = string_keys_to_atoms(input)
      {:ok, struct(module, struct_data)}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
  
  defp apply_parser(parser, input) when is_function(parser, 1) do
    try do
      parser.(input)
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
  
  defp validate_schema(data, schema) do
    # Simple schema validation - can be enhanced
    # For now, just check that required keys exist
    required_keys = Map.keys(schema)
    data_keys = Map.keys(data)
    
    missing = required_keys -- data_keys
    
    if Enum.empty?(missing) do
      {:ok, data}
    else
      {:error, "Missing required fields: #{inspect(missing)}"}
    end
  end
  
  defp string_keys_to_atoms(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) ->
        {String.to_existing_atom(key), string_keys_to_atoms(value)}
      {key, value} ->
        {key, string_keys_to_atoms(value)}
    end)
  end
  
  defp string_keys_to_atoms(list) when is_list(list) do
    Enum.map(list, &string_keys_to_atoms/1)
  end
  
  defp string_keys_to_atoms(value), do: value
end