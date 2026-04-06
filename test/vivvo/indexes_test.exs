defmodule Vivvo.IndexesTest do
  use Vivvo.DataCase

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

    test "IPC: includes last_update month when day <= 15" do
      # Last update on Jan 1 (typical rent period start) - include January
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("2.5"), date: ~D[2026-01-01]})

      result = Indexes.compute_update_factor(:ipc, ~D[2026-01-01], ~D[2026-02-15])
      # Should include Jan: (1 + 0.025) = 1.025
      assert Decimal.eq?(result, Decimal.new("1.025"))
    end

    test "IPC: skips last_update month when day > 15 (first month grace period)" do
      # Last update on Jan 16 - skip January entirely
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("2.5"), date: ~D[2026-01-01]})

      result = Indexes.compute_update_factor(:ipc, ~D[2026-01-16], ~D[2026-02-15])
      # Should skip Jan (grace period) and exclude Feb (current month) = 1.0
      assert Decimal.eq?(result, Decimal.new(1))
    end

    test "IPC: excludes today's month rate" do
      # Today is March 15, exclude March rate
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("2.5"), date: ~D[2026-01-01]})
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("3.0"), date: ~D[2026-02-01]})
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("4.0"), date: ~D[2026-03-01]})

      result = Indexes.compute_update_factor(:ipc, ~D[2026-01-01], ~D[2026-03-15])
      # Should include Jan and Feb, exclude March: (1.025) * (1.03) = 1.05575
      assert Decimal.eq?(result, Decimal.new("1.05575"))
    end

    test "IPC: returns 1.0 when last_update is in same month as today and day > 15" do
      # Both dates in January, last_update on Jan 20 (skip), today Jan 25
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("2.5"), date: ~D[2026-01-01]})

      result = Indexes.compute_update_factor(:ipc, ~D[2026-01-20], ~D[2026-01-25])
      # Skip Jan (grace period), no previous months = 1.0
      assert Decimal.eq?(result, Decimal.new(1))
    end

    test "IPC: accumulates multiple months correctly for consecutive updates" do
      # First update: Jan 1 to Feb 1 - should include Jan
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("2.5"), date: ~D[2026-01-01]})
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("3.0"), date: ~D[2026-02-01]})

      result1 = Indexes.compute_update_factor(:ipc, ~D[2026-01-01], ~D[2026-02-01])
      # Include Jan only: 1.025
      assert Decimal.eq?(result1, Decimal.new("1.025"))

      # Second update: Feb 1 to Mar 1 - should include Feb only (not Jan again)
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("3.5"), date: ~D[2026-03-01]})

      result2 = Indexes.compute_update_factor(:ipc, ~D[2026-02-01], ~D[2026-03-01])
      # Include Feb only: 1.03
      assert Decimal.eq?(result2, Decimal.new("1.03"))
    end

    test "IPC: includes last_update month when day is 15" do
      # Last update on Jan 15 - include January (boundary case)
      Indexes.create_index_history(%{type: :ipc, value: Decimal.new("2.5"), date: ~D[2026-01-01]})

      result = Indexes.compute_update_factor(:ipc, ~D[2026-01-15], ~D[2026-02-15])
      # Should include Jan: (1 + 0.025) = 1.025
      assert Decimal.eq?(result, Decimal.new("1.025"))
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

  describe "decimal precision edge cases" do
    test "IPC: very large accumulated rates maintains precision" do
      # Create 12 months of IPC rates at 5% each
      # (1.05)^12 should maintain high precision
      base_date = ~D[2025-01-01]

      for i <- 0..11 do
        date = Date.shift(base_date, month: i)

        Indexes.create_index_history(%{
          type: :ipc,
          value: Decimal.new("5.0"),
          date: date
        })
      end

      # Use Jan 1, 2026 as today - this will include all 12 months (Jan-Dec 2025)
      # because Jan 2026 is excluded as the current month
      result = Indexes.compute_update_factor(:ipc, base_date, ~D[2026-01-01])

      # Verify result is approximately 1.795856 (1.05^12)
      # Allow for small floating point differences
      lower = Decimal.new("1.795")
      upper = Decimal.new("1.80")

      assert Decimal.gt?(result, lower), "Result #{result} should be > #{lower}"
      assert Decimal.lt?(result, upper), "Result #{result} should be < #{upper}"
    end

    test "ICL: ratio approximately 1.0 when values are equal" do
      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("100.0"),
        date: ~D[2026-01-01]
      })

      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("100.0"),
        date: ~D[2026-03-01]
      })

      result = Indexes.compute_update_factor(:icl, ~D[2026-01-01], ~D[2026-03-15])

      # Should be approximately 1.0 when old and new values are equal
      assert Decimal.gt?(result, Decimal.new("0.999"))
      assert Decimal.lt?(result, Decimal.new("1.001"))
    end

    test "compound calculation with high precision decimals" do
      # Use 6 decimal places
      base_date = ~D[2025-01-01]

      Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("3.141592"),
        date: base_date
      })

      Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("2.718281"),
        date: Date.shift(base_date, month: 1)
      })

      result = Indexes.compute_update_factor(:ipc, base_date, ~D[2025-03-15])

      # Verify result is approximately 1.059 (1.03141592 * 1.02718281)
      lower = Decimal.new("1.059")
      upper = Decimal.new("1.060")

      assert Decimal.gt?(result, lower), "Result #{result} should be > #{lower}"
      assert Decimal.lt?(result, upper), "Result #{result} should be < #{upper}"
    end

    test "small factor: 0.001% IPC rate" do
      Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("0.001"),
        date: ~D[2026-01-01]
      })

      result = Indexes.compute_update_factor(:ipc, ~D[2026-01-01], ~D[2026-02-15])

      # 1 + 0.00001 = 1.00001
      expected = Decimal.new("1.00001")
      assert Decimal.eq?(result, expected)
    end

    test "large rent multiplied by small factor" do
      # Create index history
      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("1000.0"),
        date: ~D[2026-01-01]
      })

      Indexes.create_index_history(%{
        type: :icl,
        value: Decimal.new("1000.01"),
        date: ~D[2026-03-01]
      })

      result = Indexes.compute_update_factor(:icl, ~D[2026-01-01], ~D[2026-03-15])

      # Factor should be approximately 1.00001 (1000.01 / 1000.0)
      assert Decimal.gt?(result, Decimal.new("1.00000"))
      assert Decimal.lt?(result, Decimal.new("1.00002"))

      # Simulate large rent calculation: $10,000,000 * ~1.00001 factor
      large_rent = Decimal.new("10000000")
      new_rent = Decimal.mult(large_rent, result)
      # Result should be approximately $10,000,100
      assert Decimal.gt?(new_rent, Decimal.new("10000000"))
      assert Decimal.lt?(new_rent, Decimal.new("10000110"))
    end

    test "multiple compound periods: 12 periods of 2.5% each" do
      base_date = ~D[2025-01-01]

      for i <- 0..11 do
        date = Date.shift(base_date, month: i)

        Indexes.create_index_history(%{
          type: :ipc,
          value: Decimal.new("2.5"),
          date: date
        })
      end

      # Use Jan 1, 2026 as today - this will include all 12 months (Jan-Dec 2025)
      # because Jan 2026 is excluded as the current month
      result = Indexes.compute_update_factor(:ipc, base_date, ~D[2026-01-01])

      # Verify result is approximately 1.345 (1.025^12)
      lower = Decimal.new("1.34")
      upper = Decimal.new("1.35")

      assert Decimal.gt?(result, lower), "Result #{result} should be > #{lower}"
      assert Decimal.lt?(result, upper), "Result #{result} should be < #{upper}"
    end
  end

  describe "get_missing_date_range/2 edge cases" do
    test "returns yesterday+1 to today when latest date is yesterday" do
      today = ~D[2026-03-15]
      yesterday = Date.add(today, -1)

      # Create a record for yesterday
      Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("2.5"),
        date: yesterday
      })

      {from_date, to_date} = Indexes.get_missing_date_range(:ipc, today)

      # Should start from today (yesterday + 1)
      assert from_date == today
      assert to_date == today
    end

    test "returns 2-year default range when no records exist" do
      today = ~D[2026-03-15]

      {from_date, to_date} = Indexes.get_missing_date_range(:ipc, today)

      # Should default to 2 years ago
      expected_from = ~D[2024-03-15]
      assert from_date == expected_from
      assert to_date == today
    end
  end

  describe "create_index_histories/1 edge cases" do
    test "handles duplicate records with on_conflict: :nothing" do
      # Create initial record
      Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("2.5"),
        date: ~D[2026-01-01]
      })

      # Try to create duplicate
      {:ok, count} =
        Indexes.create_index_histories([
          %{type: :ipc, value: Decimal.new("3.0"), date: ~D[2026-01-01]}
        ])

      # Count should be 0 since duplicate was ignored
      assert count == 0

      # Original value should remain
      record = Indexes.get_index_history_by_date(:ipc, ~D[2026-01-01])
      assert Decimal.eq?(record.value, Decimal.new("2.5"))
    end

    test "inserts mixed types (IPC and ICL) together" do
      {:ok, count} =
        Indexes.create_index_histories([
          %{type: :ipc, value: Decimal.new("2.5"), date: ~D[2026-01-01]},
          %{type: :icl, value: Decimal.new("100.0"), date: ~D[2026-01-01]},
          %{type: :ipc, value: Decimal.new("3.0"), date: ~D[2026-02-01]},
          %{type: :icl, value: Decimal.new("110.0"), date: ~D[2026-02-01]}
        ])

      assert count == 4

      # Verify all records exist
      assert Indexes.get_index_history_by_date(:ipc, ~D[2026-01-01]) != nil
      assert Indexes.get_index_history_by_date(:icl, ~D[2026-01-01]) != nil
      assert Indexes.get_index_history_by_date(:ipc, ~D[2026-02-01]) != nil
      assert Indexes.get_index_history_by_date(:icl, ~D[2026-02-01]) != nil
    end
  end

  describe "get_latest_date/1 edge cases" do
    test "returns nil when no records exist" do
      # Use :icl which has no records in this test context
      result = Indexes.get_latest_date(:icl)
      assert result == nil
    end

    test "returns actual latest date when records exist" do
      Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("2.5"),
        date: ~D[2026-01-01]
      })

      Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("3.0"),
        date: ~D[2026-03-01]
      })

      Indexes.create_index_history(%{
        type: :ipc,
        value: Decimal.new("2.8"),
        date: ~D[2026-02-01]
      })

      result = Indexes.get_latest_date(:ipc)
      assert result == ~D[2026-03-01]
    end
  end
end
