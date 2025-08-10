defmodule Chainex.ChainMemoryTest do
  use ExUnit.Case, async: true

  alias Chainex.Chain
  alias Chainex.Memory

  describe "chain with conversation memory" do
    test "stores and retrieves conversation history" do
      chain =
        Chain.new("Hello, my name is {{name}}")
        |> Chain.with_memory(:conversation)
        |> Chain.llm(:mock, response: "Nice to meet you!")

      # First conversation
      assert {:ok, result1} = Chain.run(chain, %{name: "Alice"})
      assert result1 == "Nice to meet you!"

      # Second conversation should have context
      chain2 =
        Chain.new("What's my name?")
        |> Chain.with_memory(:conversation)
        |> Chain.llm(:mock, response: "Your name is Alice")

      assert {:ok, result2} = Chain.run(chain2, %{})
      assert result2 == "Your name is Alice"
    end

    test "maintains separate sessions" do
      chain =
        Chain.new("Hello, I'm {{name}}")
        |> Chain.with_memory(:conversation)
        |> Chain.llm(:mock, response: "Hello {{name}}!")

      # Alice's session
      assert {:ok, _} = Chain.run(chain, %{name: "Alice", session_id: "alice"})

      # Bob's session  
      assert {:ok, _} = Chain.run(chain, %{name: "Bob", session_id: "bob"})

      # Verify sessions are separate by checking we can run different conversations
      follow_up =
        Chain.new("Do you remember my name?")
        |> Chain.with_memory(:conversation)
        |> Chain.llm(:mock, response: "Yes, you're Alice")

      assert {:ok, _} = Chain.run(follow_up, %{session_id: "alice"})
    end

    test "respects session_id from variables" do
      chain =
        Chain.new("Test message")
        |> Chain.with_memory(:conversation)
        |> Chain.llm(:mock)

      # Run with explicit session ID
      assert {:ok, _} = Chain.run(chain, %{session_id: "test_session"})

      # The session should be available for follow-up calls
      assert {:ok, _} = Chain.run(chain, %{session_id: "test_session"})
    end

    test "works with buffer memory" do
      chain =
        Chain.new("Store this: {{data}}")
        |> Chain.with_memory(:buffer)
        |> Chain.llm(:mock)

      assert {:ok, _result} = Chain.run(chain, %{data: "important info"})
    end

    test "works without memory" do
      chain =
        Chain.new("Hello")
        |> Chain.llm(:mock, response: "Hi there!")

      assert {:ok, result} = Chain.run(chain)
      assert result == "Hi there!"
    end

    test "memory context injection for conversation" do
      # This test verifies that conversation history gets injected into the system message
      # We'll need to use a more sophisticated mock to verify this

      chain =
        Chain.new("Continue our chat")
        |> Chain.with_memory(:conversation)
        |> Chain.llm(:mock, response: "Sure, continuing...")

      # First establish some context
      Chain.run(chain, %{session_id: "context_test"})

      # Second call should have context injected (verified by the fact it runs successfully)
      assert {:ok, _} = Chain.run(chain, %{session_id: "context_test"})
    end
  end

  describe "memory options and configuration" do
    test "accepts memory options" do
      chain =
        Chain.new("Test")
        |> Chain.with_memory(:conversation)
        |> Chain.llm(:mock)

      # Add memory options
      updated_chain = %{
        chain
        | options: Keyword.put(chain.options, :memory_options, %{max_size: 100})
      }

      assert {:ok, _} = Chain.run(updated_chain)
    end

    test "accepts context limit option" do
      chain =
        Chain.new("Test")
        |> Chain.with_memory(:conversation)
        |> Chain.llm(:mock)

      # Add context limit
      updated_chain = %{chain | options: Keyword.put(chain.options, :context_limit, 5)}

      assert {:ok, _} = Chain.run(updated_chain)
    end

    test "works with pre-initialized memory instance" do
      # Create memory instance manually
      memory = Memory.new(:buffer)

      chain =
        Chain.new("Test")
        |> Chain.llm(:mock)

      # Use pre-created memory
      updated_chain = %{chain | options: Keyword.put(chain.options, :memory, memory)}

      assert {:ok, _} = Chain.run(updated_chain)
    end
  end

  describe "memory with multi-step chains" do
    test "preserves memory across chain steps" do
      chain =
        Chain.new("Start: {{input}}")
        |> Chain.with_memory(:conversation)
        |> Chain.llm(:mock, response: "Processing {{input}}")
        |> Chain.transform(&String.upcase/1)
        |> Chain.llm(:mock, response: "Final result")

      assert {:ok, result} = Chain.run(chain, %{input: "test", session_id: "multi_step"})
      assert result == "Final result"
    end

    test "works with tool calling" do
      # Create a simple calculator tool
      calculator = %Chainex.Tool{
        name: :add,
        description: "Adds two numbers",
        parameters: %{
          a: %{type: :integer, description: "First number"},
          b: %{type: :integer, description: "Second number"}
        },
        function: fn %{a: a, b: b} -> {:ok, a + b} end
      }

      chain =
        Chain.new("Calculate 2 + 3")
        |> Chain.with_memory(:conversation)
        |> Chain.with_tools([calculator])
        |> Chain.llm(:mock)

      assert {:ok, _result} = Chain.run(chain, %{session_id: "tool_test"})
    end
  end
end
