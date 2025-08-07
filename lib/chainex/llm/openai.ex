defmodule Chainex.LLM.OpenAI do
  @moduledoc """
  OpenAI provider implementation for Chainex.LLM

  Handles communication with OpenAI's API including GPT-4, GPT-3.5-turbo,
  and other OpenAI models.

  ## Configuration

      config :chainex, Chainex.LLM,
        openai: [
          api_key: {:system, "OPENAI_API_KEY"},
          model: "gpt-4o-mini",
          base_url: "https://api.openai.com/v1",
          organization: nil,
          timeout: 30_000
        ]

  ## Supported Models

  - gpt-4o
  - gpt-4o-mini
  - gpt-4-turbo
  - gpt-4
  - gpt-3.5-turbo
  - And other OpenAI models

  ## Features

  - Chat completions
  - Streaming responses
  - Function/tool calling
  - Token counting
  - Model listing
  """

  @behaviour Chainex.LLM.Provider

  @api_version "v1"
  @default_model "gpt-4o-mini"
  @default_temperature 0.7
  @default_max_tokens 4096
  @default_timeout 30_000

  @type config :: [
    api_key: String.t(),
    model: String.t(),
    base_url: String.t(),
    organization: String.t() | nil,
    timeout: pos_integer(),
    temperature: float(),
    max_tokens: pos_integer(),
    top_p: float(),
    frequency_penalty: float(),
    presence_penalty: float(),
    stop: String.t() | [String.t()] | nil,
    tools: [map()] | nil,
    tool_choice: String.t() | map() | nil
  ]

  @doc """
  Send a chat completion request to OpenAI
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
  Stream a chat completion from OpenAI
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
  
  Uses a rough estimation based on the tiktoken approach:
  - ~4 characters per token for English text
  - Additional tokens for message formatting
  """
  @spec count_tokens(list(), config()) :: {:ok, pos_integer()} | {:error, any()}
  def count_tokens(messages, _config) do
    # Rough estimation - for precise counting, would need tiktoken integration
    base_tokens = 3  # Base tokens per message for formatting
    
    total_tokens = 
      messages
      |> Enum.reduce(0, fn message, acc ->
        content_length = String.length(message.content)
        role_tokens = case message.role do
          :system -> 4
          :user -> 4
          :assistant -> 4
          :tool -> 4
          _ -> 4
        end
        
        # Rough estimation: 4 chars ≈ 1 token
        content_tokens = div(content_length, 4) + 1
        acc + base_tokens + role_tokens + content_tokens
      end)
    
    {:ok, total_tokens + 3} # +3 for conversation priming
  end

  @doc """
  List available OpenAI models
  """
  @spec models(config()) :: {:ok, [String.t()]} | {:error, any()}
  def models(config) do
    case validate_config(config) do
      :ok ->
        do_models_request(config)
      {:error, reason} ->
        {:error, reason}
    end
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
    url = build_url(config, "/chat/completions")
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
    url = build_url(config, "/chat/completions")
    headers = build_headers(config)
    body = build_chat_body(messages, Keyword.put(config, :stream, true))
    
    Stream.resource(
      fn -> start_stream(url, headers, body, config) end,
      fn connection -> read_stream_chunk(connection) end,
      fn connection -> close_stream(connection) end
    )
  end

  defp do_models_request(config) do
    url = build_url(config, "/models")
    headers = build_headers(config)
    
    case http_request(:get, url, headers, nil, config) do
      {:ok, %{"data" => models}} when is_list(models) ->
        model_ids = 
          models
          |> Enum.filter(fn model -> 
            # Filter for chat completion models
            model_id = model["id"]
            String.contains?(model_id, "gpt") or String.contains?(model_id, "chat")
          end)
          |> Enum.map(fn model -> model["id"] end)
          |> Enum.sort()
        
        {:ok, model_ids}
      
      {:ok, response} ->
        {:error, {:unexpected_response, response}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_url(config, path) do
    base_url = Keyword.get(config, :base_url, "https://api.openai.com/#{@api_version}")
    base_url <> path
  end

  defp build_headers(config) do
    base_headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{Keyword.fetch!(config, :api_key)}"}
    ]
    
    case Keyword.get(config, :organization) do
      nil -> base_headers
      org -> [{"OpenAI-Organization", org} | base_headers]
    end
  end

  defp build_chat_body(messages, config) do
    formatted_messages = format_messages(messages)
    
    base_body = %{
      "model" => Keyword.get(config, :model, @default_model),
      "messages" => formatted_messages,
      "temperature" => Keyword.get(config, :temperature, @default_temperature),
      "max_tokens" => Keyword.get(config, :max_tokens, @default_max_tokens)
    }
    
    # Add optional parameters
    base_body
    |> maybe_add(:top_p, config)
    |> maybe_add(:frequency_penalty, config)
    |> maybe_add(:presence_penalty, config)
    |> maybe_add(:stop, config)
    |> maybe_add(:tools, config)
    |> maybe_add(:tool_choice, config)
    |> maybe_add(:stream, config)
  end

  defp format_messages(messages) do
    Enum.map(messages, fn message ->
      base = %{
        "role" => format_role(message.role),
        "content" => message.content
      }
      
      case Map.get(message, :name) do
        nil -> base
        name -> Map.put(base, "name", name)
      end
    end)
  end

  defp format_role(:system), do: "system"
  defp format_role(:user), do: "user"
  defp format_role(:assistant), do: "assistant"
  defp format_role(:tool), do: "tool"
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
    
    json_body = if body, do: Jason.encode!(body), else: nil
    
    try do
      case Req.request([method: method, url: url, headers: headers, body: json_body] ++ request_opts) do
      {:ok, %Req.Response{status: status, body: response_body}} when status in 200..299 ->
        decoded = 
          case response_body do
            body when is_binary(body) ->
              case Jason.decode(body) do
                {:ok, decoded} -> decoded
                {:error, _} -> {:error, {:json_decode_error, body}}
              end
            body when is_map(body) -> body
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
            body when is_map(body) -> body
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

  defp parse_chat_response(%{"choices" => [choice | _]} = response) do
    message = choice["message"]
    content = message["content"] || ""
    
    usage = %{
      prompt_tokens: get_in(response, ["usage", "prompt_tokens"]) || 0,
      completion_tokens: get_in(response, ["usage", "completion_tokens"]) || 0,
      total_tokens: get_in(response, ["usage", "total_tokens"]) || 0
    }
    
    response_data = %{
      content: content,
      model: response["model"],
      provider: :openai,
      usage: usage,
      finish_reason: choice["finish_reason"]
    }
    
    {:ok, response_data}
  end

  defp parse_chat_response(response) do
    {:error, {:unexpected_response_format, response}}
  end

  # Streaming implementation
  defp start_stream(url, headers, body, config) do
    # This is a simplified streaming implementation
    # In production, you'd want to use a proper HTTP streaming client
    case http_request(:post, url, headers, body, config) do
      {:ok, response} -> {:complete, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_stream_chunk({:complete, response}) do
    # For now, return the complete response as a single chunk
    # In a real streaming implementation, this would process SSE chunks
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