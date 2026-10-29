# Changelog

## 0.4.0 (Unreleased)

### Breaking changes

**This is a breaking runtime upgrade, even though the SDK remains on a 0.x version.**

Version 0.4.0 requires **Elixir 1.17 or later and Erlang/OTP 27 or later**.
Earlier runtimes are no longer supported and cannot be relied on to build the updated dependencies.

Before upgrading:

1. Check your versions with `elixir --version`.
2. Upgrade Elixir and Erlang/OTP in development, CI, production, and any deployment images to a compatible pair meeting both minimums.
3. Set the SDK dependency to `{:growthbook, "~> 0.4.0"}`, run `mix deps.update growthbook`, and test your application before deploying.

### Dependency range warning

Existing requirements such as `~> 0.2` and `~> 0.3` **allow 0.4.0**. Your `mix.lock` keeps the currently resolved version until a dependency update changes it; updating dependencies can therefore introduce this breaking runtime requirement without changing `mix.exs`.

To defer the upgrade, constrain the SDK to your current minor version. For example, `~> 0.3.0` allows 0.3.x releases but excludes 0.4.0. Staying on an older release does not include the dependency security update in this release.

### Security

- Upgrade HTTPoison to 3.x and hackney to 4.x to address upstream security vulnerabilities.
