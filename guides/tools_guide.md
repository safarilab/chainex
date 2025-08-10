# Tools Integration Guide

Chainex provides powerful tools integration that allows LLMs to call external functions, APIs, and services to extend their capabilities beyond text generation.

## Creating Custom Tools

Define tools with parameters, descriptions, and functions:

```elixir
weather_tool = Chainex.Tool.new(
  name: "get_weather",
  description: "Get current weather information for any location",
  parameters: %{
    location: %{type: "string", description: "City name or coordinates", required: true},
    units: %{type: "string", enum: ["celsius", "fahrenheit"], default: "celsius"}
  },
  function: fn params ->
    case WeatherAPI.get_current(params.location, params.units) do
      {:ok, weather} -> 
        "#{params.location}: #{weather.temp}°#{String.upcase(params.units)}, #{weather.description}"
      {:error, reason} -> 
        "Weather data unavailable: #{reason}"
    end
  end
)
```

## Tool Usage Patterns

### 1. Automatic Tool Calling

Let the LLM decide when and how to use tools:

```elixir
# Weather assistant that automatically uses tools
chain = Chainex.Chain.new(
  system: "You can check weather and perform calculations. Use tools when needed.",
  user: "{{user_request}}"
)
|> Chainex.Chain.with_tools([weather_tool, calculator_tool])
|> Chainex.Chain.llm(:openai, tools: :auto)

# LLM automatically calls appropriate tools based on the request
chain |> Chainex.Chain.run(%{
  user_request: "What's the weather in Tokyo and convert 25°C to Fahrenheit?"
})
```

### 2. Manual Tool Calling

Explicitly call tools in your chain:

```elixir
"Check weather for {{city}}"
|> Chainex.Chain.new()
|> Chainex.Chain.with_tools([weather_tool])
|> Chainex.Chain.tool(:get_weather, location: "{{city}}", units: "celsius")
|> Chainex.Chain.transform(fn weather_data ->
  "Based on the weather: #{weather_data}, here's what you should know..."
end)
|> Chainex.Chain.llm(:openai)
|> Chainex.Chain.run(%{city: "San Francisco"})
```

## Advanced Tool Examples

### Calculator Tool

```elixir
calculator_tool = Chainex.Tool.new(
  name: "calculate",
  description: "Perform mathematical calculations and unit conversions",
  parameters: %{
    expression: %{type: "string", description: "Math expression or conversion", required: true}
  },
  function: fn params ->
    case MathParser.evaluate(params.expression) do
      {:ok, result} -> "#{params.expression} = #{result}"
      {:error, reason} -> "Calculation error: #{reason}"
    end
  end
)
```

### Database Query Tool

```elixir
db_query_tool = Chainex.Tool.new(
  name: "query_database",
  description: "Query the user database for information",
  parameters: %{
    table: %{type: "string", enum: ["users", "orders", "products"], required: true},
    filters: %{type: "object", description: "Query filters as key-value pairs"},
    limit: %{type: "integer", default: 10, minimum: 1, maximum: 100}
  },
  function: fn params ->
    case DatabaseManager.query(params.table, params.filters, params.limit) do
      {:ok, results} -> 
        "Found #{length(results)} records: #{format_results(results)}"
      {:error, reason} -> 
        "Database query failed: #{reason}"
    end
  end
)
```

### HTTP API Tool

```elixir
api_tool = Chainex.Tool.new(
  name: "call_api",
  description: "Make HTTP requests to external APIs",
  parameters: %{
    url: %{type: "string", format: "uri", required: true},
    method: %{type: "string", enum: ["GET", "POST", "PUT", "DELETE"], default: "GET"},
    headers: %{type: "object", description: "HTTP headers"},
    body: %{type: "string", description: "Request body for POST/PUT"}
  },
  function: fn params ->
    case HTTPClient.request(params.method, params.url, params.body, params.headers) do
      {:ok, %{status: 200, body: body}} ->
        "API Response: #{body}"
      {:ok, %{status: status}} ->
        "API Error: HTTP #{status}"
      {:error, reason} ->
        "Request failed: #{reason}"
    end
  end
)
```

## Tool Chaining and Workflows

### Research Assistant with Tool Chaining

```elixir
research_assistant = Chainex.Chain.new(
  system: """
  You are a research assistant. When asked to research a topic:
  1. Search for information
  2. Analyze the results
  3. Generate a summary report
  Use tools in sequence to complete the research.
  """,
  user: "{{research_request}}"
)
|> Chainex.Chain.with_tools([
  search_tool,      # Searches web/database
  analyze_tool,     # Analyzes found content
  summarize_tool,   # Creates summary
  citation_tool     # Formats citations
])
|> Chainex.Chain.llm(:openai, tools: :auto, parallel_tool_calls: true)

# The LLM will intelligently chain tools together
research_assistant |> Chainex.Chain.run(%{
  research_request: "Latest developments in quantum computing with peer-reviewed sources"
})
```

### Role-Based Tool Access

```elixir
def build_user_chain(user) do
  available_tools = case user.role do
    :admin -> 
      [user_management_tool, system_config_tool, audit_log_tool] ++ basic_tools
    :analyst ->
      [data_query_tool, visualization_tool, export_tool] ++ basic_tools
    :support ->
      [ticket_tool, customer_lookup_tool, kb_search_tool] ++ basic_tools
    _ ->
      basic_tools  # read-only tools
  end
  
  Chainex.Chain.new(
    system: "You are a {{role}} assistant with appropriate tool access",
    user: "{{request}}"
  )
  |> Chainex.Chain.with_tools(available_tools)
  |> Chainex.Chain.llm(:openai, tools: :auto)
  |> Chainex.Chain.with_metadata(%{user_id: user.id, role: user.role})
end
```

## Tool Security and Validation

### Parameter Validation

Tools automatically validate parameters based on their schema:

```elixir
payment_tool = Chainex.Tool.new(
  name: "process_payment",
  description: "Process a payment transaction",
  parameters: %{
    amount: %{type: "number", required: true, minimum: 0.01, maximum: 10000},
    currency: %{type: "string", enum: ["USD", "EUR", "GBP"], required: true},
    recipient: %{type: "string", required: true, pattern: "^[a-zA-Z0-9@._-]+$"}
  },
  function: fn params ->
    # Parameters are already validated by the tool system
    PaymentProcessor.charge(params.amount, params.currency, params.recipient)
  end
)
```

### Tool Middleware

Add security and monitoring layers:

```elixir
secured_tool = %{weather_tool | 
  function: fn params ->
    # Add rate limiting
    case RateLimiter.check_limit(:weather_api, params.location) do
      :ok -> 
        # Log the call
        Logger.info("Weather API called for: #{params.location}")
        # Call original function
        weather_tool.function.(params)
      {:error, :rate_limited} ->
        "API rate limit exceeded. Please try again later."
    end
  end
}
```

## Testing Tools

### Mock Tools for Testing

```elixir
defmodule MyApp.ToolsTest do
  use ExUnit.Case
  
  test "weather tool integration" do
    mock_weather_tool = Chainex.Tool.new(
      name: "get_weather",
      description: "Mock weather tool for testing",
      parameters: %{
        location: %{type: "string", required: true}
      },
      function: fn params ->
        "Mocked weather for #{params.location}: 22°C, Sunny"
      end
    )
    
    chain = Chainex.Chain.new("What's the weather in {{city}}?")
    |> Chainex.Chain.with_tools([mock_weather_tool])
    |> Chainex.Chain.llm(:mock, response: "Based on the weather data...")
    
    {:ok, result} = Chainex.Chain.run(chain, %{city: "Paris"})
    assert String.contains?(result, "weather data")
  end
end
```

### Integration Testing

```elixir
@tag :integration
test "real weather API integration" do
  # Only run with real API keys in integration tests
  if System.get_env("WEATHER_API_KEY") do
    chain = Chainex.Chain.new("{{request}}")
    |> Chainex.Chain.with_tools([real_weather_tool])
    |> Chainex.Chain.llm(:openai, tools: :auto)
    
    {:ok, result} = Chainex.Chain.run(chain, %{
      request: "What's the current weather in London?"
    })
    
    assert String.contains?(String.downcase(result), "london")
  else
    # Skip test if no API key
    :ok
  end
end
```

## Best Practices

### 1. Clear Tool Descriptions

Write detailed descriptions that help the LLM understand when to use each tool:

```elixir
# Good - clear and specific
description: "Get current weather information including temperature, conditions, and humidity for any city or coordinates"

# Bad - vague
description: "Weather stuff"
```

### 2. Validate Input Parameters

Always validate and sanitize tool inputs:

```elixir
function: fn params ->
  # Validate required parameters
  location = String.trim(params.location || "")
  if location == "" do
    "Error: Location is required"
  else
    # Sanitize input
    safe_location = String.slice(location, 0, 100)
    WeatherAPI.get_current(safe_location)
  end
end
```

### 3. Handle Errors Gracefully

Tools should return helpful error messages:

```elixir
function: fn params ->
  case ExternalAPI.call(params) do
    {:ok, result} -> 
      format_success_response(result)
    {:error, :not_found} -> 
      "The requested information could not be found. Please check your input and try again."
    {:error, :timeout} -> 
      "The service is currently slow to respond. Please try again in a moment."
    {:error, reason} -> 
      "An error occurred: #{reason}. Please contact support if this persists."
  end
end
```

### 4. Tool Documentation

Document your tools for other developers:

```elixir
@doc """
Weather lookup tool that integrates with OpenWeatherMap API.

## Parameters
- `location` (required): City name, "City, Country", or "latitude,longitude"  
- `units` (optional): "celsius" (default), "fahrenheit", or "kelvin"

## Returns
String with current weather information including temperature, conditions, and humidity.

## Examples
    iex> weather_tool.function.(%{location: "Paris", units: "celsius"})
    "Paris: 18°C, Partly cloudy, 65% humidity"
"""
```