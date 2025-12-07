defmodule Chainex.Chain.Store do
  @moduledoc """
  Behaviour for chain state persistence.

  State stores handle saving and loading chain execution state.
  This enables features like:
  - Pause/resume long-running chains
  - Persist state across application restarts
  - Query running chain instances

  ## Built-in Implementations

  - `Chainex.Chain.Store.ETS` - In-memory storage (fast, non-persistent)
  - `Chainex.Chain.Store.Database` - Ecto-based storage (persistent)

  ## Custom Implementations

  You can implement this behaviour for custom storage backends:

      defmodule MyApp.RedisStore do
        @behaviour Chainex.Chain.Store

        @impl true
        def save(instance_id, state) do
          # Save to Redis
        end

        # ... implement other callbacks
      end
  """

  alias Chainex.Chain.State

  @doc """
  Saves the state for a given instance.
  """
  @callback save(instance_id :: String.t(), state :: State.t()) ::
              :ok | {:error, term()}

  @doc """
  Loads the state for a given instance.
  """
  @callback load(instance_id :: String.t()) ::
              {:ok, State.t()} | {:error, :not_found} | {:error, term()}

  @doc """
  Deletes the state for a given instance.
  """
  @callback delete(instance_id :: String.t()) ::
              :ok | {:error, term()}

  @doc """
  Lists all states, optionally filtered by session_id.
  """
  @callback list(opts :: keyword()) ::
              {:ok, [State.t()]} | {:error, term()}

  @doc """
  Updates the state for a given instance.
  This is an atomic read-modify-write operation.
  """
  @callback update(instance_id :: String.t(), update_fn :: (State.t() -> State.t())) ::
              {:ok, State.t()} | {:error, :not_found} | {:error, term()}

  @doc """
  Checks if a state exists for the given instance.
  """
  @callback exists?(instance_id :: String.t()) :: boolean()

  # Convenience functions that delegate to the configured store

  @doc """
  Gets the configured store module.
  Defaults to ETS store.
  """
  @spec get_store(keyword()) :: module()
  def get_store(opts \\ []) do
    case Keyword.get(opts, :store) || Keyword.get(opts, :persist_to) do
      nil -> Chainex.Chain.Store.ETS
      :ets -> Chainex.Chain.Store.ETS
      :database -> Chainex.Chain.Store.Database
      module when is_atom(module) -> module
    end
  end

  @doc """
  Saves state using the configured store.
  """
  @spec save(String.t(), State.t(), keyword()) :: :ok | {:error, term()}
  def save(instance_id, state, opts \\ []) do
    store = get_store(opts)
    store.save(instance_id, state)
  end

  @doc """
  Loads state using the configured store.
  """
  @spec load(String.t(), keyword()) :: {:ok, State.t()} | {:error, term()}
  def load(instance_id, opts \\ []) do
    store = get_store(opts)
    store.load(instance_id)
  end

  @doc """
  Deletes state using the configured store.
  """
  @spec delete(String.t(), keyword()) :: :ok | {:error, term()}
  def delete(instance_id, opts \\ []) do
    store = get_store(opts)
    store.delete(instance_id)
  end

  @doc """
  Lists states using the configured store.
  """
  @spec list(keyword()) :: {:ok, [State.t()]} | {:error, term()}
  def list(opts \\ []) do
    store = get_store(opts)
    store.list(opts)
  end

  @doc """
  Updates state using the configured store.
  """
  @spec update(String.t(), (State.t() -> State.t()), keyword()) ::
          {:ok, State.t()} | {:error, term()}
  def update(instance_id, update_fn, opts \\ []) do
    store = get_store(opts)
    store.update(instance_id, update_fn)
  end

  @doc """
  Checks if state exists using the configured store.
  """
  @spec exists?(String.t(), keyword()) :: boolean()
  def exists?(instance_id, opts \\ []) do
    store = get_store(opts)
    store.exists?(instance_id)
  end
end
