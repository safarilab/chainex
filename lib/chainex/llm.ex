defmodule Chainex.LLM do
  @moduledoc """
  Language Model interface for Chainex

  Provides a unified interface for interacting with various LLM providers
  including OpenAI, Anthropic, and local models through Ollama.

  ## Configuration

  Configure LLM settings globally or per-request:

      config :chainex, Chainex.LLM,
        default_provider: :openai,
        openai: [
          api_key: {:system, "OPENAI_API_KEY"},
          model: "gpt-4o-mini",
          base_url: "https://api.openai.com/v1"
        ],
        anthropic: [
          api_key: {:system, "ANTHROPIC_API_KEY"},
          model: "claude-3-5-sonnet-20241022",
          base_url: "https://api.anthropic.com/v1"
        ],
        ollama: [
          model: "llama2",
          base_url: "http://localhost:11434"
        ]

  ## Basic Usage

      # Simple completion
      {:ok, response} = LLM.complete("Hello, world!")
      
      # With specific provider and model
      {:ok, response} = LLM.complete("Hello!", provider: :openai, model: "gpt-4o")
      
      # Chat-style conversation
      messages = [
        %{role: "user", content: "What is the capital of France?"}
      ]
      {:ok, response} = LLM.chat(messages)

  ## Advanced Features

  - Multiple provider support (OpenAI, Anthropic, Ollama)
  - Streaming responses
  - Token counting and usage tracking
  - Custom model parameters
  - Context integration
  - Memory integration for conversation history
  """

  alias Chainex.LLM.{OpenAI, Anthropic, Ollama, Mock}
  alias Chainex.{Context, Memory}

  @type provider :: :openai | :anthropic | :ollama | :mock
  @type role :: :system | :user | :assistant | :tool
  @type message :: %{role: role(), content: String.t()} | %{role: role(), content: String.t(), name: String.t()}
  @type messages :: [message()]
  @type model :: String.t()
  @type config :: keyword()
  
  @type completion_options :: [
    provider: provider(),
    model: model(),
    temperature: float(),
    max_tokens: pos_integer(),
    top_p: float(),
    frequency_penalty: float(),
    presence_penalty: float(),
    stop: String.t() | [String.t()],
    stream: boolean(),
    tools: [map()],
    tool_choice: String.t() | map()
  ]

  @type response :: %{
    content: String.t(),
    model: String.t(),
    provider: provider(),
    usage: %{
      prompt_tokens: pos_integer(),
      completion_tokens: pos_integer(),
      total_tokens: pos_integer()
    },
    finish_reason: String.t()
  } | %{
    content: String.t(),
    model: String.t(),
    provider: provider(),
    usage: %{
      prompt_tokens: pos_integer(),
      completion_tokens: pos_integer(),
      total_tokens: pos_integer()
    },
    finish_reason: String.t(),
    tool_calls: [map()]
  }

  @type streaming_chunk :: %{
    content: String.t(),
    delta: String.t(),
    done: boolean()
  }

  @providers %{
    openai: OpenAI,
    anthropic: Anthropic,
    ollama: Ollama,
    mock: Mock
  }

  @doc """
  Simple text completion with a single prompt

  ## Examples

      iex> LLM.complete("What is 2+2?")
      {:ok, %{content: "2+2 equals 4.", ...}}

      iex> LLM.complete("Hello!", provider: :openai, model: "gpt-4o")
      {:ok, %{content: "Hello! How can I help you today?", ...}}
  """
  @spec complete(String.t(), completion_options()) :: {:ok, response()} | {:error, any()}
  def complete(prompt, opts \\ []) when is_binary(prompt) do
    messages = [%{role: :user, content: prompt}]
    chat(messages, opts)
  end

  @doc """
  Chat-style completion with message history

  ## Examples

      iex> messages = [
      ...>   %{role: :system, content: "You are a helpful assistant"},
      ...>   %{role: :user, content: "Hello!"}
      ...> ]
      iex> LLM.chat(messages)
      {:ok, %{content: "Hello! How can I help you?", ...}}
  """
  @spec chat(messages(), completion_options()) :: {:ok, response()} | {:error, any()}
  def chat(messages, opts \\ []) when is_list(messages) do
    {provider, config} = resolve_provider_and_config(opts)
    provider_module = Map.get(@providers, provider)
    
    if provider_module do
      provider_module.chat(messages, config)
    else
      {:error, {:unsupported_provider, provider}}
    end
  end

  @doc """
  Stream completions for real-time responses

  Returns a stream of chunks that can be processed as they arrive.

  ## Examples

      iex> stream = LLM.stream("Tell me a story")
      iex> is_function(stream.reducer, 3)
      true
  """
  @spec stream(String.t(), completion_options()) :: Enumerable.t()
  def stream(prompt, opts \\ []) when is_binary(prompt) do
    messages = [%{role: :user, content: prompt}]
    stream_chat(messages, opts)
  end

  @doc """
  Stream chat completions
  """
  @spec stream_chat(messages(), completion_options()) :: Enumerable.t()
  def stream_chat(messages, opts \\ []) when is_list(messages) do
    {provider, config} = resolve_provider_and_config(Keyword.put(opts, :stream, true))
    provider_module = Map.get(@providers, provider)
    
    if provider_module do
      provider_module.stream_chat(messages, config)
    else
      [error: {:unsupported_provider, provider}]
    end
  end

  @doc """
  Complete with context integration

  Automatically manages conversation history through memory and context.

  ## Examples

      iex> context = Context.new(%{user: "Alice"})
      iex> {:ok, response, updated_context} = LLM.complete_with_context(
      ...>   "Hello, remember my name",
      ...>   context
      ...> )
  """
  @spec complete_with_context(String.t(), Context.t(), completion_options()) :: 
    {:ok, response(), Context.t()} | {:error, any()}
  def complete_with_context(prompt, context, opts \\ []) do
    # Build messages from memory if available
    messages = build_messages_from_context(prompt, context)
    
    case chat(messages, opts) do
      {:ok, response} ->
        updated_context = update_context_with_response(context, prompt, response)
        {:ok, response, updated_context}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Count tokens for a given text or messages

  Useful for managing context limits and costs.

  ## Examples

      iex> LLM.count_tokens("Hello world")
      {:ok, 2}

      iex> messages = [%{role: "user", content: "Hello"}]
      iex> LLM.count_tokens(messages, provider: :openai, model: "gpt-4o")
      {:ok, 8}
  """
  @spec count_tokens(String.t() | messages(), completion_options()) :: {:ok, pos_integer()} | {:error, any()}
  def count_tokens(input, opts \\ [])

  def count_tokens(text, opts) when is_binary(text) do
    count_tokens([%{role: :user, content: text}], opts)
  end

  def count_tokens(messages, opts) when is_list(messages) do
    {provider, config} = resolve_provider_and_config(opts)
    provider_module = Map.get(@providers, provider)
    
    if provider_module && function_exported?(provider_module, :count_tokens, 2) do
      provider_module.count_tokens(messages, config)
    else
      # Fallback to rough estimation (4 chars ≈ 1 token)
      total_chars = 
        messages
        |> Enum.map(fn %{content: content} -> String.length(content) end)
        |> Enum.sum()
      
      {:ok, div(total_chars, 4) + length(messages) * 3} # +3 for role overhead per message
    end
  end

  @doc """
  Get available models for a provider

  ## Examples

      iex> LLM.models(:openai)
      {:ok, ["gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo"]}
  """
  @spec models(provider()) :: {:ok, [String.t()]} | {:error, any()}
  def models(provider) do
    provider_module = Map.get(@providers, provider)
    
    if provider_module && function_exported?(provider_module, :models, 1) do
      config = get_provider_config(provider)
      provider_module.models(config)
    else
      {:error, {:unsupported_provider, provider}}
    end
  end

  # Private helper functions

  defp resolve_provider_and_config(opts) do
    provider = Keyword.get(opts, :provider, default_provider())
    base_config = get_provider_config(provider)
    request_config = Keyword.drop(opts, [:provider])
    config = Keyword.merge(base_config, request_config)
    
    {provider, config}
  end

  defp default_provider do
    Application.get_env(:chainex, __MODULE__, [])
    |> Keyword.get(:default_provider, :openai)
  end

  defp get_provider_config(provider) do
    Application.get_env(:chainex, __MODULE__, [])
    |> Keyword.get(provider, [])
    |> resolve_config_values()
  end

  defp resolve_config_values(config) do
    Enum.map(config, fn
      {key, {:system, env_var}} -> {key, System.get_env(env_var)}
      {key, {:system, env_var, default}} -> {key, System.get_env(env_var, default)}
      {key, value} -> {key, value}
    end)
  end

  defp build_messages_from_context(prompt, context) do
    base_messages = []
    
    # Add system message if any metadata provides it
    base_messages = 
      case Map.get(context.metadata, :system_prompt) do
        nil -> base_messages
        system_prompt -> [%{role: :system, content: system_prompt} | base_messages]
      end
    
    # Add conversation history from memory if available
    base_messages = 
      case context.memory do
        nil -> base_messages
        memory -> 
          case get_conversation_history(memory, context.session_id) do
            [] -> base_messages
            history -> base_messages ++ history
          end
      end
    
    # Add current prompt
    base_messages ++ [%{role: :user, content: prompt}]
  end

  defp get_conversation_history(memory, session_id) do
    # Try to retrieve conversation history from memory
    case Memory.retrieve(memory, "conversation:#{session_id}") do
      {:ok, history} when is_list(history) -> history
      _ -> []
    end
  end

  defp update_context_with_response(context, prompt, response) do
    # Store the conversation turn in memory if available
    updated_context = 
      case context.memory do
        nil -> context
        memory ->
          history_key = "conversation:#{context.session_id}"
          
          # Get existing history
          existing_history = 
            case Memory.retrieve(memory, history_key) do
              {:ok, history} when is_list(history) -> history
              _ -> []
            end
          
          # Add new turn
          new_turn = [
            %{role: :user, content: prompt},
            %{role: :assistant, content: response.content}
          ]
          
          updated_history = existing_history ++ new_turn
          updated_memory = Memory.store(memory, history_key, updated_history)
          
          %{context | memory: updated_memory}
      end
    
    # Update metadata with response info
    updated_metadata = 
      context.metadata
      |> Map.put(:last_model, response.model)
      |> Map.put(:last_provider, response.provider)
      |> Map.put(:last_usage, response.usage)
    
    %{updated_context | metadata: updated_metadata}
  end
end