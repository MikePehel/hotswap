-- main.lua
local labeler = require("labeler")
local utils = require("utils")

--------------------------------------------------------------------------------
-- Dialog Management
--------------------------------------------------------------------------------

-- Store dialog reference
local main_dialog = nil

-- Create the main dialog
local function create_main_dialog()
  if main_dialog and main_dialog.visible then
    main_dialog:close()
  end

  local vb = renoise.ViewBuilder()
  
  local dialog_content = vb:column {
    margin = 10,
    spacing = 10,
    
    vb:horizontal_aligner {
      mode = "center",
      margin = 10,
      
      vb:column {
        style = "panel",
        margin = 10,
        spacing = 10,
        width = 200,
        
        vb:text {
          text = "HotSwap Tools",
          style = "strong",
          align = "center",
          width = "100%",
        },
        
        vb:button {
          text = "Label Editor",
          width = "100%",
          height = 30,
          notifier = function()
            labeler.create_ui(function()
              -- When labeler closes, show main dialog again
              if not main_dialog or not main_dialog.visible then
                create_main_dialog()
              end
            end)
            -- Close the main dialog when opening the labeler
            if main_dialog and main_dialog.visible then
              main_dialog:close()
            end
          end
        },
        
        vb:button {
          text = "Import Labels",
          width = "100%",
          height = 30,
          notifier = function()
            labeler.import_labels()
          end
        },
        
        vb:button {
          text = "Export Labels",
          width = "100%",
          height = 30,
          notifier = function()
            labeler.export_labels()
          end
        },
        
        vb:button {
          text = "Place Notes",
          width = "100%",
          height = 30,
          notifier = function()
            place_notes_on_matching_tracks()
          end
        }
      }
    }
  }
  
  main_dialog = renoise.app():show_custom_dialog("HotSwap Tools", dialog_content)
end

local function find_instruments_by_label(song, label)
  local matching_instruments = {}
  for i = 1, #song.instruments do
    local instrument = song.instruments[i]
    if instrument.name:lower():find(label:lower()) and 
       (instrument.name:match("^_") or instrument.name:match("%s_")) then
      table.insert(matching_instruments, i - 1)  -- Instrument indices are 0-based
    end
  end
  return matching_instruments
end


function print_table(t, indent)
  indent = indent or 0
  for k, v in pairs(t) do
      local formatting = string.rep("  ", indent) .. tostring(k) .. ": "
      if type(v) == "table" then
          print(formatting)
          print_table(v, indent + 1)
      else
          print(formatting .. tostring(v))
      end
  end
end


-- Place notes on tracks based on labels
function place_notes_on_matching_tracks()
  local song = renoise.song()
  local pattern_index = 1
  local pattern = song:pattern(pattern_index)
  local num_of_lines = pattern.number_of_lines
  local line_index = 1
  local note_value = 48  -- C-4
  

  -- Get the current instrument's labels
  local current_instrument_index = song.selected_instrument_index
  local labels = labeler.get_labels_for_instrument(current_instrument_index)
  print("LABELS ID")
  print(labels)
  print_table(labels)

  -- Helper function to find instruments by label
  local function find_instruments_by_label(label)
    local matching_instruments = {}
    for i = 1, #song.instruments do
      local instrument = song.instruments[i]
      if instrument.name:lower():find(label:lower()) then
        table.insert(matching_instruments, i - 1)  -- Instrument indices are 0-based
      end
    end
    return matching_instruments
  end

  local function create_label_set(labels)
    local label_set = {}
    for _, label_data in pairs(labels) do
        if label_data.label then
            label_set[label_data.label:lower()] = true
        end
    end
    return label_set
  end

  local label_set = create_label_set(labels)

  local function is_non_matching(track_name, label_set)
    return not label_set[track_name:lower()]
  end

  local swappable_notes = {}

  local function add_track_info(info)
    table.insert(swappable_notes, {
        ["track_name"] = info.track_name,
        ["track"] = info.track,
        ["line"] = info.line,
        ["note"] = info.note_value,
        ["instrument"] = info.instrument_num,
        ["delay"] = info.delay_value,
        ["volume"] = info.volume_value,
        ["pan"] = info.panning_value
    })
  end

  -- Iterate through all tracks
  for track_index, track in ipairs(song.tracks) do
    local track_name = track.name:lower()
    if track_index < #song.tracks then
      local pattern_track = pattern:track(track_index)
      for line = 1, num_of_lines do 
        local note_column = pattern_track:line(line):note_column(1)
        local note_value = note_column.note_value
        local instrument = note_column.instrument_value

        if note_value < 121 then
          print(track_name)
          if is_non_matching(track_name, label_set) then
            add_track_info({
              track_name = track_name, 
              track = track_index, 
              line = line, 
              note_value = note_value, 
              instrument_num = instrument,
              delay_value = note_column.delay_value,
              volume_value = note_column.volume_value,
              panning_value = note_column.panning_value            
            })
            print(string.format(" Track Name = %s, Track# = %d,  Line %03d: Note = %d, Instrument = %02X", track_name, track_index, line, note_value, instrument))
          end
        end
      end
    end
  end  
  print_table(swappable_notes)
    -- Iterate through tracks in the pattern
      --Check notes
      -- Look up notes and based on slice count, match to labels

    
    -- Find instruments that match the track name

    local function note_matches_slice(note_value, swappable_notes)
      if not swappable_notes or type(swappable_notes) ~= "table" then
        return false, nil
      end
      
      for i, note_data in ipairs(swappable_notes) do
        if note_value == note_data.note then
          return true, swappable_notes[i].line, swappable_notes[i].delay, swappable_notes[i].volume, swappable_notes[i].pan
        end
      end
      
      return false, nil
    end
    


    -- Check if any label matches the track name
    for track_index, track in ipairs(song.tracks) do
      local track_name = track.name:lower()
      local matching_instruments = find_instruments_by_label(track_name)
      
      print("LABELS CHECK")
      print_table(labels)
      for hex_key, label_data in pairs(labels) do
        

        local slice_note = label_data.slice_note
        print("NOTE VALUE")
        print(slice_note)
        local matches, matched_line, matched_delay, matched_volume, matched_pan = note_matches_slice(slice_note, swappable_notes)
        print("MATCHES")
        print(matches)
        print(matched_line)

        if label_data.label:lower() == track_name then
            -- Place a note on the first line of the first pattern
          local pattern = song.patterns[pattern_index]
          if pattern and pattern.tracks[track_index] then
            if #matching_instruments > 0 then
              if matches then
                print("Pattern:", pattern_index, "Track:", track_index)
                print("Matching instruments:", #matching_instruments)
                print("Matches:", matches)
                print("Matched line:", matched_line)
                print("Slice note:", slice_note)
                local transfer_line = pattern.tracks[track_index]:line(matched_line)
                transfer_line.note_columns[1].note_value = 48
                transfer_line.note_columns[1].instrument_value = matching_instruments[1]
                transfer_line.note_columns[1].delay_value = matched_delay
                transfer_line.note_columns[1].volume_value = matched_volume
                transfer_line.note_columns[1].panning_value = matched_pan
              -- Use the first matching instrument if available, otherwise use the current instrument
              -- If swappable note matches a slice label note value place a note with matching instrument
                --note_column.note_value = note_value
                --note_column.instrument_value = matching_instruments[1]
              end
            end
          end
      end
    end
  end
  
  renoise.app():show_status("Notes placed on matching tracks")
end


--------------------------------------------------------------------------------
-- Tool Registration
--------------------------------------------------------------------------------

-- Register show dialog callback for labeler
labeler.set_show_dialog_callback(function()
  if main_dialog and main_dialog.visible then
    main_dialog:close()
  end
  labeler.create_ui()
end)

-- Register main menu entry
renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:HotSwap",
  invoke = create_main_dialog
}

-- Register keybinding preference
renoise.tool():add_keybinding {
  name = "Global:Tools:Show HotSwap",
  invoke = create_main_dialog
}

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

-- Add cleanup handlers
local tool = renoise.tool()
tool.app_new_document_observable:add_notifier(function()
  if main_dialog and main_dialog.visible then
    main_dialog:close()
  end
  labeler.cleanup()
end)

tool.app_release_document_observable:add_notifier(function()
  if main_dialog and main_dialog.visible then
    main_dialog:close()
  end
  labeler.cleanup()
end) 