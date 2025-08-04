defmodule Chainex.Tool do
  @moduledoc """
  Function calling abstraction for Chainex workflows

  Provides a standardized way to define, validate, and execute tools/functions
  in LLM chains. Supports parameter validation, type checking, error handling,
  and result formatting.

  ## Tool Definition

  Tools are defined with:
  - Name and description
  - Parameter schema with types and validation
  - Implementation function
  - Optional result transformation

  ## Usage Examples

      # Define a simple tool
      weather_tool = Tool.new(
        name: "get_weather",
        description: "Get current weather for a location",
        parameters: %{
          location: %{type: :string, required: true},
          units: %{type: :string, default: "celsius", enum: ["celsius", "fahrenheit"]}
        },
        function: fn params ->
          # Implementation here
          {:ok, %{temperature: 22, condition: "sunny"}}
        end
      )

      # Execute the tool
      result = Tool.call(weather_tool, %{location: "New York"})
  """

  defstruct [:name, :description, :parameters, :function, :options]

  @type parameter_type :: :string | :integer | :float | :boolean | :list | :map | :atom
  @type parameter_schema :: %{
          type: parameter_type(),
          required: boolean(),
          default: any(),
          enum: [any()],
          min: number(),
          max: number(),
          pattern: Regex.t(),
          description: String.t()
        }
  @type t :: %__MODULE__{
          name: String.t() | atom(),
          description: String.t(),
          parameters: %{atom() => parameter_schema()},
          function: (map() -> {:ok, any()} | {:error, term()}),
          options: map()
        }

  @doc """
  Creates a new tool definition

  ## Examples

      iex> tool = Tool.new(
      ...>   name: "add_numbers",
      ...>   description: "Add two numbers together",
      ...>   parameters: %{
      ...>     a: %{type: :integer, required: true},
      ...>     b: %{type: :integer, required: true}
      ...>   },
      ...>   function: fn %{a: a, b: b} -> {:ok, a + b} end
      ...> )
      iex> tool.name
      "add_numbers"

      iex> tool = Tool.new(
      ...>   name: :math_tool,
      ...>   description: "Math operations",
      ...>   parameters: %{},
      ...>   function: fn _ -> {:ok, "result"} end
      ...> )
      iex> tool.name
      :math_tool
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description, "")
    parameters = Keyword.get(opts, :parameters, %{})
    function = Keyword.fetch!(opts, :function)
    options = Keyword.get(opts, :options, %{})

    %__MODULE__{
      name: name,
      description: description,
      parameters: normalize_parameters(parameters),
      function: function,
      options: options
    }
  end

  @doc """
  Validates a tool definition

  ## Examples

      iex> tool = Tool.new(
      ...>   name: "valid_tool",
      ...>   description: "A valid tool",
      ...>   parameters: %{param: %{type: :string, required: true}},
      ...>   function: fn _ -> {:ok, "result"} end
      ...> )
      iex> Tool.validate_definition(tool)
      :ok

      iex> invalid_tool = %Tool{name: "", description: "Invalid", parameters: %{}, function: nil}
      iex> Tool.validate_definition(invalid_tool)
      {:error, {:invalid_tool, "Tool name cannot be empty"}}
  """
  @spec validate_definition(t()) :: :ok | {:error, term()}
  def validate_definition(%__MODULE__{} = tool) do
    with :ok <- validate_name(tool.name),
         :ok <- validate_parameters(tool.parameters),
         :ok <- validate_function(tool.function) do
      :ok
    end
  end

  @doc """
  Calls a tool with the given parameters

  ## Examples

      iex> tool = Tool.new(
      ...>   name: "greet",
      ...>   description: "Greet someone",
      ...>   parameters: %{
      ...>     name: %{type: :string, required: true},
      ...>     formal: %{type: :boolean, default: false}
      ...>   },
      ...>   function: fn %{name: name, formal: formal} ->
      ...>     greeting = if formal, do: "Good day, " <> name, else: "Hi " <> name <> "!"
      ...>     {:ok, greeting}
      ...>   end
      ...> )
      iex> Tool.call(tool, %{name: "Alice"})
      {:ok, "Hi Alice!"}

      iex> tool = Tool.new(
      ...>   name: "greet",
      ...>   description: "Greet someone",
      ...>   parameters: %{
      ...>     name: %{type: :string, required: true},
      ...>     formal: %{type: :boolean, default: false}
      ...>   },
      ...>   function: fn %{name: name, formal: formal} ->
      ...>     greeting = if formal, do: "Good day, " <> name, else: "Hi " <> name <> "!"
      ...>     {:ok, greeting}
      ...>   end
      ...> )
      iex> Tool.call(tool, %{name: "Bob", formal: true})
      {:ok, "Good day, Bob"}
  """
  @spec call(t(), map()) :: {:ok, any()} | {:error, term()}
  def call(%__MODULE__{} = tool, params) when is_map(params) do
    with :ok <- validate_definition(tool),
         {:ok, validated_params} <- validate_and_prepare_params(tool.parameters, params) do
      try do
        case tool.function.(validated_params) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
      rescue
        e -> {:error, {:function_error, Exception.message(e)}}
      end
    end
  end

  @doc """
  Calls a tool with parameters, raising on error

  ## Examples

      iex> tool = Tool.new(
      ...>   name: "multiply",
      ...>   description: "Multiply two numbers",
      ...>   parameters: %{
      ...>     x: %{type: :number, required: true},
      ...>     y: %{type: :number, required: true}
      ...>   },
      ...>   function: fn %{x: x, y: y} -> {:ok, x * y} end
      ...> )
      iex> Tool.call!(tool, %{x: 5, y: 3})
      15
  """
  @spec call!(t(), map()) :: any()
  def call!(%__MODULE__{} = tool, params) do
    case call(tool, params) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Tool call failed: #{inspect(reason)}"
    end
  end

  @doc """
  Gets the schema for a tool's parameters

  ## Examples

      iex> tool = Tool.new(
      ...>   name: "example",
      ...>   description: "Example tool",
      ...>   parameters: %{
      ...>     name: %{type: :string, required: true, description: "User name"},
      ...>     age: %{type: :integer, min: 0, max: 150, default: 25}
      ...>   },
      ...>   function: fn _ -> {:ok, "result"} end
      ...> )
      iex> schema = Tool.get_schema(tool)
      iex> schema.name.type
      :string
      iex> schema.age.default
      25
  """
  @spec get_schema(t()) :: map()
  def get_schema(%__MODULE__{parameters: parameters}) do
    parameters
  end

  @doc """
  Lists all required parameters for a tool

  ## Examples

      iex> tool = Tool.new(
      ...>   name: "test",
      ...>   description: "Test tool",
      ...>   parameters: %{
      ...>     required_param: %{type: :string, required: true},
      ...>     optional_param: %{type: :integer, default: 10}
      ...>   },
      ...>   function: fn _ -> {:ok, "result"} end
      ...> )
      iex> Tool.required_parameters(tool)
      [:required_param]
  """
  @spec required_parameters(t()) :: [atom()]
  def required_parameters(%__MODULE__{parameters: parameters}) do
    parameters
    |> Enum.filter(fn {_key, schema} -> Map.get(schema, :required, false) end)
    |> Enum.map(fn {key, _schema} -> key end)
  end

  @doc """
  Gets default values for optional parameters

  ## Examples

      iex> tool = Tool.new(
      ...>   name: "test",
      ...>   description: "Test tool",
      ...>   parameters: %{
      ...>     name: %{type: :string, required: true},
      ...>     count: %{type: :integer, default: 5},
      ...>     enabled: %{type: :boolean, default: true}
      ...>   },
      ...>   function: fn _ -> {:ok, "result"} end
      ...> )
      iex> Tool.default_parameters(tool)
      %{count: 5, enabled: true}
  """
  @spec default_parameters(t()) :: map()
  def default_parameters(%__MODULE__{parameters: parameters}) do
    parameters
    |> Enum.filter(fn {_key, schema} -> Map.has_key?(schema, :default) end)
    |> Enum.into(%{}, fn {key, schema} -> {key, schema.default} end)
  end

  # Private helper functions

  defp normalize_parameters(parameters) when is_map(parameters) do
    parameters
    |> Enum.into(%{}, fn {key, schema} ->
      normalized_key = if is_binary(key), do: String.to_atom(key), else: key
      normalized_schema = normalize_parameter_schema(schema)
      {normalized_key, normalized_schema}
    end)
  end

  defp normalize_parameter_schema(schema) when is_map(schema) do
    schema
    |> Map.put_new(:required, false)
    |> Map.update(:type, :string, &normalize_type/1)
  end

  defp normalize_type(:number), do: :number
  defp normalize_type("number"), do: :number
  defp normalize_type(:string), do: :string
  defp normalize_type("string"), do: :string
  defp normalize_type(:integer), do: :integer
  defp normalize_type("integer"), do: :integer
  defp normalize_type(:float), do: :float
  defp normalize_type("float"), do: :float
  defp normalize_type(:boolean), do: :boolean
  defp normalize_type("boolean"), do: :boolean
  defp normalize_type(:list), do: :list
  defp normalize_type("list"), do: :list
  defp normalize_type(:map), do: :map
  defp normalize_type("map"), do: :map
  defp normalize_type(:atom), do: :atom
  defp normalize_type("atom"), do: :atom
  defp normalize_type(type), do: type

  defp validate_name(name) when is_binary(name) and byte_size(name) > 0, do: :ok
  defp validate_name(name) when is_atom(name) and name != nil, do: :ok
  defp validate_name(""), do: {:error, {:invalid_tool, "Tool name cannot be empty"}}
  defp validate_name(nil), do: {:error, {:invalid_tool, "Tool name cannot be nil"}}
  defp validate_name(_), do: {:error, {:invalid_tool, "Tool name must be a string or atom"}}

  defp validate_parameters(parameters) when is_map(parameters) do
    case Enum.find(parameters, fn {_key, schema} -> not valid_parameter_schema?(schema) end) do
      nil -> :ok
      {key, _schema} -> {:error, {:invalid_parameter, "Invalid schema for parameter: #{key}"}}
    end
  end

  defp validate_function(function) when is_function(function, 1), do: :ok
  defp validate_function(_), do: {:error, {:invalid_tool, "Function must be a 1-arity function"}}

  defp valid_parameter_schema?(schema) when is_map(schema) do
    has_valid_type =
      Map.has_key?(schema, :type) and
        schema.type in [:string, :integer, :float, :number, :boolean, :list, :map, :atom]

    # Check enum values if present
    enum_valid =
      case Map.get(schema, :enum) do
        nil -> true
        enum_list when is_list(enum_list) -> true
        _ -> false
      end

    has_valid_type and enum_valid
  end

  defp valid_parameter_schema?(_), do: false

  defp validate_and_prepare_params(schema, params) do
    # Start with default values
    defaults = get_defaults_from_schema(schema)
    merged_params = Map.merge(defaults, params)

    with :ok <- check_required_params(schema, merged_params),
         {:ok, validated_params} <- validate_param_types(schema, merged_params) do
      {:ok, validated_params}
    end
  end

  defp get_defaults_from_schema(schema) do
    schema
    |> Enum.filter(fn {_key, param_schema} -> Map.has_key?(param_schema, :default) end)
    |> Enum.into(%{}, fn {key, param_schema} -> {key, param_schema.default} end)
  end

  defp check_required_params(schema, params) do
    required_keys =
      schema
      |> Enum.filter(fn {_key, param_schema} -> Map.get(param_schema, :required, false) end)
      |> Enum.map(fn {key, _schema} -> key end)

    missing_keys = required_keys -- Map.keys(params)

    case missing_keys do
      [] -> :ok
      missing -> {:error, {:missing_parameters, missing}}
    end
  end

  defp validate_param_types(schema, params) do
    validated_params =
      params
      |> Enum.map(fn {key, value} ->
        case Map.get(schema, key) do
          # Allow extra parameters
          nil ->
            {key, value}

          param_schema ->
            case validate_param_value(value, param_schema) do
              {:ok, validated_value} -> {key, validated_value}
              {:error, reason} -> {:error, {key, reason}}
            end
        end
      end)

    # Check for any validation errors
    case Enum.find(validated_params, fn
           {:error, _} -> true
           _ -> false
         end) do
      nil ->
        valid_params = Enum.into(validated_params, %{})
        {:ok, valid_params}

      {:error, {key, reason}} ->
        {:error, {:invalid_parameter_value, key, reason}}
    end
  end

  defp validate_param_value(value, %{type: :string} = schema) do
    cond do
      is_binary(value) -> validate_string_constraints(value, schema)
      true -> {:error, "must be a string"}
    end
  end

  defp validate_param_value(value, %{type: :integer} = schema) do
    cond do
      is_integer(value) -> validate_number_constraints(value, schema)
      true -> {:error, "must be an integer"}
    end
  end

  defp validate_param_value(value, %{type: :float} = schema) do
    cond do
      is_float(value) -> validate_number_constraints(value, schema)
      true -> {:error, "must be a float"}
    end
  end

  defp validate_param_value(value, %{type: :number} = schema) do
    cond do
      is_number(value) -> validate_number_constraints(value, schema)
      true -> {:error, "must be a number"}
    end
  end

  defp validate_param_value(value, %{type: :boolean}) do
    cond do
      is_boolean(value) -> {:ok, value}
      true -> {:error, "must be a boolean"}
    end
  end

  defp validate_param_value(value, %{type: :list}) do
    cond do
      is_list(value) -> {:ok, value}
      true -> {:error, "must be a list"}
    end
  end

  defp validate_param_value(value, %{type: :map}) do
    cond do
      is_map(value) -> {:ok, value}
      true -> {:error, "must be a map"}
    end
  end

  defp validate_param_value(value, %{type: :atom}) do
    cond do
      is_atom(value) -> {:ok, value}
      true -> {:error, "must be an atom"}
    end
  end

  defp validate_param_value(value, _schema), do: {:ok, value}

  defp validate_string_constraints(value, schema) do
    with :ok <- check_enum_constraint(value, schema),
         :ok <- check_pattern_constraint(value, schema) do
      {:ok, value}
    end
  end

  defp validate_number_constraints(value, schema) do
    with :ok <- check_enum_constraint(value, schema),
         :ok <- check_min_constraint(value, schema),
         :ok <- check_max_constraint(value, schema) do
      {:ok, value}
    end
  end

  defp check_enum_constraint(value, %{enum: enum}) when is_list(enum) do
    if value in enum do
      :ok
    else
      {:error, "must be one of #{inspect(enum)}"}
    end
  end

  defp check_enum_constraint(_value, _schema), do: :ok

  defp check_pattern_constraint(value, %{pattern: pattern}) when is_binary(value) do
    if Regex.match?(pattern, value) do
      :ok
    else
      {:error, "must match pattern #{inspect(pattern)}"}
    end
  end

  defp check_pattern_constraint(_value, _schema), do: :ok

  defp check_min_constraint(value, %{min: min}) when is_number(value) and is_number(min) do
    if value >= min do
      :ok
    else
      {:error, "must be >= #{min}"}
    end
  end

  defp check_min_constraint(_value, _schema), do: :ok

  defp check_max_constraint(value, %{max: max}) when is_number(value) and is_number(max) do
    if value <= max do
      :ok
    else
      {:error, "must be <= #{max}"}
    end
  end

  defp check_max_constraint(_value, _schema), do: :ok
end

defmodule Chainex.Tool.Registry do
  @moduledoc """
  Registry for managing multiple tools

  Provides a centralized way to register, lookup, and manage tools
  in a Chainex workflow.
  """

  defstruct [:tools, :options]

  @type t :: %__MODULE__{
          tools: %{(atom() | String.t()) => Chainex.Tool.t()},
          options: map()
        }

  @doc """
  Creates a new tool registry

  ## Examples

      iex> registry = Tool.Registry.new()
      iex> Tool.Registry.size(registry)
      0

      iex> tools = [
      ...>   Tool.new(name: "tool1", description: "First tool", parameters: %{}, function: fn _ -> {:ok, "result"} end),
      ...>   Tool.new(name: "tool2", description: "Second tool", parameters: %{}, function: fn _ -> {:ok, "result"} end)
      ...> ]
      iex> registry = Tool.Registry.new(tools)
      iex> Tool.Registry.size(registry)
      2
  """
  @spec new([Chainex.Tool.t()], map()) :: t()
  def new(tools \\ [], options \\ %{}) do
    tool_map =
      tools
      |> Enum.map(fn tool -> {tool.name, tool} end)
      |> Enum.into(%{})

    %__MODULE__{
      tools: tool_map,
      options: options
    }
  end

  @doc """
  Registers a tool in the registry

  ## Examples

      iex> registry = Tool.Registry.new()
      iex> tool = Tool.new(name: "test", description: "Test tool", parameters: %{}, function: fn _ -> {:ok, "result"} end)
      iex> updated = Tool.Registry.register(registry, tool)
      iex> Tool.Registry.size(updated)
      1
  """
  @spec register(t(), Chainex.Tool.t()) :: t()
  def register(%__MODULE__{tools: tools} = registry, %Chainex.Tool{} = tool) do
    updated_tools = Map.put(tools, tool.name, tool)
    %{registry | tools: updated_tools}
  end

  @doc """
  Gets a tool from the registry by name

  ## Examples

      iex> tool = Tool.new(name: "example", description: "Example", parameters: %{}, function: fn _ -> {:ok, "result"} end)
      iex> registry = Tool.Registry.new([tool])
      iex> {:ok, retrieved} = Tool.Registry.get(registry, "example")
      iex> retrieved.name
      "example"

      iex> registry = Tool.Registry.new()
      iex> Tool.Registry.get(registry, "missing")
      {:error, :tool_not_found}
  """
  @spec get(t(), atom() | String.t()) :: {:ok, Chainex.Tool.t()} | {:error, :tool_not_found}
  def get(%__MODULE__{tools: tools}, name) do
    case Map.get(tools, name) do
      nil -> {:error, :tool_not_found}
      tool -> {:ok, tool}
    end
  end

  @doc """
  Gets a tool from the registry by name, raising if not found

  ## Examples

      iex> tool = Tool.new(name: "example", description: "Example", parameters: %{}, function: fn _ -> {:ok, "result"} end)
      iex> registry = Tool.Registry.new([tool])
      iex> retrieved = Tool.Registry.get!(registry, "example")
      iex> retrieved.name
      "example"
  """
  @spec get!(t(), atom() | String.t()) :: Chainex.Tool.t()
  def get!(%__MODULE__{} = registry, name) do
    case get(registry, name) do
      {:ok, tool} -> tool
      {:error, :tool_not_found} -> raise ArgumentError, "Tool not found: #{name}"
    end
  end

  @doc """
  Calls a tool from the registry

  ## Examples

      iex> tool = Tool.new(
      ...>   name: "add",
      ...>   description: "Add numbers",
      ...>   parameters: %{a: %{type: :number, required: true}, b: %{type: :number, required: true}},
      ...>   function: fn %{a: a, b: b} -> {:ok, a + b} end
      ...> )
      iex> registry = Tool.Registry.new([tool])
      iex> Tool.Registry.call(registry, "add", %{a: 2, b: 3})
      {:ok, 5}

      iex> registry = Tool.Registry.new()
      iex> Tool.Registry.call(registry, "missing", %{})
      {:error, :tool_not_found}
  """
  @spec call(t(), atom() | String.t(), map()) :: {:ok, any()} | {:error, term()}
  def call(%__MODULE__{} = registry, tool_name, params) do
    case get(registry, tool_name) do
      {:ok, tool} -> Chainex.Tool.call(tool, params)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all tool names in the registry

  ## Examples

      iex> tools = [
      ...>   Tool.new(name: "tool1", description: "First", parameters: %{}, function: fn _ -> {:ok, "result"} end),
      ...>   Tool.new(name: "tool2", description: "Second", parameters: %{}, function: fn _ -> {:ok, "result"} end)
      ...> ]
      iex> registry = Tool.Registry.new(tools)
      iex> names = Tool.Registry.list_tools(registry)
      iex> Enum.sort(names)
      ["tool1", "tool2"]
  """
  @spec list_tools(t()) :: [atom() | String.t()]
  def list_tools(%__MODULE__{tools: tools}) do
    Map.keys(tools)
  end

  @doc """
  Returns the number of tools in the registry

  ## Examples

      iex> registry = Tool.Registry.new()
      iex> Tool.Registry.size(registry)
      0

      iex> tool = Tool.new(name: "test", description: "Test", parameters: %{}, function: fn _ -> {:ok, "result"} end)
      iex> registry = Tool.Registry.new([tool])
      iex> Tool.Registry.size(registry)
      1
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{tools: tools}) do
    map_size(tools)
  end

  @doc """
  Removes a tool from the registry

  ## Examples

      iex> tool = Tool.new(name: "test", description: "Test", parameters: %{}, function: fn _ -> {:ok, "result"} end)
      iex> registry = Tool.Registry.new([tool])
      iex> Tool.Registry.size(registry)
      1
      iex> updated = Tool.Registry.unregister(registry, "test")
      iex> Tool.Registry.size(updated)
      0
  """
  @spec unregister(t(), atom() | String.t()) :: t()
  def unregister(%__MODULE__{tools: tools} = registry, name) do
    updated_tools = Map.delete(tools, name)
    %{registry | tools: updated_tools}
  end

  @doc """
  Gets all tools as a list

  ## Examples

      iex> tool1 = Tool.new(name: "tool1", description: "First", parameters: %{}, function: fn _ -> {:ok, "result"} end)
      iex> tool2 = Tool.new(name: "tool2", description: "Second", parameters: %{}, function: fn _ -> {:ok, "result"} end)
      iex> registry = Tool.Registry.new([tool1, tool2])
      iex> tools = Tool.Registry.all_tools(registry)
      iex> length(tools)
      2
  """
  @spec all_tools(t()) :: [Chainex.Tool.t()]
  def all_tools(%__MODULE__{tools: tools}) do
    Map.values(tools)
  end

  @doc """
  Validates all tools in the registry

  ## Examples

      iex> valid_tool = Tool.new(name: "valid", description: "Valid", parameters: %{}, function: fn _ -> {:ok, "result"} end)
      iex> registry = Tool.Registry.new([valid_tool])
      iex> Tool.Registry.validate_all(registry)
      :ok
  """
  @spec validate_all(t()) :: :ok | {:error, term()}
  def validate_all(%__MODULE__{tools: tools}) do
    case Enum.find(tools, fn {_name, tool} ->
           case Chainex.Tool.validate_definition(tool) do
             :ok -> false
             {:error, _} -> true
           end
         end) do
      nil -> :ok
      {name, _tool} -> {:error, {:invalid_tool_in_registry, name}}
    end
  end
end
