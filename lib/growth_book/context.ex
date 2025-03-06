defmodule GrowthBook.Context do
  @moduledoc """
  Stores feature and experiment context.

  Holds the state of features, attributes and other "global" state. The
  context works similar to `%Plug.Conn{}`, as it is created for each request and passed along
  when working with features and experiments.
  """

  alias GrowthBook.Feature

  @typedoc """
  Context

  **Context** struct. Has a number of optional properties:

  - **`enabled?`** (`t:boolean/0`) - Switch to globally disable all experiments. Default `true`.
  - **`attributes`** (`t:attributes/0`) - Map of user attributes that are used
    to assign variations
  - **`url`** (`t:String.t/0`) - The URL of the current page
  - **`features_provider`** (`t:features_provider/0`) - Function that returns latest features
  - **`forced_variations`** (`t:forced_variations/0`) - Force specific experiments to always assign
    a specific variation (used for QA)
  - **`qa_mode?`** (`t:boolean/0`) - If `true`, random assignment is disabled and only explicitly
    forced variations are used.
  """
  @type t() :: %__MODULE__{
          enabled?: boolean(),
          attributes: attributes() | nil,
          url: String.t() | nil,
          features_provider: (-> map()),
          forced_variations: forced_variations(),
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
  @type attributes() :: %{String.t() => term()}

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
  @type forced_variations() :: %{GrowthBook.feature_key() => integer()}

  @typedoc """
  Features Provider

  A function that returns a map of `%Feature{}` structs. Keys are string ids for the features.
  The function will be called each time features are needed, ensuring the latest features are used.

  The returned map should be in this format:
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
  @type features_provider() :: (-> %{GrowthBook.feature_key() => Feature.t()})

  defstruct attributes: %{},
            features_provider: fn -> %{} end,
            enabled?: true,
            url: nil,
            qa_mode?: false,
            forced_variations: %{}

  @doc false
  def get_features(%__MODULE__{features_provider: provider}) do
    provider.()
  end
end
