defmodule SpaceNavigator.DeviceMetadata do
  @moduledoc """
  Module for exploring comprehensive USB device metadata and identification.
  
  This module investigates all available ways to uniquely identify USB devices:
  - Device descriptor information
  - Port and location data
  - String descriptors (manufacturer, product, serial)
  - Device speed and version information
  - Configuration and interface details
  """

  alias SpaceNavigator.UsbManager
  require Logger

  @doc """
  Get comprehensive metadata for all USB devices.
  """
  def get_all_device_metadata do
    Logger.info("=== Comprehensive USB Device Metadata ===")
    
    case UsbManager.list_devices() do
      {:ok, devices} ->
        Logger.info("Found #{length(devices)} device(s)")
        
        devices
        |> Enum.with_index(1)
        |> Enum.each(fn {device, index} ->
          Logger.info("\\n--- Device #{index} ---")
          explore_device_metadata(device)
        end)
        
        {:ok, devices}
        
      {:error, reason} ->
        Logger.error("Failed to list devices: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Explore all available metadata for a specific device.
  """
  def explore_device_metadata(device) do
    Logger.info("Basic Device Information:")
    Logger.info("  Vendor ID: 0x#{Integer.to_string(device.vendor_id, 16) |> String.pad_leading(4, "0")}")
    Logger.info("  Product ID: 0x#{Integer.to_string(device.product_id, 16) |> String.pad_leading(4, "0")}")
    Logger.info("  Bus Number: #{device.bus_number}")
    Logger.info("  Device Address: #{device.device_address}")
    
    # Explore device descriptor in detail
    explore_device_descriptor(device.device_descriptor)
    
    # Try to get port information
    explore_port_information(device)
    
    # Try to get device speed
    explore_device_speed(device)
    
    # Try to get string descriptors
    explore_string_descriptors(device)
    
    # Try to get configuration descriptors
    explore_configuration_descriptors(device)
  end

  defp explore_device_descriptor(descriptor) do
    Logger.info("\\nDevice Descriptor Details:")
    Logger.info("  USB Version: #{format_bcd_version(descriptor.usb_version)}")
    Logger.info("  Device Version: #{format_bcd_version(descriptor.device_version)}")
    Logger.info("  Class Code: #{descriptor.class_code}")
    Logger.info("  Sub-Class Code: #{descriptor.sub_class_code}")
    Logger.info("  Protocol Code: #{descriptor.protocol_code}")
    Logger.info("  Max Packet Size (EP0): #{descriptor.max_packet_size0} bytes")
    Logger.info("  Number of Configurations: #{descriptor.num_configurations}")
    Logger.info("  Manufacturer String Index: #{descriptor.manufacturer_string_index}")
    Logger.info("  Product String Index: #{descriptor.product_string_index}")
    Logger.info("  Serial Number String Index: #{descriptor.serial_number_string_index}")
  end

  defp explore_port_information(device) do
    Logger.info("\\nPort Information:")
    
    # Try to get port number
    case safe_usb_call(:get_port_number, [device.device]) do
      {:ok, port} ->
        Logger.info("  Port Number: #{port}")
      result ->
        Logger.info("  Port Number: #{inspect(result)}")
    end
    
    # Try to get port numbers (path)
    case safe_usb_call(:get_port_numbers, [device.device]) do
      {:ok, ports} when is_list(ports) ->
        Logger.info("  Port Path: #{Enum.join(ports, " -> ")}")
      result ->
        Logger.info("  Port Path: #{inspect(result)}")
    end
  end

  defp explore_device_speed(device) do
    Logger.info("\\nDevice Speed Information:")
    
    case safe_usb_call(:get_device_speed, [device.device]) do
      {:ok, speed} ->
        speed_name = case speed do
          0 -> "Unknown/Variable"
          1 -> "Low Speed (1.5 Mbit/s)"
          2 -> "Full Speed (12 Mbit/s)"
          3 -> "High Speed (480 Mbit/s)"
          4 -> "Super Speed (5 Gbit/s)"
          5 -> "Super Speed+ (10 Gbit/s)"
          _ -> "Unknown (#{speed})"
        end
        Logger.info("  Speed: #{speed_name}")
      result ->
        Logger.info("  Speed: #{inspect(result)}")
    end
  end

  defp explore_string_descriptors(device) do
    Logger.info("\\nString Descriptors:")
    
    # Try to read manufacturer string
    if device.device_descriptor.manufacturer_string_index > 0 do
      case get_string_descriptor(device, device.device_descriptor.manufacturer_string_index) do
        {:ok, manufacturer} ->
          Logger.info("  Manufacturer: \"#{manufacturer}\"")
        error ->
          Logger.info("  Manufacturer: Failed to read (#{inspect(error)})")
      end
    else
      Logger.info("  Manufacturer: No string descriptor")
    end
    
    # Try to read product string
    if device.device_descriptor.product_string_index > 0 do
      case get_string_descriptor(device, device.device_descriptor.product_string_index) do
        {:ok, product} ->
          Logger.info("  Product: \"#{product}\"")
        error ->
          Logger.info("  Product: Failed to read (#{inspect(error)})")
      end
    else
      Logger.info("  Product: No string descriptor")
    end
    
    # Try to read serial number string
    if device.device_descriptor.serial_number_string_index > 0 do
      case get_string_descriptor(device, device.device_descriptor.serial_number_string_index) do
        {:ok, serial} ->
          Logger.info("  Serial Number: \"#{serial}\"")
        error ->
          Logger.info("  Serial Number: Failed to read (#{inspect(error)})")
      end
    else
      Logger.info("  Serial Number: No string descriptor")
    end
  end

  defp explore_configuration_descriptors(device) do
    Logger.info("\\nConfiguration Information:")
    
    # Try to get configuration descriptor for configuration 0
    case safe_usb_call(:get_config_descriptor, [device.device, 0]) do
      {:ok, config} ->
        Logger.info("  Configuration 0:")
        Logger.info("    Total Length: #{Map.get(config, :total_length, "unknown")} bytes")
        Logger.info("    Number of Interfaces: #{Map.get(config, :num_interfaces, "unknown")}")
        Logger.info("    Configuration Value: #{Map.get(config, :configuration_value, "unknown")}")
        Logger.info("    Attributes: 0x#{Integer.to_string(Map.get(config, :attributes, 0), 16)}")
        Logger.info("    Max Power: #{Map.get(config, :max_power, "unknown")} mA")
      error ->
        Logger.info("  Configuration 0: Failed to read (#{inspect(error)})")
    end
  end

  defp get_string_descriptor(device, index) do
    # Note: The USB library might not support string descriptor reading directly
    # This is a placeholder for when we implement it or find the right function
    case safe_usb_call(:get_string_descriptor, [device.device, index]) do
      {:ok, string} -> {:ok, string}
      _ -> {:error, :not_supported}
    end
  end

  defp safe_usb_call(function, args) do
    try do
      apply(:usb, function, args)
    rescue
      UndefinedFunctionError ->
        {:error, :function_not_available}
      e ->
        {:error, e}
    end
  end

  defp format_bcd_version(bcd) do
    major = div(bcd, 256)
    minor = div(rem(bcd, 256), 16)
    patch = rem(bcd, 16)
    "#{major}.#{minor}.#{patch}"
  end

  @doc """
  Create a unique device fingerprint combining multiple identifiers.
  """
  def create_device_fingerprint(device) do
    # Gather all available identifying information
    basic_id = "#{device.vendor_id}:#{device.product_id}"
    location_id = "#{device.bus_number}:#{device.device_address}"
    
    # Try to get port path for more stable identification
    port_path = case safe_usb_call(:get_port_numbers, [device.device]) do
      {:ok, ports} when is_list(ports) -> Enum.join(ports, "-")
      _ -> "unknown"
    end
    
    # Create a composite fingerprint
    fingerprint = %{
      vendor_product: basic_id,
      bus_address: location_id,
      port_path: port_path,
      usb_version: device.device_descriptor.usb_version,
      device_version: device.device_descriptor.device_version,
      max_packet_size: device.device_descriptor.max_packet_size0,
      num_configurations: device.device_descriptor.num_configurations
    }
    
    Logger.info("Device Fingerprint:")
    Logger.info("  Vendor:Product = #{fingerprint.vendor_product}")
    Logger.info("  Bus:Address = #{fingerprint.bus_address}")
    Logger.info("  Port Path = #{fingerprint.port_path}")
    Logger.info("  USB Version = #{format_bcd_version(fingerprint.usb_version)}")
    Logger.info("  Device Version = #{format_bcd_version(fingerprint.device_version)}")
    
    fingerprint
  end

  @doc """
  Generate a stable device ID that persists across reconnections.
  """
  def generate_stable_device_id(device) do
    # Use port path if available, as it's more stable than bus:address
    case safe_usb_call(:get_port_numbers, [device.device]) do
      {:ok, ports} when is_list(ports) ->
        port_path = Enum.join(ports, "-")
        stable_id = "#{device.vendor_id}-#{device.product_id}-port-#{port_path}"
        Logger.info("Stable Device ID (port-based): #{stable_id}")
        {:ok, stable_id}
        
      _ ->
        # Fallback to basic identification
        basic_id = "#{device.vendor_id}-#{device.product_id}-#{device.device_descriptor.device_version}"
        Logger.info("Basic Device ID (version-based): #{basic_id}")
        {:fallback, basic_id}
    end
  end
end
