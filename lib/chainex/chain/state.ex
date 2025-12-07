defmodule Chainex.Chain.State do
  @moduledoc """
  Represents the execution state of a chain.

  State flows through every chain execution, accumulating results from each step.
  Steps can read from and write to state using `store_as`, `get`, and `update`.

  ## State Model

  - Every chain execution has a `%State{}` that flows through all steps
  - State accumulates: each step can add to it via `store_as`
  - Variables passed to `run()` become initial state data
  - Step results are automatically available as `{{_last_result}}`
  - Named results via `store_as(:name)` are available as `{{name}}`
  - Optional session_id isolates state per user/conversation

  ## Examples

      # State flows through the chain
      "Research {{topic}}"
      |> Chain.new()
      |> Chain.llm(:anthropic)
      |> Chain.store_as(:research)
      |> Chain.llm(:openai, system: "Summarize: {{research}}")
      |> Chain.run(%{topic: "AI"})
      # => {:ok, result, %State{data: %{topic: "AI", research: "...", _last_result: "..."}}}
  """

  @type status :: :pending | :running | :paused | :completed | :failed

  @type t :: %__MODULE__{
          instance_id: String.t(),
          session_id: String.t() | nil,
          status: status(),
          current_step: non_neg_integer(),
          data: map(),
          step_results: [any()],
          started_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          error: any()
        }

  defstruct [
    :instance_id,
    :session_id,
    :status,
    :current_step,
    :data,
    :step_results,
    :started_at,
    :updated_at,
    :completed_at,
    :error
  ]

  @doc """
  Creates a new state with the given initial data.

  ## Examples

      State.new(%{topic: "AI"})
      State.new(%{topic: "AI"}, session_id: "user_123")
  """
  @spec new(map(), keyword()) :: t()
  def new(initial_data \\ %{}, opts \\ []) do
    %__MODULE__{
      instance_id: generate_instance_id(),
      session_id: Keyword.get(opts, :session_id),
      status: :pending,
      current_step: 0,
      data: initial_data,
      step_results: [],
      started_at: nil,
      updated_at: nil,
      completed_at: nil,
      error: nil
    }
  end

  @doc """
  Marks the state as running and sets the start time.
  """
  @spec start(t()) :: t()
  def start(%__MODULE__{} = state) do
    now = DateTime.utc_now()

    %{state | status: :running, started_at: now, updated_at: now}
  end

  @doc """
  Stores a value in the state data under the given key.
  Also updates `_last_result` to the same value.

  ## Examples

      state = State.put(state, :research, "Some research findings")
  """
  @spec put(t(), atom(), any()) :: t()
  def put(%__MODULE__{} = state, key, value) when is_atom(key) do
    updated_data =
      state.data
      |> Map.put(key, value)
      |> Map.put(:_last_result, value)

    %{state | data: updated_data, updated_at: DateTime.utc_now()}
  end

  @doc """
  Gets a value from the state data.
  Returns the default if the key is not found.

  ## Examples

      value = State.get(state, :research)
      value = State.get(state, :missing_key, "default")
  """
  @spec get(t(), atom(), any()) :: any()
  def get(%__MODULE__{} = state, key, default \\ nil) when is_atom(key) do
    Map.get(state.data, key, default)
  end

  @doc """
  Updates a value in the state data using an update function.

  ## Examples

      state = State.update(state, :count, fn count -> count + 1 end)
  """
  @spec update(t(), atom(), (any() -> any())) :: t()
  def update(%__MODULE__{} = state, key, update_fn) when is_atom(key) and is_function(update_fn, 1) do
    current_value = Map.get(state.data, key)
    new_value = update_fn.(current_value)
    put(state, key, new_value)
  end

  @doc """
  Merges new data into the state.

  ## Examples

      state = State.merge(state, %{key1: "value1", key2: "value2"})
  """
  @spec merge(t(), map()) :: t()
  def merge(%__MODULE__{} = state, new_data) when is_map(new_data) do
    updated_data = Map.merge(state.data, new_data)
    %{state | data: updated_data, updated_at: DateTime.utc_now()}
  end

  @doc """
  Records a step result and advances the current step counter.
  """
  @spec record_step_result(t(), any()) :: t()
  def record_step_result(%__MODULE__{} = state, result) do
    %{
      state
      | step_results: state.step_results ++ [result],
        current_step: state.current_step + 1,
        data: Map.put(state.data, :_last_result, result),
        updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Marks the state as paused.
  """
  @spec pause(t()) :: t()
  def pause(%__MODULE__{} = state) do
    %{state | status: :paused, updated_at: DateTime.utc_now()}
  end

  @doc """
  Marks the state as running (resume from paused).
  Optionally merges new variables into the state data.
  """
  @spec resume(t(), map()) :: t()
  def resume(%__MODULE__{} = state, new_variables \\ %{}) do
    updated_data = Map.merge(state.data, new_variables)
    %{state | status: :running, data: updated_data, updated_at: DateTime.utc_now()}
  end

  @doc """
  Marks the state as completed with the final result.
  """
  @spec complete(t(), any()) :: t()
  def complete(%__MODULE__{} = state, final_result) do
    now = DateTime.utc_now()
    updated_data = Map.put(state.data, :_last_result, final_result)

    %{
      state
      | status: :completed,
        data: updated_data,
        completed_at: now,
        updated_at: now
    }
  end

  @doc """
  Marks the state as failed with an error.
  """
  @spec fail(t(), any()) :: t()
  def fail(%__MODULE__{} = state, error) do
    now = DateTime.utc_now()

    %{
      state
      | status: :failed,
        error: error,
        completed_at: now,
        updated_at: now
    }
  end

  @doc """
  Checks if the state is in a terminal status (completed or failed).
  """
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{status: status}) do
    status in [:completed, :failed]
  end

  @doc """
  Checks if the state is paused.
  """
  @spec paused?(t()) :: boolean()
  def paused?(%__MODULE__{status: :paused}), do: true
  def paused?(%__MODULE__{}), do: false

  @doc """
  Checks if the state is running.
  """
  @spec running?(t()) :: boolean()
  def running?(%__MODULE__{status: :running}), do: true
  def running?(%__MODULE__{}), do: false

  @doc """
  Converts state data to a map suitable for variable resolution.
  This is used when resolving templates like `{{key}}`.
  """
  @spec to_variables(t()) :: map()
  def to_variables(%__MODULE__{data: data}) do
    data
  end

  # Private helpers

  defp generate_instance_id do
    # Generate a unique instance ID using timestamp and random bytes
    timestamp = System.system_time(:microsecond)
    random = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "chain_#{timestamp}_#{random}"
  end
end
