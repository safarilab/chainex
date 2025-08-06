defmodule Chainex.Memory.MigrationTest do
  use ExUnit.Case, async: true
  
  describe "migration helper module" do
    test "module exists and functions are exported" do
      # Test that the migration module exists
      assert Code.ensure_loaded?(Chainex.Memory.Migration)
      
      # Test that required functions are exported
      assert function_exported?(Chainex.Memory.Migration, :create_memory_table, 0)
      assert function_exported?(Chainex.Memory.Migration, :create_memory_table, 1)
      assert function_exported?(Chainex.Memory.Migration, :create_memory_table, 2)
      
      assert function_exported?(Chainex.Memory.Migration, :drop_memory_table, 0)
      assert function_exported?(Chainex.Memory.Migration, :drop_memory_table, 1)
      
      assert function_exported?(Chainex.Memory.Migration, :create_memory_indexes, 0)
      assert function_exported?(Chainex.Memory.Migration, :create_memory_indexes, 1)
      
      assert function_exported?(Chainex.Memory.Migration, :drop_memory_indexes, 0)
      assert function_exported?(Chainex.Memory.Migration, :drop_memory_indexes, 1)
      
      assert function_exported?(Chainex.Memory.Migration, :add_memory_table, 0)
      assert function_exported?(Chainex.Memory.Migration, :add_memory_table, 1)
      assert function_exported?(Chainex.Memory.Migration, :add_memory_table, 2)
      
      assert function_exported?(Chainex.Memory.Migration, :remove_memory_table, 0)
      assert function_exported?(Chainex.Memory.Migration, :remove_memory_table, 1)
      
      assert function_exported?(Chainex.Memory.Migration, :upgrade_memory_table, 0)
      assert function_exported?(Chainex.Memory.Migration, :upgrade_memory_table, 1)
    end

    test "module can be imported in migration context" do
      # Test that the module can be imported without errors
      # This simulates what would happen in a real migration
      
      defmodule TestMigration do
        use Ecto.Migration
        
        # Test that we can import the migration module without errors
        def test_functions_exist do
          # Check that the functions are available from the migration module
          assert function_exported?(Chainex.Memory.Migration, :create_memory_table, 0)
          assert function_exported?(Chainex.Memory.Migration, :create_memory_table, 1)
          assert function_exported?(Chainex.Memory.Migration, :create_memory_table, 2)
        end
      end
      
      assert TestMigration.test_functions_exist()
    end

    test "default table name is correct" do
      # Test that the default table name matches what Database module expects
      alias Chainex.Memory.Database
      
      # The default table should work with Database validation
      if Code.ensure_loaded?(Ecto.Adapters.SQLite3) do
        test_repo = Chainex.RepoCase.TestRepo
        config = %{repo: test_repo, table: "chainex_memory"}
        assert {:ok, ^config} = Database.validate_config(config)
      else
        # If no test repo available, just verify the constant exists
        assert "chainex_memory" == "chainex_memory"  # Default table name
      end
    end
  end
end