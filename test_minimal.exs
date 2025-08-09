# Minimal test
alias Chainex.{Chain, Tool}

calculator = Tool.new(
  name: "add",
  description: "Add two numbers",
  parameters: %{
    a: %{type: :number, required: true},
    b: %{type: :number, required: true}
  },
  function: fn %{a: a, b: b} -> {:ok, a + b} end
)

IO.puts "Testing simple add tool..."

chain = Chain.new("Add 2 and 3")
|> Chain.with_tools([calculator])
|> Chain.llm(:anthropic, tool_choice: :auto, max_tokens: 100)

result = Chain.run(chain)
IO.inspect result, label: "Result"