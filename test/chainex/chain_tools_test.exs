defmodule Chainex.Chain.ToolsTest do
  use ExUnit.Case

  alias Chainex.{Chain, Tool}
  alias Chainex.Tools.{Calculator, Weather, TextProcessor}

  describe "Chain.tool/3" do
    test "adds tool step to chain" do
      calculator = Calculator.new()
      
      chain = Chain.new("Calculate {{expression}}")
      |> Chain.with_tools([calculator])
      |> Chain.tool(:calculator, expression: "2 + 3")

      assert length(chain.steps) == 1
      assert {:tool, :calculator, [expression: "2 + 3"]} = Enum.at(chain.steps, 0)
    end

    test "chains multiple tool calls" do
      calculator = Calculator.new()
      weather = Weather.new()
      
      chain = Chain.new("Process data")
      |> Chain.with_tools([calculator, weather])
      |> Chain.tool(:calculator, expression: "10 + 5")
      |> Chain.tool(:get_weather, location: "{{city}}")

      assert length(chain.steps) == 2
      assert {:tool, :calculator, [expression: "10 + 5"]} = Enum.at(chain.steps, 0)
      assert {:tool, :get_weather, [location: "{{city}}"]} = Enum.at(chain.steps, 1)
    end

    test "tool with no parameters" do
      simple_tool = Tool.new(
        name: "simple_tool",
        description: "A simple tool with no parameters",
        parameters: %{},
        function: fn _ -> {:ok, "simple result"} end
      )

      chain = Chain.new("Test")
      |> Chain.with_tools([simple_tool])
      |> Chain.tool(:simple_tool)

      assert {:tool, :simple_tool, []} = Enum.at(chain.steps, 0)
    end
  end

  describe "Chain.with_tools/2" do
    test "configures tools in chain options" do
      calculator = Calculator.new()
      weather = Weather.new()
      tools = [calculator, weather]

      chain = Chain.new("Test")
      |> Chain.with_tools(tools)

      assert Keyword.get(chain.options, :tools) == tools
    end

    test "replaces existing tools" do
      calculator = Calculator.new()
      weather = Weather.new()
      text_tool = TextProcessor.text_length_tool()

      chain = Chain.new("Test")
      |> Chain.with_tools([calculator])
      |> Chain.with_tools([weather, text_tool])

      tools = Keyword.get(chain.options, :tools)
      assert length(tools) == 2
      assert weather in tools
      assert text_tool in tools
      refute calculator in tools
    end

    test "accepts empty tools list" do
      chain = Chain.new("Test")
      |> Chain.with_tools([])

      assert Keyword.get(chain.options, :tools) == []
    end
  end

  describe "tool execution" do
    test "executes calculator tool" do
      calculator = Calculator.new()
      
      chain = Chain.new("Calculate the result")
      |> Chain.with_tools([calculator])
      |> Chain.tool(:calculator, expression: "15 + 25")

      assert {:ok, 40} = Chain.run(chain)
    end

    test "executes weather tool" do
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

    test "executes text processing tools" do
      text_counter = TextProcessor.text_length_tool()
      
      chain = Chain.new("Count the text")
      |> Chain.with_tools([text_counter])
      |> Chain.tool(:count_text, text: "Hello world!", count_type: "words")

      assert {:ok, %{words: 2}} = Chain.run(chain)
    end

    test "tool with variable resolution" do
      calculator = Calculator.new()
      
      chain = Chain.new("Calculate {{operation}}")
      |> Chain.with_tools([calculator])
      |> Chain.tool(:calculator, expression: "{{calculation}}")

      assert {:ok, 8} = Chain.run(chain, %{calculation: "2 * 4"})
    end

    test "chained tool calls" do
      calculator = Calculator.new()
      text_counter = TextProcessor.text_length_tool()
      
      chain = Chain.new("Process numbers and text")
      |> Chain.with_tools([calculator, text_counter])
      |> Chain.tool(:calculator, expression: "10 + 20")
      |> Chain.transform(&"Result: #{&1}")  # Transform the number to a string first
      |> Chain.tool(:count_text, text: "{{input}}", count_type: "characters")

      assert {:ok, %{characters: 10}} = Chain.run(chain)  # "Result: 30" = 10 chars
    end

    test "tool mixed with LLM calls" do
      calculator = Calculator.new()
      
      chain = Chain.new("I need to calculate something")
      |> Chain.with_tools([calculator])
      |> Chain.tool(:calculator, expression: "7 * 6")
      |> Chain.llm(:mock)

      assert {:ok, "Mock response for: 42"} = Chain.run(chain)
    end

    test "tool mixed with transforms" do
      calculator = Calculator.new()
      
      chain = Chain.new("Calculate and transform")
      |> Chain.with_tools([calculator])
      |> Chain.tool(:calculator, expression: "100 / 4")
      |> Chain.transform(&"Result is #{&1}")

      assert {:ok, "Result is 25.0"} = Chain.run(chain)
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

      assert {:error, _message} = Chain.run(chain)
    end

    test "handles missing required parameters" do
      weather = Weather.new()
      
      chain = Chain.new("Get weather without location")
      |> Chain.with_tools([weather])
      |> Chain.tool(:get_weather, units: "celsius")  # Missing required 'location'

      assert {:error, _message} = Chain.run(chain)
    end

    test "handles tool function error" do
      error_tool = Tool.new(
        name: "error_tool",
        description: "Tool that always errors",
        parameters: %{},
        function: fn _ -> raise "Tool error" end
      )

      chain = Chain.new("Use error tool")
      |> Chain.with_tools([error_tool])
      |> Chain.tool(:error_tool)

      assert {:error, {:function_error, "Tool error"}} = Chain.run(chain)
    end
  end

  describe "complex tool workflows" do
    test "weather and calculation workflow" do
      calculator = Calculator.new()
      weather = Weather.new()
      
      chain = Chain.new("Weather and math workflow")
      |> Chain.with_tools([calculator, weather])
      |> Chain.tool(:get_weather, location: "New York", units: "fahrenheit")
      |> Chain.transform(fn weather_data -> 
        # Extract temperature number from string like "75°F"
        temp_str = weather_data.temperature
        temp_num = temp_str |> String.replace("°F", "") |> String.to_integer()
        # Return the F to C conversion expression as a string
        "(#{temp_num} - 32) * 5 / 9"
      end)
      |> Chain.tool(:calculator, expression: "{{input}}")  # Calculate the expression

      assert {:ok, celsius_temp} = Chain.run(chain)
      assert is_number(celsius_temp)
    end

    test "text processing pipeline" do
      case_converter = TextProcessor.case_converter_tool()
      text_counter = TextProcessor.text_length_tool()
      search_replace = TextProcessor.search_replace_tool()
      
      chain = Chain.new("Text processing pipeline")
      |> Chain.with_tools([case_converter, text_counter, search_replace])
      |> Chain.tool(:convert_case, text: "hello WORLD", case_type: "title")
      |> Chain.tool(:search_replace, text: "{{input}}", search: " ", replace: "_")
      |> Chain.tool(:count_text, text: "{{input}}", count_type: "characters")

      assert {:ok, %{characters: 11}} = Chain.run(chain)  # "Hello_World" = 11 chars
    end

    test "conditional tool usage with variables" do
      calculator = Calculator.new()
      weather = Weather.new()
      
      chain = Chain.new("Conditional tools based on type")
      |> Chain.with_tools([calculator, weather])

      # Test math operation
      math_result = Chain.run(chain |> Chain.tool(:calculator, expression: "{{expr}}"), 
                             %{expr: "5 * 5"})
      assert {:ok, 25} = math_result

      # Test weather operation  
      weather_result = Chain.run(chain |> Chain.tool(:get_weather, location: "{{city}}"),
                                %{city: "Boston"})
      assert {:ok, weather_data} = weather_result
      assert weather_data.location == "Boston"
    end
  end
end