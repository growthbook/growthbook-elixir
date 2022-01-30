defmodule GrowthBook.Condition do
  @moduledoc """
  Functionality for evaluating conditions.

  You should not (have to) use any of these functions in your own application. They are documented
  for library developers only. Breaking changes in this module will not be considered breaking
  changes in the library's public API (or cause a minor/major semver update).
  """

  alias GrowthBook.Context
  alias GrowthBook.Helpers

  @typedoc """
  Condition

  A condition is evaluated against `t:GrowthBook.Context.attributes/0` and used to target features/experiments
  to specific users.

  The syntax is inspired by MongoDB queries. Here is an example:

  ```
  %{
    "country" => "US",
    "browser" => %{
      "$in" => ["firefox", "chrome"]
    },
    "email" => %{
      "$not" => %{
        "$regex" => "@gmail.com$"
      }
    }
  }
  ```
  """
  @type t() :: map()

  @typedoc "A condition value"
  @type condition_value() :: term()

  @doc """
  Evaluates a condition against the given attributes.

  Conditions are MongoDB-query-like expressions.

  ## Available expressions:

  ### Expression groups
  - `$or`: Logical OR
  - `$nor`: Logical OR, but inverted
  - `$and`: Logical AND
  - `$not`: Logical NOT

  ### Simple expressions
  - `$eq`: `left == right`
  - `$ne`: `left != right`
  - `$lt`: `left < right`
  - `$lte`: `left <= right`
  - `$gt`: `left > right`
  - `$gte`: `left >= right`
  - `$exists`: `(left in [nil, :undefined]) != right`
  - `$type`: `typeof left == right`
  - `$regex`: `right |> Regex.compile!() |> Regex.match?(left)`

  ### Array expressions
  - `$in`: `left in right`
  - `$nin`: `left not in right`
  - `$elemMatch`: performs the given condition(s) of left for each element of right (with support for expressions)
  - `$all`: performs the given condition(s) of left for each element of right (without support support for expressions)
  - `$size`: `eval_contition_value(left, length(right))`

  ## Examples

      iex> GrowthBook.Condition.eval_condition(%{"hello" => "world"}, %{
      ...>   "hello" => "world"
      ...> })
      true

      iex> GrowthBook.Condition.eval_condition(%{"hello" => "world"}, %{
      ...>   "hello" => "optimizely"
      ...> })
      false
  """
  @spec eval_condition(Context.attributes(), t()) :: boolean()
  def eval_condition(attributes, %{"$or" => conditions}),
    do: eval_or(attributes, conditions)

  def eval_condition(attributes, %{"$nor" => conditions}),
    do: not eval_or(attributes, conditions)

  def eval_condition(attributes, %{"$and" => conditions}),
    do: eval_and(attributes, conditions)

  def eval_condition(attributes, %{"$not" => conditions}),
    do: not eval_condition(attributes, conditions)

  def eval_condition(attributes, conditions) do
    Enum.reduce_while(conditions, true, fn {path, condition}, acc ->
      if eval_condition_value(condition, get_path(attributes, path)) do
        {:cont, acc}
      else
        {:halt, false}
      end
    end)
  end

  @spec eval_condition_value(condition_value(), term()) :: boolean()
  defp eval_condition_value(condition, value) when is_binary(condition),
    do: to_string(value) == condition

  defp eval_condition_value(condition, value) when is_number(condition) and is_number(value),
    do: value == condition

  defp eval_condition_value(condition, value) when is_float(condition) and is_binary(value),
    do: {condition, ""} == Float.parse(value)

  defp eval_condition_value(condition, value) when is_integer(condition) and is_binary(value),
    do: {condition, ""} == Integer.parse(value)

  defp eval_condition_value(condition, value) when is_boolean(condition),
    do: Helpers.cast_boolish(value) == condition

  defp eval_condition_value(condition, value) do
    if is_list(condition) or not operator_object?(condition) do
      condition == value
    else
      Enum.reduce_while(condition, true, fn {operator, expected}, acc ->
        if eval_operator_condition(operator, value, expected) do
          {:cont, acc}
        else
          {:halt, false}
        end
      end)
    end
  end

  @spec eval_operator_condition(String.t(), term(), term()) :: boolean()
  defp eval_operator_condition("$eq", left, right), do: left == right
  defp eval_operator_condition("$ne", left, right), do: left != right

  # Perform JavaScript-like type coercion
  # see https://262.ecma-international.org/5.1/#sec-11.8.5
  @type_coercion_operators ["$lt", "$lte", "$gt", "$gte"]
  defp eval_operator_condition(operator, left, right)
       when is_number(left) and is_binary(right) and operator in @type_coercion_operators do
    case Float.parse(right) do
      {right, _rest} -> eval_operator_condition(operator, left, right)
      _unparseable -> false
    end
  end

  defp eval_operator_condition(operator, left, right)
       when is_number(right) and is_binary(left) and operator in @type_coercion_operators do
    case Float.parse(left) do
      {left, _rest} -> eval_operator_condition(operator, left, right)
      _unparseable -> false
    end
  end

  defp eval_operator_condition("$lt", left, right), do: left < right
  defp eval_operator_condition("$lte", left, right), do: left <= right
  defp eval_operator_condition("$gt", left, right), do: left > right
  defp eval_operator_condition("$gte", left, right), do: left >= right

  defp eval_operator_condition("$exists", left, right),
    do: if(right, do: left not in [nil, :undefined], else: left in [nil, :undefined])

  defp eval_operator_condition("$in", left, right), do: left in right
  defp eval_operator_condition("$nin", left, right), do: left not in right
  defp eval_operator_condition("$not", left, right), do: not eval_condition_value(right, left)

  defp eval_operator_condition("$size", left, right) when is_list(left),
    do: eval_condition_value(right, length(left))

  defp eval_operator_condition("$size", _left, _right), do: false
  defp eval_operator_condition("$elemMatch", left, right), do: elem_match(left, right)

  defp eval_operator_condition("$all", left, right) when is_list(left) and is_list(right) do
    Enum.reduce_while(right, true, fn condition, acc ->
      if Enum.any?(left, &eval_condition_value(condition, &1)) do
        {:cont, acc}
      else
        {:halt, false}
      end
    end)
  end

  defp eval_operator_condition("$all", _left, _right), do: false

  defp eval_operator_condition("$regex", left, right) do
    case Regex.compile(right) do
      {:ok, regex} -> Regex.match?(regex, left)
      {:error, _err} -> false
    end
  end

  defp eval_operator_condition("$type", left, right), do: get_type(left) == right

  defp eval_operator_condition(operator, _left, _right) do
    IO.warn("Unknown operator: #{operator}")

    false
  end

  @spec elem_match(term(), term()) :: boolean()
  defp elem_match(left, right) when is_list(left) do
    check =
      if operator_object?(right),
        do: &eval_condition_value(right, &1),
        else: &eval_condition(&1, right)

    Enum.reduce_while(left, false, fn value, acc ->
      if check.(value) do
        {:halt, true}
      else
        {:cont, acc}
      end
    end)
  end

  defp elem_match(_left, _right), do: false

  @spec eval_or(Context.attributes(), [t()]) :: boolean()
  defp eval_or(_attributes, []), do: true
  defp eval_or(attributes, [condition]), do: eval_condition(attributes, condition)

  defp eval_or(attributes, [condition | conditions]),
    do: eval_condition(attributes, condition) or eval_or(attributes, conditions)

  @spec eval_and(Context.attributes(), [t()]) :: boolean()
  defp eval_and(_attributes, []), do: true

  defp eval_and(attributes, [condition | conditions]),
    do: eval_condition(attributes, condition) and eval_and(attributes, conditions)

  @spec operator_object?(t()) :: boolean()
  defp operator_object?(condition) when is_map(condition) do
    Enum.all?(condition, fn
      {"$" <> _key, _value} -> true
      _non_operator -> false
    end)
  end

  defp operator_object?(_condition), do: false

  # Given attributes and a dot-separated path string, returns the value of
  # the attribute at the path
  @doc false
  @spec get_path(map(), String.t()) :: term() | :undefined
  def get_path(map, path) do
    path = String.split(path, ".")
    do_get_path(map, path)
  end

  defp do_get_path(value, []), do: value

  defp do_get_path(value, [key | path]) when is_map_key(value, key) do
    %{^key => next_value} = value
    do_get_path(next_value, path)
  end

  defp do_get_path(_value, _path), do: :undefined

  # Returns the data type of the passed argument
  @doc false
  @spec get_type(term()) :: String.t()
  def get_type(attribute_value) when is_binary(attribute_value), do: "string"
  def get_type(attribute_value) when is_number(attribute_value), do: "number"
  def get_type(attribute_value) when is_boolean(attribute_value), do: "boolean"
  def get_type(attribute_value) when is_list(attribute_value), do: "array"
  def get_type(attribute_value) when is_map(attribute_value), do: "object"
  def get_type(attribute_value) when is_nil(attribute_value), do: "null"
  def get_type(:undefined), do: "undefined"
  def get_type(_attribute_value), do: "unknown"
end
