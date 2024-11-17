-- labeler.lua

local labeler = {}

local dialog = nil

local function calculate_scale_factor(num_slices)
  local base_slices = 16 
  return math.max(0.5, math.min(1, base_slices / num_slices))
end

labeler.saved_labels = {}


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