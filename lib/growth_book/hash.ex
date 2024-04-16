defmodule GrowthBook.Hash do
  @type value() :: String.t() | integer()
  @type seed() :: String.t() | integer()
  @type version() :: 1 | 2

  @doc """
  Hashes a string to a float between `0.0` and `1.0`, using the
  [Fowler-Noll-Vo](https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function)
  (`fnv32a`) algorithm.
  """
  @spec hash(seed(), value(), version()) :: float() | nil
  def hash(seed, value, version) do
    seed = to_string(seed)
    value = to_string(value)

    case version do
      1 -> hash_v1(seed, value)
      2 -> hash_v2(seed, value)
      _ -> nil
    end
  end

  defp hash_v1(seed, value) do
    (value <> seed)
    |> fnv32a()
    |> mod(1000)
  end

  defp hash_v2(seed, value) do
    (seed <> value)
    |> fnv32a()
    |> Integer.to_string()
    |> fnv32a()
    |> mod(10000)
  end

  defp mod(n, m), do: rem(n, m) / m

  @fnv32_prime 16_777_619
  @fnv32_init 2_166_136_261
  @fnv32_mask 0xFFFFFFFF

  # Fowler-Noll-Vo 32-bit FNV-1a hash
  @doc false
  @spec fnv32a(binary(), integer()) :: integer()
  def fnv32a(data, state \\ @fnv32_init)

  def fnv32a(<<head::8, tail::binary>>, state) do
    import Bitwise, only: [band: 2, bxor: 2]

    hash = band(bxor(state, head) * @fnv32_prime, @fnv32_mask)

    fnv32a(tail, hash)
  end

  def fnv32a(<<>>, state), do: state
end
