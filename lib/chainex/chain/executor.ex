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
  @spec execute_steps([Chain.step()], any(), Chain.t(), variables()) ::
          {:ok, any()} | {:error, any()}
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
      # Check if tools are enabled
      tools = Keyword.get(llm_opts, :tools, [])
      tool_choice = Keyword.get(llm_opts, :tool_choice, :none)

      if tools != [] and tool_choice != :none do
        # Execute with tool calling support
        execute_llm_with_tools(messages, provider, llm_opts, chain.options, 0)
      else
        # Regular LLM call without tools - remove tools from options
        clean_opts =
          llm_opts
          |> Keyword.delete(:tools)
          |> Keyword.put(:provider, provider)

        case LLM.chat(messages, clean_opts) do
          {:ok, response} -> {:ok, response.content}
          error -> error
        end
      end
    end
  end

  defp execute_step({:transform, function, _opts}, input, _chain, variables) do
    try do
      result =
        case :erlang.fun_info(function, :arity) do
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

          error ->
            error
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

    missing =
      Enum.filter(required, fn var ->
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
    messages =
      if chain.system_prompt do
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
        user_content =
          case input do
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

    # Don't add tools to the opts here - they'll be formatted in execute_llm_with_tools
    opts =
      step_opts
      |> Keyword.put_new(:temperature, 0.7)
      |> Keyword.put_new(:max_tokens, 1000)

    # Keep tools separate for processing
    opts =
      if tools != [] do
        opts
        |> Keyword.put(:tools, tools)
        |> Keyword.put_new(:tool_choice, :auto)
      else
        opts
      end

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
      resolved_value =
        case value do
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

  # LLM tool calling support
  defp execute_llm_with_tools(messages, provider, opts, chain_opts, depth) do
    # Prevent infinite loops - max 5 rounds of tool calls
    if depth > 5 do
      {:error, "Maximum tool calling depth exceeded"}
    else
      tools = Keyword.get(opts, :tools, [])

      # Convert tools to LLM format
      formatted_tools = Enum.map(tools, &Chainex.Tool.to_llm_format(&1, provider))

      # Add tools to options
      llm_opts =
        opts
        |> Keyword.put(:tools, formatted_tools)
        |> Keyword.put(:provider, provider)

      # Call LLM with tools
      case Chainex.LLM.chat(messages, llm_opts) do
        {:ok, %{tool_calls: tool_calls} = response}
        when is_list(tool_calls) and tool_calls != [] ->
          # Execute tool calls and continue conversation
          handle_tool_calls(response, messages, tools, provider, opts, chain_opts, depth + 1)

        {:ok, response} ->
          # No tool calls, return the content
          {:ok, response.content}

        error ->
          error
      end
    end
  end

  defp handle_tool_calls(assistant_response, messages, tools, provider, opts, _chain_opts, _depth) do
    # Execute each tool call
    tool_results =
      Enum.map(assistant_response.tool_calls, fn tool_call ->
        execute_tool_call(tool_call, tools)
      end)

    # Build updated message history
    # Add assistant message with tool calls
    assistant_msg = %{
      role: :assistant,
      content: assistant_response.content || "",
      tool_calls: assistant_response.tool_calls
    }

    # Add tool result messages
    tool_messages =
      Enum.zip(assistant_response.tool_calls, tool_results)
      |> Enum.map(fn {tool_call, result} ->
        %{
          role: :tool,
          tool_use_id: tool_call.id,
          content: format_tool_result(result)
        }
      end)

    # Continue conversation with tool results
    updated_messages = messages ++ [assistant_msg] ++ tool_messages

    # Make another LLM call with the tool results, but WITHOUT tools this time
    # to get the final response
    final_opts =
      opts
      |> Keyword.delete(:tools)
      |> Keyword.delete(:tool_choice)
      |> Keyword.put(:provider, provider)

    case Chainex.LLM.chat(updated_messages, final_opts) do
      {:ok, response} -> {:ok, response.content}
      error -> error
    end
  end

  defp execute_tool_call(tool_call, available_tools) do
    # Find the tool by name
    tool =
      Enum.find(available_tools, fn t ->
        to_string(t.name) == to_string(tool_call.name)
      end)

    case tool do
      nil ->
        {:error, "Tool not found: #{tool_call.name}"}

      tool ->
        # Convert string keys to atom keys
        atom_arguments = convert_tool_arguments(tool_call.arguments)

        # Execute the tool with the provided arguments
        Chainex.Tool.call(tool, atom_arguments)
    end
  end

  defp format_tool_result({:ok, result}) when is_binary(result), do: result
  defp format_tool_result({:ok, result}), do: Jason.encode!(result)
  defp format_tool_result({:error, error}), do: "Error: #{inspect(error)}"

  defp convert_tool_arguments(llm_args) when is_map(llm_args) do
    # Convert string keys from LLM to atom keys expected by tool
    # The atoms should already exist from the tool parameter definitions
    Map.new(llm_args, fn
      {key, value} when is_binary(key) ->
        try do
          atom_key = String.to_existing_atom(key)
          {atom_key, value}
        rescue
          ArgumentError ->
            # If atom doesn't exist, keep as string key
            {key, value}
        end

      {key, value} ->
        # Already correct type
        {key, value}
    end)
  end
end
