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

  def round_number(number) when is_float(number), do: round_float(number)
  def round_number(number), do: number

  # Payload filters from a spec case, as `GrowthBook.reduce_payload/2` takes them
  def filters_from_json(nil), do: nil

  def filters_from_json(filters) do
    [
      projects: filters["projects"],
      tags: filters["tags"],
      custom_fields: filters["customFields"]
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end
end
