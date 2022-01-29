defmodule GrowthBook.HelpersTest do
  use ExUnit.Case, async: true
  doctest GrowthBook.Helpers

  describe "GrowthBook.Helpers.fnv32a/1" do
    test "hashes correctly" do
      assert 1_211_955_754 == GrowthBook.Helpers.fnv32a("elixir")
    end
  end
end
