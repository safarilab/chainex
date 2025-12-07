defmodule Chainex.ChainWorkflowTest do
  use ExUnit.Case, async: true

  alias Chainex.Chain

  describe "Chain.store_as/2" do
    test "adds store_as step to chain" do
      chain =
        Chain.new("Hello")
        |> Chain.store_as(:greeting)

      assert length(chain.steps) == 1
      assert {:store_as, :greeting, []} = hd(chain.steps)
    end

    test "appends to existing steps" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(&String.upcase/1)
        |> Chain.store_as(:result)

      assert length(chain.steps) == 2
      assert {:store_as, :result, []} = List.last(chain.steps)
    end
  end

  describe "Chain.get/2" do
    test "adds get step to chain" do
      chain =
        Chain.new("Hello")
        |> Chain.get(:saved_value)

      assert length(chain.steps) == 1
      assert {:get, :saved_value, []} = hd(chain.steps)
    end
  end

  describe "Chain.update/3" do
    test "adds update step to chain" do
      update_fn = fn count -> count + 1 end

      chain =
        Chain.new("Hello")
        |> Chain.update(:counter, update_fn)

      assert length(chain.steps) == 1
      assert {:update, :counter, opts} = hd(chain.steps)
      assert Keyword.get(opts, :update_fn) == update_fn
    end
  end

  describe "Chain.persist_to/2" do
    test "sets persist_to field for :ets" do
      chain =
        Chain.new("Hello")
        |> Chain.persist_to(:ets)

      assert chain.persist_to == :ets
    end

    test "sets persist_to field for :database" do
      chain =
        Chain.new("Hello")
        |> Chain.persist_to(:database)

      assert chain.persist_to == :database
    end

    test "sets persist_to field for custom module" do
      chain =
        Chain.new("Hello")
        |> Chain.persist_to(MyCustomStore)

      assert chain.persist_to == MyCustomStore
    end
  end

  describe "Chain.condition/3" do
    test "adds when step with condition function" do
      condition_fn = fn result -> result.urgent? end
      branch_chain = Chain.new("urgent")

      chain =
        Chain.new("Hello")
        |> Chain.condition(condition_fn, branch_chain)

      assert length(chain.steps) == 1
      assert {:when, ^condition_fn, opts} = hd(chain.steps)
      assert Keyword.get(opts, :chain_or_builder) == branch_chain
    end

    test "adds when step with builder function" do
      condition_fn = fn _ -> true end
      builder_fn = fn c -> Chain.transform(c, &String.upcase/1) end

      chain =
        Chain.new("Hello")
        |> Chain.condition(condition_fn, builder_fn)

      assert length(chain.steps) == 1
      assert {:when, ^condition_fn, opts} = hd(chain.steps)
      assert is_function(Keyword.get(opts, :chain_or_builder))
    end

    test "allows multiple conditions" do
      chain =
        Chain.new("Hello")
        |> Chain.condition(&(&1.type == "a"), Chain.new("A"))
        |> Chain.condition(&(&1.type == "b"), Chain.new("B"))
        |> Chain.condition(&(&1.type == "c"), Chain.new("C"))

      assert length(chain.steps) == 3
      assert Enum.all?(chain.steps, fn {type, _, _} -> type == :when end)
    end
  end

  describe "Chain.otherwise/2" do
    test "adds otherwise step with chain" do
      fallback_chain = Chain.new("default")

      chain =
        Chain.new("Hello")
        |> Chain.condition(&(&1.urgent?), Chain.new("urgent"))
        |> Chain.otherwise(fallback_chain)

      assert length(chain.steps) == 2
      assert {:otherwise, ^fallback_chain, []} = List.last(chain.steps)
    end

    test "adds otherwise step with pass-through function" do
      pass_through = &(&1)

      chain =
        Chain.new("Hello")
        |> Chain.condition(&(&1.special?), Chain.new("special"))
        |> Chain.otherwise(pass_through)

      assert length(chain.steps) == 2
      assert {:otherwise, ^pass_through, []} = List.last(chain.steps)
    end
  end

  describe "Chain.loop/4" do
    test "adds loop step with condition and body" do
      condition = fn result, _state -> result.score < 0.8 end
      body_builder = fn c -> Chain.transform(c, &improve/1) end

      chain =
        Chain.new("Hello")
        |> Chain.loop(condition, body_builder)

      assert length(chain.steps) == 1
      assert {:loop, ^condition, opts} = hd(chain.steps)
      assert Keyword.get(opts, :body_builder) == body_builder
    end

    test "accepts max_iterations option" do
      condition = fn _, _ -> true end
      body_builder = fn c -> c end

      chain =
        Chain.new("Hello")
        |> Chain.loop(condition, body_builder, max_iterations: 5)

      assert {:loop, _, opts} = hd(chain.steps)
      assert Keyword.get(opts, :max_iterations) == 5
    end

    test "default max_iterations is not set in chain step" do
      condition = fn _, _ -> false end
      body_builder = fn c -> c end

      chain =
        Chain.new("Hello")
        |> Chain.loop(condition, body_builder)

      assert {:loop, _, opts} = hd(chain.steps)
      # Default is handled by Instance, not set in step
      assert Keyword.get(opts, :max_iterations) == nil
    end
  end

  describe "Chain.await/2" do
    test "adds await step with key" do
      chain =
        Chain.new("Hello")
        |> Chain.await(:human_review)

      assert length(chain.steps) == 1
      assert {:await, :human_review, []} = hd(chain.steps)
    end

    test "can chain multiple awaits" do
      chain =
        Chain.new("Hello")
        |> Chain.await(:first_review)
        |> Chain.await(:second_review)

      assert length(chain.steps) == 2
      assert {:await, :first_review, []} = Enum.at(chain.steps, 0)
      assert {:await, :second_review, []} = Enum.at(chain.steps, 1)
    end
  end

  describe "Chain.parallel/2" do
    test "adds parallel step with builder functions" do
      branch1 = fn c -> Chain.transform(c, &String.upcase/1) end
      branch2 = fn c -> Chain.transform(c, &String.downcase/1) end

      chain =
        Chain.new("Hello")
        |> Chain.parallel([branch1, branch2])

      assert length(chain.steps) == 1
      assert {:parallel, builders, []} = hd(chain.steps)
      assert length(builders) == 2
      assert branch1 in builders
      assert branch2 in builders
    end

    test "accepts empty list" do
      chain =
        Chain.new("Hello")
        |> Chain.parallel([])

      assert {:parallel, [], []} = hd(chain.steps)
    end
  end

  describe "Chain.execute_tools/1" do
    test "adds execute_tools step" do
      chain =
        Chain.new("Hello")
        |> Chain.execute_tools()

      assert length(chain.steps) == 1
      assert {:execute_tools, nil, []} = hd(chain.steps)
    end
  end

  describe "Chain.with_session/2" do
    test "sets session_id in options" do
      chain =
        Chain.new("Hello")
        |> Chain.with_session("user_123")

      assert Keyword.get(chain.options, :session_id) == "user_123"
    end
  end

  describe "combined workflow chain" do
    test "builds complex workflow chain" do
      chain =
        Chain.new("Research {{topic}}")
        |> Chain.store_as(:research)
        |> Chain.condition(&(&1.needs_review?), fn c ->
          c |> Chain.await(:approval)
        end)
        |> Chain.otherwise(&(&1))
        |> Chain.loop(
          fn result, _ -> result.iteration < 3 end,
          fn c -> Chain.transform(c, &refine/1) end,
          max_iterations: 5
        )
        |> Chain.store_as(:final)
        |> Chain.persist_to(:ets)
        |> Chain.with_session("user_123")

      # Verify structure
      assert length(chain.steps) == 5
      assert chain.persist_to == :ets
      assert Keyword.get(chain.options, :session_id) == "user_123"

      # Verify steps
      assert {:store_as, :research, []} = Enum.at(chain.steps, 0)
      assert {:when, _, _} = Enum.at(chain.steps, 1)
      assert {:otherwise, _, []} = Enum.at(chain.steps, 2)
      assert {:loop, _, _} = Enum.at(chain.steps, 3)
      assert {:store_as, :final, []} = Enum.at(chain.steps, 4)
    end
  end

  # Helper functions for tests
  defp improve(value), do: %{value | improved: true}
  defp refine(value), do: %{value | iteration: (value.iteration || 0) + 1}
end
