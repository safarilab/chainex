# Chainex 🔗

A powerful Elixir library for building LLM-powered applications with a fluent, pipeline-based API. Chain together multiple LLMs, tools, and transformations to create sophisticated AI workflows.

## Features

- 🔗 **Fluent Pipeline API** - Leverage Elixir's pipe operator for readable AI workflows
- 🎯 **System Prompt First-Class** - System prompts are part of your chain's identity
- 🔄 **Reusable Templates** - Build once, run many times with different variables
- 🤖 **Multi-LLM Support** - Chain OpenAI, Anthropic, Ollama, and more
- 🛠️ **Tool Integration** - Connect LLMs to external tools and APIs
- 📊 **Output Parsers** - Transform LLM responses into structured data
- 💾 **Memory & Context** - Maintain conversation state across interactions
- ⚡ **Runtime Variables** - Maximum flexibility with late-bound parameters

## Installation

Add `chainex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:chainex, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Simple question answering
"What is {{topic}}?"
|> Chain.new()
|> Chain.llm(:openai)
|> Chain.run(%{topic: "quantum computing"})
# => {:ok, "Quantum computing is a revolutionary computing paradigm..."}
```

## Core Concepts

### 1. System Prompts as First-Class Citizens

System prompts define your LLM's personality and behavior:

```elixir
# Expert consultant chain
Chain.new(
  system: "You are a {{domain}} expert with {{years}} years of experience",
  user: "Analyze {{subject}} and provide actionable insights"
)
|> Chain.llm(:openai)
|> Chain.run(%{
  domain: "cybersecurity", 
  years: 15,
  subject: "our network infrastructure"
})
```

### 2. Runtime Variable Resolution

Build reusable chains, execute with different data:

```elixir
# Define once
translator = Chain.new(
  system: "You are a professional translator specializing in {{field}}",
  user: "Translate '{{text}}' from {{from}} to {{to}}"
)
|> Chain.llm(:anthropic)

# Use many times
translator |> Chain.run(%{field: "medical", text: "headache", from: "English", to: "Spanish"})
translator |> Chain.run(%{field: "legal", text: "contract", from: "English", to: "French"})
translator |> Chain.run(%{field: "technical", text: "database", from: "English", to: "Japanese"})
```

### 3. Pipeline Composition

Chain operations with different prompts for different LLMs:

```elixir
# Multi-LLM analysis with specialized prompts
"{{raw_content}}"
|> Chain.new()
|> Chain.prompt("As an expert analyst, extract key insights from: {{input}}")
|> Chain.llm(:openai, model: "gpt-4")
|> Chain.transform(fn insights -> 
  "Previous analysis: #{insights}. Now provide a critical review and identify potential biases or gaps."
end)
|> Chain.llm(:anthropic, model: "claude-3-opus") 
|> Chain.transform(fn review ->
  "Synthesis task: Combine the insights and critical review into a balanced report with actionable recommendations."
end)
|> Chain.llm(:ollama, model: "llama2")
|> Chain.parse(:structured, schema: %{insights: [:string], concerns: [:string], recommendations: [:string]})
|> Chain.run(%{raw_content: "Market research data..."})
```

## Usage Examples

### Multi-Expert Analysis

Get multiple perspectives on the same topic:

```elixir
# Define expert perspectives
expert_analysis = fn role ->
  Chain.new(
    system: "You are a {{role}} expert. Analyze from your professional perspective.",
    user: "Evaluate: {{subject}}"
  )
  |> Chain.llm(:openai)
end

# Get different viewpoints
subject = "implementing AI in healthcare"

technical_view = expert_analysis.("software architect") |> Chain.run(%{subject: subject})
business_view = expert_analysis.("business strategist") |> Chain.run(%{subject: subject})  
ethical_view = expert_analysis.("medical ethicist") |> Chain.run(%{subject: subject})

# Synthesize perspectives
[technical_view, business_view, ethical_view]
|> Chain.new()
|> Chain.transform(fn analyses -> 
  "Synthesize these expert analyses: #{Enum.join(analyses, "\n\n")}"
end)
|> Chain.llm(:anthropic)
|> Chain.run()
```

### Smart Data Processing

Extract and validate structured data:

```elixir
# Contact extraction pipeline
contact_schema = %{
  name: :string,
  email: :string,
  phone: :string,
  company: :string
}

"{{unstructured_text}}"
|> Chain.new()
|> Chain.prompt("""
  Extract contact information from the following text.
  Return a JSON object with name, email, phone, and company fields.
  
  Text: {{input}}
  """)
|> Chain.llm(:openai)
|> Chain.parse(:json)
|> Chain.validate_schema(contact_schema)
|> Chain.transform(fn contact -> normalize_contact(contact) end)
|> Chain.run(%{unstructured_text: "John Smith from Acme Corp, john@acme.com, 555-123-4567"})
# => {:ok, %{name: "John Smith", email: "john@acme.com", phone: "+15551234567", company: "Acme Corp"}}
```

### Intelligent Tool Usage

Let LLMs decide when and how to use tools:

```elixir
# Weather assistant with tools
Chain.new(
  system: "You can check weather and perform calculations. Use tools when needed.",
  user: "{{user_request}}"
)
|> Chain.with_tools([weather_tool, calculator_tool])
|> Chain.llm(:openai, tools: :auto)
|> Chain.run(%{user_request: "What's the weather in Tokyo and convert 25°C to Fahrenheit?"})
# LLM automatically calls weather tool and calculator
```

### Conversational Memory

Build chatbots that remember context:

```elixir
# Personal assistant with memory
personal_assistant = Chain.new(
  system: "You are {{user_name}}'s personal assistant. Remember our conversation history.",
  user: "{{message}}"
)
|> Chain.with_memory(:conversation)
|> Chain.llm(:openai)

# Conversation with memory
personal_assistant 
|> Chain.with_session("user_123")
|> Chain.run(%{user_name: "Alice", message: "Schedule a meeting for tomorrow"})

personal_assistant
|> Chain.with_session("user_123")  
|> Chain.run(%{user_name: "Alice", message: "What time did we schedule it for?"})
# Remembers the previous scheduling request
```

### Content Generation Pipeline

Multi-stage content creation:

```elixir
# Blog post generator
"{{topic}}"
|> Chain.new()
|> Chain.prompt("Research and outline key points about: {{input}}")
|> Chain.llm(:openai, model: "gpt-4")
|> Chain.transform(fn outline -> "Write a detailed blog post based on: #{outline}" end)
|> Chain.llm(:anthropic, model: "claude-3-opus")
|> Chain.transform(fn draft -> "Edit and improve this draft: #{draft}" end)
|> Chain.llm(:openai, model: "gpt-4")
|> Chain.parse(:structured, schema: %{title: :string, content: :string, tags: [:string]})
|> Chain.run(%{topic: "sustainable energy solutions"})
```

### Code Analysis and Review

Automated code review pipeline:

```elixir
# Code review chain
"{{code}}"
|> Chain.new()
|> Chain.prompt("""
  Analyze this {{language}} code for:
  1. Bugs and potential issues
  2. Performance optimizations  
  3. Best practices adherence
  4. Security concerns
  
  Code: {{input}}
  """)
|> Chain.llm(:openai, model: "gpt-4")
|> Chain.transform(fn analysis -> "Suggest specific improvements: #{analysis}" end)
|> Chain.llm(:anthropic)
|> Chain.parse(:structured, schema: %{
  issues: [%{type: :string, severity: :string, description: :string}],
  suggestions: [:string],
  overall_score: :integer
})
|> Chain.run(%{code: python_function, language: "Python"})
```

### Multi-Language Support

Build international applications:

```elixir
# Multilingual customer support
customer_support = Chain.new(
  system: """
  You are a customer support agent for {{company}}.
  Respond in {{language}} with a {{tone}} tone.
  Company context: {{company_info}}
  """,
  user: "Customer inquiry: {{inquiry}}"
)
|> Chain.llm(:anthropic)
|> Chain.transform(fn response, vars -> 
  translate_if_needed(response, vars.language)
end)

# Handle inquiries in different languages
customer_support |> Chain.run(%{
  company: "TechCorp",
  language: "Spanish", 
  tone: "friendly",
  company_info: "We sell software solutions",
  inquiry: "My account is locked"
})

customer_support |> Chain.run(%{
  company: "TechCorp", 
  language: "Japanese",
  tone: "formal",
  company_info: "We sell software solutions", 
  inquiry: "Billing question"
})
```

### Batch Processing

Process multiple items efficiently:

```elixir
# Document summarizer
summarizer = Chain.new(
  system: "You are an expert at creating concise, accurate summaries",
  user: "Summarize this {{doc_type}}: {{content}}"
)
|> Chain.llm(:openai)
|> Chain.parse(:structured, schema: %{
  summary: :string,
  key_points: [:string],
  word_count: :integer
})

# Process multiple documents
documents = [
  %{type: "research paper", content: "..."},
  %{type: "news article", content: "..."},
  %{type: "legal brief", content: "..."}
]

summaries = documents
|> Task.async_stream(fn doc ->
  summarizer |> Chain.run(%{doc_type: doc.type, content: doc.content})
end, max_concurrency: 5)
|> Enum.map(fn {:ok, result} -> result end)
```

### Advanced Error Handling

Build resilient chains:

```elixir
# Fault-tolerant analysis chain
"{{complex_data}}"
|> Chain.new()
|> Chain.llm(:openai, retries: 3, backoff: :exponential)
|> Chain.on_error(fn 
  {:llm_error, :timeout} -> {:ok, "Analysis temporarily unavailable"}
  {:llm_error, :rate_limit} -> {:retry_after, 60}
  error -> {:fallback, "Error occurred: #{inspect(error)}"}
end)
|> Chain.llm(:anthropic)  # Fallback LLM
|> Chain.parse(:json, on_error: :return_raw)
|> Chain.run(%{complex_data: large_dataset})
```

### Parallel Processing

Execute multiple LLM calls simultaneously:

```elixir
# Parallel sentiment analysis
"{{text_to_analyze}}"
|> Chain.new()
|> Chain.parallel([
  # Different models analyze in parallel
  Chain.llm(:openai, model: "gpt-3.5-turbo"),
  Chain.llm(:anthropic, model: "claude-3-haiku"), 
  Chain.llm(:ollama, model: "llama2")
])
|> Chain.combine(fn [result1, result2, result3] ->
  aggregate_sentiment_scores([result1, result2, result3])
end)
|> Chain.run(%{text_to_analyze: "Customer feedback text"})
```

### Configuration-Driven Chains

Build flexible, configurable workflows:

```elixir
# Define chain configuration
analysis_config = %{
  system: "You are a {{analysis_type}} expert",
  user: "Analyze: {{content}}",
  steps: [
    {:llm, :openai, model: "gpt-4"},
    {:parse, :json},
    {:validate, :analysis_schema},
    {:transform, &format_analysis_result/1}
  ],
  fallback_llm: :anthropic,
  required_vars: [:analysis_type, :content]
}

# Create chain from configuration
analysis_chain = Chain.from_config(analysis_config)

# Use with different analysis types
analysis_chain |> Chain.run(%{analysis_type: "financial", content: earnings_report})
analysis_chain |> Chain.run(%{analysis_type: "sentiment", content: social_media_posts})
analysis_chain |> Chain.run(%{analysis_type: "technical", content: system_logs})
```

## Testing Your Chains

```elixir
defmodule MyApp.ChainTest do
  use ExUnit.Case
  import Chainex.Chain

  test "expert analysis handles different domains" do
    expert_chain = Chain.new(
      system: "You are a {{domain}} expert",
      user: "Explain {{topic}}"
    )
    |> Chain.llm(:mock)  # Use mock for testing
    
    # Test different domains
    tech_result = expert_chain |> Chain.run(%{domain: "technology", topic: "AI"})
    medical_result = expert_chain |> Chain.run(%{domain: "medical", topic: "vaccines"})
    
    assert {:ok, _} = tech_result
    assert {:ok, _} = medical_result
  end

  test "parsing handles malformed responses" do
    "Extract data"
    |> Chain.new()
    |> Chain.llm(:mock_malformed)
    |> Chain.parse(:json, on_error: :return_raw)
    |> Chain.run()
    |> case do
      {:ok, raw_text} -> assert is_binary(raw_text)
      {:error, _} -> flunk("Should have returned raw text on parse error")
    end
  end
end
```

## Configuration

Configure LLM providers in your `config/config.exs`:

```elixir
config :chainex,
  providers: %{
    openai: [
      api_key: System.get_env("OPENAI_API_KEY"),
      base_url: "https://api.openai.com/v1",
      default_model: "gpt-4"
    ],
    anthropic: [
      api_key: System.get_env("ANTHROPIC_API_KEY"), 
      base_url: "https://api.anthropic.com/v1",
      default_model: "claude-3-opus-20240229"
    ],
    ollama: [
      base_url: "http://localhost:11434",
      default_model: "llama2"
    ]
  },
  default_provider: :openai,
  timeout: 30_000,
  retries: 3
```

## Advanced Features

### Custom Parsers

Create domain-specific parsers:

```elixir
# Custom email parser
email_parser = fn text ->
  emails = Regex.scan(~r/[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}/, text)
  {:ok, List.flatten(emails)}
end

"Find emails in: {{text}}"
|> Chain.new()
|> Chain.llm(:openai)
|> Chain.parse(email_parser)
|> Chain.run(%{text: "Contact john@example.com or mary@company.org"})
# => {:ok, ["john@example.com", "mary@company.org"]}
```

### Custom Tools

Integrate with external APIs:

```elixir
weather_tool = Tool.new(
  name: "get_weather",
  description: "Get current weather for a location",
  parameters: %{
    location: %{type: :string, required: true},
    units: %{type: :string, enum: ["celsius", "fahrenheit"], default: "celsius"}
  },
  function: fn %{location: location, units: units} ->
    # Call weather API
    WeatherAPI.get_current(location, units)
  end
)

"What's the weather like?"
|> Chain.new()
|> Chain.with_tools([weather_tool])
|> Chain.tool(:get_weather, location: "{{city}}", units: "{{units}}")
|> Chain.run(%{city: "San Francisco", units: "celsius"})
```

### Chain Composition

Build complex workflows from simpler chains:

```elixir
# Reusable components
research_chain = Chain.new("Research {{topic}}")
                |> Chain.llm(:openai)

writing_chain = Chain.new("Write about {{topic}} based on: {{research}}")
               |> Chain.llm(:anthropic)

editing_chain = Chain.new("Edit and improve: {{draft}}")
               |> Chain.llm(:openai)

# Compose them
full_pipeline = Chain.new("{{topic}}")
               |> Chain.sub_chain(research_chain, %{topic: "{{input}}"})
               |> Chain.sub_chain(writing_chain, %{topic: "{{input}}", research: "{{:from_previous}}"})
               |> Chain.sub_chain(editing_chain, %{draft: "{{:from_previous}}"})

full_pipeline |> Chain.run(%{topic: "sustainable agriculture"})
```

## Performance Tips

1. **Reuse chains**: Build once, run many times
2. **Use appropriate models**: Not every task needs GPT-4
3. **Batch similar requests**: Process multiple items together
4. **Cache results**: Use memory for repeated queries
5. **Stream responses**: For long-running generations
6. **Parallel execution**: Run independent steps concurrently

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Links

- 📖 [Documentation](https://hexdocs.pm/chainex)
- 🐛 [Issues](https://github.com/your-org/chainex/issues)  
- 💬 [Discussions](https://github.com/your-org/chainex/discussions)

---

Built with ❤️ in Elixir. Perfect for building the next generation of AI-powered applications.

