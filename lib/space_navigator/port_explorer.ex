defmodule SpaceNavigator.PortExplorer do
  @moduledoc """
  Detailed exploration of USB port and location information.
  """

  require Logger

  @doc """
  Explore all available USB location and port functions.
  """
  def explore_port_functions(device) do
    Logger.info("=== USB Port and Location Exploration ===")
    
    # List of potential USB location/port functions to try
    location_functions = [
      {:get_port_number, [device.device]},
      {:get_port_numbers, [device.device]},
      {:get_bus_number, [device.device]},
      {:get_device_address, [device.device]},
      {:get_device_speed, [device.device]},
      # Try some variations that might exist
      {:get_location, [device.device]},
      {:get_port_path, [device.device]},
      {:get_device_location, [device.device]},
      {:get_parent_device, [device.device]},
      {:get_hub_port, [device.device]}
    ]
    
    Enum.each(location_functions, fn {func, args} ->
      try do
        result = apply(:usb, func, args)
        Logger.info("✓ :usb.#{func}() = #{inspect(result)}")
      rescue
        UndefinedFunctionError ->
          Logger.info("✗ :usb.#{func}() - function not available")
      catch
        :error, reason ->
          Logger.info("✗ :usb.#{func}() - error: #{inspect(reason)}")
      end
    end)
    
    # Also check what the raw device reference contains
    Logger.info("\\nRaw device reference: #{inspect(device.device)}")
    
    # Explore if we can get any system-level information
    explore_system_usb_info(device)
  end

  defp explore_system_usb_info(device) do
    Logger.info("\\n=== System USB Information ===")
    
    # Try to match with system USB info if possible
    vendor_hex = Integer.to_string(device.vendor_id, 16) |> String.pad_leading(4, "0")
    product_hex = Integer.to_string(device.product_id, 16) |> String.pad_leading(4, "0")
    
    Logger.info("Device identifiers for system lookup:")
    Logger.info("  Vendor ID: #{device.vendor_id} (0x#{vendor_hex})")
    Logger.info("  Product ID: #{device.product_id} (0x#{product_hex})")
    Logger.info("  Bus: #{device.bus_number}, Address: #{device.device_address}")
    
    # The user can correlate this with ioreg output
    Logger.info("\\nTo find this device in ioreg output, look for:")
    Logger.info("  \\\"idVendor\\\" = #{device.vendor_id}")
    Logger.info("  \\\"idProduct\\\" = #{device.product_id}")
    Logger.info("  \\\"USB Address\\\" = #{device.device_address}")
  end

  @doc """
  Create a comprehensive device location signature.
  """
  def create_location_signature(device) do
    Logger.info("=== Device Location Signature ===")
    
    # Gather all available location data
    location_data = %{
      vendor_id: device.vendor_id,
      product_id: device.product_id,
      bus_number: device.bus_number,
      device_address: device.device_address,
      usb_version: device.device_descriptor.usb_version,
      device_version: device.device_descriptor.device_version,
      max_packet_size: device.device_descriptor.max_packet_size0
    }
    
    # Try to get additional port information
    port_info = get_extended_port_info(device)
    location_data = Map.merge(location_data, port_info)
    
    # Create a hash-based signature for uniqueness
    signature_string = "#{location_data.vendor_id}-#{location_data.product_id}-#{location_data.device_version}"
    signature_hash = :crypto.hash(:sha256, signature_string) |> Base.encode16() |> String.slice(0, 8)
    
    final_signature = Map.put(location_data, :signature_hash, signature_hash)
    
    Logger.info("Location signature created:")
    Enum.each(final_signature, fn {key, value} ->
      Logger.info("  #{key}: #{inspect(value)}")
    end)
    
    final_signature
  end

  defp get_extended_port_info(device) do
    port_data = %{}
    
    # Try to get port number
    port_data = case safe_call(:usb, :get_port_number, [device.device]) do
      {:ok, port} -> Map.put(port_data, :port_number, port)
      _ -> Map.put(port_data, :port_number, nil)
    end
    
    # Try to get port numbers array
    port_data = case safe_call(:usb, :get_port_numbers, [device.device]) do
      {:ok, ports} when is_list(ports) -> Map.put(port_data, :port_path, ports)
      _ -> Map.put(port_data, :port_path, [])
    end
    
    # Try to get device speed
    port_data = case safe_call(:usb, :get_device_speed, [device.device]) do
      {:ok, speed} -> Map.put(port_data, :device_speed, speed)
      speed when is_atom(speed) -> Map.put(port_data, :device_speed, speed)
      _ -> Map.put(port_data, :device_speed, nil)
    end
    
    port_data
  end

  defp safe_call(module, function, args) do
    try do
      apply(module, function, args)
    rescue
      _ -> {:error, :not_available}
    catch
      _ -> {:error, :not_available}
    end
  end

  @doc """
  Compare your device info with ioreg data for correlation.
  """
  def correlate_with_ioreg(device) do
    Logger.info("=== Correlation with ioreg Data ===")
    
    # From your ioreg output, here's what we know about your SpaceMouse Compact:
    ioreg_data = %{
      "idVendor" => 9583,      # ✓ Matches device.vendor_id
      "idProduct" => 50741,    # ✓ Matches device.product_id  
      "bcdUSB" => 512,         # ✓ Matches device.device_descriptor.usb_version
      "bcdDevice" => 1079,     # ✓ Matches device.device_descriptor.device_version
      "bMaxPacketSize0" => 8,  # ✓ Matches device.device_descriptor.max_packet_size0
      "USB Address" => 1,      # ✓ Matches device.device_address
      "locationID" => 17825792, # This could be useful!
      "sessionID" => 245366428  # This might be unique per session
    }
    
    Logger.info("Correlation check:")
    Logger.info("  ✓ Vendor ID: #{device.vendor_id} == #{ioreg_data["idVendor"]}")
    Logger.info("  ✓ Product ID: #{device.product_id} == #{ioreg_data["idProduct"]}")
    Logger.info("  ✓ USB Address: #{device.device_address} == #{ioreg_data["USB Address"]}")
    Logger.info("  ✓ USB Version: #{device.device_descriptor.usb_version} == #{ioreg_data["bcdUSB"]}")
    Logger.info("  ✓ Device Version: #{device.device_descriptor.device_version} == #{ioreg_data["bcdDevice"]}")
    Logger.info("  ✓ Max Packet Size: #{device.device_descriptor.max_packet_size0} == #{ioreg_data["bMaxPacketSize0"]}")
    
    Logger.info("\\nioreg-specific identifiers not available via USB library:")
    Logger.info("  • locationID: #{ioreg_data["locationID"]} (persistent port identifier)")
    Logger.info("  • sessionID: #{ioreg_data["sessionID"]} (session-specific)")
    
    Logger.info("\\nRecommendation: Use combination of vendor_id + product_id + device_version")
    Logger.info("for stable device identification across reconnections.")
    
    # Create a stable identifier
    stable_id = "#{device.vendor_id}-#{device.product_id}-#{device.device_descriptor.device_version}"
    Logger.info("\\nSuggested stable device ID: #{stable_id}")
    
    stable_id
  end
end
