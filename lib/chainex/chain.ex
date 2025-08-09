defmodule Chainex.Chain do
  @moduledoc """
  A chain represents a sequence of LLM operations and transformations.
  Chains are immutable data structures that can be built once and executed many times.

  ## Examples

      # Simple chain
      chain = Chain.new("What is {{topic}}?")
      |> Chain.llm(:openai)
      |> Chain.run(%{topic: "quantum computing"})

      # Chain with system prompt
      chain = Chain.new(
        system: "You are a helpful {{role}} expert",
        user: "Explain {{concept}}"
      )
      |> Chain.llm(:openai)
      |> Chain.run(%{role: "physics", concept: "entanglement"})
  """

  defstruct [
    :system_prompt,
    :user_prompt,
    :steps,
    :options
  ]

  @type step_type :: :llm | :transform | :prompt | :tool | :parse | :conditional
  @type step :: {step_type(), any(), keyword()}
  @type variables :: %{atom() => any()} | %{String.t() => any()}

  @type t :: %__MODULE__{
          system_prompt: String.t() | nil,
          user_prompt: String.t() | any(),
          steps: [step()],
          options: keyword()
        }

  # Chain creation functions

  @doc """
  Creates a new chain.

  ## Examples

      # With just a user message
      Chain.new("What is {{topic}}?")

      # With system and user prompts
      Chain.new(
        system: "You are a helpful assistant",
        user: "Help me with {{task}}"
      )
  """
  @spec new(String.t()) :: t()
  @spec new(keyword()) :: t()
  def new(user_message) when is_binary(user_message) do
    %__MODULE__{
      system_prompt: nil,
      user_prompt: user_message,
      steps: [],
      options: []
    }
  end

  def new(opts) when is_list(opts) do
    %__MODULE__{
      system_prompt: Keyword.get(opts, :system),
      user_prompt: Keyword.get(opts, :user, ""),
      steps: [],
      options: Keyword.delete(opts, :system) |> Keyword.delete(:user)
    }
  end

  # Chain building functions

  @doc """
  Adds an LLM step to the chain.

  ## Options

    * `:model` - The model to use (e.g., "gpt-4", "claude-3")
    * `:temperature` - Temperature for randomness (0.0 to 1.0)
    * `:max_tokens` - Maximum tokens to generate
    * `:tools` - Tool calling mode (:auto, :none, or specific tool)
    * `:retries` - Number of retries on failure

  ## Examples

      chain |> Chain.llm(:openai)
      chain |> Chain.llm(:anthropic, model: "claude-3-opus")
  """
  @spec llm(t(), atom(), keyword()) :: t()
  def llm(%__MODULE__{} = chain, provider, opts \\ []) do
    step = {:llm, provider, opts}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Routes to an appropriate LLM based on a routing function or map.
  
  ## Examples
  
      # Route based on task type
      chain |> Chain.route_llm(%{
        reasoning: {:openai, model: "gpt-4"},
        summary: {:anthropic, model: "claude-3-haiku"}
      }, task: :reasoning)
      
      # Dynamic routing based on input
      chain |> Chain.route_llm(fn input ->
        if String.length(input) > 10000 do
          {:anthropic, model: "claude-3-opus"}
        else
          {:openai, model: "gpt-4"}
        end
      end)
  """
  @spec route_llm(t(), map() | function(), keyword()) :: t()
  def route_llm(%__MODULE__{} = chain, router, opts \\ []) when is_map(router) or is_function(router) do
    step = {:route_llm, router, opts}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Conditionally selects an LLM provider based on a predicate.
  
  ## Examples
  
      chain |> Chain.llm_if(
        fn _input, vars -> vars.use_premium end,
        {:openai, model: "gpt-4"},
        {:openai, model: "gpt-3.5-turbo"}
      )
  """
  @spec llm_if(t(), function(), {atom(), keyword()}, {atom(), keyword()}) :: t()
  def llm_if(%__MODULE__{} = chain, predicate, if_provider, else_provider) do
    step = {:llm_if, predicate, if_provider, else_provider}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Executes multiple LLMs in parallel and returns all results.
  
  ## Examples
  
      chain |> Chain.parallel_llm([
        {:openai, model: "gpt-4"},
        {:anthropic, model: "claude-3-opus"}
      ])
  """
  @spec parallel_llm(t(), list({atom(), keyword()})) :: t()
  def parallel_llm(%__MODULE__{} = chain, providers) when is_list(providers) do
    step = {:parallel_llm, providers, []}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Selects an LLM that supports the required capability.
  
  ## Examples
  
      chain |> Chain.llm_with_capability(:long_context, max_tokens: 100_000)
      chain |> Chain.llm_with_capability(:image_generation)
  """
  @spec llm_with_capability(t(), atom(), keyword()) :: t()
  def llm_with_capability(%__MODULE__{} = chain, capability, opts \\ []) do
    step = {:llm_with_capability, capability, opts}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Adds a transform step to the chain.

  The transform function receives the previous step's output and optionally the variables.

  ## Examples

      # Simple transform
      chain |> Chain.transform(&String.upcase/1)

      # Transform with variables
      chain |> Chain.transform(fn result, vars ->
        "Result for \#{vars.topic}: \#{result}"
      end)
  """
  @spec transform(t(), function()) :: t()
  def transform(%__MODULE__{} = chain, transform_fn) when is_function(transform_fn) do
    step = {:transform, transform_fn, []}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Adds a prompt template step to the chain.

  ## Examples

      chain |> Chain.prompt("Analyze this: {{input}}")
  """
  @spec prompt(t(), String.t() | Chainex.Prompt.t(), keyword()) :: t()
  def prompt(%__MODULE__{} = chain, template, opts \\ []) do
    step = {:prompt, template, opts}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Adds a tool calling step to the chain.

  ## Examples

      chain |> Chain.tool(:calculator, expression: "{{calculation}}")
  """
  @spec tool(t(), atom(), keyword()) :: t()
  def tool(%__MODULE__{} = chain, name, params \\ []) do
    step = {:tool, name, params}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Adds a parsing step to the chain.

  ## Examples

      # Parse as JSON
      chain |> Chain.parse(:json)

      # Parse with schema validation
      chain |> Chain.parse(:json, %{name: :string, age: :integer})

      # Parse into struct
      chain |> Chain.parse(:struct, MyModule)
  """
  @spec parse(t(), atom() | function(), any()) :: t()
  def parse(%__MODULE__{} = chain, parser_type, schema_or_module \\ nil) do
    opts = if schema_or_module, do: [schema: schema_or_module], else: []
    step = {:parse, parser_type, opts}
    
    # Auto-inject format instructions if the previous step is an LLM call
    updated_chain = inject_format_instructions(chain, parser_type, schema_or_module)
    
    %{updated_chain | steps: updated_chain.steps ++ [step]}
  end

  # Helper functions for format injection

  defp inject_format_instructions(%__MODULE__{steps: steps} = chain, parser_type, schema_or_module) do
    case List.last(steps) do
      {:llm, provider, opts} ->
        # Modify the last LLM step to include format instructions
        format_instructions = generate_format_instructions(parser_type, schema_or_module)
        updated_opts = inject_instructions_into_llm_opts(opts, format_instructions)
        updated_step = {:llm, provider, updated_opts}
        updated_steps = List.replace_at(steps, -1, updated_step)
        %{chain | steps: updated_steps}
        
      _ ->
        # Previous step is not an LLM call, no modification needed
        chain
    end
  end

  defp generate_format_instructions(:json, nil) do
    "\n\nIMPORTANT: Please respond with valid JSON only. Do not include any explanatory text before or after the JSON."
  end

  defp generate_format_instructions(:json, schema) when is_map(schema) do
    fields = schema |> Map.keys() |> Enum.map(&to_string/1) |> Enum.join(", ")
    "\n\nIMPORTANT: Please respond with valid JSON only containing these fields: #{fields}. Do not include any explanatory text before or after the JSON."
  end

  defp generate_format_instructions(:struct, module) when is_atom(module) do
    # Get struct fields to provide guidance
    fields = try do
      module.__struct__()
      |> Map.keys()
      |> Enum.reject(&(&1 == :__struct__))
      |> Enum.map(&to_string/1)
      |> Enum.join(", ")
    rescue
      _ -> "appropriate"
    end
    
    "\n\nIMPORTANT: Please respond with valid JSON only containing these fields: #{fields}. Do not include any explanatory text before or after the JSON."
  end

  defp generate_format_instructions(_, _) do
    # For custom parsers or unknown types, provide generic instruction
    "\n\nIMPORTANT: Please provide your response in the exact format requested."
  end

  defp inject_instructions_into_llm_opts(opts, instructions) do
    # Check if there's a system message in the opts, if so append to it
    case Keyword.get(opts, :system) do
      nil ->
        # No existing system message, add format instructions as system message
        Keyword.put(opts, :system, String.trim(instructions))
        
      existing_system ->
        # Append to existing system message
        updated_system = existing_system <> instructions
        Keyword.put(opts, :system, updated_system)
    end
  end

  # Execution functions

  @doc """
  Executes the chain with the given variables.

  ## Examples

      {:ok, result} = chain |> Chain.run(%{topic: "AI"})
  """
  @spec run(t(), variables()) :: {:ok, any()} | {:error, any()}
  def run(%__MODULE__{} = chain, variables \\ %{}) do
    Chainex.Chain.Executor.execute(chain, variables)
  end

  @doc """
  Runs the chain and returns result with metadata.
  
  ## Examples
  
      {:ok, result, metadata} = Chain.run_with_metadata(chain)
      IO.puts("Total cost: \#{metadata.total_cost}")
      IO.puts("Total tokens: \#{metadata.total_tokens}")
  """
  @spec run_with_metadata(t(), variables()) :: {:ok, any(), map()} | {:error, any()}
  def run_with_metadata(%__MODULE__{} = chain, variables \\ %{}) do
    Chainex.Chain.Executor.execute_with_metadata(chain, variables)
  end

  @doc """
  Executes the chain and raises on error.

  ## Examples

      result = chain |> Chain.run!(%{topic: "AI"})
  """
  @spec run!(t(), variables()) :: any()
  def run!(%__MODULE__{} = chain, variables \\ %{}) do
    case run(chain, variables) do
      {:ok, result} -> result
      {:error, error} -> raise "Chain execution failed: #{inspect(error)}"
    end
  end

  # Configuration functions

  @doc """
  Adds memory configuration to the chain.

  ## Examples

      chain |> Chain.with_memory(:conversation)
  """
  @spec with_memory(t(), atom()) :: t()
  def with_memory(%__MODULE__{} = chain, memory_type) do
    updated_options = Keyword.put(chain.options, :memory, memory_type)
    %{chain | options: updated_options}
  end

  @doc """
  Adds tools to the chain.

  ## Examples

      chain |> Chain.with_tools([weather_tool, calculator_tool])
  """
  @spec with_tools(t(), [Chainex.Tool.t()]) :: t()
  def with_tools(%__MODULE__{} = chain, tools) when is_list(tools) do
    updated_options = Keyword.put(chain.options, :tools, tools)
    %{chain | options: updated_options}
  end

  @doc """
  Specifies required variables for the chain.

  ## Examples

      chain |> Chain.require_variables([:topic, :language])
  """
  @spec require_variables(t(), [atom()]) :: t()
  def require_variables(%__MODULE__{} = chain, required_vars) when is_list(required_vars) do
    updated_options = Keyword.put(chain.options, :required_variables, required_vars)
    %{chain | options: updated_options}
  end

  @doc """
  Adds metadata to the chain.

  ## Examples

      chain |> Chain.with_metadata(%{user_id: "123", session: "abc"})
  """
  @spec with_metadata(t(), map()) :: t()
  def with_metadata(%__MODULE__{} = chain, metadata) when is_map(metadata) do
    existing_metadata = Keyword.get(chain.options, :metadata, %{})
    updated_metadata = Map.merge(existing_metadata, metadata)
    updated_options = Keyword.put(chain.options, :metadata, updated_metadata)
    %{chain | options: updated_options}
  end

  @doc """
  Sets a session ID for memory management.

  ## Examples

      chain |> Chain.with_session("user_123")
  """
  @spec with_session(t(), String.t()) :: t()
  def with_session(%__MODULE__{} = chain, session_id) when is_binary(session_id) do
    updated_options = Keyword.put(chain.options, :session_id, session_id)
    %{chain | options: updated_options}
  end
end
