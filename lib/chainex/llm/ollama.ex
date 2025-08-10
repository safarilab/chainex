defmodule Chainex.LLM.Ollama do
  @moduledoc """
  Ollama provider implementation for Chainex.LLM

  Handles communication with local Ollama instances for running
  open-source models like Llama, Mistral, CodeLlama, and others.

  ## Configuration

      config :chainex, Chainex.LLM,
        ollama: [
          model: "llama2",
          base_url: "http://localhost:11434",
          timeout: 60_000,
          keep_alive: "5m"
        ]

  ## Supported Models

  Any model available in your Ollama installation:
  - llama2, llama2:7b, llama2:13b
  - mistral, mistral:7b
  - codellama, codellama:7b
  - phi, gemma, qwen
  - And many others

  ## Features

  - Chat completions
  - Streaming responses
  - Model management
  - Local inference (no API keys needed)
  """

  @behaviour Chainex.LLM.Provider

  @default_model "llama2"
  @default_base_url "http://localhost:11434"
  @default_timeout 60_000
  @default_keep_alive "5m"

  @type config :: [
          model: String.t(),
          base_url: String.t(),
          timeout: pos_integer(),
          temperature: float(),
          top_p: float(),
          top_k: pos_integer(),
          repeat_penalty: float(),
          seed: pos_integer(),
          num_predict: pos_integer(),
          keep_alive: String.t(),
          system: String.t() | nil
        ]

  @doc """
  Send a chat completion request to Ollama
  """
  @spec chat(list(), config()) :: {:ok, map()} | {:error, any()}
  def chat(messages, config) do
    do_chat_request(messages, config)
  end

  @doc """
  Stream a chat completion from Ollama
  """
  @spec stream_chat(list(), config()) :: Enumerable.t()
  def stream_chat(messages, config) do
    do_stream_request(messages, config)
  end

  @doc """
  Count tokens for the given messages

  Uses a rough estimation since Ollama doesn't expose tokenization:
  - ~4 characters per token (varies by model)
  - Additional tokens for message formatting
  """
  @spec count_tokens(list(), config()) :: {:ok, pos_integer()} | {:error, any()}
  def count_tokens(messages, _config) do
    # Very rough estimation for local models
    total_tokens =
      messages
      |> Enum.reduce(0, fn message, acc ->
        content_length = String.length(message.content)
        # Rough estimation: 4 chars ≈ 1 token (varies by model/tokenizer)
        content_tokens = div(content_length, 4) + 1
        # +2 for role formatting
        acc + content_tokens + 2
      end)

    {:ok, total_tokens}
  end

  @doc """
  List available models from Ollama
  """
  @spec models(config()) :: {:ok, [String.t()]} | {:error, any()}
  def models(config) do
    url = build_url(config, "/api/tags")

    case http_request(:get, url, [], nil, config) do
      {:ok, %{"models" => models}} when is_list(models) ->
        model_names =
          models
          |> Enum.map(fn model -> model["name"] end)
          |> Enum.filter(fn name -> name != nil end)
          |> Enum.sort()

        {:ok, model_names}

      {:ok, response} ->
        {:error, {:unexpected_response, response}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if Ollama is running and accessible
  """
  @spec ping(config()) :: :ok | {:error, any()}
  def ping(config) do
    url = build_url(config, "/api/tags")

    case http_request(:get, url, [], nil, Keyword.put(config, :timeout, 5000)) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Pull a model from Ollama registry
  """
  @spec pull_model(String.t(), config()) :: :ok | {:error, any()}
  def pull_model(model_name, config) do
    url = build_url(config, "/api/pull")
    body = %{"name" => model_name}

    case http_request(:post, url, [], body, Keyword.put(config, :timeout, 300_000)) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp do_chat_request(messages, config) do
    url = build_url(config, "/api/chat")
    body = build_chat_body(messages, config)

    case http_request(:post, url, [], body, config) do
      {:ok, response} ->
        parse_chat_response(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_stream_request(messages, config) do
    url = build_url(config, "/api/chat")
    body = build_chat_body(messages, Keyword.put(config, :stream, true))

    Stream.resource(
      fn -> start_stream(url, body, config) end,
      fn connection -> read_stream_chunk(connection) end,
      fn connection -> close_stream(connection) end
    )
  end

  defp build_url(config, path) do
    base_url = Keyword.get(config, :base_url, @default_base_url)
    base_url <> path
  end

  defp build_chat_body(messages, config) do
    {system_message, chat_messages} = extract_system_message(messages)
    formatted_messages = format_messages(chat_messages)

    base_body = %{
      "model" => Keyword.get(config, :model, @default_model),
      "messages" => formatted_messages,
      "stream" => Keyword.get(config, :stream, false),
      "keep_alive" => Keyword.get(config, :keep_alive, @default_keep_alive)
    }

    # Add system message if present
    base_body =
      case system_message do
        nil -> base_body
        system -> Map.put(base_body, "system", system)
      end

    # Build options
    options = build_options(config)

    if map_size(options) > 0 do
      Map.put(base_body, "options", options)
    else
      base_body
    end
  end

  defp extract_system_message(messages) do
    case Enum.find(messages, fn msg -> msg.role == :system end) do
      nil ->
        {nil, messages}

      system_msg ->
        chat_messages = Enum.reject(messages, fn msg -> msg.role == :system end)
        {system_msg.content, chat_messages}
    end
  end

  defp format_messages(messages) do
    messages
    # System handled separately
    |> Enum.reject(fn msg -> msg.role == :system end)
    |> Enum.map(fn message ->
      %{
        "role" => format_role(message.role),
        "content" => message.content
      }
    end)
  end

  defp format_role(:user), do: "user"
  defp format_role(:assistant), do: "assistant"
  defp format_role(role) when is_binary(role), do: role
  defp format_role(role), do: to_string(role)

  defp build_options(config) do
    %{}
    |> maybe_add_option(:temperature, config)
    |> maybe_add_option(:top_p, config)
    |> maybe_add_option(:top_k, config)
    |> maybe_add_option(:repeat_penalty, config)
    |> maybe_add_option(:seed, config)
    |> maybe_add_option(:num_predict, config)
  end

  defp maybe_add_option(options, key, config) do
    case Keyword.get(config, key) do
      nil -> options
      value -> Map.put(options, to_string(key), value)
    end
  end

  defp http_request(method, url, headers, body, config) do
    timeout = Keyword.get(config, :timeout, @default_timeout)

    request_opts = [
      receive_timeout: timeout,
      retry: false
    ]

    base_headers = [{"Content-Type", "application/json"}]
    all_headers = base_headers ++ headers

    json_body = if body, do: Jason.encode!(body), else: nil

    try do
      case Req.request(
             [method: method, url: url, headers: all_headers, body: json_body] ++ request_opts
           ) do
        {:ok, %Req.Response{status: status, body: response_body}} when status in 200..299 ->
          decoded =
            case response_body do
              body when is_binary(body) ->
                case Jason.decode(body) do
                  {:ok, decoded} -> decoded
                  {:error, _} -> {:error, {:json_decode_error, body}}
                end

              body when is_map(body) ->
                body
            end

          case decoded do
            {:error, _} = error -> error
            decoded_body -> {:ok, decoded_body}
          end

        {:ok, %Req.Response{status: status, body: body}} ->
          decoded =
            case body do
              body when is_binary(body) ->
                case Jason.decode(body) do
                  {:ok, decoded} -> decoded
                  {:error, _} -> body
                end

              body when is_map(body) ->
                body
            end

          case decoded do
            %{"error" => error} -> {:error, {:api_error, status, error}}
            decoded_body -> {:error, {:api_error, status, decoded_body}}
          end

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    catch
      :exit, reason ->
        {:error, {:http_error, reason}}

      error, reason ->
        case reason do
          %Jason.DecodeError{} -> {:error, {:json_decode_error, reason}}
          _ -> {:error, {:http_error, {error, reason}}}
        end
    end
  end

  defp parse_chat_response(%{"message" => %{"content" => content}} = response) do
    # Ollama doesn't always provide detailed usage stats
    usage = %{
      prompt_tokens: response["prompt_eval_count"] || 0,
      completion_tokens: response["eval_count"] || 0,
      total_tokens: (response["prompt_eval_count"] || 0) + (response["eval_count"] || 0)
    }

    response_data = %{
      content: content,
      model: response["model"] || "unknown",
      provider: :ollama,
      usage: usage,
      finish_reason: if(response["done"], do: "stop", else: "length")
    }

    {:ok, response_data}
  end

  defp parse_chat_response(response) do
    {:error, {:unexpected_response_format, response}}
  end

  # Streaming implementation
  defp start_stream(url, body, config) do
    # Simplified streaming implementation
    case http_request(:post, url, [], body, config) do
      {:ok, response} -> {:complete, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_stream_chunk({:complete, response}) do
    case parse_chat_response(response) do
      {:ok, parsed} ->
        chunk = %{
          content: parsed.content,
          delta: parsed.content,
          done: true
        }

        {[{:ok, chunk}], {:done}}

      {:error, reason} ->
        {[{:error, reason}], {:done}}
    end
  end

  defp read_stream_chunk({:error, reason}) do
    {[{:error, reason}], {:done}}
  end

  defp read_stream_chunk({:done}) do
    {:halt, {:done}}
  end

  defp close_stream(_connection) do
    :ok
  end
end
