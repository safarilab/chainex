defmodule Chainex.Chain.Store.ETSTest do
  use ExUnit.Case, async: false

  alias Chainex.Chain.State
  alias Chainex.Chain.Store.ETS

  setup do
    ETS.clear()
    :ok
  end

  describe "ETS.ensure_table/0" do
    test "creates table if not exists" do
      assert :ok = ETS.ensure_table()
    end

    test "succeeds if table already exists" do
      ETS.ensure_table()
      assert :ok = ETS.ensure_table()
    end
  end

  describe "ETS.save/2" do
    test "saves state to ETS table" do
      state = State.new(%{topic: "AI"})

      assert :ok = ETS.save(state.instance_id, state)
    end

    test "overwrites existing state" do
      state1 = State.new(%{topic: "AI"})
      state2 = %{state1 | data: Map.put(state1.data, :updated, true)}

      :ok = ETS.save(state1.instance_id, state1)
      :ok = ETS.save(state1.instance_id, state2)

      {:ok, loaded} = ETS.load(state1.instance_id)
      assert loaded.data.updated == true
    end
  end

  describe "ETS.load/1" do
    test "loads state from ETS" do
      state = State.new(%{topic: "AI"})
      :ok = ETS.save(state.instance_id, state)

      assert {:ok, loaded} = ETS.load(state.instance_id)
      assert loaded.instance_id == state.instance_id
      assert loaded.data.topic == "AI"
    end

    test "returns error for missing state" do
      assert {:error, :not_found} = ETS.load("nonexistent_id")
    end
  end

  describe "ETS.delete/1" do
    test "removes state from ETS" do
      state = State.new()
      :ok = ETS.save(state.instance_id, state)

      assert :ok = ETS.delete(state.instance_id)
      assert {:error, :not_found} = ETS.load(state.instance_id)
    end

    test "succeeds for nonexistent state" do
      assert :ok = ETS.delete("nonexistent_id")
    end
  end

  describe "ETS.list/1" do
    test "lists all states" do
      state1 = State.new(%{topic: "AI"})
      state2 = State.new(%{topic: "ML"})
      :ok = ETS.save(state1.instance_id, state1)
      :ok = ETS.save(state2.instance_id, state2)

      {:ok, states} = ETS.list()

      assert length(states) == 2
      instance_ids = Enum.map(states, & &1.instance_id)
      assert state1.instance_id in instance_ids
      assert state2.instance_id in instance_ids
    end

    test "filters by session_id" do
      state1 = State.new(%{}, session_id: "user_123")
      state2 = State.new(%{}, session_id: "user_456")
      state3 = State.new(%{}, session_id: "user_123")
      :ok = ETS.save(state1.instance_id, state1)
      :ok = ETS.save(state2.instance_id, state2)
      :ok = ETS.save(state3.instance_id, state3)

      {:ok, states} = ETS.list(session_id: "user_123")

      assert length(states) == 2
      assert Enum.all?(states, &(&1.session_id == "user_123"))
    end

    test "filters by status" do
      state1 = State.new() |> State.start()
      state2 = State.new() |> State.start() |> State.pause()
      state3 = State.new() |> State.start()
      :ok = ETS.save(state1.instance_id, state1)
      :ok = ETS.save(state2.instance_id, state2)
      :ok = ETS.save(state3.instance_id, state3)

      {:ok, running_states} = ETS.list(status: :running)
      {:ok, paused_states} = ETS.list(status: :paused)

      assert length(running_states) == 2
      assert length(paused_states) == 1
      assert Enum.all?(running_states, &(&1.status == :running))
      assert Enum.all?(paused_states, &(&1.status == :paused))
    end

    test "returns empty list when no states" do
      {:ok, states} = ETS.list()
      assert states == []
    end
  end

  describe "ETS.update/2" do
    test "atomic read-modify-write" do
      state = State.new(%{count: 5})
      :ok = ETS.save(state.instance_id, state)

      {:ok, updated} =
        ETS.update(state.instance_id, fn s ->
          State.update(s, :count, &(&1 + 1))
        end)

      assert updated.data.count == 6

      {:ok, loaded} = ETS.load(state.instance_id)
      assert loaded.data.count == 6
    end

    test "returns error for missing state" do
      result =
        ETS.update("nonexistent", fn s ->
          State.put(s, :key, "value")
        end)

      assert {:error, :not_found} = result
    end
  end

  describe "ETS.exists?/1" do
    test "returns true for existing state" do
      state = State.new()
      :ok = ETS.save(state.instance_id, state)

      assert ETS.exists?(state.instance_id) == true
    end

    test "returns false for nonexistent state" do
      assert ETS.exists?("nonexistent_id") == false
    end
  end

  describe "ETS.clear/0" do
    test "clears all states" do
      state1 = State.new()
      state2 = State.new()
      :ok = ETS.save(state1.instance_id, state1)
      :ok = ETS.save(state2.instance_id, state2)

      assert ETS.count() == 2

      :ok = ETS.clear()

      assert ETS.count() == 0
      {:ok, states} = ETS.list()
      assert states == []
    end
  end

  describe "ETS.count/0" do
    test "returns count of stored states" do
      assert ETS.count() == 0

      state1 = State.new()
      state2 = State.new()
      :ok = ETS.save(state1.instance_id, state1)

      assert ETS.count() == 1

      :ok = ETS.save(state2.instance_id, state2)

      assert ETS.count() == 2
    end
  end

  describe "ETS.list_by_status/1" do
    test "returns states with specified status" do
      state1 = State.new() |> State.start()
      state2 = State.new() |> State.start() |> State.complete("done")
      :ok = ETS.save(state1.instance_id, state1)
      :ok = ETS.save(state2.instance_id, state2)

      {:ok, running} = ETS.list_by_status(:running)
      {:ok, completed} = ETS.list_by_status(:completed)

      assert length(running) == 1
      assert length(completed) == 1
    end
  end

  describe "ETS.list_by_session/1" do
    test "returns states for specified session" do
      state1 = State.new(%{}, session_id: "session_a")
      state2 = State.new(%{}, session_id: "session_b")
      :ok = ETS.save(state1.instance_id, state1)
      :ok = ETS.save(state2.instance_id, state2)

      {:ok, session_a_states} = ETS.list_by_session("session_a")

      assert length(session_a_states) == 1
      assert hd(session_a_states).session_id == "session_a"
    end
  end

  describe "ETS.running/0" do
    test "returns all running states" do
      state1 = State.new() |> State.start()
      state2 = State.new() |> State.start() |> State.pause()
      :ok = ETS.save(state1.instance_id, state1)
      :ok = ETS.save(state2.instance_id, state2)

      {:ok, running} = ETS.running()

      assert length(running) == 1
      assert hd(running).status == :running
    end
  end

  describe "ETS.paused/0" do
    test "returns all paused states" do
      state1 = State.new() |> State.start()
      state2 = State.new() |> State.start() |> State.pause()
      :ok = ETS.save(state1.instance_id, state1)
      :ok = ETS.save(state2.instance_id, state2)

      {:ok, paused} = ETS.paused()

      assert length(paused) == 1
      assert hd(paused).status == :paused
    end
  end
end
