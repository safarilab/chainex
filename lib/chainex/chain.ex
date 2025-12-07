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
    :options,
    :initial_state,
    :persist_to
  ]

  @type step_type ::
          :llm
          | :transform
          | :prompt
          | :tool
          | :parse
          | :conditional
          | :store_as
          | :get
          | :update
          | :when
          | :otherwise
          | :loop
          | :await
          | :parallel
          | :execute_tools
  @type step :: {step_type(), any(), keyword()}
  @type variables :: %{atom() => any()} | %{String.t() => any()}

  @type t :: %__MODULE__{
          system_prompt: String.t() | nil,
          user_prompt: String.t() | any(),
          steps: [step()],
          options: keyword(),
          initial_state: map() | nil,
          persist_to: :ets | :database | module() | nil
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
      options: [],
      initial_state: nil,
      persist_to: nil
    }
  end

  def new(opts) when is_list(opts) do
    %__MODULE__{
      system_prompt: Keyword.get(opts, :system),
      user_prompt: Keyword.get(opts, :user, ""),
      steps: [],
      options: Keyword.delete(opts, :system) |> Keyword.delete(:user),
      initial_state: nil,
      persist_to: nil
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
  def route_llm(%__MODULE__{} = chain, router, opts \\ [])
      when is_map(router) or is_function(router) do
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

  defp inject_format_instructions(
         %__MODULE__{steps: steps} = chain,
         parser_type,
         schema_or_module
       ) do
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
    fields =
      try do
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

      # Simple conversation memory (uses ETS)
      chain |> Chain.with_memory(:conversation)
      
      # Buffer memory
      chain |> Chain.with_memory(:buffer)
      
      # Persistent memory with file backend
      chain |> Chain.with_memory(:persistent, file_path: "/tmp/memory.dat")
      
      # Persistent memory with database backend
      chain |> Chain.with_memory(:persistent, 
        backend: :database, 
        repo: MyApp.Repo, 
        table: "chainex_memory"
      )
      
      # With pruning options
      chain |> Chain.with_memory(:persistent,
        file_path: "/tmp/memory.dat",
        max_size: 100,
        prune_strategy: :lru,
        auto_prune: true
      )
  """
  @spec with_memory(t(), atom(), keyword() | map()) :: t()
  def with_memory(%__MODULE__{} = chain, memory_type, options \\ []) do
    memory_options =
      case options do
        opts when is_list(opts) -> Enum.into(opts, %{})
        opts when is_map(opts) -> opts
      end

    updated_options =
      chain.options
      |> Keyword.put(:memory, memory_type)
      |> Keyword.put(:memory_options, memory_options)

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
  Configures automatic retry on failures.

  ## Options
  - `:max_attempts` - Maximum retry attempts (default: 3)
  - `:delay` - Delay between retries in milliseconds (default: 1000)

  ## Examples

      # Retry up to 3 times with 1 second delay
      chain |> Chain.with_retry()
      
      # Custom retry configuration
      chain |> Chain.with_retry(max_attempts: 5, delay: 2000)
  """
  @spec with_retry(t(), keyword()) :: t()
  def with_retry(%__MODULE__{} = chain, opts \\ []) do
    retry_config = %{
      max_attempts: Keyword.get(opts, :max_attempts, 3),
      delay: Keyword.get(opts, :delay, 1000)
    }

    updated_options = Keyword.put(chain.options, :retry, retry_config)
    %{chain | options: updated_options}
  end

  @doc """
  Sets timeout for chain execution.

  ## Examples

      # 10 second timeout
      chain |> Chain.with_timeout(10_000)
  """
  @spec with_timeout(t(), non_neg_integer()) :: t()
  def with_timeout(%__MODULE__{} = chain, timeout_ms)
      when is_integer(timeout_ms) and timeout_ms >= 0 do
    updated_options = Keyword.put(chain.options, :timeout, timeout_ms)
    %{chain | options: updated_options}
  end

  @doc """
  Sets a fallback value if the chain fails.

  ## Examples

      # Return default message on failure
      chain |> Chain.with_fallback("Sorry, something went wrong. Please try again.")
      
      # Use a function for dynamic fallback
      chain |> Chain.with_fallback(fn _error -> "Service temporarily unavailable" end)
  """
  @spec with_fallback(t(), any() | (any() -> any())) :: t()
  def with_fallback(%__MODULE__{} = chain, fallback) do
    updated_options = Keyword.put(chain.options, :fallback, fallback)
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

  # State Management Functions

  @doc """
  Stores the result of the previous step in state under the given key.

  The stored value can be accessed in subsequent steps using `{{key}}` templates.

  ## Examples

      chain
      |> Chain.llm(:anthropic)
      |> Chain.store_as(:research)
      |> Chain.llm(:openai, system: "Summarize: {{research}}")
  """
  @spec store_as(t(), atom()) :: t()
  def store_as(%__MODULE__{} = chain, key) when is_atom(key) do
    step = {:store_as, key, []}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Gets a value from state and makes it the current input.

  ## Examples

      chain
      |> Chain.get(:saved_value)
      |> Chain.transform(&process/1)
  """
  @spec get(t(), atom()) :: t()
  def get(%__MODULE__{} = chain, key) when is_atom(key) do
    step = {:get, key, []}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Updates a value in state using an update function.

  ## Examples

      chain
      |> Chain.update(:counter, fn count -> count + 1 end)
  """
  @spec update(t(), atom(), function()) :: t()
  def update(%__MODULE__{} = chain, key, update_fn) when is_atom(key) and is_function(update_fn, 1) do
    step = {:update, key, [update_fn: update_fn]}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Configures where state should be persisted.

  ## Options

    * `:ets` - In-memory storage (fast, non-persistent)
    * `:database` - Ecto-based storage (persistent)
    * Custom module - Any module implementing `Chainex.Chain.Store` behaviour

  ## Examples

      chain |> Chain.persist_to(:ets)
      chain |> Chain.persist_to(:database)
      chain |> Chain.persist_to(MyApp.RedisStore)
  """
  @spec persist_to(t(), :ets | :database | module()) :: t()
  def persist_to(%__MODULE__{} = chain, backend) do
    %{chain | persist_to: backend}
  end

  # Control Flow Functions

  @doc """
  Executes a chain or builder function if the condition is true.

  Multiple `condition` calls can be chained together - the first matching condition wins.
  Use `otherwise` to provide a fallback for when no conditions match.

  ## Examples

      # Simple condition with chain
      chain
      |> Chain.condition(&(&1.urgent?), urgent_chain)
      |> Chain.otherwise(normal_chain)

      # Multiple conditions
      chain
      |> Chain.condition(&(&1.type == "billing"), billing_chain)
      |> Chain.condition(&(&1.type == "tech"), tech_chain)
      |> Chain.otherwise(general_chain)

      # Inline builder function
      chain
      |> Chain.condition(&(&1.needs_review?), fn c ->
        c |> Chain.await(:approval) |> Chain.llm(:anthropic)
      end)
  """
  @spec condition(t(), function(), t() | function()) :: t()
  def condition(%__MODULE__{} = chain, condition_fn, chain_or_builder)
      when is_function(condition_fn) do
    step = {:when, condition_fn, [chain_or_builder: chain_or_builder]}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Provides a fallback for when no `when` conditions match.

  ## Examples

      chain
      |> Chain.when(&(&1.urgent?), urgent_chain)
      |> Chain.otherwise(default_chain)

      # Pass through unchanged
      chain
      |> Chain.when(&(&1.special?), special_chain)
      |> Chain.otherwise(&(&1))
  """
  @spec otherwise(t(), t() | function()) :: t()
  def otherwise(%__MODULE__{} = chain, chain_or_builder) do
    step = {:otherwise, chain_or_builder, []}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Loops while a condition is true.

  ## Options

    * `:max_iterations` - Maximum number of iterations (default: 10)

  ## Examples

      # Loop until quality score is high enough
      chain
      |> Chain.loop(
        fn result, _state -> result.score < 0.8 end,
        fn c -> c |> Chain.llm(:anthropic) |> Chain.transform(&score/1) end,
        max_iterations: 5
      )

      # Agentic tool loop
      chain
      |> Chain.loop(
        fn result, _state -> result.tool_calls != nil end,
        fn c -> c |> Chain.execute_tools() |> Chain.llm(:anthropic) end,
        max_iterations: 10
      )
  """
  @spec loop(t(), function(), function(), keyword()) :: t()
  def loop(%__MODULE__{} = chain, condition, body_builder, opts \\ [])
      when is_function(condition) and is_function(body_builder) do
    step = {:loop, condition, [body_builder: body_builder] ++ opts}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Pauses the chain execution and waits for human input.

  When the chain encounters this step, it pauses and waits for `resume/2`
  to be called with the awaited input.

  ## Examples

      chain
      |> Chain.llm(:anthropic)
      |> Chain.await(:human_review)
      |> Chain.llm(:anthropic, system: "Incorporate feedback: {{human_review}}")
      |> Chain.run_async(vars)

      # Later
      Chain.resume(instance_id, %{human_review: "Looks good!"})
  """
  @spec await(t(), atom()) :: t()
  def await(%__MODULE__{} = chain, key) when is_atom(key) do
    step = {:await, key, []}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Executes multiple branches in parallel and collects results.

  Each branch receives the same input and runs concurrently.
  Results are collected as a list in the order of the branches.

  ## Examples

      chain
      |> Chain.parallel([
        fn c -> c |> Chain.llm(:anthropic, system: "Sentiment analysis") end,
        fn c -> c |> Chain.llm(:openai, system: "Entity extraction") end,
        fn c -> c |> Chain.llm(:anthropic, system: "Summarization") end
      ])
      |> Chain.transform(fn [sentiment, entities, summary] ->
        %{sentiment: sentiment, entities: entities, summary: summary}
      end)
  """
  @spec parallel(t(), [function()]) :: t()
  def parallel(%__MODULE__{} = chain, builder_fns) when is_list(builder_fns) do
    step = {:parallel, builder_fns, []}
    %{chain | steps: chain.steps ++ [step]}
  end

  @doc """
  Executes tool calls from the previous LLM response.

  This is used in agentic loops where the LLM decides which tools to call.

  ## Examples

      chain
      |> Chain.with_tools([calculator, search])
      |> Chain.llm(:anthropic, tool_choice: :auto)
      |> Chain.execute_tools()
      |> Chain.store_as(:tool_results)
  """
  @spec execute_tools(t()) :: t()
  def execute_tools(%__MODULE__{} = chain) do
    step = {:execute_tools, nil, []}
    %{chain | steps: chain.steps ++ [step]}
  end

  # Async Execution Functions

  @doc """
  Executes the chain asynchronously with state tracking.

  Returns an instance_id that can be used to:
  - Check execution status with `get_state/1`
  - Pause execution with `pause/1`
  - Resume execution with `resume/2`

  ## Examples

      {:ok, instance_id} = chain |> Chain.run_async(%{topic: "AI"})

      # Check status
      {:ok, state} = Chain.get_state(instance_id)

      # Pause if needed
      :ok = Chain.pause(instance_id)

      # Resume later
      {:ok, result, final_state} = Chain.resume(instance_id, %{extra: "data"})
  """
  @spec run_async(t(), variables()) :: {:ok, String.t()} | {:error, any()}
  def run_async(%__MODULE__{} = chain, variables \\ %{}) do
    Chainex.Chain.Instance.start(chain, variables)
  end

  @doc """
  Gets the current state of an async chain execution.

  ## Examples

      {:ok, state} = Chain.get_state(instance_id)
      IO.inspect(state.status)  # :running, :paused, :completed, :failed
      IO.inspect(state.data)    # Accumulated state data
  """
  @spec get_state(String.t()) :: {:ok, Chainex.Chain.State.t()} | {:error, any()}
  def get_state(instance_id) when is_binary(instance_id) do
    Chainex.Chain.Instance.get_state(instance_id)
  end

  @doc """
  Pauses an async chain execution.

  The chain will pause at the next step boundary and can be resumed later.

  ## Examples

      :ok = Chain.pause(instance_id)
  """
  @spec pause(String.t()) :: :ok | {:error, any()}
  def pause(instance_id) when is_binary(instance_id) do
    Chainex.Chain.Instance.pause(instance_id)
  end

  @doc """
  Resumes a paused async chain execution.

  Optionally pass new variables to merge into the state.

  ## Examples

      # Resume without new data
      {:ok, result, state} = Chain.resume(instance_id)

      # Resume with new data (e.g., human input)
      {:ok, result, state} = Chain.resume(instance_id, %{human_review: "Approved"})
  """
  @spec resume(String.t(), variables()) :: {:ok, any(), Chainex.Chain.State.t()} | {:error, any()}
  def resume(instance_id, new_variables \\ %{}) when is_binary(instance_id) do
    Chainex.Chain.Instance.resume(instance_id, new_variables)
  end
end
