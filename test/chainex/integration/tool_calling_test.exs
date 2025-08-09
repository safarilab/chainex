defmodule Chainex.Integration.ToolCallingTest do
  use ExUnit.Case, async: false
  
  alias Chainex.{Chain, Tool}
  alias Chainex.Tools.{Calculator, Weather, TextProcessor}

  @moduletag :integration
  @moduletag timeout: 120_000  # 2 minute timeout for API calls

  describe "LLM-driven tool calling integration" do
    @tag :live_api
    test "simple tool calling with calculator" do
      calculator = Tool.new(
        name: "add",
        description: "Add two numbers",
        parameters: %{
          a: %{type: :number, required: true},
          b: %{type: :number, required: true}
        },
        function: fn %{a: a, b: b} -> {:ok, a + b} end
      )

      chain = Chain.new("Add 2 and 3")
      |> Chain.with_tools([calculator])
      |> Chain.llm(:anthropic, tool_choice: :auto, max_tokens: 100, temperature: 0)

      assert {:ok, result} = Chain.run(chain)
      assert is_binary(result)
      assert result =~ "5" or result =~ "five"
    end

    @tag :live_api
    test "LLM chooses appropriate tool from multiple options" do
      calculator = Calculator.new()
      weather = Weather.new()
      text_counter = TextProcessor.text_length_tool()

      chain = Chain.new("What's the weather in Tokyo, Japan?")
      |> Chain.with_tools([calculator, weather, text_counter])
      |> Chain.llm(:anthropic, tool_choice: :auto, max_tokens: 200, temperature: 0)

      assert {:ok, result} = Chain.run(chain)
      assert is_binary(result)
      # Should mention Tokyo and weather-related terms
      assert String.downcase(result) =~ "tokyo"
      assert String.downcase(result) =~ ~r/temperature|weather|celsius|°c/
    end

    @tag :live_api
    test "LLM makes multiple tool calls in sequence" do
      calculator = Calculator.new()
      weather = Weather.new()
      text_counter = TextProcessor.text_length_tool()

      chain = Chain.new("""
      Please help me with the following tasks:
      1. What's the weather in Paris?
      2. Calculate 25 * 8
      3. Count the characters in "Hello World"
      """)
      |> Chain.with_tools([calculator, weather, text_counter])
      |> Chain.llm(:anthropic, tool_choice: :auto, max_tokens: 500, temperature: 0)

      assert {:ok, result} = Chain.run(chain)
      assert is_binary(result)
      
      # Check for weather info
      assert String.downcase(result) =~ "paris"
      
      # Check for calculation result
      assert result =~ "200"
      
      # Check for character count
      assert result =~ "11"
    end

    @tag :live_api
    test "complex task requiring tool selection reasoning" do
      calculator = Calculator.new()
      weather = Weather.new()
      case_converter = TextProcessor.case_converter_tool()

      chain = Chain.new("""
      I need to plan a trip to London. Can you:
      1. Check the weather there
      2. Calculate how much 100 USD is if the exchange rate is 1.27 (multiply 100 by 1.27)
      3. Convert "ENJOY YOUR TRIP" to title case
      """)
      |> Chain.with_tools([calculator, weather, case_converter])
      |> Chain.llm(:anthropic, tool_choice: :auto, max_tokens: 600, temperature: 0)

      assert {:ok, result} = Chain.run(chain)
      assert is_binary(result)
      
      # Check that weather was mentioned (LLM might not repeat the location)
      assert String.downcase(result) =~ ~r/weather|temperature|celsius|°c/ or String.downcase(result) =~ "london"
      
      # Check for currency calculation (100 * 1.27 = 127)
      assert result =~ "127"
      
      # Check for title case conversion
      assert result =~ "Enjoy Your Trip"
    end

    @tag :live_api
    test "LLM chooses calculator for math request" do
      calculator = Calculator.new()
      weather = Weather.new()
      text_counter = TextProcessor.text_length_tool()

      chain = Chain.new("What's 144 divided by 12 plus 8?")
      |> Chain.with_tools([calculator, weather, text_counter])
      |> Chain.llm(:anthropic, tool_choice: :auto, max_tokens: 200, temperature: 0)

      assert {:ok, result} = Chain.run(chain)
      assert is_binary(result)
      # 144 / 12 = 12, 12 + 8 = 20
      assert result =~ "20"
    end

    @tag :live_api
    test "LLM chooses text tool for text processing" do
      calculator = Calculator.new()
      weather = Weather.new()
      text_counter = TextProcessor.text_length_tool()

      chain = Chain.new("How many characters are in the sentence 'The quick brown fox jumps over the lazy dog'?")
      |> Chain.with_tools([calculator, weather, text_counter])
      |> Chain.llm(:anthropic, tool_choice: :auto, max_tokens: 200, temperature: 0)

      assert {:ok, result} = Chain.run(chain)
      assert is_binary(result)
      # The sentence has 43 characters including spaces
      assert result =~ "43"
    end

    @tag :live_api
    test "tool_choice :none prevents tool use" do
      calculator = Calculator.new()

      chain = Chain.new("What is 2 + 2?")
      |> Chain.with_tools([calculator])
      |> Chain.llm(:anthropic, tool_choice: :none, max_tokens: 100, temperature: 0)

      assert {:ok, result} = Chain.run(chain)
      assert is_binary(result)
      # Should answer without using the tool
      assert result =~ "4" or result =~ "four"
    end

    @tag :live_api
    test "tool_choice :required forces tool use" do
      calculator = Calculator.new()

      chain = Chain.new("Hello, how are you?")  # Non-math question
      |> Chain.with_tools([calculator])
      |> Chain.llm(:anthropic, tool_choice: :required, max_tokens: 200, temperature: 0)

      assert {:ok, result} = Chain.run(chain)
      assert is_binary(result)
      # Even though the question isn't math-related, it should still attempt to use the tool
      # The response might explain it can't use the calculator for this, or might do a demo calculation
    end
  end

  describe "manual tool calling" do
    test "executes calculator tool directly" do
      calculator = Calculator.new()
      
      chain = Chain.new("Calculate the result")
      |> Chain.with_tools([calculator])
      |> Chain.tool(:calculator, expression: "15 + 25")

      assert {:ok, 40} = Chain.run(chain)
    end

    test "executes weather tool directly" do
      weather = Weather.new()
      
      chain = Chain.new("Get weather information")
      |> Chain.with_tools([weather])
      |> Chain.tool(:get_weather, location: "San Francisco", units: "celsius")

      assert {:ok, result} = Chain.run(chain)
      assert is_map(result)
      assert Map.has_key?(result, :temperature)
      assert Map.has_key?(result, :condition)
      assert result.location == "San Francisco"
    end

    test "chains multiple manual tool calls" do
      calculator = Calculator.new()
      text_counter = TextProcessor.text_length_tool()
      
      chain = Chain.new("Process numbers and text")
      |> Chain.with_tools([calculator, text_counter])
      |> Chain.tool(:calculator, expression: "10 + 20")
      |> Chain.transform(&"Result: #{&1}")
      |> Chain.tool(:count_text, text: "{{input}}", count_type: "characters")

      assert {:ok, %{characters: 10}} = Chain.run(chain)  # "Result: 30" = 10 chars
    end

    test "tool with variable resolution" do
      calculator = Calculator.new()
      
      chain = Chain.new("Calculate {{operation}}")
      |> Chain.with_tools([calculator])
      |> Chain.tool(:calculator, expression: "{{calculation}}")

      assert {:ok, 8} = Chain.run(chain, %{calculation: "2 * 4"})
    end

    test "tool mixed with LLM calls uses mock" do
      calculator = Calculator.new()
      
      chain = Chain.new("I need to calculate something")
      |> Chain.with_tools([calculator])
      |> Chain.tool(:calculator, expression: "7 * 6")
      |> Chain.llm(:mock)

      assert {:ok, "Mock response for: 42"} = Chain.run(chain)
    end
  end

  describe "error handling" do
    test "handles tool not found error" do
      chain = Chain.new("Use missing tool")
      |> Chain.tool(:missing_tool, param: "value")

      assert {:error, "Tool not found: missing_tool"} = Chain.run(chain)
    end

    test "handles tool execution error" do
      calculator = Calculator.new()
      
      chain = Chain.new("Invalid calculation")
      |> Chain.with_tools([calculator])
      |> Chain.tool(:calculator, expression: "invalid expression")

      assert {:error, message} = Chain.run(chain)
      assert message =~ "Invalid mathematical expression"
    end

    test "handles missing required parameters" do
      weather = Weather.new()
      
      chain = Chain.new("Get weather without location")
      |> Chain.with_tools([weather])
      |> Chain.tool(:get_weather, units: "celsius")  # Missing required 'location'

      assert {:error, {:missing_parameters, missing_params}} = Chain.run(chain)
      assert :location in missing_params
    end
  end
end