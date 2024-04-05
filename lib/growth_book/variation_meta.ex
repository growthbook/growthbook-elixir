defmodule GrowthBook.VariationMeta do
  @moduledoc """
  Meta info about an experiment variation.
  """

  @typedoc """
  VariationMeta

  Has the following properties:

  - **`key`** (`String.t()`) - A unique key for this variation (optional)
  - **`name`** (`String.t()`) - A human-readable name for this variation (optional)
  - **`passthrough?`** (`boolean()`) - Used to implement holdout groups (optional)
  """

  @type t() :: %__MODULE__{
    key: String.t() | nil,
    name: String.t() | nil,
    passthrough?: boolean()
  }

  defstruct [
    :key,
    :name,
    passthrough?: false
  ]

  def from_json(map) when is_map(map) do
    %__MODULE__{
      key: map["key"],
      name: map["name"],
      passthrough?: map["passthrough"] || false
    }
  end
end
