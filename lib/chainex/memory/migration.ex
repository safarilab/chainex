defmodule Chainex.Memory.Migration do
  @moduledoc """
  Database migration helpers for Chainex Memory

  Provides utilities to create the necessary database tables for memory persistence.

  ## Usage

  Add to your migration file:

      defmodule MyApp.Repo.Migrations.CreateChainexMemory do
        use Ecto.Migration
        import Chainex.Memory.Migration

        def change do
          create_memory_table()
          # or with custom table name:
          # create_memory_table("my_custom_memory_table")
        end
      end

  ## Manual Schema Creation

  If you prefer to create the table manually:

      create table(:chainex_memory, primary_key: false) do
        add :key, :text, primary_key: true
        add :value, :binary, null: false
        add :access_count, :integer, null: false, default: 0
        add :created_at, :bigint, null: false
        add :updated_at, :bigint, null: false
        add :last_access, :bigint, null: false
      end

      create index(:chainex_memory, [:access_count])
      create index(:chainex_memory, [:last_access])
      create index(:chainex_memory, [:created_at])
  """

  import Ecto.Migration

  @default_table "chainex_memory"

  @doc """
  Creates the memory table with the required schema

  This function should be called within a migration in the consuming application.

  ## Options

  - `table` - Table name (defaults to "chainex_memory")
  - `create_indexes` - Whether to create performance indexes (defaults to true)

  ## Examples

      # In your application's migration:
      defmodule MyApp.Repo.Migrations.CreateChainexMemory do
        use Ecto.Migration
        import Chainex.Memory.Migration

        def change do
          create_memory_table()
        end
      end

      # With custom table name:
      create_memory_table("my_memory")
      
      # Without indexes:
      create_memory_table("custom_memory", create_indexes: false)
  """
  @spec create_memory_table(String.t(), keyword()) :: :ok
  def create_memory_table(table \\ @default_table, opts \\ []) do
    create_indexes = Keyword.get(opts, :create_indexes, true)

    create table(table, primary_key: false) do
      add :key, :text, primary_key: true
      add :value, :binary, null: false
      add :access_count, :integer, null: false, default: 0
      add :created_at, :bigint, null: false
      add :updated_at, :bigint, null: false
      add :last_access, :bigint, null: false
    end

    if create_indexes do
      create_memory_indexes(table)
    end

    :ok
  end

  @doc """
  Drops the memory table

  ## Examples

      drop_memory_table()
      drop_memory_table("my_memory")
  """
  @spec drop_memory_table(String.t()) :: :ok
  def drop_memory_table(table \\ @default_table) do
    drop table(table)
    :ok
  end

  @doc """
  Creates performance indexes for the memory table

  These indexes optimize:
  - LFU pruning (access_count)
  - LRU pruning (last_access)
  - TTL pruning (created_at)

  ## Examples

      create_memory_indexes()
      create_memory_indexes("my_memory")
  """
  @spec create_memory_indexes(String.t()) :: :ok
  def create_memory_indexes(table \\ @default_table) do
    create index(table, [:access_count], name: "#{table}_access_count_index")
    create index(table, [:last_access], name: "#{table}_last_access_index")
    create index(table, [:created_at], name: "#{table}_created_at_index")
    :ok
  end

  @doc """
  Drops the performance indexes for the memory table

  ## Examples

      drop_memory_indexes()
      drop_memory_indexes("my_memory")
  """
  @spec drop_memory_indexes(String.t()) :: :ok
  def drop_memory_indexes(table \\ @default_table) do
    drop index(table, [:access_count], name: "#{table}_access_count_index")
    drop index(table, [:last_access], name: "#{table}_last_access_index")
    drop index(table, [:created_at], name: "#{table}_created_at_index")
    :ok
  end

  @doc """
  Adds the memory table to an existing database

  Useful for adding memory persistence to an existing application.

  ## Examples

      add_memory_table()
      add_memory_table("custom_memory")
  """
  @spec add_memory_table(String.t(), keyword()) :: :ok
  def add_memory_table(table \\ @default_table, opts \\ []) do
    create_memory_table(table, opts)
  end

  @doc """
  Removes the memory table from the database

  ## Examples

      remove_memory_table()
      remove_memory_table("custom_memory")
  """
  @spec remove_memory_table(String.t()) :: :ok
  def remove_memory_table(table \\ @default_table) do
    drop_memory_table(table)
  end

  @doc """
  Upgrades the memory table schema

  This function can be used to upgrade existing memory tables
  to support new features or fix schema issues.

  ## Examples

      upgrade_memory_table()
      upgrade_memory_table("my_memory")
  """
  @spec upgrade_memory_table(String.t()) :: :ok
  def upgrade_memory_table(table \\ @default_table) do
    # Check if columns exist and add them if missing
    # This is a no-op for now but can be extended for future schema changes
    
    # Ensure indexes exist
    create_memory_indexes(table)
    
    :ok
  end
end