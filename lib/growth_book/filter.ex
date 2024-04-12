defmodule GrowthBook.Filter do
  @moduledoc """
  Object used for mutual exclusion and filtering users out of experiments based on random hashes. Has the following properties:
  """

  alias GrowthBook.BucketRange

  @typedoc """
  Filter

  A **Filter** has the follwing properties:

  - **`seed`** (`t:String.t/0`) - Teh sedd used in the hash
  - **`ranges`** (list of `t:GrowthBook.BucketRange.t/0`) - List of ranges that are included
  - **`hash_version`** (`t:integer/0`) - The hash version to use (default to 2)
  - **`attribute`** (`t:String.t/0`) - The attribute to use (default to "id")
  """
  @type t() :: %__MODULE__{
     seed: String.t(),
     ranges: [BucketRange.t()],
     hash_version: integer() ,
     attribute: String.t()
  }

  defstruct [
    :seed,
    :ranges,
    hash_version: 2,
    attribute: "id"
  ]

  def from_json(map) when is_map(map) do
    %__MODULE__{
      seed: map["seed"] || "",
      ranges: Enum.map(map["ranges"] || [], &BucketRange.from_json/1),
      hash_version: map["hashVersion"] || 2,
      attribute: map["attribute"] || "id"
    }
  end
end
