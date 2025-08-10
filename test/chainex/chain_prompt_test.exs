defmodule Chainex.Chain.PromptTest do
  use ExUnit.Case

  alias Chainex.{Chain, Prompt}

  describe "Chain.prompt/2 with strings" do
    test "replaces template variables" do
      chain =
        Chain.new("machine learning")
        |> Chain.prompt("Explain {{input}} in simple terms")
        |> Chain.llm(:mock)

      assert {:ok, result} = Chain.run(chain)
      assert result == "Mock response for: Explain machine learning in simple terms"
    end

    test "uses variables from run/2" do
      chain =
        Chain.new("initial input")
        |> Chain.prompt("{{style}} explanation of {{topic}}: {{input}}")
        |> Chain.llm(:mock)

      assert {:ok, result} = Chain.run(chain, %{style: "Detailed", topic: "AI"})
      assert result == "Mock response for: Detailed explanation of AI: initial input"
    end

    test "handles missing variables gracefully" do
      chain =
        Chain.new("test input")
        |> Chain.prompt("Explain {{input}} for {{missing_var}}")
        |> Chain.llm(:mock)

      # Should resolve with empty string for missing variable
      assert {:ok, result} = Chain.run(chain)
      assert result == "Mock response for: Explain test input for "
    end
  end

  describe "Chain.prompt/2 with Prompt structs" do
    test "uses Prompt struct with defaults" do
      prompt_template =
        Prompt.new(
          "{{greeting}} {{name}}, explain {{topic}}",
          # Default value
          %{greeting: "Hello"}
        )

      chain =
        Chain.new("quantum computing")
        |> Chain.prompt(prompt_template)
        |> Chain.llm(:mock)

      assert {:ok, result} = Chain.run(chain, %{name: "Alice", topic: "recursion"})
      assert result == "Mock response for: Hello Alice, explain recursion"
    end

    test "Prompt struct variables override defaults" do
      prompt_template =
        Prompt.new(
          "{{greeting}} {{name}}",
          %{greeting: "Hello", name: "World"}
        )

      chain =
        Chain.new("test")
        |> Chain.prompt(prompt_template)
        |> Chain.llm(:mock)

      assert {:ok, result} = Chain.run(chain, %{greeting: "Hi", name: "Alice"})
      assert result == "Mock response for: Hi Alice"
    end

    test "uses input variable in Prompt struct" do
      prompt_template = Prompt.new("Transform this: {{input}} into {{format}}")

      chain =
        Chain.new("raw data")
        |> Chain.prompt(prompt_template)
        |> Chain.llm(:mock)

      assert {:ok, result} = Chain.run(chain, %{format: "JSON"})
      assert result == "Mock response for: Transform this: raw data into JSON"
    end
  end

  describe "Chain.prompt/2 with functions" do
    test "uses function with 1 arity" do
      prompt_fn = fn input ->
        "Please analyze: #{input}"
      end

      chain =
        Chain.new("user feedback")
        |> Chain.prompt(prompt_fn)
        |> Chain.llm(:mock)

      assert {:ok, result} = Chain.run(chain)
      assert result == "Mock response for: Please analyze: user feedback"
    end

    test "uses function with 2 arity (input + variables)" do
      prompt_fn = fn input, vars ->
        "#{Map.get(vars, :action, "Process")} this #{Map.get(vars, :type, "data")}: #{input}"
      end

      chain =
        Chain.new("customer data")
        |> Chain.prompt(prompt_fn)
        |> Chain.llm(:mock)

      assert {:ok, result} = Chain.run(chain, %{action: "Analyze", type: "feedback"})
      assert result == "Mock response for: Analyze this feedback: customer data"
    end

    test "handles function errors gracefully" do
      prompt_fn = fn _input ->
        raise "Function error"
      end

      chain =
        Chain.new("test input")
        |> Chain.prompt(prompt_fn)
        |> Chain.llm(:mock)

      assert {:error, "Function error"} = Chain.run(chain)
    end
  end

  describe "Chain.prompt/2 chaining" do
    test "chains multiple prompt transformations" do
      chain =
        Chain.new("artificial intelligence")
        |> Chain.prompt("Research: {{input}}")
        |> Chain.llm(:mock)
        |> Chain.prompt("Summarize this research: {{input}}")
        |> Chain.llm(:mock)
        |> Chain.prompt("Create 3 key takeaways from: {{input}}")
        |> Chain.llm(:mock)

      assert {:ok, result} = Chain.run(chain)
      # Each step transforms the prompt further
      expected =
        "Mock response for: Create 3 key takeaways from: Mock response for: Summarize this research: Mock response for: Research: artificial intelligence"

      assert result == expected
    end

    test "combines prompt with transform steps" do
      chain =
        Chain.new("machine learning")
        |> Chain.prompt("Explain {{input}} briefly")
        |> Chain.llm(:mock)
        |> Chain.transform(&String.upcase/1)
        |> Chain.prompt("Expand on this: {{input}}")
        |> Chain.llm(:mock)

      assert {:ok, result} = Chain.run(chain)

      expected =
        "Mock response for: Expand on this: MOCK RESPONSE FOR: EXPLAIN MACHINE LEARNING BRIEFLY"

      assert result == expected
    end

    test "uses variables across chained prompts" do
      context_prompt =
        Prompt.new(
          "Context: {{context}}\nQuestion: {{input}}",
          %{context: "You are a helpful teacher"}
        )

      followup_fn = fn input, vars ->
        "Follow up on the #{Map.get(vars, :level, "basic")} explanation: #{input}"
      end

      chain =
        Chain.new("What is recursion?")
        |> Chain.prompt(context_prompt)
        |> Chain.llm(:mock)
        |> Chain.prompt(followup_fn)
        |> Chain.llm(:mock)

      assert {:ok, result} =
               Chain.run(chain, %{
                 context: "Teaching advanced programming",
                 level: "advanced"
               })

      expected =
        "Mock response for: Follow up on the advanced explanation: Mock response for: Context: Teaching advanced programming\nQuestion: What is recursion?"

      assert result == expected
    end
  end

  describe "edge cases and errors" do
    test "handles invalid prompt template type" do
      chain =
        Chain.new("test")
        # Invalid type
        |> Chain.prompt(123)
        |> Chain.llm(:mock)

      assert {:error, "Invalid prompt template type"} = Chain.run(chain)
    end

    test "handles Prompt render errors" do
      # This would need the existing Prompt module to handle validation
      invalid_prompt = %Chainex.Prompt{
        template: "{{unclosed",
        variables: %{},
        options: %{strict: true}
      }

      chain =
        Chain.new("test")
        |> Chain.prompt(invalid_prompt)
        |> Chain.llm(:mock)

      # Should handle the error from Prompt.render
      assert {:error, _} = Chain.run(chain)
    end

    test "prompt step with empty input" do
      chain =
        Chain.new("")
        |> Chain.prompt("Process: {{input}}")
        |> Chain.llm(:mock)

      assert {:ok, result} = Chain.run(chain)
      assert result == "Mock response for: Process: "
    end
  end
end
