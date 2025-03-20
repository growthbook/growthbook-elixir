defmodule GrowthBook.InitTest do
  use ExUnit.Case, async: false

  alias GrowthBook.FeatureRepository

  # Mock HTTP client for testing
  defmodule MockHTTP do
    # Regular features
    def get("https://cdn.growthbook.io/api/features/client-key") do
      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body:
           Jason.encode!(%{
             "features" => %{
               "feature-1" => %{"defaultValue" => true},
               "feature-2" => %{"defaultValue" => "test"}
             }
           })
       }}
    end

    # Encrypted features
    def get("https://cdn.growthbook.io/api/features/encrypted-client-key") do
      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body:
           Jason.encode!(%{
             "encryptedFeatures" => "mock-encrypted-data"
           })
       }}
    end

    def get("https://cdn.growthbook.io/api/features/error-key") do
      {:ok, %HTTPoison.Response{status_code: 500, body: "Internal Server Error"}}
    end

    def get("https://cdn.growthbook.io/api/features/timeout-key") do
      {:error, %HTTPoison.Error{reason: :timeout}}
    end
  end

  # Setup mocks and cleanup
  setup do
    # Replace HTTPoison with our mock
    original_http = Application.get_env(:growthbook, :http_client, HTTPoison)
    Application.put_env(:growthbook, :http_client, MockHTTP)

    on_exit(fn ->
      # Restore original HTTP client
      Application.put_env(:growthbook, :http_client, original_http)

      # Stop any running repository
      try do
        GenServer.stop(FeatureRepository)
      catch
        :exit, _ -> :ok
      end
    end)

    :ok
  end

  describe "GrowthBook.init/1" do
    test "initializes successfully with valid parameters" do
      result =
        GrowthBook.init(
          client_key: "client-key",
          api_host: "https://cdn.growthbook.io",
          initialization_timeout: 1000
        )

      assert result == {:ok, :initialized}

      # Verify we can build a context and access features
      context = GrowthBook.build_context(%{"user_id" => "123"})
      features = GrowthBook.Context.get_features(context)

      assert Map.has_key?(features, "feature-1")
      assert Map.has_key?(features, "feature-2")
    end

    test "initializes with decryption key for encrypted features" do
      # Create a module to patch DecryptionUtils.decrypt for this test
      defmodule TestHelpers do
        def patch_decrypt do
          :meck.new(GrowthBook.DecryptionUtils, [:passthrough])

          :meck.expect(GrowthBook.DecryptionUtils, :decrypt, fn _payload, _key ->
            {:ok,
             ~s({"feature-1":{"defaultValue":"decrypted-value"},"secret-feature":{"defaultValue":true}})}
          end)
        end

        def unpatch_decrypt do
          :meck.unload(GrowthBook.DecryptionUtils)
        end
      end

      # Patch the decrypt function
      TestHelpers.patch_decrypt()

      result =
        GrowthBook.init(
          client_key: "encrypted-client-key",
          api_host: "https://cdn.growthbook.io",
          decryption_key: "test-key",
          initialization_timeout: 1000
        )

      assert result == {:ok, :initialized}

      # Verify we can build a context and access decrypted features
      context = GrowthBook.build_context(%{"user_id" => "123"})
      features = GrowthBook.Context.get_features(context)

      # Restore the original function
      TestHelpers.unpatch_decrypt()

      # Features are returned as Feature structs, not maps
      feature1 = Map.get(features, "feature-1")
      secret_feature = Map.get(features, "secret-feature")

      assert feature1 != nil
      assert secret_feature != nil
      assert feature1.default_value == "decrypted-value"
      assert secret_feature.default_value == true
    end

    test "returns error on initialization failure" do
      result =
        GrowthBook.init(
          client_key: "error-key",
          api_host: "https://cdn.growthbook.io",
          initialization_timeout: 1000
        )

      assert {:error, _message} = result
    end

    test "handles timeout during initialization" do
      # Create a mock HTTP client that sleeps
      defmodule SlowMockHTTP do
        def get(_url) do
          # Sleep longer than our timeout
          Process.sleep(200)
          {:ok, %HTTPoison.Response{status_code: 200, body: "{}"}}
        end
      end

      # Use the slow mock
      Application.put_env(:growthbook, :http_client, SlowMockHTTP)

      result =
        GrowthBook.init(
          client_key: "any-key",
          api_host: "https://cdn.growthbook.io",
          # Very short timeout
          initialization_timeout: 50
        )

      assert {:error, message} = result
      assert message =~ "timed out"
    end

    test "raises ArgumentError when required parameters are missing" do
      assert_raise ArgumentError, fn ->
        GrowthBook.init(api_host: "https://cdn.growthbook.io")
      end

      assert_raise ArgumentError, fn ->
        GrowthBook.init(client_key: "key")
      end
    end

    test "validates callback function" do
      assert_raise ArgumentError, fn ->
        GrowthBook.init(
          client_key: "key",
          api_host: "host",
          on_refresh: "not a function"
        )
      end
    end
  end

  describe "GrowthBook.build_context/2" do
    test "creates a context with dynamic features provider" do
      GrowthBook.init(
        client_key: "client-key",
        api_host: "https://cdn.growthbook.io"
      )

      context = GrowthBook.build_context(%{"user_id" => "123"})
      assert context.features == nil
      assert is_function(context.features_provider)

      # Features should be fetched from repository
      features = GrowthBook.Context.get_features(context)
      assert Map.has_key?(features, "feature-1")
    end

    test "creates a context with static features when provided" do
      static_features = %{
        "static-feature" => %GrowthBook.Feature{
          default_value: "static",
          rules: []
        }
      }

      context = GrowthBook.build_context(%{"user_id" => "123"}, static_features)

      # Features should be the static ones we provided
      features = GrowthBook.Context.get_features(context)
      assert Map.has_key?(features, "static-feature")
      assert features["static-feature"].default_value == "static"
    end
  end
end
