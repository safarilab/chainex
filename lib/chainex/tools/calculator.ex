defmodule Chainex.Tools.Calculator do
  @moduledoc """
  Calculator tool for performing mathematical calculations.
  """

  alias Chainex.Tool

  @doc """
  Creates a calculator tool that can evaluate mathematical expressions.
  """
  def new do
    Tool.new(
      name: "calculator",
      description: "Performs mathematical calculations. Supports basic arithmetic operations (+, -, *, /), exponentiation (^), and common math functions (sqrt, sin, cos, tan, log, ln, abs, round, floor, ceil).",
      parameters: %{
        expression: %{
          type: :string,
          required: true,
          description: "Mathematical expression to evaluate (e.g., '2 + 3', 'sqrt(16)', 'sin(3.14159/2)')"
        }
      },
      function: &evaluate/1
    )
  end

  @doc """
  Evaluates a mathematical expression.

  ## Examples

      iex> Calculator.evaluate(%{expression: "2 + 3"})
      {:ok, 5}

      iex> Calculator.evaluate(%{expression: "sqrt(16)"})
      {:ok, 4.0}

      iex> Calculator.evaluate(%{expression: "invalid expression"})
      {:error, "Invalid mathematical expression"}
  """
  def evaluate(%{expression: expression}) do
    try do
      result = safe_eval(expression)
      {:ok, result}
    rescue
      _ -> {:error, "Invalid mathematical expression: #{expression}"}
    end
  end

  # Safe evaluation of mathematical expressions
  defp safe_eval(expression) do
    # Clean the expression and replace common math functions
    cleaned = 
      expression
      |> String.replace(~r/\s+/, "")
      |> String.replace("^", " ** ")
      |> String.replace("sqrt(", ":math.sqrt(")
      |> String.replace("sin(", ":math.sin(")
      |> String.replace("cos(", ":math.cos(")
      |> String.replace("tan(", ":math.tan(")
      |> String.replace("log(", ":math.log10(")
      |> String.replace("ln(", ":math.log(")
      |> String.replace("abs(", "abs(")
      |> String.replace("round(", "round(")
      |> String.replace("floor(", "Float.floor(")
      |> String.replace("ceil(", "Float.ceil(")
      |> String.replace("pi", to_string(:math.pi()))
      |> String.replace("e", to_string(:math.exp(1)))

    # Validate that the expression only contains allowed characters
    if Regex.match?(~r/^[0-9+\-*\/\(\)\.\s:mathsqrtincoabslgFlourndge_]+$/, cleaned) do
      {result, _} = Code.eval_string(cleaned)
      result
    else
      raise "Invalid characters in expression"
    end
  end
end