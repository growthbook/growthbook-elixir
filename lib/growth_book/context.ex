defmodule GrowthBook.Context do
  @moduledoc """
  Stores feature and experiment context.

  Holds the state of features, experiment overrides, attributes and other "global" state. The
  context works similar to `%Plug.Conn{}`, as it is created for each request and passed along
  when working with features and experiments.
  """

  alias GrowthBook.Feature
  alias GrowthBook.ExperimentOverride

  @typedoc """
  Context

  **Context** struct. Has a number of optional properties:

  - **`enabled?`** (`boolean()`) - Switch to globally disable all experiments. Default `true`.
  - **`attributes`** (`t:attributes/0`) - Map of user attributes that are used
    to assign variations
  - **`url`** (`String.t()`) - The URL of the current page
  - **`features`** (`t:features/0`) - Feature definitions (usually pulled from an API or cache)
  - **`forced_variations`** (`t:forced_variations/0`) - Force specific experiments to always assign
    a specific variation (used for QA)
  - **`qa_mode?`** (`boolean()`) - If `true`, random assignment is disabled and only explicitly
    forced variations are used.
  """
  @type t() :: %__MODULE__{
          attributes: attributes(),
          features: features(),
          overrides: experiment_overrides(),
          forced_variations: forced_variations(),
          url: String.t() | nil,
          enabled?: boolean(),
          qa_mode?: boolean()
        }

  @typedoc """
  Attributes

  **Attributes** are an arbitrary JSON map containing user and request attributes. Here's an example:

  ```
  %{
    "id" => "123",
    "anonId" => "abcdef",
    "company" => "growthbook",
    "url" => "/pricing",
    "country" => "US",
    "browser" => "firefox",
    "age" => 25,
    "beta" => true,
    "account" => %{
      "plan" => "team",
      "seats" => 10
    }
  }
  ```
  """
  @type attributes() :: %{required(String.t()) => term()}

  @typedoc """
  Experiment overrides

  A map with feature names as keys and `%ExperimentOverride{}` struct as values.
  """
  @type experiment_overrides() :: %{required(GrowthBook.feature_key()) => ExperimentOverride.t()}

  @typedoc """
  Features

  A map of `%Feature{}` structs. Keys are string ids for the features.

  ```
  %{
    "feature-1" => %Feature{
      default_value: false
    },
    "my_other_feature" => %Feature{
      default_value: 1,
      rules: [
        %FeatureRule{
          force: 2
        }
      ]
    }
  }
  ```
  """
  @type features() :: %{required(GrowthBook.feature_key()) => Feature.t()}

  @typedoc """
  Forced variations map

  A hash or map that forces an `GrowthBook.Experiment` to always assign a specific variation.
  Useful for QA.

  Keys are the experiment key, values are the list index of the variation. For example:

  ```
  %{
    "my-test" => 0,
    "other-test" => 1
  }
  ```
  """
  @type forced_variations() :: %{required(GrowthBook.feature_key()) => integer()}

  defstruct attributes: %{},
            features: %{},
            overrides: %{},
            forced_variations: %{},
            url: nil,
            enabled?: true,
            qa_mode?: false
end
