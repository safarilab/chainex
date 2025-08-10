defmodule Chainex.LLM.OllamaTest do
  use ExUnit.Case, async: true

  alias Chainex.LLM.Ollama

  setup do
    bypass = Bypass.open()

    config = [
      model: "llama2",
      base_url: "http://localhost:#{bypass.port}",
      timeout: 5000,
      keep_alive: "5m"
    ]

    {:ok, bypass: bypass, config: config}
  end

  describe "chat/2" do
    test "makes successful chat completion request", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]

      mock_response = %{
        "model" => "llama2",
        "created_at" => "2023-12-12T14:13:43.416799Z",
        "message" => %{
          "role" => "assistant",
          "content" => "Hello! How can I help you today?"
        },
        "done" => true,
        "total_duration" => 5_191_566_416,
        "load_duration" => 2_154_458,
        "prompt_eval_count" => 26,
        "prompt_eval_duration" => 383_809_000,
        "eval_count" => 298,
        "eval_duration" => 4_799_921_000
      }

      Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
        # Verify request headers
        assert Enum.any?(conn.req_headers, fn {key, value} ->
                 key == "content-type" && value == "application/json"
               end)

        # Verify request body
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded_body = Jason.decode!(body)

        assert decoded_body["model"] == "llama2"
        assert is_list(decoded_body["messages"])
        assert length(decoded_body["messages"]) == 1
        assert decoded_body["keep_alive"] == "5m"
        assert decoded_body["stream"] == false

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      assert {:ok, response} = Ollama.chat(messages, config)
      assert response.content == "Hello! How can I help you today?"
      assert response.model == "llama2"
      assert response.provider == :ollama
      assert response.usage.prompt_tokens == 26
      assert response.usage.completion_tokens == 298
      assert response.usage.total_tokens == 324
      assert response.finish_reason == "stop"
    end

    test "handles system messages correctly", %{bypass: bypass, config: config} do
      messages = [
        %{role: :system, content: "You are a helpful assistant"},
        %{role: :user, content: "Hello"}
      ]

      mock_response = %{
        "model" => "llama2",
        "message" => %{"role" => "assistant", "content" => "Hi there!"},
        "done" => true,
        "prompt_eval_count" => 20,
        "eval_count" => 5
      }

      Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
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

      assert {:ok, _} = Ollama.chat(messages, config)
    end

    test "includes optional parameters", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]

      enhanced_config =
        config
        |> Keyword.put(:temperature, 0.8)
        |> Keyword.put(:top_p, 0.9)
        |> Keyword.put(:top_k, 40)
        |> Keyword.put(:repeat_penalty, 1.1)
        |> Keyword.put(:seed, 42)
        |> Keyword.put(:num_predict, 100)

      mock_response = %{
        "model" => "llama2",
        "message" => %{"role" => "assistant", "content" => "Response"},
        "done" => true,
        "prompt_eval_count" => 1,
        "eval_count" => 1
      }

      Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded_body = Jason.decode!(body)

        # Verify options are included
        options = decoded_body["options"]
        assert options["temperature"] == 0.8
        assert options["top_p"] == 0.9
        assert options["top_k"] == 40
        assert options["repeat_penalty"] == 1.1
        assert options["seed"] == 42
        assert options["num_predict"] == 100

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      assert {:ok, _} = Ollama.chat(messages, enhanced_config)
    end

    test "handles API errors", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]

      error_response = %{
        "error" => "model not found"
      }

      Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(404, Jason.encode!(error_response))
      end)

      assert {:error, {:api_error, 404, _}} = Ollama.chat(messages, config)
    end
  end

  describe "models/1" do
    test "fetches available models", %{bypass: bypass, config: config} do
      mock_response = %{
        "models" => [
          %{
            "name" => "llama2:latest",
            "modified_at" => "2023-12-07T09:32:18.757212583Z",
            "size" => 3_825_819_519,
            "digest" => "sha256:bc07c81de745696fdf5afca05e065818a8149fb0c77266fb584d38b4d4ce90134"
          },
          %{
            "name" => "mistral:7b",
            "modified_at" => "2023-12-07T10:15:30.123456789Z",
            "size" => 4_109_856_768,
            "digest" => "sha256:2ae6f6dd7a3dd734790bbbf58b8909a606e0e7e97e54b717344c6dd9f3f59c8"
          }
        ]
      }

      Bypass.expect_once(bypass, "GET", "/api/tags", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      assert {:ok, models} = Ollama.models(config)
      assert is_list(models)
      assert "llama2:latest" in models
      assert "mistral:7b" in models
    end

    test "handles models endpoint errors", %{bypass: bypass, config: config} do
      Bypass.expect_once(bypass, "GET", "/api/tags", fn conn ->
        conn
        |> Plug.Conn.resp(500, "Internal Server Error")
      end)

      assert {:error, {:api_error, 500, _}} = Ollama.models(config)
    end
  end

  describe "ping/1" do
    test "checks if Ollama is accessible", %{bypass: bypass, config: config} do
      mock_response = %{"models" => []}

      Bypass.expect_once(bypass, "GET", "/api/tags", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      assert :ok = Ollama.ping(config)
    end

    test "handles unreachable Ollama instance", %{config: config} do
      unreachable_config = Keyword.put(config, :base_url, "http://localhost:99999")

      assert {:error, {:http_error, _}} = Ollama.ping(unreachable_config)
    end
  end

  describe "pull_model/2" do
    test "pulls a model successfully", %{bypass: bypass, config: config} do
      model_name = "llama2:7b"

      mock_response = %{
        "status" => "success"
      }

      Bypass.expect_once(bypass, "POST", "/api/pull", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded_body = Jason.decode!(body)

        assert decoded_body["name"] == model_name

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      assert :ok = Ollama.pull_model(model_name, config)
    end

    test "handles pull errors", %{bypass: bypass, config: config} do
      model_name = "nonexistent:model"

      Bypass.expect_once(bypass, "POST", "/api/pull", fn conn ->
        conn
        |> Plug.Conn.resp(404, "Model not found")
      end)

      assert {:error, {:api_error, 404, _}} = Ollama.pull_model(model_name, config)
    end
  end

  describe "count_tokens/2" do
    test "provides token estimates" do
      messages = [%{role: :user, content: "Hello world"}]
      config = []

      {:ok, count} = Ollama.count_tokens(messages, config)
      assert is_integer(count)
      assert count > 0
    end

    test "scales with content length" do
      config = []
      short_message = [%{role: :user, content: "Hi"}]
      long_message = [%{role: :user, content: String.duplicate("Hello ", 100)}]

      {:ok, short_count} = Ollama.count_tokens(short_message, config)
      {:ok, long_count} = Ollama.count_tokens(long_message, config)

      assert long_count > short_count
    end
  end

  describe "stream_chat/2" do
    test "returns enumerable for streaming", %{config: config} do
      messages = [%{role: :user, content: "Hello"}]

      stream = Ollama.stream_chat(messages, config)
      assert is_function(stream)
    end
  end

  describe "response parsing" do
    test "handles response without usage stats", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]

      # Minimal response without detailed usage stats
      mock_response = %{
        "model" => "llama2",
        "message" => %{
          "role" => "assistant",
          "content" => "Hello!"
        },
        "done" => true
      }

      Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      assert {:ok, response} = Ollama.chat(messages, config)
      assert response.content == "Hello!"
      # Default when not provided
      assert response.usage.prompt_tokens == 0
      assert response.usage.completion_tokens == 0
      assert response.usage.total_tokens == 0
    end

    test "handles unexpected response format", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]

      # Response missing required fields
      mock_response = %{"unexpected" => "format"}

      Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(mock_response))
      end)

      assert {:error, {:unexpected_response_format, _}} = Ollama.chat(messages, config)
    end
  end

  describe "error handling" do
    test "handles network errors", %{config: config} do
      messages = [%{role: :user, content: "Hello"}]

      # Use invalid port to trigger network error
      invalid_config = Keyword.put(config, :base_url, "http://localhost:99999")

      assert {:error, {:http_error, _}} = Ollama.chat(messages, invalid_config)
    end

    test "handles malformed JSON", %{bypass: bypass, config: config} do
      messages = [%{role: :user, content: "Hello"}]

      Bypass.expect_once(bypass, "POST", "/api/chat", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, "invalid json{")
      end)

      assert {:error, {:json_decode_error, _}} = Ollama.chat(messages, config)
    end
  end
end
