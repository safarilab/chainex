defmodule Chainex.Tools.TextProcessor do
  @moduledoc """
  Text processing tools for common text manipulation tasks.
  """

  alias Chainex.Tool

  @doc """
  Creates a text length counter tool.
  """
  def text_length_tool do
    Tool.new(
      name: "count_text",
      description: "Counts characters, words, and lines in text",
      parameters: %{
        text: %{
          type: :string,
          required: true,
          description: "The text to analyze"
        },
        count_type: %{
          type: :string,
          default: "all",
          enum: ["characters", "words", "lines", "all"],
          description: "Type of count to return"
        }
      },
      function: &count_text/1
    )
  end

  @doc """
  Creates a text case converter tool.
  """
  def case_converter_tool do
    Tool.new(
      name: "convert_case",
      description: "Converts text to different cases (uppercase, lowercase, title case, etc.)",
      parameters: %{
        text: %{
          type: :string,
          required: true,
          description: "The text to convert"
        },
        case_type: %{
          type: :string,
          required: true,
          enum: ["uppercase", "lowercase", "title", "sentence"],
          description: "The case format to convert to"
        }
      },
      function: &convert_case/1
    )
  end

  @doc """
  Creates a text search and replace tool.
  """
  def search_replace_tool do
    Tool.new(
      name: "search_replace",
      description: "Searches for text patterns and replaces them",
      parameters: %{
        text: %{
          type: :string,
          required: true,
          description: "The text to search in"
        },
        search: %{
          type: :string,
          required: true,
          description: "The text or pattern to search for"
        },
        replace: %{
          type: :string,
          required: true,
          description: "The replacement text"
        },
        regex: %{
          type: :boolean,
          default: false,
          description: "Whether to treat search as a regular expression"
        }
      },
      function: &search_replace/1
    )
  end

  # Tool implementations

  def count_text(%{text: text, count_type: "characters"}) do
    {:ok, %{characters: String.length(text)}}
  end

  def count_text(%{text: text, count_type: "words"}) do
    word_count = text |> String.split(~r/\s+/, trim: true) |> length()
    {:ok, %{words: word_count}}
  end

  def count_text(%{text: text, count_type: "lines"}) do
    line_count = text |> String.split(~r/\r?\n/) |> length()
    {:ok, %{lines: line_count}}
  end

  def count_text(%{text: text, count_type: "all"}) do
    characters = String.length(text)
    words = text |> String.split(~r/\s+/, trim: true) |> length()
    lines = text |> String.split(~r/\r?\n/) |> length()
    
    {:ok, %{
      characters: characters,
      words: words,
      lines: lines
    }}
  end

  def count_text(%{text: text}) do
    count_text(%{text: text, count_type: "all"})
  end

  def convert_case(%{text: text, case_type: "uppercase"}) do
    {:ok, String.upcase(text)}
  end

  def convert_case(%{text: text, case_type: "lowercase"}) do
    {:ok, String.downcase(text)}
  end

  def convert_case(%{text: text, case_type: "title"}) do
    result = text 
    |> String.split(~r/\s+/) 
    |> Enum.map(&String.capitalize/1) 
    |> Enum.join(" ")
    {:ok, result}
  end

  def convert_case(%{text: text, case_type: "sentence"}) do
    result = text
    |> String.downcase()
    |> String.replace(~r/^\w/, fn first_char -> String.upcase(first_char) end)
    {:ok, result}
  end

  def search_replace(%{text: text, search: search, replace: replace, regex: true}) do
    try do
      pattern = Regex.compile!(search)
      result = Regex.replace(pattern, text, replace)
      {:ok, result}
    rescue
      e -> {:error, "Invalid regex pattern: #{Exception.message(e)}"}
    end
  end

  def search_replace(%{text: text, search: search, replace: replace, regex: false}) do
    result = String.replace(text, search, replace)
    {:ok, result}
  end

  def search_replace(%{text: text, search: search, replace: replace}) do
    search_replace(%{text: text, search: search, replace: replace, regex: false})
  end
end