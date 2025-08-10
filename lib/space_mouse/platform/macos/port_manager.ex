defmodule SpaceMouse.Platform.MacOS.PortManager do
  @moduledoc """
  Manages the external C HID reader process via Erlang ports.
  
  This module handles:
  - Starting/stopping the C HID reader program  
  - Parsing structured output from the C program
  - Converting C output to Elixir messages
  - Managing process lifecycle and error handling
  """

  use GenServer
  require Logger

  defmodule State do
    @moduledoc false
    defstruct [
      :port,
      :owner_pid,
      :hid_reader_path
    ]
  end

  # Client API

  @doc """
  Start the HID reader port manager.
  """
  def start_hid_reader(opts \\ []) do
    GenServer.start(__MODULE__, opts)
  end

  @doc """
  Stop the HID reader port manager.
  """
  def stop_hid_reader(pid) do
    GenServer.stop(pid, :normal)
  end

  # GenServer Implementation

  @impl true
  def init(opts) do
    owner_pid = Keyword.get(opts, :owner_pid, self())
    
    # Build path to the HID reader executable
    priv_dir = :code.priv_dir(:space_mouse)
    hid_reader_path = Path.join([priv_dir, "platform", "macos", "hid_reader"])
    
    # Verify the executable exists
    case File.exists?(hid_reader_path) do
      true ->
        state = %State{
          port: nil,
          owner_pid: owner_pid,
          hid_reader_path: hid_reader_path
        }
        
        # Start the HID reader process
        case start_hid_reader_port(state) do
          {:ok, new_state} ->
            {:ok, new_state}
            
          {:error, reason} ->
            {:stop, reason}
        end
        
      false ->
        {:stop, {:error, {:hid_reader_not_found, hid_reader_path}}}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %State{port: port} = state) do
    # Parse data from the C program
    case parse_hid_output(data) do
      {:ok, event} ->
        # Forward parsed event to owner
        send(state.owner_pid, {:hid_event, event})
        
      {:error, reason} ->
        Logger.warning("Failed to parse HID output: #{inspect(reason)}, data: #{inspect(data)}")
    end
    
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %State{port: port} = state) do
    Logger.warning("HID reader process exited with status: #{status}")
    
    # Notify owner of port exit
    send(state.owner_pid, {:port_exit, status})
    
    {:stop, :normal, %{state | port: nil}}
  end

  @impl true
  def handle_info({:EXIT, port, reason}, %State{port: port} = state) do
    Logger.warning("HID reader port process died: #{inspect(reason)}")
    
    # Notify owner of port exit  
    send(state.owner_pid, {:port_exit, reason})
    
    {:stop, :normal, %{state | port: nil}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.port do
      Port.close(state.port)
    end
    :ok
  end

  # Private Implementation

  defp start_hid_reader_port(state) do
    Logger.info("Starting HID reader: #{state.hid_reader_path}")
    
    try do
      port = Port.open({:spawn_executable, state.hid_reader_path}, [
        :binary,
        :exit_status,
        {:line, 1024},  # Line-based communication
        {:cd, Path.dirname(state.hid_reader_path)}
      ])
      
      # Link to the port process for automatic cleanup
      Process.link(port)
      
      new_state = %{state | port: port}
      {:ok, new_state}
      
    rescue
      error ->
        Logger.error("Failed to start HID reader: #{inspect(error)}")
        {:error, {:spawn_failed, error}}
    end
  end

  defp parse_hid_output(data) do
    line = case data do
      {:eol, text} -> String.trim(text)
      binary when is_binary(binary) -> String.trim(binary)
      other -> inspect(other)
    end
    
    case String.split(line, ":", parts: 2) do
      ["STATUS", message] ->
        {:ok, %{type: :status, message: message, timestamp: System.monotonic_time(:millisecond)}}
        
      ["MOTION", params] ->
        parse_motion_event(params)
        
      ["BUTTON", params] ->
        parse_button_event(params)
        
      _ ->
        {:error, {:unknown_format, line}}
    end
  end

  defp parse_motion_event(params) do
    try do
      # Parse "x=123,y=456,z=789,rx=12,ry=34,rz=56" format
      axis_data = 
        params
        |> String.split(",")
        |> Enum.reduce(%{}, fn param, acc ->
          case String.split(param, "=", parts: 2) do
            [key, value] ->
              Map.put(acc, String.to_atom(key), String.to_integer(value))
            _ ->
              acc
          end
        end)
      
      event = %{
        type: :motion,
        data: axis_data,
        timestamp: System.monotonic_time(:millisecond)
      }
      
      {:ok, event}
      
    rescue
      error ->
        {:error, {:motion_parse_error, error, params}}
    end
  end

  defp parse_button_event(params) do
    try do
      # Parse "id=1,state=pressed" format
      button_data = 
        params
        |> String.split(",")
        |> Enum.reduce(%{}, fn param, acc ->
          case String.split(param, "=", parts: 2) do
            ["id", value] ->
              Map.put(acc, :id, String.to_integer(value))
            ["state", value] ->
              Map.put(acc, :state, String.to_atom(value))
            _ ->
              acc
          end
        end)
      
      event = %{
        type: :button,
        data: button_data,
        timestamp: System.monotonic_time(:millisecond)
      }
      
      {:ok, event}
      
    rescue
      error ->
        {:error, {:button_parse_error, error, params}}
    end
  end
end
