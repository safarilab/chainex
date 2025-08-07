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
  # Take the insights from OpenAI and prepare them for critical review
  "Previous analysis: #{insights}. Now provide a critical review and identify potential biases or gaps."
end)
|> Chain.llm(:anthropic, model: "claude-3-opus") 
|> Chain.transform(fn review ->
  # Combine previous review with synthesis instructions for final LLM
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
  # Combine all expert analyses into a single prompt for synthesis
  combined_text = Enum.join(analyses, "\n\n")
  "Synthesize these expert analyses: #{combined_text}"
end)
|> Chain.llm(:anthropic)
|> Chain.run()
```

### Smart Data Processing with JSON Maps and Structs

Extract and validate complex structured data with flexible output formats:

```elixir
# Define struct modules for type safety
defmodule CompanyAnalysis do
  defstruct [:company, :financials, :key_metrics, :analysis_timestamp]
  
  defmodule Company do
    defstruct [:name, :industry, :founded, :headquarters]
    
    defmodule Headquarters do
      defstruct [:city, :country, :coordinates]
      
      defmodule Coordinates do
        defstruct [:lat, :lng]
      end
    end
  end
  
  defmodule Financials do
    defstruct [:revenue, :employees, :funding_rounds]
    
    defmodule Revenue do
      defstruct [:amount, :currency, :period]
    end
    
    defmodule FundingRound do
      defstruct [:round, :amount, :date, :investors]
    end
  end
  
  defmodule KeyMetrics do
    defstruct [:market_share, :growth_rate, :customer_satisfaction, :competitive_advantages]
  end
end

# Use struct parsing for strong typing
"{{company_info}}"
|> Chain.new()
|> Chain.prompt("Analyze the following company information: {{input}}")
|> Chain.llm(:openai)
|> Chain.parse(:struct, CompanyAnalysis)
|> Chain.transform(fn analysis -> 
  # Now working with strongly typed structs
  %{analysis | analysis_timestamp: DateTime.utc_now()}
end)
|> Chain.run(%{company_info: "Tesla Inc. is an electric vehicle manufacturer..."})
# Returns: {:ok, %CompanyAnalysis{company: %CompanyAnalysis.Company{...}}}

# Alternative: Map schema for simpler validation
company_analysis_schema = %{
  company: %{
    name: :string,
    industry: :string,
    founded: :integer,
    headquarters: %{
      city: :string,
      country: :string,
      coordinates: %{
        lat: :float,
        lng: :float
      }
    }
  },
  financials: %{
    revenue: %{
      amount: :float,
      currency: :string,
      period: :string
    },
    employees: :integer,
    funding_rounds: [%{
      round: :string,
      amount: :float,
      date: :string,
      investors: [:string]
    }]
  },
  key_metrics: %{
    market_share: :float,
    growth_rate: :float,
    customer_satisfaction: :float,
    competitive_advantages: [:string]
  }
}

"{{company_info}}"
|> Chain.new()
|> Chain.prompt("Analyze the following company information: {{input}}")
|> Chain.llm(:openai)
|> Chain.parse(:json, company_analysis_schema)
|> Chain.transform(fn analysis -> 
  # Working with validated map data
  %{
    company: normalize_company_data(analysis["company"]),
    financials: calculate_financial_ratios(analysis["financials"]),
    key_metrics: enrich_metrics(analysis["key_metrics"]),
    analysis_timestamp: DateTime.utc_now()
  }
end)
|> Chain.run(%{company_info: "Tesla Inc. is an electric vehicle manufacturer..."})
# Returns: {:ok, %{"company" => %{"name" => "Tesla Inc", ...}}}

# Product catalog with struct parsing
defmodule ProductCatalog do
  defstruct [:products, :metadata]
  
  defmodule Product do
    defstruct [:id, :name, :category, :price, :specifications, :availability]
    
    defmodule Price do
      defstruct [:amount, :currency, :discount]
      
      defmodule Discount do
        defstruct [:percentage, :valid_until]
      end
    end
    
    defmodule Specifications do
      defstruct [:dimensions, :weight, :features, :compatibility]
      
      defmodule Dimensions do
        defstruct [:length, :width, :height, :unit]
      end
      
      defmodule Weight do
        defstruct [:value, :unit]
      end
      
      defmodule Compatibility do
        defstruct [:platform, :versions]
      end
    end
    
    defmodule Availability do
      defstruct [:in_stock, :quantity, :warehouses]
      
      defmodule Warehouse do
        defstruct [:location, :stock_level]
      end
    end
  end
  
  defmodule Metadata do
    defstruct [:total_products, :last_updated, :data_source]
  end
end

"{{catalog_data}}"
|> Chain.new()
|> Chain.llm(:openai)
|> Chain.parse(:struct, ProductCatalog)
|> Chain.transform(fn catalog ->
  # Process nested struct data with type safety
  processed_products = catalog.products
  |> Enum.map(fn product ->
    %{product | 
      name: String.trim(product.name),
      price: normalize_price_struct(product.price),
      specifications: flatten_spec_struct(product.specifications)
    }
  end)
  
  %{catalog | 
    products: processed_products,
    metadata: %{catalog.metadata | last_updated: DateTime.utc_now()}
  }
end)
|> Chain.run(%{catalog_data: "Extensive product listing with specifications..."})

# Alternative: Map-based product schema
product_schema = %{
  products: [%{
    id: :string,
    name: :string,
    category: :string,
    price: %{
      amount: :float,
      currency: :string,
      discount: %{
        percentage: :float,
        valid_until: :string
      }
    },
    specifications: %{
      dimensions: %{
        length: :float,
        width: :float,
        height: :float,
        unit: :string
      },
      weight: %{
        value: :float,
        unit: :string
      },
      features: [:string],
      compatibility: [%{
        platform: :string,
        versions: [:string]
      }]
    },
    availability: %{
      in_stock: :boolean,
      quantity: :integer,
      warehouses: [%{
        location: :string,
        stock_level: :integer
      }]
    }
  }],
  metadata: %{
    total_products: :integer,
    last_updated: :string,
    data_source: :string
  }
}

"{{catalog_data}}"
|> Chain.new()
|> Chain.llm(:openai)
|> Chain.parse(:json, schema: product_schema)
|> Chain.transform(fn catalog ->
  # Process nested product data
  processed_products = catalog["products"]
  |> Enum.map(fn product ->
    %{
      id: product["id"],
      name: String.trim(product["name"]),
      normalized_price: normalize_pricing(product["price"]),
      specs: flatten_specifications(product["specifications"]),
      stock_info: calculate_total_stock(product["availability"])
    }
  end)
  
  %{
    products: processed_products,
    summary: generate_catalog_summary(processed_products),
    processed_at: DateTime.utc_now()
  }
end)
|> Chain.run(%{catalog_data: "Extensive product listing with specifications..."})

# Nested user profile extraction
user_profile_schema = %{
  user: %{
    personal: %{
      name: %{
        first: :string,
        last: :string,
        preferred: :string
      },
      contact: %{
        email: :string,
        phone: %{
          primary: :string,
          secondary: :string
        },
        address: %{
          street: :string,
          city: :string,
          state: :string,
          postal_code: :string,
          country: :string
        }
      }
    },
    professional: %{
      current_position: %{
        title: :string,
        company: :string,
        department: :string,
        start_date: :string
      },
      experience: [%{
        title: :string,
        company: :string,
        duration: :string,
        responsibilities: [:string]
      }],
      skills: [%{
        name: :string,
        proficiency: :string,
        years_experience: :integer,
        certifications: [:string]
      }]
    },
    preferences: %{
      communication: %{
        preferred_method: :string,
        timezone: :string,
        availability: %{
          days: [:string],
          hours: %{
            start: :string,
            end: :string
          }
        }
      },
      interests: [:string],
      goals: [%{
        category: :string,
        description: :string,
        target_date: :string,
        priority: :string
      }]
    }
  }
}

"{{user_data}}"
|> Chain.new()
|> Chain.llm(:openai)
|> Chain.parse(:json, schema: user_profile_schema)
|> Chain.transform(fn profile ->
  # Extract and structure nested user information
  user = profile["user"]
  
  %{
    id: generate_user_id(user["personal"]["name"]),
    display_name: get_preferred_name(user["personal"]["name"]),
    contact_score: calculate_contact_completeness(user["personal"]["contact"]),
    career_level: assess_career_level(user["professional"]),
    skill_matrix: build_skill_matrix(user["professional"]["skills"]),
    engagement_profile: analyze_preferences(user["preferences"]),
    data_quality: assess_profile_quality(user)
  }
end)
|> Chain.run(%{user_data: "Complete user profile information including contact details..."})
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
|> Chain.transform(fn outline -> 
  # Convert outline into detailed writing instructions
  "Write a detailed blog post based on: #{outline}"
end)
|> Chain.llm(:anthropic, model: "claude-3-opus")
|> Chain.transform(fn draft -> 
  # Prepare draft for editing phase with specific improvement instructions
  "Edit and improve this draft for clarity, flow, and engagement: #{draft}"
end)
|> Chain.llm(:openai, model: "gpt-4")
|> Chain.parse(:json, schema: %{title: :string, content: :string, tags: [:string]})
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
|> Chain.transform(fn analysis -> 
  # Take the analysis and prepare it for improvement suggestions
  "Based on this code analysis, suggest specific improvements: #{analysis}"
end)
|> Chain.llm(:anthropic)
|> Chain.parse(:json, schema: %{
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
  # Translate response if target language is not English
  if vars.language != "English" do
    # Call translation service or LLM for translation
    "Translate this response to #{vars.language}: #{response}"
  else
    response
  end
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
|> Chain.parse(:json, schema: %{
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
  # Aggregate sentiment scores from multiple models
  scores = [result1, result2, result3]
  |> Enum.map(&extract_sentiment_score/1)
  |> Enum.filter(&is_number/1)
  
  avg_score = Enum.sum(scores) / length(scores)
  confidence = calculate_confidence(scores)
  
  %{sentiment_score: avg_score, confidence: confidence, individual_scores: scores}
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

