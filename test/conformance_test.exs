defmodule GrowthBook.ConformanceTest do
  use ExUnit.Case, async: true
  import GrowthBook.CaseHelper
  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  cases = "test/fixtures/cases.json" |> File.read!() |> Jason.decode!()

  describe "GrowthBook.Hash.hash/1" do
    @describetag :hash

    for test_case <- cases["hash"] do
      [seed, value, version, expected] = test_case
      test "hash v#{inspect(version)} with seed #{inspect(seed)}  and value #{inspect(value)} returns #{inspect(expected)}" do
        seed = unquote(seed)
        value = unquote(value)
        version = unquote(version)

        assert unquote(expected) == GrowthBook.Hash.hash(seed, value, version)
      end
    end
  end

  describe "GrowthBook.Helpers.get_bucket_ranges/3" do
    @describetag :get_bucket_range

    for test_case <- cases["getBucketRange"] do
      [desc, input, expected] = test_case
      test desc do
        [count, coverage, weights] = unquote(input)

        assert unquote(round_tuples(expected)) ==
                 round_tuples(GrowthBook.Helpers.get_bucket_ranges(count, coverage, weights))
      end
    end
  end

  describe "GrowthBook.Helpers.choose_variation/2" do
    @describetag :choose_variation

    for test_case <- cases["chooseVariation"] do
      [desc, hash, bucket_ranges, expected] = test_case
      test desc do
        hash = unquote(hash)
        bucket_ranges = unquote(bucket_ranges)

        assert unquote(expected) ==
                 GrowthBook.Helpers.choose_variation(hash, tuples(bucket_ranges))
      end
    end
  end

  describe "GrowthBook.Helpers.get_query_string_override/3" do
    @describetag :get_query_string_override

    for test_case <- cases["getQueryStringOverride"] do
      [desc, experiment_id, url, count, expected] = test_case
      test desc do
        experiment_id = unquote(experiment_id)
        url = unquote(url)
        count = unquote(count)

        assert unquote(expected) ==
                 GrowthBook.Helpers.get_query_string_override(experiment_id, url, count)
      end
    end
  end

  describe "GrowthBook.Helpers.in_namespace?/2" do
    @describetag :in_namespace

    for test_case <- cases["inNamespace"] do
      [desc, user_id, namespace, expected] = test_case
      test desc do
        user_id = unquote(user_id)
        namespace = GrowthBook.Config.namespace_from_config(unquote(namespace))

        assert unquote(expected) == GrowthBook.Helpers.in_namespace?(user_id, namespace)
      end
    end
  end

  describe "GrowthBook.Helpers.get_equal_weights/1" do
    @describetag :get_equal_weights

    for test_case <- cases["getEqualWeights"] do
      [count, expected] = test_case
      test "equal weights for #{count}" do
        count = unquote(count)

        assert unquote(expected) == GrowthBook.Helpers.get_equal_weights(count) |> Enum.map(& Float.round(&1, 8))
      end
    end
  end

  describe "GrowthBook.Condition.eval_condition/2" do
    @describetag :eval_condition

    for {test_case, index} <- Enum.with_index(cases["evalCondition"]) do
      [desc, condition, attributes, expected] = test_case
      test "##{index}: #{desc}" do
        condition = unquote(Macro.escape(condition))
        attributes = unquote(Macro.escape(attributes))

        capture_io(:stderr, fn ->
          actual = GrowthBook.Condition.eval_condition(attributes, condition)

          assert unquote(expected) == actual
        end)
      end
    end
    end

  describe "GrowthBook.feature/2" do
    @describetag :feature

    for {test_case, index} <- Enum.with_index(cases["feature"]) do
      [desc, context_config, feature_key, expected] = test_case
      test "##{index}: #{desc}" do
        context_config = unquote(Macro.escape(context_config))
        expected_config = unquote(Macro.escape(expected))

        expected_source =
          expected_config
          |> Map.get("source")
          |> GrowthBook.FeatureResult.feature_source_from_string()

        expected = %GrowthBook.FeatureResult{
          on: Map.get(expected_config, "on"),
          on?: Map.get(expected_config, "on"),
          off: Map.get(expected_config, "off"),
          off?: Map.get(expected_config, "off"),
          value: Map.get(expected_config, "value"),
          source: expected_source
        }

        feature_key = unquote(feature_key)

        context = %GrowthBook.Context{
          features: GrowthBook.Config.features_from_config(context_config),
          attributes: Map.get(context_config, "attributes") || %{},
          forced_variations: Map.get(context_config, "forcedVariations") || %{}
        }

        capture_log(fn ->
          actual = GrowthBook.feature(context, feature_key)

          assert expected.value == actual.value
          assert expected.source == actual.source
          assert expected.on == actual.on
          assert expected.off == actual.off
          assert expected.on? == actual.on?
          assert expected.off? == actual.off?
        end)
      end
    end
  end

  describe "GrowthBook.run/2" do
    @describetag :run

    for {test_case, index} <- Enum.with_index(cases["run"]) do
      [desc| _] = test_case
      @tag index: to_string(index)
      test "##{index}: #{desc}" do
        [_desc,
         context_config,
         experiment_config,
         value,
         in_experiment?,
         hash_used?
        ] = unquote(Macro.escape(test_case))

        context = %GrowthBook.Context{
          url: Map.get(context_config, "url"),
          enabled?: Map.get(context_config, "enabled", true),
          qa_mode?: Map.get(context_config, "qaMode", false),
          forced_variations: Map.get(context_config, "forcedVariations") || %{},
          features: GrowthBook.Config.features_from_config(context_config),
          attributes: Map.get(context_config, "attributes") || %{}
        }

        experiment = GrowthBook.Config.experiment_from_config(experiment_config)

        capture_log(fn ->
          actual = GrowthBook.run(context, experiment)

          assert value == actual.value
          assert in_experiment? == actual.in_experiment?
          assert hash_used? == actual.hash_used?
        end)
      end
    end
  end
end
