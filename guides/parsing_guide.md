# Parsing and Validation Guide

Chainex provides sophisticated parsing capabilities to transform LLM text responses into structured, validated data using JSON schemas and Elixir structs.

## JSON Parsing with Schema Validation

Extract structured data from LLM responses with automatic validation:

### Basic JSON Parsing

```elixir
# Simple schema
user_schema = %{
  name: :string,
  age: :integer,
  email: :string
}

"Extract user information from: {{text}}"
|> Chainex.Chain.new()
|> Chainex.Chain.llm(:openai)
|> Chainex.Chain.parse(:json, schema: user_schema)
|> Chainex.Chain.run(%{text: "John Smith, 30 years old, john@example.com"})
# => {:ok, %{"name" => "John Smith", "age" => 30, "email" => "john@example.com"}}
```

### Nested JSON Schemas

Handle complex, nested data structures:

```elixir
company_schema = %{
  company: %{
    name: :string,
    industry: :string,
    founded: :integer,
    headquarters: %{
      city: :string,
      country: :string,
      coordinates: %{
        lat: :float,
        lng: :float
      }
    }
  },
  financials: %{
    revenue: %{
      amount: :float,
      currency: :string,
      period: :string
    },
    employees: :integer,
    funding_rounds: [%{
      round: :string,
      amount: :float,
      date: :string,
      investors: [:string]
    }]
  }
}

"Analyze this company information: {{company_info}}"
|> Chainex.Chain.new()
|> Chainex.Chain.llm(:openai)
|> Chainex.Chain.parse(:json, schema: company_schema)
|> Chainex.Chain.run(%{company_info: "Tesla Inc. is an electric vehicle manufacturer..."})
```

## Struct Parsing

Parse directly into Elixir structs for type safety:

### Defining Structs

```elixir
defmodule ProductAnalysis do
  defstruct [:product, :analysis, :recommendations, :timestamp]
  
  defmodule Product do
    defstruct [:name, :category, :price, :specifications]
    
    defmodule Price do
      defstruct [:amount, :currency, :discount_percent]
    end
    
    defmodule Specifications do
      defstruct [:dimensions, :weight, :features, :warranty_years]
      
      defmodule Dimensions do
        defstruct [:length, :width, :height, :unit]
      end
    end
  end
  
  defmodule Analysis do
    defstruct [:market_position, :strengths, :weaknesses, :competitive_score]
  end
end
```

### Using Struct Parsing

```elixir
"Analyze this product: {{product_description}}"
|> Chainex.Chain.new()
|> Chainex.Chain.llm(:openai)
|> Chainex.Chain.parse(:struct, ProductAnalysis)
|> Chainex.Chain.transform(fn analysis ->
  # Now working with strongly typed structs
  %{analysis | timestamp: DateTime.utc_now()}
end)
|> Chainex.Chain.run(%{product_description: "iPhone 15 Pro - latest smartphone..."})
# Returns: {:ok, %ProductAnalysis{product: %ProductAnalysis.Product{...}}}
```

## Advanced Parsing Features

### Automatic Format Injection

Chainex automatically adds format instructions to improve parsing success:

```elixir
# The parser automatically adds instructions like:
# "Format your response as valid JSON matching this schema: {...}"
# "Ensure all required fields are present and types are correct"

chain = "Extract data from: {{input}}"
|> Chainex.Chain.new()
|> Chainex.Chain.llm(:openai)
|> Chainex.Chain.parse(:json, schema: schema)
# Format instructions are automatically injected before the LLM call
```

### Custom Parsers

Create domain-specific parsers for specialized formats:

```elixir
# Email address parser
email_parser = fn text ->
  emails = Regex.scan(~r/[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}/, text)
  {:ok, List.flatten(emails)}
end

"Find all email addresses in this text: {{text}}"
|> Chainex.Chain.new()
|> Chainex.Chain.llm(:openai)
|> Chainex.Chain.parse(email_parser)
|> Chainex.Chain.run(%{text: "Contact john@example.com or mary@company.org"})
# => {:ok, ["john@example.com", "mary@company.org"]}
```

### CSV Parser

```elixir
csv_parser = fn text ->
  text
  |> String.split("\n")
  |> Enum.map(&String.split(&1, ","))
  |> Enum.map(&Enum.map(&1, fn cell -> String.trim(cell, "\"") end))
  |> then(fn [headers | rows] -> 
    {:ok, %{headers: headers, rows: rows}}
  end)
rescue
  _ -> {:error, "Invalid CSV format"}
end

"Convert this data to CSV format: {{data}}"
|> Chainex.Chain.new()
|> Chainex.Chain.llm(:openai)
|> Chainex.Chain.parse(csv_parser)
```

## Error Handling in Parsing

### Graceful Degradation

Handle parsing failures gracefully:

```elixir
"Extract user data: {{input}}"
|> Chainex.Chain.new()
|> Chainex.Chain.llm(:openai)
|> Chainex.Chain.parse(:json, schema: user_schema, on_error: :return_raw)
|> Chainex.Chain.transform(fn 
  %{} = parsed_data -> 
    # Successfully parsed
    {:parsed, parsed_data}
  raw_text when is_binary(raw_text) ->
    # Parsing failed, got raw text back
    {:raw, raw_text}
end)
```

### Retry with Different Models

```elixir
parsing_chain = fn text ->
  # Try with GPT-4 first (better at structured output)
  case attempt_parse_with_model(text, :gpt4, user_schema) do
    {:ok, result} -> {:ok, result}
    {:error, _} ->
      # Fallback to Claude (different parsing approach)
      case attempt_parse_with_model(text, :claude, user_schema) do
        {:ok, result} -> {:ok, result}
        {:error, _} ->
          # Final fallback - return raw text
          {:ok, text}
      end
  end
end

defp attempt_parse_with_model(text, model, schema) do
  "Extract user data: #{text}"
  |> Chainex.Chain.new()
  |> Chainex.Chain.llm(model)
  |> Chainex.Chain.parse(:json, schema: schema)
  |> Chainex.Chain.run()
end
```

## Validation and Schema Types

### Supported Types

```elixir
comprehensive_schema = %{
  # Basic types
  name: :string,
  age: :integer,
  score: :float,
  active: :boolean,
  
  # Arrays
  tags: [:string],
  numbers: [:integer],
  
  # Nested objects
  address: %{
    street: :string,
    city: :string,
    postal_code: :string
  },
  
  # Array of objects
  contacts: [%{
    type: :string,
    value: :string,
    preferred: :boolean
  }],
  
  # Optional fields (use default values or make nullable)
  bio: {:optional, :string},
  last_login: {:nullable, :string}
}
```

### Custom Validation

Add custom validation logic:

```elixir
validated_parser = fn json_result ->
  case json_result do
    {:ok, %{"email" => email} = data} ->
      if String.contains?(email, "@") do
        {:ok, data}
      else
        {:error, "Invalid email format"}
      end
    error -> error
  end
end

chain = "Extract user data: {{input}}"
|> Chainex.Chain.new()
|> Chainex.Chain.llm(:openai)
|> Chainex.Chain.parse(:json, schema: user_schema)
|> Chainex.Chain.transform(validated_parser)
```

## Real-World Parsing Examples

### Resume Parser

```elixir
defmodule ResumeParser do
  defstruct [:personal, :experience, :education, :skills]
  
  defmodule Personal do
    defstruct [:name, :email, :phone, :location, :summary]
  end
  
  defmodule Experience do
    defstruct [:title, :company, :duration, :responsibilities, :achievements]
  end
  
  defmodule Education do
    defstruct [:degree, :institution, :graduation_year, :gpa]
  end
  
  defmodule Skills do
    defstruct [:technical, :languages, :certifications]
  end
end

resume_chain = "Parse this resume: {{resume_text}}"
|> Chainex.Chain.new()
|> Chainex.Chain.llm(:openai, model: "gpt-4")
|> Chainex.Chain.parse(:struct, ResumeParser)
|> Chainex.Chain.transform(fn resume ->
  # Post-processing
  %{resume | 
    personal: normalize_contact_info(resume.personal),
    experience: rank_by_relevance(resume.experience),
    skills: categorize_skills(resume.skills)
  }
end)
```

### Invoice Parser

```elixir
invoice_schema = %{
  invoice: %{
    number: :string,
    date: :string,
    due_date: :string,
    status: :string
  },
  vendor: %{
    name: :string,
    address: %{
      street: :string,
      city: :string,
      state: :string,
      zip: :string
    },
    tax_id: :string
  },
  line_items: [%{
    description: :string,
    quantity: :integer,
    unit_price: :float,
    total: :float,
    tax_rate: :float
  }],
  totals: %{
    subtotal: :float,
    tax_amount: :float,
    total: :float,
    currency: :string
  }
}

"Extract all information from this invoice: {{invoice_image_description}}"
|> Chainex.Chain.new()
|> Chainex.Chain.llm(:openai, model: "gpt-4-vision")
|> Chainex.Chain.parse(:json, schema: invoice_schema)
|> Chainex.Chain.transform(fn invoice_data ->
  # Validate totals match line items
  calculated_total = calculate_invoice_total(invoice_data["line_items"])
  actual_total = invoice_data["totals"]["total"]
  
  if abs(calculated_total - actual_total) < 0.01 do
    {:ok, invoice_data}
  else
    {:error, "Invoice totals don't match line items"}
  end
end)
```

## Testing Parsing

### Unit Tests

```elixir
defmodule MyApp.ParsingTest do
  use ExUnit.Case
  
  test "user schema parsing" do
    user_schema = %{name: :string, age: :integer}
    
    chain = Chainex.Chain.new("{{input}}")
    |> Chainex.Chain.llm(:mock, response: ~s({"name": "Alice", "age": 25}))
    |> Chainex.Chain.parse(:json, schema: user_schema)
    
    {:ok, result} = Chainex.Chain.run(chain, %{input: "test"})
    
    assert result["name"] == "Alice"
    assert result["age"] == 25
  end
  
  test "handles parsing errors gracefully" do
    chain = Chainex.Chain.new("{{input}}")
    |> Chainex.Chain.llm(:mock, response: "Invalid JSON{")
    |> Chainex.Chain.parse(:json, on_error: :return_raw)
    
    {:ok, result} = Chainex.Chain.run(chain, %{input: "test"})
    assert result == "Invalid JSON{"
  end
end
```

## Best Practices

### 1. Schema Design

- Keep schemas as simple as possible while capturing necessary data
- Use descriptive field names that help the LLM understand what to extract
- Provide default values for optional fields
- Use arrays for collections of similar items

### 2. Error Handling

- Always handle parsing failures gracefully
- Provide fallback options (return raw text, retry with different model)
- Log parsing failures for debugging and schema improvement

### 3. Validation

- Validate critical fields with custom logic after parsing
- Use Elixir's pattern matching for robust data handling
- Consider using Ecto changesets for complex validation

### 4. Performance

- Cache parsing results for repeated operations  
- Use simpler models for basic parsing tasks
- Consider streaming for large documents