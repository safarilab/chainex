# Chainex Chain Module Design Specification

## Overview

The Chainex Chain module provides a fluent, pipeline-based API for chaining LLM operations together, similar to Python's LangChain but leveraging Elixir's pipe operator and functional programming principles. The key innovations are:

- **Runtime Variable Resolution**: Variables are passed at execution time, not build time
- **System Prompt First-Class**: System prompts are part of the chain definition
- **Build Once, Run Many**: Chain definitions are reusable templates

## Core Design Principles

1. **Build Once, Run Many**: Chain definitions are reusable templates
2. **Runtime Variables**: Variables are passed at execution time, not build time
3. **System Prompt First-Class**: System prompts are part of chain identity
4. **Pipe-Friendly**: Leverages Elixir's pipe operator for fluent APIs
5. **Immutable**: Each operation returns a new chain
6. **Simple to Complex**: Progressive complexity from basic to advanced features
7. **Clear Separation**: Steps are data structures until `run()` is called

## API Design (Progressive Complexity)

### Level 1: Basic Chain Creation

```elixir
# Simple user message only
chain = Chain.new("What is {{topic}}?")
|> Chain.llm(:openai)

result = chain |> Chain.run(%{topic: "AI"})
# Returns: {:ok, "AI is..."}

# With explicit system prompt
chain = Chain.new(
  system: "You are a helpful medical assistant",
  user: "Explain {{condition}} in simple terms"
)
|> Chain.llm(:openai)

chain |> Chain.run(%{condition: "diabetes"})
# Returns: {:ok, "Diabetes is a condition where..."}
```

### Level 2: Dynamic System Prompts

```elixir
# System prompt with variables
chain = Chain.new(
  system: "You are a {{role}} expert with {{years}} years of experience",
  user: "Analyze {{topic}}"
)
|> Chain.llm(:openai)

# Reusable with different expert perspectives
chain |> Chain.run(%{role: "financial", years: 15, topic: "crypto trends"})
chain |> Chain.run(%{role: "medical", years: 10, topic: "telemedicine"})

# Template with defaults
chain = Chain.new(
  system: "You are a {{role:helpful}} assistant",
  user: "Help with {{task}}"
)
|> Chain.llm(:openai)

chain |> Chain.run(%{task: "planning"})  # role defaults to "helpful"
```

### Level 3: Transform Steps

```elixir
# Simple transformations
chain = Chain.new("Generate {{count}} {{items}}")
|> Chain.llm(:openai)
|> Chain.transform(&String.upcase/1)
|> Chain.transform(fn result -> "RESULT: #{result}" end)

chain |> Chain.run(%{count: 3, items: "colors"})

# Context-aware transforms with access to variables
chain = Chain.new(
  system: "You are a creative writer",
  user: "Write about {{topic}}"
)
|> Chain.llm(:openai)
|> Chain.transform(fn result, vars -> 
  "Story about #{vars.topic}: #{result}" 
end)

chain |> Chain.run(%{topic: "space exploration"})
```

### Level 4: Prompt Templates

```elixir
# Explicit prompt steps
chain = Chain.new("raw input")
|> Chain.prompt("{{system_role}}\n\nAnalyze: {{input}}\nFocus: {{focus}}")
|> Chain.llm(:openai)

chain |> Chain.run(%{
  system_role: "You are a data analyst",
  input: "sales data",
  focus: "trends"
})

# Structured prompts
prompt = Prompt.new(
  system: "You are a {{role}} expert",
  user: "Explain {{topic}} in {{style}} terms"
)

chain = Chain.new("initial input")
|> Chain.prompt(prompt)
|> Chain.llm(:openai)

chain |> Chain.run(%{
  role: "medical",
  topic: "diabetes", 
  style: "simple"
})
```

### Level 5: Multiple LLMs

```elixir
# Chain different LLMs with shared variables
chain = Chain.new(
  system: "You are an analyst",
  user: "Analyze {{subject}} from {{perspective}}"
)
|> Chain.llm(:openai)          # First analysis
|> Chain.transform(fn result, vars -> 
  "Critique the analysis of #{vars.subject}: #{result}" 
end)
|> Chain.llm(:anthropic)       # Second opinion
|> Chain.transform(fn result, vars ->
  "Final synthesis about #{vars.subject}: #{result}"
end)
|> Chain.llm(:ollama, model: "llama2")  # Final synthesis

chain |> Chain.run(%{
  subject: "climate change",
  perspective: "economic impact"
})
```

### Level 6: Tool Integration

```elixir
# Simple tool calls with runtime parameters
chain = Chain.new("Get weather information")
|> Chain.tool(:weather, location: "{{city}}", units: "{{units}}")
|> Chain.transform(fn weather, vars -> 
  "Weather report for #{vars.city}: #{weather}" 
end)
|> Chain.llm(:openai)

chain |> Chain.run(%{city: "Paris", units: "celsius"})
chain |> Chain.run(%{city: "Tokyo", units: "fahrenheit"})

# Tool parameters from previous results
chain = Chain.new("Calculate expenses")
|> Chain.tool(:calculator, operation: "sum", values: "{{:from_input}}")
|> Chain.transform(fn total -> "Total: $#{total}" end)
|> Chain.llm(:openai)

chain |> Chain.run([100, 250, 75])  # Input becomes tool parameter
```

### Level 7: Output Parsers with JSON Maps and Structs

```elixir
# Simple JSON parsing (returns map)
chain = Chain.new(
  system: "You are a data extractor",
  user: "Extract info from: {{text}}"
)
|> Chain.llm(:openai)
|> Chain.parse(:json)

chain |> Chain.run(%{text: "John Doe, age 30, from NYC"})
# Returns: {:ok, %{"name" => "John Doe", "age" => 30, "city" => "NYC"}}

# JSON parsing with map schema validation
person_schema = %{
  name: :string,
  age: :integer,
  city: :string,
  skills: [:string]
}

chain = Chain.new("Extract person info: {{text}}")
|> Chain.llm(:openai)
|> Chain.parse(:json, person_schema)

chain |> Chain.run(%{text: "John Doe, 30 years old, lives in NYC, knows Python and Elixir"})
# Returns: {:ok, %{"name" => "John Doe", "age" => 30, "city" => "NYC", "skills" => ["Python", "Elixir"]}}

# Struct-based parsing for type safety
defmodule CompanyAnalysis do
  defstruct [
    :company,
    :financials,
    :metrics
  ]
  
  defmodule Company do
    defstruct [:name, :industry, :headquarters]
    
    defmodule Headquarters do
      defstruct [:city, :country, :coordinates]
      
      defmodule Coordinates do
        defstruct [:latitude, :longitude]
      end
    end
  end
  
  defmodule Financials do
    defstruct [:revenue, :employees, :funding_rounds]
    
    defmodule Revenue do
      defstruct [:amount, :currency]
    end
    
    defmodule FundingRound do
      defstruct [:series, :amount, :investors]
    end
  end
  
  defmodule Metrics do
    defstruct [:growth_rate, :market_share]
  end
end

# Parse directly into nested structs
chain = Chain.new("Analyze company: {{company_info}}")
|> Chain.llm(:openai)
|> Chain.parse(:struct, CompanyAnalysis)

chain |> Chain.run(%{company_info: "Tesla Inc. based in Austin, Texas..."})
# Returns: {:ok, %CompanyAnalysis{company: %CompanyAnalysis.Company{...}, financials: %CompanyAnalysis.Financials{...}}}

# Mixed approach - map schema with struct parsing
company_map_schema = %{
  company: %{
    name: :string,
    industry: :string,
    headquarters: %{
      city: :string,
      country: :string,
      coordinates: %{
        latitude: :float,
        longitude: :float
      }
    }
  },
  financials: %{
    revenue: %{
      amount: :float,
      currency: :string
    },
    employees: :integer,
    funding_rounds: [%{
      series: :string,
      amount: :float,
      investors: [:string]
    }]
  },
  metrics: %{
    growth_rate: :float,
    market_share: :float
  }
}

# Parse with map schema but convert to struct
chain = Chain.new("Analyze company: {{company_info}}")
|> Chain.llm(:openai)
|> Chain.parse(:json, company_map_schema)
|> Chain.transform(fn data -> 
  # Convert validated map to struct
  struct(CompanyAnalysis, data)
end)

# Returns: {:ok, %CompanyAnalysis{...}} with validation

# Array of objects with nested properties
product_catalog_schema = %{
  products: [%{
    id: :string,
    name: :string,
    pricing: %{
      base_price: %{
        amount: :float,
        currency: :string
      },
      discounts: [%{
        type: :string,
        percentage: :float,
        conditions: [:string]
      }]
    },
    specifications: %{
      dimensions: %{
        length: :float,
        width: :float,
        height: :float,
        unit: :string
      },
      features: [%{
        category: :string,
        items: [:string]
      }]
    }
  }],
  catalog_info: %{
    total_count: :integer,
    last_updated: :string
  }
}

chain = Chain.new("Extract product catalog: {{catalog_data}}")
|> Chain.llm(:openai)
|> Chain.parse(:json, schema: product_catalog_schema)

# User profile with deeply nested preferences
user_schema = %{
  profile: %{
    personal: %{
      name: %{
        first: :string,
        last: :string
      },
      contact: %{
        email: :string,
        phones: [%{
          type: :string,
          number: :string,
          verified: :boolean
        }]
      }
    },
    preferences: %{
      notifications: %{
        email: %{
          marketing: :boolean,
          updates: :boolean,
          frequency: :string
        },
        push: %{
          enabled: :boolean,
          quiet_hours: %{
            start: :string,
            end: :string
          }
        }
      },
      privacy: %{
        profile_visibility: :string,
        data_sharing: [%{
          partner: :string,
          allowed: :boolean,
          categories: [:string]
        }]
      }
    }
  }
}

chain = Chain.new("Extract user profile: {{user_data}}")
|> Chain.llm(:openai)
|> Chain.parse(:json, schema: user_schema)

# Custom nested parsers
financial_parser = fn text ->
  # Extract complex financial data with validation
  case Jason.decode(text) do
    {:ok, data} -> 
      validate_financial_structure(data)
    {:error, _} -> 
      {:error, :invalid_financial_json}
  end
end

chain = Chain.new("Generate financial report: {{data}}")
|> Chain.llm(:openai)
|> Chain.parse(financial_parser)
```

### Level 8: Memory and Context

```elixir
# Conversation memory
chat_chain = Chain.new(
  system: "You are {{user_name}}'s assistant",
  user: "{{message}}"
)
|> Chain.with_memory(:conversation)
|> Chain.llm(:openai)

# In application
def handle_message(message, user_id) do
  chat_chain 
  |> Chain.with_session(user_id)
  |> Chain.run(%{user_name: "Alice", message: message})
end

# Contextual memory with variables
analysis_chain = Chain.new(
  system: "Continue analysis of {{project}}",
  user: "New data: {{data}}"
)
|> Chain.with_memory(:project_context)
|> Chain.llm(:openai)
```

### Level 9: Advanced Tool Usage (LLM-Driven)

```elixir
# Define tools first - weather tool
weather_tool = Tool.new(
  name: "get_weather",
  description: "Get current weather for a location",
  parameters: %{
    location: %{type: "string", description: "City name or coordinates", required: true},
    units: %{type: "string", enum: ["celsius", "fahrenheit"], default: "celsius"}
  },
  function: fn params ->
    case WeatherAPI.get_current(params.location, params.units) do
      {:ok, weather} -> 
        "Temperature: #{weather.temp}°#{String.upcase(params.units)}, Conditions: #{weather.description}"
      {:error, reason} -> 
        "Weather unavailable: #{reason}"
    end
  end
)

# Calculator tool
calculator_tool = Tool.new(
  name: "calculate",
  description: "Perform mathematical calculations",
  parameters: %{
    expression: %{type: "string", description: "Mathematical expression to evaluate", required: true},
    precision: %{type: "integer", default: 2, description: "Decimal places for result"}
  },
  function: fn params ->
    try do
      result = Code.eval_string(params.expression) |> elem(0)
      Float.round(result, params.precision)
    rescue
      _ -> "Invalid mathematical expression"
    end
  end
)

# Calendar tool
calendar_tool = Tool.new(
  name: "check_calendar",
  description: "Check calendar events for a specific date",
  parameters: %{
    date: %{type: "string", description: "Date in YYYY-MM-DD format", required: true},
    user_id: %{type: "string", description: "User identifier", required: true}
  },
  function: fn params ->
    case CalendarAPI.get_events(params.user_id, params.date) do
      {:ok, events} when events == [] ->
        "No events scheduled for #{params.date}"
      {:ok, events} ->
        event_list = events
        |> Enum.map(fn event -> "- #{event.title} at #{event.time}" end)
        |> Enum.join("\n")
        "Events for #{params.date}:\n#{event_list}"
      {:error, reason} ->
        "Calendar unavailable: #{reason}"
    end
  end
)

# LLM decides which tools to call
chain = Chain.new(
  system: "You have access to tools: {{available_tools}}. Use them when needed.",
  user: "{{request}}"
)
|> Chain.with_tools([weather_tool, calculator_tool, calendar_tool])
|> Chain.llm(:openai, tools: :auto)

chain |> Chain.run(%{
  available_tools: "weather, calculator, calendar",
  request: "What's weather in NYC and 15% tip on $47.50?"
})

# Filtered tools based on context
planning_chain = Chain.new(
  system: "Help with {{task_type}}",
  user: "{{request}}"
)
|> Chain.with_tools([weather_tool, calendar_tool])
|> Chain.llm(:openai, tools: :auto)

planning_chain |> Chain.run(%{
  task_type: "planning my day",
  request: "Help me plan tomorrow"
})
```

### Tool Structure Definition

```elixir
defmodule Chainex.Tool do
  @moduledoc """
  Represents a tool that can be called by LLMs during chain execution.
  Tools encapsulate external functionality and API integrations.
  """
  
  defstruct [
    :name,
    :description,
    :parameters,
    :function,
    :timeout,
    :retries,
    :metadata
  ]
  
  @type parameter_spec :: %{
    type: String.t(),
    description: String.t(),
    required: boolean(),
    enum: [String.t()] | nil,
    default: any(),
    format: String.t() | nil,
    minimum: number() | nil,
    maximum: number() | nil,
    properties: %{String.t() => parameter_spec()} | nil
  }
  
  @type t :: %__MODULE__{
    name: String.t(),
    description: String.t(),
    parameters: %{String.t() => parameter_spec()},
    function: function(),
    timeout: integer(),
    retries: integer(),
    metadata: map()
  }
  
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.fetch!(opts, :description),
      parameters: Keyword.get(opts, :parameters, %{}),
      function: Keyword.fetch!(opts, :function),
      timeout: Keyword.get(opts, :timeout, 30_000),
      retries: Keyword.get(opts, :retries, 3),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
  
  @spec call(t(), map()) :: {:ok, any()} | {:error, any()}
  def call(%__MODULE__{} = tool, params) do
    with {:ok, validated_params} <- validate_parameters(tool.parameters, params),
         {:ok, result} <- execute_with_timeout(tool.function, validated_params, tool.timeout) do
      {:ok, result}
    end
  end
  
  # Complex tool examples
  
  # Database query tool
  database_tool = Tool.new(
    name: "query_database",
    description: "Execute database queries with safety checks",
    parameters: %{
      "query" => %{
        type: "string",
        description: "SQL query to execute",
        required: true
      },
      "max_rows" => %{
        type: "integer", 
        description: "Maximum rows to return",
        default: 100,
        maximum: 1000
      },
      "timeout" => %{
        type: "integer",
        description: "Query timeout in milliseconds", 
        default: 30000
      }
    },
    function: fn params ->
      case DatabaseAPI.execute_safe(params["query"], params["max_rows"], params["timeout"]) do
        {:ok, results} -> format_query_results(results)
        {:error, reason} -> "Query failed: #{reason}"
      end
    end,
    timeout: 45_000,
    retries: 1
  )
  
  # File system tool
  file_tool = Tool.new(
    name: "read_file",
    description: "Read contents of a file safely",
    parameters: %{
      "path" => %{
        type: "string",
        description: "File path to read",
        required: true
      },
      "encoding" => %{
        type: "string",
        description: "File encoding",
        enum: ["utf8", "latin1", "ascii"],
        default: "utf8"
      },
      "max_size" => %{
        type: "integer",
        description: "Maximum file size in bytes",
        default: 1_048_576,  # 1MB
        maximum: 10_485_760  # 10MB
      }
    },
    function: fn params ->
      case FileAPI.read_safe(params["path"], params["encoding"], params["max_size"]) do
        {:ok, content} -> content
        {:error, :file_too_large} -> "File exceeds maximum size limit"
        {:error, :not_found} -> "File not found: #{params["path"]}"
        {:error, reason} -> "File read error: #{reason}"
      end
    end
  )
  
  # HTTP request tool
  http_tool = Tool.new(
    name: "http_request",
    description: "Make HTTP requests to external APIs",
    parameters: %{
      "url" => %{
        type: "string",
        description: "URL to request",
        required: true,
        format: "uri"
      },
      "method" => %{
        type: "string",
        description: "HTTP method",
        enum: ["GET", "POST", "PUT", "DELETE"],
        default: "GET"
      },
      "headers" => %{
        type: "object",
        description: "Request headers",
        properties: %{},
        default: %{}
      },
      "body" => %{
        type: "string",
        description: "Request body"
      },
      "timeout" => %{
        type: "integer",
        description: "Request timeout in milliseconds",
        default: 10000,
        maximum: 30000
      }
    },
    function: fn params ->
      case HTTPClient.request(params["method"], params["url"], params["body"], params["headers"], params["timeout"]) do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          body
        {:ok, %{status: status}} ->
          "HTTP request failed with status: #{status}"
        {:error, reason} ->
          "HTTP request error: #{reason}"
      end
    end
  )
end
```

### Advanced Tool Usage Patterns

```elixir
# 1. Tool Chaining - Output of one tool feeds into another
search_tool = Tool.new(
  name: "search_web",
  description: "Search the web for information",
  parameters: %{
    "query" => %{type: "string", required: true},
    "max_results" => %{type: "integer", default: 5}
  },
  function: fn params ->
    SearchAPI.search(params["query"], params["max_results"])
  end
)

summarize_tool = Tool.new(
  name: "summarize_text",
  description: "Summarize long text content",
  parameters: %{
    "text" => %{type: "string", required: true},
    "max_words" => %{type: "integer", default: 100}
  },
  function: fn params ->
    TextAPI.summarize(params["text"], params["max_words"])
  end
)

# Chain that searches then summarizes
research_chain = Chain.new(
  system: "You are a research assistant. Use search to find information, then summarize key findings.",
  user: "Research: {{topic}}"
)
|> Chain.with_tools([search_tool, summarize_tool])
|> Chain.llm(:openai, tools: :auto)

research_chain |> Chain.run(%{topic: "quantum computing breakthroughs 2024"})
# LLM will: 1) Call search_tool, 2) Call summarize_tool with search results

# 2. Conditional Tool Usage - Tools only available in certain contexts
admin_tools = [
  Tool.new(
    name: "delete_user",
    description: "Delete a user account (admin only)",
    parameters: %{"user_id" => %{type: "string", required: true}},
    function: fn params ->
      if authorized?(:admin) do
        UserAPI.delete(params["user_id"])
      else
        {:error, "Unauthorized: Admin access required"}
      end
    end
  ),
  Tool.new(
    name: "modify_permissions",
    description: "Modify user permissions (admin only)",
    parameters: %{
      "user_id" => %{type: "string", required: true},
      "permissions" => %{type: "array", items: %{type: "string"}}
    },
    function: fn params ->
      if authorized?(:admin) do
        PermissionAPI.update(params["user_id"], params["permissions"])
      else
        {:error, "Unauthorized: Admin access required"}
      end
    end
  )
]

# Dynamically select tools based on user role
def create_chain_for_user(user) do
  tools = case user.role do
    :admin -> admin_tools ++ basic_tools
    :moderator -> moderation_tools ++ basic_tools
    _ -> basic_tools
  end
  
  Chain.new(
    system: "You are a helpful assistant with role: {{role}}",
    user: "{{request}}"
  )
  |> Chain.with_tools(tools)
  |> Chain.llm(:openai, tools: :auto)
end

# 3. Tool with Complex Return Types
data_analysis_tool = Tool.new(
  name: "analyze_dataset",
  description: "Perform statistical analysis on dataset",
  parameters: %{
    "data_source" => %{type: "string", required: true},
    "analysis_type" => %{
      type: "string", 
      enum: ["descriptive", "correlation", "regression", "clustering"],
      required: true
    },
    "options" => %{
      type: "object",
      properties: %{
        "confidence_level" => %{type: "number", default: 0.95},
        "include_visualizations" => %{type: "boolean", default: false}
      }
    }
  },
  function: fn params ->
    result = DataAnalyzer.analyze(
      params["data_source"],
      params["analysis_type"],
      params["options"]
    )
    
    # Return structured data that LLM can interpret
    %{
      summary: result.summary,
      statistics: result.stats,
      insights: result.insights,
      visualization_urls: result.charts,
      confidence: result.confidence_score
    }
  end
)

# 4. Streaming Tool Results
streaming_tool = Tool.new(
  name: "generate_report",
  description: "Generate a detailed report (streams results)",
  parameters: %{
    "topic" => %{type: "string", required: true},
    "sections" => %{type: "array", items: %{type: "string"}}
  },
  function: fn params ->
    # Return a stream for long-running operations
    Stream.resource(
      fn -> ReportGenerator.start(params["topic"], params["sections"]) end,
      fn state ->
        case ReportGenerator.next_chunk(state) do
          {:ok, chunk, new_state} -> {[chunk], new_state}
          :done -> {:halt, state}
        end
      end,
      fn state -> ReportGenerator.cleanup(state) end
    )
  end
)

# 5. Tool with Side Effects and Confirmation
email_tool = Tool.new(
  name: "send_email",
  description: "Send an email (requires confirmation)",
  parameters: %{
    "to" => %{type: "array", items: %{type: "string"}, required: true},
    "subject" => %{type: "string", required: true},
    "body" => %{type: "string", required: true},
    "cc" => %{type: "array", items: %{type: "string"}, default: []},
    "attachments" => %{type: "array", items: %{type: "string"}, default: []}
  },
  function: fn params ->
    # Generate preview first
    preview = EmailAPI.preview(params)
    
    # In production, this might trigger a confirmation UI
    case confirm_action?("send_email", preview) do
      true -> 
        case EmailAPI.send(params) do
          {:ok, message_id} -> "Email sent successfully. Message ID: #{message_id}"
          {:error, reason} -> "Failed to send email: #{reason}"
        end
      false ->
        "Email cancelled by user"
    end
  end,
  metadata: %{
    requires_confirmation: true,
    side_effects: [:external_communication]
  }
)

# 6. Tool Execution Strategies
chain = Chain.new(
  system: "You are an AI assistant with access to various tools",
  user: "{{request}}"
)
|> Chain.with_tools(all_tools)
|> Chain.llm(:openai, 
  tools: :auto,           # Let LLM decide when to use tools
  tool_choice: "auto",    # Can be "auto", "none", or specific tool name
  parallel_tool_calls: true  # Allow multiple tools in parallel
)

# Force specific tool usage
chain_with_forced_tool = Chain.new("Analyze this data")
|> Chain.with_tools([data_analysis_tool])
|> Chain.llm(:openai, 
  tool_choice: %{type: "function", function: %{name: "analyze_dataset"}}
)

# 7. Tool Result Processing
chain_with_processing = Chain.new("Get weather and format nicely")
|> Chain.with_tools([weather_tool])
|> Chain.llm(:openai, tools: :auto)
|> Chain.transform(fn result ->
  # Post-process tool results
  case result do
    %{tool_calls: tool_results} ->
      formatted = tool_results
      |> Enum.map(&format_tool_result/1)
      |> Enum.join("\n\n")
      
      "Here's what I found:\n#{formatted}"
    _ -> result
  end
end)

# 8. Tool with State Management
stateful_conversation_tool = Tool.new(
  name: "manage_conversation",
  description: "Manage conversation state and history",
  parameters: %{
    "action" => %{
      type: "string",
      enum: ["save", "retrieve", "clear", "summarize"],
      required: true
    },
    "session_id" => %{type: "string", required: true},
    "data" => %{type: "object"}
  },
  function: fn params ->
    case params["action"] do
      "save" ->
        ConversationStore.save(params["session_id"], params["data"])
        "Conversation saved"
      
      "retrieve" ->
        case ConversationStore.get(params["session_id"]) do
          {:ok, history} -> Jason.encode!(history)
          {:error, :not_found} -> "No conversation history found"
        end
      
      "clear" ->
        ConversationStore.delete(params["session_id"])
        "Conversation history cleared"
      
      "summarize" ->
        case ConversationStore.get(params["session_id"]) do
          {:ok, history} ->
            summary = ConversationSummarizer.summarize(history)
            "Summary: #{summary}"
          {:error, :not_found} ->
            "No conversation to summarize"
        end
    end
  end
)

# 9. Tool Middleware and Interceptors
defmodule ToolMiddleware do
  def rate_limit(tool, params) do
    case RateLimiter.check(tool.name, params) do
      :ok -> {:ok, params}
      {:error, :rate_limited} -> {:error, "Rate limit exceeded. Try again later."}
    end
  end
  
  def log_usage(tool, params, result) do
    Logger.info("Tool called", 
      tool: tool.name,
      params: params,
      result: result,
      timestamp: DateTime.utc_now()
    )
    result
  end
  
  def validate_permissions(tool, params, user) do
    if PermissionChecker.can_use?(user, tool) do
      {:ok, params}
    else
      {:error, "Permission denied for tool: #{tool.name}"}
    end
  end
end

# Apply middleware to tools
protected_tool = Tool.new(
  name: "sensitive_operation",
  description: "Perform sensitive operation",
  parameters: %{"data" => %{type: "string", required: true}},
  function: fn params ->
    # Middleware will be applied before this executes
    SensitiveAPI.process(params["data"])
  end,
  middleware: [
    &ToolMiddleware.rate_limit/2,
    &ToolMiddleware.validate_permissions/3,
    &ToolMiddleware.log_usage/3
  ]
)

# 10. Tool Composition and Workflows
defmodule WorkflowTools do
  def create_workflow_tool(steps) do
    Tool.new(
      name: "execute_workflow",
      description: "Execute a multi-step workflow",
      parameters: %{
        "input" => %{type: "object", required: true},
        "options" => %{type: "object", default: %{}}
      },
      function: fn params ->
        initial_state = %{
          input: params["input"],
          options: params["options"],
          results: []
        }
        
        Enum.reduce(steps, initial_state, fn step, state ->
          result = execute_step(step, state)
          %{state | results: state.results ++ [result]}
        end)
      end
    )
  end
  
  # Example workflow tool
  data_pipeline_tool = create_workflow_tool([
    {:fetch, &DataFetcher.fetch/1},
    {:validate, &DataValidator.validate/1},
    {:transform, &DataTransformer.transform/1},
    {:analyze, &DataAnalyzer.analyze/1},
    {:report, &ReportGenerator.generate/1}
  ])
end
```

### Tool Function Calling Format (OpenAI-style)

```elixir
# How the LLM sees and calls tools
defmodule ToolCallingFormat do
  # LLM generates this structure when calling a tool
  @tool_call_format %{
    "id" => "call_abc123",
    "type" => "function",
    "function" => %{
      "name" => "get_weather",
      "arguments" => ~s({"location": "San Francisco", "units": "fahrenheit"})
    }
  }
  
  # Chain processes tool calls
  def process_llm_response(llm_response) do
    case llm_response do
      %{"tool_calls" => tool_calls} ->
        # Execute each tool call
        results = Enum.map(tool_calls, fn call ->
          tool_name = call["function"]["name"]
          args = Jason.decode!(call["function"]["arguments"])
          
          tool = find_tool(tool_name)
          {:ok, result} = Tool.call(tool, args)
          
          %{
            "tool_call_id" => call["id"],
            "role" => "tool",
            "name" => tool_name,
            "content" => result
          }
        end)
        
        # Send results back to LLM for final response
        {:continue, results}
        
      %{"content" => content} ->
        # Regular response without tool calls
        {:done, content}
    end
  end
end

# Complete tool interaction flow
defmodule ToolInteractionFlow do
  def run_with_tools(chain, variables) do
    # 1. Initial prompt with tool descriptions
    messages = [
      %{role: "system", content: build_system_prompt(chain)},
      %{role: "user", content: resolve_variables(chain.user_prompt, variables)}
    ]
    
    # 2. Include tool definitions in API call
    tool_definitions = Enum.map(chain.tools, &format_tool_for_llm/1)
    
    # 3. LLM response might include tool calls
    case LLM.complete(messages, tools: tool_definitions) do
      %{tool_calls: calls} when calls != [] ->
        # 4. Execute tools
        tool_results = execute_tool_calls(calls, chain.tools)
        
        # 5. Add tool results to messages
        updated_messages = messages ++ tool_results
        
        # 6. Get final response from LLM
        LLM.complete(updated_messages, tools: tool_definitions)
        
      response ->
        # No tool calls needed
        response
    end
  end
  
  defp format_tool_for_llm(tool) do
    %{
      "type" => "function",
      "function" => %{
        "name" => tool.name,
        "description" => tool.description,
        "parameters" => %{
          "type" => "object",
          "properties" => tool.parameters,
          "required" => get_required_params(tool.parameters)
        }
      }
    }
  end
end
```

## Implementation Structure

### Core Chain Module

```elixir
defmodule Chainex.Chain do
  defstruct [:system_prompt, :user_prompt, :steps, :options]
  
  @type step_type :: :llm | :transform | :prompt | :tool | :parse | :conditional
  @type step :: {step_type(), any(), keyword()}
  @type variables :: %{atom() => any()}
  
  @type t :: %__MODULE__{
    system_prompt: String.t() | nil,
    user_prompt: String.t() | any(),
    steps: [step()],
    options: keyword()
  }
  
  # Chain creation
  @spec new(String.t()) :: t()
  def new(user_message) when is_binary(user_message)
  
  @spec new(system: String.t(), user: String.t()) :: t()
  def new(system: system_prompt, user: user_prompt)
  
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts)
  
  # Chain building functions
  @spec llm(t(), atom(), keyword()) :: t()
  def llm(chain, provider, opts \\ [])
  
  @spec transform(t(), function()) :: t()
  def transform(chain, transform_fn)
  
  @spec prompt(t(), String.t() | Prompt.t(), keyword()) :: t()
  def prompt(chain, template, opts \\ [])
  
  @spec tool(t(), atom(), keyword()) :: t()
  def tool(chain, name, params \\ [])
  
  @spec parse(t(), atom() | function(), keyword()) :: t()
  def parse(chain, parser_type, opts \\ [])
  # opts can include: schema, on_error, strict, etc.
  # When schema is provided, automatic validation is performed
  
  # Execution functions
  @spec run(t(), variables()) :: {:ok, any()} | {:error, any()}
  def run(chain, variables \\ %{})
  
  @spec run!(t(), variables()) :: any()
  def run!(chain, variables \\ %{})
  
  # Configuration functions
  @spec with_memory(t(), atom()) :: t()
  def with_memory(chain, memory_type)
  
  @spec with_tools(t(), [Tool.t()]) :: t()
  def with_tools(chain, tools)
  
  @spec require_variables(t(), [atom()]) :: t()
  def require_variables(chain, required_vars)
end
```

### System Prompt Integration

```elixir
# Multiple ways to create chains
Chain.new("What is {{topic}}?")  # Simple user message

Chain.new(
  system: "You are a {{role}} expert",
  user: "Analyze {{subject}}"
)  # Explicit system and user

Chain.new(
  system: "You are helpful",
  user: "{{query}}",
  model: "gpt-4",
  temperature: 0.7
)  # With additional options
```

### Execution Engine

```elixir
defmodule Chainex.Chain.Executor do
  @spec execute_steps([step()], any(), variables()) :: {:ok, any()} | {:error, any()}
  def execute_steps(steps, initial_input, variables)
  
  defp execute_step({:llm, provider, opts}, input, variables)
  defp execute_step({:transform, function}, input, variables)
  defp execute_step({:prompt, template, opts}, input, variables)
  defp execute_step({:tool, name, params}, input, variables)
  defp execute_step({:parse, parser, opts}, input, variables)
  
  # System prompt resolution
  defp resolve_system_prompt(chain, variables)
  defp resolve_user_prompt(chain, input, variables)
  
  # Variable resolution
  defp resolve_variables(template, variables)
  defp merge_built_in_variables(variables, input, context)
end
```

### Variable System

```elixir
# Built-in variables always available
%{
  input: current_input,           # Result from previous step
  step: current_step_number,      # Current step index
  timestamp: DateTime.utc_now(),  # Execution time
  chain_id: generate_id()         # Unique execution ID
}

# Variable resolution with defaults
"Hello {{name:Anonymous}}"      # Default value syntax
"Process {{count:10}} items"    # Numeric defaults
"{{setting:true}}"              # Boolean defaults

# Special variable references
"{{:from_input}}"               # Use entire input as value
"{{:from_previous}}"            # Alias for :from_input  
"{{:from_context.memory}}"      # Access context fields
```

### Output Parser System

```elixir
defmodule Chainex.Parser do
  @callback parse(String.t(), variables()) :: {:ok, any()} | {:error, any()}
  
  defstruct [:type, :options, :schema, :validator]
  
  @type t :: %__MODULE__{
    type: atom() | function(),
    options: keyword(),
    schema: map() | nil,
    validator: function() | nil
  }
end

# Built-in parsers
defmodule Chainex.Parser.JSON do
  @behaviour Chainex.Parser
  def parse(text, _variables), do: Jason.decode(text)
end

defmodule Chainex.Parser.List do
  @behaviour Chainex.Parser
  def parse(text, _variables) do
    items = text
    |> String.split(["\n", ",", ";"])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    {:ok, items}
  end
end
```

## Advanced Features

### Conditional Execution

```elixir
chain = Chain.new("Analyze data")
|> Chain.llm(:openai)
|> Chain.conditional(
  condition: fn vars -> vars[:detailed] end,
  then_step: Chain.transform(&deep_analysis/1),
  else_step: Chain.transform(&summary/1)
)
|> Chain.llm(:anthropic)

# Different paths based on variables
chain |> Chain.run(%{detailed: true})   # Runs deep analysis
chain |> Chain.run(%{detailed: false})  # Runs summary
```

### Error Handling and Recovery

```elixir
chain = Chain.new("Unreliable operation")
|> Chain.llm(:openai, retries: 3, backoff: :exponential)
|> Chain.on_error(fn error, vars -> 
  "Fallback response for error: #{error}"
end)
|> Chain.llm(:anthropic)  # Continues even if first LLM fails
```

### Parallel Execution

```elixir
# Execute multiple LLMs in parallel, then combine
chain = Chain.new("Complex analysis task")
|> Chain.parallel([
  Chain.llm(:openai, model: "gpt-4"),
  Chain.llm(:anthropic, model: "claude-3-opus"),
  Chain.llm(:ollama, model: "llama2")
])
|> Chain.combine(fn [result1, result2, result3], vars ->
  "Combined: #{result1} | #{result2} | #{result3}"
end)
```

### Chain Composition

```elixir
# Define reusable sub-chains
summarize_chain = Chain.new(
  system: "You are a summarizer",
  user: "Summarize: {{content}}"
)
|> Chain.llm(:openai)

analyze_chain = Chain.new(
  system: "You are an analyst", 
  user: "Analyze: {{content}}"
)
|> Chain.llm(:anthropic)

# Compose into larger chain
full_chain = Chain.new("{{raw_content}}")
|> Chain.sub_chain(summarize_chain, %{content: "{{:from_input}}"})
|> Chain.sub_chain(analyze_chain, %{content: "{{:from_input}}"})

full_chain |> Chain.run(%{raw_content: "Long document..."})
```

## Usage Patterns

### Batch Processing

```elixir
# Process multiple documents with same chain
document_processor = Chain.new(
  system: "You are a document analyzer",
  user: "Analyze this {{doc_type}}: {{content}}"
)
|> Chain.llm(:openai)
|> Chain.parse(:json)

results = documents
|> Task.async_stream(fn doc ->
  document_processor |> Chain.run(%{
    doc_type: doc.type,
    content: doc.text
  })
end)
|> Enum.map(fn {:ok, result} -> result end)
```

### Interactive Applications

```elixir
# Web application chat
defmodule MyApp.ChatController do
  @chat_chain Chain.new(
    system: "You are {{user_name}}'s personal assistant",
    user: "{{message}}"
  )
  |> Chain.with_memory(:conversation)
  |> Chain.llm(:openai)
  
  def chat(conn, %{"message" => message}) do
    user_id = get_session(conn, :user_id)
    user_name = get_user_name(user_id)
    
    result = @chat_chain
    |> Chain.with_session(user_id)
    |> Chain.run(%{user_name: user_name, message: message})
    
    case result do
      {:ok, response} -> json(conn, %{response: response})
      {:error, error} -> json(conn, %{error: error})
    end
  end
end
```

### Configuration-Driven Chains

```elixir
# config/chains.exs
config :my_app, :analysis_chain, %{
  system: "You are a {{domain}} expert",
  user: "Analyze: {{content}}",
  steps: [
    {:llm, :openai, model: "gpt-4"},
    {:parse, :json, []},
    {:transform, &MyApp.Analyzers.format_result/1}
  ],
  required_variables: [:domain, :content]
}

# In application
def analyze_content(content, domain) do
  chain_config = Application.get_env(:my_app, :analysis_chain)
  chain = Chain.from_config(chain_config)
  
  chain |> Chain.run(%{content: content, domain: domain})
end
```

### System Prompt Libraries

```elixir
defmodule MyApp.SystemPrompts do
  def expert(domain, years \\ 10) do
    "You are a #{domain} expert with #{years} years of experience."
  end
  
  def teacher(subject, grade_level) do
    "You are a #{subject} teacher for #{grade_level} students."
  end
  
  def creative_writer(genre \\ "general") do
    "You are a creative writer specializing in #{genre} content."
  end
end

# Usage
chain = Chain.new(
  system: MyApp.SystemPrompts.expert("{{field}}", "{{experience}}"),
  user: "{{task}}"
)
|> Chain.llm(:openai)

chain |> Chain.run(%{
  field: "data science",
  experience: 12,
  task: "Explain machine learning to executives"
})
```

## Error Handling Strategy

### Validation Errors (Build Time)

```elixir
# Invalid chain construction
Chain.new(
  system: "Valid system prompt",
  user: "{{missing_var}}"
)
|> Chain.require_variables([:missing_var])
|> Chain.run(%{})  # Error: missing required variable

# Type validation
Chain.new("test")
|> Chain.transform("not a function")  # Error: transform must be function
```

### Runtime Errors

```elixir
# LLM failures
{:error, {:llm_error, %{provider: :openai, reason: :timeout}}}

# Template resolution failures
{:error, {:template_error, {:missing_variable, :unknown_var}}}

# Parse failures
{:error, {:parse_error, %{parser: :json, reason: :invalid_json}}}

# Tool execution failures
{:error, {:tool_error, %{tool: :weather, reason: :api_unavailable}}}
```

### Error Recovery

```elixir
chain = Chain.new("Analyze {{content}}")
|> Chain.llm(:openai)
|> Chain.on_error(fn 
  {:llm_error, _} -> {:ok, "LLM unavailable, using cached result"}
  error -> {:error, error}
end)
|> Chain.llm(:anthropic)  # Continues with recovered result
```

## Performance Considerations

### Chain Reuse
- Chains are immutable data structures - safe to reuse
- Variable resolution happens only at runtime
- No expensive operations during chain building

### Parallel Execution
- Steps can be parallelized where data dependencies allow
- Tool calls can be batched
- Multiple LLM providers can be called concurrently

### Memory Management
- Conversation memory persists between runs
- Memory can be scoped by session, user, or context
- Automatic cleanup of old memory entries

## Testing Strategy

```elixir
defmodule ChainTest do
  test "chain handles different variables" do
    chain = Chain.new(
      system: "You are a {{role}} expert",
      user: "Explain {{topic}}"
    )
    |> Chain.llm(:openai)
    
    # Test with different roles and topics
    medical_result = chain |> Chain.run(%{
      role: "medical", 
      topic: "diabetes"
    })
    
    tech_result = chain |> Chain.run(%{
      role: "technology",
      topic: "blockchain"
    })
    
    assert {:ok, _} = medical_result
    assert {:ok, _} = tech_result
  end
  
  test "chain with mock LLM for testing" do
    chain = Chain.new(
      system: "Test system",
      user: "Test {{input}}"
    )
    |> Chain.llm(:mock)  # Use mock provider for tests
    
    result = chain |> Chain.run(%{input: "data"})
    assert {:ok, "Mock response"} = result
  end
end
```

## Migration Path

### Phase 1: Core Implementation
1. Basic chain structure with system/user prompts
2. Template variable resolution  
3. Single LLM calls
4. Simple transform steps
5. Basic error handling

### Phase 2: Enhanced Features  
1. Output parser integration
2. Tool calling support
3. Memory integration
4. Multi-LLM support

### Phase 3: Advanced Features
1. Conditional execution
2. Parallel processing
3. Error recovery
4. Chain composition

### Phase 4: Enterprise Features
1. Monitoring and observability
2. Rate limiting and quotas
3. Caching strategies
4. Performance optimization

This specification provides a comprehensive design for the Chainex Chain module that prioritizes system prompts as first-class citizens while maintaining the flexibility of runtime variable resolution and progressive complexity from simple to advanced features.