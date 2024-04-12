defmodule GrowthBook.ExperimentResult do
  @moduledoc """
  Struct holding the results of an `GrowthBook.Experiment`.

  Holds the result of running an `GrowthBook.Experiment` against a `GrowthBook.Context`.
  """

  @typedoc """
  Experiment result

  The result of running an `GrowthBook.Experiment` given a specific `GrowthBook.Context`

  - **`in_experiment?`** (`t:boolean/0`) - Whether or not the user is part of the experiment
  - **`variation_id`** (`t:integer/0`) - The array index of the assigned variation
  - **`value`** (`t:any/0`) - The array value of the assigned variation
  - **`hash_used?`** (`t:boolean/0`) - If a hash was used to assign a variation
  - **`hash_attribute`** (`t:String.t/0`) - The user attribute used to assign a variation
  - **`hash_value`** (`t:String.t/0`) - The value of that attribute
  - **`feature_id`** (`t:String.t/0`) - The id of the feature (if any) that the experiment came from
  - **`key`** (`t:String.t/0`) - The unique key for the assigned variation
  - **`bucket`** (`t:float/0`) - The hash value used to assign a variation (float from 0 to 1)
  - **`name`** (`t:String.t/0`) - The human-readable name of the assigned variation
  - **`passthrough?`** (`t:boolean/0`) - Used for holdout groups
  - **`sticky_bucket_used?`** (`t:boolean/0`) - If sticky bucketing was used to assign a variation

  The `variation_id` and `value` should always be set, even when `in_experiment?` is false.

  The `hash_attribute` and `hash_value` should always be set, even when `hash_used?` is false.

  The `key` should always be set, even if `experiment.meta` is not defined or incomplete.
  In that case, convert the variation's array index to a string (e.g. 0 -> "0") and use that as the key instead.
  """
  @type t() :: %__MODULE__{
    in_experiment?: boolean(),
    variation_id: integer(),
    value: term(),
    hash_used?: boolean(),
    hash_attribute: String.t(),
    hash_value: String.t() | integer(),
    feature_id: String.t(),
    key: String.t(),
    bucket: float(),
    name: String.t(),
    passthrough?: boolean(),
    sticky_bucket_used?: boolean()
  }

  @enforce_keys [:value, :variation_id, :in_experiment?, :hash_attribute, :hash_value, :key, :passthrough?]
  defstruct [
    :in_experiment?,
    :variation_id,
    :value,
    :hash_used?,
    :hash_attribute,
    :hash_value,
    :feature_id,
    :key,
    :bucket,
    :name,
    :passthrough?,
    :sticky_bucket_used?
  ]
end
