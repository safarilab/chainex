defmodule Chainex.LLM.Mock do
  @moduledoc """
  Mock LLM provider for testing.
  """
  
  @behaviour Chainex.LLM.Provider
  
  @doc """
  Returns a mock response based on the last user message.
  """
  def chat(messages, opts) do
    cond do
      # Check for forced error
      Keyword.get(opts, :mock_error, false) or Keyword.get(opts, :force_all_errors, false) ->
        {:error, "Mock error for testing"}
        
      # Check for required capability
      required_capability = Keyword.get(opts, :required_capability) ->
        {:error, "Mock provider does not support capability: #{required_capability}"}
        
      # Normal response
      true ->
        user_message = messages
        |> Enum.filter(fn msg -> msg.role == :user end)
        |> List.last()
        
        content = if user_message, do: user_message.content, else: "test"
        
        # Allow custom response override
        mock_content = case Keyword.get(opts, :response) do
          nil -> "Mock response for: #{content}"
          custom_response -> custom_response
        end
        
        response = %{
          content: mock_content,
          model: "mock-model",
          provider: :mock,
          usage: %{
            prompt_tokens: 10,
            completion_tokens: 5,
            total_tokens: 15
          },
          finish_reason: "stop"
        }
        
        {:ok, response}
    end
  end
  
  @doc """
  Returns a mock stream.
  """
  def stream_chat(messages, opts) do
    {:ok, response} = chat(messages, opts)
    
    # Create a simple stream that returns the response in chunks
    Stream.resource(
      fn -> String.graphemes(response.content) end,
      fn
        [] -> {:halt, nil}
        [char | rest] ->
          chunk = %{
            content: char,
            delta: char,
            done: rest == []
          }
          {[chunk], rest}
      end,
      fn _ -> :ok end
    )
  end
  
  @doc """
  Mock token counting.
  """
  def count_tokens(messages, _opts) do
    total = messages
    |> Enum.map(fn msg -> String.length(msg.content) end)
    |> Enum.sum()
    
    {:ok, div(total, 4)}
  end
  
  @doc """
  Returns mock models.
  """
  def models(_opts) do
    {:ok, ["mock-model-1", "mock-model-2"]}
  end
end