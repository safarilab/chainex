defmodule Chainex.Memory do
  @moduledoc """
  Memory storage and retrieval for Chainex workflows

  Provides different memory types for storing and retrieving data across
  chain executions. Supports various storage backends including in-memory
  buffers, persistent storage, and conversation history.
  """

  defstruct [:type, :storage, :options, :pruning_config, :access_stats]

  @type memory_type :: :buffer | :persistent | :conversation | :vector
  @type storage :: map() | any()
  @type pruning_strategy :: :lru | :lfu | :ttl | :hybrid
  @type pruning_config :: %{
          max_size: non_neg_integer() | :unlimited,
          ttl_seconds: non_neg_integer() | :unlimited,
          prune_strategy: pruning_strategy(),
          prune_percentage: float(),
          auto_prune: boolean()
        }
  @type access_stats :: %{
          access_count: %{any() => non_neg_integer()},
          last_access: %{any() => non_neg_integer()},
          creation_time: %{any() => non_neg_integer()}
        }
  @type t :: %__MODULE__{
          type: memory_type(),
          storage: storage(),
          options: map(),
          pruning_config: pruning_config(),
          access_stats: access_stats()
        }

  @doc """
  Creates a new memory instance with the specified type

  ## Memory Types

  - `:buffer` - Simple in-memory key-value storage
  - `:persistent` - File-based persistent storage  
  - `:conversation` - Conversation history with message ordering
  - `:vector` - Vector-based semantic storage (future)

  ## Examples

      iex> memory = Memory.new(:buffer)
      iex> memory.type
      :buffer

      iex> memory = Memory.new(:persistent, %{file_path: "/tmp/memory.dat"})
      iex> memory.options.file_path
      "/tmp/memory.dat"
  """
  @spec new(memory_type(), map()) :: t()
  def new(type, options \\ %{}) when type in [:buffer, :persistent, :conversation, :vector] do
    storage = initialize_storage(type, options)
    pruning_config = initialize_pruning_config(options)
    access_stats = initialize_access_stats()

    %__MODULE__{
      type: type,
      storage: storage,
      options: options,
      pruning_config: pruning_config,
      access_stats: access_stats
    }
  end

  @doc """
  Stores a value in memory with the given key

  ## Examples

      iex> memory = Memory.new(:buffer)
      iex> updated = Memory.store(memory, :name, "Alice")
      iex> Memory.retrieve(updated, :name)
      {:ok, "Alice"}

      iex> memory = Memory.new(:conversation)
      iex> updated = Memory.store(memory, :message, %{role: "user", content: "Hello"})
      iex> {:ok, message} = Memory.retrieve(updated, :message)
      iex> message.content
      "Hello"
  """
  @spec store(t(), any(), any()) :: t()
  def store(%__MODULE__{type: :buffer, storage: storage} = memory, key, value) do
    new_storage = Map.put(storage, key, value)
    updated_memory = %{memory | storage: new_storage}
    
    updated_memory
    |> update_creation_stats(key)
    |> maybe_auto_prune()
  end

  def store(%__MODULE__{type: :conversation, storage: storage} = memory, key, value) do
    timestamp = :os.system_time(:millisecond)

    entry = %{
      key: key,
      value: value,
      timestamp: timestamp,
      id: generate_id()
    }

    new_storage = [entry | storage]
    updated_memory = %{memory | storage: new_storage}
    
    updated_memory
    |> update_creation_stats(key)
    |> maybe_auto_prune()
  end

  def store(
        %__MODULE__{type: :persistent, storage: storage, options: options} = memory,
        key,
        value
      ) do
    # Update in-memory storage first
    new_storage = Map.put(storage, key, value)
    updated_memory = %{memory | storage: new_storage}

    # Persist to file
    final_memory = case persist_to_file(new_storage, options) do
      :ok ->
        updated_memory

      {:error, _reason} ->
        # On file write error, still return updated memory (data exists in memory)
        # This allows the system to continue working even if persistence fails
        updated_memory
    end
    
    final_memory
    |> update_creation_stats(key)
    |> maybe_auto_prune()
  end

  def store(%__MODULE__{type: :vector} = memory, key, value) do
    # Vector storage would involve embeddings and similarity search
    # For now, treating it like buffer storage
    store(%{memory | type: :buffer}, key, value)
  end

  @doc """
  Retrieves a value from memory by key

  ## Examples

      iex> memory = Memory.new(:buffer) |> Memory.store(:age, 25)
      iex> Memory.retrieve(memory, :age)
      {:ok, 25}

      iex> memory = Memory.new(:buffer)
      iex> Memory.retrieve(memory, :missing)
      {:error, :not_found}
  """
  @spec retrieve(t(), any()) :: {:ok, any()} | {:error, atom()}
  def retrieve(%__MODULE__{type: :buffer, storage: storage}, key) do
    if Map.has_key?(storage, key) do
      {:ok, Map.get(storage, key)}
    else
      {:error, :not_found}
    end
  end

  def retrieve(%__MODULE__{type: :conversation, storage: storage}, key) do
    case Enum.find(storage, fn entry -> entry.key == key end) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry.value}
    end
  end

  def retrieve(%__MODULE__{type: :persistent, storage: storage, options: options}, key) do
    # First try in-memory storage for performance
    case Map.get(storage, key) do
      nil ->
        # If not in memory, try to load from file and check again
        case load_from_file(options) do
          {:ok, file_storage} ->
            case Map.get(file_storage, key) do
              nil -> {:error, :not_found}
              value -> {:ok, value}
            end

          {:error, _reason} ->
            {:error, :not_found}
        end

      value ->
        {:ok, value}
    end
  end

  def retrieve(%__MODULE__{type: :vector} = memory, key) do
    # Vector retrieval would involve similarity search
    # For now, treating it like buffer storage
    retrieve(%{memory | type: :buffer}, key)
  end

  @doc """
  Lists all keys stored in memory

  ## Examples

      iex> memory = Memory.new(:buffer)
      iex> memory = memory |> Memory.store(:a, 1) |> Memory.store(:b, 2)
      iex> keys = Memory.keys(memory)
      iex> Enum.sort(keys)
      [:a, :b]
  """
  @spec keys(t()) :: [any()]
  def keys(%__MODULE__{type: :buffer, storage: storage}) do
    Map.keys(storage)
  end

  def keys(%__MODULE__{type: :conversation, storage: storage}) do
    storage
    |> Enum.map(& &1.key)
    |> Enum.uniq()
  end

  def keys(%__MODULE__{type: :persistent, storage: storage, options: options}) do
    # Combine in-memory keys with file keys
    memory_keys = Map.keys(storage)

    case load_from_file(options) do
      {:ok, file_storage} ->
        file_keys = Map.keys(file_storage)
        (memory_keys ++ file_keys) |> Enum.uniq()

      {:error, _reason} ->
        memory_keys
    end
  end

  def keys(%__MODULE__{type: :vector} = memory) do
    keys(%{memory | type: :buffer})
  end

  @doc """
  Returns the number of items stored in memory

  ## Examples

      iex> memory = Memory.new(:buffer)
      iex> Memory.size(memory)
      0

      iex> memory = Memory.new(:buffer) |> Memory.store(:key, "value")
      iex> Memory.size(memory)
      1
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{type: :buffer, storage: storage}) do
    map_size(storage)
  end

  def size(%__MODULE__{type: :conversation, storage: storage}) do
    length(storage)
  end

  def size(%__MODULE__{type: :persistent, storage: storage, options: options}) do
    # Count unique keys from both memory and file
    memory_size = map_size(storage)

    case load_from_file(options) do
      {:ok, file_storage} ->
        # Count unique keys across both storages
        all_keys = Map.keys(storage) ++ Map.keys(file_storage)
        length(Enum.uniq(all_keys))

      {:error, _reason} ->
        memory_size
    end
  end

  def size(%__MODULE__{type: :vector} = memory) do
    size(%{memory | type: :buffer})
  end

  @doc """
  Clears all data from memory

  ## Examples

      iex> memory = Memory.new(:buffer) |> Memory.store(:key, "value")
      iex> Memory.size(memory)
      1
      iex> cleared = Memory.clear(memory)
      iex> Memory.size(cleared)
      0
  """
  @spec clear(t()) :: t()
  def clear(%__MODULE__{type: type} = memory) do
    new_storage = initialize_storage(type, memory.options)
    %{memory | storage: new_storage}
  end

  @doc """
  Deletes a specific key from memory

  ## Examples

      iex> memory = Memory.new(:buffer) |> Memory.store(:temp, "data")
      iex> updated = Memory.delete(memory, :temp)
      iex> Memory.retrieve(updated, :temp)
      {:error, :not_found}
  """
  @spec delete(t(), any()) :: t()
  def delete(%__MODULE__{type: :buffer, storage: storage} = memory, key) do
    new_storage = Map.delete(storage, key)
    updated_memory = %{memory | storage: new_storage}
    clean_access_stats(updated_memory, key)
  end

  def delete(%__MODULE__{type: :conversation, storage: storage} = memory, key) do
    new_storage = Enum.reject(storage, fn entry -> entry.key == key end)
    updated_memory = %{memory | storage: new_storage}
    clean_access_stats(updated_memory, key)
  end

  def delete(%__MODULE__{type: :persistent, storage: storage, options: options} = memory, key) do
    # Remove from in-memory storage
    new_storage = Map.delete(storage, key)
    updated_memory = %{memory | storage: new_storage}

    # Update persistent file
    final_memory = case persist_to_file(new_storage, options) do
      :ok ->
        updated_memory

      {:error, _reason} ->
        # On file write error, still return updated memory (data deleted from memory)
        # This allows the system to continue working even if persistence fails
        updated_memory
    end
    
    clean_access_stats(final_memory, key)
  end

  def delete(%__MODULE__{type: :vector} = memory, key) do
    delete(%{memory | type: :buffer}, key)
  end

  @doc """
  Manually triggers pruning based on the configured strategy

  ## Examples

      iex> memory = Memory.new(:buffer, %{max_size: 10, prune_strategy: :lru})
      iex> pruned = Memory.prune(memory)
      iex> Memory.size(pruned) <= 10
      true
  """
  @spec prune(t()) :: t()
  def prune(%__MODULE__{pruning_config: %{prune_strategy: strategy}} = memory) do
    case should_prune?(memory) do
      true -> do_prune(memory, strategy)
      false -> memory
    end
  end

  @doc """
  Forces pruning regardless of current size or conditions

  ## Examples

      iex> memory = Memory.new(:buffer, %{max_size: 100})
      iex> large_memory = Enum.reduce(1..10, memory, fn i, acc -> Memory.store(acc, String.to_atom("key_" <> Integer.to_string(i)), "value") end)
      iex> pruned = Memory.force_prune(large_memory, :lru)
      iex> Memory.size(pruned) < Memory.size(large_memory)
      true
  """
  @spec force_prune(t(), pruning_strategy() | nil) :: t()
  def force_prune(memory, strategy \\ nil) do
    prune_strategy = strategy || memory.pruning_config.prune_strategy
    do_prune(memory, prune_strategy)
  end

  @doc """
  Removes expired entries based on TTL configuration

  ## Examples

      iex> memory = Memory.new(:buffer, %{ttl_seconds: 3600}) 
      iex> _cleaned = Memory.cleanup_expired(memory)
  """
  @spec cleanup_expired(t()) :: t()
  def cleanup_expired(%__MODULE__{pruning_config: %{ttl_seconds: :unlimited}} = memory) do
    memory
  end

  def cleanup_expired(%__MODULE__{pruning_config: %{ttl_seconds: ttl}} = memory) do
    current_time = :os.system_time(:second)
    expired_keys = find_expired_keys(memory, current_time, ttl)

    Enum.reduce(expired_keys, memory, fn key, acc ->
      delete(acc, key)
    end)
  end

  @doc """
  Retrieves a value and updates access statistics for smart pruning

  Returns {updated_memory, result} tuple where result is the same as retrieve/2

  ## Examples

      iex> memory = Memory.new(:buffer, %{max_size: 10})
      iex> memory = Memory.store(memory, :key, "value")  
      iex> {_updated_memory, {:ok, value}} = Memory.get_and_track(memory, :key)
      iex> value
      "value"
  """
  @spec get_and_track(t(), any()) :: {t(), {:ok, any()} | {:error, atom()}}
  def get_and_track(memory, key) do
    result = retrieve(memory, key)
    
    case result do
      {:ok, _value} ->
        updated_memory = update_access_stats(memory, key)
        {updated_memory, result}
      
      {:error, _reason} ->
        {memory, result}
    end
  end

  # Private helper functions

  defp initialize_storage(:buffer, _options), do: %{}
  defp initialize_storage(:conversation, _options), do: []

  defp initialize_storage(:persistent, options) do
    # Try to load existing data from file, fallback to empty map
    case load_from_file(options) do
      {:ok, storage} -> storage
      {:error, _reason} -> %{}
    end
  end

  defp initialize_storage(:vector, _options), do: %{}

  defp generate_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16()
    |> String.downcase()
  end

  # File I/O helper functions for persistent storage

  defp persist_to_file(storage, %{file_path: file_path}) when is_binary(file_path) do
    try do
      # Ensure directory exists
      file_path |> Path.dirname() |> File.mkdir_p!()

      # Serialize data to binary format
      data = :erlang.term_to_binary(storage, [:compressed])

      # Write to file atomically (write to temp file, then rename)
      temp_path = file_path <> ".tmp"

      case File.write(temp_path, data) do
        :ok ->
          case File.rename(temp_path, file_path) do
            :ok ->
              :ok

            {:error, reason} ->
              File.rm(temp_path)
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e -> {:error, e}
    end
  end

  defp persist_to_file(_storage, _options) do
    {:error, :no_file_path}
  end

  defp load_from_file(%{file_path: file_path}) when is_binary(file_path) do
    case File.read(file_path) do
      {:ok, data} ->
        try do
          storage = :erlang.binary_to_term(data, [:safe])
          {:ok, storage}
        rescue
          _ -> {:error, :corrupt_file}
        end

      # File doesn't exist yet, return empty storage
      {:error, :enoent} ->
        {:ok, %{}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_from_file(_options) do
    {:error, :no_file_path}
  end

  # Pruning helper functions

  defp initialize_pruning_config(options) do
    %{
      max_size: Map.get(options, :max_size, :unlimited),
      ttl_seconds: Map.get(options, :ttl_seconds, :unlimited),
      prune_strategy: Map.get(options, :prune_strategy, :lru),
      prune_percentage: Map.get(options, :prune_percentage, 0.2),
      auto_prune: Map.get(options, :auto_prune, true)
    }
  end

  defp initialize_access_stats do
    %{
      access_count: %{},
      last_access: %{},
      creation_time: %{}
    }
  end

  defp update_creation_stats(%__MODULE__{access_stats: stats} = memory, key) do
    current_time = :os.system_time(:second)
    
    updated_stats = %{
      stats
      | creation_time: Map.put(stats.creation_time, key, current_time),
        access_count: Map.put_new(stats.access_count, key, 0)
    }
    
    %{memory | access_stats: updated_stats}
  end

  defp update_access_stats(%__MODULE__{access_stats: stats} = memory, key) do
    current_time = :os.system_time(:second)
    current_count = Map.get(stats.access_count, key, 0)
    
    updated_stats = %{
      stats
      | access_count: Map.put(stats.access_count, key, current_count + 1),
        last_access: Map.put(stats.last_access, key, current_time)
    }
    
    %{memory | access_stats: updated_stats}
  end

  defp maybe_auto_prune(%__MODULE__{pruning_config: %{auto_prune: false}} = memory), do: memory
  defp maybe_auto_prune(%__MODULE__{pruning_config: %{auto_prune: true}} = memory) do
    case should_prune?(memory) do
      true -> do_prune(memory, memory.pruning_config.prune_strategy)
      false -> memory
    end
  end

  defp should_prune?(%__MODULE__{pruning_config: %{max_size: :unlimited}}), do: false
  defp should_prune?(%__MODULE__{pruning_config: %{max_size: max_size}} = memory) do
    size(memory) > max_size
  end

  defp do_prune(memory, strategy) do
    case strategy do
      :lru -> prune_lru(memory)
      :lfu -> prune_lfu(memory)
      :ttl -> cleanup_expired(memory)
      :hybrid -> prune_hybrid(memory)
    end
  end

  defp prune_lru(%__MODULE__{pruning_config: %{prune_percentage: percentage}} = memory) do
    current_size = size(memory)
    target_removals = max(1, trunc(current_size * percentage))
    
    # Get keys sorted by last access time (oldest first)
    # Use creation time as fallback for items never accessed
    all_keys = keys(memory)
    
    keys_to_remove = 
      all_keys
      |> Enum.sort_by(fn key ->
        # Use last_access if available, otherwise creation_time
        Map.get(memory.access_stats.last_access, key) ||
        Map.get(memory.access_stats.creation_time, key, 0)
      end)
      |> Enum.take(target_removals)
    
    remove_keys(memory, keys_to_remove)
  end

  defp prune_lfu(%__MODULE__{pruning_config: %{prune_percentage: percentage}} = memory) do
    current_size = size(memory)
    target_removals = max(1, trunc(current_size * percentage))
    
    # Get all keys and sort by access count (least used first)
    all_keys = keys(memory)
    
    keys_to_remove = 
      all_keys
      |> Enum.sort_by(fn key ->
        Map.get(memory.access_stats.access_count, key, 0)
      end)
      |> Enum.take(target_removals)
    
    remove_keys(memory, keys_to_remove)
  end

  defp prune_hybrid(memory) do
    memory
    |> cleanup_expired()
    |> maybe_prune_by_access()
  end

  defp maybe_prune_by_access(%__MODULE__{pruning_config: %{max_size: max_size}} = memory) do
    if size(memory) > max_size do
      prune_lru(memory)
    else
      memory
    end
  end

  defp find_expired_keys(memory, current_time, ttl_seconds) do
    cutoff_time = current_time - ttl_seconds
    
    memory.access_stats.creation_time
    |> Enum.filter(fn {_key, creation_time} -> creation_time < cutoff_time end)
    |> Enum.map(fn {key, _time} -> key end)
  end

  defp remove_keys(memory, keys) do
    Enum.reduce(keys, memory, fn key, acc ->
      delete(acc, key)
    end)
  end

  defp clean_access_stats(%__MODULE__{access_stats: stats} = memory, key) do
    updated_stats = %{
      stats
      | access_count: Map.delete(stats.access_count, key),
        last_access: Map.delete(stats.last_access, key),
        creation_time: Map.delete(stats.creation_time, key)
    }
    
    %{memory | access_stats: updated_stats}
  end
end
