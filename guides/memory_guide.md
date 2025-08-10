# Memory and Context Guide

Chainex provides powerful memory capabilities to build conversational AI applications that remember context across interactions.

## Memory Types

Chainex supports four types of memory:

### 1. Conversation Memory

Maintains full conversation history with automatic context injection:

```elixir
# Personal assistant with memory
personal_assistant = Chainex.Chain.new(
  system: "You are {{user_name}}'s personal assistant. Remember our conversation history.",
  user: "{{message}}"
)
|> Chainex.Chain.with_memory(:conversation)
|> Chainex.Chain.llm(:openai)

# First interaction
personal_assistant 
|> Chainex.Chain.run(%{
  user_name: "Alice", 
  message: "Schedule a meeting for tomorrow",
  session_id: "user_123"
})

# Second interaction - remembers previous context
personal_assistant
|> Chainex.Chain.run(%{
  user_name: "Alice", 
  message: "What time did we schedule it for?",
  session_id: "user_123"  
})
# Remembers the previous scheduling request
```

### 2. Buffer Memory

Simple key-value memory for temporary data:

```elixir
chain = Chainex.Chain.new("{{message}}")
|> Chainex.Chain.with_memory(:buffer, max_entries: 10)
|> Chainex.Chain.llm(:openai)

# Stores only the most recent 10 entries
```

### 3. Persistent Memory

File and database-backed memory that survives application restarts:

```elixir
# File-based persistence
file_chain = Chainex.Chain.new("{{message}}")
|> Chainex.Chain.with_memory(:persistent, %{
  backend: :file,
  file_path: "/path/to/conversation.dat"
})
|> Chainex.Chain.llm(:openai)

# Database persistence (requires Ecto setup)
db_chain = Chainex.Chain.new("{{message}}")
|> Chainex.Chain.with_memory(:persistent, %{
  backend: :database,
  repo: MyApp.Repo,
  table_name: "conversations"
})
|> Chainex.Chain.llm(:openai)
```

### 4. Vector Memory (Coming Soon)

Semantic similarity-based memory for advanced context retrieval.

## Memory Configuration Options

### Pruning Strategies

Control memory size with automatic pruning:

```elixir
chain = Chainex.Chain.new("{{message}}")
|> Chainex.Chain.with_memory(:conversation, %{
  max_entries: 100,
  pruning_strategy: :lru,  # :lru, :lfu, :ttl, or :hybrid
  auto_prune: true,
  prune_threshold: 0.8  # Prune when 80% full
})
|> Chainex.Chain.llm(:openai)
```

### Session Management

Separate conversations by session:

```elixir
# User A's conversation
chain |> Chainex.Chain.run(%{message: "Hello", session_id: "user_a"})

# User B's conversation (completely separate)
chain |> Chainex.Chain.run(%{message: "Hi there", session_id: "user_b"})
```

## Memory Integration in Multi-Step Chains

Memory works seamlessly across all chain steps:

```elixir
conversation_chain = Chainex.Chain.new("{{user_input}}")
|> Chainex.Chain.with_memory(:conversation)
|> Chainex.Chain.llm(:openai, model: "gpt-4")
|> Chainex.Chain.transform(fn response -> 
  # Memory context is automatically injected into the LLM call above
  "Processed: #{response}"
end)
|> Chainex.Chain.llm(:anthropic)  # This call also gets memory context

# Each LLM call receives the full conversation history
```

## Database Setup for Persistent Memory

If using database persistence, create the required table:

```elixir
defmodule MyApp.Repo.Migrations.CreateChainexMemory do
  use Ecto.Migration

  def up do
    Chainex.Memory.Database.create_table("conversations")
  end

  def down do
    Chainex.Memory.Database.drop_table("conversations")
  end
end
```

## Best Practices

### 1. Choose the Right Memory Type

- **Conversation**: For chatbots and interactive applications
- **Buffer**: For temporary context in processing pipelines  
- **Persistent**: For long-term user relationships and data retention
- **Vector**: For semantic search and retrieval (coming soon)

### 2. Session Management

Always use session IDs to separate user conversations:

```elixir
# Good - separate sessions
Chain.run(chain, %{message: "Hello", session_id: user.id})

# Bad - shared session
Chain.run(chain, %{message: "Hello"})
```

### 3. Memory Pruning

Configure appropriate pruning to manage memory usage:

```elixir
# For high-traffic applications
|> Chainex.Chain.with_memory(:conversation, %{
  max_entries: 50,
  pruning_strategy: :lru,
  auto_prune: true
})

# For detailed analysis applications  
|> Chainex.Chain.with_memory(:persistent, %{
  backend: :database,
  max_entries: 1000,
  pruning_strategy: :ttl,
  ttl_seconds: 86400  # 24 hours
})
```

### 4. Error Handling

Memory operations can fail, so handle errors gracefully:

```elixir
case Chainex.Chain.run(chain_with_memory, variables) do
  {:ok, result} -> 
    # Success
    result
  {:error, {:memory_error, reason}} ->
    # Handle memory-specific errors
    Logger.error("Memory error: #{reason}")
    # Fallback to chain without memory
    Chainex.Chain.run(chain_without_memory, variables)
  {:error, reason} ->
    # Handle other errors
    {:error, reason}
end
```

## Testing Memory

Use the test environment for memory testing:

```elixir
defmodule MyApp.MemoryTest do
  use ExUnit.Case
  
  test "conversation memory maintains context" do
    chain = Chainex.Chain.new("{{message}}")
    |> Chainex.Chain.with_memory(:conversation)
    |> Chainex.Chain.llm(:mock, response: "I remember: {{message}}")
    
    # First message
    {:ok, _} = Chainex.Chain.run(chain, %{
      message: "My name is Alice", 
      session_id: "test_session"
    })
    
    # Second message should have context
    {:ok, response} = Chainex.Chain.run(chain, %{
      message: "What's my name?",
      session_id: "test_session"
    })
    
    # The mock will receive both messages as context
    assert String.contains?(response, "Alice")
  end
end
```