defmodule Chainex.Chain.StoreTest do
  use ExUnit.Case, async: false

  alias Chainex.Chain.State
  alias Chainex.Chain.Store
  alias Chainex.Chain.Store.ETS

  setup do
    ETS.clear()
    :ok
  end

  describe "Store.get_store/1" do
    test "returns ETS by default" do
      assert Store.get_store() == Chainex.Chain.Store.ETS
      assert Store.get_store([]) == Chainex.Chain.Store.ETS
    end

    test "returns ETS for :ets option" do
      assert Store.get_store(store: :ets) == Chainex.Chain.Store.ETS
      assert Store.get_store(persist_to: :ets) == Chainex.Chain.Store.ETS
    end

    test "returns Database for :database option" do
      assert Store.get_store(store: :database) == Chainex.Chain.Store.Database
      assert Store.get_store(persist_to: :database) == Chainex.Chain.Store.Database
    end

    test "returns custom module" do
      assert Store.get_store(store: MyCustomStore) == MyCustomStore
      assert Store.get_store(persist_to: MyCustomStore) == MyCustomStore
    end
  end

  describe "Store.save/3" do
    test "delegates to configured store" do
      state = State.new(%{topic: "AI"})

      assert :ok = Store.save(state.instance_id, state)
      assert {:ok, _} = ETS.load(state.instance_id)
    end

    test "uses store from opts" do
      state = State.new(%{topic: "AI"})

      assert :ok = Store.save(state.instance_id, state, persist_to: :ets)
      assert {:ok, _} = ETS.load(state.instance_id)
    end
  end

  describe "Store.load/2" do
    test "delegates to configured store" do
      state = State.new(%{topic: "AI"})
      ETS.save(state.instance_id, state)

      assert {:ok, loaded} = Store.load(state.instance_id)
      assert loaded.data.topic == "AI"
    end

    test "returns error for missing state" do
      assert {:error, :not_found} = Store.load("nonexistent")
    end
  end

  describe "Store.delete/2" do
    test "delegates to configured store" do
      state = State.new()
      ETS.save(state.instance_id, state)

      assert :ok = Store.delete(state.instance_id)
      assert {:error, :not_found} = ETS.load(state.instance_id)
    end
  end

  describe "Store.list/1" do
    test "delegates to configured store" do
      state1 = State.new(%{topic: "AI"})
      state2 = State.new(%{topic: "ML"})
      ETS.save(state1.instance_id, state1)
      ETS.save(state2.instance_id, state2)

      {:ok, states} = Store.list()

      assert length(states) == 2
    end

    test "passes filter options" do
      state1 = State.new(%{}, session_id: "user_1")
      state2 = State.new(%{}, session_id: "user_2")
      ETS.save(state1.instance_id, state1)
      ETS.save(state2.instance_id, state2)

      {:ok, states} = Store.list(session_id: "user_1")

      assert length(states) == 1
      assert hd(states).session_id == "user_1"
    end
  end

  describe "Store.update/3" do
    test "delegates to configured store" do
      state = State.new(%{count: 5})
      ETS.save(state.instance_id, state)

      {:ok, updated} =
        Store.update(state.instance_id, fn s ->
          State.put(s, :count, 10)
        end)

      assert updated.data.count == 10
    end

    test "returns error for missing state" do
      result =
        Store.update("nonexistent", fn s ->
          State.put(s, :key, "value")
        end)

      assert {:error, :not_found} = result
    end
  end

  describe "Store.exists?/2" do
    test "delegates to configured store" do
      state = State.new()
      ETS.save(state.instance_id, state)

      assert Store.exists?(state.instance_id) == true
      assert Store.exists?("nonexistent") == false
    end
  end
end
