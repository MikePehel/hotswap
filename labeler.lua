-- labeler.lua

local labeler = {}
local dialog = nil


local function calculate_scale_factor(num_slices)
  local base_slices = 16 
  return math.max(0.5, math.min(1, base_slices / num_slices))
end

labeler.saved_labels = {}
labeler.saved_labels_observable = renoise.Document.ObservableBoolean(false)

local function escape_csv_field(field)
  if type(field) == "string" and (field:find(',') or field:find('"')) then
    return '"' .. field:gsub('"', '""') .. '"'
  end
  return tostring(field)
end

local function unescape_csv_field(field)
  if field:sub(1,1) == '"' and field:sub(-1) == '"' then
    return field:sub(2, -2):gsub('""', '"')
  end
  return field
end

local function parse_csv_line(line)
  local fields = {}
  local field = ""
  local in_quotes = false
  
  local i = 1
  while i <= #line do
    local char = line:sub(i,i)
    
    if char == '"' then
      if in_quotes and line:sub(i+1,i+1) == '"' then
        -- Handle escaped quotes
        field = field .. '"'
        i = i + 2
      else
        -- Toggle quote mode
        in_quotes = not in_quotes
        i = i + 1
      end
    elseif char == ',' and not in_quotes then
      -- End of field
      table.insert(fields, field)
      field = ""
      i = i + 1
    else
      field = field .. char
      i = i + 1
    end
  end
  
  table.insert(fields, field)
  return fields
end

local function get_current_sample_name()
  local song = renoise.song()
  local instrument = song.selected_instrument
  if instrument and #instrument.samples > 0 then
    -- Remove any characters that might be problematic in filenames
    local name = instrument.samples[1].name:gsub("[%c%p%s]", "_")
    return name
  end
  return "default"
end

function labeler.export_labels()
  local filename = get_current_sample_name() .. "_labels.csv"
  local filepath = renoise.app():prompt_for_filename_to_write("csv", "Export Labels")
  
  if not filepath or filepath == "" then return end
  
  if not filepath:lower():match("%.csv$") then
      filepath = filepath .. ".csv"
  end
  
  local file, err = io.open(filepath, "w")
  if not file then
      renoise.app():show_error("Unable to open file for writing: " .. tostring(err))
      return
  end
  
  file:write("Index,Label,Cycle,Roll,Ghost,Shuffle\n")
  
  for hex_key, data in pairs(labeler.saved_labels) do
      local values = {
          hex_key,
          data.label or "---------",
          tostring(data.cycle or false),
          tostring(data.roll or false),
          tostring(data.ghost_note or false),
          tostring(data.shuffle or false)
      }
      
      -- Escape each field
      for i, value in ipairs(values) do
          values[i] = escape_csv_field(value)
      end
      
      file:write(table.concat(values, ",") .. "\n")
  end
  
  file:close()
  renoise.app():show_status("Labels exported to " .. filepath)
end

function labeler.import_labels()
  local filepath = renoise.app():prompt_for_filename_to_read({"*.csv"}, "Import Labels")
  
  if not filepath or filepath == "" then return end
  
  local file, err = io.open(filepath, "r")
  if not file then
      renoise.app():show_error("Unable to open file: " .. tostring(err))
      return
  end
  
  local header = file:read()
  if not header or not header:lower():match("index,label,cycle,roll,ghost,shuffle") then
      renoise.app():show_error("Invalid CSV format: Missing or incorrect header")
      file:close()
      return
  end
  
  local new_labels = {}
  local line_number = 1
  
  for line in file:lines() do
      line_number = line_number + 1
      local fields = parse_csv_line(line)
      
      if #fields ~= 6 then
          renoise.app():show_error(string.format(
              "Invalid CSV format at line %d: Expected 6 fields, got %d", 
              line_number, #fields))
          file:close()
          return
      end
      
      local index = fields[1]
      if not index:match("^%x%x$") then
          renoise.app():show_error(string.format(
              "Invalid index format at line %d: %s", 
              line_number, index))
          file:close()
          return
      end
      
      local function str_to_bool(str)
          return str:lower() == "true"
      end
      
      new_labels[index] = {
          label = unescape_csv_field(fields[2]),
          cycle = str_to_bool(fields[3]),
          roll = str_to_bool(fields[4]),
          ghost_note = str_to_bool(fields[5]),
          shuffle = str_to_bool(fields[6])
      }
  end
  
  file:close()
  
  labeler.saved_labels = new_labels
  labeler.saved_labels_observable.value = not labeler.saved_labels_observable.value
  renoise.app():show_status("Labels imported from " .. filepath)
  
  if dialog and dialog.visible then
      dialog:close()
      labeler.create_ui()
  end
end

function labeler.create_ui()
  if dialog and dialog.visible then
    dialog:close()
    dialog = nil
  end

  local vb = renoise.ViewBuilder()

  local column_width = 100
  local spacing = 10

  local slice_data = {}

  local song = renoise.song()
  local instrument = song.selected_instrument
  local samples = instrument.samples

  for j = 2, #samples do
    local sample = samples[j]
    local hex_key = string.format("%02X", j)
    local saved_label = labeler.saved_labels[hex_key] or {
      label = "---------", 
      ghost_note = false, 
      cycle = false, 
      roll = false,
      shuffle = false
    }
    table.insert(slice_data, {
      index = j - 1, 
      sample_name = sample.name,
      label = saved_label.label,
      ghost_note = saved_label.ghost_note,
      cycle = saved_label.cycle,
      roll = saved_label.roll,
      shuffle = saved_label.shuffle
    })
  end

  local scale_factor = calculate_scale_factor(#slice_data)
  
  local column_width = 100 
  local spacing = 10 
  local padding = math.max(0, math.min(5, 5 * scale_factor)) 
  local row_height = math.max(13, math.min(25, 25 * scale_factor)) 

  local dialog_content = vb:column {
    spacing = spacing 
  }
  
  local grid = vb:column {
    spacing = padding
  }
  
  local header_row = vb:row {
    spacing = spacing,
    vb:text { text = "Slice", width = column_width, align = "center" },
    vb:text { text = "Label", width = column_width, align = "center" },
    vb:text { text = "Cycle", width = column_width, align = "center" },
    vb:text { text = "Roll", width = column_width, align = "center" },
    vb:text { text = "Ghost Note", width = column_width, align = "center" },
    vb:text { text = "Shuffle", width = column_width, align = "center" }
  }
  
  grid:add_child(header_row)
  
  for _, slice in ipairs(slice_data) do
    local row = vb:row {
      spacing = spacing,
      height = row_height,
      vb:text { 
        text = "#" .. slice.index, 
        width = column_width, 
        align = "center" 
      },
      vb:popup {
        id = "label_" .. slice.index,
        items = {"---------", "Kick", "Snare", "Hi Hat Closed", "Hi Hat Open", "Crash", "Tom", "Ride", "Shaker", "Tambourine", "Cowbell"},
        width = column_width,
        value = table.find({"---------", "Kick", "Snare", "Hi Hat Closed", "Hi Hat Open", "Crash", "Tom", "Ride", "Shaker", "Tambourine", "Cowbell"}, slice.label) or 1
      },
      vb:horizontal_aligner {
        mode = "center",
        width = column_width,
        vb:checkbox {
          id = "cycle_" .. slice.index,
          value = slice.cycle,
          width = 20,
          height = math.max(15, math.min(20, 20 * scale_factor))
        }
      },
      vb:horizontal_aligner {
        mode = "center",
        width = column_width,
        vb:checkbox {
          id = "roll_" .. slice.index,
          value = slice.roll,
          width = 20,
          height = math.max(15, math.min(20, 20 * scale_factor))
        }
      },
      vb:horizontal_aligner {
        mode = "center",
        width = column_width,
        vb:checkbox {
          id = "ghost_note_" .. slice.index,
          value = slice.ghost_note,
          width = 20,
          height = math.max(15, math.min(20, 20 * scale_factor))
        }
      },
      vb:horizontal_aligner {
        mode = "center",
        width = column_width,
        vb:checkbox {
          id = "shuffle_" .. slice.index,
          value = slice.shuffle,
          width = 20,
          height = math.max(15, math.min(20, 20 * scale_factor))
        }
      }
    }
    grid:add_child(row)
  end
  
  dialog_content:add_child(grid)

  dialog_content:add_child(vb:horizontal_aligner {
    mode = "right",
    margin = 20,
    spacing = 10,
    vb:button {
      text = "Save Labels",
      notifier = function()
        local saved_labels = {}
        for _, slice in ipairs(slice_data) do
          local hex_key = string.format("%02X", slice.index + 1) 
          saved_labels[hex_key] = {
            label = vb.views["label_" .. slice.index].items[vb.views["label_" .. slice.index].value],
            ghost_note = vb.views["ghost_note_" .. slice.index].value,
            cycle = vb.views["cycle_" .. slice.index].value,
            roll = vb.views["roll_" .. slice.index].value,
            shuffle = vb.views["shuffle_" .. slice.index].value
          }
        end
        renoise.app():show_status("Labels saved successfully")

        labeler.saved_labels = saved_labels
        labeler.saved_labels_observable.value = not labeler.saved_labels_observable.value

        if dialog and dialog.visible then
          dialog:close()
        end

        renoise.app():show_message("Your labels have been saved.")
      end
    }
  })

  dialog = renoise.app():show_custom_dialog("Slice Labeler", dialog_content)
end

function labeler.recall_labels()
  local vb = renoise.ViewBuilder()
  local saved_labels_str = ""

  for k, v in pairs(labeler.saved_labels) do
    saved_labels_str = saved_labels_str .. string.format("%s: Label=%s, Cycle=%s, Roll=%s, Ghost Note=%s, Shuffle=%s\n", 
                                                         k, v.label, tostring(v.cycle), tostring(v.roll), 
                                                         tostring(v.ghost_note), tostring(v.shuffle))
  end

  renoise.app():show_custom_prompt("Recalled Labels", vb:column {
    vb:multiline_text {
      text = saved_labels_str,
      width = 400,
      height = 300
    }
  }, {"OK"})
end

function labeler.cleanup()
  if dialog and dialog.visible then
    dialog:close()
    dialog = nil
  end
end

return labeler