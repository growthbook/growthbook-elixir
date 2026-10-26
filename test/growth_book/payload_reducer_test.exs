defmodule GrowthBook.PayloadReducerTest do
  use ExUnit.Case, async: true

  doctest GrowthBook, only: [prune_condition: 3, reduce_payload: 2]
end
