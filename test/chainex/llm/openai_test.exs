defmodule Chainex.LLM.OpenAITest do
  use ExUnit.Case, async: true

  alias Chainex.LLM.OpenAI

  setup do
    bypass = Bypass.open()
    
    config = [
      api_key: "test-api-key",
      model: "gpt-4o-mini",
      base_url: "http://localhost:#{bypass.port}/v1",
      timeout: 5000
    ]
    
    {:ok, bypass: bypass, config: config}
  end

  describe "chat/2" do
    test "validates configuration" do
      messages = [%{role: :user, content: "Hello"}]
      
      # Missing API key
      assert {:error, :missing_api_key} = OpenAI.chat(messages, [])
      assert {:error, :missing_api_key} = OpenAI.chat(messages, [api_key: ""])
    end

    test "makes successful chat completion request", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      mock_response = %{
        "id" => "chatcmpl-123",
        "object" => "chat.completion",
        "created" => 1677652288,
        "model" => "gpt-4o-mini",
        "choices" => [
          %{
            "index" => 0,
            "message" => %{
              "role" => "assistant",
              "content" => "Hello! How can I help you today?"
            },
            "finish_reason" => "stop"
          }
        ],
        "usage" => %{
          "prompt_tokens" => 9,
          "completion_tokens" => 12,
          "total_tokens" => 21
        }
      }
      
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        # Verify request headers
        assert Enum.any?(conn.req_headers, fn {key, value} -> 
          key == "authorization" && String.starts_with?(value, "Bearer ")
        end)
        
        # Verify request body
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body != ""
        
        decoded_body = Jason.decode!(body)
        assert decoded_body["model"] == "gpt-4o-mini"
        assert is_list(decoded_body["messages"])
        assert length(decoded_body["messages"]) == 1
        
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)
      
      assert {:ok, response} = OpenAI.chat(messages, config)
      assert response.content == "Hello! How can I help you today?"
      assert response.model == "gpt-4o-mini"
      assert response.provider == :openai
      assert response.usage.total_tokens == 21
      assert response.finish_reason == "stop"
    end

    test "handles API errors", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      error_response = %{
        "error" => %{
          "message" => "You exceeded your current quota",
          "type" => "insufficient_quota",
          "param" => nil,
          "code" => "insufficient_quota"
        }
      }
      
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(429, Jason.encode!(error_response))
      end)
      
      assert {:error, {:api_error, 429, _}} = OpenAI.chat(messages, config)
    end

    test "handles network errors", %{config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      # Use invalid URL to trigger network error
      invalid_config = Keyword.put(config, :base_url, "http://localhost:99999/v1")
      
      assert {:error, {:http_error, _}} = OpenAI.chat(messages, invalid_config)
    end

    test "handles malformed JSON response", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, "invalid json{")
      end)
      
      assert {:error, {:json_decode_error, _}} = OpenAI.chat(messages, config)
    end
  end

  describe "count_tokens/2" do
    test "provides token estimates" do
      messages = [%{role: :user, content: "Hello world"}]
      config = [api_key: "test"]
      
      {:ok, count} = OpenAI.count_tokens(messages, config)
      assert is_integer(count)
      assert count > 0
    end

    test "scales with content length" do
      config = [api_key: "test"]
      short_message = [%{role: :user, content: "Hi"}]
      long_message = [%{role: :user, content: String.duplicate("Hello ", 100)}]
      
      {:ok, short_count} = OpenAI.count_tokens(short_message, config)
      {:ok, long_count} = OpenAI.count_tokens(long_message, config)
      
      assert long_count > short_count
    end
  end

  describe "models/1" do
    test "fetches available models", %{bypass: bypass, config: config} do
      mock_response = %{
        "object" => "list",
        "data" => [
          %{
            "id" => "gpt-4o",
            "object" => "model",
            "created" => 1677649963,
            "owned_by" => "openai"
          },
          %{
            "id" => "gpt-4o-mini",
            "object" => "model", 
            "created" => 1677649963,
            "owned_by" => "openai"
          },
          %{
            "id" => "whisper-1",
            "object" => "model",
            "created" => 1677649963,
            "owned_by" => "openai"
          }
        ]
      }
      
      Bypass.expect_once(bypass, "GET", "/v1/models", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)
      
      assert {:ok, models} = OpenAI.models(config)
      assert is_list(models)
      # Should filter for chat models (containing "gpt")
      assert "gpt-4o" in models
      assert "gpt-4o-mini" in models
      refute "whisper-1" in models  # Not a chat model
    end

    test "validates configuration before request" do
      assert {:error, :missing_api_key} = OpenAI.models([])
    end
  end

  describe "stream_chat/2" do
    test "returns enumerable for streaming", %{config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      stream = OpenAI.stream_chat(messages, config)
      assert is_function(stream)
    end

    test "validates config for streaming" do
      messages = [%{role: :user, content: "Hello"}]
      
      stream = OpenAI.stream_chat(messages, [])
      [result] = Enum.to_list(stream)
      assert match?({:error, _}, result)
    end
  end

  describe "request formatting" do
    test "includes organization header when configured", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]
      config_with_org = Keyword.put(config, :organization, "org-123")
      
      mock_response = %{
        "choices" => [%{"message" => %{"content" => "Hi"}, "finish_reason" => "stop"}],
        "model" => "gpt-4o-mini",
        "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2}
      }
      
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        # Verify organization header is present
        assert Enum.any?(conn.req_headers, fn {key, value} -> 
          key == "openai-organization" && value == "org-123"
        end)
        
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)
      
      assert {:ok, _} = OpenAI.chat(messages, config_with_org)
    end

    test "formats messages correctly", %{bypass: bypass, config: config} do
      messages = [
        %{role: :system, content: "You are helpful"},
        %{role: :user, content: "Hello", name: "Alice"},
        %{role: :assistant, content: "Hi there!"}
      ]
      
      mock_response = %{
        "choices" => [%{"message" => %{"content" => "Response"}, "finish_reason" => "stop"}],
        "model" => "gpt-4o-mini", 
        "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2}
      }
      
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded_body = Jason.decode!(body)
        
        formatted_messages = decoded_body["messages"]
        assert length(formatted_messages) == 3
        
        # Check system message
        system_msg = Enum.find(formatted_messages, & &1["role"] == "system")
        assert system_msg["content"] == "You are helpful"
        
        # Check user message with name
        user_msg = Enum.find(formatted_messages, & &1["role"] == "user")
        assert user_msg["content"] == "Hello"
        assert user_msg["name"] == "Alice"
        
        # Check assistant message
        assistant_msg = Enum.find(formatted_messages, & &1["role"] == "assistant")
        assert assistant_msg["content"] == "Hi there!"
        
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)
      
      assert {:ok, _} = OpenAI.chat(messages, config)
    end

    test "includes optional parameters", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      enhanced_config = config
      |> Keyword.put(:temperature, 0.8)
      |> Keyword.put(:max_tokens, 150)
      |> Keyword.put(:top_p, 0.9)
      |> Keyword.put(:frequency_penalty, 0.1)
      |> Keyword.put(:presence_penalty, 0.1)
      |> Keyword.put(:stop, ["\\n", "END"])
      
      mock_response = %{
        "choices" => [%{"message" => %{"content" => "Response"}, "finish_reason" => "stop"}],
        "model" => "gpt-4o-mini",
        "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2}
      }
      
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded_body = Jason.decode!(body)
        
        # Verify optional parameters are included
        assert decoded_body["temperature"] == 0.8
        assert decoded_body["max_tokens"] == 150
        assert decoded_body["top_p"] == 0.9
        assert decoded_body["frequency_penalty"] == 0.1
        assert decoded_body["presence_penalty"] == 0.1
        assert decoded_body["stop"] == ["\\n", "END"]
        
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)
      
      assert {:ok, _} = OpenAI.chat(messages, enhanced_config)
    end
  end

  describe "response parsing" do
    test "handles different finish reasons", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      mock_response = %{
        "choices" => [%{
          "message" => %{"content" => "Partial response"},
          "finish_reason" => "length"
        }],
        "model" => "gpt-4o-mini",
        "usage" => %{"prompt_tokens" => 1, "completion_tokens" => 1, "total_tokens" => 2}
      }
      
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)
      
      assert {:ok, response} = OpenAI.chat(messages, config)
      assert response.finish_reason == "length"
    end

    test "handles unexpected response format", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]
      
      # Response missing required fields
      mock_response = %{"unexpected" => "format"}
      
      Bypass.expect_once(bypass, "POST", "/v1/chat/completions", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)
      
      assert {:error, {:unexpected_response_format, _}} = OpenAI.chat(messages, config)
    end
  end
end