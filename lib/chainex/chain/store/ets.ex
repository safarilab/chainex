defmodule Chainex.Chain.Store.ETS do
  @moduledoc """
  ETS-based state storage adapter.

  This is the default storage backend. It provides fast in-memory storage
  but state is lost when the application restarts.

  ## Features

  - Fast read/write operations
  - No external dependencies
  - Automatic table creation
  - Session-based filtering

  ## Usage

      # Implicit (default)
      chain
      |> Chain.persist_to(:ets)
      |> Chain.run_async(vars)

      # Explicit
      Chainex.Chain.Store.ETS.save(instance_id, state)
  """

  @behaviour Chainex.Chain.Store

  alias Chainex.Chain.State

  @table_name :chainex_chain_state

  @doc """
  Ensures the ETS table exists.
  Called automatically when needed.
  """
  @spec ensure_table() :: :ok
  def ensure_table do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
        :ok

      _tid ->
        :ok
    end
  end

  @impl true
  def save(instance_id, %State{} = state) do
    ensure_table()

    case :ets.insert(@table_name, {instance_id, state}) do
      true -> :ok
      _ -> {:error, :insert_failed}
    end
  end

  @impl true
  def load(instance_id) do
    ensure_table()

    case :ets.lookup(@table_name, instance_id) do
      [{^instance_id, state}] -> {:ok, state}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def delete(instance_id) do
    ensure_table()
    :ets.delete(@table_name, instance_id)
    :ok
  end

  @impl true
  def list(opts \\ []) do
    ensure_table()
    session_id = Keyword.get(opts, :session_id)
    status = Keyword.get(opts, :status)

    states =
      :ets.tab2list(@table_name)
      |> Enum.map(fn {_id, state} -> state end)
      |> filter_by_session(session_id)
      |> filter_by_status(status)

    {:ok, states}
  end

  @impl true
  def update(instance_id, update_fn) when is_function(update_fn, 1) do
    ensure_table()

    case load(instance_id) do
      {:ok, state} ->
        updated_state = update_fn.(state)
        :ok = save(instance_id, updated_state)
        {:ok, updated_state}

      {:error, :not_found} = error ->
        error

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def exists?(instance_id) do
    ensure_table()

    case :ets.lookup(@table_name, instance_id) do
      [{^instance_id, _}] -> true
      [] -> false
    end
  end

  @doc """
  Clears all states from the store.
  Useful for testing.
  """
  @spec clear() :: :ok
  def clear do
    ensure_table()
    :ets.delete_all_objects(@table_name)
    :ok
  end

  @doc """
  Returns the count of stored states.
  """
  @spec count() :: non_neg_integer()
  def count do
    ensure_table()
    :ets.info(@table_name, :size)
  end

  @doc """
  Lists states by status.
  """
  @spec list_by_status(State.status()) :: {:ok, [State.t()]}
  def list_by_status(status) do
    list(status: status)
  end

  @doc """
  Lists states by session_id.
  """
  @spec list_by_session(String.t()) :: {:ok, [State.t()]}
  def list_by_session(session_id) do
    list(session_id: session_id)
  end

  @doc """
  Gets all running states.
  """
  @spec running() :: {:ok, [State.t()]}
  def running do
    list_by_status(:running)
  end

  @doc """
  Gets all paused states.
  """
  @spec paused() :: {:ok, [State.t()]}
  def paused do
    list_by_status(:paused)
  end

  # Private helpers

  defp filter_by_session(states, nil), do: states

  defp filter_by_session(states, session_id) do
    Enum.filter(states, fn state -> state.session_id == session_id end)
  end

  defp filter_by_status(states, nil), do: states

  defp filter_by_status(states, status) do
    Enum.filter(states, fn state -> state.status == status end)
  end
end
