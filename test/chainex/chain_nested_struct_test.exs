defmodule Chainex.ChainNestedStructTest do
  use ExUnit.Case, async: true
  
  alias Chainex.Chain

  # Define nested structs for testing
  defmodule Address do
    defstruct [:street, :city, :country, :postal_code]
  end

  defmodule Company do
    defstruct [:name, :industry, :size, :address]
  end

  defmodule PersonalInfo do
    defstruct [:first_name, :last_name, :date_of_birth, :phone]
  end

  defmodule WorkInfo do
    defstruct [:position, :department, :salary, :start_date, :company]
  end

  defmodule ComplexUser do
    defstruct [:id, :personal_info, :work_info, :addresses, :metadata]
  end

  describe "automatic nested struct parsing" do
    test "parses simple nested struct automatically" do
      json_string = ~s({
        "name": "TechCorp",
        "industry": "Technology", 
        "size": 500,
        "address": {
          "street": "123 Tech St",
          "city": "San Francisco",
          "country": "USA",
          "postal_code": "94105"
        }
      })
      
      chain = Chain.new(json_string)
      |> Chain.parse(:struct, Company)
      
      assert {:ok, result} = Chain.run(chain)
      assert %Company{} = result
      assert result.name == "TechCorp"
      assert result.industry == "Technology"
      assert result.size == 500
      
      # This should be automatically converted to an Address struct
      # based on field name matching (address -> Address)
      assert %Address{} = result.address
      assert result.address.street == "123 Tech St"
      assert result.address.city == "San Francisco"
      assert result.address.country == "USA"
      assert result.address.postal_code == "94105"
    end

    test "parses deeply nested structs" do
      json_string = ~s({
        "id": 12345,
        "personal_info": {
          "first_name": "John",
          "last_name": "Doe", 
          "date_of_birth": "1990-01-15",
          "phone": "+1-555-0123"
        },
        "work_info": {
          "position": "Software Engineer",
          "department": "Engineering",
          "salary": 95000,
          "start_date": "2020-03-01",
          "company": {
            "name": "Awesome Inc",
            "industry": "Software",
            "size": 1200
          }
        },
        "addresses": [
          {
            "street": "456 Home Ave",
            "city": "Austin",
            "country": "USA", 
            "postal_code": "73301"
          },
          {
            "street": "789 Work Blvd",
            "city": "Austin",
            "country": "USA",
            "postal_code": "73302"
          }
        ],
        "metadata": {
          "created_at": "2024-08-09T10:00:00Z",
          "updated_at": "2024-08-09T10:00:00Z", 
          "version": 1
        }
      })
      
      chain = Chain.new(json_string)
      |> Chain.parse(:struct, ComplexUser)
      
      assert {:ok, result} = Chain.run(chain)
      assert %ComplexUser{} = result
      assert result.id == 12345
      
      # personal_info should be converted to PersonalInfo struct
      assert %PersonalInfo{} = result.personal_info
      assert result.personal_info.first_name == "John"
      assert result.personal_info.last_name == "Doe"
      assert result.personal_info.date_of_birth == "1990-01-15"
      
      # work_info should be converted to WorkInfo struct
      assert %WorkInfo{} = result.work_info
      assert result.work_info.position == "Software Engineer"
      assert result.work_info.salary == 95000
      
      # Nested company in work_info should be converted to Company struct  
      assert %Company{} = result.work_info.company
      assert result.work_info.company.name == "Awesome Inc"
      assert result.work_info.company.industry == "Software"
      
      # addresses should be a list of Address structs
      assert is_list(result.addresses)
      assert length(result.addresses) == 2
      assert %Address{} = hd(result.addresses)
      assert hd(result.addresses).street == "456 Home Ave"
      assert hd(result.addresses).city == "Austin"
      
      # metadata should be empty map since no Metadata struct exists 
      assert result.metadata == %{}
    end

    test "handles missing nested structs gracefully" do
      # If a nested struct module doesn't exist, fall back to map
      json_string = ~s({
        "id": 67890,
        "unknown_nested": {
          "some_field": "value"
        }
      })
      
      chain = Chain.new(json_string)
      |> Chain.parse(:struct, ComplexUser)
      
      assert {:ok, result} = Chain.run(chain)
      assert %ComplexUser{} = result
      assert result.id == 67890
      # Since no UnknownNested struct exists, should remain a map
      # But since unknown_nested is not a field of ComplexUser, it should be ignored
      assert result.personal_info == nil
    end

    test "handles arrays of nested structs" do
      json_string = ~s({
        "addresses": [
          {"street": "123 Main St", "city": "Boston", "country": "USA"},
          {"street": "456 Oak Ave", "city": "Portland", "country": "USA"}
        ]
      })
      
      chain = Chain.new(json_string)
      |> Chain.parse(:struct, ComplexUser)
      
      assert {:ok, result} = Chain.run(chain)
      assert %ComplexUser{} = result
      
      # addresses should be converted to list of Address structs
      assert is_list(result.addresses)
      assert length(result.addresses) == 2
      assert %Address{} = hd(result.addresses)
      assert hd(result.addresses).street == "123 Main St"
      assert hd(result.addresses).city == "Boston"
    end
  end
end