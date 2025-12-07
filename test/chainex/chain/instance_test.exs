defmodule Chainex.Chain.InstanceTest do
  use ExUnit.Case, async: false

  alias Chainex.Chain
  alias Chainex.Chain.Instance
  alias Chainex.Chain.State
  alias Chainex.Chain.Store.ETS

  setup do
    # Clear ETS store
    ETS.clear()

    # Start registry under the test supervisor so it's properly isolated
    start_supervised!({Registry, keys: :unique, name: Chainex.Chain.Instance.Registry})

    :ok
  end

  describe "Instance.start/2" do
    test "returns instance_id on success" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ -> "World" end)

      assert {:ok, instance_id} = Instance.start(chain, %{})
      assert is_binary(instance_id)
      assert String.starts_with?(instance_id, "chain_")

      # Allow some time for async execution
      Process.sleep(50)
    end

    test "creates state with initial variables" do
      chain =
        Chain.new("Topic: {{topic}}")
        |> Chain.transform(&String.upcase/1)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{topic: "AI"})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.data.topic == "AI"
    end

    test "passes session_id to state" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ -> "Done" end)
        |> Chain.with_session("user_123")
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.session_id == "user_123"
    end
  end

  describe "Instance.get_state/1" do
    test "returns current state for running instance" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ ->
          Process.sleep(200)
          "Done"
        end)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(50)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.status == :running
    end

    test "returns completed state after execution" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ -> "World" end)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.status == :completed
    end

    test "loads from store for completed instances" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ -> "World" end)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      # State should be loadable from store even if process is stopped
      {:ok, state} = Instance.get_state(instance_id)
      assert state.instance_id == instance_id
    end
  end

  describe "Instance.pause/1" do
    test "pauses running instance" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ ->
          Process.sleep(500)
          "Done"
        end)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(50)

      assert :ok = Instance.pause(instance_id)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.status == :paused
    end

    test "returns error for nonexistent instance" do
      assert {:error, :not_found} = Instance.pause("nonexistent")
    end
  end

  describe "Instance.resume/2" do
    test "resumes paused instance" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ ->
          Process.sleep(100)
          "Step 1"
        end)
        |> Chain.transform(fn _ -> "Step 2" end)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(50)

      :ok = Instance.pause(instance_id)
      {:ok, state} = Instance.get_state(instance_id)
      assert state.status == :paused

      {:ok, result, final_state} = Instance.resume(instance_id, %{})
      assert final_state.status == :completed
    end

    test "merges new variables on resume" do
      chain =
        Chain.new("Hello")
        |> Chain.await(:user_input)
        |> Chain.store_as(:input)
        |> Chain.transform(fn _ -> "Done" end)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.status == :paused

      {:ok, _result, final_state} = Instance.resume(instance_id, %{user_input: "My input"})
      assert final_state.data.user_input == "My input"
    end
  end

  describe "Instance.stop/1" do
    test "stops running instance" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ ->
          Process.sleep(1000)
          "Done"
        end)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(50)

      assert :ok = Instance.stop(instance_id)
    end

    test "succeeds for nonexistent instance" do
      assert :ok = Instance.stop("nonexistent")
    end
  end

  describe "await/resume workflow" do
    test "pauses at await and resumes with input" do
      chain =
        Chain.new("Generate")
        |> Chain.transform(fn _ -> "Draft content" end)
        |> Chain.store_as(:draft)
        |> Chain.await(:feedback)
        |> Chain.transform(fn _ -> "Final content" end)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      # Should be paused at await
      {:ok, state} = Instance.get_state(instance_id)
      assert state.status == :paused
      assert state.data.draft == "Draft content"

      # Resume with feedback
      {:ok, result, final_state} = Instance.resume(instance_id, %{feedback: "Looks good!"})
      assert final_state.status == :completed
      assert final_state.data.feedback == "Looks good!"
    end
  end

  describe "state persistence" do
    test "persists state to ETS between steps" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ -> "Step 1" end)
        |> Chain.store_as(:step1)
        |> Chain.transform(fn _ -> "Step 2" end)
        |> Chain.store_as(:step2)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = ETS.load(instance_id)
      assert state.data.step1 == "Step 1"
      assert state.data.step2 == "Step 2"
    end

    test "persists paused state" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ -> "Draft" end)
        |> Chain.await(:approval)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = ETS.load(instance_id)
      assert state.status == :paused
    end

    test "persists failed state" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ -> raise "Test error" end)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = ETS.load(instance_id)
      assert state.status == :failed
      assert state.error != nil
    end
  end

  describe "step execution" do
    test "executes store_as step" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ -> "Result" end)
        |> Chain.store_as(:my_result)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.data.my_result == "Result"
    end

    test "executes get step" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ -> "First" end)
        |> Chain.store_as(:saved)
        |> Chain.transform(fn _ -> "Second" end)
        |> Chain.get(:saved)
        |> Chain.store_as(:retrieved)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.data.retrieved == "First"
    end

    test "executes update step" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ -> 5 end)
        |> Chain.store_as(:count)
        |> Chain.update(:count, fn c -> c * 2 end)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.data.count == 10
    end
  end

  describe "error handling" do
    test "captures errors and marks state as failed" do
      chain =
        Chain.new("Hello")
        |> Chain.transform(fn _ -> raise "Intentional error" end)
        |> Chain.persist_to(:ets)

      {:ok, instance_id} = Instance.start(chain, %{})
      Process.sleep(100)

      {:ok, state} = Instance.get_state(instance_id)
      assert state.status == :failed
      assert state.error != nil
    end
  end
end
