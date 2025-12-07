defmodule Chainex.Integration.WorkflowTest do
  @moduledoc """
  Integration tests for workflow features.

  These tests verify end-to-end workflow scenarios using transforms
  instead of actual LLM calls for deterministic testing.
  """

  use ExUnit.Case, async: false

  alias Chainex.Chain
  alias Chainex.Chain.Instance
  alias Chainex.Chain.Store.ETS

  setup do
    ETS.clear()
    # Start registry under the test supervisor so it's properly isolated
    start_supervised!({Registry, keys: :unique, name: Chainex.Chain.Instance.Registry})
    :ok
  end

  describe "state flows through chain steps" do
    test "initial variables are accessible in state" do
      chain =
        Chain.new("Topic: {{topic}}")
        |> Chain.transform(fn input -> "Processed: #{input}" end)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{topic: "AI"})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.data.topic == "AI"
    end

    test "store_as stores step results in state" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ -> "Research result" end)
        |> Chain.store_as(:research)
        |> Chain.transform(fn _ -> "Summary result" end)
        |> Chain.store_as(:summary)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.data.research == "Research result"
      assert state.data.summary == "Summary result"
    end

    test "_last_result tracks the most recent step output" do
      chain =
        Chain.new("Start")
        |> Chain.transform(fn _ -> "First" end)
        |> Chain.transform(fn _ -> "Second" end)
        |> Chain.transform(fn _ -> "Third" end)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.data._last_result == "Third"
    end
  end

  describe "condition/otherwise branching" do
    test "executes branch when condition is true" do
      chain =
        Chain.new("Input")
        |> Chain.transform(fn _ -> %{type: "urgent"} end)
        |> Chain.condition(
          fn result -> result.type == "urgent" end,
          fn c -> Chain.transform(c, fn _ -> "Urgent handled" end) end
        )
        |> Chain.otherwise(fn c -> Chain.transform(c, fn _ -> "Normal handled" end) end)
        |> Chain.store_as(:result)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.data.result == "Urgent handled"
    end

    test "executes otherwise when condition is false" do
      chain =
        Chain.new("Input")
        |> Chain.transform(fn _ -> %{type: "normal"} end)
        |> Chain.condition(
          fn result -> result.type == "urgent" end,
          fn c -> Chain.transform(c, fn _ -> "Urgent handled" end) end
        )
        |> Chain.otherwise(fn c -> Chain.transform(c, fn _ -> "Normal handled" end) end)
        |> Chain.store_as(:result)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.data.result == "Normal handled"
    end

    test "pass-through otherwise preserves value" do
      chain =
        Chain.new("Input")
        |> Chain.transform(fn _ -> %{value: "original"} end)
        |> Chain.condition(
          fn _ -> false end,
          fn c -> Chain.transform(c, fn _ -> "modified" end) end
        )
        |> Chain.otherwise(&(&1))
        |> Chain.store_as(:result)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.data.result == %{value: "original"}
    end
  end

  describe "loop execution" do
    test "executes until condition is false" do
      chain =
        Chain.new("Start")
        |> Chain.transform(fn _ -> %{count: 0} end)
        |> Chain.store_as(:counter)
        |> Chain.loop(
          fn result, _ -> result.count < 3 end,
          fn c ->
            c |> Chain.transform(fn result -> %{count: result.count + 1} end)
          end,
          max_iterations: 10
        )
        |> Chain.store_as(:final_count)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(200)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.data.final_count.count == 3
    end

    test "respects max_iterations" do
      chain =
        Chain.new("Start")
        |> Chain.transform(fn _ -> %{count: 0} end)
        |> Chain.loop(
          fn _, _ -> true end,  # Always true - would loop forever
          fn c ->
            c |> Chain.transform(fn result -> %{count: result.count + 1} end)
          end,
          max_iterations: 5
        )
        |> Chain.store_as(:final_count)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(200)

      {:ok, state} = Instance.get_state(instance_id)
      # Should stop at 5 due to max_iterations
      assert state.data.final_count.count == 5
    end

    test "does not execute if condition is initially false" do
      chain =
        Chain.new("Start")
        |> Chain.transform(fn _ -> %{count: 10} end)
        |> Chain.loop(
          fn result, _ -> result.count < 5 end,
          fn c ->
            c |> Chain.transform(fn result -> %{count: result.count + 1} end)
          end
        )
        |> Chain.store_as(:final)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      # Should not have looped at all
      assert state.data.final.count == 10
    end
  end

  describe "await pauses execution" do
    test "pauses at await point" do
      chain =
        Chain.new("Start")
        |> Chain.transform(fn _ -> "Draft" end)
        |> Chain.store_as(:draft)
        |> Chain.await(:approval)
        |> Chain.transform(fn _ -> "Finalized" end)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.status == :paused
      assert state.data.draft == "Draft"
    end

    test "resume continues from await point with new data" do
      chain =
        Chain.new("Start")
        |> Chain.transform(fn _ -> "Draft" end)
        |> Chain.store_as(:draft)
        |> Chain.await(:feedback)
        |> Chain.transform(fn _ -> "Finalized" end)
        |> Chain.store_as(:final)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      # Should be paused
      {:ok, state} = Instance.get_state(instance_id)
      assert state.status == :paused

      # Resume with feedback
      {:ok, result, final_state} = Instance.resume(instance_id, %{feedback: "LGTM"})

      assert final_state.status == :completed
      assert final_state.data.feedback == "LGTM"
      assert final_state.data.final == "Finalized"
    end
  end

  describe "parallel execution" do
    test "executes branches concurrently and collects results" do
      chain =
        Chain.new("Input")
        |> Chain.transform(fn _ -> "Hello" end)
        |> Chain.parallel([
          fn c -> Chain.transform(c, &String.upcase/1) end,
          fn c -> Chain.transform(c, &String.downcase/1) end,
          fn c -> Chain.transform(c, &String.reverse/1) end
        ])
        |> Chain.store_as(:parallel_results)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(200)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.data.parallel_results == ["HELLO", "hello", "olleH"]
    end

    test "all branches receive the same input" do
      chain =
        Chain.new("Input")
        |> Chain.transform(fn _ -> "Test" end)
        |> Chain.parallel([
          fn c -> Chain.transform(c, fn input -> "Branch1: #{input}" end) end,
          fn c -> Chain.transform(c, fn input -> "Branch2: #{input}" end) end
        ])
        |> Chain.store_as(:results)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(150)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.data.results == ["Branch1: Test", "Branch2: Test"]
    end
  end

  describe "multi-step pipeline with state" do
    test "simulates multi-agent pipeline" do
      chain =
        Chain.new("Topic: {{topic}}")
        |> Chain.transform(fn input -> "Research on #{input}" end)
        |> Chain.store_as(:research)
        |> Chain.transform(fn _ -> "Written draft" end)
        |> Chain.store_as(:draft)
        |> Chain.transform(fn _ -> "Edited final" end)
        |> Chain.store_as(:final)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{topic: "AI"})
      Process.sleep(150)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.status == :completed
      assert state.data.topic == "AI"
      assert state.data.research =~ "Research on"
      assert state.data.draft == "Written draft"
      assert state.data.final == "Edited final"
    end
  end

  describe "session isolation" do
    test "states are isolated by session_id" do
      chain1 =
        Chain.new("Hello")
        |> Chain.transform(fn _ -> "User 1 data" end)
        |> Chain.store_as(:data)
        |> Chain.with_session("user_1")
        |> Chain.persist_to(:ets)

      chain2 =
        Chain.new("Hello")
        |> Chain.transform(fn _ -> "User 2 data" end)
        |> Chain.store_as(:data)
        |> Chain.with_session("user_2")
        |> Chain.persist_to(:ets)

      {:ok, instance1} = Instance.start(chain1, %{})
      {:ok, instance2} = Instance.start(chain2, %{})
      Process.sleep(100)

      {:ok, state1} = Instance.get_state(instance1)
      {:ok, state2} = Instance.get_state(instance2)

      assert state1.session_id == "user_1"
      assert state2.session_id == "user_2"
      assert state1.data.data == "User 1 data"
      assert state2.data.data == "User 2 data"

      # Can filter by session
      {:ok, user1_states} = ETS.list(session_id: "user_1")
      assert length(user1_states) == 1
      assert hd(user1_states).session_id == "user_1"
    end
  end

  describe "complex workflow scenarios" do
    test "human-in-the-loop approval workflow" do
      chain =
        Chain.new("Generate proposal")
        |> Chain.transform(fn _ -> %{content: "Draft proposal", quality: 0.6} end)
        |> Chain.store_as(:proposal)
        |> Chain.condition(
          fn result -> result.quality < 0.8 end,
          fn c -> c |> Chain.await(:revision_feedback) end
        )
        |> Chain.otherwise(&(&1))
        |> Chain.transform(fn _ -> "Final proposal" end)
        |> Chain.store_as(:final)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      # Should be paused for feedback since quality < 0.8
      {:ok, state} = Instance.get_state(instance_id)
      assert state.status == :paused

      # Resume with feedback
      {:ok, _, final_state} = Instance.resume(instance_id, %{revision_feedback: "Add more details"})
      assert final_state.status == :completed
      assert final_state.data.revision_feedback == "Add more details"
    end

    test "iterative refinement loop" do
      chain =
        Chain.new("Start")
        |> Chain.transform(fn _ -> %{score: 0.5, iterations: 0} end)
        |> Chain.loop(
          fn result, _ -> result.score < 0.8 end,
          fn c ->
            c
            |> Chain.transform(fn result ->
              %{
                score: result.score + 0.15,
                iterations: result.iterations + 1
              }
            end)
          end,
          max_iterations: 10
        )
        |> Chain.store_as(:refined)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(200)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.status == :completed
      # Should have iterated until score >= 0.8
      # 0.5 -> 0.65 -> 0.80 (2 iterations)
      assert state.data.refined.iterations == 2
      assert state.data.refined.score >= 0.8
    end
  end
end
