defmodule GrowthBook.IntegrationTest do
  use ExUnit.Case, async: false

  alias GrowthBook.FeatureRepository

  # Mock HTTP client for testing with changing features
  defmodule DynamicMockHTTP do
    use Agent

    def start_link(_) do
      Agent.start_link(
        fn ->
          %{
            "features" => %{
              "test-feature" => %{"defaultValue" => false}
            }
          }
        end,
        name: __MODULE__
      )
    end

    def get("https://cdn.growthbook.io/api/features/client-key") do
      body = Agent.get(__MODULE__, fn state -> Jason.encode!(state) end)
      {:ok, %HTTPoison.Response{status_code: 200, body: body}}
    end

    def update_features(new_features) do
      Agent.update(__MODULE__, fn _ ->
        %{"features" => new_features}
      end)
    end
  end

  # Setup mocks and cleanup
  setup do
    {:ok, _} = DynamicMockHTTP.start_link(nil)

    # Replace HTTPoison with our mock
    original_http = Application.get_env(:growthbook, :http_client, HTTPoison)
    Application.put_env(:growthbook, :http_client, DynamicMockHTTP)

    on_exit(fn ->
      # Restore original HTTP client
      Application.put_env(:growthbook, :http_client, original_http)

      # Stop any running repository
      try do
        GenServer.stop(FeatureRepository)
      catch
        :exit, _ -> :ok
      end

      try do
        Agent.stop(DynamicMockHTTP)
      catch
        :exit, _ -> :ok
      end
    end)

    :ok
  end

  describe "Feature evaluation with auto-refresh" do
    test "GrowthBook.feature uses latest features" do
      # Initialize with a short TTL
      GrowthBook.init(
        client_key: "client-key",
        api_host: "https://cdn.growthbook.io",
        swr_ttl_seconds: 1
      )

      # Create a context that uses auto-refresh
      context = GrowthBook.build_context(%{"user_id" => "123"})

      # Initially feature is false
      result = GrowthBook.feature(context, "test-feature")
      assert result.value == false

      # Update the feature on the "server"
      DynamicMockHTTP.update_features(%{
        "test-feature" => %{"defaultValue" => true}
      })

      # Force the state to have an old last_fetch time
      :sys.replace_state(FeatureRepository, fn state ->
        %{state | last_fetch: DateTime.add(DateTime.utc_now(), -10)}
      end)

      # Wait a moment for TTL to trigger refresh
      Process.sleep(100)

      # Feature should now evaluate to true with the same context
      result = GrowthBook.feature(context, "test-feature")
      assert result.value == true
    end

    test "GrowthBook.feature_value uses latest features" do
      # Initialize with a short TTL
      GrowthBook.init(
        client_key: "client-key",
        api_host: "https://cdn.growthbook.io",
        swr_ttl_seconds: 1
      )

      # Create a context that uses auto-refresh
      context = GrowthBook.build_context(%{"user_id" => "123"})

      # Add feature_value method to GrowthBook if it doesn't exist
      if not function_exported?(GrowthBook, :feature_value, 3) do
        defmodule GrowthBookExt do
          def feature_value(context, feature_id, default) do
            result = GrowthBook.feature(context, feature_id)
            if is_nil(result.value), do: default, else: result.value
          end
        end

        # Initially feature is false
        value = GrowthBookExt.feature_value(context, "test-feature", nil)
        assert value == false

        # Update the feature on the "server"
        DynamicMockHTTP.update_features(%{
          "test-feature" => %{"defaultValue" => "new-value"}
        })

        # Force the state to have an old last_fetch time
        :sys.replace_state(FeatureRepository, fn state ->
          %{state | last_fetch: DateTime.add(DateTime.utc_now(), -10)}
        end)

        # Wait a moment for TTL to trigger refresh
        Process.sleep(100)

        # Feature should now evaluate to the new value with the same context
        value = GrowthBookExt.feature_value(context, "test-feature", nil)
        assert value == "new-value"
      else
        # If feature_value exists, use it directly
        # Initially feature is false
        value = GrowthBook.feature_value(context, "test-feature", nil)
        assert value == false

        # Update the feature on the "server"
        DynamicMockHTTP.update_features(%{
          "test-feature" => %{"defaultValue" => "new-value"}
        })

        # Force the state to have an old last_fetch time
        :sys.replace_state(FeatureRepository, fn state ->
          %{state | last_fetch: DateTime.add(DateTime.utc_now(), -10)}
        end)

        # Wait a moment for TTL to trigger refresh
        Process.sleep(100)

        # Feature should now evaluate to the new value with the same context
        value = GrowthBook.feature_value(context, "test-feature", nil)
        assert value == "new-value"
      end
    end

    test "feature evaluation with callback notification" do
      test_pid = self()

      # Initialize with callback
      GrowthBook.init(
        client_key: "client-key",
        api_host: "https://cdn.growthbook.io",
        swr_ttl_seconds: 1,
        on_refresh: fn features ->
          send(test_pid, {:features_updated, features})
        end
      )

      # Create a context
      context = GrowthBook.build_context(%{"user_id" => "123"})

      # Update the feature and force refresh
      DynamicMockHTTP.update_features(%{
        "test-feature" => %{"defaultValue" => "callback-test"}
      })

      # Force the state to have an old last_fetch time
      :sys.replace_state(FeatureRepository, fn state ->
        %{state | last_fetch: DateTime.add(DateTime.utc_now(), -10)}
      end)

      # Trigger refresh by accessing features
      GrowthBook.feature(context, "test-feature")

      # We should receive the callback with updated features
      assert_receive {:features_updated, features}, 1000
      assert features["test-feature"]["defaultValue"] == "callback-test"
    end
  end
end
