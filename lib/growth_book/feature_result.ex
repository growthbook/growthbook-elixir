defmodule GrowthBook.FeatureResult do
  @moduledoc """
  Struct holding results of an evaluated Feature.

  Holds the result of a feature evaluation, and is used to check if a feature is enabled, and
  optionally what data it provides, if that was configured.
  """

  @typedoc """
  Feature result

  The result of evaluating a `GrowthBook.Feature`. Has a number of keys:

  - **`value`** (`term()`) - The assigned value of the feature
  - **`on`**/**`on?`** (`boolean()`) - The assigned value cast to a boolean
  - **`off`**/**`off?`** (`boolean()`) - The assigned value cast to a boolean and then negated
  - **`source`** (`t:source/0`) - The source of the feature result
  - **`experiment`** (`t:GrowthBook.Experiment.t/0` or `nil`) - When source is `:experiment`, this
    will be an `%GrowthBook.Experiment{}` struct
  - **`experiment_result`** (`t:GrowthBook.ExperimentResult.t/0` or `nil`) - When source is
    `:experiment`, this will be an `%GrowthBook.ExperimentResult{}` struct
  """
  @type t() :: %__MODULE__{
          value: term(),
          source: source(),
          on: boolean(),
          on?: boolean(),
          off: boolean(),
          off?: boolean(),
          experiment: GrowthBook.Experiment.t() | nil,
          experiment_result: GrowthBook.ExperimentResult.t() | nil
        }

  @typedoc "The source of a feature"
  @type source() :: :unknown_feature | :default_value | :force | :experiment

  @enforce_keys [:value, :source, :on, :off, :on?, :off?]
  defstruct value: nil,
            on: nil,
            on?: nil,
            off: nil,
            off?: nil,
            source: :unknown_feature,
            experiment: nil,
            experiment_result: nil

  @doc "Helper function to convert string sources to atoms"
  @spec feature_source_from_string(String.t()) :: source()
  def feature_source_from_string("defaultValue"), do: :default_value
  def feature_source_from_string("force"), do: :force
  def feature_source_from_string("experiment"), do: :experiment
  def feature_source_from_string(_unknown), do: :unknown_feature
end
