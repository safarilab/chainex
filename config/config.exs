import Config

# Configure LLM providers
config :chainex, Chainex.LLM,
  default_provider: :anthropic,
  anthropic: [
    api_key: {:system, "ANTHROPIC_API_KEY"},
    model: "claude-3-5-sonnet-20241022",
    base_url: "https://api.anthropic.com/v1",
    version: "2023-06-01"
  ],
  openai: [
    api_key: {:system, "OPENAI_API_KEY"},
    model: "gpt-4",
    base_url: "https://api.openai.com/v1"
  ],
  mock: [
    model: "mock-model"
  ]

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
