defmodule Chainex.Chain.StateTest do
  use ExUnit.Case, async: true

  alias Chainex.Chain.State

  describe "State.new/2" do
    test "creates state with default values" do
      state = State.new()

      assert state.status == :pending
      assert state.current_step == 0
      assert state.data == %{}
      assert state.step_results == []
      assert is_binary(state.instance_id)
      assert String.starts_with?(state.instance_id, "chain_")
      assert state.session_id == nil
      assert state.started_at == nil
      assert state.error == nil
    end

    test "creates state with initial data" do
      state = State.new(%{topic: "AI", count: 5})

      assert state.data.topic == "AI"
      assert state.data.count == 5
      assert state.status == :pending
    end

    test "creates state with session_id option" do
      state = State.new(%{}, session_id: "user_123")

      assert state.session_id == "user_123"
    end

    test "generates unique instance_ids" do
      state1 = State.new()
      state2 = State.new()

      assert state1.instance_id != state2.instance_id
    end
  end

  describe "State.start/1" do
    test "marks state as running" do
      state = State.new() |> State.start()

      assert state.status == :running
      assert state.started_at != nil
      assert state.updated_at != nil
    end

    test "sets timestamps" do
      state = State.new() |> State.start()

      assert %DateTime{} = state.started_at
      assert %DateTime{} = state.updated_at
    end
  end

  describe "State.put/3" do
    test "stores value in state data" do
      state = State.new() |> State.put(:key, "value")

      assert state.data.key == "value"
    end

    test "also sets _last_result" do
      state = State.new() |> State.put(:key, "value")

      assert state.data._last_result == "value"
    end

    test "updates updated_at timestamp" do
      state = State.new() |> State.put(:key, "value")

      assert state.updated_at != nil
    end

    test "overwrites existing values" do
      state =
        State.new()
        |> State.put(:key, "first")
        |> State.put(:key, "second")

      assert state.data.key == "second"
    end
  end

  describe "State.get/3" do
    test "retrieves value from state" do
      state = State.new(%{topic: "AI"})

      assert State.get(state, :topic) == "AI"
    end

    test "returns nil for missing keys" do
      state = State.new()

      assert State.get(state, :missing) == nil
    end

    test "returns default for missing keys" do
      state = State.new()

      assert State.get(state, :missing, "default") == "default"
    end
  end

  describe "State.update/3" do
    test "updates value using function" do
      state =
        State.new(%{count: 5})
        |> State.update(:count, fn count -> count + 1 end)

      assert state.data.count == 6
    end

    test "handles nil values in update" do
      state =
        State.new()
        |> State.update(:count, fn nil -> 1 end)

      assert state.data.count == 1
    end

    test "also updates _last_result" do
      state =
        State.new(%{count: 5})
        |> State.update(:count, fn count -> count * 2 end)

      assert state.data._last_result == 10
    end
  end

  describe "State.merge/2" do
    test "merges new data into state" do
      state =
        State.new(%{a: 1})
        |> State.merge(%{b: 2, c: 3})

      assert state.data.a == 1
      assert state.data.b == 2
      assert state.data.c == 3
    end

    test "overwrites existing keys" do
      state =
        State.new(%{a: 1})
        |> State.merge(%{a: 100})

      assert state.data.a == 100
    end
  end

  describe "State.record_step_result/2" do
    test "appends result to step_results" do
      state =
        State.new()
        |> State.record_step_result("result1")
        |> State.record_step_result("result2")

      assert state.step_results == ["result1", "result2"]
    end

    test "increments current_step" do
      state =
        State.new()
        |> State.record_step_result("result1")
        |> State.record_step_result("result2")

      assert state.current_step == 2
    end

    test "sets _last_result" do
      state =
        State.new()
        |> State.record_step_result("latest")

      assert state.data._last_result == "latest"
    end
  end

  describe "State.pause/1" do
    test "marks state as paused" do
      state =
        State.new()
        |> State.start()
        |> State.pause()

      assert state.status == :paused
    end

    test "updates timestamp" do
      state =
        State.new()
        |> State.start()

      original_time = state.updated_at
      Process.sleep(1)

      paused_state = State.pause(state)

      assert paused_state.updated_at != original_time
    end
  end

  describe "State.resume/2" do
    test "marks state as running" do
      state =
        State.new()
        |> State.start()
        |> State.pause()
        |> State.resume()

      assert state.status == :running
    end

    test "merges new variables" do
      state =
        State.new(%{a: 1})
        |> State.start()
        |> State.pause()
        |> State.resume(%{b: 2})

      assert state.data.a == 1
      assert state.data.b == 2
    end
  end

  describe "State.complete/2" do
    test "marks state as completed" do
      state =
        State.new()
        |> State.start()
        |> State.complete("final result")

      assert state.status == :completed
    end

    test "sets completed_at timestamp" do
      state =
        State.new()
        |> State.start()
        |> State.complete("final result")

      assert state.completed_at != nil
    end

    test "stores final result in _last_result" do
      state =
        State.new()
        |> State.start()
        |> State.complete("final result")

      assert state.data._last_result == "final result"
    end
  end

  describe "State.fail/2" do
    test "marks state as failed" do
      state =
        State.new()
        |> State.start()
        |> State.fail("something went wrong")

      assert state.status == :failed
    end

    test "stores error" do
      state =
        State.new()
        |> State.start()
        |> State.fail("something went wrong")

      assert state.error == "something went wrong"
    end

    test "sets completed_at timestamp" do
      state =
        State.new()
        |> State.start()
        |> State.fail("error")

      assert state.completed_at != nil
    end
  end

  describe "State.terminal?/1" do
    test "returns true for completed state" do
      state = State.new() |> State.start() |> State.complete("done")

      assert State.terminal?(state) == true
    end

    test "returns true for failed state" do
      state = State.new() |> State.start() |> State.fail("error")

      assert State.terminal?(state) == true
    end

    test "returns false for running state" do
      state = State.new() |> State.start()

      assert State.terminal?(state) == false
    end

    test "returns false for paused state" do
      state = State.new() |> State.start() |> State.pause()

      assert State.terminal?(state) == false
    end

    test "returns false for pending state" do
      state = State.new()

      assert State.terminal?(state) == false
    end
  end

  describe "State.paused?/1" do
    test "returns true for paused state" do
      state = State.new() |> State.start() |> State.pause()

      assert State.paused?(state) == true
    end

    test "returns false for running state" do
      state = State.new() |> State.start()

      assert State.paused?(state) == false
    end
  end

  describe "State.running?/1" do
    test "returns true for running state" do
      state = State.new() |> State.start()

      assert State.running?(state) == true
    end

    test "returns false for paused state" do
      state = State.new() |> State.start() |> State.pause()

      assert State.running?(state) == false
    end
  end

  describe "State.to_variables/1" do
    test "returns state data as map" do
      state = State.new(%{topic: "AI", count: 5})

      vars = State.to_variables(state)

      assert vars.topic == "AI"
      assert vars.count == 5
    end
  end
end
