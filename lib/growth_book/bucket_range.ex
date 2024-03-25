defmodule GrowthBook.BucketRange do
  @moduledoc """
  A tuple that describes a range of the numberline between 0 and 1.
  The tuple has 2 parts, both floats - the start of the range and the end.

  For example:

  ```
  {0.3, 0.7}
  ```
  """
  @type t() :: {number(), number()}

  def from_json(nil), do: nil
  def from_json([min, max]) when is_number(min) and is_number(max) do
    {min, max}
  end
end
