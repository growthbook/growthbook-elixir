# GrowthBook

[Online documentation](https://hexdocs.pm/growthbook) | [Hex.pm](https://hex.pm/packages/growthbook)

> NOTE: This library is in active development, and the API may change.

<!-- MDOC !-->

`GrowthBook` is a [GrowthBook](https://growthbook.io) SDK for Elixir/OTP.

This SDK follows the guidelines set out in [GrowthBook's documentation](https://docs.growthbook.io/lib/build-your-own), and the API is tested on conformance with the test cases from the JS SDK.

To ensure an Elixir-friendly API, the implementation deviates from the official SDK in the following ways:

- Instead of tuple-lists, this library uses actual tuples
- Comparisons with `undefined` are implemented by using `:undefined`
- Function names are converted to `snake_case`, and `is_` prefix is replaced with a `?` suffix
- Instead of classes, a Context struct is used (similar to `%Plug.Conn{}` in `plug`)
- There may be some discrepancies between handling of Truthy values between the JS and Elixir SDKs (if you notice this, a issue, or better, a PR is welcome)

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
    {:growthbook, "~> 0.1"}
  ]
end
```

## Usage

```elixir
# Create a context, which can be reused for multiple users
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

context = %GrowthBook.Context{
  enabled?: true,
  features: features,
  attributes: %{
    "id" => "12345",
    "country_code" => "NL",
    "browser" => "chrome"
  }
}

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

## License

This library is MIT licensed. See the
[LICENSE](https://github.com/growthbook/growthbook-elixir/blob/main/LICENSE)
file in this repository for details.

