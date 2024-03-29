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
    Experiment
  }

  @typedoc """
  Experiment

  Defines a single **Experiment**. Has a number of properties:

  - **`key`** (`String.t()`) - The globally unique identifier for the experiment
  - **`variations`** (list of `t:variation/0`) - The different variations to choose between
  - **`weights` (`[float()]`) - How to weight traffic between variations. Must add to 1.
  - **`active?`** (`boolean()`) - If set to false, always return the control (first variation)
  - **`coverage`** (`float()`) - What percent of users should be included in the experiment (between 0 and 1, inclusive)
  - **`ranges`** (`[t:BucketRange.t/0]`) - Array of ranges, one per variation
  - **`condition`** (`t:Condition.t/0`) - Optional targeting condition
  - **`namespace`** (`t:GrowthBook.namespace/0`) - Adds the experiment to a namespace
  - **`force`** (`integer()`) - All users included in the experiment will be forced into the specific variation index
  - **`hash_attribute`** (`String.t/0`) - What user attribute should be used to assign variations (defaults to id)
  - **`fallback_attribute`** (`String.t/0`) - When using sticky bucketing, can be used as a fallback to assign variations
  - **`hash_version`** (`integer()`) - The hash version to use (default to 1)
  - **`meta`** (`[t:VariationMeta.t()]`) - Meta info about the variations
  - **`filters`** (`[t:Filter.t()]`) - Array of filters to apply
  - **`seed`** (`String.t()`) - The hash seed to use
  - **`name`** (`String.t()`) - Human-readable name for the experiment
  - **`phase`** (`String.t()`) - Id of the current experiment phase
  - **`disable_sticky_bucketing` (`boolean()`) - If true, sticky bucketing will be disabled for this experiment.
    (Note: sticky bucketing is only available if a StickyBucketingService is provided in the Context)
  - **`bucket_version`** (`integer()`) - An sticky bucket version number that can be used to force a re-bucketing of users (default to 0)
  - **`min_bucket_version`** (`integer()`) - Any users with a sticky bucket version less than this will be excluded from the experiment
  """
  @type t() :: %__MODULE__{
    key: String.t(),
    variations: [variation()],
    weights: [float()] | nil,
    active?: boolean() | nil,
    coverage: float() | nil,
    ranges: [BucketRange.t()] | nil,
    condition: Condition.t() | nil,
    namespace: GrowthBook.namespace() | nil,
    force:  integer() | nil,
    hash_attribute: String.t() | nil,
    fallback_attribute: String.t() | nil,
    hash_version:  integer() | nil,
    meta: [VariationMeta.t()] | nil,
    filters: [Filter.t()] | nil,
    seed: String.t() | nil,
    name: String.t() | nil,
    phase: String.t() | nil,
    disable_sticky_bucketing: boolean() | nil,
    bucket_version: integer() | nil,
    min_bucket_version: integer() | nil
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
    :min_bucket_version
  ]

  @doc """
  Creates new experiment struct from rule.
  """
  @spec from_rule(String.t(), FeatureRule.t()) ::t()
  def from_rule(feature_id, %FeatureRule{} = rule) do
    %Experiment{
      variations: rule.variations,
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
      condition: rule.condition
    }
  end
end
