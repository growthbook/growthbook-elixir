defmodule GrowthBook.ParentCondition do
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

  alias GrowthBook.{
    Context,
    Condition,
    FeatureResult,
    ParentCondition
  }

  alias ParentCondition.{
    CyclingError,
    PrerequisiteError
  }

  require Logger

  defmodule CyclingError do
    @type t() :: %__MODULE__{message: String.t()}
    defexception [:message]
  end

  defmodule PrerequisiteError do
    @type t() :: %__MODULE__{message: String.t()}
    defexception [:message]
  end

  @typedoc """
  ParentCondition

  A **ParentCondition** consists of a parent feature's id (string), a condition (Condition), and an optional gate (boolean) flag.

  - **`id`** (`String.t()`) - parent feature's id
  - **`condition`** `GrowthBook.Condition.t()` - condition
  - **`gate`** `boolean()`
  """
  @type t() :: %__MODULE__{
     id: String.t(),
     condition: Condition.t(),
     gate: boolean()
  }

  @type error() :: CyclingError.t() | PrerequisiteError.t()

  defstruct [
    :id,
    :condition,
    gate: false
  ]

  @spec from_json(map()) :: ParentCondition.t()
  def from_json(map) when is_map(map) do
    %ParentCondition{
      id: map["id"],
      condition: map["condition"],
      gate: map["gate"] || false
    }
  end

  @spec eval( Context.t(), [ParentCondition.t()] | nil, [String.t()]) :: true | false | {:error, ParentCondition.error()}
  def eval(_, [], _), do: true
  def eval(_, nil, _), do: true
  def eval(%Context{} = context, [parent_condition | rest], path) do
    %ParentCondition{
      id: parent_feature_id,
      gate:  gate,
      condition: condition
    } = parent_condition

    if parent_feature_id in path do
      error = "Cycling feature prerequisite: #{parent_feature_id}, path: #{inspect(path)}"
      Logger.debug(error)
      {:error, %CyclingError{message: error}}
    else
      case GrowthBook.feature(context, parent_feature_id, path) do
        %FeatureResult{source: :cyclic_prerequisite} ->
          error = "Cycling feature prerequisite: #{parent_feature_id}, path: #{inspect(path)}"
          {:error, %CyclingError{message: error}}
        %FeatureResult{value: value} ->
          case Condition.eval_condition(%{"value" => value}, condition) do
            true ->
              eval(context, rest, path)
            false when gate == true ->
              error = "Feature prerequisite missing: #{parent_feature_id}, path: #{inspect(path)}"
              Logger.debug(error)
              {:error, %PrerequisiteError{message: error}}
            false ->
              false
          end
      end
    end
  end
end
