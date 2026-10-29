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
      refute Helpers.cast_boolish(0.0)
      refute Helpers.cast_boolish(nil)
      refute Helpers.cast_boolish(:undefined)
      refute Helpers.cast_boolish(false)
      refute Helpers.cast_boolish("")

      assert Helpers.cast_boolish(1)
      assert Helpers.cast_boolish(true)
      assert Helpers.cast_boolish("hello")
      assert Helpers.cast_boolish("off")
      assert Helpers.cast_boolish([])
      assert Helpers.cast_boolish(%{})
      assert Helpers.cast_boolish({1, 2, 3})
    end
  end

  describe "Helpers.hash_value/2" do
    test "uses only non-empty strings and non-zero numbers" do
      for value <- ["1", 1, 1.5, -1] do
        assert value == Helpers.hash_value(%{"id" => value}, "id")
      end

      for value <- ["", 0, 0.0, true, false, nil, [], ["1"], %{}, %{"a" => "1"}] do
        assert nil == Helpers.hash_value(%{"id" => value}, "id")
      end

      assert nil == Helpers.hash_value(%{}, "id")
      assert nil == Helpers.hash_value(nil, "id")
    end
  end

  describe "hash attribute values" do
    defp run_with(attributes, experiment_config \\ %{}) do
      experiment =
        Map.merge(%{"key" => "my-test", "variations" => [0, 1]}, experiment_config)
        |> GrowthBook.Config.experiment_from_config()

      GrowthBook.run(%GrowthBook.Context{attributes: attributes}, experiment)
    end

    test "a value that isn't a string or number is missing, even with a fallback attribute" do
      for id <- [true, false, 0, "", [], ["1"], %{}, %{"a" => "1"}] do
        result = run_with(%{"id" => id, "deviceId" => "d1"}, %{"fallbackAttribute" => "deviceId"})

        refute result.in_experiment?
        refute result.hash_used?
        assert result.hash_value == ""
      end
    end

    test "an integral float hashes like the integer" do
      for version <- [1, 2] do
        assert run_with(%{"id" => 1.0}, %{"hashVersion" => version}).bucket ==
                 run_with(%{"id" => 1}, %{"hashVersion" => version}).bucket
      end

      assert GrowthBook.Hash.hash("a", 1.0, 2) == GrowthBook.Hash.hash("a", "1", 2)
      assert GrowthBook.Hash.hash("a", 1.5, 2) == GrowthBook.Hash.hash("a", "1.5", 2)
    end

    test "a rollout skips a user whose hash attribute is missing" do
      for id <- [true, [], %{}, 0] do
        refute Helpers.included_in_rollout?(%{"id" => id}, "seed", nil, nil, 1.0, 1)
      end
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
