defmodule GrowthBook.FeatureRule do
  @moduledoc """
  Struct holding Feature rule configuration.

  Holds rule configuration to determine if a feature should be run, given the active
  `GrowthBook.Context`.
  """

  @typedoc """
  Feature rule

  Overrides the `default_value` of a `GrowthBook.Feature`. Has a number of optional properties

  - **`condition`** (`t:GrowthBook.Condition.t/0`) - Optional targeting condition
  - **`coverage`** (`float()`) - What percent of users should be included in the experiment
    (between 0 and 1, inclusive)
  - **`force`** (`term()`) - Immediately force a specific value (ignore every other option besides
    condition and coverage)
  - **`variations`** (`[term()]`) - Run an experiment (A/B test) and randomly choose between these
    variations
  - **`key`** (`String.t()`) - The globally unique tracking key for the experiment (default to
    the feature key)
  - **`weights`** (`[float()]`) - How to weight traffic between variations. Must add to 1.
  - **`namespace`** (`t:GrowthBook.namespace/0`) - Adds the experiment to a namespace
  - **`hash_attribute`** (`String.t()`) - What user attribute should be used to assign variations
    (defaults to `id`)
  """
  @type t() :: %__MODULE__{
          condition: GrowthBook.Condition.t() | nil,
          coverage: float() | nil,
          force: term() | nil,
          variations: [term()] | nil,
          key: String.t() | nil,
          weights: [float()] | nil,
          namespace: GrowthBook.namespace() | nil,
          hash_attribute: String.t() | nil
        }

  defstruct [
    :condition,
    :coverage,
    :force,
    :variations,
    :key,
    :weights,
    :namespace,
    :hash_attribute
  ]
end
