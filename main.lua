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

local function find_instruments_by_label(song, label, is_ghost)
  local matching_instruments = {}
  local label_lower = string.lower(label)
  
  for i = 1, #song.instruments do
    local instrument = song.instruments[i]
    local instrument_name = string.lower(instrument.name)
    
    -- Check if we're looking for ghost instruments
    if is_ghost then
      if string.find(instrument_name, "_" .. label_lower .. "_ghost") then
        table.insert(matching_instruments, i - 1)  -- Instrument indices are 0-based
      end
    else
      -- Original matching logic for non-ghost instruments
      if string.find(instrument_name, label_lower) and 
         (string.match(instrument_name, "^_") or string.match(instrument_name, "%s_")) and
         not string.find(instrument_name, "_ghost") then
        table.insert(matching_instruments, i - 1)
      end
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
    local occupied_slots = {} 
  

  -- Get the current instrument's labels
  local current_instrument_index = song.selected_instrument_index
  local labels = labeler.get_labels_for_instrument(current_instrument_index)
  print("LABELS ID")
  print(labels)
  print_table(labels)

  -- Helper function to find instruments by label
  local function find_instruments_by_label(song, label, is_ghost)
    local matching_instruments = {}
    local label_lower = string.lower(label)
    
    for i = 1, #song.instruments do
      local instrument = song.instruments[i]
      local instrument_name = string.lower(instrument.name)
      
      -- Check if we're looking for ghost instruments
      if is_ghost then
        if string.find(instrument_name, "_" .. label_lower .. "_ghost") then
          table.insert(matching_instruments, i - 1)  -- Instrument indices are 0-based
        end
      else
        -- Original matching logic for non-ghost instruments
        if string.find(instrument_name, label_lower) and 
           (string.match(instrument_name, "^_") or string.match(instrument_name, "%s_")) and
           not string.find(instrument_name, "_ghost") then
          table.insert(matching_instruments, i - 1)
        end
      end
    end
    return matching_instruments
  end

  local function create_label_set(labels)
    local label_set = {}
    for hex_key, label_data in pairs(labels) do
        if label_data.label then
            local key = label_data.label:lower()
            label_set[key] = {
                primary = true,
                slice_note = label_data.slice_note,
                ghost = label_data.ghost_note
            }
            -- Add ghost track entry if ghost note is true
            if label_data.ghost_note then
                label_set[key .. " ghost"] = {
                    primary = true,
                    slice_note = label_data.slice_note,
                    ghost = true,
                    original_label = key
                }
            end
        end
        if label_data.label2 and label_data.label2 ~= "---------" then
            local key = label_data.label2:lower()
            label_set[key] = {
                primary = false,
                slice_note = label_data.slice_note,
                ghost = label_data.ghost_note
            }
            -- Add ghost track entry if ghost note is true
            if label_data.ghost_note then
                label_set[key .. " ghost"] = {
                    primary = false,
                    slice_note = label_data.slice_note,
                    ghost = true,
                    original_label = key
                }
            end
        end
    end
    return label_set
  end

  local label_set = create_label_set(labels)

  local function is_non_matching(track_name, label_set)
    local lower_track = track_name:lower()
    local base_track = lower_track:gsub("%s*ghost$", "")
    -- Check both normal and ghost variations
    return not (label_set[lower_track] or label_set[base_track] or label_set[base_track .. " ghost"])
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

    local function note_matches_slice(note_value, swappable_notes, track_name, label_set)
      if not swappable_notes or type(swappable_notes) ~= "table" then
        return false, nil
      end
      
      local track_name_lower = track_name:lower()
      local label_info = label_set[track_name_lower]
      if not label_info then
        return false, nil
      end
      
      local is_ghost_track = track_name_lower:match("ghost$") ~= nil
      
      for i, note_data in ipairs(swappable_notes) do
        if note_value == note_data.note then
          -- If it's a ghost track, only match ghost notes
          -- If it's a regular track, match either regular notes or ghost notes when no ghost track exists
          if (is_ghost_track and label_info.ghost) or 
             (not is_ghost_track) then  -- Removed the ghost check for regular tracks
            return true, 
                   swappable_notes[i].line, 
                   swappable_notes[i].delay, 
                   swappable_notes[i].volume, 
                   swappable_notes[i].pan,
                   label_info.primary,
                   label_info.ghost
          end
        end
      end
      
      return false, nil
    end

    local function ghost_track_exists(song, base_label)
      for _, track in ipairs(song.tracks) do
        local track_name = track.name:lower()
        if track_name == base_label .. " ghost" then
          return true
        end
      end
      return false
    end
    


    -- Check if any label matches the track name
    for track_index, track in ipairs(song.tracks) do
      local track_name = track.name:lower()
      local is_ghost_track = track_name:match("ghost$") ~= nil
      
      -- Get base label for ghost tracks
      local base_label = track_name
      if is_ghost_track then
        base_label = track_name:gsub("%s*ghost$", "")
      end
      
      local matching_instruments = find_instruments_by_label(song, base_label, is_ghost_track)
      
      for hex_key, label_data in pairs(labels) do
        -- Process primary label (Label)
        if label_data.label and label_data.label ~= "---------" then
          local slice_note = label_data.slice_note
          local matches, matched_line, matched_delay, matched_volume, matched_pan, is_primary, is_ghost = 
            note_matches_slice(slice_note, swappable_notes, track_name, label_set)
          
            if label_data.label:lower() == base_label then
              local pattern = song.patterns[pattern_index]
              if pattern and pattern.tracks[track_index] then
                if #matching_instruments > 0 then
                  if matches then
                    -- If it's a ghost note, check if ghost track exists
                    local should_place = false
                    if label_data.ghost_note then
                      -- Place on ghost track if it exists, otherwise place on regular track
                      if is_ghost_track or not ghost_track_exists(song, base_label) then
                        should_place = true
                      end
                    else
                      -- For non-ghost notes, place as normal
                      should_place = not is_ghost_track
                    end
            
                    if should_place then
                      local slot_key = string.format("%d_%d", track_index, matched_line)
                      if not occupied_slots[slot_key] then
                        local transfer_line = pattern.tracks[track_index]:line(matched_line)
                        transfer_line.note_columns[1].note_value = 48
                        transfer_line.note_columns[1].instrument_value = matching_instruments[1]
                        transfer_line.note_columns[1].delay_value = matched_delay
                        transfer_line.note_columns[1].volume_value = matched_volume
                        transfer_line.note_columns[1].panning_value = matched_pan
                        
                        occupied_slots[slot_key] = true
                      end
                    end
                  end
                end
              end
            end
        end
        
        -- Process secondary label (Label 2)
        -- Process secondary label (Label 2)
        if label_data.label2 and label_data.label2 ~= "---------" then
        local slice_note = label_data.slice_note
        local matches, matched_line, matched_delay, matched_volume, matched_pan, is_primary, is_ghost = 
          note_matches_slice(slice_note, swappable_notes, track_name, label_set)

        if label_data.label2:lower() == base_label then
          local pattern = song.patterns[pattern_index]
          -- Check if this specific track+line combination is occupied
          local slot_key = string.format("%d_%d", track_index, matched_line)
          if pattern and pattern.tracks[track_index] and not occupied_slots[slot_key] then
            if #matching_instruments > 0 then
              if matches then
                -- If it's a ghost note, check if ghost track exists
                local should_place = false
                if label_data.ghost_note then
                  -- Place on ghost track if it exists, otherwise place on regular track
                  if is_ghost_track or not ghost_track_exists(song, base_label) then
                    should_place = true
                  end
                else
                  -- For non-ghost notes, place as normal
                  should_place = not is_ghost_track
                end

                if should_place then
                  local transfer_line = pattern.tracks[track_index]:line(matched_line)
                  transfer_line.note_columns[1].note_value = 48
                  transfer_line.note_columns[1].instrument_value = matching_instruments[1]
                  transfer_line.note_columns[1].delay_value = matched_delay
                  transfer_line.note_columns[1].volume_value = matched_volume
                  transfer_line.note_columns[1].panning_value = matched_pan
                  
                  occupied_slots[slot_key] = true
                end
              end
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