defmodule GrowthBook.Condition do
  @moduledoc """
  Functionality for evaluating conditions.

  You should not (have to) use any of these functions in your own application. They are documented
  for library developers only. Breaking changes in this module will not be considered breaking
  changes in the library's public API (or cause a minor/major semver update).
  """

  alias GrowthBook.Context

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

  Types are strict: when the attribute's type differs from the condition's type, a
  positive operator fails and its negation matches. `"10"` does not equal `10`, booleans
  are not ordered, and version operators need two strings or two numbers.

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
  - `$regexi`: like `$regex`, but case-insensitive

  ### Array expressions
  - `$in`: `left in right`
  - `$nin`: `left not in right`
  - `$ini` / `$nini`: like `$in` / `$nin`, but case-insensitive
  - `$elemMatch`: performs the given condition(s) of left for each element of right (with support for expressions)
  - `$all`: performs the given condition(s) of left for each element of right (without support support for expressions)
  - `$alli`: like `$all`, but case-insensitive
  - `$size`: `eval_contition_value(left, length(right))`

  ### Version comparison
  - `$veq`: `versions are equal`
  - `$vne`: `versions are not equal`
  - `$vlt`: `the first version is lesser than the second version`
  - `$vlte`: `the first version is lesser than or equal to the second version`
  - `$vgt`: `the first version is greater than the second version`
  - `$vgte`: `the first version is greater than or equal to the second version`

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
  def eval_condition(attributes, conditions) do
    # Every key must pass, including logical operators next to attribute paths
    Enum.all?(conditions, fn
      {"$or", conditions} -> eval_or(attributes, conditions)
      {"$nor", conditions} -> not eval_or(attributes, conditions)
      {"$and", conditions} -> eval_and(attributes, conditions)
      {"$not", condition} -> not eval_condition(attributes, condition)
      {path, condition} -> eval_condition_value(condition, get_path(attributes, path))
    end)
  end

  # Attribute type ≠ condition type never matches; there is no type coercion
  @spec eval_condition_value(condition_value(), term(), boolean()) :: boolean()
  defp eval_condition_value(condition, value, insensitive \\ false)

  defp eval_condition_value(condition, value, true)
       when is_binary(condition) and is_binary(value),
       do: String.downcase(value) == String.downcase(condition)

  defp eval_condition_value(condition, value, _insensitive)
       when is_binary(condition) or is_number(condition) or is_boolean(condition),
       do: get_type(value) == get_type(condition) and value == condition

  defp eval_condition_value(nil, value, _insensitive), do: value in [nil, :undefined]

  defp eval_condition_value(condition, value, _insensitive) do
    if is_list(condition) or not operator_object?(condition) do
      get_type(value) == get_type(condition) and condition == value
    else
      Enum.all?(condition, fn {operator, expected} ->
        eval_operator_condition(operator, value, expected)
      end)
    end
  end

  @version_operators ["$veq", "$vne", "$vlt", "$vlte", "$vgt", "$vgte"]
  @order_operators ["$lt", "$lte", "$gt", "$gte"]

  @spec eval_operator_condition(String.t(), term(), term()) :: boolean()
  defp eval_operator_condition("$eq", left, right), do: strict_equal?(left, right)
  defp eval_operator_condition("$ne", left, right), do: not strict_equal?(left, right)

  # Only two numbers or two strings are ordered; strings compare as text
  defp eval_operator_condition(op, left, right) when op in @order_operators do
    if orderable?(left, right) do
      case op do
        "$lt" -> left < right
        "$lte" -> left <= right
        "$gt" -> left > right
        "$gte" -> left >= right
      end
    else
      false
    end
  end

  # A type mismatch fails every version operator except `$vne`, its negation
  defp eval_operator_condition(op, left, right) when op in @version_operators do
    if orderable?(left, right) do
      lversion = padded_version(left)
      rversion = padded_version(right)

      case op do
        "$veq" -> lversion == rversion
        "$vne" -> lversion != rversion
        "$vlt" -> lversion < rversion
        "$vlte" -> lversion <= rversion
        "$vgt" -> lversion > rversion
        "$vgte" -> lversion >= rversion
      end
    else
      op == "$vne"
    end
  end

  defp eval_operator_condition("$exists", left, right),
    do: if(right, do: left not in [nil, :undefined], else: left in [nil, :undefined])

  defp eval_operator_condition(op, left, right) when op in ["$in", "$ini"] and is_list(right),
    do: in?(left, right, op == "$ini")

  defp eval_operator_condition(op, left, right) when op in ["$nin", "$nini"] and is_list(right),
    do: not in?(left, right, op == "$nini")

  defp eval_operator_condition(op, _left, _right) when op in ["$in", "$ini", "$nin", "$nini"],
    do: false

  defp eval_operator_condition("$not", left, right), do: not eval_condition_value(right, left)

  defp eval_operator_condition("$size", left, right) when is_list(left),
    do: eval_condition_value(right, length(left))

  defp eval_operator_condition("$size", _left, _right), do: false
  defp eval_operator_condition("$elemMatch", left, right), do: elem_match(left, right)

  defp eval_operator_condition(op, left, right)
       when op in ["$all", "$alli"] and is_list(left) and is_list(right) do
    Enum.all?(right, fn condition ->
      Enum.any?(left, &eval_condition_value(condition, &1, op == "$alli"))
    end)
  end

  defp eval_operator_condition(op, _left, _right) when op in ["$all", "$alli"], do: false

  defp eval_operator_condition(op, left, right)
       when op in ["$regex", "$regexi"] and is_binary(left) do
    case Regex.compile(right, if(op == "$regexi", do: "i", else: "")) do
      {:ok, regex} -> Regex.match?(regex, left)
      {:error, _err} -> false
    end
  end

  defp eval_operator_condition(op, _left, _right) when op in ["$regex", "$regexi"], do: false

  defp eval_operator_condition("$type", left, right), do: get_type(left) == right

  defp eval_operator_condition(operator, _left, _right) do
    IO.warn("Unknown operator: #{operator}")

    false
  end

  @spec orderable?(term(), term()) :: boolean()
  defp orderable?(left, right) when is_number(left) and is_number(right), do: true
  defp orderable?(left, right) when is_binary(left) and is_binary(right), do: true
  defp orderable?(_left, _right), do: false

  # Like JavaScript's `===`: arrays and objects are never equal, and a missing attribute is null
  @spec strict_equal?(term(), term()) :: boolean()
  defp strict_equal?(left, _right) when is_list(left) or is_map(left), do: false
  defp strict_equal?(:undefined, right), do: strict_equal?(nil, right)
  defp strict_equal?(left, :undefined), do: strict_equal?(left, nil)

  defp strict_equal?(left, right),
    do: get_type(left) == get_type(right) and left == right

  # An array attribute matches when any of its elements is in the list
  @spec in?(term(), list(), boolean()) :: boolean()
  defp in?(left, right, insensitive) when is_list(left),
    do: Enum.any?(left, &in?(&1, right, insensitive))

  defp in?(left, right, insensitive) do
    left = case_fold(left, insensitive)
    Enum.any?(right, &strict_equal?(left, case_fold(&1, insensitive)))
  end

  defp case_fold(value, true) when is_binary(value), do: String.downcase(value)
  defp case_fold(value, _insensitive), do: value

  @spec elem_match(term(), term()) :: boolean()
  defp elem_match(left, right) when is_list(left) do
    check =
      if operator_object?(right),
        do: &eval_condition_value(right, &1),
        else: &eval_condition(&1, right)

    # Skip only null elements; falsy values like 0, "" and false are still tested
    Enum.any?(left, &(&1 not in [nil, :undefined] and check.(&1)))
  end

  defp elem_match(_left, _right), do: false

  @spec eval_or(Context.attributes(), [t()]) :: boolean()
  defp eval_or(_attributes, []), do: true
  defp eval_or(attributes, conditions), do: Enum.any?(conditions, &eval_condition(attributes, &1))

  @spec eval_and(Context.attributes(), [t()]) :: boolean()
  defp eval_and(attributes, conditions),
    do: Enum.all?(conditions, &eval_condition(attributes, &1))

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

  @doc false
  @spec padded_version(String.t() | number()) :: String.t()
  def padded_version(n) when is_integer(n), do: padded_version(Integer.to_string(n))

  # Formats integral floats without a decimal, like JavaScript ("2.0" -> "2")
  def padded_version(n) when is_float(n) and n == trunc(n), do: padded_version(trunc(n))
  def padded_version(n) when is_float(n), do: padded_version(Float.to_string(n))
  def padded_version(""), do: padded_version("0")
  def padded_version("v" <> s), do: padded_version(s)

  def padded_version(s) when is_binary(s) do
    parts =
      String.split(s, "+")
      |> hd()
      |> String.split([".", "-"])

    # "~" sorts after any pre-release tag, so "1.0.0" > "1.0.0-beta"
    parts = if length(parts) == 3, do: parts ++ ["~"], else: parts

    # Joined like the JS SDK, so versions compare as one string
    parts
    |> Enum.map(fn s ->
      if Regex.match?(~r/^\d+$/, s),
        do: String.pad_leading(s, 5),
        else: s
    end)
    |> Enum.join("-")
  end
end
