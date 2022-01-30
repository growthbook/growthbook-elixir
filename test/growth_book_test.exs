defmodule GrowthBookTest do
  use ExUnit.Case, async: true
  doctest GrowthBook
  import ExUnit.CaptureLog

  describe "GrowthBook.run/2" do
    test "ignores draft experiments" do
      context = %GrowthBook.Context{attributes: %{"id" => "1"}}

      context_with_qs_override = %GrowthBook.Context{
        context
        | url: "http://example.com/?my-test=1"
      }

      experiment = %GrowthBook.Experiment{
        key: "my-test",
        status: "draft",
        variations: [0, 1]
      }

      capture_log(fn ->
        refute GrowthBook.run(context, experiment).in_experiment?
        assert 0 == GrowthBook.run(context, experiment).value
        refute GrowthBook.run(context_with_qs_override, experiment).in_experiment?
        assert 1 == GrowthBook.run(context_with_qs_override, experiment).value
      end)
    end

    test "ignores stopped experiments unless forced" do
      context = %GrowthBook.Context{attributes: %{"id" => "1"}}

      experiment_lose = %GrowthBook.Experiment{
        key: "my-test",
        status: "stopped",
        variations: [0, 1, 2]
      }

      experiment_win = %GrowthBook.Experiment{
        key: "my-test",
        status: "stopped",
        variations: [0, 1, 2],
        force: 2
      }

      capture_log(fn ->
        refute GrowthBook.run(context, experiment_lose).in_experiment?
        assert 0 == GrowthBook.run(context, experiment_lose).value
        refute GrowthBook.run(context, experiment_win).in_experiment?
        assert 2 == GrowthBook.run(context, experiment_win).value
      end)
    end
  end
end
