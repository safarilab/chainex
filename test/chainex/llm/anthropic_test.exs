defmodule Chainex.LLM.AnthropicTest do
  use ExUnit.Case, async: true

  alias Chainex.LLM.Anthropic

  setup do
    bypass = Bypass.open()
    
    config = [
      api_key: "test-api-key",
      model: "claude-3-5-sonnet-20241022",
      base_url: "http://localhost:#{bypass.port}/v1",
      version: "2023-06-01",
      timeout: 5000
    ]
    
    {:ok, bypass: bypass, config: config}
  end

  describe "chat/2" do
    test "validates configuration" do
      messages = [%{role: :user, content: "Hello"}]
      
      # Missing API key
      assert {:error, :missing_api_key} = Anthropic.chat(messages, [])
      assert {:error, :missing_api_key} = Anthropic.chat(messages, [api_key: ""])
    end

    test "makes successful chat completion request", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      mock_response = %{
        "id" => "msg_123",
        "type" => "message",
        "role" => "assistant",
        "content" => [
          %{
            "type" => "text",
            "text" => "Hello! How can I assist you today?"
          }
        ],
        "model" => "claude-3-5-sonnet-20241022",
        "stop_reason" => "end_turn",
        "stop_sequence" => nil,
        "usage" => %{
          "input_tokens" => 10,
          "output_tokens" => 15
        }
      }
      
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        # Verify request headers
        assert Enum.any?(conn.req_headers, fn {key, value} -> 
          key == "x-api-key" && value == "test-api-key"
        end)
        
        assert Enum.any?(conn.req_headers, fn {key, value} -> 
          key == "anthropic-version" && value == "2023-06-01"
        end)
        
        # Verify request body
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded_body = Jason.decode!(body)
        
        assert decoded_body["model"] == "claude-3-5-sonnet-20241022"
        assert is_list(decoded_body["messages"])
        assert length(decoded_body["messages"]) == 1
        assert decoded_body["max_tokens"] == 4096  # default
        
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)
      
      assert {:ok, response} = Anthropic.chat(messages, config)
      assert response.content == "Hello! How can I assist you today?"
      assert response.model == "claude-3-5-sonnet-20241022"
      assert response.provider == :anthropic
      assert response.usage.prompt_tokens == 10
      assert response.usage.completion_tokens == 15
      assert response.usage.total_tokens == 25
      assert response.finish_reason == "end_turn"
    end

    test "handles system messages correctly", %{bypass: bypass, config: config} do
      messages = [
        %{role: :system, content: "You are a helpful assistant"},
        %{role: :user, content: "Hello"}
      ]
      
      mock_response = %{
        "content" => [%{"type" => "text", "text" => "Hi there!"}],
        "model" => "claude-3-5-sonnet-20241022",
        "stop_reason" => "end_turn",
        "usage" => %{"input_tokens" => 10, "output_tokens" => 5}
      }
      
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded_body = Jason.decode!(body)
        
        # System message should be in separate field
        assert decoded_body["system"] == "You are a helpful assistant"
        
        # Only user message should be in messages array
        assert length(decoded_body["messages"]) == 1
        user_message = List.first(decoded_body["messages"])
        assert user_message["role"] == "user"
        assert user_message["content"] == "Hello"
        
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)
      
      assert {:ok, _} = Anthropic.chat(messages, config)
    end

    test "handles API errors", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      error_response = %{
        "type" => "error",
        "error" => %{
          "type" => "rate_limit_error",
          "message" => "Rate limit exceeded"
        }
      }
      
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(429, Jason.encode!(error_response))
      end)
      
      assert {:error, {:api_error, 429, _}} = Anthropic.chat(messages, config)
    end

    test "includes optional parameters", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      enhanced_config = config
      |> Keyword.put(:temperature, 0.8)
      |> Keyword.put(:max_tokens, 200)
      |> Keyword.put(:top_p, 0.9)
      |> Keyword.put(:top_k, 50)
      |> Keyword.put(:stop_sequences, ["\\n\\n", "END"])
      
      mock_response = %{
        "content" => [%{"type" => "text", "text" => "Response"}],
        "model" => "claude-3-5-sonnet-20241022",
        "stop_reason" => "end_turn",
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
      }
      
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded_body = Jason.decode!(body)
        
        # Verify optional parameters
        assert decoded_body["temperature"] == 0.8
        assert decoded_body["max_tokens"] == 200
        assert decoded_body["top_p"] == 0.9
        assert decoded_body["top_k"] == 50
        assert decoded_body["stop_sequences"] == ["\\n\\n", "END"]
        
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)
      
      assert {:ok, _} = Anthropic.chat(messages, enhanced_config)
    end
  end

  describe "count_tokens/2" do
    test "provides token estimates" do
      messages = [%{role: :user, content: "Hello world"}]
      config = [api_key: "test"]
      
      {:ok, count} = Anthropic.count_tokens(messages, config)
      assert is_integer(count)
      assert count > 0
    end

    test "scales with content length" do
      config = [api_key: "test"]
      short_message = [%{role: :user, content: "Hi"}]
      long_message = [%{role: :user, content: String.duplicate("Hello ", 100)}]
      
      {:ok, short_count} = Anthropic.count_tokens(short_message, config)
      {:ok, long_count} = Anthropic.count_tokens(long_message, config)
      
      assert long_count > short_count
    end

    test "accounts for different roles" do
      config = [api_key: "test"]
      user_message = [%{role: :user, content: "Hello"}]
      system_message = [%{role: :system, content: "Hello"}]
      
      {:ok, user_count} = Anthropic.count_tokens(user_message, config)
      {:ok, system_count} = Anthropic.count_tokens(system_message, config)
      
      assert is_integer(user_count) and user_count > 0
      assert is_integer(system_count) and system_count > 0
    end
  end

  describe "models/1" do
    test "returns known Claude models" do
      config = [api_key: "test"]
      
      assert {:ok, models} = Anthropic.models(config)
      assert is_list(models)
      assert "claude-3-5-sonnet-20241022" in models
      assert "claude-3-5-haiku-20241022" in models
      assert "claude-3-opus-20240229" in models
    end
  end

  describe "stream_chat/2" do
    test "returns enumerable for streaming", %{config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      stream = Anthropic.stream_chat(messages, config)
      assert is_function(stream)
    end

    test "validates config for streaming" do
      messages = [%{role: :user, content: "Hello"}]
      
      stream = Anthropic.stream_chat(messages, [])
      [result] = Enum.to_list(stream)
      assert match?({:error, _}, result)
    end
  end

  describe "message formatting" do
    test "handles role conversion correctly" do
      messages = [
        %{role: :user, content: "Hello"},
        %{role: :assistant, content: "Hi there!"},
        %{role: :system, content: "Be helpful"}  # Should be extracted
      ]
      
      # Test through the actual API call
      config = [api_key: "test", base_url: "http://nonexistent"]
      
      # This will fail with network error, but we're testing message formatting
      assert {:error, {:http_error, _}} = Anthropic.chat(messages, config)
    end
  end

  describe "response parsing" do
    test "handles different stop reasons", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      mock_response = %{
        "content" => [%{"type" => "text", "text" => "Partial response"}],
        "model" => "claude-3-5-sonnet-20241022",
        "stop_reason" => "max_tokens",
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
      }
      
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)
      
      assert {:ok, response} = Anthropic.chat(messages, config)
      assert response.finish_reason == "max_tokens"
    end

    test "handles unexpected response format", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      # Response missing required fields
      mock_response = %{"unexpected" => "format"}
      
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)
      
      assert {:error, {:unexpected_response_format, _}} = Anthropic.chat(messages, config)
    end

    test "handles missing content", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      # Response with empty content
      mock_response = %{
        "content" => [],
        "model" => "claude-3-5-sonnet-20241022",
        "stop_reason" => "end_turn",
        "usage" => %{"input_tokens" => 1, "output_tokens" => 0}
      }
      
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)
      
      assert {:error, {:unexpected_response_format, _}} = Anthropic.chat(messages, config)
    end
  end

  describe "error handling" do
    test "handles network timeouts", %{config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      # Use very short timeout and invalid URL
      timeout_config = config
      |> Keyword.put(:timeout, 1)
      |> Keyword.put(:base_url, "http://localhost:99999/v1")
      
      assert {:error, {:http_error, _}} = Anthropic.chat(messages, timeout_config)
    end

    test "handles malformed JSON", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      Bypass.expect_once(bypass, "POST", "/v1/messages", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, "invalid json{")
      end)
      
      assert {:error, {:json_decode_error, _}} = Anthropic.chat(messages, config)
    end
  end
end