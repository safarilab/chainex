# Chainex Stateful Workflows

This document describes the stateful workflow capabilities in Chainex, enabling chains to act as workflows with state tracking, pause/resume, and advanced control flow.

## Overview

Every chain in Chainex has built-in state management. State flows through all steps, allowing you to:

- Store intermediate results with `store_as/2`
- Access stored values in templates with `{{key}}`
- Pause execution for human input with `await/2`
- Branch conditionally with `when/3` and `otherwise/2`
- Loop with conditions using `loop/4`
- Execute parallel branches with `parallel/2`
- Persist state with `persist_to/2`

## State Model

State is a first-class citizen in every chain:

```elixir
# State automatically flows through the chain
"Research {{topic}}"
|> Chain.new()
|> Chain.llm(:anthropic)
|> Chain.store_as(:research)          # Store LLM result in state[:research]
|> Chain.llm(:openai, system: "Summarize: {{research}}")  # Access via template
|> Chain.store_as(:summary)
|> Chain.run(%{topic: "quantum computing"})
# => {:ok, final_result, %{topic: "...", research: "...", summary: "..."}}
```

### State Functions

| Function | Description |
|----------|-------------|
| `store_as(chain, key)` | Store step result in state under `key` |
| `get(chain, key)` | Get value from state as current input |
| `update(chain, key, fn)` | Update state value using function |
| `with_session(chain, id)` | Isolate state by session ID |
| `persist_to(chain, backend)` | Configure state persistence (`:ets`, `:database`) |

## Control Flow

### Fluent Guards (when/otherwise)

Use `when/3` for conditional execution and `otherwise/2` for fallbacks:

```elixir
# Simple condition
"Classify: {{text}}"
|> Chain.new()
|> Chain.llm(:anthropic)
|> Chain.parse(:json, %{category: :string})
|> Chain.when(&(&1.category == "urgent"), urgent_chain)
|> Chain.otherwise(normal_chain)
|> Chain.run(vars)

# Multiple conditions (first match wins)
chain
|> Chain.when(&(&1.type == "billing"), billing_chain)
|> Chain.when(&(&1.type == "tech"), tech_chain)
|> Chain.when(&(&1.priority == "high"), escalation_chain)
|> Chain.otherwise(general_chain)

# Inline builder function
chain
|> Chain.when(&(&1.needs_review?), fn c ->
    c
    |> Chain.await(:approval)
    |> Chain.llm(:anthropic, system: "Incorporate feedback")
  end)
|> Chain.otherwise(&(&1))  # Pass through unchanged
```

### Loops

Use `loop/4` for iterative execution:

```elixir
# Loop until quality score is high enough
"Refine draft: {{draft}}"
|> Chain.new()
|> Chain.loop(
    fn result, _state -> result.score < 0.8 end,  # Continue while true
    fn c ->
      c
      |> Chain.llm(:anthropic, system: "Improve this draft")
      |> Chain.transform(&score_quality/1)
    end,
    max_iterations: 5
  )
|> Chain.run(%{draft: "Initial text"})
```

### Parallel Execution

Use `parallel/2` for fan-out/fan-in:

```elixir
"Analyze {{text}}"
|> Chain.new()
|> Chain.parallel([
    fn c -> c |> Chain.llm(:anthropic, system: "Sentiment analysis") end,
    fn c -> c |> Chain.llm(:openai, system: "Entity extraction") end,
    fn c -> c |> Chain.llm(:anthropic, system: "Summarization") end
  ])
|> Chain.transform(fn [sentiment, entities, summary] ->
    %{sentiment: sentiment, entities: entities, summary: summary}
  end)
|> Chain.run(%{text: "Long document..."})
```

## Async Execution

For long-running chains, use async execution with pause/resume:

```elixir
# Start async execution
{:ok, instance_id} = chain
|> Chain.persist_to(:ets)
|> Chain.run_async(%{topic: "AI"})

# Check status
{:ok, state} = Chain.get_state(instance_id)
IO.inspect(state.status)  # :running, :paused, :completed, :failed

# Pause if needed
:ok = Chain.pause(instance_id)

# Resume later
{:ok, result, final_state} = Chain.resume(instance_id, %{extra: "data"})
```

## Human-in-the-Loop

Use `await/2` to pause for human input:

```elixir
"Generate proposal for {{topic}}"
|> Chain.new()
|> Chain.llm(:anthropic)
|> Chain.await(:human_review)  # Pauses here
|> Chain.transform(fn result, vars ->
    "Feedback: #{vars.human_review}\n\nOriginal: #{result}"
  end)
|> Chain.llm(:anthropic, system: "Incorporate feedback")
|> Chain.persist_to(:database)
|> Chain.run_async(%{topic: "AI project"})
# => {:ok, instance_id}

# Later - human provides input
{:ok, result, state} = Chain.resume(instance_id, %{human_review: "Add more details"})
```

## Agentic Tool Loops

For ReAct-style agents that decide when to use tools:

```elixir
# Basic tool loop (built-in, max 5 iterations)
"Help me with: {{task}}"
|> Chain.new()
|> Chain.with_tools([calculator, web_search])
|> Chain.llm(:anthropic, tool_choice: :auto)  # Auto-loops until done
|> Chain.run(%{task: "Calculate 25 * 4"})

# Explicit agentic loop with state tracking
"Agent task: {{task}}"
|> Chain.new()
|> Chain.with_tools([calculator, web_search])
|> Chain.loop(
    fn result, _state -> result.tool_calls != nil end,
    fn c ->
      c
      |> Chain.execute_tools()
      |> Chain.store_as(:tool_results)
      |> Chain.llm(:anthropic, tool_choice: :auto)
    end,
    max_iterations: 10
  )
|> Chain.store_as(:final_answer)
|> Chain.run(%{task: "Research quantum computing"})
```

## Multi-Agent Pipelines

Chain multiple agents together with state:

```elixir
"Research {{topic}}"
|> Chain.new()
|> Chain.llm(:anthropic, system: "You are a researcher")
|> Chain.store_as(:research)
|> Chain.llm(:openai, system: "You are a writer. Write based on: {{research}}")
|> Chain.store_as(:draft)
|> Chain.llm(:anthropic, system: "You are an editor. Polish: {{draft}}")
|> Chain.store_as(:final)
|> Chain.run(%{topic: "quantum computing"})
# => {:ok, edited_content, %{topic: "...", research: "...", draft: "...", final: "..."}}
```

## Session-Based State Isolation

Isolate state per user or conversation:

```elixir
# Each session has independent state
"Chat: {{message}}"
|> Chain.new()
|> Chain.llm(:anthropic)
|> Chain.store_as(:response)
|> Chain.with_session("user_123")
|> Chain.persist_to(:ets)
|> Chain.run(%{message: "Hello!"})

# Different session = completely separate state
|> Chain.with_session("user_456")
```

## State Persistence

### ETS (In-Memory)

Fast, non-persistent storage:

```elixir
chain |> Chain.persist_to(:ets)
```

### Database (Ecto)

Persistent storage across restarts:

```elixir
chain |> Chain.persist_to(:database)
```

### Custom Backend

Implement `Chainex.Chain.Store` behaviour:

```elixir
defmodule MyApp.RedisStore do
  @behaviour Chainex.Chain.Store

  @impl true
  def save(instance_id, state), do: # ...

  @impl true
  def load(instance_id), do: # ...

  # ... other callbacks
end

chain |> Chain.persist_to(MyApp.RedisStore)
```

## API Reference

### State Management

- `Chain.store_as(chain, key)` - Store step result in state
- `Chain.get(chain, key)` - Get value from state
- `Chain.update(chain, key, fn)` - Update state value
- `Chain.with_session(chain, session_id)` - Isolate state by session
- `Chain.persist_to(chain, backend)` - Configure persistence

### Control Flow

- `Chain.when(chain, condition, chain_or_builder)` - Conditional execution
- `Chain.otherwise(chain, chain_or_builder)` - Fallback for when
- `Chain.loop(chain, condition, body_builder, opts)` - Loop while condition true
- `Chain.await(chain, key)` - Pause for human input
- `Chain.parallel(chain, [builder_fns])` - Parallel execution
- `Chain.execute_tools(chain)` - Execute tool calls from LLM

### Async Execution

- `Chain.run_async(chain, variables)` - Start async execution
- `Chain.get_state(instance_id)` - Get current state
- `Chain.pause(instance_id)` - Pause execution
- `Chain.resume(instance_id, new_vars)` - Resume execution

## State Struct

The `Chainex.Chain.State` struct contains:

```elixir
%Chainex.Chain.State{
  instance_id: "chain_123_abc",     # Unique execution ID
  session_id: "user_123",           # Optional session ID
  status: :running,                 # :pending | :running | :paused | :completed | :failed
  current_step: 3,                  # Current step index
  data: %{                          # Accumulated state data
    topic: "AI",
    research: "...",
    _last_result: "..."
  },
  step_results: [...],              # Results from each step
  started_at: ~U[2024-01-01 00:00:00Z],
  updated_at: ~U[2024-01-01 00:01:00Z],
  completed_at: nil,
  error: nil
}
```
