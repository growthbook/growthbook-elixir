defmodule GrowthBook.Experiment do
  @moduledoc """
  Struct holding Experiment configuration.

  Holds configuration data for an experiment.
  """

  alias GrowthBook.ExperimentOverride

  @typedoc """
  Experiment

  Defines a single **Experiment**. Has a number of properties:

  - **`key`** (`String.t()`) - The globally unique identifier for the experiment
  - **`variations`** (list of `t:variation/0`) - The different variations to choose between
  - **`weights`** (`[float()]`) - How to weight traffic between variations. Must add to `1`.
  - **`active?`** (`boolean()`) - If set to `false`, always return the control (first variation)
  - **`coverage`** (`float()`) - What percent of users should be included in the experiment
    (between 0 and 1, inclusive)
  - **`condition`** (`t:GrowthBook.Condition.t/0`) - Optional targeting condition
  - **`namespace`** (`t:GrowthBook.namespace/0`) - Adds the experiment to a namespace
  - **`force`** (`integer()`) - All users included in the experiment will be forced into the
    specific variation index
  - **`hash_attribute`** (`String.t()`) - What user attribute should be used to assign variations
    (defaults to `id`)
  - **`status`** (`String.t()`) - The status of the experiment, one of
    `"draft"`, `"running"`, `"stopped"`
  """
  @type t() :: %__MODULE__{
          key: String.t(),
          variations: [variation()],
          weights: [float()] | nil,
          condition: GrowthBook.Condition.t() | nil,
          coverage: float() | nil,
          namespace: GrowthBook.namespace() | nil,
          force: integer() | nil,
          hash_attribute: String.t() | nil,
          active?: boolean() | nil,
          status: String.t() | nil
        }

  @typedoc """
  Variation

  Defines a single variation. It may be a map, a number of a string.
  """
  @type variation() :: number() | String.t() | map()

  @enforce_keys [:key, :variations]
  defstruct key: nil,
            variations: [],
            weights: nil,
            condition: nil,
            coverage: nil,
            namespace: nil,
            force: nil,
            hash_attribute: nil,
            active?: nil,
            status: nil

  @doc """
  Applies overrides to the experiment, if configured.

  Takes an experiment struct and a map of experiment overrides, and if the experiment key has
  overrides configured, applies them to the experiment.
  """
  @spec merge_with_overrides(t(), GrowthBook.Context.experiment_overrides()) :: t()
  def merge_with_overrides(%__MODULE__{key: key} = experiment, experiment_overrides)
      when is_map_key(experiment_overrides, key) do
    %{^key => %ExperimentOverride{} = overrides} = experiment_overrides

    # Filter out any keys that aren't set before overriding
    overrides
    |> Map.from_struct()
    |> Enum.reject(&match?({_key, nil}, &1))
    |> Map.new()
    |> then(&struct(experiment, &1))
  end

  def merge_with_overrides(%__MODULE__{} = experiment, _experiment_overrides), do: experiment
end
