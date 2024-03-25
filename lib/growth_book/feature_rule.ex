defmodule GrowthBook.FeatureRule do
  @moduledoc """
  Struct holding Feature rule configuration.

  Holds rule configuration to determine if a feature should be run, given the active
  `GrowthBook.Context`.
  """

  alias GrowthBook.{
    Condition,
    VariationMeta,
    BucketRange,
    Filter
  }

  @typedoc """
  Feature rule

  Overrides the `default_value` of a `GrowthBook.Feature`. Has a number of optional properties

  - **`condition`** (`t:GrowthBook.Condition.t/0`) - Optional targeting condition
  - **`parent_conditions`** (`list of t:GrowthBook.ParentCondition.t/0`) - Each item defines a prerequisite
    where a condition must evaluate against a parent feature's value (identified by id). If gate is true, then
    this is a blocking feature-level prerequisite; otherwise it applies to the current rule only.
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
  - **`hash_version`** (`integer()`) - The hash version to use (default to 1)
  - **`range`** (`t:GrowthBook.BucketRange.t()`) - A more precise version of `coverage`
  - **`ranges`** (`list of t:GrowthBook.BucketRange.t()`) - Ranges for experiment variations
  - **`meta`** (`[t:GrowthBook.VariationMeta.t/0]`) - Meta info about the experiment variations
  - **`filters`** (`[t:GrowthBook.Filter.t/0]`) - Array of filters to apply to the rule
  - **`seed`** (`string()`) - Seed to use for hashing
  - **`name`** (`String.t()`) - Human-readable name for the experiment
  - **`phase`** (`String.t()`) - The phase id of the experiment
  """
  @type t() :: %__MODULE__{
    condition: Condition.t() | nil,
    parent_conditions: [ParentCondition.t()] | nil,
    coverage: float() | nil,
    force: term() | nil,
    variations: [term()] | nil,
    key: String.t() | nil,
    weights: [float()] | nil,
    namespace: GrowthBook.namespace() | nil,
    hash_attribute: String.t() | nil,
    hash_version: integer() | nil,
    range: BucketRange.t() | nil,
    ranges: [BucketRange.t()] | nil,
    meta: [VariationMeta.t()] | nil,
    filters: [Filter.t()] | nil,
    seed: String.t() | nil,
    name: String.t() | nil,
    phase: String.t() | nil
  }

  defstruct [
    :condition,
    :parent_conditions,
    :coverage,
    :force,
    :variations,
    :key,
    :weights,
    :namespace,
    :hash_attribute,
    :hash_version,
    :range,
    :ranges,
    :meta,
    :filters,
    :seed,
    :name,
    :phase
  ]
end
