defmodule SpaceMouse.Core.Supervisor do
  @moduledoc """
  Supervisor for the SpaceMouse core system.
  
  This supervisor manages the main device GenServer and ensures proper
  fault tolerance and recovery for the SpaceMouse communication system.
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    children = [
      # Main device manager
      {SpaceMouse.Core.Device, opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
