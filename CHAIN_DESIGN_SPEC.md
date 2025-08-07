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

### Level 7: Output Parsers

```elixir
# Parse LLM responses into structured data
chain = Chain.new(
  system: "You are a data extractor",
  user: "Extract info from: {{text}}"
)
|> Chain.llm(:openai)
|> Chain.parse(:json)

chain |> Chain.run(%{text: "John Doe, age 30, from NYC"})
# Returns: {:ok, %{"name" => "John Doe", "age" => 30, "city" => "NYC"}}

# Schema-based parsing
person_schema = %{
  name: :string,
  age: :integer,
  skills: [:string],
  active: :boolean
}

chain = Chain.new("Extract person info: {{text}}")
|> Chain.llm(:openai)
|> Chain.parse(:structured, schema: person_schema)

# Custom parsers
date_parser = fn text ->
  case Regex.run(~r/(\d{4})-(\d{2})-(\d{2})/, text) do
    [_, year, month, day] -> 
      {:ok, Date.new!(String.to_integer(year), String.to_integer(month), String.to_integer(day))}
    nil -> 
      {:error, :no_date_found}
  end
end

chain = Chain.new("When was {{event}}?")
|> Chain.llm(:openai)
|> Chain.parse(date_parser)
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
chain = Chain.new(
  system: "Help with {{task_type}}",
  user: "{{request}}"
)
|> Chain.with_tools([weather_tool, math_tool, calendar_tool])
|> Chain.llm(:openai, tools: "{{available_tools}}")

chain |> Chain.run(%{
  task_type: "planning my day",
  available_tools: ["weather", "calendar"],
  request: "Help me plan tomorrow"
})
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