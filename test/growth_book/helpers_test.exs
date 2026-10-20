defmodule GrowthBook.HelpersTest do
  use ExUnit.Case, async: true
  alias GrowthBook.Helpers
  doctest GrowthBook.Helpers

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

  describe "missing seed and hashVersion" do
    defp assignments(experiment_config) do
      experiment =
        Map.merge(%{"key" => "my-test", "variations" => [0, 1]}, experiment_config)
        |> GrowthBook.Config.experiment_from_config()

      for id <- 1..50 do
        context = %GrowthBook.Context{attributes: %{"id" => to_string(id)}}
        GrowthBook.run(context, experiment).variation_id
      end
    end

    test "empty seed falls back to the experiment key" do
      assert assignments(%{"seed" => ""}) == assignments(%{})
    end

    test "hashVersion 0 falls back to version 1" do
      assert assignments(%{"hashVersion" => 0}) == assignments(%{})
    end
  end
end
