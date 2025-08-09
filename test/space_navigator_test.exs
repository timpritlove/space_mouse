defmodule SpaceNavigatorTest do
  use ExUnit.Case
  doctest SpaceNavigator

  test "greets the world" do
    assert SpaceNavigator.hello() == :world
  end
end
