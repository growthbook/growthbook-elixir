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

  @type init_result :: {:ok, :initialized} | {:error, String.t()}

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
  # TODO fix dialyzer error @spec get_experiment_result(
  #  Context.t(),
  #  Experiment.t(),
  #  String.t(),
  #  integer(),
  #  boolean(),
  #  number()
  # ) :: Experiment.t()
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

    meta =
      if is_list(experiment.meta) do
        Enum.at(experiment.meta, variation_id)
      end

    %ExperimentResult{
      key:
        if meta && meta.key do
          meta.key
        else
          to_string(variation_id)
        end,
      feature_id: feature_id,
      in_experiment?: in_experiment,
      hash_used?: hash_used,
      variation_id: variation_id,
      value: Enum.at(experiment.variations, variation_id),
      hash_attribute: hash_attribute,
      hash_value: hash_value,
      name:
        if meta && meta.name do
          meta.name
        end,
      passthrough?: meta && meta.passthrough?,
      bucket: bucket
    }
  end

  @doc """
  Determine feature state for a given context

  This function takes a context and a feature key, and returns a `GrowthBook.FeatureResult` struct.
  """
  @spec feature(Context.t(), feature_key(), [feature_key()]) :: FeatureResult.t()

  def feature(%Context{} = context, feature_id, path \\ []) do
    features = Context.get_features(context)

    case Map.get(features, feature_id) do
      nil ->
        Logger.debug(
          "No feature with id: #{feature_id}, known features are: #{inspect(Map.keys(features))}"
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

  defp eval_rules(
         %Context{} = context,
         feature_id,
         %Feature{} = feature,
         [%FeatureRule{} = rule | rest],
         path
       ) do
    with true <-
           ParentCondition.eval(context, rule.parent_conditions, [feature_id | path]) || :skip,
         true <- not filtered_out?(context, rule.filters) || :skip,
         true <- eval_rule_condition(context.attributes, rule.condition) || :skip,
         true <- eval_forced_rule(context.attributes, feature_id, rule),
         exp = %Experiment{} = Experiment.from_rule(feature_id, rule),
         result = %ExperimentResult{} = run(context, exp, feature_id),
         true <- (result.in_experiment? && !result.passthrough?) || :skip do
      get_feature_result(result.value, :experiment, exp, result)
    else
      :skip ->
        eval_rules(context, feature_id, feature, rest, path)

      %FeatureResult{} = result ->
        result

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
       ) do
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
      "" ->
        true

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
         true <- variations_count >= 2 || {:error, "has less than 2 variations"},
         true <- context.enabled? || {:error, "disabled"},
         :ok <- check_query_string_override(context, exp, feature_id),
         :ok <- check_forced_variation(context, exp, feature_id),
         true <- exp.active? || {:error, "is not active"},
         {:ok, _hash_attribute, hash_value} <- get_experiment_hash_value(context, exp),
         true <- not filtered_out?(context, exp.filters) || {:error, "filtered out"},
         true <-
           (exp.filters || []) != [] || Helpers.in_namespace?(hash_value, exp.namespace) ||
             {:error, "not in namespace"},
         true <-
           eval_rule_condition(context.attributes, exp.condition) ||
             {:error, "condition is false"},
         true <-
           ParentCondition.eval(context, exp.parent_conditions, path) ||
             {:error, "parent conditions are false"} do
      bucket_ranges =
        exp.ranges ||
          Helpers.get_bucket_ranges(variations_count, exp.coverage || 1.0, exp.weights || [])

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

  @doc """
  Initialize GrowthBook with the feature repository configuration.
  Returns {:ok, :initialized} if initialization succeeds with features loaded, {:error, reason} otherwise.

  ## Options
    * `:client_key` - Required. The API client key
    * `:api_host` - Required. The GrowthBook API host
    * `:decryption_key` - Optional. Key for decrypting feature payloads
    * `:swr_ttl_seconds` - Optional. Cache TTL in seconds (default: 60)
    * `:refresh_strategy` - Optional. Either :periodic or :manual (default: :periodic)
    * `:on_refresh` - Optional. Function to call when features are refreshed
    * `:initialization_timeout` - Optional. Timeout in ms for initial feature fetch (default: 5000)
  """
  @spec init(Keyword.t()) :: init_result()
  def init(opts) do
    # Validate required options
    unless opts[:client_key] && opts[:api_host] do
      raise ArgumentError, "client_key and api_host are required"
    end

    # Validate callback if provided
    if opts[:on_refresh] && !is_function(opts[:on_refresh], 1) do
      raise ArgumentError, "on_refresh must be a function that accepts one argument"
    end

    case GrowthBook.FeatureRepository.start_link(opts) do
      {:ok, pid} ->
        # Wait for initial feature fetch
        timeout = opts[:initialization_timeout] || 5000

        case GrowthBook.FeatureRepository.await_initialization(pid, timeout) do
          :ok ->
            {:ok, :initialized}

          {:error, :timeout} ->
            GenServer.stop(pid)
            {:error, "initialization timed out after #{timeout}ms"}

          {:error, reason} ->
            GenServer.stop(pid)
            {:error, "initialization failed: #{reason}"}
        end

      {:error, reason} ->
        {:error, "failed to start feature repository: #{inspect(reason)}"}
    end
  end

  @doc """
  Build a context with the given attributes and features.
  If features are not provided, it will use the FeatureRepository to always get the latest features.
  """
  @spec build_context(map(), map() | nil) :: Context.t()
  def build_context(attributes, features \\ nil) do
    features_provider =
      case features do
        nil -> &GrowthBook.FeatureRepository.get_latest_features/0
        features -> fn -> features end
      end

    %Context{
      attributes: attributes,
      features_provider: features_provider,
      # Set to nil since we're using features_provider
      features: nil,
      enabled?: true,
      url: nil,
      qa_mode?: false,
      forced_variations: %{}
    }
  end
end
