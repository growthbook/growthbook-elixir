defmodule GrowthBook.ExperimentResultTest do
  use ExUnit.Case, async: true
  alias GrowthBook.ExperimentResult
  doctest GrowthBook.ExperimentResult

  describe "%ExperimentResult{}" do
    test "enforces required keys" do
      assert_raise(ArgumentError, fn ->
        struct!(ExperimentResult, value: 1)
      end)

      assert struct!(ExperimentResult,
               value: nil,
               variation_id: nil,
               in_experiment?: nil,
               hash_attribute: nil,
               hash_value: nil
             )
    end
  end
end
