defmodule GrowthBook.ConditionTest do
  use ExUnit.Case, async: true
  alias GrowthBook.Condition
  doctest GrowthBook.Condition

  describe "Condition.get_type/1" do
    test "returns the type of the value" do
      assert "string" == Condition.get_type("value")
      assert "number" == Condition.get_type(1)
      assert "number" == Condition.get_type(1.0)
      assert "boolean" == Condition.get_type(true)
      assert "array" == Condition.get_type([1, 2, 3])
      assert "object" == Condition.get_type(%{})
      assert "null" == Condition.get_type(nil)
      assert "undefined" == Condition.get_type(:undefined)
      assert "unknown" == Condition.get_type(:ok)
    end
  end

  describe "Condition.get_path/2" do
    test "retrieves value at path" do
      assert 1 == Condition.get_path(%{"a" => %{"b" => %{"c" => 1}}}, "a.b.c")
      assert nil == Condition.get_path(%{"a" => %{"b" => %{"c" => nil}}}, "a.b.c")
    end

    test "falls back to :undefined if path is not found" do
      assert :undefined == Condition.get_path(%{"a" => %{"b" => %{"c" => 1}}}, "a.b.d")
    end

    test "returns :undefined if path isn't all maps" do
      assert :undefined == Condition.get_path(%{"a" => %{"b" => nil}}, "a.b.c")
      assert :undefined == Condition.get_path(%{"a" => %{"b" => [nil]}}, "a.b.c")
    end
  end

  describe "Condition.eval_condition/2" do
    test "skips non-operator values" do
      refute Condition.eval_condition(%{}, %{"id" => %{"$elemMatch" => nil}})
    end

    test "equality does not convert between numbers and strings" do
      refute Condition.eval_condition(%{"a" => "123"}, %{"a" => 123})
      refute Condition.eval_condition(%{"a" => "123.0"}, %{"a" => 123.0})
      refute Condition.eval_condition(%{"a" => 123}, %{"a" => "123"})
      assert Condition.eval_condition(%{"a" => 123}, %{"a" => 123.0})
    end

    test "$gt, $gte, $lt and $lte compare two strings as text" do
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gt" => "122"}})
      refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gt" => "123"}})
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gte" => "123"}})
      assert Condition.eval_condition(%{"a" => "10"}, %{"a" => %{"$lt" => "9"}})
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$lte" => "123"}})
    end

    test "$gt, $gte, $lt and $lte fail on a number-string mismatch" do
      for op <- ["$gt", "$gte", "$lt", "$lte"] do
        refute Condition.eval_condition(%{"a" => 123}, %{"a" => %{op => "122"}})
        refute Condition.eval_condition(%{"a" => 123}, %{"a" => %{op => "124"}})
        refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{op => 122}})
        refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{op => 124}})
        assert Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$not" => %{op => "122"}}})
      end
    end

    test "$in, $nin, $ini, $nini and list saved groups do not look inside nested arrays" do
      attrs = %{"a" => [[1], ["x"]]}
      groups = %{"g" => [1]}

      for condition <- [
            %{"a" => %{"$in" => [1]}},
            %{"a" => %{"$ini" => ["X"]}},
            %{"a" => %{"$inGroup" => "g"}}
          ] do
        refute Condition.eval_condition(attrs, condition, groups)
        assert Condition.prune_condition(attrs, condition, groups) == false
      end

      for condition <- [
            %{"a" => %{"$nin" => [1]}},
            %{"a" => %{"$nini" => ["X"]}},
            %{"a" => %{"$notInGroup" => "g"}}
          ] do
        assert Condition.eval_condition(attrs, condition, groups)
        assert Condition.prune_condition(attrs, condition, groups) == true
      end

      assert Condition.eval_condition(%{"a" => [[1], 1]}, %{"a" => %{"$in" => [1]}})
    end

    test "$regex and $regexi match non-ASCII text by character" do
      assert Condition.eval_condition(%{"a" => "É"}, %{"a" => %{"$regexi" => "^é$"}})
      assert Condition.prune_condition(%{"a" => "É"}, %{"a" => %{"$regexi" => "^é$"}}) == true
      refute Condition.eval_condition(%{"a" => "É"}, %{"a" => %{"$regex" => "^é$"}})
      assert Condition.eval_condition(%{"a" => "é"}, %{"a" => %{"$regex" => "^.$"}})
      assert Condition.eval_condition(%{"a" => "é"}, %{"a" => %{"$regexi" => "^.$"}})
    end

    test "case-insensitive operators lowercase a final sigma like JavaScript" do
      attrs = %{"a" => "ΟΣ", "list" => ["ΟΣ"]}

      for condition <- [
            %{"a" => %{"$ini" => ["ος"]}},
            %{"list" => %{"$alli" => ["ος"]}},
            %{"a" => %{"$not" => %{"$nini" => ["ος"]}}}
          ] do
        assert Condition.eval_condition(attrs, condition)
        assert Condition.prune_condition(attrs, condition) == true
      end
    end
  end
end
