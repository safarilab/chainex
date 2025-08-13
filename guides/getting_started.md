# Getting Started with Chainex

Chainex is a powerful Elixir library for building LLM-powered applications with a fluent, pipeline-based API. This guide will help you get up and running quickly.

## Installation

Add `chainex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:chainex, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Configuration

Configure your LLM providers in `config/config.exs`:

```elixir
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
```

## Your First Chain

Let's create a simple question-answering chain:

```elixir
# Simple question answering
"What is {{topic}}?"
|> Chainex.Chain.new()
|> Chainex.Chain.llm(:openai)
|> Chainex.Chain.run(%{topic: "quantum computing"})
# => {:ok, "Quantum computing is a revolutionary computing paradigm..."}
```

## Key Concepts

### 1. Chains are Reusable

Build once, run many times with different variables:

```elixir
# Define once
translator = Chainex.Chain.new(
  system: "You are a professional translator specializing in {{field}}",
  user: "Translate '{{text}}' from {{from}} to {{to}}"
)
|> Chainex.Chain.llm(:anthropic)

# Use many times
translator |> Chainex.Chain.run(%{field: "medical", text: "headache", from: "English", to: "Spanish"})
translator |> Chainex.Chain.run(%{field: "legal", text: "contract", from: "English", to: "French"})
```

### 2. Pipeline Composition

Chain multiple operations together:

```elixir
"{{content}}"
|> Chainex.Chain.new()
|> Chainex.Chain.prompt("Summarize this content: {{input}}")
|> Chainex.Chain.llm(:openai, model: "gpt-4")
|> Chainex.Chain.transform(fn summary -> 
  "Create a title for this summary: #{summary}"
end)
|> Chainex.Chain.llm(:anthropic)
|> Chainex.Chain.run(%{content: "Long article text..."})
```

### 3. System Prompts are First-Class

System prompts define your LLM's personality and behavior:

```elixir
Chainex.Chain.new(
  system: "You are a {{domain}} expert with {{years}} years of experience",
  user: "Analyze {{subject}} and provide actionable insights"
)
|> Chainex.Chain.llm(:openai)
|> Chainex.Chain.run(%{
  domain: "cybersecurity", 
  years: 15,
  subject: "our network infrastructure"
})
```

## Next Steps

- Learn about [Memory and Context](memory_guide.html) for conversational AI
- Explore [Tools Integration](tools_guide.html) for connecting to external APIs
- Master [Parsing and Validation](parsing_guide.html) for structured data extraction
- Build robust applications with [Error Handling](error_handling_guide.html)

## Testing Your Chains

Use the built-in mock provider for testing:

```elixir
defmodule MyApp.ChainTest do
  use ExUnit.Case
  import Chainex.Chain

  test "expert analysis works" do
    chain = Chain.new(
      system: "You are a {{domain}} expert",
      user: "Explain {{topic}}"
    )
    |> Chain.llm(:mock, response: "Expert explanation here")
    
    assert {:ok, result} = Chain.run(chain, %{domain: "technology", topic: "AI"})
    assert result == "Expert explanation here"
  end
end
```