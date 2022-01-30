defmodule GrowthBook.ConfigTest do
  use ExUnit.Case, async: true
  alias GrowthBook.Config
  alias GrowthBook.ExperimentOverride
  doctest GrowthBook.Config

  describe "Config.experiment_overrides_from_config/1" do
    test "returns the type of the value" do
      config = %{"my-feature" => %{"coverage" => 0.2}}

      assert %{"my-feature" => %ExperimentOverride{coverage: 0.2}} =
               Config.experiment_overrides_from_config(config)
    end
  end
end
