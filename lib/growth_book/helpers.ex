defmodule GrowthBook.Helpers do
  @moduledoc """
  GrowthBook internal helper functions.

  A collection of helper functions for use internally inside the `GrowthBook` library. You should
  not (have to) use any of these functions in your own application. They are documented for
  library developers only. Breaking changes in this module will not be considered breaking
  changes in the library's public API (or cause a minor/major semver update).
  """

  alias GrowthBook.{Hash, BucketRange}

  @doc """
  This checks if a userId is within an experiment namespace or not.
  """
  @spec in_namespace?(String.t(), GrowthBook.namespace() | nil) :: boolean()
  def in_namespace?(_, nil) do
    true
  end

  def in_namespace?(user_id, {namespace, min, max}) do
    hash = Hash.hash("__#{namespace}", user_id, 1)
    hash >= min and hash < max
  end

  @doc """
  Determines if a number n is within the provided range.
  """
  @spec in_range?(number(), BucketRange.t()) :: boolean()
  def in_range?(n, {min, max}), do: n >= min and n < max

  @doc """
  Determines if the user is part of a gradual feature rollout.
  """
  @spec included_in_rollout?(map(), String.t(), String.t(), BucketRange.t(), number(), integer()) ::
          boolean()
  def included_in_rollout?(_attributes, _seed, _hash_attribute, nil, nil, _hash_version), do: true

  def included_in_rollout?(_attributes, _seed, _hash_attribute, nil, coverage, _hash_version)
      when coverage == 0,
      do: false

  def included_in_rollout?(attributes, seed, hash_attribute, range, coverage, hash_version) do
    case hash_value(attributes, coalesce(hash_attribute, "id")) do
      nil ->
        false

      hash_value ->
        n = Hash.hash(seed, hash_value, hash_version(hash_version))

        case {range, coverage} do
          {nil, coverage} -> n < coverage
          {range, _} -> in_range?(n, range)
        end
    end
  end

  @doc """
  Returns the attribute's value if it can identify a user, otherwise `nil`.

  Only a non-empty string or a non-zero number can. Anything else, such as `0`, `true`, a list
  or a map, counts as missing, like in the JS SDK.
  """
  @spec hash_value(map() | nil, String.t()) :: String.t() | number() | nil
  def hash_value(attributes, attribute) when is_map(attributes) do
    case Map.get(attributes, attribute) do
      value when is_binary(value) and value != "" -> value
      value when is_number(value) and value != 0 -> value
      _missing -> nil
    end
  end

  def hash_value(_attributes, _attribute), do: nil

  @spec coalesce([any()]) :: any()
  @spec coalesce(any(), any()) :: any()
  def coalesce(v1, v2), do: coalesce([v1, v2])
  def coalesce([last]), do: last
  def coalesce([nil | next]), do: coalesce(next)
  def coalesce(["" | next]), do: coalesce(next)
  def coalesce([v | _]), do: v

  @spec hash_version(integer() | nil) :: integer()
  def hash_version(v) when v in [nil, 0], do: 1
  def hash_version(v), do: v

  @doc """
  Returns an list of floats with `count` items that are all equal and sum to 1.

  ## Examples

      iex> GrowthBook.Helpers.get_equal_weights(2)
      [0.5, 0.5]
  """
  @spec get_equal_weights(integer()) :: [float()]
  def get_equal_weights(count) when count < 1, do: []
  def get_equal_weights(count), do: List.duplicate(1.0 / count, count)

  @doc """
  Converts and experiment's coverage and variation weights into a list of bucket ranges.

  ## Examples

      iex> GrowthBook.Helpers.get_bucket_ranges(2, 1, [0.5, 0.5])
      [{0.0, 0.5}, {0.5, 1.0}]

      iex> GrowthBook.Helpers.get_bucket_ranges(2, 0.5, [0.4, 0.6])
      [{0.0, 0.2}, {0.4, 0.7}]
  """
  @spec get_bucket_ranges(integer(), float(), [float()] | nil) :: [GrowthBook.bucket_range()]
  def get_bucket_ranges(count, coverage, nil), do: get_bucket_ranges(count, coverage, [])

  def get_bucket_ranges(count, coverage, weights) do
    coverage = max(min(coverage, 1.0), 0.0)

    # Default to equal weights if the number of weights is not equal to count,
    # or if the sum isn't close to 1.0
    weights =
      if abs(1 - Enum.sum(weights)) < 0.01 and length(weights) == count,
        do: weights,
        else: get_equal_weights(count)

    {ranges, _acc} =
      Enum.map_reduce(weights, 0.0, fn weight, acc ->
        {{acc, acc + coverage * weight}, acc + weight}
      end)

    ranges
  end

  @doc """
  Given a hash and bucket ranges, assign one of the bucket ranges.
  """
  @spec choose_variation(float(), [GrowthBook.bucket_range()]) :: integer()
  def choose_variation(hash, bucket_ranges) do
    Enum.find_index(bucket_ranges, fn {min, max} -> hash >= min and hash < max end) || -1
  end

  @doc """
  Checks if an experiment variation is being forced via a URL query string.

  ## Examples

      iex> GrowthBook.Helpers.get_query_string_override("my-test", "http://localhost/?my-test=1", 2)
      1

      iex> GrowthBook.Helpers.get_query_string_override("my-test", "not valid", 2)
      nil
  """
  @spec get_query_string_override(String.t(), String.t(), integer()) :: integer() | nil
  def get_query_string_override(experiment_id, url, count) do
    with {:ok, %URI{query: query}} <- URI.new(url),
         %{^experiment_id => variation} <- URI.decode_query(query || ""),
         {index, ""} when index >= 0 and index < count <- Integer.parse(variation) do
      index
    else
      _missing_or_parse_error -> nil
    end
  end

  # JavaScript truthiness: "off", [] and %{} are all on
  @doc false
  @spec cast_boolish(term()) :: boolean()
  def cast_boolish(""), do: false
  def cast_boolish(n) when is_number(n) and n == 0, do: false
  def cast_boolish(false), do: false
  def cast_boolish(nil), do: false
  def cast_boolish(:undefined), do: false
  def cast_boolish(_truthy), do: true
end
