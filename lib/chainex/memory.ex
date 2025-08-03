defmodule Chainex.Memory do
  @moduledoc """
  Memory storage and retrieval for Chainex workflows

  Provides different memory types for storing and retrieving data across
  chain executions. Supports various storage backends including in-memory
  buffers, persistent storage, and conversation history.
  """

  defstruct [:type, :storage, :options]

  @type memory_type :: :buffer | :persistent | :conversation | :vector
  @type storage :: map() | any()
  @type t :: %__MODULE__{
          type: memory_type(),
          storage: storage(),
          options: map()
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
    
    %__MODULE__{
      type: type,
      storage: storage,
      options: options
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
    %{memory | storage: new_storage}
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
    %{memory | storage: new_storage}
  end

  def store(%__MODULE__{type: :persistent, storage: storage, options: options} = memory, key, value) do
    # Update in-memory storage first
    new_storage = Map.put(storage, key, value)
    updated_memory = %{memory | storage: new_storage}
    
    # Persist to file
    case persist_to_file(new_storage, options) do
      :ok -> updated_memory
      {:error, _reason} -> 
        # On file write error, still return updated memory (data exists in memory)
        # This allows the system to continue working even if persistence fails
        updated_memory
    end
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
          {:error, _reason} -> {:error, :not_found}
        end
      value -> {:ok, value}
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
    %{memory | storage: new_storage}
  end

  def delete(%__MODULE__{type: :conversation, storage: storage} = memory, key) do
    new_storage = Enum.reject(storage, fn entry -> entry.key == key end)
    %{memory | storage: new_storage}
  end

  def delete(%__MODULE__{type: :persistent, storage: storage, options: options} = memory, key) do
    # Remove from in-memory storage
    new_storage = Map.delete(storage, key)
    updated_memory = %{memory | storage: new_storage}
    
    # Update persistent file
    case persist_to_file(new_storage, options) do
      :ok -> updated_memory
      {:error, _reason} -> 
        # On file write error, still return updated memory (data deleted from memory)
        # This allows the system to continue working even if persistence fails
        updated_memory
    end
  end

  def delete(%__MODULE__{type: :vector} = memory, key) do 
    delete(%{memory | type: :buffer}, key)
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
            :ok -> :ok
            {:error, reason} -> 
              File.rm(temp_path)
              {:error, reason}
          end
        {:error, reason} -> {:error, reason}
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
      {:error, :enoent} -> {:ok, %{}}  # File doesn't exist yet, return empty storage
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_from_file(_options) do
    {:error, :no_file_path}
  end
end