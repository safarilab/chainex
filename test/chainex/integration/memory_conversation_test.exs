defmodule Chainex.Integration.MemoryConversationTest do
  use ExUnit.Case, async: false
  
  alias Chainex.Chain
  alias Chainex.Memory

  @moduletag :integration
  @moduletag timeout: 60_000

  describe "conversation memory integration" do
    @tag :live_api
    test "maintains conversation context across multiple chain executions" do
      # Create a conversational chain
      chain = Chain.new("{{message}}")
      |> Chain.with_memory(:conversation)
      |> Chain.llm(:anthropic, temperature: 0, max_tokens: 100)
      
      session_id = "conversation_test_#{:os.system_time(:millisecond)}"
      
      # First interaction
      {:ok, response1} = Chain.run(chain, %{
        message: "Hi, I'm Alice and I love pizza", 
        session_id: session_id
      })
      
      assert is_binary(response1)
      assert String.length(response1) > 0
      
      # Second interaction - should remember Alice
      {:ok, response2} = Chain.run(chain, %{
        message: "What's my name?", 
        session_id: session_id
      })
      
      assert is_binary(response2)
      # Response should contain "Alice" since the LLM should remember from context
      assert String.contains?(String.downcase(response2), "alice")
      
      # Third interaction - should remember pizza preference
      {:ok, response3} = Chain.run(chain, %{
        message: "What food do I like?", 
        session_id: session_id
      })
      
      assert is_binary(response3)
      # Response should mention pizza since it should remember from context
      assert String.contains?(String.downcase(response3), "pizza")
    end

    @tag :live_api
    test "separate sessions maintain independent conversations" do
      chain = Chain.new("{{message}}")
      |> Chain.with_memory(:conversation)
      |> Chain.llm(:anthropic, temperature: 0, max_tokens: 100)
      
      timestamp = :os.system_time(:millisecond)
      session_alice = "alice_#{timestamp}"
      session_bob = "bob_#{timestamp}"
      
      # Alice introduces herself
      {:ok, _} = Chain.run(chain, %{
        message: "Hi, I'm Alice and I'm a doctor", 
        session_id: session_alice
      })
      
      # Bob introduces himself  
      {:ok, _} = Chain.run(chain, %{
        message: "Hi, I'm Bob and I'm a teacher", 
        session_id: session_bob
      })
      
      # Ask Alice's session about her name
      {:ok, alice_response} = Chain.run(chain, %{
        message: "What's my name and job?", 
        session_id: session_alice
      })
      
      # Ask Bob's session about his name
      {:ok, bob_response} = Chain.run(chain, %{
        message: "What's my name and job?", 
        session_id: session_bob
      })
      
      # Verify responses are different and contextual
      assert String.contains?(String.downcase(alice_response), "alice")
      assert String.contains?(String.downcase(alice_response), "doctor") 
      
      assert String.contains?(String.downcase(bob_response), "bob")
      assert String.contains?(String.downcase(bob_response), "teacher")
      
      # Make sure they don't contain each other's info
      refute String.contains?(String.downcase(alice_response), "bob")
      refute String.contains?(String.downcase(bob_response), "alice")
    end

    test "memory context injection with mock provider" do
      # Create a memory instance manually to examine its contents
      memory = Memory.new(:conversation)
      
      # Store some conversation history manually
      memory = Memory.store(memory, "msg1", %{
        role: :user, 
        content: "My favorite color is blue",
        timestamp: :os.system_time(:millisecond)
      })
      
      memory = Memory.store(memory, "msg2", %{
        role: :assistant, 
        content: "That's a nice color! Blue is very calming.",
        timestamp: :os.system_time(:millisecond)
      })
      
      # Create chain with pre-populated memory
      chain = Chain.new("What color do I like?")
      |> Chain.llm(:mock, response: "Based on our conversation, you like blue!")
      
      # Manually set the memory instance
      updated_chain = %{chain | options: 
        Keyword.put(chain.options, :memory, memory)
      }
      
      {:ok, result} = Chain.run(updated_chain, %{session_id: "default"})
      
      assert result == "Based on our conversation, you like blue!"
    end

    @tag :live_api
    test "memory with transform steps and multiple LLM calls" do
      chain = Chain.new("{{input}}")
      |> Chain.with_memory(:conversation)
      |> Chain.llm(:anthropic, temperature: 0, max_tokens: 50)
      |> Chain.transform(fn response -> "The AI said: #{response}" end)
      |> Chain.llm(:anthropic, temperature: 0, max_tokens: 50)
      
      session_id = "transform_test_#{:os.system_time(:millisecond)}"
      
      # First conversation
      {:ok, result1} = Chain.run(chain, %{
        input: "I'm learning Elixir",
        session_id: session_id
      })
      
      assert is_binary(result1)
      
      # Second conversation should have context from first
      {:ok, result2} = Chain.run(chain, %{
        input: "What was I learning?",
        session_id: session_id
      })
      
      assert is_binary(result2)
      assert String.contains?(String.downcase(result2), "elixir")
    end

    test "buffer memory integration" do
      # Test that buffer memory also works with chains (simpler, no conversation context)
      chain = Chain.new("Store: {{data}}")
      |> Chain.with_memory(:buffer)
      |> Chain.llm(:mock, response: "Data stored successfully")
      
      {:ok, result} = Chain.run(chain, %{data: "test information"})
      assert result == "Data stored successfully"
    end

    @tag :live_api
    test "conversation memory with context limit" do
      # Test that context limit works properly
      chain = Chain.new("{{message}}")
      |> Chain.with_memory(:conversation)
      |> Chain.llm(:anthropic, temperature: 0, max_tokens: 50)
      
      # Add context limit option
      updated_chain = %{chain | options: 
        Keyword.put(chain.options, :context_limit, 2)  # Only last 2 messages
      }
      
      session_id = "context_limit_test_#{:os.system_time(:millisecond)}"
      
      # Have several interactions to build up history
      {:ok, _} = Chain.run(updated_chain, %{message: "First message", session_id: session_id})
      {:ok, _} = Chain.run(updated_chain, %{message: "Second message", session_id: session_id})
      {:ok, _} = Chain.run(updated_chain, %{message: "Third message", session_id: session_id})
      
      # This should still work even with context limit
      {:ok, result} = Chain.run(updated_chain, %{message: "Fourth message", session_id: session_id})
      assert is_binary(result)
    end
  end
end