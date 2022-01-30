defmodule GrowthBook.FeatureTest do
  use ExUnit.Case, async: true
  alias GrowthBook.Feature
  doctest GrowthBook.Feature

  describe "%Feature{}" do
    test "doesn't enforce any keys" do
      assert struct!(Feature, [])
    end
  end
end
