# Test multiple tool calling scenarios
alias Chainex.Chain
alias Chainex.Tools.{Calculator, Weather, TextProcessor}

IO.puts "\n=== Multiple Tool Calling Tests ===\n"

# Setup tools
calculator = Calculator.new()
weather = Weather.new()
text_counter = TextProcessor.text_length_tool()
case_converter = TextProcessor.case_converter_tool()

# Test 1: LLM chooses between different tool types
IO.puts "Test 1: LLM chooses appropriate tool from multiple options"
chain = Chain.new("What's the weather in Tokyo, Japan?")
|> Chain.with_tools([calculator, weather, text_counter])
|> Chain.llm(:anthropic, tool_choice: :auto, max_tokens: 200)

result = Chain.run(chain)
IO.inspect result, label: "Weather choice result"

# Test 2: LLM makes multiple tool calls in one request
IO.puts "\nTest 2: LLM makes multiple tool calls in sequence"
chain = Chain.new("""
Please help me with the following tasks:
1. What's the weather in Paris?
2. Calculate 25 * 8
3. Count the characters in "Hello World"
""")
|> Chain.with_tools([calculator, weather, text_counter])
|> Chain.llm(:anthropic, tool_choice: :auto, max_tokens: 500)

result = Chain.run(chain)
IO.inspect result, label: "Multiple tool calls result"

# Test 3: Complex reasoning requiring different tools
IO.puts "\nTest 3: Complex task requiring tool selection reasoning"
chain = Chain.new("""
I need to plan a trip to London. Can you:
1. Check the weather there
2. Calculate how much 100 USD is if the exchange rate is 1.27 (multiply 100 by 1.27)
3. Convert "ENJOY YOUR TRIP" to title case
""")
|> Chain.with_tools([calculator, weather, case_converter])
|> Chain.llm(:anthropic, tool_choice: :auto, max_tokens: 600)

result = Chain.run(chain)
IO.inspect result, label: "Trip planning result"

# Test 4: LLM chooses math tool for calculation request
IO.puts "\nTest 4: LLM should choose calculator for math request"
chain = Chain.new("What's 144 divided by 12 plus 8?")
|> Chain.with_tools([calculator, weather, text_counter])
|> Chain.llm(:anthropic, tool_choice: :auto, max_tokens: 200)

result = Chain.run(chain)
IO.inspect result, label: "Math choice result"

# Test 5: LLM chooses text tool for text processing
IO.puts "\nTest 5: LLM should choose text tool for text processing"
chain = Chain.new("How many characters are in the sentence 'The quick brown fox jumps over the lazy dog'?")
|> Chain.with_tools([calculator, weather, text_counter])
|> Chain.llm(:anthropic, tool_choice: :auto, max_tokens: 200)

result = Chain.run(chain)
IO.inspect result, label: "Text processing choice result"

IO.puts "\n=== Multiple Tool Tests Complete ===\n"
