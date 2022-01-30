defmodule GrowthBook.ExperimentTest do
  use ExUnit.Case, async: true
  alias GrowthBook.Experiment
  alias GrowthBook.ExperimentOverride
  doctest GrowthBook.Experiment

  describe "Experiment.merge_with_overrides/2" do
    test "overrides all non-nil values" do
      experiment = %Experiment{
        key: "my-feature",
        active?: true,
        condition: %{"key" => "val"},
        coverage: 0.2,
        force: 1,
        hash_attribute: "id",
        namespace: {"key", 0.1, 0.3},
        status: "active",
        variations: [1, 2, 3],
        weights: [0.33, 0.33, 0.33]
      }

      experiment_overrides = %{
        "my-feature" => %ExperimentOverride{
          active?: false,
          condition: %{"key1" => "val1"},
          coverage: 0.5,
          force: 2,
          hash_attribute: "company_id",
          namespace: {"key1", 0.2, 0.4},
          status: "draft",
          weights: [0.2, 0.4, 0.4]
        }
      }

      assert %Experiment{
               # Remained unchanged:
               key: "my-feature",
               variations: [1, 2, 3],

               # Overridden:
               active?: false,
               condition: %{"key1" => "val1"},
               coverage: 0.5,
               force: 2,
               hash_attribute: "company_id",
               namespace: {"key1", 0.2, 0.4},
               status: "draft",
               weights: [0.2, 0.4, 0.4]
             } == Experiment.merge_with_overrides(experiment, experiment_overrides)
    end

    test "doesn't overwrite values that are overwritten as nil" do
      experiment = %Experiment{
        key: "my-feature",
        active?: true,
        condition: %{"key" => "val"},
        coverage: 0.2,
        force: 1,
        hash_attribute: "id",
        namespace: {"key", 0.1, 0.3},
        status: "active",
        variations: [1, 2, 3],
        weights: [0.33, 0.33, 0.33]
      }

      experiment_overrides = %{
        "my-feature" => %ExperimentOverride{
          active?: nil,
          condition: nil,
          coverage: nil,
          force: nil,
          hash_attribute: nil,
          namespace: nil,
          status: nil,
          weights: nil
        }
      }

      assert experiment == Experiment.merge_with_overrides(experiment, experiment_overrides)
    end
  end
end
