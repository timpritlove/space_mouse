defmodule SpaceNavigator.HidParser do
  @moduledoc """
  HID Report Descriptor parser for SpaceMouse devices.
  
  This module parses HID report descriptors to extract:
  - Report structures and formats
  - Endpoint addresses
  - Input/Output report layouts
  - Usage information for 6DOF motion data
  """

  require Logger
  import Bitwise

  # HID Item Types
  @item_type_main 0
  @item_type_global 1
  @item_type_local 2

  # Main Items
  @main_input 0x08
  @main_output 0x09
  @main_feature 0x0B
  @main_collection 0x0A
  @main_end_collection 0x0C

  # Global Items
  @global_usage_page 0x00
  @global_logical_min 0x01
  @global_logical_max 0x02
  @global_physical_min 0x03
  @global_physical_max 0x04
  @global_unit_exponent 0x05
  @global_unit 0x06
  @global_report_size 0x07
  @global_report_id 0x08
  @global_report_count 0x09

  # Local Items
  @local_usage 0x00
  @local_usage_min 0x01
  @local_usage_max 0x02

  # Usage Pages
  @usage_page_generic_desktop 0x01

  @usage_page_button 0x09

  # Generic Desktop Usages
  @usage_pointer 0x01
  @usage_mouse 0x02
  @usage_joystick 0x04
  @usage_gamepad 0x05

  @usage_multi_axis_controller 0x08
  @usage_x 0x30
  @usage_y 0x31
  @usage_z 0x32
  @usage_rx 0x33
  @usage_ry 0x34
  @usage_rz 0x35
  @usage_slider 0x36
  @usage_dial 0x37
  @usage_wheel 0x38

  defmodule ParseState do
    defstruct [
      :usage_page,
      :logical_min,
      :logical_max,
      :physical_min,
      :physical_max,
      :report_size,
      :report_count,
      :report_id,
      :unit,
      :unit_exponent,
      :usage,
      :usage_min,
      :usage_max,
      :collection_level,
      :reports,
      :current_report,
      :position
    ]
  end

  defmodule ReportInfo do
    defstruct [
      :type,          # :input, :output, :feature
      :report_id,     # Report ID (if any)
      :size_bits,     # Total size in bits
      :fields,        # List of field definitions
      :usage_page,    # Main usage page
      :usage          # Main usage
    ]
  end

  defmodule FieldInfo do
    defstruct [
      :usage_page,
      :usage,
      :logical_min,
      :logical_max,
      :physical_min,
      :physical_max,
      :report_size,   # Size in bits
      :report_count,  # Number of fields
      :bit_offset,    # Offset in report
      :flags          # Input/Output flags
    ]
  end

  @doc """
  Parse HID report descriptor and extract SpaceMouse configuration.
  """
  def parse_spacemouse_descriptor do
    Logger.info("=== Parsing SpaceMouse HID Report Descriptor ===")
    
    case get_spacemouse_descriptor() do
      {:ok, descriptor} ->
        Logger.info("Got HID descriptor: #{byte_size(descriptor)} bytes")
        
        # Parse the descriptor
        case parse_hid_descriptor(descriptor) do
          {:ok, parsed_info} ->
            analyze_spacemouse_reports(parsed_info)
            show_endpoint_recommendations(parsed_info)
            {:ok, parsed_info}
            
          {:error, reason} ->
            Logger.error("Failed to parse HID descriptor: #{inspect(reason)}")
            {:error, reason}
        end
        
      {:error, reason} ->
        Logger.error("Could not get HID descriptor: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_spacemouse_descriptor do
    case SpaceNavigator.UsbManager.find_devices(%{vendor_id: 0x256F}) do
      {:ok, [device | _]} ->
        case SpaceNavigator.UsbManager.open_device(device) do
          {:ok, connected_device} ->
            # Get HID Report Descriptor via control transfer
            case :usb.read_control(
              connected_device.handle,
              0x81,    # bmRequestType: Device to Host, Standard, Interface
              0x06,    # bRequest: GET_DESCRIPTOR
              0x2200,  # wValue: Report Descriptor (0x22) + index 0
              0,       # wIndex: Interface 0
              512,     # wLength: Max descriptor size
              5000     # timeout
            ) do
              {:ok, data} when byte_size(data) > 0 ->
                {:ok, data}
                
              {:error, reason} ->
                {:error, reason}
            end
            
          {:error, reason} ->
            {:error, reason}
        end
        
      error ->
        error
    end
  end

  @doc """
  Parse a HID report descriptor binary.
  """
  def parse_hid_descriptor(descriptor) do
    Logger.info("Parsing HID descriptor (#{byte_size(descriptor)} bytes)...")
    
    initial_state = %ParseState{
      collection_level: 0,
      reports: [],
      position: 0
    }
    
    case parse_items(descriptor, initial_state) do
      {:ok, final_state} ->
        Logger.info("✓ Parsing complete, found #{length(final_state.reports)} reports")
        {:ok, final_state}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_items(<<>>, state) do
    {:ok, state}
  end

  defp parse_items(<<item_byte, rest::binary>>, state) do
    # Parse HID item header
    size = item_byte &&& 0x03
    type = (item_byte >>> 2) &&& 0x03
    tag = (item_byte >>> 4) &&& 0x0F
    
    # Extract data based on size
    {data, remaining} = case size do
      0 -> {0, rest}
      1 -> <<value, remaining::binary>> = rest; {value, remaining}
      2 -> <<value::little-16, remaining::binary>> = rest; {value, remaining}
      3 -> <<value::little-32, remaining::binary>> = rest; {value, remaining}
    end
    
    # Process the item
    {:ok, new_state} = process_hid_item(type, tag, data, state)
    parse_items(remaining, %{new_state | position: state.position + 1 + size})
  end

  defp process_hid_item(@item_type_main, tag, data, state) do
    case tag do
      @main_input ->
        field_info = create_field_info(state, data, :input)
        report = add_field_to_current_report(state, field_info, :input)
        {:ok, %{state | current_report: report}}
        
      @main_output ->
        field_info = create_field_info(state, data, :output)
        report = add_field_to_current_report(state, field_info, :output)
        {:ok, %{state | current_report: report}}
        
      @main_feature ->
        field_info = create_field_info(state, data, :feature)
        report = add_field_to_current_report(state, field_info, :feature)
        {:ok, %{state | current_report: report}}
        
      @main_collection ->
        Logger.debug("Collection start (level #{state.collection_level})")
        {:ok, %{state | collection_level: state.collection_level + 1}}
        
      @main_end_collection ->
        new_level = max(0, state.collection_level - 1)
        Logger.debug("Collection end (level #{new_level})")
        
        # If we're ending the top-level collection, finalize current report
        new_state = if new_level == 0 and state.current_report do
          reports = [state.current_report | state.reports]
          %{state | reports: reports, current_report: nil}
        else
          state
        end
        
        {:ok, %{new_state | collection_level: new_level}}
        
      _ ->
        Logger.debug("Unknown main item: tag=#{tag}, data=#{data}")
        {:ok, state}
    end
  end

  defp process_hid_item(@item_type_global, tag, data, state) do
    case tag do
      @global_usage_page ->
        {:ok, %{state | usage_page: data}}
        
      @global_logical_min ->
        {:ok, %{state | logical_min: data}}
        
      @global_logical_max ->
        {:ok, %{state | logical_max: data}}
        
      @global_physical_min ->
        {:ok, %{state | physical_min: data}}
        
      @global_physical_max ->
        {:ok, %{state | physical_max: data}}
        
      @global_report_size ->
        {:ok, %{state | report_size: data}}
        
      @global_report_count ->
        {:ok, %{state | report_count: data}}
        
      @global_report_id ->
        Logger.info("Report ID: #{data}")
        {:ok, %{state | report_id: data}}
        
      @global_unit ->
        {:ok, %{state | unit: data}}
        
      @global_unit_exponent ->
        {:ok, %{state | unit_exponent: data}}
        
      _ ->
        Logger.debug("Unknown global item: tag=#{tag}, data=#{data}")
        {:ok, state}
    end
  end

  defp process_hid_item(@item_type_local, tag, data, state) do
    case tag do
      @local_usage ->
        usage_name = get_usage_name(state.usage_page, data)
        Logger.debug("Usage: #{usage_name} (page=#{state.usage_page}, usage=#{data})")
        {:ok, %{state | usage: data}}
        
      @local_usage_min ->
        {:ok, %{state | usage_min: data}}
        
      @local_usage_max ->
        {:ok, %{state | usage_max: data}}
        
      _ ->
        Logger.debug("Unknown local item: tag=#{tag}, data=#{data}")
        {:ok, state}
    end
  end

  defp process_hid_item(type, tag, data, state) do
    Logger.debug("Unknown item type: type=#{type}, tag=#{tag}, data=#{data}")
    {:ok, state}
  end

  defp create_field_info(state, flags, _type) do
    %FieldInfo{
      usage_page: state.usage_page,
      usage: state.usage,
      logical_min: state.logical_min,
      logical_max: state.logical_max,
      physical_min: state.physical_min,
      physical_max: state.physical_max,
      report_size: state.report_size,
      report_count: state.report_count,
      flags: flags
    }
  end

  defp add_field_to_current_report(state, field_info, type) do
    current_report = state.current_report || %ReportInfo{
      type: type,
      report_id: state.report_id,
      fields: [],
      usage_page: state.usage_page,
      usage: state.usage,
      size_bits: 0
    }
    
    # Calculate bit offset for this field
    bit_offset = current_report.size_bits
    field_with_offset = %{field_info | bit_offset: bit_offset}
    
    # Update report
    field_size_bits = (field_info.report_size || 0) * (field_info.report_count || 1)
    %{current_report |
      fields: [field_with_offset | current_report.fields],
      size_bits: current_report.size_bits + field_size_bits
    }
  end

  defp get_usage_name(@usage_page_generic_desktop, usage) do
    case usage do
      @usage_pointer -> "Pointer"
      @usage_mouse -> "Mouse"
      @usage_joystick -> "Joystick"
      @usage_gamepad -> "Gamepad"
      @usage_multi_axis_controller -> "Multi-axis Controller"
      @usage_x -> "X"
      @usage_y -> "Y"
      @usage_z -> "Z"
      @usage_rx -> "Rx"
      @usage_ry -> "Ry"
      @usage_rz -> "Rz"
      @usage_slider -> "Slider"
      @usage_dial -> "Dial"
      @usage_wheel -> "Wheel"
      _ -> "Generic Desktop (#{usage})"
    end
  end

  defp get_usage_name(@usage_page_button, usage) do
    "Button #{usage}"
  end

  defp get_usage_name(page, usage) do
    "Usage #{usage} (page #{page})"
  end

  defp analyze_spacemouse_reports(state) do
    Logger.info("\\n=== SpaceMouse Report Analysis ===")
    
    state.reports
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.each(fn {report, index} ->
      analyze_report(report, index)
    end)
  end

  defp analyze_report(report, index) do
    Logger.info("\\nReport #{index} (#{report.type}):")
    Logger.info("  Report ID: #{inspect(report.report_id)}")
    Logger.info("  Total size: #{report.size_bits} bits (#{div(report.size_bits + 7, 8)} bytes)")
    Logger.info("  Usage: #{get_usage_name(report.usage_page, report.usage)}")
    Logger.info("  Fields: #{length(report.fields)}")
    
    report.fields
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.each(fn {field, field_index} ->
      Logger.info("    Field #{field_index}: #{get_usage_name(field.usage_page, field.usage)}")
      Logger.info("      Size: #{field.report_size} bits × #{field.report_count} = #{(field.report_size || 0) * (field.report_count || 1)} bits")
      Logger.info("      Range: #{field.logical_min} to #{field.logical_max}")
      Logger.info("      Bit offset: #{field.bit_offset}")
      
      if field.usage_page == @usage_page_generic_desktop do
        case field.usage do
          @usage_x -> Logger.info("      → Translation X axis")
          @usage_y -> Logger.info("      → Translation Y axis")
          @usage_z -> Logger.info("      → Translation Z axis")
          @usage_rx -> Logger.info("      → Rotation X axis")
          @usage_ry -> Logger.info("      → Rotation Y axis")
          @usage_rz -> Logger.info("      → Rotation Z axis")
          _ -> nil
        end
      end
    end)
  end

  defp show_endpoint_recommendations(state) do
    Logger.info("\\n=== Endpoint and Communication Recommendations ===")
    
    input_reports = Enum.filter(state.reports, &(&1.type == :input))
    output_reports = Enum.filter(state.reports, &(&1.type == :output))
    
    if length(input_reports) > 0 do
      Logger.info("\\nInput Reports (Motion Data):")
      Enum.each(input_reports, fn report ->
        size_bytes = div(report.size_bits + 7, 8)
        Logger.info("  Report ID #{inspect(report.report_id)}: #{size_bytes} bytes")
        
        # Check for 6DOF motion fields
        motion_fields = Enum.filter(report.fields, fn field ->
          field.usage_page == @usage_page_generic_desktop and
          field.usage in [@usage_x, @usage_y, @usage_z, @usage_rx, @usage_ry, @usage_rz]
        end)
        
        if length(motion_fields) > 0 do
          Logger.info("    → Contains #{length(motion_fields)} motion axes")
          Logger.info("    → This is likely the MAIN MOTION REPORT")
        end
      end)
      
      Logger.info("\\nRecommended approach:")
      Logger.info("  1. Use HID GET_REPORT control transfers")
      Logger.info("  2. Request input reports with the Report IDs shown above")
      Logger.info("  3. Parse the multi-axis motion data from these reports")
    end
    
    if length(output_reports) > 0 do
      Logger.info("\\nOutput Reports:")
      Enum.each(output_reports, fn report ->
        size_bytes = div(report.size_bits + 7, 8)
        Logger.info("  Report ID #{inspect(report.report_id)}: #{size_bytes} bytes")
      end)
    end
    
    Logger.info("\\n🎯 KEY FINDINGS:")
    Logger.info("  • SpaceMouse uses HID reports, NOT direct endpoints")
    Logger.info("  • Use control transfers with GET_REPORT requests")
    Logger.info("  • Report IDs and sizes are now known")
    Logger.info("  • Motion data structure is defined in the reports above")
  end

  @doc """
  Extract motion data from a HID report based on parsed descriptor info.
  """
  def extract_motion_data(report_data, parsed_info) do
    # Find the input report that contains motion data
    motion_report = Enum.find(parsed_info.reports, fn report ->
      report.type == :input and
      Enum.any?(report.fields, fn field ->
        field.usage_page == @usage_page_generic_desktop and
        field.usage in [@usage_x, @usage_y, @usage_z, @usage_rx, @usage_ry, @usage_rz]
      end)
    end)
    
    if motion_report do
      extract_fields_from_report(report_data, motion_report)
    else
      {:error, :no_motion_report}
    end
  end

  defp extract_fields_from_report(data, report) do
    # Extract each field from the report data based on bit positions
    motion_data = %{
      report_id: report.report_id,
      x: 0, y: 0, z: 0,
      rx: 0, ry: 0, rz: 0,
      timestamp: System.monotonic_time(:millisecond)
    }
    
    # Parse each field
    final_data = Enum.reduce(report.fields, motion_data, fn field, acc ->
      if field.usage_page == @usage_page_generic_desktop do
        value = extract_field_value(data, field)
        
        case field.usage do
          @usage_x -> %{acc | x: value}
          @usage_y -> %{acc | y: value}
          @usage_z -> %{acc | z: value}
          @usage_rx -> %{acc | rx: value}
          @usage_ry -> %{acc | ry: value}
          @usage_rz -> %{acc | rz: value}
          _ -> acc
        end
      else
        acc
      end
    end)
    
    {:ok, final_data}
  end

  defp extract_field_value(data, field) do
    # Extract value from binary data at specific bit offset
    byte_offset = div(field.bit_offset, 8)
    bit_offset_in_byte = rem(field.bit_offset, 8)
    field_size_bits = field.report_size || 8
    
    if byte_offset < byte_size(data) do
      # Simple extraction for common cases (8, 16 bit fields)
      case field_size_bits do
        8 ->
          <<_::binary-size(byte_offset), value, _::binary>> = data
          sign_extend(value, 8, field.logical_min)
          
        16 when bit_offset_in_byte == 0 ->
          <<_::binary-size(byte_offset), value::little-16, _::binary>> = data
          sign_extend(value, 16, field.logical_min)
          
        _ ->
          # For complex bit extractions, use bitstring matching
          extract_bits(data, field.bit_offset, field_size_bits, field.logical_min)
      end
    else
      0
    end
  end

  defp extract_bits(data, bit_offset, size_bits, logical_min) do
    # Convert to bitstring and extract the specific bits
    bit_size = byte_size(data) * 8
    
    if bit_offset + size_bits <= bit_size do
      <<_::size(bit_offset), value::size(size_bits), _::bitstring>> = data
      sign_extend(value, size_bits, logical_min)
    else
      0
    end
  end

  defp sign_extend(value, bits, logical_min) do
    # Sign extend if logical_min is negative (signed field)
    if logical_min < 0 do
      max_unsigned = (1 <<< bits) - 1
      half_range = 1 <<< (bits - 1)
      
      if value >= half_range do
        value - max_unsigned - 1
      else
        value
      end
    else
      value
    end
  end

  @doc """
  Show the raw HID descriptor in hex format for manual analysis.
  """
  def show_raw_descriptor do
    case get_spacemouse_descriptor() do
      {:ok, descriptor} ->
        Logger.info("=== Raw HID Report Descriptor ===")
        Logger.info("Size: #{byte_size(descriptor)} bytes")
        
        descriptor
        |> :binary.bin_to_list()
        |> Enum.chunk_every(16)
        |> Enum.with_index()
        |> Enum.each(fn {row, index} ->
          offset = Integer.to_string(index * 16, 16) |> String.pad_leading(4, "0")
          hex_part = row
          |> Enum.map(&Integer.to_string(&1, 16))
          |> Enum.map(&String.pad_leading(&1, 2, "0"))
          |> Enum.join(" ")
          |> String.pad_trailing(47)
          
          ascii_part = row
          |> Enum.map(fn byte -> 
            if byte >= 32 and byte <= 126, do: <<byte>>, else: "."
          end)
          |> Enum.join()
          
          Logger.info("#{offset}: #{hex_part} |#{ascii_part}|")
        end)
        
        {:ok, descriptor}
        
      error ->
        error
    end
  end
end
