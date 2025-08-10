defmodule Chainex.Integration.NestedStructTest do
  use ExUnit.Case, async: false

  alias Chainex.Chain

  @moduletag :integration
  @moduletag timeout: 120_000

  defmodule Address do
    defstruct [:street, :city, :country, :postal_code]
  end

  defmodule Company do
    defstruct [:name, :industry, :size, :address]
  end

  defmodule PersonalInfo do
    defstruct [:first_name, :last_name, :age, :email]
  end

  defmodule CompleteUser do
    defstruct [:id, :personal_info, :company]
  end

  describe "LLM + automatic nested struct parsing" do
    @tag :live_api
    test "LLM generates nested JSON that gets parsed into nested structs" do
      chain =
        Chain.new("""
        Generate information for a software engineer:
        - id: 12345
        - personal_info with: first_name "Sarah", last_name "Chen", age 28, email "sarah@example.com"
        - company with: name "TechCorp", industry "Software", size 250, and address with street "123 Tech Ave", city "San Francisco", country "USA", postal_code "94105"
        """)
        |> Chain.llm(:anthropic, temperature: 0, max_tokens: 400)
        |> Chain.parse(:struct, CompleteUser)

      assert {:ok, result} = Chain.run(chain)
      assert %CompleteUser{} = result
      assert result.id == 12345

      # personal_info should be converted to PersonalInfo struct automatically
      assert %PersonalInfo{} = result.personal_info
      assert result.personal_info.first_name == "Sarah"
      assert result.personal_info.last_name == "Chen"
      assert result.personal_info.age == 28
      assert result.personal_info.email == "sarah@example.com"

      # company should be converted to Company struct automatically
      assert %Company{} = result.company
      assert result.company.name == "TechCorp"
      assert result.company.industry == "Software"
      assert result.company.size == 250

      # nested address within company should be converted to Address struct
      assert %Address{} = result.company.address
      assert result.company.address.street == "123 Tech Ave"
      assert result.company.address.city == "San Francisco"
      assert result.company.address.country == "USA"
      assert result.company.address.postal_code == "94105"
    end

    test "nested struct parsing with mock LLM" do
      chain =
        Chain.new("Generate user data")
        |> Chain.llm(:mock)
        |> Chain.transform(fn _mock_response ->
          # Simulate LLM response with nested JSON
          ~s({
          "id": 67890,
          "personal_info": {
            "first_name": "John",
            "last_name": "Doe",
            "age": 35,
            "email": "john@company.com"
          },
          "company": {
            "name": "Amazing Corp",
            "industry": "Technology",
            "size": 500,
            "address": {
              "street": "456 Business St",
              "city": "Austin",
              "country": "USA",
              "postal_code": "78701"
            }
          }
        })
        end)
        |> Chain.parse(:struct, CompleteUser)

      assert {:ok, result} = Chain.run(chain)
      assert %CompleteUser{} = result
      assert result.id == 67890

      # All nested structs should be properly converted
      assert %PersonalInfo{} = result.personal_info
      assert result.personal_info.first_name == "John"

      assert %Company{} = result.company
      assert result.company.name == "Amazing Corp"

      assert %Address{} = result.company.address
      assert result.company.address.street == "456 Business St"
    end
  end
end
