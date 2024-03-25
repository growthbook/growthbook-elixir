defmodule ParentCondition do
  @moduledoc """
  A ParentCondition defines a prerequisite.

  Instead of evaluating against attributes, the condition evaluates against the returned value of the parent feature. The condition will always reference a "value" property. Here is an example of a gating prerequisite where the parent feature must be toggled on:

  ```
  %ParentCondition{
    id: "parent-feature",
    condition: %{
      "value": {
        "$exists": true
      }
    },
    gate: true
  }
  ```
  """

  alias GrowthBook.Condition
  @typedoc """
  ParentCondition

  A **ParentCondition** consists It consists of a parent feature's id (string), a condition (Condition), and an optional gate (boolean) flag.

  - **`id`** (`String.t()`) - parent feature's id
  - **`condition`** `GrowthBook.Condition.t()` - condition
  - **`gate`** `boolean()`
  """
  @type t() :: %__MODULE__{
     id: String.t(),
     condition: Condition.t(),
     gate: boolean()
  }

  defstruct [
    :id,
    :condition,
    gate: false
  ]

  def from_json(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      condition: map["condition"],
      gate: map["gate"] || false
    }
  end

end
