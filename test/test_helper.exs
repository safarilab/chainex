ExUnit.start()

# Start the test repo for database tests
if Code.ensure_loaded?(Ecto.Adapters.SQLite3) do
  Chainex.RepoCase.start_repo()
end
