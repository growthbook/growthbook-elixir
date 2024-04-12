defmodule GrowthBook.Experiment do
  @moduledoc """
  Struct holding Experiment configuration.

  Holds configuration data for an experiment.
  """

  alias GrowthBook.{
    FeatureRule,
    VariationMeta,
    BucketRange,
    Condition,
    ParentCondition,
    Experiment
  }

  @typedoc """
  Experiment

  Defines a single **Experiment**. Has a number of properties:

  - **`key`** (`t:String.t/0`) - The globally unique identifier for the experiment
  - **`variations`** (list of `t:variation/0`) - The different variations to choose between
  - **`weights`** (list of `t:float/0`) - How to weight traffic between variations. Must add to 1.
  - **`active?`** (`t:boolean/0`) - If set to false, always return the control (first variation)
  - **`coverage`** (`t:float/0`) - What percent of users should be included in the experiment (between 0 and 1, inclusive)
  - **`ranges`** (list of `t:GrowthBook.BucketRange.t/0`) - Array of ranges, one per variation
  - **`condition`** (`t:GrowthBook.Condition.t/0`) - Optional targeting condition
  - **`namespace`** (`t:GrowthBook.namespace/0`) - Adds the experiment to a namespace
  - **`force`** (`t:integer/0`) - All users included in the experiment will be forced into the specific variation index
  - **`hash_attribute`** (`t:String.t/0`) - What user attribute should be used to assign variations (defaults to id)
  - **`fallback_attribute`** (`t:String.t/0`) - When using sticky bucketing, can be used as a fallback to assign variations
  - **`hash_version`** (`t:integer/0`) - The hash version to use (default to 1)
  - **`meta`** (list of `t:GrowthBook.VariationMeta.t/0`) - Meta info about the variations
  - **`filters`** (list of `t:GrowthBook.Filter.t/0`) - Array of filters to apply
  - **`seed`** (`t:String.t/0`) - The hash seed to use
  - **`name`** (`t:String.t/0`) - Human-readable name for the experiment
  - **`phase`** (`t:String.t/0`) - Id of the current experiment phase
  - **`disable_sticky_bucketing`** (`t:boolean/0`) - If true, sticky bucketing will be disabled for this experiment.
    (Note: sticky bucketing is only available if a StickyBucketingService is provided in the Context)
  - **`bucket_version`** (`t:integer/0`) - An sticky bucket version number that can be used to force a re-bucketing of users (default to 0)
  - **`min_bucket_version`** (`t:integer/0`) - Any users with a sticky bucket version less than this will be excluded from the experiment
  - **`parent_conditions`** (list of `t:GrowthBook.ParentCondition.t/0`) - Optional parent conditions
  """
  @type t() :: %__MODULE__{
    key: String.t(),
    variations: [variation()],
    weights: [float()],
    active?: boolean() | nil,
    coverage: float() | nil,
    ranges: [BucketRange.t()],
    condition: Condition.t() | nil,
    namespace: GrowthBook.namespace() | nil,
    force:  integer() | nil,
    hash_attribute: String.t() | nil,
    fallback_attribute: String.t() | nil,
    hash_version:  integer() | nil,
    meta: [VariationMeta.t()],
    filters: [Filter.t()] | nil,
    seed: String.t() | nil,
    name: String.t() | nil,
    phase: String.t() | nil,
    disable_sticky_bucketing: boolean() | nil,
    bucket_version: integer() | nil,
    min_bucket_version: integer() | nil,
    parent_conditions: [ParentCondition.t()] | nil
  }

  @typedoc """
  Variation

  Defines a single variation. It may be a map, a number of a string.
  """
  @type variation() :: number() | String.t() | map()

  @enforce_keys [:key, :variations]
  defstruct [
    :key,
    :variations,
    :weights,
    :active?,
    :coverage,
    :ranges,
    :condition,
    :namespace,
    :force,
    :hash_attribute,
    :fallback_attribute,
    :hash_version,
    :meta,
    :filters,
    :seed,
    :name,
    :phase,
    :disable_sticky_bucketing,
    :bucket_version,
    :min_bucket_version,
    :parent_conditions
  ]

  @doc """
  Creates new experiment struct from rule.
  """
  @spec from_rule(String.t(), FeatureRule.t()) ::t()
  def from_rule(feature_id, %FeatureRule{} = rule) do
    %Experiment{
      variations: rule.variations || [],
      key: rule.key || feature_id,
      coverage: rule.coverage,
      weights: rule.weights,
      hash_attribute: rule.hash_attribute,
      fallback_attribute: rule.fallback_attribute,
      disable_sticky_bucketing: rule.disable_sticky_bucketing,
      bucket_version: rule.bucket_version,
      min_bucket_version: rule.min_bucket_version,
      namespace: rule.namespace,
      meta: rule.meta,
      ranges: rule.ranges,
      name: rule.name,
      phase: rule.phase,
      seed: rule.seed,
      hash_version: rule.hash_version,
      filters: rule.filters,
      condition: rule.condition,
      active?: true
    }
  end

end
