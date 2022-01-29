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
end
