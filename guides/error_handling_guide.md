# Error Handling Guide

Chainex provides comprehensive error handling capabilities to build resilient AI applications that gracefully handle failures, timeouts, and unexpected conditions.

## Core Error Handling Features

Chainex offers three main error handling mechanisms:

1. **Retry Mechanism** - Automatic retry with configurable backoff
2. **Timeout Protection** - Prevent long-running operations from hanging
3. **Fallback Handling** - Graceful degradation with static or dynamic fallbacks

## Retry Mechanism

### Basic Retry Configuration

```elixir
# Retry up to 3 times with 1 second delay between attempts
chain = Chainex.Chain.new("{{message}}")
|> Chainex.Chain.with_retry(max_attempts: 3, delay: 1000)
|> Chainex.Chain.llm(:openai)

case Chainex.Chain.run(chain, %{message: "Hello"}) do
  {:ok, result} -> 
    # Success (possibly after retries)
    IO.puts("Got response: #{result}")
  {:error, reason} -> 
    # Failed even after retries
    IO.puts("Failed: #{inspect(reason)}")
end
```

### Smart Error Detection

The retry mechanism automatically detects retryable errors:

```elixir
# These errors will trigger retries:
# - Network timeouts
# - Rate limiting (HTTP 429)
# - Server errors (HTTP 5xx)
# - Connection failures

# These errors will NOT trigger retries:
# - Authentication errors (HTTP 401)
# - Invalid requests (HTTP 400)
# - Not found errors (HTTP 404)
```

### Exponential Backoff

```elixir
# Delay increases with each retry: 1s, 2s, 4s, 8s...
chain = Chainex.Chain.new("{{input}}")
|> Chainex.Chain.with_retry(
  max_attempts: 4,
  delay: 1000,
  backoff: :exponential,
  max_delay: 10_000  # Cap at 10 seconds
)
|> Chainex.Chain.llm(:openai)
```

## Timeout Protection

### Global Chain Timeout

```elixir
# Entire chain must complete within 30 seconds
chain = Chainex.Chain.new("{{query}}")
|> Chainex.Chain.with_timeout(30_000)
|> Chainex.Chain.llm(:openai)
|> Chainex.Chain.transform(fn result ->
  # Long processing step
  perform_analysis(result)
end)
|> Chainex.Chain.llm(:anthropic)

case Chainex.Chain.run(chain, %{query: "Analyze this data"}) do
  {:ok, result} -> result
  {:error, :timeout} -> "Operation timed out"
  {:error, reason} -> "Error: #{inspect(reason)}"
end
```

### Step-Level Timeouts

```elixir
# Different timeouts for different operations
chain = Chainex.Chain.new("{{input}}")
|> Chainex.Chain.llm(:openai, timeout: 10_000)  # 10s for LLM
|> Chainex.Chain.transform(fn result ->
  # This transform has the global timeout
  expensive_computation(result)
end)
|> Chainex.Chain.llm(:anthropic, timeout: 5_000)  # 5s for second LLM
```

## Fallback Handling

### Static Fallback

```elixir
# Return a fixed response on any error
chain = Chainex.Chain.new("{{question}}")
|> Chainex.Chain.with_fallback("I apologize, but I'm experiencing technical difficulties. Please try again later.")
|> Chainex.Chain.llm(:openai)

# Always returns {:ok, result} - never {:error, reason}
{:ok, response} = Chainex.Chain.run(chain, %{question: "What is AI?"})
```

### Dynamic Fallback

```elixir
# Generate fallback response based on the error
chain = Chainex.Chain.new("{{user_request}}")
|> Chainex.Chain.with_fallback(fn error ->
  case error do
    {:llm_error, :rate_limit} ->
      "I'm currently receiving high traffic. Please try again in a few minutes."
    {:llm_error, :timeout} ->
      "That request is taking too long to process. Please try a simpler question."
    {:network_error, _} ->
      "I'm having trouble connecting to my services. Please check your connection."
    _ ->
      "Something unexpected happened. Please try again or contact support."
  end
end)
|> Chainex.Chain.llm(:openai)
```

### Provider Fallback

```elixir
# Automatically fallback to different LLM providers
chain = Chainex.Chain.new("{{prompt}}")
|> Chainex.Chain.llm(:openai, model: "gpt-4")
|> Chainex.Chain.on_error(fn error ->
  case error do
    {:llm_error, :rate_limit} -> 
      # Switch to Anthropic if OpenAI is rate limited
      {:fallback_to, :anthropic}
    {:llm_error, :model_overloaded} ->
      # Use a smaller model
      {:fallback_to, {:openai, model: "gpt-3.5-turbo"}}
    _ ->
      {:continue_error, error}
  end
end)
```

## Combined Error Handling

### Comprehensive Error Strategy

```elixir
# Combine retry, timeout, and fallback for maximum resilience
robust_chain = Chainex.Chain.new(
  system: "You are a helpful assistant",
  user: "{{user_message}}"
)
|> Chainex.Chain.with_retry(max_attempts: 3, delay: 1000)
|> Chainex.Chain.with_timeout(30_000)
|> Chainex.Chain.with_fallback(fn error, context ->
  # Context includes retry attempts, elapsed time, etc.
  Logger.warning("Chain failed after #{context.retry_attempts} attempts: #{inspect(error)}")
  
  case error do
    {:error, :timeout} ->
      "Your request is taking longer than expected. The system might be under heavy load."
    {:llm_error, :rate_limit} ->
      "Our AI service is currently at capacity. Please try again in a few minutes."
    _ ->
      "I encountered an unexpected issue. Our team has been notified."
  end
end)
|> Chainex.Chain.llm(:openai)
```

### Multi-Step Chain Error Handling

```elixir
# Different error handling for different steps
analysis_chain = Chainex.Chain.new("{{data}}")
|> Chainex.Chain.transform(fn data ->
  # Critical step - no fallback, let it fail
  validate_input_data(data)
end)
|> Chainex.Chain.llm(:openai, retries: 2)
|> Chainex.Chain.transform(fn analysis ->
  # Optional enhancement - fallback to basic analysis
  try do
    enhanced_analysis(analysis)
  rescue
    _ -> analysis  # Return basic analysis if enhancement fails
  end
end)
|> Chainex.Chain.llm(:anthropic)
|> Chainex.Chain.with_fallback("Analysis completed with limited features due to service issues.")
```

## Real-World Error Handling Patterns

### Customer Support Bot

```elixir
def create_support_bot do
  Chainex.Chain.new(
    system: "You are a customer support agent. Be helpful and understanding.",
    user: "Customer: {{message}}"
  )
  |> Chainex.Chain.with_retry(max_attempts: 2, delay: 500)
  |> Chainex.Chain.with_timeout(15_000)  # 15 second timeout for customer experience
  |> Chainex.Chain.with_fallback(fn error, context ->
    # Log for monitoring
    CustomerSupport.log_ai_failure(error, context)
    
    # Escalate to human agent
    case CustomerSupport.create_ticket(context.variables) do
      {:ok, ticket_id} ->
        "I apologize for the technical difficulty. I've created ticket ##{ticket_id} and a human agent will assist you shortly."
      {:error, _} ->
        "I'm experiencing technical issues. Please call our support line at 1-800-SUPPORT for immediate assistance."
    end
  end)
  |> Chainex.Chain.llm(:openai)
end
```

### Data Processing Pipeline

```elixir
def create_data_processor do
  Chainex.Chain.new("{{raw_data}}")
  # Step 1: Data validation (fail fast)
  |> Chainex.Chain.transform(fn data ->
    case DataValidator.validate(data) do
      {:ok, clean_data} -> clean_data
      {:error, reason} -> raise "Invalid data: #{reason}"
    end
  end)
  # Step 2: AI analysis (with retry and fallback)
  |> Chainex.Chain.llm(:openai, retries: 3)
  |> Chainex.Chain.on_error(fn 
    {:llm_error, _} -> 
      # Fallback to rule-based analysis
      {:fallback_result, RuleBasedAnalyzer.analyze(data)}
    error -> 
      {:continue_error, error}
  end)
  # Step 3: Report generation (timeout protection)
  |> Chainex.Chain.with_timeout(60_000)  # 1 minute for report
  |> Chainex.Chain.transform(fn analysis ->
    ReportGenerator.create(analysis)
  end)
  |> Chainex.Chain.with_fallback("Analysis completed but report generation failed. Raw results available on request.")
end
```

### Rate Limiting Handler

```elixir
def create_rate_aware_chain do
  Chainex.Chain.new("{{query}}")
  |> Chainex.Chain.with_retry(
    max_attempts: 5,
    delay: 2000,
    backoff: :exponential,
    max_delay: 30_000
  )
  |> Chainex.Chain.llm(:openai)
  |> Chainex.Chain.on_error(fn error ->
    case error do
      {:llm_error, :rate_limit} ->
        # Check if we can switch to a different provider
        case RateLimiter.get_available_provider() do
          {:ok, provider} -> 
            Logger.info("Switching to provider: #{provider}")
            {:fallback_to, provider}
          :none_available ->
            # Queue the request for later
            QueueManager.enqueue_for_retry(context.variables, delay: 300_000)
            {:fallback_result, "Your request has been queued and will be processed when capacity is available."}
        end
      _ ->
        {:continue_error, error}
    end
  end)
end
```

## Error Monitoring and Logging

### Structured Error Logging

```elixir
# Add error context to all chains
monitored_chain = fn base_chain ->
  base_chain
  |> Chainex.Chain.with_metadata(%{
    request_id: generate_request_id(),
    user_id: get_current_user_id(),
    timestamp: DateTime.utc_now()
  })
  |> Chainex.Chain.on_error(fn error, context ->
    # Structured logging for monitoring
    Logger.error("Chain execution failed", %{
      error: inspect(error),
      request_id: context.metadata.request_id,
      user_id: context.metadata.user_id,
      retry_attempts: context.retry_attempts,
      elapsed_time_ms: context.elapsed_time,
      chain_steps: length(context.executed_steps)
    })
    
    # Send to error tracking service
    ErrorTracker.report(error, context)
    
    {:continue_error, error}
  end)
end
```

### Health Checks

```elixir
def perform_health_check do
  health_chain = Chainex.Chain.new("Health check: respond with 'OK'")
  |> Chainex.Chain.with_timeout(5000)
  |> Chainex.Chain.llm(:openai)
  
  case Chainex.Chain.run(health_chain) do
    {:ok, response} when response =~ ~r/ok/i ->
      {:healthy, "LLM services operational"}
    {:ok, _unexpected} ->
      {:degraded, "LLM services responding but may be impaired"}
    {:error, :timeout} ->
      {:unhealthy, "LLM services not responding"}
    {:error, reason} ->
      {:unhealthy, "LLM services error: #{inspect(reason)}"}
  end
end
```

## Testing Error Handling

### Unit Tests

```elixir
defmodule MyApp.ErrorHandlingTest do
  use ExUnit.Case
  
  test "handles rate limiting with retry" do
    chain = Chainex.Chain.new("{{message}}")
    |> Chainex.Chain.with_retry(max_attempts: 2, delay: 10)
    |> Chainex.Chain.with_fallback("Rate limited fallback")
    |> Chainex.Chain.llm(:mock, mock_error: {:rate_limit, "Too many requests"})
    
    {:ok, result} = Chainex.Chain.run(chain, %{message: "Hello"})
    assert result == "Rate limited fallback"
  end
  
  test "timeout with fallback" do
    chain = Chainex.Chain.new("Test")
    |> Chainex.Chain.with_timeout(50)
    |> Chainex.Chain.with_fallback("Timeout fallback")
    |> Chainex.Chain.transform(fn _input ->
      Process.sleep(100)  # Simulate slow operation
      "Should timeout"
    end)
    
    {:ok, result} = Chainex.Chain.run(chain)
    assert result == "Timeout fallback"
  end
end
```

## Best Practices

### 1. Layered Error Handling

Apply error handling at appropriate levels:
- **Transport level**: Network timeouts, connection failures
- **Service level**: Rate limiting, service unavailability  
- **Application level**: Business logic errors, validation failures
- **User level**: Friendly error messages, graceful degradation

### 2. Error Context

Always provide context in error handling:
- Include request IDs for tracing
- Log user actions that led to errors
- Track error patterns for system health monitoring

### 3. Graceful Degradation

Design fallback strategies that maintain user experience:
- Reduced functionality over complete failure
- Clear communication about limitations
- Alternative paths to achieve user goals

### 4. Testing

Test error conditions thoroughly:
- Network failures and timeouts
- Rate limiting scenarios
- Invalid responses and parsing errors
- Concurrent error conditions

Error handling is critical for production LLM applications. Chainex's comprehensive error handling features help you build resilient systems that gracefully handle the inherent unpredictability of AI services.