defmodule GrowthBook.ExperimentOverride do
  @moduledoc """
  Struct holding experiment overrides configuration.

  Holds data from the GrowthBook experiment configuration, to override hard-coded experiment
  config.
  """

  @typedoc """
  ExperimentOverride

  Defines overrides for an existing hard-coded experiment. Has a number of optional properties:

  - **`weights`** (`[float()]`) - How to weight traffic between variations. Must add to `1`.
  - **`active`** (`boolean()`) - If set to `false`, always return the control (first variation)
  - **`coverage`** (`float()`) - What percent of users should be included in the experiment
    (between 0 and 1, inclusive)
  - **`condition`** (`t:GrowthBook.Condition.t/0`) - Optional targeting condition
  - **`namespace`** (`t:GrowthBook.namespace/0`) - Adds the experiment to a namespace
  - **`force`** (`integer()`) - All users included in the experiment will be forced into the
    specific variation index
  """
  @type t() :: %__MODULE__{
          weights: [float()] | nil,
          condition: GrowthBook.Condition.t() | nil,
          coverage: float() | nil,
          namespace: GrowthBook.namespace() | nil,
          force: integer() | nil,
          hash_attribute: String.t() | nil,
          active?: boolean() | nil
        }

  defstruct weights: nil,
            condition: nil,
            coverage: nil,
            namespace: nil,
            force: nil,
            hash_attribute: nil,
            active?: nil
end
