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
    do: js_string(value) == condition

  defp eval_condition_value(condition, value) when is_number(condition),
    do: js_number(value) == condition

  defp eval_condition_value(condition, value) when is_boolean(condition),
    do: value not in [nil, :undefined] and js_truthy?(value) == condition

  defp eval_condition_value(nil, value), do: value in [nil, :undefined]

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

  defp eval_operator_condition(operator, left, right)
       when is_number(right) and is_binary(left) and operator in @type_coercion_operators do
    case Float.parse(left) do
      {left, _rest} -> eval_operator_condition(operator, left, right)
      _unparseable -> false
    end
  end

  defp eval_operator_condition(operator, left, right)
       when is_number(right) and left in [nil, :undefined] and
              operator in @type_coercion_operators do
    eval_operator_condition(operator, 0, right)
  end

  defp eval_operator_condition(operator, left, right)
       when is_number(left) and right in [nil, :undefined] and
              operator in @type_coercion_operators do
    eval_operator_condition(operator, left, 0)
  end

  defp eval_operator_condition("$lt", left, right), do: left < right
  defp eval_operator_condition("$lte", left, right), do: left <= right
  defp eval_operator_condition("$gt", left, right), do: left > right
  defp eval_operator_condition("$gte", left, right), do: left >= right

  defp eval_operator_condition(op, left, right)
       when op in ["$veq", "$vne", "$vlt", "$vlte", "$vgt", "$vgte"] do
    lversion = padded_version(left)
    rversion = padded_version(right)

    lversion = Enum.join(lversion, "-")
    rversion = Enum.join(rversion, "-")

    case op do
      "$veq" -> lversion == rversion
      "$vne" -> lversion != rversion
      "$vlt" -> lversion < rversion
      "$vlte" -> lversion <= rversion
      "$vgt" -> lversion > rversion
      "$vgte" -> lversion >= rversion
    end
  end

  defp eval_operator_condition("$exists", left, right),
    do: if(right, do: left not in [nil, :undefined], else: left in [nil, :undefined])

  defp eval_operator_condition("$in", _, right) when not is_list(right), do: false

  defp eval_operator_condition("$in", left, right) when is_list(left) do
    Enum.any?(left, &(&1 in right))
  end

  defp eval_operator_condition("$in", left, right), do: left in right
  defp eval_operator_condition("$nin", _, right) when not is_list(right), do: false

  defp eval_operator_condition("$nin", left, right),
    do: not eval_operator_condition("$in", left, right)

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

  defp eval_operator_condition("$regex", left, right), do: regex_match?(left, right, "")
  defp eval_operator_condition("$regexi", left, right), do: regex_match?(left, right, "i")

  defp eval_operator_condition("$type", left, right), do: get_type(left) == right

  defp eval_operator_condition(operator, _left, _right) do
    IO.warn("Unknown operator: #{operator}")

    false
  end

  @spec regex_match?(term(), term(), String.t()) :: boolean()
  defp regex_match?(left, right, options) when is_binary(right) do
    case Regex.compile(right, options) do
      {:ok, regex} -> Regex.match?(regex, js_string(left))
      {:error, _err} -> false
    end
  end

  defp regex_match?(_left, _right, _options), do: false

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

  @doc false
  @spec padded_version(term()) :: [String.t()]
  def padded_version(n) when is_number(n), do: padded_version(js_string(n))

  def padded_version(s) when is_binary(s) and s != "" do
    parts =
      s
      |> String.replace(~r/^v/, "")
      |> String.split("+")
      |> hd()
      |> String.split([".", "-"])
      |> Enum.map(fn s ->
        if Regex.match?(~r/^\d+$/, s),
          do: String.pad_leading(s, 5),
          else: s
      end)

    if length(parts) == 3,
      do: parts ++ ["~"],
      else: parts
  end

  def padded_version(_other), do: padded_version("0")

  # Converts a value to a string the way JavaScript's `String(value)` does.
  # A missing attribute is `null` in the JS SDK, so `:undefined` converts to "null" too.
  @doc false
  @spec js_string(term()) :: String.t()
  def js_string(value) when is_binary(value), do: value
  def js_string(value) when value in [nil, :undefined], do: "null"
  def js_string(value) when is_boolean(value), do: to_string(value)
  def js_string(value) when is_integer(value), do: Integer.to_string(value)
  def js_string(value) when is_float(value), do: js_float_string(value)
  def js_string(value) when is_map(value), do: "[object Object]"

  def js_string(value) when is_list(value) do
    Enum.map_join(value, ",", fn
      element when element in [nil, :undefined] -> ""
      element -> js_string(element)
    end)
  end

  def js_string(value), do: to_string(value)

  # ECMAScript Number::toString, using Elixir's shortest round-trip digits
  defp js_float_string(value) when value == 0, do: "0"
  defp js_float_string(value) when value < 0, do: "-" <> js_float_string(-value)

  defp js_float_string(value) do
    {mantissa, exponent} =
      case String.split(Float.to_string(value), "e") do
        [mantissa, exponent] -> {mantissa, String.to_integer(exponent)}
        [mantissa] -> {mantissa, 0}
      end

    [int, frac] = String.split(mantissa, ".")
    all_digits = int <> frac
    digits = String.trim_leading(all_digits, "0")
    n = String.length(int) + exponent - (String.length(all_digits) - String.length(digits))
    digits = String.trim_trailing(digits, "0")
    k = String.length(digits)

    cond do
      k <= n and n <= 21 ->
        digits <> String.duplicate("0", n - k)

      0 < n and n <= 21 ->
        String.slice(digits, 0, n) <> "." <> String.slice(digits, n..-1//1)

      -6 < n and n <= 0 ->
        "0." <> String.duplicate("0", -n) <> digits

      true ->
        sign = if n - 1 < 0, do: "-", else: "+"
        exponent = "e" <> sign <> Integer.to_string(abs(n - 1))

        case digits do
          <<first::binary-size(1)>> -> first <> exponent
          <<first::binary-size(1), rest::binary>> -> first <> "." <> rest <> exponent
        end
    end
  end

  # Converts a value to a number the way JavaScript's `value * 1` does; returns `:nan` for NaN.
  @doc false
  @spec js_number(term()) :: number() | :nan
  def js_number(value) when is_number(value), do: value
  def js_number(value) when value in [nil, :undefined, false], do: 0
  def js_number(true), do: 1
  def js_number(value) when is_list(value), do: js_number(js_string(value))

  def js_number(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        0

      match = Regex.run(~r/^0([xob])([0-9a-f]+)$/i, value) ->
        [_, base, digits] = match
        base = %{"x" => 16, "o" => 8, "b" => 2}[String.downcase(base)]

        case Integer.parse(digits, base) do
          {number, ""} -> number
          _invalid -> :nan
        end

      match = Regex.run(~r/^([+-]?)(\d*)(?:\.(\d*))?(?:e([+-]?\d+))?$/i, value) ->
        parse_js_decimal(match)

      true ->
        :nan
    end
  end

  def js_number(_value), do: :nan

  defp parse_js_decimal([_, _sign, ""]), do: :nan
  defp parse_js_decimal([_, _sign, "", "" | _exponent]), do: :nan

  defp parse_js_decimal([_, sign, int | rest]) do
    {frac, exponent} =
      case rest do
        [] -> {"", ""}
        [frac] -> {frac, ""}
        [frac, exponent] -> {frac, exponent}
      end

    int = if int == "", do: "0", else: int
    frac = if frac == "", do: "0", else: frac
    exponent = if exponent == "", do: "0", else: exponent

    case Float.parse(sign <> int <> "." <> frac <> "e" <> exponent) do
      {number, ""} -> number
      _invalid -> :nan
    end
  rescue
    ArgumentError -> :nan
  end

  # JavaScript truthiness
  defp js_truthy?(value) when value in [nil, :undefined, false, ""], do: false
  defp js_truthy?(value) when is_number(value), do: value != 0
  defp js_truthy?(_value), do: true
end
