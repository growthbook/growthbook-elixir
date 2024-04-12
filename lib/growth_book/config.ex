defmodule GrowthBook.Config do
  @moduledoc """
  A set of helper functions to convert config maps to structs.

  This module is used to convert the configuration maps that are retrieved from GrowthBook's API
  (or your local cache) to values that can be used directly with the `GrowthBook.Context` module.
  """

  alias GrowthBook.{
    Context,
    Feature,
    FeatureRule,
    Experiment,
    VariationMeta,
    BucketRange,
    Filter,
    ParentCondition
  }

  @typedoc """
  A map with string keys, as returned when decoding JSON using Jason/Poison
  """
  @type json_map() :: %{required(String.t()) => term()}

  @doc """
  Converts feature configuration to a map of features.

  Use this function to take the configuration retrieved from the `/features` API endpoint and
  convert it into a usable map of `GrowthBook.Feature` structs.
  """
  @spec features_from_config(json_map()) :: Context.features()
  def features_from_config(%{"features" => features_config}) when is_map(features_config) do
    Map.new(features_config, fn {feature_key, feature_config} ->
      rules = feature_config |> Map.get("rules") |> feature_rules_from_config(feature_key)

      feature = %Feature{
        default_value: Map.get(feature_config, "defaultValue"),
        rules: rules
      }

      {feature_key, feature}
    end)
  end

  def features_from_config(_features_not_found_or_empty), do: %{}

  @doc """
  Converts feature rule configuration to a list of feature rules.

  Use this function to take the configuration retrieved from the `/features` API endpoint and
  convert it into a usable list of `GrowthBook.FeatureRule` structs. This function is used by
  `features_from_config`.
  """
  @spec feature_rules_from_config([json_map()], String.t()) :: [FeatureRule.t()]
  def feature_rules_from_config([_ | _] = feature_rules, feature_key) do
    Enum.map(feature_rules, fn feature_rule ->
      namespace = feature_rule |> Map.get("namespace") |> namespace_from_config()
      meta = Map.get(feature_rule, "meta", []) |> Enum.map(&VariationMeta.from_json/1)

      ranges =
        case Map.get(feature_rule, "ranges") do
          nil -> nil
          ranges -> Enum.map(ranges, &BucketRange.from_json/1)
        end

      parent_conditions =
        Map.get(feature_rule, "parentConditions", []) |> Enum.map(&ParentCondition.from_json/1)

      filters = Map.get(feature_rule, "filters", []) |> Enum.map(&Filter.from_json/1)

      range =
        case Map.get(feature_rule, "range") do
          nil -> nil
          range -> BucketRange.from_json(range)
        end

      %FeatureRule{
        condition: Map.get(feature_rule, "condition"),
        parent_conditions: parent_conditions,
        coverage: feature_rule |> Map.get("coverage") |> ensure_float(),
        force: Map.get(feature_rule, "force"),
        variations: Map.get(feature_rule, "variations"),
        key: Map.get(feature_rule, "key") || feature_key,
        weights: Map.get(feature_rule, "weights"),
        namespace: namespace,
        hash_attribute: Map.get(feature_rule, "hashAttribute"),
        hash_version: Map.get(feature_rule, "hashVersion") || 1,
        range: range,
        ranges: ranges,
        meta: meta,
        filters: filters,
        seed: Map.get(feature_rule, "seed"),
        name: Map.get(feature_rule, "name"),
        phase: Map.get(feature_rule, "phase")
      }
    end)
  end

  def feature_rules_from_config(_feature_rules_not_found_or_empty, _feature_key), do: []

  @doc """
  Converts experiment configuration into an `GrowthBook.Experiment`.

  Use this function to take the configuration from GrowthBook and
  convert it into a usable `GrowthBook.Experiment` struct.
  """
  @spec experiment_from_config(json_map()) :: Experiment.t()
  def experiment_from_config(experiment_config) do
    namespace = experiment_config |> Map.get("namespace") |> namespace_from_config()
    meta = Map.get(experiment_config, "meta", []) |> Enum.map(&VariationMeta.from_json/1)

    ranges =
      case Map.get(experiment_config, "ranges") do
        nil -> nil
        ranges -> Enum.map(ranges, &BucketRange.from_json/1)
      end

    filters = Map.get(experiment_config, "filters", []) |> Enum.map(&Filter.from_json/1)

    parent_conditions =
      Map.get(experiment_config, "parentConditions", []) |> Enum.map(&ParentCondition.from_json/1)

    %Experiment{
      key: Map.get(experiment_config, "key"),
      variations: Map.get(experiment_config, "variations"),
      active?: Map.get(experiment_config, "active", true),
      namespace: namespace,
      condition: Map.get(experiment_config, "condition"),
      coverage: experiment_config |> Map.get("coverage") |> ensure_float(),
      hash_attribute: Map.get(experiment_config, "hashAttribute"),
      force: Map.get(experiment_config, "force"),
      weights: Map.get(experiment_config, "weights"),
      ranges: ranges,
      meta: meta,
      filters: filters,
      parent_conditions: parent_conditions
    }
  end

  @doc """
  Convert namespace configuration to a namespace.

  Namespaces are represented by tuples, not lists, in the Elixir SDK, so this function converts
  a list to the corresponding tuple.
  """
  @spec namespace_from_config(term()) :: GrowthBook.namespace() | nil
  def namespace_from_config([namespace_id, range_from, range_to]),
    do: {namespace_id, ensure_float(range_from), ensure_float(range_to)}

  def namespace_from_config(_namespace_not_found_or_empty), do: nil

  @spec ensure_float(nil) :: nil
  @spec ensure_float(number()) :: float()
  defp ensure_float(nil), do: nil
  defp ensure_float(number) when is_float(number), do: number
  defp ensure_float(number) when is_integer(number), do: number / 1.0
end
