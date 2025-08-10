defmodule Chainex.Integration.PersistentMemoryTest do
  use ExUnit.Case, async: false

  alias Chainex.Chain
  alias Chainex.Memory

  @moduletag :integration
  @moduletag timeout: 60_000

  describe "persistent memory with file backend" do
    setup do
      # Use a unique temp file for each test
      temp_file = "/tmp/chainex_persistent_test_#{:erlang.unique_integer([:positive])}.dat"
      on_exit(fn -> File.rm(temp_file) end)
      {:ok, temp_file: temp_file}
    end

    test "persists conversation across application restarts", %{temp_file: temp_file} do
      # Create a chain with persistent file-backed memory
      chain =
        Chain.new("{{message}}")
        |> Chain.with_memory(:persistent, file_path: temp_file)
        |> Chain.llm(:mock, response: "Response to: {{message}}")

      session_id = "persistent_test_#{:os.system_time(:millisecond)}"

      # First interaction
      {:ok, response1} =
        Chain.run(chain, %{
          message: "Remember that I love Elixir",
          session_id: session_id
        })

      assert response1 == "Response to: Remember that I love Elixir"

      # Simulate application restart by creating a new chain with same file
      new_chain =
        Chain.new("{{message}}")
        |> Chain.with_memory(:persistent, file_path: temp_file)
        |> Chain.llm(:mock, response: "Based on history: {{message}}")

      # Should still have access to previous conversation
      {:ok, response2} =
        Chain.run(new_chain, %{
          message: "What do I love?",
          session_id: session_id
        })

      assert response2 == "Based on history: What do I love?"

      # Verify the file exists and contains data
      assert File.exists?(temp_file)

      # Verify we can load the memory and it has data
      memory = Memory.new(:persistent, %{file_path: temp_file})
      assert Memory.size(memory) > 0
    end

    @tag :live_api
    test "persistent memory with real LLM", %{temp_file: temp_file} do
      chain =
        Chain.new("{{message}}")
        |> Chain.with_memory(:persistent, file_path: temp_file)
        |> Chain.llm(:anthropic, temperature: 0, max_tokens: 100)

      session_id = "persistent_live_#{:os.system_time(:millisecond)}"

      # First conversation
      {:ok, response1} =
        Chain.run(chain, %{
          message: "My favorite programming language is Elixir",
          session_id: session_id
        })

      assert is_binary(response1)

      # Create new chain instance (simulating restart)
      new_chain =
        Chain.new("{{message}}")
        |> Chain.with_memory(:persistent, file_path: temp_file)
        |> Chain.llm(:anthropic, temperature: 0, max_tokens: 100)

      # Should remember from file
      {:ok, response2} =
        Chain.run(new_chain, %{
          message: "What's my favorite programming language?",
          session_id: session_id
        })

      assert is_binary(response2)
      assert String.contains?(String.downcase(response2), "elixir")
    end

    test "persistent memory with pruning options", %{temp_file: temp_file} do
      # Create chain with max_size and auto-pruning
      chain =
        Chain.new("Message {{num}}")
        |> Chain.with_memory(:persistent,
          file_path: temp_file,
          max_size: 3,
          auto_prune: true,
          prune_strategy: :lru,
          prune_percentage: 0.5
        )
        |> Chain.llm(:mock, response: "Ack {{num}}")

      # Add multiple entries to trigger pruning
      for i <- 1..5 do
        {:ok, _} =
          Chain.run(chain, %{
            num: i,
            session_id: "session_#{i}"
          })
      end

      # Load memory to check size
      memory =
        Memory.new(:persistent, %{
          file_path: temp_file,
          max_size: 3,
          auto_prune: true
        })

      # Should have pruned to stay within max_size
      assert Memory.size(memory) <= 3
    end

    test "persistent memory stores complex data structures", %{temp_file: temp_file} do
      chain =
        Chain.new("Process: {{data}}")
        |> Chain.with_memory(:persistent, file_path: temp_file)
        |> Chain.llm(:mock, response: "Processed")

      # Store various data types in different sessions
      test_data = [
        {"test1", "string data"},
        {"test2", 42},
        {"test3", %{nested: %{key: "value"}}},
        {"test4", [1, 2, 3, 4, 5]}
      ]

      for {session, data} <- test_data do
        {:ok, _} =
          Chain.run(chain, %{
            data: inspect(data),
            session_id: session
          })
      end

      # Verify file was created
      assert File.exists?(temp_file)

      # Load memory and verify all sessions are stored
      memory = Memory.new(:persistent, %{file_path: temp_file})

      # Each session should have stored conversation data
      for {session, _} <- test_data do
        assert {:ok, _messages} = Memory.retrieve(memory, session)
      end
    end
  end

  describe "persistent memory with database backend" do
    import Chainex.RepoCase, only: [repo: 0]

    setup do
      # Start owner for database tests
      pid = Ecto.Adapters.SQL.Sandbox.start_owner!(repo(), shared: false)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

      # Create table for this test
      Ecto.Adapters.SQL.query!(
        repo(),
        """
          CREATE TABLE IF NOT EXISTS chainex_chain_memory (
            key TEXT PRIMARY KEY,
            value BLOB NOT NULL,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
            access_count INTEGER NOT NULL DEFAULT 0,
            last_access INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
          )
        """,
        []
      )

      {:ok, table: "chainex_chain_memory"}
    end

    test "persists conversation with database backend", %{table: table} do
      chain =
        Chain.new("{{message}}")
        |> Chain.with_memory(:persistent,
          backend: :database,
          repo: repo(),
          table: table
        )
        |> Chain.llm(:mock, response: "Response: {{message}}")

      session_id = "db_test_#{:os.system_time(:millisecond)}"

      # First interaction
      {:ok, response1} =
        Chain.run(chain, %{
          message: "Store this in database",
          session_id: session_id
        })

      assert response1 == "Response: Store this in database"

      # Create new chain instance (simulating restart)
      new_chain =
        Chain.new("{{message}}")
        |> Chain.with_memory(:persistent,
          backend: :database,
          repo: repo(),
          table: table
        )
        |> Chain.llm(:mock, response: "From DB: {{message}}")

      # Should have access to data from database
      {:ok, response2} =
        Chain.run(new_chain, %{
          message: "Retrieve from database",
          session_id: session_id
        })

      assert response2 == "From DB: Retrieve from database"

      # Verify data in database
      result = Ecto.Adapters.SQL.query!(repo(), "SELECT COUNT(*) FROM #{table}", [])
      [[count]] = result.rows
      assert count > 0
    end

    @tag :live_api
    test "database memory with real LLM", %{table: table} do
      chain =
        Chain.new("{{message}}")
        |> Chain.with_memory(:persistent,
          backend: :database,
          repo: repo(),
          table: table
        )
        |> Chain.llm(:anthropic, temperature: 0, max_tokens: 100)

      session_id = "db_live_#{:os.system_time(:millisecond)}"

      # First conversation
      {:ok, response1} =
        Chain.run(chain, %{
          message: "I'm working on a Phoenix web application",
          session_id: session_id
        })

      assert is_binary(response1)

      # Create new chain (simulating app restart)
      new_chain =
        Chain.new("{{message}}")
        |> Chain.with_memory(:persistent,
          backend: :database,
          repo: repo(),
          table: table
        )
        |> Chain.llm(:anthropic, temperature: 0, max_tokens: 100)

      # Should remember from database
      {:ok, response2} =
        Chain.run(new_chain, %{
          message: "What am I working on?",
          session_id: session_id
        })

      assert is_binary(response2)

      assert String.contains?(String.downcase(response2), "phoenix") or
               String.contains?(String.downcase(response2), "web") or
               String.contains?(String.downcase(response2), "application")
    end

    test "database backend with auto-pruning", %{table: table} do
      chain =
        Chain.new("Message {{num}}")
        |> Chain.with_memory(:persistent,
          backend: :database,
          repo: repo(),
          table: table,
          max_size: 3,
          auto_prune: true,
          prune_strategy: :lfu,
          prune_percentage: 0.5
        )
        |> Chain.llm(:mock, response: "Ack {{num}}")

      # Add multiple entries to trigger pruning
      for i <- 1..5 do
        {:ok, _} =
          Chain.run(chain, %{
            num: i,
            session_id: "session_#{i}"
          })
      end

      # Check that pruning happened
      result = Ecto.Adapters.SQL.query!(repo(), "SELECT COUNT(*) FROM #{table}", [])
      [[count]] = result.rows

      # Should have pruned some entries to stay within max_size
      assert count <= 3
    end
  end

  describe "persistent vs conversation memory comparison" do
    test "conversation memory uses ETS, persistent uses file" do
      temp_file = "/tmp/chainex_compare_#{:erlang.unique_integer([:positive])}.dat"
      on_exit(fn -> File.rm(temp_file) end)

      # Conversation memory chain (uses ETS)
      conv_chain =
        Chain.new("{{msg}}")
        |> Chain.with_memory(:conversation)
        |> Chain.llm(:mock, response: "Conv: {{msg}}")

      # Persistent memory chain (uses file)
      pers_chain =
        Chain.new("{{msg}}")
        |> Chain.with_memory(:persistent, file_path: temp_file)
        |> Chain.llm(:mock, response: "Pers: {{msg}}")

      session = "compare_test"

      # Run both chains
      {:ok, conv_result} = Chain.run(conv_chain, %{msg: "test", session_id: session})
      {:ok, pers_result} = Chain.run(pers_chain, %{msg: "test", session_id: session})

      assert conv_result == "Conv: test"
      assert pers_result == "Pers: test"

      # Persistent memory should have created a file
      assert File.exists?(temp_file)

      # Conversation memory should be in ETS
      assert :ets.whereis(:chainex_conversation_memory) != :undefined
    end

    test "persistent memory survives process restart, conversation doesn't" do
      temp_file = "/tmp/chainex_survival_#{:erlang.unique_integer([:positive])}.dat"
      on_exit(fn -> File.rm(temp_file) end)

      session = "survival_test"

      # Store data in both memory types
      conv_chain =
        Chain.new("Store: {{data}}")
        |> Chain.with_memory(:conversation)
        |> Chain.llm(:mock, response: "Stored")

      pers_chain =
        Chain.new("Store: {{data}}")
        |> Chain.with_memory(:persistent, file_path: temp_file)
        |> Chain.llm(:mock, response: "Stored")

      {:ok, _} = Chain.run(conv_chain, %{data: "conversation data", session_id: session})
      {:ok, _} = Chain.run(pers_chain, %{data: "persistent data", session_id: session})

      # Clear ETS table to simulate process restart
      if :ets.whereis(:chainex_conversation_memory) != :undefined do
        :ets.delete_all_objects(:chainex_conversation_memory)
      end

      # Create new chains
      _new_conv_chain =
        Chain.new("Retrieve")
        |> Chain.with_memory(:conversation)
        |> Chain.llm(:mock, response: "Retrieved")

      _new_pers_chain =
        Chain.new("Retrieve")
        |> Chain.with_memory(:persistent, file_path: temp_file)
        |> Chain.llm(:mock, response: "Retrieved")

      # Persistent memory should still have data
      memory = Memory.new(:persistent, %{file_path: temp_file})
      assert {:ok, _} = Memory.retrieve(memory, session)

      # Conversation memory should be empty (after ETS clear)
      assert :ets.lookup(:chainex_conversation_memory, session) == []
    end
  end
end
