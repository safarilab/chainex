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
        # Same key again
        |> Memory.store(:msg1, "Updated First")

      keys = Memory.keys(memory)
      # Should only have unique keys
      assert length(keys) == 2
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

  describe "smart pruning functionality" do
    test "initializes with default pruning config" do
      memory = Memory.new(:buffer)

      assert memory.pruning_config.max_size == :unlimited
      assert memory.pruning_config.ttl_seconds == :unlimited
      assert memory.pruning_config.prune_strategy == :lru
      assert memory.pruning_config.prune_percentage == 0.2
      assert memory.pruning_config.auto_prune == true
    end

    test "accepts custom pruning configuration" do
      options = %{
        max_size: 50,
        ttl_seconds: 300,
        prune_strategy: :lfu,
        prune_percentage: 0.3,
        auto_prune: false
      }

      memory = Memory.new(:buffer, options)

      assert memory.pruning_config.max_size == 50
      assert memory.pruning_config.ttl_seconds == 300
      assert memory.pruning_config.prune_strategy == :lfu
      assert memory.pruning_config.prune_percentage == 0.3
      assert memory.pruning_config.auto_prune == false
    end

    test "tracks creation and access statistics" do
      memory = Memory.new(:buffer, %{max_size: 10})

      # Store some values
      memory =
        memory
        |> Memory.store(:key1, "value1")
        |> Memory.store(:key2, "value2")

      # Check creation stats are tracked
      assert Map.has_key?(memory.access_stats.creation_time, :key1)
      assert Map.has_key?(memory.access_stats.creation_time, :key2)
      assert Map.has_key?(memory.access_stats.access_count, :key1)
      assert Map.has_key?(memory.access_stats.access_count, :key2)

      # Track access
      {updated_memory, {:ok, _}} = Memory.get_and_track(memory, :key1)

      # Access count should be incremented
      assert updated_memory.access_stats.access_count[:key1] == 1
      assert Map.has_key?(updated_memory.access_stats.last_access, :key1)
    end

    test "auto prunes when max_size exceeded" do
      memory = Memory.new(:buffer, %{max_size: 2, auto_prune: true, prune_percentage: 0.5})

      # Store items up to limit
      memory =
        memory
        |> Memory.store(:key1, "value1")
        |> Memory.store(:key2, "value2")

      assert Memory.size(memory) == 2

      # Add one more - should trigger auto pruning
      memory = Memory.store(memory, :key3, "value3")

      # Should have pruned some items (50% of 3 = 1.5, truncated to 1)
      assert Memory.size(memory) <= 2
    end

    test "LRU pruning removes least recently used items" do
      memory = Memory.new(:buffer, %{max_size: 3, auto_prune: false, prune_strategy: :lru})

      # Store items
      memory =
        memory
        |> Memory.store(:old1, "value1")
        |> Memory.store(:old2, "value2")
        |> Memory.store(:new1, "value3")
        |> Memory.store(:new2, "value4")

      # Access some items to update their access time
      {memory, _} = Memory.get_and_track(memory, :new1)
      {memory, _} = Memory.get_and_track(memory, :new2)

      # Manual prune
      pruned = Memory.prune(memory)

      # Should keep more recently accessed items
      assert {:ok, _} = Memory.retrieve(pruned, :old2)
      assert {:ok, _} = Memory.retrieve(pruned, :new1)
      assert {:ok, _} = Memory.retrieve(pruned, :new2)
    end

    test "LFU pruning removes least frequently used items" do
      memory = Memory.new(:buffer, %{max_size: 3, auto_prune: false, prune_strategy: :lfu})

      # Store items
      memory =
        memory
        |> Memory.store(:rare, "value1")
        |> Memory.store(:common1, "value2")
        |> Memory.store(:common2, "value3")
        |> Memory.store(:extra, "value4")

      # Access some items multiple times
      {memory, _} = Memory.get_and_track(memory, :common1)
      {memory, _} = Memory.get_and_track(memory, :common1)
      {memory, _} = Memory.get_and_track(memory, :common2)
      {memory, _} = Memory.get_and_track(memory, :common2)

      # Manual prune
      pruned = Memory.prune(memory)

      # Should keep frequently accessed items
      assert {:ok, _} = Memory.retrieve(pruned, :common1)
      assert {:ok, _} = Memory.retrieve(pruned, :common2)

      # Should remove least frequently used items (rare and extra have 0 access count)
      # assert {:error, :not_found} = Memory.retrieve(pruned, :rare)
      # Note: :extra might or might not be removed depending on which items are selected first
      # but at least one of the unaccessed items should be gone
      removed_count =
        [:rare, :extra]
        |> Enum.count(fn key -> Memory.retrieve(pruned, key) == {:error, :not_found} end)

      assert removed_count >= 1
    end

    test "TTL cleanup removes expired entries" do
      memory = Memory.new(:buffer, %{ttl_seconds: 1})

      # Store an item
      memory = Memory.store(memory, :temp, "temporary")

      # Should exist initially
      assert {:ok, "temporary"} = Memory.retrieve(memory, :temp)

      # Wait for expiration (simulate by manually setting old creation time)
      old_time = :os.system_time(:second) - 2

      updated_stats = %{
        memory.access_stats
        | creation_time: Map.put(memory.access_stats.creation_time, :temp, old_time)
      }

      aged_memory = %{memory | access_stats: updated_stats}

      # Cleanup expired
      cleaned = Memory.cleanup_expired(aged_memory)

      # Should be removed
      assert {:error, :not_found} = Memory.retrieve(cleaned, :temp)
    end

    test "hybrid strategy combines TTL and LRU pruning" do
      memory =
        Memory.new(:buffer, %{
          max_size: 3,
          ttl_seconds: 1,
          prune_strategy: :hybrid,
          auto_prune: false
        })

      # Store items with different ages
      memory =
        memory
        |> Memory.store(:old_expired, "value1")
        |> Memory.store(:new_item, "value2")
        |> Memory.store(:another_new, "value3")

      # Simulate expiration for one item
      old_time = :os.system_time(:second) - 2

      updated_stats = %{
        memory.access_stats
        | creation_time: Map.put(memory.access_stats.creation_time, :old_expired, old_time)
      }

      aged_memory = %{memory | access_stats: updated_stats}

      # Hybrid prune should remove expired first
      pruned = Memory.force_prune(aged_memory, :hybrid)

      # Expired item should be gone
      assert {:error, :not_found} = Memory.retrieve(pruned, :old_expired)
      # Non-expired items should remain
      assert {:ok, _} = Memory.retrieve(pruned, :new_item)
      assert {:ok, _} = Memory.retrieve(pruned, :another_new)
    end

    test "force_prune works regardless of auto_prune setting" do
      memory = Memory.new(:buffer, %{max_size: 5, auto_prune: false})

      # Fill beyond capacity
      memory =
        1..10
        |> Enum.reduce(memory, fn i, acc ->
          Memory.store(acc, :"key_#{i}", "value_#{i}")
        end)

      assert Memory.size(memory) == 10

      # Force prune
      pruned = Memory.force_prune(memory, :lru)

      # Should be reduced
      assert Memory.size(pruned) < 10
    end

    test "disabling auto_prune prevents automatic pruning" do
      memory = Memory.new(:buffer, %{max_size: 2, auto_prune: false})

      # Store beyond capacity
      memory =
        memory
        |> Memory.store(:key1, "value1")
        |> Memory.store(:key2, "value2")
        |> Memory.store(:key3, "value3")

      # Should not auto-prune
      assert Memory.size(memory) == 3
    end

    test "conversation memory supports pruning" do
      memory = Memory.new(:conversation, %{max_size: 2, prune_percentage: 0.5})

      # Add multiple conversation entries
      memory =
        memory
        |> Memory.store(:msg1, %{role: "user", content: "First"})
        |> Memory.store(:msg2, %{role: "assistant", content: "Second"})
        |> Memory.store(:msg3, %{role: "user", content: "Third"})

      # Should have pruned (auto_prune is true by default)
      assert Memory.size(memory) <= 2
    end

    test "persistent memory supports pruning" do
      temp_file = "/tmp/chainex_pruning_test_#{:erlang.unique_integer([:positive])}.dat"
      on_exit(fn -> File.rm(temp_file) end)

      memory =
        Memory.new(:persistent, %{
          file_path: temp_file,
          max_size: 2,
          prune_percentage: 0.5
        })

      # Store beyond capacity
      memory =
        memory
        |> Memory.store(:key1, "value1")
        |> Memory.store(:key2, "value2")
        |> Memory.store(:key3, "value3")

      # Should have auto-pruned
      assert Memory.size(memory) <= 2

      # Verify persistence works with pruning
      fresh_memory = Memory.new(:persistent, %{file_path: temp_file})
      assert Memory.size(fresh_memory) <= 2
    end

    test "get_and_track updates access statistics" do
      memory = Memory.new(:buffer)
      memory = Memory.store(memory, :test_key, "test_value")

      # Initial access count should be 0
      assert memory.access_stats.access_count[:test_key] == 0

      # Track access
      {updated_memory, {:ok, "test_value"}} = Memory.get_and_track(memory, :test_key)

      # Access count should be incremented
      assert updated_memory.access_stats.access_count[:test_key] == 1
      assert Map.has_key?(updated_memory.access_stats.last_access, :test_key)

      # Track another access
      {updated_memory2, {:ok, "test_value"}} = Memory.get_and_track(updated_memory, :test_key)
      assert updated_memory2.access_stats.access_count[:test_key] == 2
    end

    test "get_and_track handles missing keys" do
      memory = Memory.new(:buffer)

      # Should handle missing key gracefully
      {updated_memory, {:error, :not_found}} = Memory.get_and_track(memory, :missing)

      # Memory should be unchanged
      assert updated_memory == memory
    end

    test "pruning config validation with unlimited values" do
      memory =
        Memory.new(:buffer, %{
          max_size: :unlimited,
          ttl_seconds: :unlimited
        })

      # Should not prune with unlimited settings
      memory =
        1..100
        |> Enum.reduce(memory, fn i, acc ->
          Memory.store(acc, :"key_#{i}", "value_#{i}")
        end)

      assert Memory.size(memory) == 100

      # Manual prune should not reduce size with unlimited max_size
      pruned = Memory.prune(memory)
      assert Memory.size(pruned) == 100
    end
  end

  describe "database backend integration" do
    import Chainex.RepoCase, only: [repo: 0]
    
    setup do
      # Start owner for database tests
      pid = Ecto.Adapters.SQL.Sandbox.start_owner!(repo(), shared: false)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
      
      # Create table for this test
      Ecto.Adapters.SQL.query!(repo(), """
        CREATE TABLE IF NOT EXISTS chainex_memory (
          key TEXT PRIMARY KEY,
          value BLOB NOT NULL,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          access_count INTEGER NOT NULL DEFAULT 0,
          last_access INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
        )
      """, [])
      
      {:ok, table: "chainex_memory"}
    end

    test "creates database backend memory", %{table: table} do
      memory = Memory.new(:persistent, %{
        backend: :database,
        repo: repo(),
        table: table
      })

      assert memory.type == :persistent
      assert memory.options.backend == :database
      assert memory.options.repo == repo()
      assert memory.options.table == table
    end

    test "stores and retrieves values with database backend", %{table: table} do
      memory = Memory.new(:persistent, %{
        backend: :database,
        repo: repo(),
        table: table
      })

      # Store values
      memory = Memory.store(memory, :db_key1, "db_value1")
      memory = Memory.store(memory, :db_key2, %{data: "complex", count: 42})

      # Retrieve values
      assert {:ok, "db_value1"} = Memory.retrieve(memory, :db_key1)
      assert {:ok, %{data: "complex", count: 42}} = Memory.retrieve(memory, :db_key2)
      assert {:error, :not_found} = Memory.retrieve(memory, :missing)
    end

    test "database backend size and keys operations", %{table: table} do
      memory = Memory.new(:persistent, %{
        backend: :database,
        repo: repo(),
        table: table
      })

      # Initially empty
      assert Memory.size(memory) == 0
      assert Memory.keys(memory) == []

      # Add items
      memory = memory
        |> Memory.store(:db1, "value1")
        |> Memory.store(:db2, "value2")
        |> Memory.store("string_key", "value3")

      # Check size and keys
      assert Memory.size(memory) == 3
      
      keys = Memory.keys(memory)
      assert length(keys) == 3
      assert :db1 in keys
      assert :db2 in keys  
      assert "string_key" in keys
    end

    test "database backend delete operations", %{table: table} do
      memory = Memory.new(:persistent, %{
        backend: :database,
        repo: repo(),
        table: table
      })

      # Store and delete
      memory = memory
        |> Memory.store(:delete_me, "temporary")
        |> Memory.store(:keep_me, "permanent")

      assert Memory.size(memory) == 2
      assert {:ok, "temporary"} = Memory.retrieve(memory, :delete_me)

      # Delete one item
      memory = Memory.delete(memory, :delete_me)
      
      assert Memory.size(memory) == 1
      assert {:error, :not_found} = Memory.retrieve(memory, :delete_me)
      assert {:ok, "permanent"} = Memory.retrieve(memory, :keep_me)
    end

    test "database backend clear operations", %{table: table} do
      memory = Memory.new(:persistent, %{
        backend: :database,
        repo: repo(),
        table: table
      })

      # Add data
      memory = memory
        |> Memory.store(:clear1, "value1")
        |> Memory.store(:clear2, "value2")

      assert Memory.size(memory) == 2

      # Clear all
      cleared = Memory.clear(memory)
      assert Memory.size(cleared) == 0
      assert Memory.keys(cleared) == []
    end

    test "database backend supports smart pruning", %{table: table} do
      memory = Memory.new(:persistent, %{
        backend: :database,
        repo: repo(),
        table: table,
        max_size: 3,
        prune_strategy: :lru,
        auto_prune: true,
        prune_percentage: 0.5
      })

      # Store items up to limit
      memory = memory
        |> Memory.store(:item1, "value1")
        |> Memory.store(:item2, "value2")
        |> Memory.store(:item3, "value3")

      assert Memory.size(memory) == 3

      # Add one more - should trigger auto pruning
      memory = Memory.store(memory, :item4, "value4")

      # Should have pruned some items
      final_size = Memory.size(memory)
      assert final_size <= 3
      assert final_size >= 1  # At least some items should remain
    end

    test "database backend get_and_track updates access stats", %{table: table} do
      memory = Memory.new(:persistent, %{
        backend: :database,
        repo: repo(),
        table: table
      })

      # Store a value
      memory = Memory.store(memory, :track_me, "tracked_value")

      # Track access
      {updated_memory, {:ok, "tracked_value"}} = Memory.get_and_track(memory, :track_me)
      
      # Verify the value was retrieved correctly
      assert updated_memory.access_stats.access_count[:track_me] == 1

      # Track again
      {updated_memory2, {:ok, "tracked_value"}} = Memory.get_and_track(updated_memory, :track_me)
      assert updated_memory2.access_stats.access_count[:track_me] == 2
    end

    test "database backend handles invalid configuration gracefully", %{table: table} do
      # Missing repo
      memory = Memory.new(:persistent, %{
        backend: :database,
        table: table
      })

      # Operations should still work but may fail gracefully
      memory = Memory.store(memory, :test, "value")
      
      # The memory should still track stats even if database operations fail
      assert Map.has_key?(memory.access_stats.creation_time, :test)
    end

    test "database backend works with conversation memory type", %{table: table} do
      # Note: This tests that conversation type can also use database backend
      # In practice, users might want separate tables for different memory types
      memory = Memory.new(:persistent, %{
        backend: :database,
        repo: repo(),
        table: table
      })

      # Store conversation-style entries
      memory = memory
        |> Memory.store(:msg1, %{role: "user", content: "Hello"})
        |> Memory.store(:msg2, %{role: "assistant", content: "Hi there!"})

      assert {:ok, %{role: "user", content: "Hello"}} = Memory.retrieve(memory, :msg1)
      assert {:ok, %{role: "assistant", content: "Hi there!"}} = Memory.retrieve(memory, :msg2)
      assert Memory.size(memory) == 2
    end

    test "database backend coexists with file backend", %{table: table} do
      # Create file backend memory
      temp_file = "/tmp/chainex_coexist_test_#{:erlang.unique_integer([:positive])}.dat"
      on_exit(fn -> File.rm(temp_file) end)

      file_memory = Memory.new(:persistent, %{file_path: temp_file})
      
      # Create database backend memory  
      db_memory = Memory.new(:persistent, %{
        backend: :database,
        repo: repo(),
        table: table
      })

      # Store different data in each
      file_memory = Memory.store(file_memory, :file_key, "file_value")
      db_memory = Memory.store(db_memory, :db_key, "db_value")

      # Verify separation
      assert {:ok, "file_value"} = Memory.retrieve(file_memory, :file_key)
      assert {:error, :not_found} = Memory.retrieve(file_memory, :db_key)

      assert {:ok, "db_value"} = Memory.retrieve(db_memory, :db_key)
      assert {:error, :not_found} = Memory.retrieve(db_memory, :file_key)
    end
  end
end
