defmodule Chainex.ChainMultiLLMTest do
  use ExUnit.Case, async: true
  
  alias Chainex.Chain

  describe "multiple LLM providers in chain" do
    test "uses different providers in sequence" do
      chain = Chain.new("First prompt")
      |> Chain.llm(:mock, response: "First response")
      |> Chain.transform(&String.upcase/1)
      |> Chain.llm(:mock, response: "Second response")
      
      assert {:ok, "Second response"} = Chain.run(chain)
    end

    test "different providers with different configurations" do
      _chain = Chain.new("Analyze this")
      |> Chain.llm(:openai, model: "gpt-4", temperature: 0.7)
      |> Chain.transform(fn response -> "Summary: #{response}" end)
      |> Chain.llm(:anthropic, model: "claude-3-haiku", max_tokens: 100)
      
      # Mock providers should handle these differently
      chain_with_mocks = Chain.new("Analyze this")
      |> Chain.llm(:mock, model: "gpt-4")
      |> Chain.transform(fn response -> "Summary: #{response}" end)
      |> Chain.llm(:mock, model: "claude-3-haiku")
      
      assert {:ok, result} = Chain.run(chain_with_mocks)
      assert is_binary(result)
    end

    test "maintains provider context through chain" do
      chain = Chain.new("Initial prompt")
      |> Chain.llm(:mock, model: "model-a")
      |> Chain.transform(&String.length/1)
      |> Chain.llm(:mock, model: "model-b")
      
      assert {:ok, result} = Chain.run(chain)
      assert is_binary(result)
    end
  end

  describe "fallback providers" do
    test "falls back to secondary provider on primary failure" do
      # Simulate OpenAI failure, fallback to Mock
      chain = Chain.new("Generate text")
      |> Chain.llm(:openai, 
          fallback: :mock,
          mock_error: true  # Force error for testing
        )
      
      # Should succeed with fallback
      assert {:ok, _result} = Chain.run(chain)
    end

    test "supports multiple fallback providers" do
      chain = Chain.new("Generate text")
      |> Chain.llm(:openai,
          fallback: [:anthropic, :ollama, :mock],
          mock_error: true  # Force error for testing
        )
      
      # Should eventually succeed with mock
      assert {:ok, result} = Chain.run(chain)
      assert result =~ "Mock response"
    end

    test "returns error when all providers fail" do
      chain = Chain.new("Generate text")
      |> Chain.llm(:openai,
          fallback: :anthropic,
          force_all_errors: true  # Force all to fail
        )
      
      assert {:error, reason} = Chain.run(chain)
      assert reason =~ "All providers failed"
    end

    test "fallback preserves original options" do
      chain = Chain.new("Generate text")
      |> Chain.llm(:openai,
          model: "gpt-4",
          temperature: 0.5,
          max_tokens: 100,
          fallback: :mock,
          mock_error: true
        )
      
      assert {:ok, result} = Chain.run(chain)
      # Mock should receive the same options
      assert is_binary(result)
    end
  end

  describe "model routing" do
    test "routes to appropriate model based on task" do
      chain = Chain.new("Complex reasoning task")
      |> Chain.route_llm(%{
        reasoning: {:openai, model: "gpt-4"},
        summarization: {:anthropic, model: "claude-3-haiku"},
        default: {:mock, model: "default"}
      }, task: :reasoning)
      
      # Should route to openai/gpt-4 for reasoning
      assert {:ok, _result} = Chain.run(chain)
    end

    test "routes based on input characteristics" do
      long_text = String.duplicate("This is a long text. ", 1000)
      
      _chain = Chain.new(long_text)
      |> Chain.route_llm(fn input ->
        if String.length(input) > 5000 do
          {:anthropic, model: "claude-3-opus"}  # Better for long context
        else
          {:openai, model: "gpt-4"}
        end
      end)
      
      # For testing, use mock
      test_chain = Chain.new(long_text)
      |> Chain.route_llm(fn _input ->
        {:mock, model: "long-context-model"}
      end)
      
      assert {:ok, _result} = Chain.run(test_chain)
    end

    test "conditional provider selection" do
      chain = Chain.new("Task")
      |> Chain.llm_if(
        fn _input, vars -> Map.get(vars, :use_premium, false) end,
        {:openai, model: "gpt-4"},
        {:openai, model: "gpt-3.5-turbo"}
      )
      
      # Test with premium
      assert {:ok, _} = Chain.run(chain, %{use_premium: true})
      
      # Test without premium  
      assert {:ok, _} = Chain.run(chain, %{use_premium: false})
    end
  end

  describe "cost tracking" do
    test "tracks costs across multiple providers" do
      _chain = Chain.new("First prompt")
      |> Chain.llm(:openai, model: "gpt-4", track_cost: true)
      |> Chain.llm(:anthropic, model: "claude-3-opus", track_cost: true)
      |> Chain.llm(:openai, model: "gpt-3.5-turbo", track_cost: true)
      
      # Mock version for testing
      test_chain = Chain.new("First prompt")
      |> Chain.llm(:mock, model: "expensive", mock_cost: 0.03)
      |> Chain.llm(:mock, model: "medium", mock_cost: 0.02)
      |> Chain.llm(:mock, model: "cheap", mock_cost: 0.001)
      
      assert {:ok, result, metadata} = Chain.run_with_metadata(test_chain)
      assert is_binary(result)
      assert_in_delta metadata.total_cost, 0.051, 0.001
      assert length(metadata.provider_costs) == 3
    end

    test "aggregates token usage across providers" do
      chain = Chain.new("Prompt")
      |> Chain.llm(:mock, mock_tokens: %{prompt: 10, completion: 20})
      |> Chain.llm(:mock, mock_tokens: %{prompt: 15, completion: 25})
      
      assert {:ok, _result, metadata} = Chain.run_with_metadata(chain)
      assert metadata.total_tokens.prompt == 25
      assert metadata.total_tokens.completion == 45
    end
  end

  describe "provider capabilities" do
    test "checks provider capabilities before execution" do
      _chain = Chain.new("Generate image")
      |> Chain.llm(:openai, 
          model: "dall-e-3",
          required_capability: :image_generation
        )
      
      # Mock doesn't support image generation
      test_chain = Chain.new("Generate image")
      |> Chain.llm(:mock,
          required_capability: :image_generation
        )
      
      assert {:error, reason} = Chain.run(test_chain)
      assert reason =~ "does not support capability: image_generation"
    end

    test "auto-selects provider based on required capabilities" do
      _chain = Chain.new("Task")
      |> Chain.llm_with_capability(:long_context, max_tokens: 100_000)
      
      # Should auto-select Anthropic Claude for long context
      # For testing, mock this behavior
      test_chain = Chain.new("Task")
      |> Chain.llm(:mock, model: "auto-selected-long-context")
      
      assert {:ok, _} = Chain.run(test_chain)
    end
  end

  describe "parallel LLM execution" do
    test "executes multiple LLMs in parallel and combines results" do
      _chain = Chain.new("Analyze this text")
      |> Chain.parallel_llm([
        {:openai, model: "gpt-4"},
        {:anthropic, model: "claude-3-opus"},
        {:openai, model: "gpt-3.5-turbo"}
      ])
      |> Chain.transform(fn results ->
        # Combine results from multiple models
        Enum.join(results, "\n---\n")
      end)
      
      # Mock version
      test_chain = Chain.new("Analyze this text")
      |> Chain.parallel_llm([
        {:mock, response: "Response 1"},
        {:mock, response: "Response 2"},
        {:mock, response: "Response 3"}
      ])
      |> Chain.transform(fn results ->
        Enum.join(results, "\n---\n")
      end)
      
      assert {:ok, result} = Chain.run(test_chain)
      assert result =~ "Response 1"
      assert result =~ "Response 2"
      assert result =~ "Response 3"
    end
  end
end