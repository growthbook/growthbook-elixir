defmodule GrowthBook.ConformanceTest do
  use ExUnit.Case, async: true
  import GrowthBook.CaseHelper
  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  cases = "test/fixtures/cases.json" |> File.read!() |> Jason.decode!()

  # Spec cases for features this SDK doesn't implement yet, by section and description.
  # Saved groups are supported in conditions (`GrowthBook.Condition.eval_condition/3`), but not
  # yet read from a context's payload.
  @unsupported %{
    "feature" => %{
      "SavedGroups correctly pulled from context for force rule" => "saved groups in the context",
      "SavedGroups correctly pulled from context for experiment rule" =>
        "saved groups in the context",
      "CB rule with empty contexts (explore) buckets on marginal weights with fallback leaf -1" =>
        "contextual bandits",
      "CB rule with no contexts key falls back to marginal weights (fallback leaf -1)" =>
        "contextual bandits",
      "CB rule with empty contexts uses marginal weights (fallback leaf -1)" =>
        "contextual bandits",
      "CB rule with empty contexts is overridden by forced variation like a normal experiment" =>
        "contextual bandits"
    },
    "run" => %{
      "SavedGroups correctly pulled from context for experiment" => "saved groups in the context"
    }
  }

  # Whole sections this SDK doesn't run yet, and why
  @unsupported_sections %{
    "decrypt" => "not run by this harness",
    "stickyBucket" => "sticky bucketing",
    "urlRedirect" => "URL redirects (browser only)",
    "contextualBandit" => "contextual bandits",
    "savedGroupReferencesV2.feature" => "saved groups in the context",
    "savedGroupReferencesV2.run" => "saved groups in the context"
  }

  test "every spec section is run or listed as unsupported" do
    sections =
      for {key, value} <- unquote(Macro.escape(cases)), key != "specVersion" do
        if is_map(value), do: Enum.map(Map.keys(value), &"#{key}.#{&1}"), else: [key]
      end
      |> List.flatten()

    run =
      ~w(hash getBucketRange chooseVariation getQueryStringOverride inNamespace getEqualWeights
         evalCondition feature run pruneCondition reducePayload savedGroupReferencesV2.evalCondition)

    assert Enum.sort(sections) == Enum.sort(run ++ Map.keys(@unsupported_sections))
  end

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

        assert unquote(expected) ==
                 GrowthBook.Helpers.get_equal_weights(count) |> Enum.map(&Float.round(&1, 8))
      end
    end
  end

  describe "GrowthBook.Condition.eval_condition/3" do
    @describetag :eval_condition

    for {section, test_cases} <- [
          {"evalCondition", cases["evalCondition"]},
          {"savedGroupReferencesV2.evalCondition",
           cases["savedGroupReferencesV2"]["evalCondition"]}
        ],
        {test_case, index} <- Enum.with_index(test_cases) do
      [desc, condition, attributes, expected | rest] = test_case
      saved_groups = List.first(rest) || %{}

      test "#{section} ##{index}: #{desc}" do
        condition = unquote(Macro.escape(condition))
        attributes = unquote(Macro.escape(attributes))
        saved_groups = unquote(Macro.escape(saved_groups))

        capture_io(:stderr, fn ->
          actual = GrowthBook.Condition.eval_condition(attributes, condition, saved_groups)

          assert unquote(expected) == actual
        end)
      end
    end
  end

  describe "GrowthBook.prune_condition/3" do
    @describetag :prune_condition

    for {test_case, index} <- Enum.with_index(cases["pruneCondition"]) do
      [desc, condition, attributes, expected | rest] = test_case
      saved_groups = List.first(rest) || %{}

      test "##{index}: #{desc}" do
        condition = unquote(Macro.escape(condition))
        attributes = unquote(Macro.escape(attributes))
        saved_groups = unquote(Macro.escape(saved_groups))

        capture_io(:stderr, fn ->
          assert unquote(Macro.escape(expected)) ==
                   GrowthBook.prune_condition(attributes, condition, saved_groups)
        end)
      end
    end
  end

  describe "GrowthBook.reduce_payload/2" do
    @describetag :reduce_payload

    for {test_case, index} <- Enum.with_index(cases["reducePayload"]) do
      [desc, input, expected] = test_case

      test "##{index}: #{desc}" do
        input = unquote(Macro.escape(input))

        # Global attributes are merged with the user's, which take precedence
        attributes = Map.merge(input["globalAttributes"] || %{}, input["attributes"] || %{})

        opts =
          [
            attributes: attributes,
            include: filters_from_json(input["include"]),
            exclude: filters_from_json(input["exclude"]),
            prerequisites:
              input["prerequisites"] && String.to_existing_atom(input["prerequisites"])
          ]
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)

        capture_io(:stderr, fn ->
          assert unquote(Macro.escape(expected)) ==
                   GrowthBook.reduce_payload(input["payload"], opts)
        end)
      end
    end
  end

  describe "GrowthBook.feature/2" do
    @describetag :feature

    for {test_case, index} <- Enum.with_index(cases["feature"]) do
      [desc, context_config, feature_key, expected] = test_case

      if reason = @unsupported["feature"][desc] do
        @tag skip: "Not implemented: #{reason}"
      end

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
      [desc | _] = test_case

      if reason = @unsupported["run"][desc] do
        @tag skip: "Not implemented: #{reason}"
      end

      @tag index: to_string(index)
      test "##{index}: #{desc}" do
        [_desc, context_config, experiment_config, value, in_experiment?, hash_used?] =
          unquote(Macro.escape(test_case))

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
