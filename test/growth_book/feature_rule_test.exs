defmodule GrowthBook.FeatureRuleTest do
  use ExUnit.Case, async: true
  alias GrowthBook.FeatureRule
  doctest GrowthBook.FeatureRule

  describe "%FeatureRule{}" do
    test "doesn't enforce any keys" do
      assert struct!(FeatureRule, [])
    end
  end
end
