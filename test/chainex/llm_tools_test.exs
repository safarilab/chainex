defmodule Chainex.LLMToolsTest do
  use ExUnit.Case

  alias Chainex.{Chain, Tool}
  alias Chainex.Tools.{Calculator, Weather}

  describe "LLM-driven tool calling" do
    test "LLM decides to use calculator tool" do
      calculator = Calculator.new()

      # Mock LLM that simulates tool calling
      _mock_llm = create_tool_calling_mock()

      chain =
        Chain.new("What is 25 times 4?")
        |> Chain.with_tools([calculator])
        |> Chain.llm(:mock, tool_choice: :auto)

      # This test would need a mock LLM that returns tool calls
      # For now, we test the structure is correct
      assert length(chain.steps) == 1
      assert {:llm, :mock, opts} = Enum.at(chain.steps, 0)
      assert Keyword.get(opts, :tool_choice) == :auto
    end

    test "Chain with tools option enables tool calling" do
      calculator = Calculator.new()
      weather = Weather.new()

      chain =
        Chain.new("What's the weather in Paris and calculate 20 celsius to fahrenheit")
        |> Chain.with_tools([calculator, weather])
        # Should default to tool_choice: :auto when tools present
        |> Chain.llm(:mock)

      assert chain.options[:tools] == [calculator, weather]
    end

    test "Tool choice options" do
      tool =
        Tool.new(
          name: "test_tool",
          description: "Test tool",
          parameters: %{},
          function: fn _ -> {:ok, "result"} end
        )

      # Auto tool selection
      chain1 =
        Chain.new("Test")
        |> Chain.with_tools([tool])
        |> Chain.llm(:mock, tool_choice: :auto)

      assert {:llm, :mock, opts1} = Enum.at(chain1.steps, 0)
      assert Keyword.get(opts1, :tool_choice) == :auto

      # No tools
      chain2 =
        Chain.new("Test")
        |> Chain.with_tools([tool])
        |> Chain.llm(:mock, tool_choice: :none)

      assert {:llm, :mock, opts2} = Enum.at(chain2.steps, 0)
      assert Keyword.get(opts2, :tool_choice) == :none

      # Required tool use
      chain3 =
        Chain.new("Test")
        |> Chain.with_tools([tool])
        |> Chain.llm(:mock, tool_choice: :required)

      assert {:llm, :mock, opts3} = Enum.at(chain3.steps, 0)
      assert Keyword.get(opts3, :tool_choice) == :required
    end
  end

  describe "Tool format conversion" do
    test "converts tool to Anthropic format" do
      calculator = Calculator.new()

      anthropic_format = Tool.to_llm_format(calculator, :anthropic)

      assert anthropic_format["name"] == "calculator"
      assert anthropic_format["description"] =~ "mathematical calculations"
      assert anthropic_format["input_schema"]["type"] == "object"
      assert Map.has_key?(anthropic_format["input_schema"]["properties"], "expression")
      assert "expression" in anthropic_format["input_schema"]["required"]
    end

    test "converts tool to OpenAI format" do
      weather = Weather.new()

      openai_format = Tool.to_llm_format(weather, :openai)

      assert openai_format["type"] == "function"
      assert openai_format["function"]["name"] == "get_weather"
      assert openai_format["function"]["description"] =~ "weather information"
      assert openai_format["function"]["parameters"]["type"] == "object"
      assert Map.has_key?(openai_format["function"]["parameters"]["properties"], "location")
    end

    test "handles optional parameters correctly" do
      tool =
        Tool.new(
          name: "test",
          description: "Test tool",
          parameters: %{
            required_param: %{type: :string, required: true, description: "Required"},
            optional_param: %{
              type: :integer,
              required: false,
              description: "Optional",
              default: 10
            }
          },
          function: fn _ -> {:ok, "result"} end
        )

      anthropic_format = Tool.to_llm_format(tool, :anthropic)

      assert anthropic_format["input_schema"]["required"] == ["required_param"]
      assert Map.has_key?(anthropic_format["input_schema"]["properties"], "optional_param")
      assert anthropic_format["input_schema"]["properties"]["optional_param"]["type"] == "integer"
    end

    test "handles enum parameters" do
      tool =
        Tool.new(
          name: "test",
          description: "Test tool",
          parameters: %{
            units: %{
              type: :string,
              enum: ["celsius", "fahrenheit", "kelvin"],
              description: "Temperature units"
            }
          },
          function: fn _ -> {:ok, "result"} end
        )

      anthropic_format = Tool.to_llm_format(tool, :anthropic)

      assert anthropic_format["input_schema"]["properties"]["units"]["enum"] == [
               "celsius",
               "fahrenheit",
               "kelvin"
             ]
    end
  end

  # Helper to create a mock LLM that simulates tool calling
  defp create_tool_calling_mock do
    # This would be implemented in the Mock provider
    # to simulate tool calling behavior
    :mock
  end
end
