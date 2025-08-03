defmodule Chainex.Prompt do
  @moduledoc """
  String templating and formatting for Chainex workflows

  Provides template parsing, variable substitution, conditional rendering,
  and formatting utilities for creating dynamic prompts in LLM chains.

  Supports multiple template formats:
  - Mustache-style: `{{variable}}`
  - Python-style: `{variable}`
  - Custom delimiters

  ## Template Features

  - Variable substitution
  - Nested object access (e.g., `{{user.name}}`)
  - Conditional blocks (`{{#if condition}}...{{/if}}`)
  - Loops (`{{#each items}}...{{/each}}`)
  - Filters and transformations
  """

  defstruct [:template, :variables, :options]

  @type template_format :: :mustache | :python | :custom
  @type t :: %__MODULE__{
          template: String.t(),
          variables: map(),
          options: map()
        }

  @doc """
  Creates a new prompt template

  ## Examples

      iex> prompt = Prompt.new("Hello {{name}}!")
      iex> prompt.template
      "Hello {{name}}!"

      iex> prompt = Prompt.new("Hello {name}!", %{}, %{format: :python})
      iex> prompt.options.format
      :python
  """
  @spec new(String.t(), map(), map()) :: t()
  def new(template, variables \\ %{}, options \\ %{}) do
    default_options = %{
      format: :mustache,
      strict: false,
      escape_html: false,
      trim_whitespace: true
    }

    %__MODULE__{
      template: template,
      variables: ensure_map(variables),
      options: Map.merge(default_options, options)
    }
  end

  @doc """
  Renders a template with the given variables

  ## Examples

      iex> prompt = Prompt.new("Hello {{name}}!")
      iex> Prompt.render(prompt, %{name: "Alice"})
      {:ok, "Hello Alice!"}

      iex> prompt = Prompt.new("Age: {{user.age}}")
      iex> Prompt.render(prompt, %{user: %{age: 25}})
      {:ok, "Age: 25"}

      iex> prompt = Prompt.new("Hello {{missing}}!", %{}, %{strict: true})
      iex> Prompt.render(prompt, %{})
      {:error, {:missing_variable, "missing"}}
  """
  @spec render(t(), map()) :: {:ok, String.t()} | {:error, term()}
  def render(%__MODULE__{} = prompt, variables \\ %{}) do
    all_variables = Map.merge(prompt.variables, ensure_map(variables))
    
    case do_render(prompt.template, all_variables, prompt.options) do
      {:ok, result} -> {:ok, maybe_trim(result, prompt.options)}
      error -> error
    end
  end

  @doc """
  Renders a template with variables, raising on error

  ## Examples

      iex> prompt = Prompt.new("Hello {{name}}!")
      iex> Prompt.render!(prompt, %{name: "Bob"})
      "Hello Bob!"
  """
  @spec render!(t(), map()) :: String.t()
  def render!(%__MODULE__{} = prompt, variables \\ %{}) do
    case render(prompt, variables) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Template render failed: #{inspect(reason)}"
    end
  end

  @doc """
  Validates a template and returns any errors

  ## Examples

      iex> prompt = Prompt.new("Hello {{name}}!")
      iex> Prompt.validate(prompt)
      :ok

      iex> prompt = Prompt.new("Hello {{unclosed")
      iex> Prompt.validate(prompt)
      {:error, {:invalid_syntax, "Unclosed template tag at position 6"}}

      iex> prompt = Prompt.new("Hello {{}}!")
      iex> Prompt.validate(prompt)
      {:error, {:invalid_syntax, "Empty variable name"}}

      iex> prompt = Prompt.new("Hello {{.invalid}}!")
      iex> Prompt.validate(prompt)
      {:error, {:invalid_syntax, "Invalid variable name '.invalid'"}}
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{template: template, options: options}) do
    case validate_template_syntax(template, options) do
      :ok -> 
        case parse_template(template, options) do
          {:ok, tokens} -> validate_tokens(tokens)
          error -> error
        end
      error -> error
    end
  end

  @doc """
  Lists all variables referenced in a template

  ## Examples

      iex> prompt = Prompt.new("Hello {{name}}, you are {{age}} years old!")
      iex> Prompt.variables(prompt)
      ["name", "age"]

      iex> prompt = Prompt.new("User: {{user.name}} ({{user.email}})")
      iex> Prompt.variables(prompt)
      ["user.name", "user.email"]
  """
  @spec variables(t()) :: [String.t()]
  def variables(%__MODULE__{template: template, options: options}) do
    case parse_template(template, options) do
      {:ok, tokens} -> extract_variables(tokens)
      {:error, _} -> []
    end
  end

  @doc """
  Compiles a template string into a reusable function

  ## Examples

      iex> compiled = Prompt.compile("Hello {{name}}!")
      iex> compiled.(%{name: "Charlie"})
      "Hello Charlie!"
  """
  @spec compile(String.t(), map()) :: (map() -> String.t())
  def compile(template, options \\ %{}) do
    prompt = new(template, %{}, options)
    
    fn variables ->
      case render(prompt, variables) do
        {:ok, result} -> result
        {:error, reason} -> raise ArgumentError, "Template render failed: #{inspect(reason)}"
      end
    end
  end

  @doc """
  Formats a template with conditional blocks

  ## Examples

      iex> template = "Hello {{name}}!"
      iex> Prompt.format_conditional(template, %{name: "Dave"})
      {:ok, "Hello Dave!"}

      iex> template = "Hello {{name}}!"
      iex> Prompt.format_conditional(template, %{})
      {:ok, "Hello !"}
  """
  @spec format_conditional(String.t(), map(), map()) :: {:ok, String.t()} | {:error, term()}
  def format_conditional(template, variables, options \\ %{}) do
    prompt = new(template, variables, options)
    render(prompt)
  end

  @doc """
  Formats a template with loops

  ## Examples

      iex> template = "Items: {{items}}"
      iex> variables = %{items: ["apple", "banana"]}
      iex> Prompt.format_loop(template, variables)
      {:ok, ~s(Items: ["apple", "banana"])}
  """
  @spec format_loop(String.t(), map(), map()) :: {:ok, String.t()} | {:error, term()}
  def format_loop(template, variables, options \\ %{}) do
    prompt = new(template, variables, options)
    render(prompt)
  end

  # Private helper functions

  defp ensure_map(variables) when is_map(variables), do: variables
  defp ensure_map(variables) when is_list(variables), do: Enum.into(variables, %{})
  defp ensure_map(_), do: %{}

  defp do_render(template, variables, options) do
    case parse_template(template, options) do
      {:ok, tokens} -> render_tokens(tokens, variables, options)
      error -> error
    end
  end

  defp parse_template(template, %{format: :python}) do
    parse_python_template(template)
  end

  defp parse_template(template, _options) do
    parse_mustache_template(template)
  end

  defp parse_mustache_template(template) do
    try do
      matches = Regex.scan(~r/\{\{(.*?)\}\}/, template, capture: :all_but_first)
      tokens = build_tokens(template, matches, ~r/\{\{(.*?)\}\}/)
      {:ok, tokens}
    rescue
      _ -> {:error, {:invalid_syntax, "Invalid template syntax"}}
    end
  end

  defp parse_python_template(template) do
    try do
      matches = Regex.scan(~r/\{([^}]+)\}/, template, capture: :all_but_first)
      tokens = build_tokens(template, matches, ~r/\{([^}]+)\}/)
      {:ok, tokens}
    rescue
      _ -> {:error, {:invalid_syntax, "Invalid template syntax"}}
    end
  end

  defp build_tokens(template, matches, regex) do
    # Use Regex.split with include_captures to get alternating text and variable parts
    parts = Regex.split(regex, template, include_captures: true)
    
    # Process parts - odd indices are text, even indices are variables
    parts
    |> Enum.with_index()
    |> Enum.map(fn {part, index} ->
      if rem(index, 2) == 0 do
        # Text part
        {:text, part}
      else
        # Variable part - extract variable name from the matched content
        var_name = extract_variable_from_match(part, matches)
        {:variable, var_name}
      end
    end)
    |> Enum.reject(fn 
      {:text, ""} -> true
      _ -> false
    end)
  end

  defp extract_variable_from_match(match_text, matches) do
    # Find the matching variable name from our captured groups
    case Enum.find(matches, fn [var] -> 
      String.contains?(match_text, var) 
    end) do
      [var_name] -> String.trim(var_name)
      nil -> 
        # Extract content between braces as fallback
        match_text
        |> String.replace(~r/^\{\{?/, "")
        |> String.replace(~r/\}?\}$/, "")
        |> String.trim()
    end
  end

  defp render_tokens(tokens, variables, options) do
    try do
      result =
        tokens
        |> Enum.map(&render_token(&1, variables, options))
        |> Enum.join("")
      
      {:ok, result}
    rescue
      e in ArgumentError -> {:error, {:missing_variable, e.message}}
      _ -> {:error, {:render_error, "Failed to render template"}}
    end
  end

  defp render_token({:text, text}, _variables, _options), do: text

  defp render_token({:variable, var_name}, variables, options) do
    case get_nested_value(variables, var_name) do
      {:ok, value} -> format_value(value, options)
      {:error, _} -> 
        if options[:strict] do
          raise ArgumentError, var_name
        else
          ""
        end
    end
  end

  defp get_nested_value(variables, var_name) do
    keys = String.split(var_name, ".")
    
    case get_in(variables, Enum.map(keys, &String.to_atom/1)) do
      nil -> 
        # Try string keys
        case get_in(variables, keys) do
          nil -> {:error, :not_found}
          value -> {:ok, value}
        end
      value -> {:ok, value}
    end
  end

  defp format_value(value, %{escape_html: true}) when is_binary(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#x27;")
  end

  defp format_value(nil, _options), do: ""
  defp format_value(value, _options) when is_binary(value), do: value
  defp format_value(value, _options) when is_number(value), do: to_string(value)
  defp format_value(value, _options) when is_atom(value), do: to_string(value)
  defp format_value(value, _options) when is_boolean(value), do: to_string(value)
  defp format_value(value, _options), do: inspect(value)

  defp extract_variables(tokens) do
    tokens
    |> Enum.filter(fn {type, _} -> type == :variable end)
    |> Enum.map(fn {_type, var_name} -> var_name end)
    |> Enum.uniq()
  end

  defp maybe_trim(result, %{trim_whitespace: true}) do
    String.trim(result)
  end

  defp maybe_trim(result, _options), do: result

  # Template validation functions

  defp validate_template_syntax(template, %{format: :python}) do
    validate_python_syntax(template)
  end

  defp validate_template_syntax(template, _options) do
    validate_mustache_syntax(template)
  end

  defp validate_mustache_syntax(template) do
    validate_template_tags(template, ~r/\{\{|\}\}/)
  end

  defp validate_python_syntax(template) do
    validate_template_tags(template, ~r/\{|\}/)
  end

  defp validate_template_tags(template, regex) do
    tags = Regex.scan(regex, template, return: :index)
    |> List.flatten()
    |> Enum.map(fn {pos, len} -> 
      tag = String.slice(template, pos, len)
      {tag, pos}
    end)

    case check_tag_balance(tags, 0, nil) do
      :ok -> :ok
      {:error, type, pos} when type == :unclosed ->
        {:error, {:invalid_syntax, "Unclosed template tag at position #{pos}"}}
      {:error, type, pos} when type == :unopened ->
        {:error, {:invalid_syntax, "Unopened template tag at position #{pos}"}}
    end
  end

  defp check_tag_balance([], 0, _), do: :ok
  defp check_tag_balance([], depth, pos) when depth > 0, do: {:error, :unclosed, pos}
  
  defp check_tag_balance([{tag, pos} | rest], depth, last_open_pos) do
    cond do
      tag in ["{{", "{"] ->
        check_tag_balance(rest, depth + 1, pos)
      
      tag in ["}}", "}"] and depth > 0 ->
        check_tag_balance(rest, depth - 1, last_open_pos)
      
      tag in ["}}", "}"] and depth == 0 ->
        {:error, :unopened, pos}
      
      true ->
        check_tag_balance(rest, depth, last_open_pos)
    end
  end

  defp validate_tokens(tokens) do
    case Enum.find(tokens, &invalid_token?/1) do
      nil -> :ok
      {:variable, ""} -> {:error, {:invalid_syntax, "Empty variable name"}}
      {:variable, var_name} -> validate_variable_name(var_name)
      invalid_token -> {:error, {:invalid_syntax, "Invalid token: #{inspect(invalid_token)}"}}
    end
  end

  defp invalid_token?({:text, _}), do: false
  defp invalid_token?({:variable, ""}), do: true
  defp invalid_token?({:variable, var_name}) when is_binary(var_name) do
    trimmed = String.trim(var_name)
    trimmed == "" or invalid_variable_name?(trimmed)
  end
  defp invalid_token?(_), do: true

  defp validate_variable_name(""), do: {:error, {:invalid_syntax, "Empty variable name"}}
  defp validate_variable_name(var_name) do
    trimmed = String.trim(var_name)
    cond do
      trimmed == "" ->
        {:error, {:invalid_syntax, "Empty variable name"}}
      
      invalid_variable_name?(trimmed) ->
        {:error, {:invalid_syntax, "Invalid variable name '#{trimmed}'"}}
      
      true ->
        :ok
    end
  end

  defp invalid_variable_name?(var_name) do
    # Variable names cannot:
    # - Start or end with dots
    # - Have consecutive dots
    # - Contain only whitespace
    # - Contain invalid characters
    String.starts_with?(var_name, ".") or
    String.ends_with?(var_name, ".") or
    String.contains?(var_name, "..") or
    String.trim(var_name) == "" or
    not Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*(\.[a-zA-Z_][a-zA-Z0-9_]*)*$/, var_name)
  end
end