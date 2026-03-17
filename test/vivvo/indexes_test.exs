defmodule Vivvo.IndexesTest do
  use Vivvo.DataCase, async: true

  alias Vivvo.Indexes

  describe "compute_update_factor/3" do
    test "returns 1 when last update is after previous month end for IPC" do
      today = ~D[2026-03-15]
      # After Feb 28 (previous month end)
      last_update = ~D[2026-03-10]

      result = Indexes.compute_update_factor(:ipc, last_update, today)
      # Returns 1 (no change multiplier) when no history in range
      assert Decimal.eq?(result, Decimal.new(1))
    end

    test "computes IPC update factor by accumulating historic rates" do
      today = ~D[2026-03-15]
      last_update = ~D[2026-01-01]

      # Create IPC history for Jan and Feb
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("2.5"), date: ~D[2026-01-01]})
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("3.0"), date: ~D[2026-02-01]})

      result = Indexes.compute_update_factor(:ipc, last_update, today)
      # Returns direct multiplier: (1 + 0.025) * (1 + 0.03) = 1.05575
      assert Decimal.eq?(result, Decimal.new("1.05575"))
    end

    test "returns 1 for IPC when no history exists" do
      today = ~D[2026-03-15]
      last_update = ~D[2025-10-01]

      result = Indexes.compute_update_factor(:ipc, last_update, today)
      # Returns 1 (no change multiplier) when no history exists
      assert Decimal.eq?(result, Decimal.new(1))
    end

    test "computes ICL update factor using ratio of values" do
      # Create ICL history entries
      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("100.0"),
        date: ~D[2026-01-01]
      })

      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("110.0"),
        date: ~D[2026-03-01]
      })

      result = Indexes.compute_update_factor(:icl, ~D[2026-01-01], ~D[2026-03-15])
      # Returns direct ratio: 110 / 100 = 1.1 (multiply by this to get new rent)
      assert Decimal.eq?(result, Decimal.new("1.1"))
    end

    test "raises error for ICL when old history does not exist" do
      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("110.0"),
        date: ~D[2026-03-01]
      })

      assert_raise ArgumentError, ~r/No ICL history found for date/, fn ->
        Indexes.compute_update_factor(:icl, ~D[2026-01-01], ~D[2026-03-15])
      end
    end

    test "raises error for ICL when latest history does not exist" do
      # Create only old history, but no recent history
      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("100.0"),
        date: ~D[2026-01-01]
      })

      # Query with today before the history date so no latest value exists
      assert_raise ArgumentError, ~r/No latest ICL history found for date/, fn ->
        Indexes.compute_update_factor(:icl, ~D[2026-01-01], ~D[2025-12-01])
      end
    end

    test "raises error for unknown index type" do
      assert_raise ArgumentError, ~r/Unsupported index type: unknown/, fn ->
        Indexes.compute_update_factor(:unknown, ~D[2026-01-01], ~D[2026-03-15])
      end
    end

    test "uses default today date when not provided" do
      # Just verify it doesn't crash with default
      result = Indexes.compute_update_factor(:ipc, ~D[2026-01-01])
      assert %Decimal{} = result
    end
  end

  describe "get_index_history_by_date_range/3" do
    test "returns histories within date range ordered by date" do
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("1.0"), date: ~D[2026-01-01]})
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("2.0"), date: ~D[2026-02-01]})
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("3.0"), date: ~D[2026-03-01]})
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("4.0"), date: ~D[2026-04-01]})

      results = Indexes.get_index_history_by_date_range(:ipc, ~D[2026-02-01], ~D[2026-03-01])

      assert length(results) == 2
      assert Enum.map(results, & &1.value) == [Decimal.new("2.0"), Decimal.new("3.0")]
    end

    test "returns empty list when no histories in range" do
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("1.0"), date: ~D[2026-01-01]})

      results = Indexes.get_index_history_by_date_range(:ipc, ~D[2026-05-01], ~D[2026-06-01])

      assert results == []
    end

    test "filters by type" do
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("1.0"), date: ~D[2026-01-01]})

      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("100.0"),
        date: ~D[2026-01-01]
      })

      results = Indexes.get_index_history_by_date_range(:ipc, ~D[2026-01-01], ~D[2026-01-31])

      assert length(results) == 1
      assert hd(results).type == :ipc
    end
  end

  describe "get_index_history_by_date/2" do
    test "returns history for specific date" do
      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("150.5"),
        date: ~D[2026-02-01]
      })

      result = Indexes.get_index_history_by_date(:icl, ~D[2026-02-01])

      assert result != nil
      assert Decimal.eq?(result.value, Decimal.new("150.5"))
    end

    test "returns nil when no history exists for date" do
      result = Indexes.get_index_history_by_date(:icl, ~D[2020-01-01])
      assert result == nil
    end
  end

  describe "get_latest_index_value/1" do
    test "returns latest history by date" do
      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("100.0"),
        date: ~D[2026-01-01]
      })

      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("110.0"),
        date: ~D[2026-03-01]
      })

      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("105.0"),
        date: ~D[2026-02-01]
      })

      result = Indexes.get_latest_index_value(:icl)

      assert result != nil
      assert Decimal.eq?(result.value, Decimal.new("110.0"))
      assert result.date == ~D[2026-03-01]
    end

    test "returns nil when no history exists for type" do
      result = Indexes.get_latest_index_value(:icl)
      assert result == nil
    end
  end
end
