defmodule Chainex.ContextTest do
  use ExUnit.Case, async: true
  alias Chainex.Context
  doctest Chainex.Context

  describe "new/2" do
    test "creates context with empty variables by default" do
      context = Context.new()

      assert context.variables == %{}
      assert context.metadata == %{}
      assert context.memory == nil
      assert is_binary(context.session_id)
      assert String.length(context.session_id) == 32
    end

    test "creates context with initial variables map" do
      variables = %{name: "Alice", age: 30}
      context = Context.new(variables)

      assert context.variables == variables
    end

    test "creates context with initial variables keyword list" do
      variables = [name: "Bob", city: "NYC"]
      context = Context.new(variables)

      assert context.variables == %{name: "Bob", city: "NYC"}
    end

    test "creates context with memory" do
      memory = %{type: :test}
      context = Context.new(%{}, memory)

      assert context.memory == memory
    end

    test "generates unique session IDs" do
      context1 = Context.new()
      context2 = Context.new()

      assert context1.session_id != context2.session_id
    end

    test "handles invalid variables gracefully" do
      context = Context.new("invalid")
      assert context.variables == %{}
    end
  end

  describe "put/3 and get/3" do
    test "stores and retrieves variables" do
      context = Context.new()

      updated = Context.put(context, :name, "Charlie")
      assert Context.get(updated, :name) == "Charlie"
    end

    test "returns default value for missing keys" do
      context = Context.new()

      assert Context.get(context, :missing) == nil
      assert Context.get(context, :missing, "default") == "default"
    end

    test "overwrites existing variables" do
      context = Context.new(%{count: 1})

      updated = Context.put(context, :count, 5)
      assert Context.get(updated, :count) == 5
    end

    test "handles different data types" do
      context = Context.new()

      updated =
        context
        |> Context.put(:string, "text")
        |> Context.put(:number, 42)
        |> Context.put(:list, [1, 2, 3])
        |> Context.put(:map, %{nested: true})

      assert Context.get(updated, :string) == "text"
      assert Context.get(updated, :number) == 42
      assert Context.get(updated, :list) == [1, 2, 3]
      assert Context.get(updated, :map) == %{nested: true}
    end
  end

  describe "merge_vars/2" do
    test "merges map variables" do
      context = Context.new(%{a: 1, b: 2})
      new_vars = %{b: 20, c: 3}

      merged = Context.merge_vars(context, new_vars)

      assert merged.variables == %{a: 1, b: 20, c: 3}
    end

    test "merges keyword list variables" do
      context = Context.new(%{x: 10})
      new_vars = [y: 20, z: 30]

      merged = Context.merge_vars(context, new_vars)

      assert merged.variables == %{x: 10, y: 20, z: 30}
    end

    test "preserves original context structure" do
      original_metadata = %{step: 1}
      context = Context.new(%{a: 1}) |> Context.put_metadata(:step, 1)

      merged = Context.merge_vars(context, %{b: 2})

      assert merged.metadata == original_metadata
      assert merged.session_id == context.session_id
    end
  end

  describe "metadata operations" do
    test "stores and retrieves metadata" do
      context = Context.new()

      updated = Context.put_metadata(context, :step_count, 5)
      assert Context.get_metadata(updated, :step_count) == 5
    end

    test "returns default for missing metadata" do
      context = Context.new()

      assert Context.get_metadata(context, :missing) == nil
      assert Context.get_metadata(context, :missing, "default") == "default"
    end

    test "overwrites existing metadata" do
      context = Context.new() |> Context.put_metadata(:retry_count, 1)

      updated = Context.put_metadata(context, :retry_count, 3)
      assert Context.get_metadata(updated, :retry_count) == 3
    end
  end

  describe "memory operations" do
    test "handles context without memory" do
      context = Context.new()

      # Should not crash, just return unchanged context
      result = Context.store_in_memory(context, :key, "value")
      assert result == context

      # Should return error
      assert Context.get_from_memory(context, :key) == {:error, :no_memory}
    end

    test "works with mock memory" do
      # Create a simple mock memory for testing
      mock_memory = %{
        storage: %{},
        store: fn memory, key, value ->
          %{memory | storage: Map.put(memory.storage, key, value)}
        end,
        retrieve: fn memory, key ->
          case Map.get(memory.storage, key) do
            nil -> {:error, :not_found}
            value -> {:ok, value}
          end
        end
      }

      # Mock the Memory module functions for this test
      defmodule TestMemory do
        def store(memory, key, value) do
          memory.store.(memory, key, value)
        end

        def retrieve(memory, key) do
          memory.retrieve.(memory, key)
        end
      end

      # Test with mocked functions
      context = Context.new(%{}, mock_memory)

      # This would work with actual Memory implementation
      # For now, just test the structure
      assert context.memory == mock_memory
    end
  end

  describe "utility functions" do
    test "keys/1 returns all variable keys" do
      context = Context.new(%{name: "Alice", age: 30, city: "Boston"})
      keys = Context.keys(context)

      assert length(keys) == 3
      assert :name in keys
      assert :age in keys
      assert :city in keys
    end

    test "size/1 returns variable count" do
      context = Context.new()
      assert Context.size(context) == 0

      context = Context.new(%{a: 1, b: 2})
      assert Context.size(context) == 2
    end

    test "to_map/1 returns variables as map" do
      variables = %{user: "bob", role: "admin"}
      context = Context.new(variables)

      assert Context.to_map(context) == variables
    end
  end

  describe "edge cases and error handling" do
    test "handles nil values gracefully" do
      context = Context.new()

      updated = Context.put(context, :nil_value, nil)
      assert Context.get(updated, :nil_value) == nil
      assert Context.get(updated, :nil_value, "default") == nil
    end

    test "handles atom and string keys" do
      context = Context.new()

      updated =
        context
        |> Context.put(:atom_key, "atom_value")
        |> Context.put("string_key", "string_value")

      assert Context.get(updated, :atom_key) == "atom_value"
      assert Context.get(updated, "string_key") == "string_value"
    end

    test "context is immutable" do
      original = Context.new(%{count: 1})

      _updated = Context.put(original, :count, 5)

      # Original should be unchanged
      assert Context.get(original, :count) == 1
    end

    test "large context performance" do
      # Test with many variables
      large_vars = 1..1000 |> Enum.into(%{}, fn i -> {:"key_#{i}", i} end)
      context = Context.new(large_vars)

      assert Context.size(context) == 1000
      assert Context.get(context, :key_500) == 500

      # Test merge performance
      new_vars = 1001..1100 |> Enum.into(%{}, fn i -> {:"key_#{i}", i} end)
      merged = Context.merge_vars(context, new_vars)

      assert Context.size(merged) == 1100
    end
  end
end
