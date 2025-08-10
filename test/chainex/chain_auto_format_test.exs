defmodule Chainex.ChainAutoFormatTest do
  use ExUnit.Case, async: true

  alias Chainex.Chain

  defmodule TestUser do
    defstruct [:name, :age, :email]
  end

  defmodule User do
    defstruct [:name, :age]
  end

  describe "automatic format instruction injection" do
    test "injects JSON format instructions into LLM step" do
      chain =
        Chain.new("Generate some data")
        |> Chain.llm(:mock, max_tokens: 100)
        |> Chain.parse(:json)

      # Check that the LLM step was modified
      [{:llm, :mock, opts}, {:parse, :json, _}] = chain.steps

      assert Keyword.has_key?(opts, :system)
      system_message = Keyword.get(opts, :system)
      assert system_message =~ "IMPORTANT: Please respond with valid JSON only"
      assert system_message =~ "Do not include any explanatory text"
    end

    test "injects JSON format instructions with schema" do
      schema = %{"name" => :string, "age" => :integer}

      chain =
        Chain.new("Generate user data")
        |> Chain.llm(:mock)
        |> Chain.parse(:json, schema)

      [{:llm, :mock, opts}, {:parse, :json, _}] = chain.steps

      system_message = Keyword.get(opts, :system)
      assert system_message =~ "containing these fields:"
      assert system_message =~ "name"
      assert system_message =~ "age"
    end

    test "injects struct format instructions" do
      chain =
        Chain.new("Generate user")
        |> Chain.llm(:mock)
        |> Chain.parse(:struct, TestUser)

      [{:llm, :mock, opts}, {:parse, :struct, _}] = chain.steps

      system_message = Keyword.get(opts, :system)
      assert system_message =~ "containing these fields: name, age, email"
    end

    test "appends to existing system message" do
      chain =
        Chain.new("Generate data")
        |> Chain.llm(:mock, system: "You are a helpful assistant.")
        |> Chain.parse(:json)

      [{:llm, :mock, opts}, {:parse, :json, _}] = chain.steps

      system_message = Keyword.get(opts, :system)
      assert system_message =~ "You are a helpful assistant."
      assert system_message =~ "IMPORTANT: Please respond with valid JSON only"
    end

    test "does not modify non-LLM previous steps" do
      original_chain =
        Chain.new("test")
        |> Chain.transform(fn x -> x end)

      chain = original_chain |> Chain.parse(:json)

      # Should have transform step unchanged, then parse step
      [{:transform, _, _}, {:parse, :json, _}] = chain.steps
    end

    test "handles custom parser functions" do
      custom_parser = fn input -> {:ok, input} end

      chain =
        Chain.new("Generate data")
        |> Chain.llm(:mock)
        |> Chain.parse(custom_parser)

      [{:llm, :mock, opts}, {:parse, _, _}] = chain.steps

      system_message = Keyword.get(opts, :system)
      assert system_message =~ "Please provide your response in the exact format requested"
    end
  end

  describe "format instruction integration tests" do
    test "works with mock LLM for JSON parsing" do
      chain =
        Chain.new("Generate user data with name and age")
        # This should get format instructions injected
        |> Chain.llm(:mock)
        |> Chain.transform(fn _mock_response ->
          # Override mock response with proper JSON (simulating LLM following instructions)
          ~s({"name": "Alice", "age": 30})
        end)
        |> Chain.parse(:json)

      assert {:ok, result} = Chain.run(chain)
      assert result["name"] == "Alice"
      assert result["age"] == 30
    end

    test "works with mock LLM for struct parsing" do
      chain =
        Chain.new("Generate user")
        # This should get format instructions injected
        |> Chain.llm(:mock)
        |> Chain.transform(fn _mock_response ->
          # Simulate LLM responding with clean JSON as instructed
          ~s({"name": "Bob", "age": 25})
        end)
        |> Chain.parse(:struct, User)

      assert {:ok, %User{} = result} = Chain.run(chain)
      assert result.name == "Bob"
      assert result.age == 25
    end
  end
end
