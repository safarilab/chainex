defmodule Chainex.PromptTest do
  use ExUnit.Case, async: true
  alias Chainex.Prompt
  doctest Chainex.Prompt

  describe "new/3" do
    test "creates prompt with default options" do
      prompt = Prompt.new("Hello {{name}}!")

      assert prompt.template == "Hello {{name}}!"
      assert prompt.variables == %{}
      assert prompt.options.format == :mustache
      assert prompt.options.strict == false
    end

    test "creates prompt with variables" do
      variables = %{name: "Alice", age: 25}
      prompt = Prompt.new("Hello {{name}}!", variables)

      assert prompt.variables == variables
    end

    test "creates prompt with custom options" do
      options = %{format: :python, strict: true}
      prompt = Prompt.new("Hello {name}!", %{}, options)

      assert prompt.options.format == :python
      assert prompt.options.strict == true
    end

    test "handles keyword list variables" do
      variables = [name: "Bob", city: "NYC"]
      prompt = Prompt.new("{{name}} from {{city}}", variables)

      assert prompt.variables == %{name: "Bob", city: "NYC"}
    end
  end

  describe "render/2 with mustache templates" do
    test "renders simple variable substitution" do
      prompt = Prompt.new("Hello {{name}}!")
      
      assert {:ok, "Hello Alice!"} = Prompt.render(prompt, %{name: "Alice"})
    end

    test "renders multiple variables" do
      template = "{{name}} is {{age}} years old"
      prompt = Prompt.new(template)
      variables = %{name: "Bob", age: 30}

      assert {:ok, "Bob is 30 years old"} = Prompt.render(prompt, variables)
    end

    test "renders nested object access" do
      template = "User: {{user.name}} ({{user.email}})"
      prompt = Prompt.new(template)
      variables = %{
        user: %{
          name: "Charlie",
          email: "charlie@example.com"
        }
      }

      assert {:ok, "User: Charlie (charlie@example.com)"} = Prompt.render(prompt, variables)
    end

    test "handles string keys for nested access" do
      template = "{{user.name}} works at {{user.company}}"
      prompt = Prompt.new(template)
      variables = %{
        "user" => %{
          "name" => "David",
          "company" => "TechCorp"
        }
      }

      assert {:ok, "David works at TechCorp"} = Prompt.render(prompt, variables)
    end

    test "handles missing variables in non-strict mode" do
      prompt = Prompt.new("Hello {{name}}, welcome {{missing}}!")
      
      assert {:ok, "Hello Alice, welcome !"} = Prompt.render(prompt, %{name: "Alice"})
    end

    test "returns error for missing variables in strict mode" do
      options = %{strict: true}
      prompt = Prompt.new("Hello {{missing}}!", %{}, options)
      
      assert {:error, {:missing_variable, "missing"}} = Prompt.render(prompt, %{})
    end

    test "handles different data types" do
      template = "String: {{str}}, Number: {{num}}, Boolean: {{bool}}, Atom: {{atom}}"
      prompt = Prompt.new(template)
      variables = %{
        str: "text",
        num: 42,
        bool: true,
        atom: :value
      }

      expected = "String: text, Number: 42, Boolean: true, Atom: value"
      assert {:ok, ^expected} = Prompt.render(prompt, variables)
    end

    test "uses pre-loaded variables from prompt" do
      prompt = Prompt.new("{{greeting}} {{name}}!", %{greeting: "Hello"})
      
      assert {:ok, "Hello Alice!"} = Prompt.render(prompt, %{name: "Alice"})
    end

    test "merges variables with render-time taking precedence" do
      prompt = Prompt.new("{{name}} is {{age}}", %{name: "Original", age: 25})
      
      assert {:ok, "Updated is 25"} = Prompt.render(prompt, %{name: "Updated"})
    end
  end

  describe "render/2 with python templates" do
    test "renders python-style templates" do
      options = %{format: :python}
      prompt = Prompt.new("Hello {name}!", %{}, options)
      
      assert {:ok, "Hello Python!"} = Prompt.render(prompt, %{name: "Python"})
    end

    test "renders nested access with python style" do
      options = %{format: :python}
      template = "User {user.name} has {user.points} points"
      prompt = Prompt.new(template, %{}, options)
      variables = %{
        user: %{
          name: "Eve",
          points: 100
        }
      }

      assert {:ok, "User Eve has 100 points"} = Prompt.render(prompt, variables)
    end
  end

  describe "render!/2" do
    test "returns result directly on success" do
      prompt = Prompt.new("Hello {{name}}!")
      
      assert "Hello World!" == Prompt.render!(prompt, %{name: "World"})
    end

    test "raises on error" do
      options = %{strict: true}
      prompt = Prompt.new("Hello {{missing}}!", %{}, options)
      
      assert_raise ArgumentError, fn ->
        Prompt.render!(prompt, %{})
      end
    end
  end

  describe "validate/1" do
    test "returns :ok for valid mustache templates" do
      prompt = Prompt.new("Hello {{name}}! You are {{age}} years old.")
      assert :ok = Prompt.validate(prompt)

      prompt = Prompt.new("{{user.name}} works at {{user.company}}")
      assert :ok = Prompt.validate(prompt)
    end

    test "returns :ok for valid python templates" do
      prompt = Prompt.new("Hello {name}!", %{}, %{format: :python})
      assert :ok = Prompt.validate(prompt)

      prompt = Prompt.new("{user.name} has {user.points} points", %{}, %{format: :python})
      assert :ok = Prompt.validate(prompt)
    end

    test "catches unclosed mustache tags" do
      prompt = Prompt.new("Hello {{name")
      assert {:error, {:invalid_syntax, "Unclosed template tag at position 6"}} = Prompt.validate(prompt)

      prompt = Prompt.new("Hello {{name}} and {{age")
      assert {:error, {:invalid_syntax, "Unclosed template tag at position " <> _}} = Prompt.validate(prompt)
    end

    test "catches unclosed python tags" do
      prompt = Prompt.new("Hello {name", %{}, %{format: :python})
      assert {:error, {:invalid_syntax, "Unclosed template tag at position 6"}} = Prompt.validate(prompt)
    end

    test "catches unopened closing tags" do
      prompt = Prompt.new("Hello name}} world")
      assert {:error, {:invalid_syntax, "Unopened template tag at position " <> _}} = Prompt.validate(prompt)

      prompt = Prompt.new("Hello name} world", %{}, %{format: :python})
      assert {:error, {:invalid_syntax, "Unopened template tag at position " <> _}} = Prompt.validate(prompt)
    end

    test "catches empty variable names" do
      prompt = Prompt.new("Hello {{}}!")
      assert {:error, {:invalid_syntax, "Empty variable name"}} = Prompt.validate(prompt)

      prompt = Prompt.new("Hello {{  }}!")
      assert {:error, {:invalid_syntax, "Empty variable name"}} = Prompt.validate(prompt)
    end

    test "catches invalid variable names" do
      # Variable names starting with dots
      prompt = Prompt.new("Hello {{.invalid}}!")
      assert {:error, {:invalid_syntax, "Invalid variable name '.invalid'"}} = Prompt.validate(prompt)

      # Variable names ending with dots
      prompt = Prompt.new("Hello {{invalid.}}!")
      assert {:error, {:invalid_syntax, "Invalid variable name 'invalid.'"}} = Prompt.validate(prompt)

      # Variable names with consecutive dots
      prompt = Prompt.new("Hello {{user..name}}!")
      assert {:error, {:invalid_syntax, "Invalid variable name 'user..name'"}} = Prompt.validate(prompt)

      # Variable names with invalid characters
      prompt = Prompt.new("Hello {{user-name}}!")
      assert {:error, {:invalid_syntax, "Invalid variable name 'user-name'"}} = Prompt.validate(prompt)

      prompt = Prompt.new("Hello {{user@domain}}!")
      assert {:error, {:invalid_syntax, "Invalid variable name 'user@domain'"}} = Prompt.validate(prompt)
    end

    test "allows valid nested variable names" do
      prompt = Prompt.new("Hello {{user.profile.name}}!")
      assert :ok = Prompt.validate(prompt)

      prompt = Prompt.new("Hello {{_private.data_2.value_3}}!")
      assert :ok = Prompt.validate(prompt)
    end

    test "validates multiple issues" do
      # Template with both unclosed tag and invalid variable
      prompt = Prompt.new("Hello {{name}} and {{.invalid")
      # Should catch the first error (unclosed tag)
      assert {:error, {:invalid_syntax, _}} = Prompt.validate(prompt)
    end

    test "handles complex valid templates" do
      template = """
      Welcome {{user.name}}!
      Your account balance is {{account.balance}}.
      You have {{notifications.count}} new notifications.
      Last login: {{user.last_login}}.
      """
      
      prompt = Prompt.new(template)
      assert :ok = Prompt.validate(prompt)
    end

    test "validates python format correctly" do
      prompt = Prompt.new("Hello {user.name} from {user.location}", %{}, %{format: :python})
      assert :ok = Prompt.validate(prompt)

      prompt = Prompt.new("Hello {.invalid}", %{}, %{format: :python})
      assert {:error, {:invalid_syntax, "Invalid variable name '.invalid'"}} = Prompt.validate(prompt)
    end
  end

  describe "variables/1" do
    test "extracts all variables from template" do
      template = "Hello {{name}}, you are {{age}} years old and live in {{city}}!"
      prompt = Prompt.new(template)
      
      variables = Prompt.variables(prompt)
      assert length(variables) == 3
      assert "name" in variables
      assert "age" in variables
      assert "city" in variables
    end

    test "extracts nested variables" do
      template = "User {{user.name}} ({{user.email}}) from {{user.address.city}}"
      prompt = Prompt.new(template)
      
      variables = Prompt.variables(prompt)
      assert "user.name" in variables
      assert "user.email" in variables
      assert "user.address.city" in variables
    end

    test "returns unique variables only" do
      template = "{{name}} {{name}} {{age}} {{name}}"
      prompt = Prompt.new(template)
      
      variables = Prompt.variables(prompt)
      assert length(variables) == 2
      assert "name" in variables
      assert "age" in variables
    end

    test "handles python format variables" do
      options = %{format: :python}
      template = "Hello {name}, you are {age} years old"
      prompt = Prompt.new(template, %{}, options)
      
      variables = Prompt.variables(prompt)
      assert "name" in variables
      assert "age" in variables
    end
  end

  describe "compile/2" do
    test "creates reusable template function" do
      compiled = Prompt.compile("Hello {{name}}!")
      
      assert "Hello Alice!" == compiled.(%{name: "Alice"})
      assert "Hello Bob!" == compiled.(%{name: "Bob"})
    end

    test "compiled function raises on missing variables in strict mode" do
      compiled = Prompt.compile("Hello {{name}}!", %{strict: true})
      
      assert_raise ArgumentError, fn ->
        compiled.(%{})
      end
    end

    test "works with python format" do
      compiled = Prompt.compile("Hello {name}!", %{format: :python})
      
      assert "Hello Python!" == compiled.(%{name: "Python"})
    end
  end

  describe "formatting options" do
    test "trims whitespace by default" do
      prompt = Prompt.new("  Hello {{name}}!  ")
      
      assert {:ok, "Hello Alice!"} = Prompt.render(prompt, %{name: "Alice"})
    end

    test "preserves whitespace when disabled" do
      options = %{trim_whitespace: false}
      prompt = Prompt.new("  Hello {{name}}!  ", %{}, options)
      
      assert {:ok, "  Hello Alice!  "} = Prompt.render(prompt, %{name: "Alice"})
    end

    test "escapes HTML when enabled" do
      options = %{escape_html: true}
      prompt = Prompt.new("Content: {{content}}", %{}, options)
      
      variables = %{content: "<script>alert('xss')</script>"}
      expected = "Content: &lt;script&gt;alert(&#x27;xss&#x27;)&lt;/script&gt;"
      
      assert {:ok, ^expected} = Prompt.render(prompt, variables)
    end

    test "does not escape HTML by default" do
      prompt = Prompt.new("Content: {{content}}")
      
      variables = %{content: "<b>bold</b>"}
      assert {:ok, "Content: <b>bold</b>"} = Prompt.render(prompt, variables)
    end
  end

  describe "edge cases and error handling" do
    test "handles empty template" do
      prompt = Prompt.new("")
      
      assert {:ok, ""} = Prompt.render(prompt, %{name: "Alice"})
    end

    test "handles template with no variables" do
      prompt = Prompt.new("Static text only")
      
      assert {:ok, "Static text only"} = Prompt.render(prompt, %{unused: "value"})
    end

    test "handles nil values" do
      prompt = Prompt.new("Value: {{value}}")
      
      assert {:ok, "Value:"} = Prompt.render(prompt, %{value: nil})
    end

    test "handles complex nested structures" do
      template = "{{data.user.profile.name}} has {{data.stats.points}} points"
      prompt = Prompt.new(template)
      
      variables = %{
        data: %{
          user: %{
            profile: %{name: "DeepNest"}
          },
          stats: %{points: 500}
        }
      }
      
      assert {:ok, "DeepNest has 500 points"} = Prompt.render(prompt, variables)
    end

    test "handles lists and maps in variables" do
      template = "Items: {{items}}, Config: {{config}}"
      prompt = Prompt.new(template)
      
      variables = %{
        items: [1, 2, 3],
        config: %{debug: true, timeout: 30}
      }
      
      {:ok, result} = Prompt.render(prompt, variables)
      assert String.contains?(result, "Items: [1, 2, 3]")
      assert String.contains?(result, "Config:")
    end

    test "template is immutable" do
      original = Prompt.new("Hello {{name}}!", %{name: "Original"})
      
      {:ok, _result} = Prompt.render(original, %{name: "Updated"})
      
      # Original should be unchanged
      assert original.variables.name == "Original"
    end

    test "performance with multiple templates" do
      # Test with multiple separate templates instead of one large one
      templates = [
        "Hello {{name}}!",
        "Age: {{age}}",
        "City: {{city}}",
        "Status: {{status}}"
      ]
      
      variables = %{
        name: "Alice",
        age: 25,
        city: "NYC", 
        status: "active"
      }
      
      # Should render all templates without issues
      results = Enum.map(templates, fn template ->
        prompt = Prompt.new(template)
        {:ok, result} = Prompt.render(prompt, variables)
        result
      end)
      
      assert Enum.at(results, 0) == "Hello Alice!"
      assert Enum.at(results, 1) == "Age: 25"
      assert Enum.at(results, 2) == "City: NYC"
      assert Enum.at(results, 3) == "Status: active"
    end
  end

  describe "integration with other modules" do
    test "works with context variables" do
      # Simulate using with Chainex.Context
      context_vars = %{
        user: %{name: "Integration", role: "admin"},
        session: %{id: "sess_123", expires: "2024-12-31"}
      }
      
      template = "Welcome {{user.name}} ({{user.role}})! Session: {{session.id}}"
      prompt = Prompt.new(template)
      
      {:ok, result} = Prompt.render(prompt, context_vars)
      assert result == "Welcome Integration (admin)! Session: sess_123"
    end
  end
end