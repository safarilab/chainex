defmodule Chainex.RepoCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Chainex.Memory.Database

      import Ecto
      import Ecto.Query
      import Chainex.RepoCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(repo(), shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    
    # Create the test table for each test
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
    
    {:ok, config: %{repo: repo(), table: "chainex_memory"}}
  end

  # Test repo for database tests
  defmodule TestRepo do
    use Ecto.Repo,
      otp_app: :chainex,
      adapter: Ecto.Adapters.SQLite3
  end

  def repo, do: TestRepo

  def start_repo do
    # Start the test repo with sandbox pool
    {:ok, _} = TestRepo.start_link(
      database: ":memory:",
      pool: Ecto.Adapters.SQL.Sandbox
    )
    
    # Set up sandbox mode
    Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
    
    :ok
  end
end