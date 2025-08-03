defmodule Chainex.MemoryTest do
  use ExUnit.Case, async: true
  alias Chainex.Memory
  doctest Chainex.Memory

  describe "new/2" do
    test "creates buffer memory by default" do
      memory = Memory.new(:buffer)

      assert memory.type == :buffer
      assert memory.storage == %{}
      assert memory.options == %{}
    end

    test "creates conversation memory" do
      memory = Memory.new(:conversation)

      assert memory.type == :conversation
      assert memory.storage == []
      assert memory.options == %{}
    end

    test "creates persistent memory with options" do
      options = %{file_path: "/tmp/test.dat"}
      memory = Memory.new(:persistent, options)

      assert memory.type == :persistent
      assert memory.options == options
    end

    test "creates vector memory" do
      memory = Memory.new(:vector)

      assert memory.type == :vector
      assert memory.storage == %{}
    end

    test "raises error for invalid memory type" do
      assert_raise FunctionClauseError, fn ->
        Memory.new(:invalid_type)
      end
    end
  end

  describe "buffer memory operations" do
    setup do
      {:ok, memory: Memory.new(:buffer)}
    end

    test "stores and retrieves values", %{memory: memory} do
      updated = Memory.store(memory, :name, "Alice")
      
      assert {:ok, "Alice"} = Memory.retrieve(updated, :name)
    end

    test "returns error for missing keys", %{memory: memory} do
      assert {:error, :not_found} = Memory.retrieve(memory, :missing)
    end

    test "overwrites existing values", %{memory: memory} do
      memory = 
        memory
        |> Memory.store(:count, 1)
        |> Memory.store(:count, 5)

      assert {:ok, 5} = Memory.retrieve(memory, :count)
    end

    test "handles different data types", %{memory: memory} do
      memory =
        memory
        |> Memory.store(:string, "text")
        |> Memory.store(:number, 42)
        |> Memory.store(:list, [1, 2, 3])
        |> Memory.store(:map, %{nested: true})
        |> Memory.store(:atom, :value)

      assert {:ok, "text"} = Memory.retrieve(memory, :string)
      assert {:ok, 42} = Memory.retrieve(memory, :number)
      assert {:ok, [1, 2, 3]} = Memory.retrieve(memory, :list)
      assert {:ok, %{nested: true}} = Memory.retrieve(memory, :map)
      assert {:ok, :value} = Memory.retrieve(memory, :atom)
    end

    test "lists all keys", %{memory: memory} do
      memory =
        memory
        |> Memory.store(:a, 1)
        |> Memory.store(:b, 2)
        |> Memory.store(:c, 3)

      keys = Memory.keys(memory)
      assert length(keys) == 3
      assert :a in keys
      assert :b in keys
      assert :c in keys
    end

    test "returns correct size", %{memory: memory} do
      assert Memory.size(memory) == 0

      memory = Memory.store(memory, :key1, "value1")
      assert Memory.size(memory) == 1

      memory = Memory.store(memory, :key2, "value2")
      assert Memory.size(memory) == 2
    end

    test "clears all data", %{memory: memory} do
      memory =
        memory
        |> Memory.store(:key1, "value1")
        |> Memory.store(:key2, "value2")

      assert Memory.size(memory) == 2

      cleared = Memory.clear(memory)
      assert Memory.size(cleared) == 0
      assert {:error, :not_found} = Memory.retrieve(cleared, :key1)
    end

    test "deletes specific keys", %{memory: memory} do
      memory =
        memory
        |> Memory.store(:keep, "keep_this")
        |> Memory.store(:delete, "delete_this")

      assert Memory.size(memory) == 2

      updated = Memory.delete(memory, :delete)
      assert Memory.size(updated) == 1
      assert {:ok, "keep_this"} = Memory.retrieve(updated, :keep)
      assert {:error, :not_found} = Memory.retrieve(updated, :delete)
    end
  end

  describe "conversation memory operations" do
    setup do
      {:ok, memory: Memory.new(:conversation)}
    end

    test "stores conversation entries with timestamps", %{memory: memory} do
      message = %{role: "user", content: "Hello"}
      updated = Memory.store(memory, :message1, message)

      assert {:ok, ^message} = Memory.retrieve(updated, :message1)
      assert length(updated.storage) == 1
      
      [entry] = updated.storage
      assert entry.key == :message1
      assert entry.value == message
      assert is_integer(entry.timestamp)
      assert is_binary(entry.id)
    end

    test "maintains conversation history order", %{memory: memory} do
      memory =
        memory
        |> Memory.store(:msg1, %{role: "user", content: "First"})
        |> Memory.store(:msg2, %{role: "assistant", content: "Second"})
        |> Memory.store(:msg3, %{role: "user", content: "Third"})

      # Most recent should be first (prepended to list)
      [latest, middle, oldest] = memory.storage
      
      assert latest.value.content == "Third"
      assert middle.value.content == "Second"
      assert oldest.value.content == "First"
      
      # But timestamps should reflect actual order
      assert latest.timestamp >= middle.timestamp
      assert middle.timestamp >= oldest.timestamp
    end

    test "retrieves by key from conversation history", %{memory: memory} do
      memory =
        memory
        |> Memory.store(:greeting, %{content: "Hello"})
        |> Memory.store(:question, %{content: "How are you?"})

      assert {:ok, %{content: "Hello"}} = Memory.retrieve(memory, :greeting)
      assert {:ok, %{content: "How are you?"}} = Memory.retrieve(memory, :question)
      assert {:error, :not_found} = Memory.retrieve(memory, :missing)
    end

    test "lists unique keys from conversation", %{memory: memory} do
      memory =
        memory
        |> Memory.store(:msg1, "First")
        |> Memory.store(:msg2, "Second")
        |> Memory.store(:msg1, "Updated First")  # Same key again

      keys = Memory.keys(memory)
      assert length(keys) == 2  # Should only have unique keys
      assert :msg1 in keys
      assert :msg2 in keys
    end

    test "returns correct size for conversation", %{memory: memory} do
      assert Memory.size(memory) == 0

      memory = Memory.store(memory, :msg1, "First")
      assert Memory.size(memory) == 1

      memory = Memory.store(memory, :msg2, "Second")
      assert Memory.size(memory) == 2

      # Same key adds another entry (conversation keeps history)
      memory = Memory.store(memory, :msg1, "Updated")
      assert Memory.size(memory) == 3
    end

    test "deletes all entries with matching key", %{memory: memory} do
      memory =
        memory
        |> Memory.store(:keep, "Keep this")
        |> Memory.store(:delete, "Delete this")
        |> Memory.store(:delete, "Delete this too")
        |> Memory.store(:keep, "Keep this too")

      assert Memory.size(memory) == 4

      updated = Memory.delete(memory, :delete)
      assert Memory.size(updated) == 2
      
      # Should only have :keep entries
      keys = Memory.keys(updated)
      assert :keep in keys
      assert :delete not in keys
    end
  end

  describe "persistent memory operations" do
    setup do
      # Use a unique temp file for each test
      temp_file = "/tmp/chainex_test_#{:erlang.unique_integer([:positive])}.dat"
      on_exit(fn -> File.rm(temp_file) end)
      {:ok, memory: Memory.new(:persistent, %{file_path: temp_file}), temp_file: temp_file}
    end

    test "stores and retrieves values from file", %{memory: memory, temp_file: temp_file} do
      # Store a value
      updated = Memory.store(memory, :key, "persistent_value")
      assert {:ok, "persistent_value"} = Memory.retrieve(updated, :key)
      
      # Verify file was created
      assert File.exists?(temp_file)
      
      # Create new memory instance and verify data persisted
      new_memory = Memory.new(:persistent, %{file_path: temp_file})
      assert {:ok, "persistent_value"} = Memory.retrieve(new_memory, :key)
    end

    test "handles file operations correctly", %{memory: memory, temp_file: temp_file} do
      # Store multiple values
      memory =
        memory
        |> Memory.store(:name, "Alice")
        |> Memory.store(:age, 25)
        |> Memory.store(:city, "NYC")

      # Verify all values can be retrieved
      assert {:ok, "Alice"} = Memory.retrieve(memory, :name)
      assert {:ok, 25} = Memory.retrieve(memory, :age)
      assert {:ok, "NYC"} = Memory.retrieve(memory, :city)
      
      # Create fresh memory instance and verify persistence
      fresh_memory = Memory.new(:persistent, %{file_path: temp_file})
      assert {:ok, "Alice"} = Memory.retrieve(fresh_memory, :name)
      assert {:ok, 25} = Memory.retrieve(fresh_memory, :age)
      assert {:ok, "NYC"} = Memory.retrieve(fresh_memory, :city)
    end

    test "handles file deletion correctly", %{memory: memory, temp_file: temp_file} do
      # Store and delete values
      memory = Memory.store(memory, :temp, "temporary")
      assert {:ok, "temporary"} = Memory.retrieve(memory, :temp)
      
      updated = Memory.delete(memory, :temp)
      assert {:error, :not_found} = Memory.retrieve(updated, :temp)
      
      # Verify deletion persisted to file
      fresh_memory = Memory.new(:persistent, %{file_path: temp_file})
      assert {:error, :not_found} = Memory.retrieve(fresh_memory, :temp)
    end

    test "returns correct size and keys", %{memory: memory, temp_file: temp_file} do
      # Store multiple items
      memory =
        memory
        |> Memory.store(:a, 1)
        |> Memory.store(:b, 2)
        |> Memory.store(:c, 3)

      assert Memory.size(memory) == 3
      keys = Memory.keys(memory)
      assert length(keys) == 3
      assert :a in keys
      assert :b in keys
      assert :c in keys
      
      # Verify with fresh memory instance
      fresh_memory = Memory.new(:persistent, %{file_path: temp_file})
      assert Memory.size(fresh_memory) == 3
      fresh_keys = Memory.keys(fresh_memory)
      assert length(fresh_keys) == 3
      assert :a in fresh_keys
      assert :b in fresh_keys  
      assert :c in fresh_keys
    end

    test "handles missing file gracefully", %{temp_file: temp_file} do
      # Create memory with non-existent file
      memory = Memory.new(:persistent, %{file_path: temp_file})
      
      # Should work normally with empty storage
      assert Memory.size(memory) == 0
      assert Memory.keys(memory) == []
      assert {:error, :not_found} = Memory.retrieve(memory, :missing)
    end

    test "handles invalid file path" do
      # Memory without file_path should fail gracefully
      memory = Memory.new(:persistent, %{})
      
      # Store should not crash but data won't persist
      updated = Memory.store(memory, :key, "value")
      # Should still work in memory
      assert {:ok, "value"} = Memory.retrieve(updated, :key)
    end

    test "handles corrupted file gracefully", %{temp_file: temp_file} do
      # Create corrupted file
      File.write!(temp_file, "not_valid_erlang_term")
      
      # Should fallback to empty storage
      memory = Memory.new(:persistent, %{file_path: temp_file})
      assert Memory.size(memory) == 0
      assert {:error, :not_found} = Memory.retrieve(memory, :key)
    end

    test "atomic file operations", %{memory: memory, temp_file: temp_file} do
      # Store a value
      updated = Memory.store(memory, :atomic_test, "original")
      
      # Verify temp file is cleaned up (atomic operation)
      temp_files = Path.wildcard(temp_file <> ".*")
      assert temp_files == []
      
      # Verify data integrity
      assert {:ok, "original"} = Memory.retrieve(updated, :atomic_test)
    end
  end

  describe "vector memory operations" do
    setup do
      {:ok, memory: Memory.new(:vector)}
    end

    test "behaves like buffer storage for now", %{memory: memory} do
      # For now, vector memory delegates to buffer behavior
      updated = Memory.store(memory, :embedding, [0.1, 0.2, 0.3])
      assert {:ok, [0.1, 0.2, 0.3]} = Memory.retrieve(updated, :embedding)
      assert Memory.size(updated) == 1
    end
  end

  describe "edge cases and error handling" do
    test "handles nil values" do
      memory = Memory.new(:buffer)
      updated = Memory.store(memory, :nil_key, nil)
      
      assert {:ok, nil} = Memory.retrieve(updated, :nil_key)
    end

    test "handles complex nested data structures" do
      memory = Memory.new(:buffer)
      complex_data = %{
        users: [
          %{name: "Alice", preferences: %{theme: "dark", lang: "en"}},
          %{name: "Bob", preferences: %{theme: "light", lang: "fr"}}
        ],
        metadata: %{version: "1.0", created: ~D[2024-01-01]}
      }

      updated = Memory.store(memory, :complex, complex_data)
      assert {:ok, ^complex_data} = Memory.retrieve(updated, :complex)
    end

    test "memory is immutable" do
      original = Memory.new(:buffer)
      _updated = Memory.store(original, :key, "value")

      # Original should be unchanged
      assert {:error, :not_found} = Memory.retrieve(original, :key)
      assert Memory.size(original) == 0
    end

    test "large memory performance" do
      memory = Memory.new(:buffer)
      
      # Store many items
      large_memory = 
        1..1000
        |> Enum.reduce(memory, fn i, acc ->
          Memory.store(acc, :"key_#{i}", "value_#{i}")
        end)

      assert Memory.size(large_memory) == 1000
      assert {:ok, "value_500"} = Memory.retrieve(large_memory, :key_500)
      
      keys = Memory.keys(large_memory)
      assert length(keys) == 1000
      assert :key_1 in keys
      assert :key_1000 in keys
    end

    test "conversation memory with many entries" do
      memory = Memory.new(:conversation)
      
      # Add many conversation entries
      large_memory =
        1..100
        |> Enum.reduce(memory, fn i, acc ->
          Memory.store(acc, :"msg_#{i}", %{content: "Message #{i}"})
        end)

      assert Memory.size(large_memory) == 100
      assert {:ok, %{content: "Message 50"}} = Memory.retrieve(large_memory, :msg_50)
      
      # Most recent should be first
      [first_entry | _] = large_memory.storage
      assert first_entry.value.content == "Message 100"
    end
  end
end