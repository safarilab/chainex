defmodule Chainex.Chain.Instance do
  @moduledoc """
  GenServer for managing async chain execution.

  Each running chain instance is managed by its own GenServer process.
  This enables:
  - Pause/resume of long-running chains
  - State persistence across steps
  - Human-in-the-loop workflows

  ## Usage

  Typically accessed through `Chain` module functions:

      {:ok, instance_id} = Chain.run_async(chain, %{topic: "AI"})
      {:ok, state} = Chain.get_state(instance_id)
      :ok = Chain.pause(instance_id)
      {:ok, result, state} = Chain.resume(instance_id, %{extra: "data"})
  """

  use GenServer

  alias Chainex.Chain
  alias Chainex.Chain.State
  alias Chainex.Chain.Store

  @registry Chainex.Chain.Instance.Registry
  @supervisor Chainex.Chain.Instance.Supervisor

  # Client API

  @doc """
  Starts a new chain instance.

  Returns the instance_id which can be used to interact with the chain.
  """
  @spec start(Chain.t(), map()) :: {:ok, String.t()} | {:error, any()}
  def start(%Chain{} = chain, variables \\ %{}) do
    # Create initial state
    session_id = Keyword.get(chain.options, :session_id)
    state = State.new(variables, session_id: session_id)
    instance_id = state.instance_id

    # Start the GenServer
    case start_instance(instance_id, chain, state) do
      {:ok, _pid} ->
        # Begin execution asynchronously
        GenServer.cast(via(instance_id), :execute)
        {:ok, instance_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the current state of a chain instance.
  """
  @spec get_state(String.t()) :: {:ok, State.t()} | {:error, any()}
  def get_state(instance_id) do
    case lookup(instance_id) do
      {:ok, pid} ->
        GenServer.call(pid, :get_state)

      {:error, :not_found} ->
        # Try to load from store
        Store.load(instance_id)
    end
  end

  @doc """
  Pauses a running chain instance.
  """
  @spec pause(String.t()) :: :ok | {:error, any()}
  def pause(instance_id) do
    case lookup(instance_id) do
      {:ok, pid} ->
        GenServer.call(pid, :pause)

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Resumes a paused chain instance.
  """
  @spec resume(String.t(), map()) :: {:ok, any(), State.t()} | {:error, any()}
  def resume(instance_id, new_variables \\ %{}) do
    case lookup(instance_id) do
      {:ok, pid} ->
        GenServer.call(pid, {:resume, new_variables}, :infinity)

      {:error, :not_found} ->
        # Try to load from store and restart
        resume_from_store(instance_id, new_variables)
    end
  end

  @doc """
  Stops a chain instance.
  """
  @spec stop(String.t()) :: :ok
  def stop(instance_id) do
    case lookup(instance_id) do
      {:ok, pid} ->
        GenServer.stop(pid)

      {:error, :not_found} ->
        :ok
    end
  end

  # GenServer Callbacks

  @impl true
  def init({chain, state}) do
    # Start the state as running
    state = State.start(state)

    {:ok, %{chain: chain, state: state, paused: false, awaiting: nil}}
  end

  @impl true
  def handle_call(:get_state, _from, %{state: state} = data) do
    {:reply, {:ok, state}, data}
  end

  @impl true
  def handle_call(:pause, _from, %{state: state} = data) do
    updated_state = State.pause(state)
    persist_state(data.chain, updated_state)
    {:reply, :ok, %{data | state: updated_state, paused: true}}
  end

  @impl true
  def handle_call({:resume, new_variables}, from, %{state: state, paused: true} = data) do
    updated_state = State.resume(state, new_variables)

    # Continue execution
    send(self(), {:continue_execution, from})
    {:noreply, %{data | state: updated_state, paused: false}}
  end

  @impl true
  def handle_call({:resume, new_variables}, from, %{state: state, awaiting: key} = data)
      when not is_nil(key) do
    # Resume from await point - merge the awaited value
    updated_state = State.put(state, key, Map.get(new_variables, key))
    updated_state = State.resume(updated_state, Map.delete(new_variables, key))

    # Continue execution from next step
    send(self(), {:continue_execution, from})
    {:noreply, %{data | state: updated_state, awaiting: nil}}
  end

  @impl true
  def handle_call({:resume, _}, _from, data) do
    {:reply, {:error, :not_paused}, data}
  end

  @impl true
  def handle_cast(:execute, data) do
    execute_chain(data, nil)
  end

  @impl true
  def handle_info({:continue_execution, from}, data) do
    execute_chain(data, from)
  end

  # Private Functions

  defp execute_chain(%{chain: chain, state: state, paused: paused} = data, reply_to) do
    if paused do
      {:noreply, data}
    else
      case execute_remaining_steps(chain, state) do
        {:ok, result, updated_state} ->
          final_state = State.complete(updated_state, result)
          persist_state(chain, final_state)

          if reply_to do
            GenServer.reply(reply_to, {:ok, result, final_state})
          end

          {:stop, :normal, %{data | state: final_state}}

        {:await, key, updated_state} ->
          paused_state = State.pause(updated_state)
          persist_state(chain, paused_state)
          {:noreply, %{data | state: paused_state, awaiting: key, paused: true}}

        {:paused, updated_state} ->
          persist_state(chain, updated_state)
          {:noreply, %{data | state: updated_state, paused: true}}

        {:error, reason} ->
          failed_state = State.fail(state, reason)
          persist_state(chain, failed_state)

          if reply_to do
            GenServer.reply(reply_to, {:error, reason})
          end

          {:stop, :normal, %{data | state: failed_state}}
      end
    end
  end

  defp execute_remaining_steps(chain, state) do
    # Get remaining steps starting from current_step
    remaining_steps = Enum.drop(chain.steps, state.current_step)

    execute_steps(remaining_steps, state, chain)
  end

  defp execute_steps([], state, _chain) do
    # All steps completed
    result = State.get(state, :_last_result)
    {:ok, result, state}
  end

  defp execute_steps([step | rest], state, chain) do
    # Check if paused
    if State.paused?(state) do
      {:paused, state}
    else
      case execute_step(step, state, chain) do
        {:ok, result, updated_state} ->
          new_state = State.record_step_result(updated_state, result)
          execute_steps(rest, new_state, chain)

        {:await, key, updated_state} ->
          {:await, key, updated_state}

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp execute_step({:store_as, key, _opts}, state, _chain) do
    # Store the last result under the given key
    last_result = State.get(state, :_last_result)
    updated_state = State.put(state, key, last_result)
    {:ok, last_result, updated_state}
  end

  defp execute_step({:get, key, _opts}, state, _chain) do
    # Get a value from state and make it the current result
    value = State.get(state, key)
    {:ok, value, state}
  end

  defp execute_step({:update, key, opts}, state, _chain) do
    # Update a value in state
    update_fn = Keyword.fetch!(opts, :update_fn)
    updated_state = State.update(state, key, update_fn)
    {:ok, State.get(updated_state, key), updated_state}
  end

  defp execute_step({:await, key, _opts}, state, _chain) do
    # Pause and wait for human input
    {:await, key, state}
  end

  defp execute_step({:when, condition, opts}, state, chain) do
    # Conditional execution
    last_result = State.get(state, :_last_result)

    try do
      if condition.(last_result) do
        chain_or_builder = Keyword.fetch!(opts, :chain_or_builder)
        execute_branch(chain_or_builder, state, chain, last_result)
      else
        # Condition not met, continue with current result
        {:ok, last_result, state}
      end
    rescue
      e -> {:error, {:condition_error, e}}
    end
  end

  defp execute_step({:otherwise, chain_or_builder, _opts}, state, chain) do
    # Fallback - execute if no previous when matched
    last_result = State.get(state, :_last_result)
    execute_branch(chain_or_builder, state, chain, last_result)
  end

  defp execute_step({:loop, condition, opts}, state, chain) do
    body_builder = Keyword.fetch!(opts, :body_builder)
    max_iterations = Keyword.get(opts, :max_iterations, 10)

    execute_loop(condition, body_builder, state, chain, 0, max_iterations)
  end

  defp execute_step({:parallel, builder_fns, _opts}, state, chain) do
    last_result = State.get(state, :_last_result)

    tasks =
      Enum.map(builder_fns, fn builder_fn ->
        Task.async(fn ->
          # Create a sub-chain from the builder
          sub_chain = builder_fn.(Chain.new(""))
          sub_state = State.merge(state, %{_last_result: last_result})

          case execute_steps(sub_chain.steps, sub_state, chain) do
            {:ok, result, _} -> result
            {:error, reason} -> {:error, reason}
          end
        end)
      end)

    results = Task.await_many(tasks, 30_000)
    {:ok, results, state}
  end

  defp execute_step({:execute_tools, _, _opts}, state, chain) do
    # Execute tool calls from the previous LLM response
    last_result = State.get(state, :_last_result)
    tools = Keyword.get(chain.options, :tools, [])

    case last_result do
      %{tool_calls: tool_calls} when is_list(tool_calls) and length(tool_calls) > 0 ->
        results = execute_tool_calls(tool_calls, tools)
        {:ok, results, state}

      _ ->
        # No tool calls, pass through
        {:ok, last_result, state}
    end
  end

  defp execute_step(step, state, chain) do
    # Delegate to the existing executor for other step types
    variables = State.to_variables(state)
    last_result = State.get(state, :_last_result, "")

    case Chainex.Chain.Executor.execute_single_step(step, last_result, chain, variables) do
      {:ok, result} ->
        {:ok, result, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_branch(chain_or_builder, state, _parent_chain, input) when is_function(chain_or_builder, 1) do
    # Builder function - call it with a new chain and execute
    sub_chain = chain_or_builder.(Chain.new(""))
    sub_state = State.merge(state, %{_last_result: input})

    case execute_steps(sub_chain.steps, sub_state, sub_chain) do
      {:ok, result, updated_state} ->
        {:ok, result, State.merge(state, updated_state.data)}

      error ->
        error
    end
  end

  defp execute_branch(%Chain{} = sub_chain, state, _parent_chain, input) do
    # Full chain - execute it
    sub_state = State.merge(state, %{_last_result: input})

    case execute_steps(sub_chain.steps, sub_state, sub_chain) do
      {:ok, result, updated_state} ->
        {:ok, result, State.merge(state, updated_state.data)}

      error ->
        error
    end
  end

  defp execute_branch(pass_through, state, _parent_chain, input) when is_function(pass_through, 1) do
    # Simple function like &(&1) - just apply it
    {:ok, pass_through.(input), state}
  end

  defp execute_loop(condition, body_builder, state, chain, iteration, max_iterations) do
    if iteration >= max_iterations do
      # Max iterations reached
      {:ok, State.get(state, :_last_result), state}
    else
      last_result = State.get(state, :_last_result)

      # Check condition
      should_continue =
        try do
          condition.(last_result, state.data)
        rescue
          _ -> false
        end

      if should_continue do
        # Execute loop body
        sub_chain = body_builder.(Chain.new(""))
        sub_state = State.merge(state, %{_last_result: last_result})

        case execute_steps(sub_chain.steps, sub_state, chain) do
          {:ok, result, updated_state} ->
            # Merge state and continue loop
            merged_state = State.merge(state, updated_state.data)
            merged_state = State.put(merged_state, :_last_result, result)
            execute_loop(condition, body_builder, merged_state, chain, iteration + 1, max_iterations)

          error ->
            error
        end
      else
        # Condition is false, exit loop
        {:ok, last_result, state}
      end
    end
  end

  defp execute_tool_calls(tool_calls, tools) do
    Enum.map(tool_calls, fn tool_call ->
      tool_name = tool_call["name"] || tool_call[:name]
      arguments = tool_call["arguments"] || tool_call[:arguments] || %{}

      tool = Enum.find(tools, fn t -> t.name == tool_name end)

      if tool do
        case Chainex.Tool.call(tool, arguments) do
          {:ok, result} -> %{tool: tool_name, result: result}
          {:error, reason} -> %{tool: tool_name, error: reason}
        end
      else
        %{tool: tool_name, error: "Tool not found"}
      end
    end)
  end

  defp persist_state(chain, state) do
    if chain.persist_to do
      Store.save(state.instance_id, state, persist_to: chain.persist_to)
    end
  end

  defp start_instance(instance_id, chain, state) do
    # Try to start under supervisor if available, otherwise start linked
    case Process.whereis(@supervisor) do
      nil ->
        # No supervisor, start linked
        GenServer.start_link(__MODULE__, {chain, state}, name: via(instance_id))

      _pid ->
        DynamicSupervisor.start_child(@supervisor, {__MODULE__, {chain, state, instance_id}})
    end
  end

  defp lookup(instance_id) do
    case Registry.lookup(@registry, instance_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp via(instance_id) do
    {:via, Registry, {@registry, instance_id}}
  end

  defp resume_from_store(instance_id, new_variables) do
    case Store.load(instance_id) do
      {:ok, state} ->
        # TODO: Implement restarting from stored state
        {:error, :not_implemented}

      {:error, _} = error ->
        error
    end
  end

  # Child spec for supervisor
  def child_spec({chain, state, instance_id}) do
    %{
      id: instance_id,
      start: {GenServer, :start_link, [__MODULE__, {chain, state}, [name: via(instance_id)]]},
      restart: :temporary
    }
  end
end
