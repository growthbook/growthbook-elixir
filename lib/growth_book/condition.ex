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
  @spec eval_condition(Context.attributes(), t(), saved_groups()) :: boolean()
  def eval_condition(attributes, conditions, saved_groups \\ %{}) do
    # An unknown result (an operator or saved group type this SDK doesn't support) fails
    eval_with_context(attributes, conditions, new_context(saved_groups)) == true
  end

  @typedoc """
  Saved groups from the payload's `savedGroups` key, by id. An entry is a bare list of values,
  or a typed map: `%{"type" => "list", "attributeKey" => ..., "values" => [...]}` or
  `%{"type" => "condition", "condition" => %{...}}`.
  """
  @type saved_groups() :: %{optional(String.t()) => term()}

  # true or false, or :unknown when the result depends on an operator or saved group type this
  # SDK doesn't support. Public functions treat :unknown as failing.
  @typep result() :: boolean() | :unknown

  # Keys a condition can have that aren't attributes, besides `$not`, which is also an operator
  # on a value
  @condition_operators ["$or", "$nor", "$and", "$savedGroup"]

  defp new_context(saved_groups), do: %{saved_groups: saved_groups || %{}, visited: MapSet.new()}

  defp negate(:unknown), do: :unknown
  defp negate(result), do: not result

  # One failing entry decides the result, wherever an unknown one is
  @spec all_results(Enumerable.t(), (term() -> result())) :: result()
  defp all_results(items, fun) do
    Enum.reduce_while(items, true, fn item, acc ->
      case fun.(item) do
        false -> {:halt, false}
        :unknown -> {:cont, :unknown}
        true -> {:cont, acc}
      end
    end)
  end

  # One passing entry decides the result, wherever an unknown one is
  @spec any_result(Enumerable.t(), (term() -> result())) :: result()
  defp any_result(items, fun) do
    Enum.reduce_while(items, false, fn item, acc ->
      case fun.(item) do
        true -> {:halt, true}
        :unknown -> {:cont, :unknown}
        false -> {:cont, acc}
      end
    end)
  end

  @spec eval_with_context(Context.attributes(), t(), map()) :: result()
  defp eval_with_context(attributes, conditions, ctx) do
    # Every key must pass, including logical operators next to attribute paths
    all_results(conditions, fn
      {"$or", conditions} -> eval_or(attributes, conditions, ctx)
      {"$nor", conditions} -> negate(eval_or(attributes, conditions, ctx))
      {"$and", conditions} -> eval_and(attributes, conditions, ctx)
      {"$not", condition} -> negate(eval_with_context(attributes, condition, ctx))
      {"$savedGroup", reference} -> eval_saved_group(attributes, reference, ctx, nil)
      {path, condition} -> eval_condition_value(condition, get_path(attributes, path), ctx)
    end)
  end

  @doc """
  Partially evaluates a condition when only some attributes are known, e.g. on a server.

  Attributes missing from `attributes` are unknown, and so is any nested path. Returns a boolean
  once the result can't depend on unknown attributes, otherwise the condition minus every branch
  that is already decided. A condition that raises, such as a malformed one, is returned as is.

  ## Examples

      iex> GrowthBook.Condition.prune_condition(%{"id" => "123"}, %{
      ...>   "id" => %{"$ne" => "789"},
      ...>   "country" => "US"
      ...> })
      %{"country" => "US"}
  """
  @spec prune_condition(Context.attributes(), t(), saved_groups()) :: t() | boolean()
  def prune_condition(attributes, condition, saved_groups \\ %{}) do
    prune_with_context(attributes, condition, new_context(saved_groups))
  end

  @doc false
  # Prunes the saved group a reference points to. Returns its result once decided, :unknown
  # while it depends on an unknown attribute, or its condition minus every decided branch.
  @spec prune_saved_group(Context.attributes(), term(), saved_groups()) :: result() | t()
  def prune_saved_group(attributes, reference, saved_groups) do
    eval_saved_group(attributes, reference, new_context(saved_groups), &prune_with_context/3)
  end

  # A condition that raises stays as written. Evaluating it fails as a whole, so no part of it
  # can be decided.
  defp prune_with_context(attributes, condition, ctx) do
    prune_entries(attributes, condition, ctx)
  rescue
    _error -> condition
  end

  defp prune_entries(attributes, condition, ctx) do
    result =
      Enum.reduce_while(condition, %{}, fn {key, value}, acc ->
        result =
          case key do
            op when op in ["$or", "$nor", "$and"] ->
              prune_list(attributes, value, ctx, op != "$and")

            "$not" ->
              prune_entries(attributes, value, ctx)

            "$savedGroup" ->
              # Keep an undecided reference as is rather than inlining the group
              case eval_saved_group(attributes, value, ctx, &prune_entries/3) do
                decided when is_boolean(decided) -> decided
                _undecided -> :unknown
              end

            path ->
              # Unknown when the attribute is unknown, or the value uses an operator this SDK
              # doesn't support, which the client's SDK may
              if known?(attributes, path),
                do: eval_condition_value(value, get_path(attributes, path), ctx),
                else: :unknown
          end

        # `$not` and `$nor` pass when what they hold fails
        result =
          if key in ["$not", "$nor"] and is_boolean(result), do: not result, else: result

        # One failing entry fails the whole condition, and a passing one is dropped
        case result do
          false -> {:halt, false}
          true -> {:cont, acc}
          :unknown -> {:cont, Map.put(acc, key, value)}
          pruned -> {:cont, Map.put(acc, key, pruned)}
        end
      end)

    if result == %{}, do: true, else: result
  end

  # Prunes an `$or` (or an `$and`) list. Returns the conditions still undecided, or the list's
  # result once there are none.
  defp prune_list(attributes, conditions, ctx, or?) when is_list(conditions) do
    result =
      Enum.reduce_while(conditions, [], fn condition, acc ->
        case prune_entries(attributes, condition, ctx) do
          # One passing condition decides an `$or`, and one failing condition an `$and`
          true when or? -> {:halt, true}
          false when not or? -> {:halt, false}
          decided when is_boolean(decided) -> {:cont, acc}
          pruned -> {:cont, [pruned | acc]}
        end
      end)

    case result do
      decided when is_boolean(decided) -> decided
      # Every condition failed an `$or`, or passed an `$and`. Like `eval_or`, an empty `$or`
      # passes.
      [] -> if or?, do: conditions == [], else: true
      pruned -> Enum.reverse(pruned)
    end
  end

  # A nested path is unknown, since the server may only have part of the object
  defp known?(attributes, path),
    do: is_map(attributes) and not String.contains?(path, ".") and Map.has_key?(attributes, path)

  # Resolves a `$savedGroup` reference. Anything unrecognized matches nobody. With `prune`, an
  # unknown attribute leaves the result undecided.
  defp eval_saved_group(attributes, reference, ctx, prune)

  defp eval_saved_group(attributes, %{"id" => id} = reference, ctx, prune) when is_binary(id) do
    # Falling back to the entry's attribute would check a different population
    with false <- MapSet.member?(ctx.visited, id),
         {:ok, attribute_key} <- reference_attribute_key(reference),
         %{} = entry <- Map.get(ctx.saved_groups, id) do
      eval_saved_group_entry(attributes, id, attribute_key, entry, ctx, prune)
    else
      _invalid -> false
    end
  end

  defp eval_saved_group(_attributes, _reference, _ctx, _prune), do: false

  defp reference_attribute_key(reference) do
    case Map.fetch(reference, "attributeKey") do
      :error -> {:ok, nil}
      {:ok, key} when is_binary(key) -> {:ok, key}
      {:ok, _not_a_string} -> :error
    end
  end

  defp eval_saved_group_entry(
         attributes,
         _id,
         attribute_key,
         %{"type" => "list"} = entry,
         _ctx,
         prune
       ) do
    # The override wins over the entry's own attribute
    key = attribute_key || entry["attributeKey"]

    cond do
      not is_binary(key) or not is_list(entry["values"]) -> false
      prune && not known?(attributes, key) -> :unknown
      true -> in?(get_path(attributes, key), entry["values"], false)
    end
  end

  defp eval_saved_group_entry(
         attributes,
         id,
         _attribute_key,
         %{"type" => "condition"} = entry,
         ctx,
         prune
       ) do
    # A condition group has no single attribute, so any override is ignored. Its own id is
    # visited only below it, so sibling groups don't see each other's ids.
    case entry["condition"] do
      %{} = condition ->
        ctx = %{ctx | visited: MapSet.put(ctx.visited, id)}

        if prune,
          do: prune.(attributes, condition, ctx),
          else: eval_with_context(attributes, condition, ctx)

      _malformed ->
        false
    end
  end

  # A group type added after this SDK was built
  defp eval_saved_group_entry(_attributes, _id, _attribute_key, _entry, _ctx, _prune),
    do: :unknown

  # Attribute type ≠ condition type never matches; there is no type coercion
  @spec eval_condition_value(condition_value(), term(), map(), boolean()) :: result()
  defp eval_condition_value(condition, value, ctx, insensitive \\ false)

  defp eval_condition_value(condition, value, _ctx, true)
       when is_binary(condition) and is_binary(value),
       do: String.downcase(value) == String.downcase(condition)

  defp eval_condition_value(condition, value, _ctx, _insensitive)
       when is_binary(condition) or is_number(condition) or is_boolean(condition),
       do: get_type(value) == get_type(condition) and value == condition

  defp eval_condition_value(nil, value, _ctx, _insensitive), do: value in [nil, :undefined]

  defp eval_condition_value(condition, value, ctx, _insensitive) do
    # An empty map has no operators, so it passes
    if is_list(condition) or not operator_object?(condition) do
      get_type(value) == get_type(condition) and condition == value
    else
      all_results(condition, fn {operator, expected} ->
        eval_operator_condition(operator, value, expected, ctx)
      end)
    end
  end

  @version_operators ["$veq", "$vne", "$vlt", "$vlte", "$vgt", "$vgte"]
  @order_operators ["$lt", "$lte", "$gt", "$gte"]

  @spec eval_operator_condition(String.t(), term(), term(), map()) :: result()
  defp eval_operator_condition("$eq", left, right, _ctx), do: strict_equal?(left, right)
  defp eval_operator_condition("$ne", left, right, _ctx), do: not strict_equal?(left, right)

  # Only two numbers or two strings are ordered; strings compare as text
  defp eval_operator_condition(op, left, right, _ctx) when op in @order_operators do
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
  defp eval_operator_condition(op, left, right, _ctx) when op in @version_operators do
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

  defp eval_operator_condition("$exists", left, right, _ctx),
    do: if(right, do: left not in [nil, :undefined], else: left in [nil, :undefined])

  defp eval_operator_condition(op, left, right, _ctx)
       when op in ["$in", "$ini"] and is_list(right),
       do: in?(left, right, op == "$ini")

  defp eval_operator_condition(op, left, right, _ctx)
       when op in ["$nin", "$nini"] and is_list(right),
       do: not in?(left, right, op == "$nini")

  defp eval_operator_condition(op, _left, _right, _ctx)
       when op in ["$in", "$ini", "$nin", "$nini"],
       do: false

  defp eval_operator_condition(op, left, group_id, ctx) when op in ["$inGroup", "$notInGroup"] do
    entry = saved_group_entry(ctx.saved_groups, group_id)

    if new_group_type?(entry) do
      :unknown
    else
      case saved_group_values(entry) do
        # No values means matching nobody. An empty list would pass everyone.
        nil -> false
        values when op == "$inGroup" -> in?(left, values, false)
        values -> not in?(left, values, false)
      end
    end
  end

  defp eval_operator_condition("$not", left, right, ctx),
    do: negate(eval_condition_value(right, left, ctx))

  defp eval_operator_condition("$size", left, right, ctx) when is_list(left),
    do: eval_condition_value(right, length(left), ctx)

  defp eval_operator_condition("$size", _left, _right, _ctx), do: false
  defp eval_operator_condition("$elemMatch", left, right, ctx), do: elem_match(left, right, ctx)

  defp eval_operator_condition(op, left, right, ctx)
       when op in ["$all", "$alli"] and is_list(left) and is_list(right) do
    all_results(right, fn condition ->
      any_result(left, &eval_condition_value(condition, &1, ctx, op == "$alli"))
    end)
  end

  defp eval_operator_condition(op, _left, _right, _ctx) when op in ["$all", "$alli"], do: false

  defp eval_operator_condition(op, left, right, _ctx)
       when op in ["$regex", "$regexi"] and is_binary(left) and is_binary(right) do
    case Regex.compile(right, if(op == "$regexi", do: "i", else: "")) do
      {:ok, regex} -> Regex.match?(regex, left)
      {:error, _err} -> false
    end
  end

  defp eval_operator_condition(op, _left, _right, _ctx) when op in ["$regex", "$regexi"],
    do: false

  defp eval_operator_condition("$type", left, right, _ctx), do: get_type(left) == right

  # Keys this SDK knows, but on a condition rather than on a value, where they never match
  defp eval_operator_condition(op, _left, _right, _ctx) when op in @condition_operators,
    do: false

  defp eval_operator_condition(operator, _left, _right, _ctx) do
    IO.warn("Unknown operator: #{operator}")

    :unknown
  end

  # An unknown id has always behaved like an empty list
  defp saved_group_entry(saved_groups, group_id) do
    case Map.fetch(saved_groups, group_id) do
      {:ok, entry} -> entry
      :error -> :absent
    end
  end

  defp saved_group_values(:absent), do: []
  defp saved_group_values(values) when is_list(values), do: values

  # These operators take their attribute from the condition they sit on
  defp saved_group_values(%{"type" => "list", "values" => values}) when is_list(values),
    do: values

  # A condition group, a malformed entry, or an unknown type
  defp saved_group_values(_entry), do: nil

  # A saved group type added after this SDK was built
  defp new_group_type?(%{"type" => type}) when type in ["list", "condition"], do: false
  defp new_group_type?(%{}), do: true
  defp new_group_type?(_entry), do: false

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

  # An array attribute matches when any of its own elements is in the list. Nested arrays
  # are not searched, and never equal anything.
  @spec in?(term(), list(), boolean()) :: boolean()
  defp in?(left, right, insensitive) when is_list(left),
    do: Enum.any?(left, &member?(&1, right, insensitive))

  defp in?(left, right, insensitive), do: member?(left, right, insensitive)

  defp member?(left, right, insensitive) do
    left = case_fold(left, insensitive)
    Enum.any?(right, &strict_equal?(left, case_fold(&1, insensitive)))
  end

  defp case_fold(value, true) when is_binary(value), do: String.downcase(value)
  defp case_fold(value, _insensitive), do: value

  @spec elem_match(term(), term(), map()) :: result()
  defp elem_match(left, right, ctx) when is_list(left) do
    # Operators test each element itself. A condition, including one that only uses `$or`,
    # `$and`, `$nor`, or `$savedGroup`, tests each element's fields.
    check =
      if operator_object?(right) and
           not Enum.any?(Map.keys(right), &(&1 in @condition_operators)),
         do: &eval_condition_value(right, &1, ctx),
         else: &eval_with_context(&1, right, ctx)

    # Skip only null elements; falsy values like 0, "" and false are still tested
    left
    |> Enum.reject(&(&1 in [nil, :undefined]))
    |> any_result(check)
  end

  defp elem_match(_left, _right, _ctx), do: false

  @spec eval_or(Context.attributes(), [t()], map()) :: result()
  defp eval_or(_attributes, [], _ctx), do: true

  defp eval_or(attributes, conditions, ctx),
    do: any_result(conditions, &eval_with_context(attributes, &1, ctx))

  @spec eval_and(Context.attributes(), [t()], map()) :: result()
  defp eval_and(attributes, conditions, ctx),
    do: all_results(conditions, &eval_with_context(attributes, &1, ctx))

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
