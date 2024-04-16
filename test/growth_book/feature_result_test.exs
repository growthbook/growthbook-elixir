defmodule GrowthBook.FeatureResultTest do
  use ExUnit.Case, async: true
  alias GrowthBook.FeatureResult
  doctest GrowthBook.FeatureResult

  describe "%FeatureResult{}" do
    test "enforces required keys" do
      assert_raise(ArgumentError, fn ->
        struct!(FeatureResult, experiment: nil)
      end)

      assert struct!(FeatureResult,
               value: 1,
               on: true,
               on?: true,
               off: false,
               off?: false,
               source: :unknown_feature,
               experiment: nil,
               experiment_result: nil
             )
    end
  end
end
