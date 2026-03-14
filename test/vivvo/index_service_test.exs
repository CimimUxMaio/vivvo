defmodule Vivvo.IndexServiceTest do
  use ExUnit.Case, async: true

  alias Vivvo.IndexService

  describe "get_index_value/1" do
    test "returns 0.03 for cpi" do
      assert IndexService.get_index_value(:cpi) == Decimal.new("0.03")
    end

    test "returns 0.05 for fixed_percentage" do
      assert IndexService.get_index_value(:fixed_percentage) == Decimal.new("0.05")
    end
  end

  describe "get_all_index_values/0" do
    test "returns map with all index types" do
      result = IndexService.get_all_index_values()

      assert result.cpi == Decimal.new("0.03")
      assert result.fixed_percentage == Decimal.new("0.05")
    end
  end
end
