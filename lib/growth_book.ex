defmodule GrowthBook do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  alias GrowthBook.Condition
  alias GrowthBook.Context
  alias GrowthBook.Feature
  alias GrowthBook.Experiment
  alias GrowthBook.ExperimentResult
  alias GrowthBook.FeatureResult
  alias GrowthBook.FeatureRule
  alias GrowthBook.Helpers

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
  # NOTE: This is called "getResult" in the JS SDK, but the guide says "getExperimentResult"
  @spec get_experiment_result(Context.t(), Experiment.t() | nil, integer(), boolean()) ::
          ExperimentResult.t()
  def get_experiment_result(
        %Context{} = context,
        %Experiment{} = experiment,
        variation_id \\ 0,
        in_experiment? \\ false
      ) do
    hash_attribute = experiment.hash_attribute || "id"

    variation_id =
      if variation_id < 0 or variation_id > length(experiment.variations),
        do: 0,
        else: variation_id

    %ExperimentResult{
      value: Enum.at(experiment.variations, variation_id),
      variation_id: variation_id,
      in_experiment?: in_experiment?,
      hash_attribute: hash_attribute,
      hash_value: Map.get(context.attributes, hash_attribute) || ""
    }
  end

  @doc """
  Determine feature state for a given context

  This function takes a context and a feature key, and returns a `GrowthBook.FeatureResult` struct.
  """
  @spec feature(Context.t(), feature_key()) :: FeatureResult.t()
  def feature(%Context{features: features} = context, feature_id)
      when is_map_key(features, feature_id) do
    %{^feature_id => %Feature{} = feature} = features

    cond do
      # No rules, using default value
      feature.rules == [] -> get_feature_result(feature.default_value, :default_value)
      true -> find_matching_feature_rule(context, feature, feature_id)
    end
  end

  def feature(%Context{} = context, missing_feature_id) do
    Logger.debug(
      "No feature with id: #{missing_feature_id}, known features are: #{inspect(Map.keys(context.features))}"
    )

    get_feature_result(nil, :unknown_feature)
  end

  @doc false
  @spec find_matching_feature_rule(Context.t(), Feature.t(), feature_key()) :: FeatureResult.t()
  def find_matching_feature_rule(%Context{} = context, %Feature{} = feature, feature_id) do
    Enum.find_value(feature.rules, fn %FeatureRule{} = rule ->
      cond do
        # Skip this rule if the condition doesn't evaluate to true
        rule.condition && not Condition.eval_condition(context.attributes, rule.condition) ->
          Logger.debug(
            "#{feature_id}: Skipping rule #{rule.key} because condition evaluated to false"
          )

          false

        # Feature being forced with coverage
        not is_nil(rule.force) and not is_nil(rule.coverage) ->
          hash_value = Map.get(context.attributes, rule.hash_attribute || "id")

          # If the hash value is empty, or if the rule is excluded because of coverage, skip
          cond do
            hash_value in [nil, ""] ->
              Logger.debug("#{feature_id}: Skipping rule #{rule.key} because hash value is empty")

              false

            Helpers.hash(hash_value <> feature_id) > rule.coverage ->
              Logger.debug(
                "#{feature_id}: Skipping rule #{rule.key} because it's outside coverage"
              )

              false

            true ->
              Logger.debug("#{feature_id}: Force value from rule #{rule.key}")

              get_feature_result(rule.force, :force)
          end

        # Feature being forced without coverage
        not is_nil(rule.force) ->
          Logger.debug("#{feature_id}: Force value from rule #{rule.key}")
          get_feature_result(rule.force, :force)

        # Skip invalid rule
        rule.variations in [[], nil] ->
          Logger.debug("#{feature_id}: Skipping rule #{rule.key} because it has no variations")
          false

        # Run the experiment
        true ->
          experiment = %Experiment{
            key: rule.key || feature_id,
            variations: rule.variations,
            coverage: rule.coverage,
            weights: rule.weights,
            hash_attribute: rule.hash_attribute,
            namespace: rule.namespace
          }

          %ExperimentResult{} = experiment_result = run(context, experiment)

          if experiment_result.in_experiment? do
            get_feature_result(
              experiment_result.value,
              :experiment,
              experiment,
              experiment_result
            )
          else
            Logger.debug(
              "#{feature_id}: Skipping rule #{rule.key} because it is not in the experiment"
            )

            false
          end
      end
    end) || get_feature_result(feature.default_value, :default_value)
  end

  @doc """
  Run an experiment for the given context

  This function takes a context and an experiment, and returns an `GrowthBook.ExperimentResult` struct.
  """
  @spec run(Context.t(), Experiment.t()) :: ExperimentResult.t()
  def run(context, experiment)

  # 2. When the context is disabled
  def run(%Context{enabled?: false} = context, %Experiment{} = experiment) do
    Logger.debug("Experiment is disabled")
    get_experiment_result(context, experiment)
  end

  # 1. If experiment has less than 2 variations
  def run(%Context{} = context, %Experiment{variations: variations} = experiment)
      when length(variations) < 2 do
    Logger.debug("Experiment is invalid: has less than 2 variations")
    get_experiment_result(context, experiment)
  end

  def run(%Context{} = context, %Experiment{key: key, variations: variations} = experiment) do
    variations_count = length(variations)

    # 2.5. Merge in experiment overrides from context
    experiment = Experiment.merge_with_overrides(experiment, context.overrides)

    query_string_override =
      not is_nil(context.url) &&
        Helpers.get_query_string_override(key, context.url, variations_count)

    hash_value = Map.get(context.attributes, experiment.hash_attribute || "id")

    # 9. Get bucket ranges and choose variation
    bucket_ranges =
      Helpers.get_bucket_ranges(variations_count, experiment.coverage || 1.0, experiment.weights)

    hash = if hash_value, do: Helpers.hash(hash_value <> key)
    assigned_variation = Helpers.choose_variation(hash, bucket_ranges)

    cond do
      # 3. If a variation is forced from a query string, return forced variation
      query_string_override ->
        Logger.debug("#{key}: Forced variation from query string: #{query_string_override}")
        get_experiment_result(context, experiment, query_string_override)

      # 4. If a variation is forced in the context, return forced variation
      is_map_key(context.forced_variations, key) ->
        Logger.debug("#{key}: Forced variation from context: #{context.forced_variations[key]}")
        get_experiment_result(context, experiment, context.forced_variations[key])

      # 5. Exclude if experiment is inactive or in draft
      experiment.active? == false or experiment.status == "draft" ->
        Logger.debug("#{key}: Experiment is inactive (or in draft)")
        get_experiment_result(context, experiment)

      # 6. Skip if hash value is empty
      hash_value in [nil, ""] ->
        Logger.debug("#{key}: Skipping experiment because hash value is empty")
        get_experiment_result(context, experiment)

      # 7. Exclude if user not in experiment's namespace
      experiment.namespace && not Helpers.in_namespace?(hash_value, experiment.namespace) ->
        Logger.debug("#{key}: Skipping experiment because user is not in namespace")
        get_experiment_result(context, experiment)

      # 8. Exclude if condition is set and it doesn't evaluate to true
      experiment.condition &&
          not Condition.eval_condition(context.attributes, experiment.condition) ->
        Logger.debug("#{key}: Skipping experiment because condition evaluated to false")
        get_experiment_result(context, experiment)

      # NOTE: Legacy URL and Group targetting is omitted in favor of conditions

      # 10. Exclude if not in experiment
      assigned_variation < 0 ->
        Logger.debug("#{key}: Skipping experiment because user is not assigned to variation")
        get_experiment_result(context, experiment)

      # 11. If experiment has forced variation
      experiment.force ->
        Logger.debug("#{key}: Forced variation from experiment: #{experiment.force}")
        get_experiment_result(context, experiment, experiment.force)

      # 12. Exclude if in QA mode
      context.qa_mode? ->
        Logger.debug("#{key}: Skipping experiment because QA mode is enabled")
        get_experiment_result(context, experiment)

      # 12.5. Exclude if experiment is stopped
      experiment.status == "stopped" ->
        get_experiment_result(context, experiment)

      # 13. Experiment is active
      true ->
        Logger.debug("#{key}: Experiment is active")
        get_experiment_result(context, experiment, assigned_variation, true)
    end
  end
end
