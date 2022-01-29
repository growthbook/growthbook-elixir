defmodule GrowthBook.ExperimentResult do
  @moduledoc """
  Struct holding the results of an `GrowthBook.Experiment`.

  Holds the result of running an `GrowthBook.Experiment` against a `GrowthBook.Context`.
  """

  @typedoc """
  Experiment result

  The result of running an `GrowthBook.Experiment` given a specific `GrowthBook.Context`

  - **`in_experiment?`** (`boolean()`) - Whether or not the user is part of the experiment
  - **`variation_id`** (`String.t()`) - The list index of the assigned variation
  - **`value`** (`term()`) - The list value of the assigned variation
  - **`hash_attribute`** (`String.t()`) - The user attribute used to assign a variation
  - **`hash_value`** (`String.t())` - The value of that attribute

  The `variation_id` and `value` should always be set, even when `in_experiment?` is false.
  """
  @type t() :: %__MODULE__{
          value: term(),
          variation_id: integer(),
          in_experiment?: boolean(),
          hash_attribute: String.t(),
          hash_value: String.t()
        }

  @enforce_keys [:value, :variation_id, :in_experiment?, :hash_attribute, :hash_value]
  defstruct [:value, :variation_id, :in_experiment?, :hash_attribute, :hash_value]
end
