defmodule Chainex.Memory.DatabaseTest do
  use Chainex.RepoCase, async: true

  describe "validate_config/1" do
    test "validates valid config with repo and table" do
      config = %{repo: repo(), table: "memory_test"}
      assert {:ok, ^config} = Database.validate_config(config)
    end

    test "validates config with repo only, uses default table" do
      config = %{repo: repo()}
      assert {:ok, result} = Database.validate_config(config)
      assert result.repo == repo()
      assert result.table == "chainex_memory"
    end

    test "rejects config without repo" do
      config = %{table: "memory_test"}
      assert {:error, :missing_repo} = Database.validate_config(config)
    end

    test "rejects config with invalid repo" do
      config = %{repo: NonExistentRepo, table: "memory_test"}
      assert {:error, :invalid_repo} = Database.validate_config(config)
    end
  end

  describe "store/3 and retrieve/2" do
    test "stores and retrieves simple values", %{config: config} do
      assert :ok = Database.store(config, :test_key, "test_value")
      assert {:ok, "test_value"} = Database.retrieve(config, :test_key)
    end

    test "stores and retrieves complex data structures", %{config: config} do
      complex_data = %{
        list: [1, 2, 3],
        map: %{nested: true, count: 42},
        tuple: {:ok, "success"},
        atom: :some_atom
      }

      assert :ok = Database.store(config, :complex, complex_data)
      assert {:ok, ^complex_data} = Database.retrieve(config, :complex)
    end

    test "handles different key types", %{config: config} do
      # String key
      assert :ok = Database.store(config, "string_key", "value1")
      assert {:ok, "value1"} = Database.retrieve(config, "string_key")

      # Atom key
      assert :ok = Database.store(config, :atom_key, "value2")
      assert {:ok, "value2"} = Database.retrieve(config, :atom_key)

      # Complex key
      complex_key = {:user, 123, "session"}
      assert :ok = Database.store(config, complex_key, "value3")
      assert {:ok, "value3"} = Database.retrieve(config, complex_key)
    end

    test "overwrites existing values", %{config: config} do
      assert :ok = Database.store(config, :overwrite_key, "original")
      assert {:ok, "original"} = Database.retrieve(config, :overwrite_key)

      assert :ok = Database.store(config, :overwrite_key, "updated")
      assert {:ok, "updated"} = Database.retrieve(config, :overwrite_key)
    end

    test "returns error for missing keys", %{config: config} do
      assert {:error, :not_found} = Database.retrieve(config, :missing_key)
    end
  end

  describe "update_access/2" do
    test "updates access statistics", %{config: config} do
      # Store a key first
      assert :ok = Database.store(config, :access_key, "value")
      
      # Update access
      assert :ok = Database.update_access(config, :access_key)
      
      # Verify access count increased
      {:ok, %{rows: [[_key, _created_at, access_count, _last_access]]}} = 
        Ecto.Adapters.SQL.query(config.repo, "SELECT key, created_at, access_count, last_access FROM #{config.table} WHERE key = ?", ["a:access_key"])
      
      assert access_count == 1
    end

    test "handles multiple access updates", %{config: config} do
      assert :ok = Database.store(config, :multi_access, "value")
      
      # Update access multiple times
      assert :ok = Database.update_access(config, :multi_access)
      assert :ok = Database.update_access(config, :multi_access)
      assert :ok = Database.update_access(config, :multi_access)
      
      # Verify final count
      {:ok, %{rows: [[_key, _created_at, access_count, _last_access]]}} = 
        Ecto.Adapters.SQL.query(config.repo, "SELECT key, created_at, access_count, last_access FROM #{config.table} WHERE key = ?", ["a:multi_access"])
      
      assert access_count == 3
    end
  end

  describe "delete/2" do
    test "deletes existing keys", %{config: config} do
      assert :ok = Database.store(config, :delete_me, "temporary")
      assert {:ok, "temporary"} = Database.retrieve(config, :delete_me)
      
      assert :ok = Database.delete(config, :delete_me)
      assert {:error, :not_found} = Database.retrieve(config, :delete_me)
    end

    test "handles deletion of non-existent keys gracefully", %{config: config} do
      assert :ok = Database.delete(config, :never_existed)
    end
  end

  describe "keys/1 and size/1" do
    test "lists all keys", %{config: config} do
      # Empty initially
      assert {:ok, []} = Database.keys(config)
      
      # Add some keys
      assert :ok = Database.store(config, :key1, "value1")
      assert :ok = Database.store(config, :key2, "value2")
      assert :ok = Database.store(config, "string_key", "value3")
      
      # Get keys
      assert {:ok, keys} = Database.keys(config)
      assert length(keys) == 3
      assert :key1 in keys
      assert :key2 in keys
      assert "string_key" in keys
    end

    test "returns correct size", %{config: config} do
      # Empty initially
      assert {:ok, 0} = Database.size(config)
      
      # Add keys and check size
      assert :ok = Database.store(config, :size1, "value")
      assert {:ok, 1} = Database.size(config)
      
      assert :ok = Database.store(config, :size2, "value")
      assert {:ok, 2} = Database.size(config)
      
      # Delete and check size
      assert :ok = Database.delete(config, :size1)
      assert {:ok, 1} = Database.size(config)
    end
  end

  describe "clear/1" do
    test "clears all entries", %{config: config} do
      # Add some data
      assert :ok = Database.store(config, :clear1, "value1")
      assert :ok = Database.store(config, :clear2, "value2")
      assert {:ok, 2} = Database.size(config)
      
      # Clear all
      assert :ok = Database.clear(config)
      assert {:ok, 0} = Database.size(config)
      assert {:ok, []} = Database.keys(config)
    end
  end

  describe "get_access_stats/1" do
    test "returns access statistics", %{config: config} do
      # Store some keys
      assert :ok = Database.store(config, :stats1, "value1")
      assert :ok = Database.store(config, :stats2, "value2")
      
      # Update access for one key
      assert :ok = Database.update_access(config, :stats1)
      assert :ok = Database.update_access(config, :stats1)
      
      # Get stats
      assert {:ok, stats} = Database.get_access_stats(config)
      
      assert is_map(stats.access_count)
      assert is_map(stats.last_access)
      assert is_map(stats.creation_time)
      
      assert stats.access_count[:stats1] == 2
      assert stats.access_count[:stats2] == 0
      
      assert Map.has_key?(stats.creation_time, :stats1)
      assert Map.has_key?(stats.creation_time, :stats2)
    end
  end

  describe "find_keys_for_pruning/4" do
    test "finds keys for LFU pruning", %{config: config} do
      # Store keys with different access patterns
      assert :ok = Database.store(config, :frequent, "value1")
      assert :ok = Database.store(config, :rare, "value2")
      assert :ok = Database.store(config, :medium, "value3")
      
      # Access keys differently
      assert :ok = Database.update_access(config, :frequent)
      assert :ok = Database.update_access(config, :frequent)
      assert :ok = Database.update_access(config, :frequent)
      
      assert :ok = Database.update_access(config, :medium)
      
      # :rare not accessed (count = 0)
      
      # Get least frequently used (should return :rare first)
      assert {:ok, keys} = Database.find_keys_for_pruning(config, :lfu, 2)
      
      assert length(keys) == 2
      assert :rare in keys
      assert :medium in keys
      refute :frequent in keys
    end

    test "finds keys for LRU pruning", %{config: config} do
      # Store keys
      assert :ok = Database.store(config, :old, "value1") 
      assert :ok = Database.store(config, :new, "value2")
      
      # Access :new more recently
      :timer.sleep(1) # Ensure different timestamps
      assert :ok = Database.update_access(config, :new)
      
      # Get least recently used
      assert {:ok, keys} = Database.find_keys_for_pruning(config, :lru, 1)
      
      assert length(keys) == 1
      assert :old in keys
    end

    test "finds keys for TTL pruning", %{config: config} do
      current_time = :os.system_time(:second)
      
      # Store key
      assert :ok = Database.store(config, :ttl_key, "value")
      
      # Simulate old creation time by updating database directly
      Ecto.Adapters.SQL.query!(config.repo, """
        UPDATE #{config.table} 
        SET created_at = ? 
        WHERE key = ?
      """, [current_time - 3600, "a:ttl_key"]) # 1 hour ago
      
      # Find expired keys (cutoff = 30 minutes ago)
      cutoff = current_time - 1800
      assert {:ok, keys} = Database.find_keys_for_pruning(config, :ttl, 10, cutoff)
      
      assert :ttl_key in keys
    end
  end

  describe "table_exists?/1" do
    test "returns true for existing table", %{config: config} do
      assert Database.table_exists?(config) == true
    end

    test "returns false for non-existent table" do
      config = %{repo: repo(), table: "non_existent_table"}
      assert Database.table_exists?(config) == false
    end
  end
end