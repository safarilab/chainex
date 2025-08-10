defmodule Chainex.Chain.VariableResolver do
  @moduledoc """
  Resolves template variables in strings using {{variable}} syntax.
  Supports default values with {{variable:default}} syntax.
  """

  @variable_regex ~r/\{\{([^}:]+)(?::([^}]+))?\}\}/

  @doc """
  Resolves all variables in a template string.

  ## Examples

      iex> resolve("Hello {{name}}", %{name: "Alice"})
      {:ok, "Hello Alice"}
      
      iex> resolve("Hello {{name:World}}", %{})
      {:ok, "Hello World"}
      
      iex> resolve("{{greeting}} {{name}}", %{greeting: "Hi", name: "Bob"})
      {:ok, "Hi Bob"}
  """
  @spec resolve(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def resolve(template, variables) when is_binary(template) do
    result =
      Regex.replace(@variable_regex, template, fn match, var_name, default ->
        resolve_variable(var_name, default, variables, match)
      end)

    # Check if any variables remain unresolved (still have {{ }})
    if String.contains?(result, "{{") and String.contains?(result, "}}") do
      unresolved = extract_unresolved_variables(result)
      {:error, "Unresolved variables: #{inspect(unresolved)}"}
    else
      {:ok, result}
    end
  end

  def resolve(template, _variables) when is_nil(template) do
    {:ok, ""}
  end

  def resolve(template, _variables) do
    {:ok, to_string(template)}
  end

  @doc """
  Extracts all variable names from a template.

  ## Examples

      iex> extract_variables("Hello {{name}}, you are {{age}} years old")
      ["name", "age"]
  """
  @spec extract_variables(String.t()) :: [String.t()]
  def extract_variables(template) when is_binary(template) do
    @variable_regex
    |> Regex.scan(template)
    |> Enum.map(fn
      [_, var_name, _default] -> String.trim(var_name)
      [_, var_name] -> String.trim(var_name)
    end)
    |> Enum.uniq()
  end

  def extract_variables(_), do: []

  @doc """
  Checks if a template has any variables.

  ## Examples

      iex> has_variables?("Hello {{name}}")
      true
      
      iex> has_variables?("Hello World")
      false
  """
  @spec has_variables?(String.t()) :: boolean()
  def has_variables?(template) when is_binary(template) do
    Regex.match?(@variable_regex, template)
  end

  def has_variables?(_), do: false

  # Private functions

  defp resolve_variable(var_name, default, variables, original_match) do
    var_name = String.trim(var_name)

    # Handle special variables
    case var_name do
      ":from_input" ->
        Map.get(variables, :input, Map.get(variables, "input", default || original_match))
        |> to_string()

      ":from_previous" ->
        Map.get(variables, :input, Map.get(variables, "input", default || original_match))
        |> to_string()

      _ ->
        # Try to find the variable as atom or string key
        value = find_variable_value(var_name, variables)

        case value do
          nil when not is_nil(default) ->
            # Use default value if provided
            default

          nil ->
            # Keep original if no value and no default
            original_match

          value ->
            to_string(value)
        end
    end
  end

  defp find_variable_value(var_name, variables) do
    # Try as string key first
    case Map.get(variables, var_name) do
      nil ->
        # Try as atom key
        try do
          atom_key = String.to_existing_atom(var_name)
          Map.get(variables, atom_key)
        rescue
          ArgumentError -> nil
        end

      value ->
        value
    end
  end

  defp extract_unresolved_variables(text) do
    @variable_regex
    |> Regex.scan(text)
    |> Enum.map(fn
      [full_match, _, _] -> full_match
      [full_match, _] -> full_match
    end)
  end

  @doc """
  Resolves variables in a nested data structure.

  ## Examples

      iex> resolve_deep(%{greeting: "Hello {{name}}"}, %{name: "Alice"})
      {:ok, %{greeting: "Hello Alice"}}
  """
  @spec resolve_deep(any(), map()) :: {:ok, any()} | {:error, String.t()}
  def resolve_deep(data, variables) when is_map(data) do
    resolved =
      Enum.reduce_while(data, %{}, fn {key, value}, acc ->
        case resolve_deep(value, variables) do
          {:ok, resolved_value} ->
            {:cont, Map.put(acc, key, resolved_value)}

          {:error, _} = error ->
            {:halt, error}
        end
      end)

    case resolved do
      {:error, _} = error -> error
      map -> {:ok, map}
    end
  end

  def resolve_deep(data, variables) when is_list(data) do
    resolved =
      Enum.reduce_while(data, [], fn item, acc ->
        case resolve_deep(item, variables) do
          {:ok, resolved_item} ->
            {:cont, acc ++ [resolved_item]}

          {:error, _} = error ->
            {:halt, error}
        end
      end)

    case resolved do
      {:error, _} = error -> error
      list -> {:ok, list}
    end
  end

  def resolve_deep(data, variables) when is_binary(data) do
    resolve(data, variables)
  end

  def resolve_deep(data, _variables) do
    {:ok, data}
  end
end
