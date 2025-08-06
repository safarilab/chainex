defmodule Chainex.Memory.Database do
  @moduledoc """
  Database persistence backend for Chainex Memory using Ecto

  Provides database storage for memory persistence by accepting an Ecto repo.
  This allows users to use any database supported by Ecto (PostgreSQL, MySQL, 
  SQLite, etc.) and manage their own database configuration and migrations.

  ## Usage

      # User defines their own repo
      defmodule MyApp.Repo do
        use Ecto.Repo,
          otp_app: :my_app,
          adapter: Ecto.Adapters.Postgres
      end

      # Pass repo to memory
      memory = Memory.new(:persistent, %{
        backend: :database,
        repo: MyApp.Repo,
        table: "chainex_memory"  # optional, defaults to "chainex_memory"
      })

  ## Database Schema

  The table should have the following structure:

      create table(:chainex_memory) do
        add :key, :text, primary_key: true
        add :value, :binary, null: false
        add :access_count, :integer, null: false, default: 0
        add :created_at, :bigint, null: false
        add :updated_at, :bigint, null: false  
        add :last_access, :bigint, null: false
      end

  Use `Chainex.Memory.Database.Migration` to generate the migration.
  """

  import Ecto.Query
  
  @type config :: %{
          repo: module(),
          table: String.t()
        }

  @default_table "chainex_memory"

  @doc """
  Validates the database configuration
  """
  @spec validate_config(map()) :: {:ok, config()} | {:error, atom()}
  def validate_config(%{repo: repo, table: table} = config) when is_atom(repo) and is_binary(table) do
    if Code.ensure_loaded?(repo) and function_exported?(repo, :__adapter__, 0) do
      {:ok, config}
    else
      {:error, :invalid_repo}
    end
  end

  def validate_config(%{repo: repo} = config) when is_atom(repo) do
    validate_config(Map.put(config, :table, @default_table))
  end

  def validate_config(_config) do
    {:error, :missing_repo}
  end

  @doc """
  Stores a key-value pair in the database
  """
  @spec store(config(), any(), any()) :: :ok | {:error, any()}
  def store(%{repo: repo, table: table}, key, value) do
    try do
      serialized_key = serialize_key(key)
      serialized_value = :erlang.term_to_binary(value, [:compressed])
      timestamp = :os.system_time(:second)

      # Use Ecto's conflict resolution - works across different adapters
      changeset_data = %{
        key: serialized_key,
        value: serialized_value,
        created_at: timestamp,
        updated_at: timestamp,
        access_count: 0,
        last_access: timestamp
      }

      result = repo.insert_all(
        table,
        [changeset_data],
        on_conflict: {:replace, [:value, :updated_at]},
        conflict_target: [:key]
      )

      case result do
        {_count, _} -> :ok
        error -> {:error, error}
      end
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  @doc """
  Retrieves a value by key from the database
  """
  @spec retrieve(config(), any()) :: {:ok, any()} | {:error, :not_found | any()}
  def retrieve(%{repo: repo, table: table}, key) do
    try do
      serialized_key = serialize_key(key)
      
      query = from t in table,
              where: t.key == ^serialized_key,
              select: t.value

      case repo.one(query) do
        nil ->
          {:error, :not_found}

        serialized_value ->
          value = :erlang.binary_to_term(serialized_value, [:safe])
          {:ok, value}
      end
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  @doc """
  Updates access statistics for a key
  """
  @spec update_access(config(), any()) :: :ok | {:error, any()}
  def update_access(%{repo: repo, table: table}, key) do
    try do
      serialized_key = serialize_key(key)
      timestamp = :os.system_time(:second)

      query = from t in table,
              where: t.key == ^serialized_key

      case repo.update_all(query, inc: [access_count: 1], set: [last_access: timestamp]) do
        {_count, _} -> :ok
        error -> {:error, error}
      end
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  @doc """
  Deletes a key from the database
  """
  @spec delete(config(), any()) :: :ok | {:error, any()}
  def delete(%{repo: repo, table: table}, key) do
    try do
      serialized_key = serialize_key(key)
      
      query = from t in table,
              where: t.key == ^serialized_key

      case repo.delete_all(query) do
        {_count, _} -> :ok
        error -> {:error, error}
      end
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  @doc """
  Lists all keys in the database
  """
  @spec keys(config()) :: {:ok, [any()]} | {:error, any()}
  def keys(%{repo: repo, table: table}) do
    try do
      query = from t in table,
              select: t.key

      keys = repo.all(query)
             |> Enum.map(&deserialize_key/1)

      {:ok, keys}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  @doc """
  Returns the number of entries in the database
  """
  @spec size(config()) :: {:ok, non_neg_integer()} | {:error, any()}
  def size(%{repo: repo, table: table}) do
    try do
      query = from t in table,
              select: count()

      count = repo.one(query) || 0
      {:ok, count}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  @doc """
  Clears all entries from the database
  """
  @spec clear(config()) :: :ok | {:error, any()}
  def clear(%{repo: repo, table: table}) do
    try do
      query = from t in table

      case repo.delete_all(query) do
        {_count, _} -> :ok
        error -> {:error, error}
      end
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  @doc """
  Gets access statistics for pruning
  """
  @spec get_access_stats(config()) :: {:ok, map()} | {:error, any()}
  def get_access_stats(%{repo: repo, table: table}) do
    try do
      query = from t in table,
              select: {t.key, t.created_at, t.access_count, t.last_access}

      rows = repo.all(query)

      stats = Enum.reduce(rows, %{access_count: %{}, last_access: %{}, creation_time: %{}}, 
        fn {serialized_key, created_at, access_count, last_access}, acc ->
          key = deserialize_key(serialized_key)

          %{
            acc
            | access_count: Map.put(acc.access_count, key, access_count),
              last_access: Map.put(acc.last_access, key, last_access),
              creation_time: Map.put(acc.creation_time, key, created_at)
          }
        end)

      {:ok, stats}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  @doc """
  Finds keys that match a pruning criteria
  """
  @spec find_keys_for_pruning(config(), :lru | :lfu | :ttl, integer(), integer()) ::
          {:ok, [any()]} | {:error, any()}
  def find_keys_for_pruning(%{repo: repo, table: table}, strategy, limit, ttl_cutoff \\ 0) do
    try do
      query = case strategy do
        :lru ->
          from t in table,
          order_by: [asc: t.last_access],
          limit: ^limit,
          select: t.key

        :lfu ->
          from t in table,
          order_by: [asc: t.access_count],
          limit: ^limit,
          select: t.key

        :ttl ->
          from t in table,
          where: t.created_at < ^ttl_cutoff,
          limit: ^limit,
          select: t.key
      end

      keys = repo.all(query)
             |> Enum.map(&deserialize_key/1)

      {:ok, keys}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  @doc """
  Checks if the required table exists and has the correct schema
  """
  @spec table_exists?(config()) :: boolean()
  def table_exists?(%{repo: repo, table: table}) do
    try do
      # Try a simple query to see if table exists
      # Use raw SQL since table name is dynamic
      case Ecto.Adapters.SQL.query(repo, "SELECT 1 FROM #{table} LIMIT 1", []) do
        {:ok, _} -> true
        {:error, _} -> false
      end
    catch
      _, _ -> false
    end
  end

  # Private helper functions

  # Key serialization: Store type info with keys to preserve original types
  defp serialize_key(key) when is_binary(key), do: "s:" <> key
  defp serialize_key(key) when is_atom(key), do: "a:" <> Atom.to_string(key)
  defp serialize_key(key), do: "t:" <> (:erlang.term_to_binary(key, [:compressed]) |> Base.encode64())

  defp deserialize_key("s:" <> key), do: key  # String key
  defp deserialize_key("a:" <> key), do: String.to_atom(key)  # Atom key
  defp deserialize_key("t:" <> encoded_key) do  # Term key
    case Base.decode64(encoded_key) do
      {:ok, binary} ->
        try do
          :erlang.binary_to_term(binary, [:safe])
        catch
          _, _ -> encoded_key
        end
      :error -> encoded_key
    end
  end
  defp deserialize_key(key), do: key  # Fallback for old format
end