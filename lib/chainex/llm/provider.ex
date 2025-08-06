defmodule Chainex.LLM.Provider do
  @moduledoc """
  Behaviour for LLM providers in Chainex

  Defines the interface that all LLM providers must implement to work
  with the unified LLM interface.
  """

  @type message :: %{role: atom(), content: String.t()}
  @type messages :: [message()]
  @type config :: keyword()
  @type response :: %{
    content: String.t(),
    model: String.t(),
    provider: atom(),
    usage: %{
      prompt_tokens: pos_integer(),
      completion_tokens: pos_integer(),
      total_tokens: pos_integer()
    },
    finish_reason: String.t()
  }
  @type streaming_chunk :: %{
    content: String.t(),
    delta: String.t(),
    done: boolean()
  }

  @doc """
  Send a chat completion request to the provider
  """
  @callback chat(messages(), config()) :: {:ok, response()} | {:error, any()}

  @doc """
  Stream a chat completion from the provider
  """
  @callback stream_chat(messages(), config()) :: Enumerable.t()

  @doc """
  Count tokens for the given messages (optional)
  """
  @callback count_tokens(messages(), config()) :: {:ok, pos_integer()} | {:error, any()}

  @doc """
  List available models from the provider (optional)
  """
  @callback models(config()) :: {:ok, [String.t()]} | {:error, any()}

  @optional_callbacks [count_tokens: 2, models: 1]
end