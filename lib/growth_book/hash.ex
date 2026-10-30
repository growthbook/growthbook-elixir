defmodule GrowthBook.Hash do
  @type value() :: String.t() | number()
  @type seed() :: String.t() | number()
  @type version() :: 1 | 2

  @doc """
  Hashes a string to a float between `0.0` and `1.0`, using the
  [Fowler-Noll-Vo](https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function)
  (`fnv32a`) algorithm.

  Strings are hashed by UTF-16 code unit, like JavaScript's `charCodeAt`, and numbers are
  formatted like JavaScript's `String()`, so `1.0` hashes as `"1"`.
  """
  @spec hash(seed(), value(), version()) :: float() | nil
  def hash(seed, value, version) do
    seed = to_hash_string(seed)
    value = to_hash_string(value)

    case version do
      1 -> hash_v1(seed, value)
      2 -> hash_v2(seed, value)
      _ -> nil
    end
  end

  @doc """
  Formats a hash value like JavaScript's `String()`: integral numbers have no decimal part.
  """
  @spec to_hash_string(term()) :: String.t()
  def to_hash_string(value) when is_float(value) and value == trunc(value),
    do: Integer.to_string(trunc(value))

  def to_hash_string(value), do: to_string(value)

  defp hash_v1(seed, value) do
    (value <> seed)
    |> fnv32a_utf16()
    |> mod(1000)
  end

  defp hash_v2(seed, value) do
    (seed <> value)
    |> fnv32a_utf16()
    |> Integer.to_string()
    |> fnv32a()
    |> mod(10000)
  end

  defp mod(n, m), do: rem(n, m) / m

  @fnv32_prime 16_777_619
  @fnv32_init 2_166_136_261
  @fnv32_mask 0xFFFFFFFF

  # FNV-1a over the string's UTF-16 code units. ASCII strings hash the same as their bytes.
  defp fnv32a_utf16(string) do
    if ascii?(string) do
      fnv32a(string)
    else
      string
      |> :unicode.characters_to_binary(:utf8, {:utf16, :little})
      |> fnv32a_units(@fnv32_init)
    end
  end

  defp ascii?(<<c, rest::binary>>) when c < 128, do: ascii?(rest)
  defp ascii?(<<>>), do: true
  defp ascii?(_non_ascii), do: false

  defp fnv32a_units(<<unit::little-16, tail::binary>>, state) do
    import Bitwise, only: [band: 2, bxor: 2]

    fnv32a_units(tail, band(bxor(state, unit) * @fnv32_prime, @fnv32_mask))
  end

  defp fnv32a_units(<<>>, state), do: state

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
