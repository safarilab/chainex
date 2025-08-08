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
    %{chain | steps: chain.steps ++ [step]}
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
