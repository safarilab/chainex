defmodule Chainex.ChainParsingTest do
  use ExUnit.Case, async: true

  alias Chainex.Chain

  defmodule TestUser do
    defstruct [:name, :age, :email]
  end

  defmodule Address do
    defstruct [:street, :city, :country, :postal_code]
  end

  defmodule Company do
    defstruct [:name, :industry, :size, :address]
  end

  defmodule ComplexUser do
    defstruct [:id, :personal_info, :work_info, :addresses, :metadata]
  end

  defmodule PersonalInfo do
    defstruct [:first_name, :last_name, :date_of_birth, :phone]
  end

  defmodule WorkInfo do
    defstruct [:position, :department, :salary, :start_date, :company]
  end

  describe "JSON parsing" do
    test "parses valid JSON string without schema" do
      json_string = ~s({"name": "Alice", "age": 30})

      chain =
        Chain.new(json_string)
        |> Chain.parse(:json)

      assert {:ok, result} = Chain.run(chain)
      assert is_map(result)
      assert result["name"] == "Alice"
      assert result["age"] == 30
    end

    test "parses valid JSON string with schema validation" do
      json_string = ~s({"name": "Bob", "age": 25})
      schema = %{"name" => :string, "age" => :integer}

      chain =
        Chain.new(json_string)
        |> Chain.parse(:json, schema)

      assert {:ok, result} = Chain.run(chain)
      assert result["name"] == "Bob"
      assert result["age"] == 25
    end

    test "fails with invalid JSON" do
      invalid_json = ~s({"name": "Alice", "age":})

      chain =
        Chain.new(invalid_json)
        |> Chain.parse(:json)

      assert {:error, _reason} = Chain.run(chain)
    end

    test "fails schema validation with missing required fields" do
      json_string = ~s({"name": "Charlie"})
      schema = %{"name" => :string, "age" => :integer}

      chain =
        Chain.new(json_string)
        |> Chain.parse(:json, schema)

      assert {:error, _reason} = Chain.run(chain)
    end

    test "fails when input is not a string" do
      chain =
        Chain.new("placeholder")
        # Transform to map
        |> Chain.transform(fn _input -> %{name: "Alice"} end)
        |> Chain.parse(:json)

      assert {:error, error_msg} = Chain.run(chain)
      assert error_msg =~ "Input must be a string for JSON parsing"
    end
  end

  describe "struct parsing" do
    test "parses JSON string into struct" do
      json_string = ~s({"name": "Alice", "age": 30, "email": "alice@example.com"})

      chain =
        Chain.new(json_string)
        |> Chain.parse(:struct, TestUser)

      assert {:ok, result} = Chain.run(chain)
      assert %TestUser{} = result
      assert result.name == "Alice"
      assert result.age == 30
      assert result.email == "alice@example.com"
    end

    test "parses map into struct" do
      input_map = %{"name" => "Bob", "age" => 25}

      chain =
        Chain.new("placeholder")
        # Transform to provide map
        |> Chain.transform(fn _input -> input_map end)
        |> Chain.parse(:struct, TestUser)

      assert {:ok, result} = Chain.run(chain)
      assert %TestUser{} = result
      assert result.name == "Bob"
      assert result.age == 25
      # Default value
      assert result.email == nil
    end

    test "handles unknown fields gracefully" do
      json_string = ~s({"name": "Charlie", "age": 28, "unknown_field": "ignored"})

      chain =
        Chain.new(json_string)
        |> Chain.parse(:struct, TestUser)

      # Should succeed but ignore unknown field
      assert {:ok, result} = Chain.run(chain)
      assert %TestUser{} = result
      assert result.name == "Charlie"
      assert result.age == 28
    end
  end

  describe "custom parser functions" do
    test "uses custom parser function" do
      input = "2024-01-15"

      date_parser = fn date_string ->
        case Date.from_iso8601(date_string) do
          {:ok, date} -> {:ok, date}
          {:error, reason} -> {:error, "Invalid date: #{reason}"}
        end
      end

      chain =
        Chain.new(input)
        |> Chain.parse(date_parser)

      assert {:ok, result} = Chain.run(chain)
      assert %Date{} = result
      assert result.year == 2024
      assert result.month == 1
      assert result.day == 15
    end

    test "handles parser function errors" do
      input = "not-a-date"

      date_parser = fn date_string ->
        case Date.from_iso8601(date_string) do
          {:ok, date} -> {:ok, date}
          {:error, reason} -> {:error, "Invalid date: #{reason}"}
        end
      end

      chain =
        Chain.new(input)
        |> Chain.parse(date_parser)

      assert {:error, error_msg} = Chain.run(chain)
      assert error_msg =~ "Invalid date"
    end
  end

  describe "chaining with other steps" do
    test "chains JSON parsing after LLM call" do
      # This would typically be an LLM response, but we'll use a transform for testing
      chain =
        Chain.new("Generate some data")
        |> Chain.transform(fn _input -> ~s({"result": "success", "count": 42}) end)
        |> Chain.parse(:json)

      assert {:ok, result} = Chain.run(chain)
      assert result["result"] == "success"
      assert result["count"] == 42
    end

    test "chains struct parsing after JSON parsing" do
      json_string = ~s({"name": "David", "age": 35})

      chain =
        Chain.new(json_string)
        |> Chain.parse(:json)
        |> Chain.parse(:struct, TestUser)

      assert {:ok, result} = Chain.run(chain)
      assert %TestUser{} = result
      assert result.name == "David"
      assert result.age == 35
    end

    test "uses parsed data in subsequent transform" do
      json_string = ~s({"name": "Eve", "age": 28})

      chain =
        Chain.new(json_string)
        |> Chain.parse(:json)
        |> Chain.transform(fn parsed_data ->
          "Hello #{parsed_data["name"]}, you are #{parsed_data["age"]} years old"
        end)

      assert {:ok, result} = Chain.run(chain)
      assert result == "Hello Eve, you are 28 years old"
    end
  end
end
