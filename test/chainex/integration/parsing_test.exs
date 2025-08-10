defmodule Chainex.Integration.ParsingTest do
  use ExUnit.Case, async: false

  alias Chainex.Chain

  @moduletag :integration
  # 2 minute timeout for API calls
  @moduletag timeout: 120_000

  defmodule TestUser do
    defstruct [:name, :age, :email, :location, :active]
  end

  defmodule TestProduct do
    defstruct [:id, :name, :price, :category, :in_stock]
  end

  describe "LLM + JSON parsing integration" do
    @tag :live_api
    test "LLM generates JSON that gets parsed correctly" do
      chain =
        Chain.new("""
        Generate a JSON object with the following fields:
        - name: "Alice Johnson"  
        - age: 28
        - email: "alice@example.com"
        """)
        |> Chain.llm(:anthropic, temperature: 0, max_tokens: 200)
        |> Chain.parse(:json)

      assert {:ok, result} = Chain.run(chain)
      assert is_map(result)
      assert result["name"] == "Alice Johnson"
      assert result["age"] == 28
      assert result["email"] == "alice@example.com"
    end

    @tag :live_api
    test "LLM generates JSON with schema validation" do
      schema = %{"name" => :string, "age" => :integer, "active" => :boolean}

      chain =
        Chain.new("""
        Create a JSON object for a user with:
        - name: "Bob Smith"
        - age: 35
        - active: true
        """)
        |> Chain.llm(:anthropic, temperature: 0, max_tokens: 200)
        |> Chain.parse(:json, schema)

      assert {:ok, result} = Chain.run(chain)
      assert result["name"] == "Bob Smith"
      assert result["age"] == 35
      assert result["active"] == true
    end

    @tag :live_api
    test "handles LLM JSON with extra formatting" do
      chain =
        Chain.new("""
        Create a JSON object for a product:
        - id: 123
        - name: "Laptop"
        - price: 999.99
        """)
        |> Chain.llm(:anthropic, temperature: 0, max_tokens: 300)
        |> Chain.transform(fn response ->
          # Extract JSON from response that might have extra text
          case Regex.run(~r/\{.*\}/s, response) do
            [json] -> json
            # Fallback to original
            _ -> response
          end
        end)
        |> Chain.parse(:json)

      assert {:ok, result} = Chain.run(chain)
      assert is_map(result)
      assert result["id"] == 123
      assert result["name"] == "Laptop"
      assert is_number(result["price"])
    end
  end

  describe "LLM + struct parsing integration" do
    @tag :live_api
    test "LLM generates JSON that gets parsed into struct" do
      chain =
        Chain.new("""
        Generate JSON for a user profile:
        - name: "Charlie Brown"
        - age: 32
        - email: "charlie@example.com" 
        - location: "San Francisco"
        - active: true
        """)
        |> Chain.llm(:anthropic, temperature: 0, max_tokens: 250)
        |> Chain.parse(:struct, TestUser)

      assert {:ok, result} = Chain.run(chain)
      assert %TestUser{} = result
      assert result.name == "Charlie Brown"
      assert result.age == 32
      assert result.email == "charlie@example.com"
      assert result.location == "San Francisco"
      assert result.active == true
    end

    @tag :live_api
    test "struct parsing ignores unknown fields from LLM" do
      chain =
        Chain.new("""
        Create a JSON object with these fields and some extra ones:
        - name: "Diana Prince"
        - age: 30
        - email: "diana@example.com"
        - extra_field: "this should be ignored"
        - another_extra: 12345
        """)
        |> Chain.llm(:anthropic, temperature: 0, max_tokens: 300)
        |> Chain.parse(:struct, TestUser)

      assert {:ok, result} = Chain.run(chain)
      assert %TestUser{} = result
      assert result.name == "Diana Prince"
      assert result.age == 30
      assert result.email == "diana@example.com"
      # Extra fields should be ignored, check what we expect
      # Note: LLM might include location field as it's part of the struct
      assert is_binary(result.name)
      assert is_integer(result.age)
    end

    @tag :live_api
    test "handles multiple structs in chain" do
      chain =
        Chain.new("""
        Generate JSON for a product:
        - id: 456
        - name: "Smartphone" 
        - price: 799.99
        - category: "Electronics"
        - in_stock: true
        """)
        |> Chain.llm(:anthropic, temperature: 0, max_tokens: 250)
        |> Chain.parse(:struct, TestProduct)
        |> Chain.transform(fn product ->
          # Transform the product struct into a user-friendly description
          "Product: #{product.name} (#{product.category}) - $#{product.price} - #{if product.in_stock, do: "Available", else: "Out of Stock"}"
        end)

      assert {:ok, result} = Chain.run(chain)
      assert is_binary(result)
      assert result =~ "Smartphone"
      assert result =~ "Electronics"
      assert result =~ "$799.99"
      assert result =~ "Available"
    end
  end

  describe "complex parsing workflows" do
    @tag :live_api
    test "LLM to JSON to struct to transformation pipeline" do
      chain =
        Chain.new("""
        Create a user profile in JSON format:
        - name: "Eve Wilson"
        - age: 27
        - email: "eve@company.com"
        - location: "New York"
        - active: true
        """)
        |> Chain.llm(:anthropic, temperature: 0, max_tokens: 250)
        |> Chain.parse(:json)
        |> Chain.transform(fn json_data ->
          # Modify the data before struct parsing
          # Age them up by 1
          Map.put(json_data, "age", json_data["age"] + 1)
        end)
        |> Chain.parse(:struct, TestUser)
        |> Chain.transform(fn %TestUser{} = user ->
          # Generate a welcome message
          "Welcome #{user.name}! You are #{user.age} years old and located in #{user.location}."
        end)

      assert {:ok, result} = Chain.run(chain)
      assert is_binary(result)
      assert result =~ "Eve Wilson"
      # Age should be incremented
      assert result =~ "28"
      assert result =~ "New York"
    end

    @tag :live_api
    test "error handling in parsing chain" do
      # This should fail at JSON parsing stage
      chain =
        Chain.new("Generate invalid JSON that cannot be parsed")
        |> Chain.llm(:anthropic, temperature: 0, max_tokens: 100)
        # Force invalid JSON
        |> Chain.transform(fn _response -> "invalid json {" end)
        |> Chain.parse(:json)
        |> Chain.parse(:struct, TestUser)

      assert {:error, _reason} = Chain.run(chain)
    end

    @tag :live_api
    test "schema validation failure in chain" do
      schema = %{"name" => :string, "age" => :integer}

      # Use a transform to force invalid JSON that will fail schema validation
      chain =
        Chain.new("Generate user data")
        |> Chain.llm(:mock)
        |> Chain.transform(fn _mock_response ->
          # Force JSON that doesn't match schema (missing required fields)
          ~s({"email": "test@example.com", "city": "New York"})
        end)
        |> Chain.parse(:json, schema)

      assert {:error, _reason} = Chain.run(chain)
    end
  end

  describe "parsing with mock LLM" do
    test "mock LLM with JSON parsing" do
      chain =
        Chain.new("Generate user data")
        |> Chain.llm(:mock)
        |> Chain.transform(fn _mock_response ->
          # Override mock response with known JSON
          ~s({"name": "Mock User", "age": 25, "email": "mock@test.com"})
        end)
        |> Chain.parse(:json)

      assert {:ok, result} = Chain.run(chain)
      assert result["name"] == "Mock User"
      assert result["age"] == 25
    end

    test "mock LLM with struct parsing" do
      chain =
        Chain.new("Generate product data")
        |> Chain.llm(:mock)
        |> Chain.transform(fn _mock_response ->
          ~s({"id": 789, "name": "Mock Product", "price": 99.99, "category": "Test", "in_stock": false})
        end)
        |> Chain.parse(:struct, TestProduct)

      assert {:ok, result} = Chain.run(chain)
      assert %TestProduct{} = result
      assert result.name == "Mock Product"
      assert result.price == 99.99
      assert result.in_stock == false
    end
  end
end
