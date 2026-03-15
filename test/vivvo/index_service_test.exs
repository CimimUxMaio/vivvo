defmodule Vivvo.IndexServiceTest do
  use ExUnit.Case, async: true

  alias Vivvo.IndexService

  describe "latest/1" do
    test "fetches latest IPC data from API" do
      assert {:ok, %{date: date, value: value}} = IndexService.latest(:ipc)
      assert is_struct(date, Date)
      assert is_struct(value, Decimal)
    end

    test "fetches latest ICL data from API" do
      assert {:ok, %{date: date, value: value}} = IndexService.latest(:icl)
      assert is_struct(date, Date)
      assert is_struct(value, Decimal)
    end

    test "returns error for unknown index type" do
      assert_raise ArgumentError, fn ->
        IndexService.latest(:unknown)
      end
    end
  end

  describe "history/3" do
    test "fetches historical IPC data for specific date range" do
      from = Date.new!(2025, 1, 1)
      to = Date.new!(2025, 3, 1)

      assert {:ok, history} = IndexService.history(:ipc, from, to)
      assert is_list(history)

      for item <- history do
        assert %{date: date, value: value} = item
        assert is_struct(date, Date)
        assert is_struct(value, Decimal)
      end
    end

    test "fetches historical ICL data for specific date range" do
      from = Date.new!(2025, 1, 1)
      to = Date.new!(2025, 3, 1)

      assert {:ok, history} = IndexService.history(:icl, from, to)
      assert is_list(history)

      for item <- history do
        assert %{date: date, value: value} = item
        assert is_struct(date, Date)
        assert is_struct(value, Decimal)
      end
    end

    test "returns error when from date is nil" do
      to = Date.new!(2025, 3, 1)
      assert {:error, "From and To dates cannot be nil"} = IndexService.history(:ipc, nil, to)
    end

    test "returns error when to date is nil" do
      from = Date.new!(2025, 1, 1)
      assert {:error, "From and To dates cannot be nil"} = IndexService.history(:ipc, from, nil)
    end

    test "returns error when both dates are nil" do
      assert {:error, "From and To dates cannot be nil"} = IndexService.history(:ipc, nil, nil)
    end
  end
end
