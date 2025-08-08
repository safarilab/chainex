defmodule Chainex.ChainTest do
  use ExUnit.Case
  doctest Chainex.Chain
  
  alias Chainex.Chain
  
  describe "Chain.new/1" do
    test "creates a chain with user message" do
      chain = Chain.new("Hello {{name}}")
      
      assert chain.user_prompt == "Hello {{name}}"
      assert chain.system_prompt == nil
      assert chain.steps == []
      assert chain.options == []
    end
    
    test "creates a chain with system and user prompts" do
      chain = Chain.new(
        system: "You are a helpful {{role}}",
        user: "Help me with {{task}}"
      )
      
      assert chain.system_prompt == "You are a helpful {{role}}"
      assert chain.user_prompt == "Help me with {{task}}"
      assert chain.steps == []
    end
    
    test "preserves additional options" do
      chain = Chain.new(
        system: "System prompt",
        user: "User prompt",
        temperature: 0.5,
        model: "gpt-4"
      )
      
      assert chain.system_prompt == "System prompt"
      assert chain.user_prompt == "User prompt"
      assert Keyword.get(chain.options, :temperature) == 0.5
      assert Keyword.get(chain.options, :model) == "gpt-4"
    end
  end
  
  describe "Chain building" do
    test "adds LLM step" do
      chain = Chain.new("Test")
      |> Chain.llm(:openai)
      
      assert [{:llm, :openai, []}] = chain.steps
    end
    
    test "adds LLM step with options" do
      chain = Chain.new("Test")
      |> Chain.llm(:anthropic, model: "claude-3", temperature: 0.8)
      
      assert [{:llm, :anthropic, opts}] = chain.steps
      assert Keyword.get(opts, :model) == "claude-3"
      assert Keyword.get(opts, :temperature) == 0.8
    end
    
    test "chains multiple steps" do
      chain = Chain.new("Test")
      |> Chain.llm(:openai)
      |> Chain.transform(&String.upcase/1)
      |> Chain.parse(:json)
      
      assert [
        {:llm, :openai, []},
        {:transform, _, []},
        {:parse, :json, []}
      ] = chain.steps
    end
    
    test "adds transform step" do
      transform_fn = fn x -> String.upcase(x) end
      
      chain = Chain.new("Test")
      |> Chain.transform(transform_fn)
      
      assert [{:transform, ^transform_fn, []}] = chain.steps
    end
    
    test "adds parse step with schema" do
      schema = %{name: :string, age: :integer}
      
      chain = Chain.new("Test")
      |> Chain.parse(:json, schema)
      
      assert [{:parse, :json, opts}] = chain.steps
      assert Keyword.get(opts, :schema) == schema
    end
    
    test "adds parse step for struct" do
      chain = Chain.new("Test")
      |> Chain.parse(:struct, MyModule)
      
      assert [{:parse, :struct, opts}] = chain.steps
      assert Keyword.get(opts, :schema) == MyModule
    end
  end
  
  describe "Chain configuration" do
    test "adds memory configuration" do
      chain = Chain.new("Test")
      |> Chain.with_memory(:conversation)
      
      assert Keyword.get(chain.options, :memory) == :conversation
    end
    
    test "adds tools" do
      tools = [:tool1, :tool2]
      
      chain = Chain.new("Test")
      |> Chain.with_tools(tools)
      
      assert Keyword.get(chain.options, :tools) == tools
    end
    
    test "adds required variables" do
      chain = Chain.new("Test {{var1}} {{var2}}")
      |> Chain.require_variables([:var1, :var2])
      
      assert Keyword.get(chain.options, :required_variables) == [:var1, :var2]
    end
    
    test "adds metadata" do
      chain = Chain.new("Test")
      |> Chain.with_metadata(%{user_id: "123", session: "abc"})
      
      metadata = Keyword.get(chain.options, :metadata)
      assert metadata.user_id == "123"
      assert metadata.session == "abc"
    end
    
    test "merges metadata" do
      chain = Chain.new("Test")
      |> Chain.with_metadata(%{user_id: "123"})
      |> Chain.with_metadata(%{session: "abc"})
      
      metadata = Keyword.get(chain.options, :metadata)
      assert metadata.user_id == "123"
      assert metadata.session == "abc"
    end
    
    test "adds session ID" do
      chain = Chain.new("Test")
      |> Chain.with_session("session_123")
      
      assert Keyword.get(chain.options, :session_id) == "session_123"
    end
  end
  
  describe "Chain execution with mock" do
    test "executes simple chain" do
      chain = Chain.new("Hello world")
      |> Chain.llm(:mock)
      
      assert {:ok, result} = Chain.run(chain)
      assert result == "Mock response for: Hello world"
    end
    
    test "executes chain with variables" do
      chain = Chain.new("Hello {{name}}")
      |> Chain.llm(:mock)
      
      assert {:ok, result} = Chain.run(chain, %{name: "Alice"})
      assert result == "Mock response for: Hello Alice"
    end
    
    test "executes chain with transform" do
      chain = Chain.new("hello")
      |> Chain.llm(:mock)
      |> Chain.transform(&String.upcase/1)
      
      assert {:ok, result} = Chain.run(chain)
      assert result == "MOCK RESPONSE FOR: HELLO"
    end
    
    test "executes chain with transform using variables" do
      chain = Chain.new("{{greeting}}")
      |> Chain.llm(:mock)
      |> Chain.transform(fn result, vars -> 
        "#{vars.greeting}: #{result}"
      end)
      
      assert {:ok, result} = Chain.run(chain, %{greeting: "Hello"})
      assert result == "Hello: Mock response for: Hello"
    end
    
    test "fails with missing required variables" do
      chain = Chain.new("Hello {{name}}")
      |> Chain.require_variables([:name, :age])
      |> Chain.llm(:mock)
      
      assert {:error, message} = Chain.run(chain, %{name: "Alice"})
      assert message =~ "Missing required variables"
      assert message =~ "age"
    end
    
    test "run! raises on error" do
      chain = Chain.new("Test")
      |> Chain.require_variables([:missing])
      |> Chain.llm(:mock)
      
      assert_raise RuntimeError, ~r/Chain execution failed/, fn ->
        Chain.run!(chain, %{})
      end
    end
  end
end