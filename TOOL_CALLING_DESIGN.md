# Tool Calling Design for Chainex

## Current Implementation (Manual Tool Calling)
```elixir
# We explicitly tell the chain to call a tool
chain = Chain.new("Calculate something")
|> Chain.with_tools([calculator])
|> Chain.tool(:calculator, expression: "2 + 2")  # Manual tool call
```

## Desired Implementation (LLM-Driven Tool Calling)

### Option 1: Automatic Tool Selection
```elixir
# LLM decides whether and which tool to use
chain = Chain.new("What's the weather in Paris?")
|> Chain.with_tools([weather_tool, calculator_tool])
|> Chain.llm(:anthropic, tools: :auto)  # LLM decides to call weather_tool

# The LLM would:
# 1. Receive the prompt "What's the weather in Paris?"
# 2. Decide it needs the weather_tool
# 3. Call weather_tool with {location: "Paris"}
# 4. Get the result
# 5. Format and return the answer
```

### Option 2: Tool-Enabled LLM Step
```elixir
# Enable tool calling on specific LLM steps
chain = Chain.new("Calculate the square root of 144 and explain the result")
|> Chain.with_tools([calculator])
|> Chain.llm(:anthropic, tool_choice: :auto)  # Can call tools if needed

# Or force tool usage
chain = Chain.new("Get weather for these cities: Paris, London, Tokyo")
|> Chain.with_tools([weather])
|> Chain.llm(:anthropic, tool_choice: :required)  # Must use a tool
```

### Option 3: Agent-Style Execution
```elixir
# ReAct-style agent that can make multiple tool calls
agent = Chain.agent("Research the weather in Paris and calculate the celsius to fahrenheit conversion")
|> Chain.with_tools([weather, calculator])
|> Chain.with_max_iterations(5)  # Prevent infinite loops

# The agent would:
# 1. Think: "I need to get weather for Paris"
# 2. Act: Call weather_tool(location: "Paris")
# 3. Observe: "Temperature is 20°C"
# 4. Think: "Now I need to convert 20°C to Fahrenheit"
# 5. Act: Call calculator("20 * 9/5 + 32")
# 6. Observe: "Result is 68"
# 7. Respond: "The weather in Paris is 20°C (68°F)"
```

## Implementation Requirements

### 1. LLM Provider Support
- Anthropic: Uses tool_use API with tools parameter
- OpenAI: Uses function_calling with functions parameter
- Need to convert our Tool format to provider-specific format

### 2. Tool Description Format
```elixir
# Tools need to be described to the LLM
def to_llm_format(%Tool{} = tool, :anthropic) do
  %{
    name: tool.name,
    description: tool.description,
    input_schema: %{
      type: "object",
      properties: tool.parameters,
      required: tool.required_params
    }
  }
end
```

### 3. Execution Loop
```elixir
defp execute_llm_with_tools(messages, tools, provider, opts) do
  # 1. Call LLM with tools
  response = LLM.chat(messages, tools: tools, provider: provider)
  
  # 2. Check if LLM wants to use a tool
  case response do
    %{tool_calls: tool_calls} when tool_calls != [] ->
      # 3. Execute each tool call
      tool_results = Enum.map(tool_calls, &execute_tool_call/1)
      
      # 4. Add tool results to messages
      messages = messages ++ [%{role: :assistant, content: response.content, tool_calls: tool_calls}]
      messages = messages ++ Enum.map(tool_results, fn result ->
        %{role: :tool, content: result}
      end)
      
      # 5. Call LLM again with tool results
      execute_llm_with_tools(messages, tools, provider, opts)
      
    _ ->
      # No tool calls, return final response
      {:ok, response.content}
  end
end
```

### 4. Chain Step Types

We need to distinguish between:
- `Chain.tool/3` - Manual tool execution (current implementation)
- `Chain.llm/3` with tools - LLM-driven tool calling (new)
- `Chain.agent/2` - Multi-step reasoning with tools (future)

## Proposed API Changes

### 1. Update Chain.llm/3 to support tools
```elixir
# Auto tool selection
Chain.llm(:anthropic, tool_choice: :auto)

# Force specific tool
Chain.llm(:anthropic, tool_choice: {:tool, "calculator"})

# Require some tool use
Chain.llm(:anthropic, tool_choice: :required)

# No tools (default)
Chain.llm(:anthropic, tool_choice: :none)
```

### 2. Keep Chain.tool/3 for explicit tool calls
```elixir
# When you want to force a specific tool call
Chain.tool(:calculator, expression: "2 + 2")
```

### 3. Add Chain.agent/2 for ReAct patterns
```elixir
Chain.agent("Solve this problem step by step")
|> Chain.with_tools([...])
|> Chain.with_max_iterations(5)
```

## Migration Path

1. **Phase 1**: Keep current `Chain.tool/3` for manual tool calling
2. **Phase 2**: Add LLM-driven tool calling to `Chain.llm/3`
3. **Phase 3**: Add agent capabilities for complex reasoning
4. **Phase 4**: Add streaming support for tool calls

## Example Use Cases

### Weather Assistant
```elixir
Chain.new("What's the weather like in Paris and London? Also convert 20C to Fahrenheit.")
|> Chain.with_tools([weather_tool, calculator_tool])
|> Chain.llm(:anthropic, tool_choice: :auto)
# LLM automatically calls weather(Paris), weather(London), calculator(20*9/5+32)
```

### Math Tutor
```elixir
Chain.new("Solve x^2 + 5x + 6 = 0 step by step")
|> Chain.with_tools([calculator_tool])
|> Chain.llm(:anthropic, tool_choice: :auto)
# LLM explains steps and uses calculator for verification
```

### Research Agent
```elixir
Chain.agent("Research the population of major European cities and calculate the total")
|> Chain.with_tools([search_tool, calculator_tool])
|> Chain.run()
# Agent makes multiple searches and calculations autonomously
```