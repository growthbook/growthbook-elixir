# Changelog

## 0.4.0 (2026-10-30)

### Breaking changes

**This is a breaking runtime upgrade, even though the SDK remains on a 0.x version.**

Version 0.4.0 requires **Elixir 1.17 or later and Erlang/OTP 27 or later**.
Earlier runtimes are no longer supported and cannot be relied on to build the updated dependencies.

Before upgrading:

1. Check your versions with `elixir --version`.
2. Upgrade Elixir and Erlang/OTP in development, CI, production, and any deployment images to a compatible pair meeting both minimums.
3. Set the SDK dependency to `{:growthbook, "~> 0.4.0"}`, run `mix deps.update growthbook`, and test your application before deploying.

### Breaking changes in evaluation (SDK spec 0.12.0)

- Targeting conditions are strict about types. Values are no longer converted between types (`"10"` doesn't match `10`, and `0` doesn't match a missing attribute), and negated operators always give the opposite result of their positive form. Two strings compare as text, booleans can't be compared with greater than or less than, and version operators need two strings or two numbers.
- Conditions that use an operator or saved group type this SDK doesn't support always fail, even under `$not` or `$nor`.
- Only strings and numbers can be hash attributes. Other values (booleans, lists, maps, `0` and `""`) count as missing, so the user isn't included in the experiment or rollout. Whole-number floats hash like integers (`1.0` like `1`).
- Hashing uses UTF-16 code units, like the JavaScript SDK. Bucketing only changes for ids and experiment or feature keys that contain non-ASCII characters (such as `é`, CJK or emoji).
- Percentage rollouts no longer include one extra hash bucket.
- Experiments no longer use `fallbackAttribute`. The JavaScript SDK only uses it with sticky bucketing, which this SDK doesn't support.
- A feature value of `"off"` is now on, matching JavaScript truthiness.

### Added

- `GrowthBook.prune_condition/3` and `GrowthBook.reduce_payload/2` shrink a payload to what one user needs.

### Dependency range warning

Existing requirements such as `~> 0.2` and `~> 0.3` **allow 0.4.0**. Your `mix.lock` keeps the currently resolved version until a dependency update changes it; updating dependencies can therefore introduce this breaking runtime requirement without changing `mix.exs`.

To defer the upgrade, constrain the SDK to your current minor version. For example, `~> 0.3.0` allows 0.3.x releases but excludes 0.4.0. Staying on an older release does not include the dependency security update in this release.

### Security

- Upgrade HTTPoison to 3.x and hackney to 4.x to address upstream security vulnerabilities.
