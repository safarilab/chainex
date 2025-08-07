import Config

# Configure the test repo for testing database functionality
if Mix.env() == :test do
  config :chainex, Chainex.RepoCase.TestRepo,
    database: Path.expand("../test_chainex.db", __DIR__),
    pool: Ecto.Adapters.SQL.Sandbox,
    log: false

  config :chainex, ecto_repos: [Chainex.RepoCase.TestRepo]
  
  # Disable SQL debug logging in tests
  config :logger, level: :warning
end
