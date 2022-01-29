defmodule GrowthBook.ConformanceTest do
  use ExUnit.Case, async: true
  import GrowthBook.CaseHelper
  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  cases = "test/fixtures/cases.json" |> File.read!() |> Jason.decode!()

  describe "GrowthBook.Helpers.hash/1" do
    for [input, expected] <- cases["hash"] do
      test "with #{inspect(input)} returns #{inspect(expected)}" do
        input = unquote(input)
        assert unquote(expected) == GrowthBook.Helpers.hash(input)
      end
    end
  end

  describe "GrowthBook.Helpers.get_bucket_ranges/3" do
    for [desc, input, expected] <- cases["getBucketRange"] do
      test desc do
        [count, coverage, weights] = unquote(input)

        assert unquote(round_tuples(expected)) ==
                 round_tuples(GrowthBook.Helpers.get_bucket_ranges(count, coverage, weights))
      end
    end
  end

  describe "GrowthBook.Helpers.choose_variation/2" do
    for [desc, hash, bucket_ranges, expected] <- cases["chooseVariation"] do
      test desc do
        hash = unquote(hash)
        bucket_ranges = unquote(bucket_ranges)

        assert unquote(expected) ==
                 GrowthBook.Helpers.choose_variation(hash, tuples(bucket_ranges))
      end
    end
  end

  describe "GrowthBook.Helpers.get_query_string_override/3" do
    for [desc, experiment_id, url, count, expected] <- cases["getQueryStringOverride"] do
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
    for [desc, user_id, namespace, expected] <- cases["getQueryStringOverride"] do
      test desc do
        user_id = unquote(user_id)
        namespace = unquote(namespace)

        assert unquote(expected) == GrowthBook.Helpers.in_namespace?(experiment_id, url)
      end
    end
  end

  describe "GrowthBook.Helpers.get_equal_weights/1" do
    for [desc, count, expected] <- cases["getQueryStringOverride"] do
      test desc do
        count = unquote(count)

        assert unquote(expected) == GrowthBook.Helpers.get_equal_weights(count)
      end
    end
  end

  describe "GrowthBook.Condition.eval_condition/2" do
    for {[desc, condition, attributes, expected], index} <-
          Enum.with_index(cases["evalCondition"]) do
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
    for {[desc, context_config, feature_key, expected], index} <-
          Enum.with_index(cases["feature"]) do
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
          attributes: Map.get(context_config, "attributes") || %{}
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
    for {[desc, context_config, experiment_config, value, in_experiment?], index} <-
          Enum.with_index(cases["run"]) do
      @tag index: to_string(index)
      test "##{index}: #{desc}" do
        context_config = unquote(Macro.escape(context_config))
        experiment_config = unquote(Macro.escape(experiment_config))
        value = unquote(Macro.escape(value))
        in_experiment? = unquote(Macro.escape(in_experiment?))

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
        end)
      end
    end
  end
end
