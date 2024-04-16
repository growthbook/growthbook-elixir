defmodule GrowthBook.Feature do
  @moduledoc """
  Struct holding Feature configuration.

  Holds the feature's default value, along with the feature's rules.
  """

  alias GrowthBook.FeatureRule

  @typedoc """
  Feature

  A **Feature** consists of a default value plus rules that can override the default.

  - **default_value** (`t:term/0`) - The default value (should use `nil` if not specified)
  - **rules** (list of `t:GrowthBook.FeatureRule.t/0`) - List of rules that determine when and
    how the `default_value` gets overridden
  """
  @type t() :: %__MODULE__{
          default_value: term() | nil,
          rules: [FeatureRule.t()] | nil
        }

  defstruct [
    :default_value,
    :rules
  ]
end
