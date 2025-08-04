defmodule Chainex.ToolTest do
  use ExUnit.Case, async: true
  alias Chainex.Tool
  doctest Chainex.Tool
  doctest Chainex.Tool.Registry

  describe "new/1" do
    test "creates tool with basic parameters" do
      tool = Tool.new(
        name: "test_tool",
        description: "A test tool",
        parameters: %{},
        function: fn _ -> {:ok, "result"} end
      )

      assert tool.name == "test_tool"
      assert tool.description == "A test tool"
      assert tool.parameters == %{}
      assert is_function(tool.function, 1)
    end

    test "creates tool with atom name" do
      tool = Tool.new(
        name: :atom_tool,
        description: "Tool with atom name",
        parameters: %{},
        function: fn _ -> {:ok, "result"} end
      )

      assert tool.name == :atom_tool
    end

    test "normalizes parameter schemas" do
      tool = Tool.new(
        name: "param_tool",
        description: "Tool with parameters",
        parameters: %{
          "string_key" => %{type: "string", required: true},
          number_param: %{type: :integer, default: 10}
        },
        function: fn _ -> {:ok, "result"} end
      )

      # Should convert string keys to atoms
      assert Map.has_key?(tool.parameters, :string_key)
      assert Map.has_key?(tool.parameters, :number_param)
      
      # Should normalize types
      assert tool.parameters.string_key.type == :string
      assert tool.parameters.number_param.type == :integer
      
      # Should add default required: false
      assert tool.parameters.number_param.required == false
    end
  end

  describe "validate_definition/1" do
    test "validates valid tool definition" do
      tool = Tool.new(
        name: "valid_tool",
        description: "Valid tool",
        parameters: %{
          param1: %{type: :string, required: true},
          param2: %{type: :integer, default: 5}
        },
        function: fn _ -> {:ok, "result"} end
      )

      assert :ok = Tool.validate_definition(tool)
    end

    test "rejects empty name" do
      tool = Tool.new(
        name: "",
        description: "Invalid tool",
        parameters: %{},
        function: fn _ -> {:ok, "result"} end
      )

      assert {:error, {:invalid_tool, "Tool name cannot be empty"}} = Tool.validate_definition(tool)
    end

    test "rejects nil name" do
      tool = %Tool{
        name: nil,
        description: "Invalid tool",
        parameters: %{},
        function: fn _ -> {:ok, "result"} end
      }

      assert {:error, {:invalid_tool, "Tool name cannot be nil"}} = Tool.validate_definition(tool)
    end

    test "rejects invalid function" do
      tool = %Tool{
        name: "test",
        description: "Invalid function",
        parameters: %{},
        function: "not_a_function"
      }

      assert {:error, {:invalid_tool, "Function must be a 1-arity function"}} = Tool.validate_definition(tool)
    end

    test "rejects invalid parameter schema" do
      tool = Tool.new(
        name: "invalid_params",
        description: "Invalid parameters",
        parameters: %{
          bad_param: %{type: :invalid_type}
        },
        function: fn _ -> {:ok, "result"} end
      )

      assert {:error, {:invalid_parameter, _}} = Tool.validate_definition(tool)
    end
  end

  describe "call/2" do
    test "calls tool with valid parameters" do
      tool = Tool.new(
        name: "add_tool",
        description: "Add two numbers",
        parameters: %{
          a: %{type: :number, required: true},
          b: %{type: :number, required: true}
        },
        function: fn %{a: a, b: b} -> {:ok, a + b} end
      )

      assert {:ok, 8} = Tool.call(tool, %{a: 3, b: 5})
    end

    test "applies default parameter values" do
      tool = Tool.new(
        name: "greet_tool",
        description: "Greet someone",
        parameters: %{
          name: %{type: :string, required: true},
          prefix: %{type: :string, default: "Hello"}
        },
        function: fn %{name: name, prefix: prefix} -> {:ok, "#{prefix}, #{name}!"} end
      )

      assert {:ok, "Hello, Alice!"} = Tool.call(tool, %{name: "Alice"})
      assert {:ok, "Hi, Bob!"} = Tool.call(tool, %{name: "Bob", prefix: "Hi"})
    end

    test "validates required parameters" do
      tool = Tool.new(
        name: "required_tool",
        description: "Tool with required param",
        parameters: %{
          required_param: %{type: :string, required: true},
          optional_param: %{type: :string, default: "default"}
        },
        function: fn _ -> {:ok, "result"} end
      )

      assert {:error, {:missing_parameters, [:required_param]}} = Tool.call(tool, %{})
      assert {:ok, "result"} = Tool.call(tool, %{required_param: "value"})
    end

    test "validates parameter types" do
      tool = Tool.new(
        name: "typed_tool",
        description: "Tool with typed parameters",
        parameters: %{
          string_param: %{type: :string, required: true},
          int_param: %{type: :integer, required: true},
          bool_param: %{type: :boolean, default: false}
        },
        function: fn params -> {:ok, params} end
      )

      # Valid types
      assert {:ok, _} = Tool.call(tool, %{string_param: "hello", int_param: 42})
      
      # Invalid types
      assert {:error, {:invalid_parameter_value, :string_param, "must be a string"}} = 
        Tool.call(tool, %{string_param: 123, int_param: 42})
      
      assert {:error, {:invalid_parameter_value, :int_param, "must be an integer"}} = 
        Tool.call(tool, %{string_param: "hello", int_param: "not_int"})
    end

    test "validates enum constraints" do
      tool = Tool.new(
        name: "enum_tool",
        description: "Tool with enum parameter",
        parameters: %{
          status: %{type: :string, enum: ["active", "inactive", "pending"], required: true}
        },
        function: fn %{status: status} -> {:ok, "Status is #{status}"} end
      )

      assert {:ok, "Status is active"} = Tool.call(tool, %{status: "active"})
      assert {:error, {:invalid_parameter_value, :status, _}} = Tool.call(tool, %{status: "invalid"})
    end

    test "validates number constraints" do
      tool = Tool.new(
        name: "range_tool",
        description: "Tool with number range",
        parameters: %{
          age: %{type: :integer, min: 0, max: 150, required: true}
        },
        function: fn %{age: age} -> {:ok, "Age is #{age}"} end
      )

      assert {:ok, "Age is 25"} = Tool.call(tool, %{age: 25})
      assert {:error, {:invalid_parameter_value, :age, "must be >= 0"}} = Tool.call(tool, %{age: -1})
      assert {:error, {:invalid_parameter_value, :age, "must be <= 150"}} = Tool.call(tool, %{age: 200})
    end

    test "validates string pattern constraints" do
      tool = Tool.new(
        name: "pattern_tool",
        description: "Tool with pattern validation",
        parameters: %{
          email: %{type: :string, pattern: ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/, required: true}
        },
        function: fn %{email: email} -> {:ok, "Email is #{email}"} end
      )

      assert {:ok, "Email is test@example.com"} = Tool.call(tool, %{email: "test@example.com"})
      assert {:error, {:invalid_parameter_value, :email, _}} = Tool.call(tool, %{email: "invalid-email"})
    end

    test "handles function errors gracefully" do
      tool = Tool.new(
        name: "error_tool",
        description: "Tool that can error",
        parameters: %{
          should_error: %{type: :boolean, default: false}
        },
        function: fn %{should_error: should_error} ->
          if should_error do
            raise "Intentional error"
          else
            {:ok, "success"}
          end
        end
      )

      assert {:ok, "success"} = Tool.call(tool, %{should_error: false})
      assert {:error, {:function_error, "Intentional error"}} = Tool.call(tool, %{should_error: true})
    end

    test "handles functions that return raw values" do
      tool = Tool.new(
        name: "raw_return_tool",
        description: "Tool that returns raw values",
        parameters: %{},
        function: fn _ -> "raw_result" end
      )

      assert {:ok, "raw_result"} = Tool.call(tool, %{})
    end

    test "handles functions that return error tuples" do
      tool = Tool.new(
        name: "error_tuple_tool",
        description: "Tool that returns error tuples",
        parameters: %{
          should_succeed: %{type: :boolean, required: true}
        },
        function: fn %{should_succeed: should_succeed} ->
          if should_succeed do
            {:ok, "success"}
          else
            {:error, :custom_error}
          end
        end
      )

      assert {:ok, "success"} = Tool.call(tool, %{should_succeed: true})
      assert {:error, :custom_error} = Tool.call(tool, %{should_succeed: false})
    end
  end

  describe "call!/2" do
    test "returns result directly on success" do
      tool = Tool.new(
        name: "success_tool",
        description: "Always succeeds",
        parameters: %{},
        function: fn _ -> {:ok, "success"} end
      )

      assert "success" = Tool.call!(tool, %{})
    end

    test "raises on error" do
      tool = Tool.new(
        name: "fail_tool",
        description: "Always fails",
        parameters: %{},
        function: fn _ -> {:error, :failure} end
      )

      assert_raise ArgumentError, fn ->
        Tool.call!(tool, %{})
      end
    end
  end

  describe "utility functions" do
    setup do
      tool = Tool.new(
        name: "utility_tool",
        description: "Tool for testing utilities",
        parameters: %{
          required_string: %{type: :string, required: true, description: "A required string"},
          optional_int: %{type: :integer, default: 42, description: "An optional integer"},
          optional_bool: %{type: :boolean, default: true},
          enum_param: %{type: :string, enum: ["a", "b", "c"], default: "a"}
        },
        function: fn _ -> {:ok, "result"} end
      )
      
      {:ok, tool: tool}
    end

    test "get_schema/1 returns parameter schemas", %{tool: tool} do
      schema = Tool.get_schema(tool)
      
      assert Map.has_key?(schema, :required_string)
      assert Map.has_key?(schema, :optional_int)
      assert schema.required_string.type == :string
      assert schema.optional_int.default == 42
    end

    test "required_parameters/1 lists required parameters", %{tool: tool} do
      required = Tool.required_parameters(tool)
      
      assert required == [:required_string]
    end

    test "default_parameters/1 returns default values", %{tool: tool} do
      defaults = Tool.default_parameters(tool)
      
      expected = %{
        optional_int: 42,
        optional_bool: true,
        enum_param: "a"
      }
      
      assert defaults == expected
    end
  end

  describe "complex parameter validation" do
    test "validates all supported types" do
      tool = Tool.new(
        name: "types_tool",
        description: "Tool with all types",
        parameters: %{
          string_param: %{type: :string, required: true},
          integer_param: %{type: :integer, required: true},
          float_param: %{type: :float, required: true},
          number_param: %{type: :number, required: true},
          boolean_param: %{type: :boolean, required: true},
          list_param: %{type: :list, required: true},
          map_param: %{type: :map, required: true},
          atom_param: %{type: :atom, required: true}
        },
        function: fn params -> {:ok, params} end
      )

      valid_params = %{
        string_param: "hello",
        integer_param: 42,
        float_param: 3.14,
        number_param: 100,
        boolean_param: true,
        list_param: [1, 2, 3],
        map_param: %{key: "value"},
        atom_param: :test
      }

      assert {:ok, result} = Tool.call(tool, valid_params)
      assert result == valid_params
    end

    test "rejects invalid types for each parameter type" do
      tool = Tool.new(
        name: "strict_types_tool",
        description: "Tool with strict type checking",
        parameters: %{
          string_param: %{type: :string, required: true},
          integer_param: %{type: :integer, required: true},
          float_param: %{type: :float, required: true},
          boolean_param: %{type: :boolean, required: true},
          list_param: %{type: :list, required: true},
          map_param: %{type: :map, required: true},
          atom_param: %{type: :atom, required: true}
        },
        function: fn _ -> {:ok, "result"} end
      )

      # Test invalid string
      assert {:error, {:invalid_parameter_value, :string_param, "must be a string"}} = 
        Tool.call(tool, %{string_param: 123, integer_param: 1, float_param: 1.0, boolean_param: true, list_param: [], map_param: %{}, atom_param: :test})

      # Test invalid integer  
      assert {:error, {:invalid_parameter_value, :integer_param, "must be an integer"}} = 
        Tool.call(tool, %{string_param: "test", integer_param: "not_int", float_param: 1.0, boolean_param: true, list_param: [], map_param: %{}, atom_param: :test})

      # Test invalid float
      assert {:error, {:invalid_parameter_value, :float_param, "must be a float"}} = 
        Tool.call(tool, %{string_param: "test", integer_param: 1, float_param: "not_float", boolean_param: true, list_param: [], map_param: %{}, atom_param: :test})

      # Test invalid boolean
      assert {:error, {:invalid_parameter_value, :boolean_param, "must be a boolean"}} = 
        Tool.call(tool, %{string_param: "test", integer_param: 1, float_param: 1.0, boolean_param: "not_bool", list_param: [], map_param: %{}, atom_param: :test})
    end
  end
end

defmodule Chainex.Tool.RegistryTest do
  use ExUnit.Case, async: true
  alias Chainex.Tool
  alias Chainex.Tool.Registry

  describe "new/2" do
    test "creates empty registry" do
      registry = Registry.new()
      
      assert Registry.size(registry) == 0
      assert Registry.list_tools(registry) == []
    end

    test "creates registry with initial tools" do
      tools = [
        Tool.new(name: "tool1", description: "First tool", parameters: %{}, function: fn _ -> {:ok, "result1"} end),
        Tool.new(name: "tool2", description: "Second tool", parameters: %{}, function: fn _ -> {:ok, "result2"} end)
      ]
      
      registry = Registry.new(tools)
      
      assert Registry.size(registry) == 2
      assert "tool1" in Registry.list_tools(registry)
      assert "tool2" in Registry.list_tools(registry)
    end

    test "creates registry with options" do
      registry = Registry.new([], %{description: "Test registry"})
      
      assert registry.options.description == "Test registry"
    end
  end

  describe "register/2 and get/2" do
    setup do
      {:ok, registry: Registry.new()}
    end

    test "registers and retrieves tools", %{registry: registry} do
      tool = Tool.new(
        name: "test_tool",
        description: "Test tool",
        parameters: %{},
        function: fn _ -> {:ok, "result"} end
      )
      
      updated_registry = Registry.register(registry, tool)
      
      assert Registry.size(updated_registry) == 1
      assert {:ok, retrieved_tool} = Registry.get(updated_registry, "test_tool")
      assert retrieved_tool.name == "test_tool"
    end

    test "overwrites existing tools with same name", %{registry: registry} do
      tool1 = Tool.new(name: "same_name", description: "First", parameters: %{}, function: fn _ -> {:ok, "first"} end)
      tool2 = Tool.new(name: "same_name", description: "Second", parameters: %{}, function: fn _ -> {:ok, "second"} end)
      
      registry = 
        registry
        |> Registry.register(tool1)
        |> Registry.register(tool2)
      
      assert Registry.size(registry) == 1
      assert {:ok, retrieved} = Registry.get(registry, "same_name")
      assert retrieved.description == "Second"
    end

    test "returns error for missing tools", %{registry: registry} do
      assert {:error, :tool_not_found} = Registry.get(registry, "missing_tool")
    end
  end

  describe "get!/2" do
    test "returns tool directly when found" do
      tool = Tool.new(name: "found", description: "Found tool", parameters: %{}, function: fn _ -> {:ok, "result"} end)
      registry = Registry.new([tool])
      
      retrieved = Registry.get!(registry, "found")
      assert retrieved.name == "found"
    end

    test "raises when tool not found" do
      registry = Registry.new()
      
      assert_raise ArgumentError, "Tool not found: missing", fn ->
        Registry.get!(registry, "missing")
      end
    end
  end

  describe "call/3" do
    test "calls tool from registry" do
      tool = Tool.new(
        name: "math_tool",
        description: "Math operations",
        parameters: %{
          operation: %{type: :string, enum: ["add", "multiply"], required: true},
          a: %{type: :number, required: true},
          b: %{type: :number, required: true}
        },
        function: fn %{operation: "add", a: a, b: b} -> {:ok, a + b}
                     %{operation: "multiply", a: a, b: b} -> {:ok, a * b}
                  end
      )
      
      registry = Registry.new([tool])
      
      assert {:ok, 8} = Registry.call(registry, "math_tool", %{operation: "add", a: 3, b: 5})
      assert {:ok, 15} = Registry.call(registry, "math_tool", %{operation: "multiply", a: 3, b: 5})
    end

    test "returns error for missing tool" do
      registry = Registry.new()
      
      assert {:error, :tool_not_found} = Registry.call(registry, "missing", %{})
    end

    test "propagates tool execution errors" do
      tool = Tool.new(
        name: "error_tool",
        description: "Tool that errors",
        parameters: %{},
        function: fn _ -> {:error, :custom_error} end
      )
      
      registry = Registry.new([tool])
      
      assert {:error, :custom_error} = Registry.call(registry, "error_tool", %{})
    end
  end

  describe "list_tools/1 and all_tools/1" do
    test "lists tool names and retrieves all tools" do
      tools = [
        Tool.new(name: "alpha", description: "Alpha tool", parameters: %{}, function: fn _ -> {:ok, "alpha"} end),
        Tool.new(name: "beta", description: "Beta tool", parameters: %{}, function: fn _ -> {:ok, "beta"} end),
        Tool.new(name: "gamma", description: "Gamma tool", parameters: %{}, function: fn _ -> {:ok, "gamma"} end)
      ]
      
      registry = Registry.new(tools)
      
      # Test list_tools
      tool_names = Registry.list_tools(registry)
      assert length(tool_names) == 3
      assert "alpha" in tool_names
      assert "beta" in tool_names
      assert "gamma" in tool_names
      
      # Test all_tools
      all_tools = Registry.all_tools(registry)
      assert length(all_tools) == 3
      assert Enum.any?(all_tools, fn tool -> tool.name == "alpha" end)
      assert Enum.any?(all_tools, fn tool -> tool.name == "beta" end)
      assert Enum.any?(all_tools, fn tool -> tool.name == "gamma" end)
    end
  end

  describe "unregister/2" do
    test "removes tool from registry" do
      tool1 = Tool.new(name: "keep", description: "Keep this", parameters: %{}, function: fn _ -> {:ok, "keep"} end)
      tool2 = Tool.new(name: "remove", description: "Remove this", parameters: %{}, function: fn _ -> {:ok, "remove"} end)
      
      registry = Registry.new([tool1, tool2])
      assert Registry.size(registry) == 2
      
      updated = Registry.unregister(registry, "remove")
      assert Registry.size(updated) == 1
      assert {:ok, _} = Registry.get(updated, "keep")
      assert {:error, :tool_not_found} = Registry.get(updated, "remove")
    end

    test "handles removing non-existent tool gracefully" do
      registry = Registry.new()
      updated = Registry.unregister(registry, "non_existent")
      
      assert Registry.size(updated) == 0
    end
  end

  describe "validate_all/1" do
    test "validates all tools in registry" do
      valid_tools = [
        Tool.new(name: "valid1", description: "Valid", parameters: %{}, function: fn _ -> {:ok, "result"} end),
        Tool.new(name: "valid2", description: "Also valid", parameters: %{param: %{type: :string}}, function: fn _ -> {:ok, "result"} end)
      ]
      
      registry = Registry.new(valid_tools)
      assert :ok = Registry.validate_all(registry)
    end

    test "detects invalid tools in registry" do
      valid_tool = Tool.new(name: "valid", description: "Valid", parameters: %{}, function: fn _ -> {:ok, "result"} end)
      invalid_tool = %Tool{name: "", description: "Invalid", parameters: %{}, function: nil}
      
      # Manually create registry with invalid tool (bypassing normal validation)
      registry = %Registry{tools: %{"valid" => valid_tool, "invalid" => invalid_tool}, options: %{}}
      
      assert {:error, {:invalid_tool_in_registry, "invalid"}} = Registry.validate_all(registry)
    end
  end

  describe "integration scenarios" do
    test "complex workflow with multiple tools" do
      # Define a set of related tools
      calculator_tools = [
        Tool.new(
          name: "add",
          description: "Add two numbers",
          parameters: %{a: %{type: :number, required: true}, b: %{type: :number, required: true}},
          function: fn %{a: a, b: b} -> {:ok, a + b} end
        ),
        Tool.new(
          name: "multiply",
          description: "Multiply two numbers", 
          parameters: %{a: %{type: :number, required: true}, b: %{type: :number, required: true}},
          function: fn %{a: a, b: b} -> {:ok, a * b} end
        ),
        Tool.new(
          name: "format_result",
          description: "Format a number as currency",
          parameters: %{amount: %{type: :number, required: true}, currency: %{type: :string, default: "USD"}},
          function: fn %{amount: amount, currency: currency} -> {:ok, "#{currency} #{amount}"} end
        )
      ]

      registry = Registry.new(calculator_tools)
      
      # Test workflow: (2 + 3) * 4 = 20, formatted as USD 20
      assert {:ok, 5} = Registry.call(registry, "add", %{a: 2, b: 3})
      assert {:ok, 20} = Registry.call(registry, "multiply", %{a: 5, b: 4})
      assert {:ok, "USD 20"} = Registry.call(registry, "format_result", %{amount: 20})
      assert {:ok, "EUR 20"} = Registry.call(registry, "format_result", %{amount: 20, currency: "EUR"})
    end

    test "tool registry is immutable" do
      original_tool = Tool.new(name: "original", description: "Original", parameters: %{}, function: fn _ -> {:ok, "original"} end)
      registry = Registry.new([original_tool])
      
      # Adding a tool should not modify the original registry
      new_tool = Tool.new(name: "new", description: "New", parameters: %{}, function: fn _ -> {:ok, "new"} end)
      updated_registry = Registry.register(registry, new_tool)
      
      assert Registry.size(registry) == 1
      assert Registry.size(updated_registry) == 2
      assert {:error, :tool_not_found} = Registry.get(registry, "new")
      assert {:ok, _} = Registry.get(updated_registry, "new")
    end
  end
end