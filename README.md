# GrowthBook - Elixir SDK

![Elixir SDK for the GrowthBook feature flagging and AB testing platform](https://docs.growthbook.io/images/GrowthBook-hero-elixir.png)

[Online documentation](https://hexdocs.pm/growthbook) | [Hex.pm](https://hex.pm/packages/growthbook)

<!-- MDOC !-->

`GrowthBook` is a [GrowthBook](https://growthbook.io) SDK for Elixir/OTP.

This SDK follows the guidelines set out in [GrowthBook's documentation](https://docs.growthbook.io/lib/build-your-own), and the API is tested on conformance with the test cases from the JS SDK.

To ensure an Elixir-friendly API, the implementation deviates from the official SDK in the following ways:

- Instead of tuple-lists, this library uses actual tuples
- Comparisons with `undefined` are implemented by using `:undefined`
- Function names are converted to `snake_case`, and `is_` prefix is replaced with a `?` suffix
- Instead of classes, a Context struct is used (similar to `%Plug.Conn{}` in `plug`)

## What is GrowthBook?

[GrowthBook](https://www.growthbook.io) is an open source A/B testing platform. The platform works
significantly different from other A/B testing platforms, most notably: it is language agnostic.

Clients by default work offline, and manage their own data. This means that you are free to
implement A/B tests server-side, or client-side without worrying about things like "anti-flicker"
scripts, or the added latency of JS embeds.

Furthermore, GrowthBook supports both experiments (A/B tests and multivariate tests) and feature
flags. Because all logic to run experiments and feature flags is contained in the library, there
is virtually no added latency to running experiments or using feature flags.

## Installation

Add `growthbook` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:growthbook, "~> 0.2"}
  ]
end
```

## Usage

```elixir
# Create a context, which can be reused for multiple users
# Approach 1: Manual Feature Configuration
features_config = Jason.decode!("""
{
  "features": {
    "send-reminder": {
      "defaultValue": false,
      "rules": [{ "condition": { "browser": "chrome" }, "force": true }]
    },
    "add-to-cart-btn-color": {
      "rules": [{ "variations": [{ "color": "red" }, { "color": "green" }] }]
    }
  }
}
""")

features = GrowthBook.Config.features_from_config(features_config)

context = GrowthBook.build_context(
  %{
    "id" => "12345",
    "country_code" => "NL",
    "browser" => "chrome"
  },
  features  # Explicitly provide features
)

# Approach 2: Auto-refreshing Features
case GrowthBook.init(
  client_key: "key_123",
  api_host: "https://cdn.growthbook.io"
) do
  {:ok, :initialized} ->
    Logger.info("GrowthBook ready to use")
    # Start using GrowthBook...
    
  {:error, reason} ->
    Logger.error("Failed to initialize GrowthBook: #{reason}")
    # Handle initialization failure...
end

# Create context that automatically uses latest features
context = GrowthBook.build_context(%{
  "id" => "12345",
  "country_code" => "NL",
  "browser" => "chrome"
})

# Usage is the same for both approaches:

# Use a feature toggle
if GrowthBook.feature(context, "send-reminder").on? do
  Logger.info("Sending reminder")
end

# Use a feature's value
color = GrowthBook.feature(context, "add-to-cart-btn-color").value["color"]
Logger.info("Color: " <> color)

# Run an inline experiment
if GrowthBook.run(context, %GrowthBook.Experiment{
  key: "checkout-v2",
  active?: true,
  coverage: 1,
  variations: [1, 2]
}).in_experiment? do
  Logger.info("In experiment")
end
```

## Auto-Refresh Features

GrowthBook now supports automatic feature refreshing from your GrowthBook API. Instead of manually managing features, you can initialize GrowthBook with your API credentials:

```elixir
# Initialize GrowthBook with auto-refresh
GrowthBook.init(
  client_key: "key_prod_123...",
  api_host: "https://cdn.growthbook.io",
  decryption_key: "key_123...",  # Optional: Required for encrypted features
  swr_ttl_seconds: 60,  # Optional: Default is 60 seconds
  on_refresh: fn features ->  # Optional: Callback when features are refreshed
    Logger.info("Features refreshed: #{map_size(features)} available")
    # Notify your application about new features
    MyApp.FeatureNotifier.features_updated(features)
  end
)

# Create context that automatically uses latest features
context = GrowthBook.build_context(%{
  "id" => "12345",
  "country_code" => "NL",
  "browser" => "chrome"
})

# Features will automatically refresh in the background
# All feature evaluations will use the latest features
if GrowthBook.feature(context, "send-reminder").on? do
  Logger.info("Sending reminder")
end
```

Key improvements:

- **Auto-refresh**: Features automatically refresh from your GrowthBook API
- **Encryption**: Support for encrypted feature payloads
- **Callbacks**: Get notified when features are updated
- **Resilient**: Keeps existing features on API errors
- **Configurable**: Control refresh intervals and strategies

## License

This library is MIT licensed. See the
[LICENSE](https://github.com/growthbook/growthbook-elixir/blob/main/LICENSE)
file in this repository for details.
