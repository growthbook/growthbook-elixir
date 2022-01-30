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
      refute Condition.eval_condition(%{}, %{"$elemMatch" => nil})
    end

    test "handles numeric type-conversion like JS" do
      refute Condition.eval_condition(%{}, %{"$elemMatch" => nil})
    end

    test "numeric type conversion on eval_condition_value" do
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => 123})
      assert Condition.eval_condition(%{"a" => "123.0"}, %{"a" => 123.0})
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => 123.0})
    end

    test "$gt performs type conversions on number-string comparison" do
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gt" => "122"}})
      refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gt" => "123"}})
      refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gt" => "124"}})

      assert Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$gt" => "122"}})
      refute Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$gt" => "123"}})
      refute Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$gt" => "124"}})
      refute Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$gt" => "d124"}})

      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gt" => 122}})
      refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gt" => 123}})
      refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gt" => 124}})
      refute Condition.eval_condition(%{"a" => "d123"}, %{"a" => %{"$gt" => 124}})
    end

    test "$gte performs type conversions on number-string comparison" do
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gte" => "122"}})
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gte" => "123"}})
      refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gte" => "124"}})

      assert Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$gte" => "122"}})
      assert Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$gte" => "123"}})
      refute Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$gte" => "124"}})
      refute Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$gte" => "d124"}})

      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gte" => 122}})
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gte" => 123}})
      refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$gte" => 124}})
      refute Condition.eval_condition(%{"a" => "d123"}, %{"a" => %{"$gte" => 124}})
    end

    test "$lt performs type conversions on number-string comparison" do
      refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$lt" => "122"}})
      refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$lt" => "123"}})
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$lt" => "124"}})

      refute Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$lt" => "122"}})
      refute Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$lt" => "123"}})
      assert Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$lt" => "124"}})
      refute Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$lt" => "d124"}})

      refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$lt" => 122}})
      refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$lt" => 123}})
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$lt" => 124}})
      refute Condition.eval_condition(%{"a" => "d123"}, %{"a" => %{"$lt" => 124}})
    end

    test "$lte performs type conversions on number-string comparison" do
      refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$lte" => "122"}})
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$lte" => "123"}})
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$lte" => "124"}})

      refute Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$lte" => "122"}})
      assert Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$lte" => "123"}})
      assert Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$lte" => "124"}})
      refute Condition.eval_condition(%{"a" => 123}, %{"a" => %{"$lte" => "d124"}})

      refute Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$lte" => 122}})
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$lte" => 123}})
      assert Condition.eval_condition(%{"a" => "123"}, %{"a" => %{"$lte" => 124}})
      refute Condition.eval_condition(%{"a" => "d123"}, %{"a" => %{"$lte" => 124}})
    end
  end
end
