defmodule GrowthBook.PayloadReducerTest do
  use ExUnit.Case, async: true

  doctest GrowthBook, only: [prune_condition: 3, reduce_payload: 2]

  defp feature_using(group_ids) do
    rules =
      Enum.map(group_ids, &%{"force" => true, "condition" => %{"$savedGroup" => %{"id" => &1}}})

    %{"flag" => %{"defaultValue" => false, "rules" => rules}}
  end

  test "reduces many condition groups that share one large list group" do
    list = %{"type" => "list", "attributeKey" => "id", "values" => Enum.map(1..10_000, &"u#{&1}")}
    ids = Enum.map(1..300, &"c#{&1}")

    condition_groups =
      Map.new(ids, fn id ->
        {id,
         %{
           "type" => "condition",
           "condition" => %{"plan" => "pro", "id" => %{"$inGroup" => "big"}}
         }}
      end)

    payload = %{
      "features" => feature_using(ids),
      "savedGroups" => Map.put(condition_groups, "big", list)
    }

    reduced = GrowthBook.reduce_payload(payload, attributes: %{"plan" => "pro"})

    assert map_size(reduced["savedGroups"]) == 301
    assert reduced["savedGroups"]["big"] == list

    for id <- ids do
      assert reduced["savedGroups"][id]["condition"] == %{"id" => %{"$inGroup" => "big"}}
    end
  end

  test "keeps condition groups on a cycle as written and reduces the rest" do
    groups = %{
      # a two-group cycle
      "a" => %{
        "type" => "condition",
        "condition" => %{"$or" => [%{"$savedGroup" => %{"id" => "b"}}, %{"x" => true}]}
      },
      "b" => %{
        "type" => "condition",
        "condition" => %{"$and" => [%{"$savedGroup" => %{"id" => "a"}}, %{"y" => 1}]}
      },
      # a group that references itself
      "self" => %{
        "type" => "condition",
        "condition" => %{
          "plan" => "pro",
          "$or" => [%{"$savedGroup" => %{"id" => "self"}}, %{"z" => 1}]
        }
      },
      # references the cycle but isn't on it
      "outside" => %{
        "type" => "condition",
        "condition" => %{"plan" => "pro", "$savedGroup" => %{"id" => "a"}}
      },
      "plain" => %{"type" => "condition", "condition" => %{"plan" => "pro", "z" => 1}}
    }

    payload = %{
      "features" => feature_using(["a", "self", "outside", "plain"]),
      "savedGroups" => groups
    }

    reduced = GrowthBook.reduce_payload(payload, attributes: %{"plan" => "pro"})["savedGroups"]

    assert reduced["a"] == groups["a"]
    assert reduced["b"] == groups["b"]
    assert reduced["self"] == groups["self"]
    assert reduced["outside"]["condition"] == %{"$savedGroup" => %{"id" => "a"}}
    assert reduced["plain"]["condition"] == %{"z" => 1}
  end

  test "never follows a list group's values to other groups" do
    vip = %{
      "type" => "condition",
      "condition" => %{"plan" => "pro", "id" => %{"$inGroup" => "ids"}}
    }

    for ids <- [%{"type" => "list", "attributeKey" => "id", "values" => ["vip"]}, ["vip"]] do
      # "ids" names "vip" only as an attribute value, so "vip" isn't on a cycle and is reduced
      payload = %{
        "features" => feature_using(["vip"]),
        "savedGroups" => %{"vip" => vip, "ids" => ids}
      }

      reduced = GrowthBook.reduce_payload(payload, attributes: %{"plan" => "pro"})["savedGroups"]
      assert reduced["vip"]["condition"] == %{"id" => %{"$inGroup" => "ids"}}
      assert reduced["ids"] == ids

      # A list group under $elemMatch doesn't mark the groups its values name as written
      payload = %{
        "features" => %{
          "flag" => %{
            "defaultValue" => false,
            "rules" => [
              %{
                "force" => true,
                "condition" => %{
                  "tags" => %{"$elemMatch" => %{"$inGroup" => "ids"}},
                  "$savedGroup" => %{"id" => "vip"}
                }
              }
            ]
          }
        },
        "savedGroups" => %{"vip" => vip, "ids" => ids}
      }

      reduced = GrowthBook.reduce_payload(payload, attributes: %{"plan" => "pro"})["savedGroups"]
      assert reduced["vip"]["condition"] == %{"id" => %{"$inGroup" => "ids"}}

      # A group named only in a list's values isn't kept
      payload = %{
        "features" => %{
          "flag" => %{
            "defaultValue" => false,
            "rules" => [%{"force" => true, "condition" => %{"id" => %{"$inGroup" => "ids"}}}]
          }
        },
        "savedGroups" => %{"vip" => vip, "ids" => ids}
      }

      assert GrowthBook.reduce_payload(payload)["savedGroups"] == %{"ids" => ids}
    end
  end

  test "skips the saved group walks when the payload has no groups" do
    # Only a map holds groups, so a malformed empty list is no groups rather than an error
    payload = %{"features" => feature_using(["missing"]), "savedGroups" => []}

    assert GrowthBook.reduce_payload(payload)["savedGroups"] == %{}
  end

  test "leaves contextualBandits out when the payload has none" do
    for bandits <- [:absent, nil, false] do
      payload = %{"features" => feature_using([]), "savedGroups" => %{}}

      payload =
        if bandits == :absent, do: payload, else: Map.put(payload, "contextualBandits", bandits)

      refute Map.has_key?(GrowthBook.reduce_payload(payload), "contextualBandits")
    end

    payload = %{"features" => %{}, "contextualBandits" => %{}}
    assert GrowthBook.reduce_payload(payload)["contextualBandits"] == %{}
  end
end
