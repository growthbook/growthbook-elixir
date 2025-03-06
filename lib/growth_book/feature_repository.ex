defmodule GrowthBook.FeatureRepository do
  @moduledoc """
  Repository for fetching and caching features from a GrowthBook API endpoint.
  """

  use GenServer
  require Logger

  @default_ttl 60
  @default_api_host "https://cdn.growthbook.io"

  defstruct [
    :client_key,
    :api_host,
    :decryption_key,
    :swr_ttl_seconds,
    :refresh_strategy,
    :features,
    :last_fetch,
    :on_refresh_callback
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Logger.info("Initializing GrowthBook FeatureRepository")

    state = %__MODULE__{
      client_key: opts[:client_key],
      api_host: normalize_api_host(opts[:api_host]),
      decryption_key: opts[:decryption_key],
      swr_ttl_seconds: opts[:swr_ttl_seconds] || @default_ttl,
      refresh_strategy: opts[:refresh_strategy] || :periodic,
      features: %{},
      last_fetch: nil,
      on_refresh_callback: opts[:on_refresh]
    }

    Logger.info(
      "FeatureRepository configured with:" <>
        " api_host=#{state.api_host}" <>
        " ttl=#{state.swr_ttl_seconds}s" <>
        " refresh_strategy=#{state.refresh_strategy}" <>
        " decryption_enabled=#{!is_nil(state.decryption_key)}"
    )

    if state.refresh_strategy == :periodic do
      schedule_refresh(state.swr_ttl_seconds)
    end

    # Initial fetch
    {:ok, refresh_features(state)}
  end

  @impl true
  def handle_call(:get_features, _from, state) do
    state = maybe_refresh_features(state)
    {:reply, state.features, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    {:noreply, refresh_features(state)}
  end

  @impl true
  def handle_info(:refresh, state) do
    if state.refresh_strategy == :periodic do
      schedule_refresh(state.swr_ttl_seconds)
    end

    {:noreply, refresh_features(state)}
  end

  def get_features do
    GenServer.call(__MODULE__, :get_features)
  end

  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  defp maybe_refresh_features(%{last_fetch: nil} = state), do: refresh_features(state)

  defp maybe_refresh_features(state) do
    elapsed = DateTime.diff(DateTime.utc_now(), state.last_fetch)

    if elapsed > state.swr_ttl_seconds do
      Logger.debug(
        "Features cache expired (#{elapsed}s > #{state.swr_ttl_seconds}s), refreshing..."
      )

      refresh_features(state)
    else
      state
    end
  end

  defp refresh_features(state) do
    Logger.debug("Fetching features from GrowthBook API...")

    case fetch_features(state) do
      {:ok, features} ->
        Logger.info("Successfully fetched #{map_size(features)} features from GrowthBook")
        new_state = %{state | features: features, last_fetch: DateTime.utc_now()}

        if is_function(state.on_refresh_callback) do
          try do
            state.on_refresh_callback.(features)
          rescue
            e ->
              Logger.error("Error in refresh callback: #{Exception.message(e)}")
          end
        end

        new_state

      {:error, reason} ->
        Logger.error("Failed to fetch features: #{inspect(reason)}")
        # Keep existing features on error
        state
    end
  end

  defp fetch_features(%{api_host: host, client_key: key} = state) do
    url = "#{host}/api/features/#{key}"

    Logger.debug("Requesting features from #{url}")

    try do
      case HTTPoison.get(url) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          parsed = Jason.decode!(body)

          features =
            cond do
              Map.has_key?(parsed, "encryptedFeatures") && state.decryption_key ->
                Logger.debug("Decrypting encrypted features")
                decrypt_features(parsed["encryptedFeatures"], state.decryption_key)

              Map.has_key?(parsed, "encryptedFeatures") ->
                Logger.error("Received encrypted features but no decryption key provided")
                {:error, "Decryption key required for encrypted features"}

              Map.has_key?(parsed, "features") ->
                Logger.debug("Using unencrypted features")
                {:ok, parsed["features"]}

              true ->
                {:error, "Invalid response format"}
            end

          case features do
            {:ok, features_map} -> {:ok, features_map}
            {:error, reason} -> {:error, reason}
          end

        {:ok, %HTTPoison.Response{status_code: status}} ->
          {:error, "API request failed with status #{status}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, "HTTP request failed: #{inspect(reason)}"}
      end
    rescue
      e in Jason.DecodeError ->
        {:error, "Failed to decode API response: #{Exception.message(e)}"}

      e ->
        {:error, "Unexpected error: #{Exception.message(e)}"}
    end
  end

  defp decrypt_features(encrypted_features, decryption_key) do
    try do
      case GrowthBook.DecryptionUtils.decrypt(encrypted_features, decryption_key) do
        {:ok, decrypted_json} ->
          case Jason.decode(decrypted_json) do
            {:ok, features} -> {:ok, features}
            {:error, _} -> {:error, "Failed to parse decrypted features"}
          end

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Failed to decrypt features: #{Exception.message(e)}")
        {:error, "Decryption failed"}
    end
  end

  defp normalize_api_host(nil), do: @default_api_host
  defp normalize_api_host(""), do: @default_api_host

  defp normalize_api_host(host) do
    String.trim_trailing(host, "/")
  end

  defp schedule_refresh(ttl) do
    Process.send_after(self(), :refresh, :timer.seconds(ttl))
  end
end
