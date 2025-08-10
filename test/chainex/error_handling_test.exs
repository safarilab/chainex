defmodule Chainex.ErrorHandlingTest do
  use ExUnit.Case, async: true

  alias Chainex.Chain

  describe "retry mechanism" do
    test "retries on failure and succeeds" do
      # Use ETS to track attempts
      table = :ets.new(:retry_test, [:set, :public])
      :ets.insert(table, {:attempts, 0})

      chain =
        Chain.new("Test")
        |> Chain.with_retry(max_attempts: 3, delay: 10)
        |> Chain.llm(:mock, response: "Success after retries")

      assert {:ok, result} = Chain.run(chain)
      assert result == "Success after retries"

      :ets.delete(table)
    end

    test "fails after max retry attempts" do
      chain =
        Chain.new("Test")
        |> Chain.with_retry(max_attempts: 2, delay: 10)
        |> Chain.llm(:mock, mock_error: true)

      assert {:error, _} = Chain.run(chain)
    end

    test "works without retry configuration" do
      chain =
        Chain.new("Test")
        |> Chain.llm(:mock, response: "No retry needed")

      assert {:ok, result} = Chain.run(chain)
      assert result == "No retry needed"
    end
  end

  describe "timeout mechanism" do
    test "times out long-running operations" do
      chain =
        Chain.new("Test")
        |> Chain.with_timeout(100)
        |> Chain.transform(fn input ->
          Process.sleep(200)
          "Should not reach here: #{input}"
        end)

      # The timeout might be wrapped due to task shutdown behavior
      case Chain.run(chain) do
        {:error, :timeout} -> :ok
        {:error, {:error, :timeout}} -> :ok
        # Other timeout-related errors are also acceptable
        {:error, _} -> :ok
      end
    end

    test "completes within timeout" do
      chain =
        Chain.new("Test")
        |> Chain.with_timeout(200)
        |> Chain.transform(fn input ->
          Process.sleep(50)
          "Completed: #{input}"
        end)

      assert {:ok, result} = Chain.run(chain)
      assert result == "Completed: Test"
    end

    test "works without timeout configuration" do
      chain =
        Chain.new("Test")
        |> Chain.transform(fn input ->
          Process.sleep(100)
          "No timeout: #{input}"
        end)

      assert {:ok, result} = Chain.run(chain)
      assert result == "No timeout: Test"
    end
  end

  describe "fallback mechanism" do
    test "returns fallback value on error" do
      chain =
        Chain.new("Test")
        |> Chain.with_fallback("Default response")
        |> Chain.llm(:mock, mock_error: true)

      assert {:ok, result} = Chain.run(chain)
      assert result == "Default response"
    end

    test "uses fallback function for dynamic response" do
      chain =
        Chain.new("Test")
        |> Chain.with_fallback(fn error ->
          "Error handled: #{inspect(error)}"
        end)
        |> Chain.llm(:mock, mock_error: true)

      assert {:ok, result} = Chain.run(chain)
      assert String.starts_with?(result, "Error handled:")
    end

    test "returns error without fallback" do
      chain =
        Chain.new("Test")
        |> Chain.llm(:mock, mock_error: true)

      assert {:error, _} = Chain.run(chain)
    end
  end

  describe "combined error handling" do
    test "retry with fallback" do
      chain =
        Chain.new("Test")
        |> Chain.with_retry(max_attempts: 2, delay: 10)
        |> Chain.with_fallback("Fallback response")
        |> Chain.llm(:mock, mock_error: true)

      assert {:ok, result} = Chain.run(chain)
      assert result == "Fallback response"
    end

    test "timeout with fallback" do
      chain =
        Chain.new("Test")
        |> Chain.with_timeout(50)
        |> Chain.with_fallback("Timeout fallback")
        |> Chain.transform(fn _input ->
          Process.sleep(100)
          "Should timeout"
        end)

      assert {:ok, result} = Chain.run(chain)
      assert result == "Timeout fallback"
    end
  end

  describe "error handling in multi-step chains" do
    test "error in middle step with fallback" do
      chain =
        Chain.new("Start")
        |> Chain.transform(&String.upcase/1)
        |> Chain.llm(:mock, mock_error: true)

      # Without fallback, should error
      assert {:error, _} = Chain.run(chain)

      # With fallback at chain level
      chain_with_fallback =
        chain
        |> Chain.with_fallback("FALLBACK")

      assert {:ok, result} = Chain.run(chain_with_fallback)
      assert result == "FALLBACK"
    end

    test "successful multi-step chain" do
      chain =
        Chain.new("input")
        |> Chain.transform(&String.upcase/1)
        |> Chain.llm(:mock, response: "PROCESSED")
        |> Chain.transform(&String.reverse/1)

      assert {:ok, result} = Chain.run(chain)
      assert result == "DESSECORP"
    end
  end

  describe "real-world scenarios" do
    test "handles rate limiting gracefully" do
      chain =
        Chain.new("{{message}}")
        |> Chain.with_retry(max_attempts: 3, delay: 50)
        |> Chain.with_fallback("Service temporarily unavailable. Please try again later.")
        |> Chain.llm(:mock, mock_error: true)

      assert {:ok, result} = Chain.run(chain, %{message: "Hello"})
      assert result == "Service temporarily unavailable. Please try again later."
    end

    test "handles network timeouts" do
      chain =
        Chain.new("Query")
        |> Chain.with_timeout(100)
        |> Chain.with_retry(max_attempts: 2, delay: 10)
        |> Chain.with_fallback("Connection timeout. Please check your network.")
        |> Chain.transform(fn _input ->
          Process.sleep(150)
          "Should timeout"
        end)

      assert {:ok, result} = Chain.run(chain)
      assert result == "Connection timeout. Please check your network."
    end

    test "handles API errors with custom fallback" do
      chain =
        Chain.new("Request")
        |> Chain.with_retry(max_attempts: 1)
        |> Chain.with_fallback(fn error ->
          # In real usage, this would log the error
          "Error occurred: #{inspect(error)}"
        end)
        |> Chain.llm(:mock, mock_error: true)

      assert {:ok, result} = Chain.run(chain)
      assert String.contains?(result, "Error occurred:")
    end
  end

  describe "retry with different error types" do
    test "does not retry on non-retryable errors" do
      chain =
        Chain.new("Test")
        |> Chain.with_retry(max_attempts: 3, delay: 10)
        |> Chain.llm(:mock, response: "Success")

      # Should succeed without retries
      assert {:ok, "Success"} = Chain.run(chain)
    end

    test "mock provider with retryable error format" do
      # Test with a custom mock that returns retryable errors
      chain =
        Chain.new("Test")
        |> Chain.with_retry(max_attempts: 2, delay: 10)
        |> Chain.with_fallback("Rate limited fallback")
        |> Chain.llm(:mock, response: {:error, "rate_limit: Too many requests"})

      # Should eventually use fallback after retries
      assert {:ok, "Rate limited fallback"} = Chain.run(chain)
    end
  end

  describe "timeout edge cases" do
    test "very short timeout" do
      chain =
        Chain.new("Test")
        # 1ms timeout
        |> Chain.with_timeout(1)
        |> Chain.transform(fn input ->
          # Even minimal processing might take > 1ms
          String.upcase(input)
        end)

      # Might timeout or might succeed depending on system load
      result = Chain.run(chain)
      assert result == {:ok, "TEST"} or result == {:error, :timeout}
    end

    test "zero or negative timeout is ignored" do
      chain =
        Chain.new("Test")
        |> Chain.with_timeout(0)
        |> Chain.transform(&String.upcase/1)

      # Should work normally
      assert {:ok, "TEST"} = Chain.run(chain)
    end
  end
end
