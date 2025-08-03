defmodule Chainex.Context do
  @moduledoc """
  Execution context management for Chainex workflows

  Provides a simple data container for variables, metadata, memory references,
  and session tracking across chain and graph executions.
  """

  defstruct [:variables, :memory, :metadata, :session_id]

  @type t :: %__MODULE__{
          variables: map(),
          memory: Chainex.Memory.t() | nil,
          metadata: map(),
          session_id: String.t()
        }

  @doc """
  Creates a new context with optional initial variables and memory

  ## Examples

      iex> context = Context.new()
      iex> context.variables
      %{}

      iex> context = Context.new(%{user: "alice"})
      iex> context.variables.user
      "alice"
  """
  @spec new(map(), any()) :: t()
  def new(variables \\ %{}, memory \\ nil) do
    %__MODULE__{
      variables: ensure_map(variables),
      memory: memory,
      metadata: %{},
      session_id: generate_session_id()
    }
  end

  @doc """
  Stores a variable in the context

  ## Examples

      iex> context = Context.new()
      iex> updated = Context.put(context, :name, "Bob")
      iex> updated.variables.name
      "Bob"
  """
  @spec put(t(), any(), any()) :: t()
  def put(%__MODULE__{} = context, key, value) do
    %{context | variables: Map.put(context.variables, key, value)}
  end

  @doc """
  Retrieves a variable from the context with optional default

  ## Examples

      iex> context = Context.new(%{age: 25})
      iex> Context.get(context, :age)
      25

      iex> context = Context.new(%{age: 25})
      iex> Context.get(context, :missing, "default")
      "default"
  """
  @spec get(t(), any(), any()) :: any()
  def get(%__MODULE__{} = context, key, default \\ nil) do
    Map.get(context.variables, key, default)
  end

  @doc """
  Merges new variables into the context

  ## Examples

      iex> context = Context.new(%{a: 1})
      iex> merged = Context.merge_vars(context, %{b: 2, c: 3})
      iex> merged.variables
      %{a: 1, b: 2, c: 3}
  """
  @spec merge_vars(t(), map() | keyword()) :: t()
  def merge_vars(%__MODULE__{} = context, new_vars) when is_map(new_vars) do
    %{context | variables: Map.merge(context.variables, new_vars)}
  end

  def merge_vars(%__MODULE__{} = context, new_vars) when is_list(new_vars) do
    merge_vars(context, Enum.into(new_vars, %{}))
  end

  @doc """
  Stores metadata in the context

  ## Examples

      iex> context = Context.new()
      iex> updated = Context.put_metadata(context, :step, 1)
      iex> updated.metadata.step
      1
  """
  @spec put_metadata(t(), any(), any()) :: t()
  def put_metadata(%__MODULE__{} = context, key, value) do
    %{context | metadata: Map.put(context.metadata, key, value)}
  end

  @doc """
  Retrieves metadata from the context

  ## Examples

      iex> context = Context.new() |> Context.put_metadata(:retries, 3)
      iex> Context.get_metadata(context, :retries)
      3

      iex> context = Context.new() |> Context.put_metadata(:retries, 3)
      iex> Context.get_metadata(context, :missing, 0)
      0
  """
  @spec get_metadata(t(), any(), any()) :: any()
  def get_metadata(%__MODULE__{} = context, key, default \\ nil) do
    Map.get(context.metadata, key, default)
  end

  @doc """
  Stores data in the associated memory (if present)

  ## Examples

      iex> memory = Chainex.Memory.new(:buffer)
      iex> context = Context.new(%{}, memory)
      iex> updated = Context.store_in_memory(context, :key, "value")
      iex> updated.memory.storage[:key]
      "value"
  """
  @spec store_in_memory(t(), any(), any()) :: t()
  def store_in_memory(%__MODULE__{memory: nil} = context, _key, _value) do
    context
  end

  def store_in_memory(%__MODULE__{memory: memory} = context, key, value) do
    new_memory = Chainex.Memory.store(memory, key, value)
    %{context | memory: new_memory}
  end

  @doc """
  Retrieves data from the associated memory

  ## Examples

      iex> memory = Chainex.Memory.new(:buffer)
      iex> context = Context.new(%{}, memory) |> Context.store_in_memory(:key, "value")
      iex> Context.get_from_memory(context, :key)
      {:ok, "value"}

      iex> context_no_memory = Context.new()
      iex> Context.get_from_memory(context_no_memory, :key)
      {:error, :no_memory}
  """
  @spec get_from_memory(t(), any()) :: {:ok, any()} | {:error, atom()}
  def get_from_memory(%__MODULE__{memory: nil}, _key) do
    {:error, :no_memory}
  end

  def get_from_memory(%__MODULE__{memory: memory}, key) do
    Chainex.Memory.retrieve(memory, key)
  end

  @doc """
  Returns all variable keys in the context

  ## Examples

      iex> context = Context.new(%{name: "Alice", age: 30})
      iex> Context.keys(context)
      [:name, :age]
  """
  @spec keys(t()) :: [any()]
  def keys(%__MODULE__{} = context) do
    Map.keys(context.variables)
  end

  @doc """
  Returns the number of variables in the context

  ## Examples

      iex> context = Context.new(%{a: 1, b: 2})
      iex> Context.size(context)
      2
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = context) do
    map_size(context.variables)
  end

  @doc """
  Converts context variables to a map

  ## Examples

      iex> context = Context.new(%{user: "bob"})
      iex> Context.to_map(context)
      %{user: "bob"}
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = context) do
    context.variables
  end

  # Private helper functions

  defp ensure_map(variables) when is_map(variables), do: variables
  defp ensure_map(variables) when is_list(variables), do: Enum.into(variables, %{})
  defp ensure_map(_), do: %{}

  defp generate_session_id() do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16()
    |> String.downcase()
  end
end
