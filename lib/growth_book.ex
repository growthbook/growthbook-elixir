defmodule GrowthBook do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  alias GrowthBook.{
    Condition,
    Context,
    Feature,
    Experiment,
    ExperimentResult,
    FeatureResult,
    FeatureRule,
    Helpers,
    Hash,
    Filter,
    ParentCondition
  }

  require Logger

  @typedoc """
  Bucket range

  A tuple that describes a range of the numberline between `0` and `1`.

  The tuple has 2 parts, both floats - the start of the range and the end. For example:

  ```
  {0.3, 0.7}
  ```
  """
  @type bucket_range() :: {float(), float()}

  @typedoc """
  Feature key

  A key for a feature. This is a string that references a feature.
  """
  @type feature_key() :: String.t()

  @typedoc """
  Namespace

  A tuple that specifies what part of a namespace an experiment includes. If two experiments are
  in the same namespace and their ranges don't overlap, they wil be mutually exclusive.

  The tuple has 3 parts:

  1. The namespace id (`String.t()`)
  2. The beginning of the range (`float()`, between `0` and `1`)
  3. The end of the range (`float()`, between `0` and `1`)

  For example:

  ```
  {"namespace1", 0, 0.5}
  ```
  """
  @type namespace() :: {String.t(), float(), float()}

  @doc false
  @spec get_feature_result(
          term(),
          FeatureResult.source(),
          Experiment.t() | nil,
          ExperimentResult.t() | nil
        ) :: FeatureResult.t()
  def get_feature_result(value, source, experiment \\ nil, experiment_result \\ nil) do
    %FeatureResult{
      value: value,
      on: Helpers.cast_boolish(value),
      on?: Helpers.cast_boolish(value),
      off: not Helpers.cast_boolish(value),
      off?: not Helpers.cast_boolish(value),
      source: source,
      experiment: experiment,
      experiment_result: experiment_result
    }
  end

  @doc false
  @spec get_experiment_result(
    Context.t(),
    Experiment.t(),
    String.t() | nil,
    integer() | nil,
    boolean() | nil,
    number() | nil
  ) :: ExperimentResult.t()
  def get_experiment_result(
        %Context{} = context,
        %Experiment{} = experiment,
        feature_id \\ nil,
        variation_id \\ -1,
        hash_used \\ false,
        bucket \\ nil
      ) do

    {in_experiment, variation_id} =
      if variation_id < 0 or variation_id >= length(experiment.variations),
        do: {false, 0},
        else: {true, variation_id}

    hash_attribute = experiment.hash_attribute || "id"
    hash_value = context.attributes[hash_attribute] || ""

    meta = if is_list(experiment.meta) do Enum.at(experiment.meta, variation_id) end

    %ExperimentResult{
      key: if meta && meta.key do meta.key else to_string(variation_id) end,
      feature_id: feature_id,
      in_experiment?: in_experiment,
      hash_used?: hash_used,
      variation_id: variation_id,
      value: Enum.at(experiment.variations, variation_id),
      hash_attribute: hash_attribute,
      hash_value: hash_value,
      name: if meta && meta.name do meta.name end,
      passthrough?: meta && meta.passthrough?,
      bucket: bucket
    }
  end

  @doc """
  Determine feature state for a given context

  This function takes a context and a feature key, and returns a `GrowthBook.FeatureResult` struct.
  """
  @spec feature(Context.t(), feature_key(), [feature_key()]) :: FeatureResult.t()

  def feature(context, feature_id, path \\ [])

  def feature(%Context{features: features} = context, feature_id, path) do
    case Map.get(features, feature_id) do
      nil ->
        Logger.debug(
          "No feature with id: #{feature_id}, known features are: #{inspect(Map.keys(context.features))}"
        )
        get_feature_result(nil, :unknown_feature)
      %Feature{rules: rules} = feature ->
        eval_rules(context, feature_id, feature, rules, path)
    end
  end

  @doc false
  defp eval_rules(%Context{} = _context, _feature_id, %Feature{} = feature, [], _path) do
    get_feature_result(feature.default_value, :default_value)
  end

  defp eval_rules(%Context{} = context, feature_id, %Feature{} = feature, [%FeatureRule{} = rule | rest], path) do
    with true <- ParentCondition.eval(context, rule.parent_conditions, [feature_id | path]) || :skip,
         true <- not filtered_out?(context, rule.filters) || :skip,
         true <- eval_rule_condition(context.attributes, rule.condition) || :skip,
         true <- eval_forced_rule(context.attributes, feature_id, rule),
         exp = %Experiment{} = Experiment.from_rule(feature_id, rule),
         result = %ExperimentResult{} = run(context, exp, feature_id),
         true <- (result.in_experiment? && !result.passthrough?) || :skip do
      get_feature_result(result.value, :experiment, exp, result)
    else
      :skip -> eval_rules(context, feature_id, feature, rest, path)
      %FeatureResult{} = result -> result
      {:error, %ParentCondition.CyclingError{}} ->
        get_feature_result(nil, :cyclic_prerequisite)
      {:error, %ParentCondition.PrerequisiteError{}} ->
        get_feature_result(nil, :prerequisite)
    end
  end

  defp eval_forced_rule(_, _, %FeatureRule{force: nil}), do: true
  defp eval_forced_rule(attributes, feature_id, %FeatureRule{} = rule) do
    if Helpers.included_in_rollout?(
          attributes,
          Helpers.coalesce(rule.seed, feature_id),
          rule.hash_attribute,
          rule.range,
          rule.coverage,
          rule.hash_version
      )
    do
      # TODO add rule.tracks callbacks calls
      get_feature_result(rule.force, :force)
    else
      :skip
    end
  end

  defp eval_rule_condition(_, nil), do: true
  defp eval_rule_condition(attributes, condition),
    do: Condition.eval_condition(attributes, condition)

  defp filtered_out?(_context, nil), do: false
  defp filtered_out?(context, filters) when is_list(filters) do
    Enum.any?(filters, &filtered_out?(context, &1))
  end
  defp filtered_out?(%Context{} = context, %Filter{} = filter) do
    hash_attribute = filter.attribute
    hash_value = context.attributes[hash_attribute] || ""
    case hash_value do
      "" -> true
      _ ->
        n = Hash.hash(filter.seed, hash_value, filter.hash_version)
        not Enum.any?(filter.ranges, &Helpers.in_range?(n, &1))
    end
  end

  @doc """
  Run an experiment for the given context

  This function takes a context and an experiment, and returns an `GrowthBook.ExperimentResult` struct.
  """
  @spec run(Context.t(), Experiment.t(), String.t() | nil) :: ExperimentResult.t()
  def run(%Context{} = context, %Experiment{} = exp, feature_id \\ nil, path \\ []) do
    with variations_count <- length(exp.variations),
         true <- variations_count >=2 || {:error, "has less than 2 variations"},
         true <- context.enabled? || {:error, "disabled"},
         :ok <- check_query_string_override(context, exp, feature_id),
         :ok <- check_forced_variation(context, exp, feature_id),
         true <- exp.active? || {:error, "is not active"},
         {:ok, _hash_attribute, hash_value} <- get_experiment_hash_value(context, exp),
         true <- not filtered_out?(context, exp.filters) || {:error, "filtered out"},
         true <- (exp.filters || []) != [] || Helpers.in_namespace?(hash_value, exp.namespace) || {:error, "not in namespace"},
         true <- eval_rule_condition(context.attributes, exp.condition) || {:error, "condition is false"},
         true <- ParentCondition.eval(context, exp.parent_conditions, path) || {:error, "parent conditions are false"} do

      bucket_ranges = exp.ranges || Helpers.get_bucket_ranges(variations_count, exp.coverage || 1.0, exp.weights || [])
      hash = Hash.hash(exp.seed || exp.key, hash_value, exp.hash_version || 1)
      variation_id = Helpers.choose_variation(hash, bucket_ranges)

      cond do
        variation_id < 0 ->
          Logger.debug("Experiment #{exp.key} skipped: no assigned variation")
          get_experiment_result(context, exp, feature_id)

        not is_nil(exp.force) ->
          Logger.debug("Experiment #{exp.key} forced: #{exp.force}")
          get_experiment_result(context, exp, feature_id, exp.force)

        context.qa_mode? ->
          Logger.debug("Experiment #{exp.key} skipped: QA mode enabled")
          get_experiment_result(context, exp, feature_id)

        true ->
          get_experiment_result(context, exp, feature_id, variation_id, true, hash)
      end
    else
      {:error, %ParentCondition.CyclingError{message: message}} ->
        Logger.debug("Experiment #{exp.key} skipped: #{message}")
        get_experiment_result(context, exp)
      {:error, %ParentCondition.PrerequisiteError{message: message}} ->
        Logger.debug("Experiment #{exp.key} skipped: #{message}")
        get_experiment_result(context, exp)
      {:error, error} ->
        Logger.debug("Experiment #{exp.key} skipped: #{error}")
        get_experiment_result(context, exp)
      %ExperimentResult{} = result ->
        result
    end
  end

  defp check_query_string_override(%Context{url: nil}, %Experiment{}, _), do: :ok
  defp check_query_string_override(%Context{url: url} = context, %Experiment{} = exp, feature_id) do
    qs_override = Helpers.get_query_string_override(exp.key, url, length(exp.variations))
    if not is_nil(qs_override) do
      get_experiment_result(context, exp, feature_id, qs_override)
    else
      :ok
    end
  end

  defp check_forced_variation(%Context{} = context, %Experiment{} = exp, feature_id) do
    case Map.get(context.forced_variations, exp.key) do
      nil -> :ok
      var -> get_experiment_result(context, exp, feature_id, var)
    end
  end

  defp get_experiment_hash_value(%Context{} = context, %Experiment{} = exp) do
    hash_attribute = exp.hash_attribute || "id"
    hash_value = context.attributes[hash_attribute] || ""
    case hash_value do
      "" -> get_experiment_fallback_value(context, exp)
      _ -> {:ok, hash_attribute, hash_value}
    end
  end

  defp get_experiment_fallback_value(%Context{} = context, %Experiment{} = exp) do
    case {exp.fallback_attribute, context.attributes[exp.fallback_attribute]} do
      {nil, _} -> {:error, "empty fallback attribute"}
      {_, nil} -> {:error, "empty fallback attribute value"}
      {attr, val} -> {:ok, attr, val}
    end
  end
end
