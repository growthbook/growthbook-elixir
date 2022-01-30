defmodule GrowthBook.HelpersTest do
  use ExUnit.Case, async: true
  alias GrowthBook.Helpers
  doctest GrowthBook.Helpers

  describe "Helpers.fnv32a/1" do
    test "hashes correctly" do
      assert 1_211_955_754 == Helpers.fnv32a("elixir")
    end
  end

  describe "Helpers.get_equal_weights/1" do
    test "returns an empty list if count < 1" do
      assert [] == Helpers.get_equal_weights(0)
      assert [] == Helpers.get_equal_weights(-1)
      assert [] == Helpers.get_equal_weights(-10)
    end
  end

  describe "Helpers.cast_boolish/1" do
    test "returns an empty list if count < 1" do
      refute Helpers.cast_boolish(0)
      refute Helpers.cast_boolish(nil)
      refute Helpers.cast_boolish(:undefined)
      refute Helpers.cast_boolish(false)
      refute Helpers.cast_boolish("off")
      refute Helpers.cast_boolish("")

      assert Helpers.cast_boolish(1)
      assert Helpers.cast_boolish(true)
      assert Helpers.cast_boolish("hello")
      assert Helpers.cast_boolish([])
      assert Helpers.cast_boolish(%{})
      assert Helpers.cast_boolish({1, 2, 3})
    end
  end
end
