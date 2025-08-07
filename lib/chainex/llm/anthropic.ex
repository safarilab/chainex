defmodule Chainex.LLM.Anthropic do
  @moduledoc """
  Anthropic Claude provider implementation for Chainex.LLM

  Handles communication with Anthropic's API including Claude 3.5 Sonnet,
  Claude 3 Haiku, and other Claude models.

  ## Configuration

      config :chainex, Chainex.LLM,
        anthropic: [
          api_key: {:system, "ANTHROPIC_API_KEY"},
          model: "claude-3-5-sonnet-20241022",
          base_url: "https://api.anthropic.com/v1",
          version: "2023-06-01",
          timeout: 30_000
        ]

  ## Supported Models

  - claude-3-5-sonnet-20241022
  - claude-3-5-haiku-20241022
  - claude-3-opus-20240229
  - claude-3-sonnet-20240229
  - claude-3-haiku-20240307

  ## Features

  - Chat completions with system messages
  - Streaming responses
  - Tool/function calling
  - Token counting estimation
  """

  @behaviour Chainex.LLM.Provider

  @api_version "2023-06-01"
  @default_model "claude-3-5-sonnet-20241022"
  @default_temperature 0.7
  @default_max_tokens 4096
  @default_timeout 30_000

  @type config :: [
          api_key: String.t(),
          model: String.t(),
          base_url: String.t(),
          version: String.t(),
          timeout: pos_integer(),
          temperature: float(),
          max_tokens: pos_integer(),
          top_p: float(),
          top_k: pos_integer(),
          stop_sequences: [String.t()] | nil,
          tools: [map()] | nil,
          tool_choice: map() | nil,
          system: String.t() | nil
        ]

  @doc """
  Send a chat completion request to Anthropic
  """
  @spec chat(list(), config()) :: {:ok, map()} | {:error, any()}
  def chat(messages, config) do
    case validate_config(config) do
      :ok ->
        do_chat_request(messages, config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stream a chat completion from Anthropic
  """
  @spec stream_chat(list(), config()) :: Enumerable.t()
  def stream_chat(messages, config) do
    case validate_config(config) do
      :ok ->
        do_stream_request(messages, config)

      {:error, reason} ->
        [error: reason]
    end
  end

  @doc """
  Count tokens for the given messages

  Uses a rough estimation based on Claude's tokenization patterns:
  - ~3.5 characters per token for English text
  - Additional tokens for message formatting
  """
  @spec count_tokens(list(), config()) :: {:ok, pos_integer()} | {:error, any()}
  def count_tokens(messages, _config) do
    # Rough estimation for Claude models
    # Base tokens per message for formatting
    base_tokens = 2

    total_tokens =
      messages
      |> Enum.reduce(0, fn message, acc ->
        content_length = String.length(message.content)

        role_tokens =
          case message.role do
            :system -> 3
            :user -> 3
            :assistant -> 3
            _ -> 3
          end

        # Claude roughly: 3.5 chars ≈ 1 token
        content_tokens = div(content_length * 10, 35) + 1
        acc + base_tokens + role_tokens + content_tokens
      end)

    # +5 for conversation structure
    {:ok, total_tokens + 5}
  end

  @doc """
  List available Anthropic models
  """
  @spec models(config()) :: {:ok, [String.t()]} | {:error, any()}
  def models(_config) do
    # Anthropic doesn't have a models endpoint yet, so we return known models
    models = [
      "claude-3-5-sonnet-20241022",
      "claude-3-5-haiku-20241022",
      "claude-3-opus-20240229",
      "claude-3-sonnet-20240229",
      "claude-3-haiku-20240307"
    ]

    {:ok, models}
  end

  # Private functions

  defp validate_config(config) do
    case Keyword.get(config, :api_key) do
      nil -> {:error, :missing_api_key}
      "" -> {:error, :missing_api_key}
      _api_key -> :ok
    end
  end

  defp do_chat_request(messages, config) do
    url = build_url(config, "/messages")
    headers = build_headers(config)
    body = build_chat_body(messages, config)

    case http_request(:post, url, headers, body, config) do
      {:ok, response} ->
        parse_chat_response(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_stream_request(messages, config) do
    url = build_url(config, "/messages")
    headers = build_headers(config)
    body = build_chat_body(messages, Keyword.put(config, :stream, true))

    Stream.resource(
      fn -> start_stream(url, headers, body, config) end,
      fn connection -> read_stream_chunk(connection) end,
      fn connection -> close_stream(connection) end
    )
  end

  defp build_url(config, path) do
    base_url = Keyword.get(config, :base_url, "https://api.anthropic.com/v1")
    base_url <> path
  end

  defp build_headers(config) do
    version = Keyword.get(config, :version, @api_version)

    [
      {"Content-Type", "application/json"},
      {"x-api-key", Keyword.fetch!(config, :api_key)},
      {"anthropic-version", version}
    ]
  end

  defp build_chat_body(messages, config) do
    {system_message, chat_messages} = extract_system_message(messages)
    formatted_messages = format_messages(chat_messages)

    base_body = %{
      "model" => Keyword.get(config, :model, @default_model),
      "messages" => formatted_messages,
      "max_tokens" => Keyword.get(config, :max_tokens, @default_max_tokens)
    }

    # Add system message if present
    base_body =
      case system_message do
        nil -> base_body
        system -> Map.put(base_body, "system", system)
      end

    # Add optional parameters with defaults
    base_body
    |> Map.put("temperature", Keyword.get(config, :temperature, @default_temperature))
    |> maybe_add(:top_p, config)
    |> maybe_add(:top_k, config)
    |> maybe_add(:stop_sequences, config)
    |> maybe_add(:tools, config)
    |> maybe_add(:tool_choice, config)
    |> maybe_add(:stream, config)
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

  defp maybe_add(body, key, config) do
    case Keyword.get(config, key) do
      nil -> body
      value -> Map.put(body, to_string(key), value)
    end
  end

  defp http_request(method, url, headers, body, config) do
    timeout = Keyword.get(config, :timeout, @default_timeout)

    request_opts = [
      receive_timeout: timeout,
      retry: false
    ]

    json_body = Jason.encode!(body)

    try do
      case Req.request(
             [method: method, url: url, headers: headers, body: json_body] ++ request_opts
           ) do
        {:ok, %Req.Response{status: status, body: response_body}} when status in 200..299 ->
          decoded =
            case response_body do
              resp_body when is_binary(resp_body) ->
                case Jason.decode(resp_body) do
                  {:ok, decoded} -> decoded
                  {:error, _} -> {:error, {:json_decode_error, resp_body}}
                end

              resp_body when is_map(resp_body) ->
                resp_body
            end

          case decoded do
            {:error, _} = error -> error
            decoded_body -> {:ok, decoded_body}
          end

        {:ok, %Req.Response{status: status, body: body}} ->
          decoded =
            case body do
              resp_body when is_binary(resp_body) ->
                case Jason.decode(resp_body) do
                  {:ok, decoded} -> decoded
                  {:error, _} -> resp_body
                end

              resp_body when is_map(resp_body) ->
                resp_body
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

  defp parse_chat_response(%{"content" => [%{"text" => text} | _]} = response) do
    usage = %{
      prompt_tokens: get_in(response, ["usage", "input_tokens"]) || 0,
      completion_tokens: get_in(response, ["usage", "output_tokens"]) || 0,
      total_tokens:
        (get_in(response, ["usage", "input_tokens"]) || 0) +
          (get_in(response, ["usage", "output_tokens"]) || 0)
    }

    response_data = %{
      content: text,
      model: response["model"],
      provider: :anthropic,
      usage: usage,
      finish_reason: response["stop_reason"]
    }

    {:ok, response_data}
  end

  defp parse_chat_response(response) do
    {:error, {:unexpected_response_format, response}}
  end

  # Streaming implementation
  defp start_stream(url, headers, body, config) do
    # Simplified streaming implementation
    # In production, you'd want to use Server-Sent Events processing
    case http_request(:post, url, headers, body, config) do
      {:ok, response} -> {:complete, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_stream_chunk({:complete, response}) do
    # For now, return the complete response as a single chunk
    # In a real streaming implementation, this would process SSE events
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
    # Cleanup streaming connection
    :ok
  end
end
