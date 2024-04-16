defmodule GrowthBook.CaseHelper do
  def round_tuple(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> round_tuple()

  def round_tuple(tuple_or_list) do
    tuple_or_list
    |> Enum.map(fn
      value when is_float(value) -> round_float(value)
      value -> value
    end)
    |> List.to_tuple()
  end

  def round_tuples(tuples), do: Enum.map(tuples, &round_tuple/1)
  def tuples(lists), do: Enum.map(lists, &List.to_tuple/1)

  def round_float(float) when is_float(float), do: Float.round(float, 8)
end
