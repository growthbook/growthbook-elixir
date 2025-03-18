defmodule GrowthBook.FeatureRepositoryTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias GrowthBook.FeatureRepository

  # Mock HTTP client for testing
  defmodule MockHTTP do
    # This simulates the GrowthBook API server
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

    # This simulates the encrypted response from GrowthBook API
    def get("https://cdn.growthbook.io/api/features/encrypted-client-key") do
      # Return a simple encrypted payload that our decryption module can handle for testing
      # This is a simplified version that doesn't require actual decryption
      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body:
           Jason.encode!(%{
             # Use a special format our test decryption module will recognize
             "encryptedFeatures" => "test.dGVzdA=="
           })
       }}
    end

    # Error cases - these can still use different client keys for simpler testing
    def get("https://cdn.growthbook.io/api/features/error-key") do
      {:ok, %HTTPoison.Response{status_code: 500, body: "Internal Server Error"}}
    end

    def get("https://cdn.growthbook.io/api/features/timeout-key") do
      # Simulate network delay
      Process.sleep(200)
      {:error, %HTTPoison.Error{reason: :timeout}}
    end

    def get("https://cdn.growthbook.io/api/features/invalid-json-key") do
      {:ok, %HTTPoison.Response{status_code: 200, body: "not-json"}}
    end
  end

  # Setup mocks and cleanup
  setup do
    # Replace HTTPoison with our mock
    original_http = Application.get_env(:growthbook, :http_client, HTTPoison)
    Application.put_env(:growthbook, :http_client, MockHTTP)

    # Start a test repository
    on_exit(fn ->
      # Restore original HTTP client
      Application.put_env(:growthbook, :http_client, original_http)
    end)

    :ok
  end

  describe "initialization" do
    test "successfully initializes with valid config" do
      start_supervised!(
        {FeatureRepository, client_key: "client-key", api_host: "https://cdn.growthbook.io"}
      )

      # Give it time to initialize
      Process.sleep(100)

      features = FeatureRepository.get_features()
      assert Map.has_key?(features, "feature-1")
      assert Map.has_key?(features, "feature-2")
    end

    test "handles initialization errors" do
      log =
        capture_log(fn ->
          start_supervised!(
            {FeatureRepository, client_key: "error-key", api_host: "https://cdn.growthbook.io"}
          )

          Process.sleep(100)
        end)

      assert log =~ "Failed to initialize features"
      assert FeatureRepository.get_features() == %{}
    end
  end

  describe "feature fetching" do
    test "fetches features on demand" do
      start_supervised!(
        {FeatureRepository,
         client_key: "client-key",
         api_host: "https://cdn.growthbook.io",
         refresh_strategy: :manual}
      )

      Process.sleep(100)
      features = FeatureRepository.get_features()

      assert features["feature-1"]["defaultValue"] == true
      assert features["feature-2"]["defaultValue"] == "test"
    end

    test "handles network errors gracefully" do
      start_supervised!(
        {FeatureRepository,
         client_key: "timeout-key",
         api_host: "https://cdn.growthbook.io",
         refresh_strategy: :manual}
      )

      # Need to wait for the timeout simulation
      Process.sleep(300)

      log =
        capture_log(fn ->
          FeatureRepository.refresh()
          Process.sleep(300)
        end)

      assert log =~ "Failed to fetch features"
      assert FeatureRepository.get_features() == %{}
    end

    test "handles invalid JSON responses" do
      start_supervised!(
        {FeatureRepository,
         client_key: "invalid-json-key",
         api_host: "https://cdn.growthbook.io",
         refresh_strategy: :manual}
      )

      Process.sleep(100)

      log =
        capture_log(fn ->
          FeatureRepository.refresh()
          Process.sleep(100)
        end)

      assert log =~ "Failed to decode API response"
      assert FeatureRepository.get_features() == %{}
    end
  end

  describe "callback functionality" do
    test "calls the refresh callback when features are updated" do
      test_pid = self()

      start_supervised!(
        {FeatureRepository,
         client_key: "client-key",
         api_host: "https://cdn.growthbook.io",
         refresh_strategy: :manual,
         on_refresh: fn features ->
           send(test_pid, {:features_refreshed, features})
         end}
      )

      Process.sleep(100)
      FeatureRepository.refresh()

      assert_receive {:features_refreshed, features}, 1000
      assert Map.has_key?(features, "feature-1")
    end
  end

  describe "encrypted features" do
    test "requires decryption key for encrypted features" do
      log =
        capture_log(fn ->
          start_supervised!(
            {FeatureRepository,
             client_key: "encrypted-client-key", api_host: "https://cdn.growthbook.io"}
          )

          Process.sleep(100)
        end)

      assert log =~ "Received encrypted features but no decryption key provided"
      assert FeatureRepository.get_features() == %{}
    end

    test "handles encrypted features with decryption key" do
      # Create a module to patch DecryptionUtils.decrypt for this test
      # This avoids issues with mocking entire modules
      defmodule TestHelpers do
        # Store the original function
        @original &GrowthBook.DecryptionUtils.decrypt/2

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

      # Test with decryption key
      start_supervised!(
        {FeatureRepository,
         client_key: "encrypted-client-key",
         api_host: "https://cdn.growthbook.io",
         decryption_key: "test-key"}
      )

      Process.sleep(100)
      features = FeatureRepository.get_features()

      # Restore the original function
      TestHelpers.unpatch_decrypt()

      # Check that decryption worked
      assert Map.has_key?(features, "feature-1")
      assert Map.has_key?(features, "secret-feature")
      assert features["feature-1"]["defaultValue"] == "decrypted-value"
      assert features["secret-feature"]["defaultValue"] == true
    end
  end

  describe "auto refresh" do
    test "refreshes features after TTL expires" do
      start_supervised!({
        FeatureRepository,
        # Very short TTL for testing
        client_key: "client-key", api_host: "https://cdn.growthbook.io", swr_ttl_seconds: 1
      })

      Process.sleep(100)

      # Force the state to have an old last_fetch time
      :sys.replace_state(FeatureRepository, fn state ->
        %{state | last_fetch: DateTime.add(DateTime.utc_now(), -10)}
      end)

      # This should trigger a refresh due to expired TTL
      log =
        capture_log(fn ->
          FeatureRepository.get_features()
          Process.sleep(100)
        end)

      assert log =~ "Features cache expired"
    end
  end
end
