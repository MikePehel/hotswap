local swapper = {}
local utils = require("utils")
local labeler = require("labeler")


function swapper.place_notes_on_matching_tracks( track_offset, pattern_index)
    local track_offset = track_offset
    local song = renoise.song()
    local pattern_index = pattern_index or song.selected_pattern_index
    print("PATTERN INDEX")
    print(pattern_index)
    local pattern = song:pattern(pattern_index)
    local num_of_lines = pattern.number_of_lines
    local line_index = 1
    local note_value = 48  -- C-4
    local occupied_slots = {} 
  

  local current_instrument_index = song.selected_instrument_index
  local labels = labeler.get_labels_for_instrument(current_instrument_index)
  print("LABELS ID")
  print(labels)
  utils.print_table(labels)

  local function find_instruments_by_label(song, label, is_ghost)
    local matching_instruments = {}
    local label_lower = string.lower(label)
    
    for i = 1, #song.instruments do
      local instrument = song.instruments[i]
      local instrument_name = string.lower(instrument.name)
      
      if is_ghost then
        if string.find(instrument_name, "_" .. label_lower .. "_ghost") then
          table.insert(matching_instruments, i)  
        end
      else
        if string.find(instrument_name, label_lower) and 
           (string.match(instrument_name, "^_") or string.match(instrument_name, "%s_")) and
           not string.find(instrument_name, "_ghost") then
          table.insert(matching_instruments, i)
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

  for track_index, track in ipairs(song.tracks) do
    print("TRACK")
    print(track)

    if not (track.type == renoise.Track.TRACK_TYPE_GROUP or
    track.type == renoise.Track.TRACK_TYPE_SEND or
    track.type == renoise.Track.TRACK_TYPE_MASTER) then
        local track_name = track.name:lower()
        print(track_name)
        if track_index < #song.tracks then
        local pattern_track = pattern:track(track_index)
        print(pattern_track)
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
  end  
  print("SWAPPABLE NOTES")
  utils.print_table(swappable_notes)

    local function note_matches_slice(note_value, swappable_notes, track_name, label_set)
      if not swappable_notes or type(swappable_notes) ~= "table" then
        return false, {}
      end
      
      local track_name_lower = track_name:lower()
      local label_info = label_set[track_name_lower]
      if not label_info then
        return false, {}
      end
      
      local is_ghost_track = track_name_lower:match("ghost$") ~= nil
      local matches = {}
      
      for _, note_data in ipairs(swappable_notes) do
        if note_value == note_data.note then
          if (is_ghost_track and label_info.ghost) or (not is_ghost_track) then
            table.insert(matches, {
              line = note_data.line,
              delay = note_data.delay,
              volume = note_data.volume,
              pan = note_data.pan,
              primary = label_info.primary,
              ghost = label_info.ghost
            })
          end
        end
      end
      
      return #matches > 0, matches
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
    


    for track_index, track in ipairs(song.tracks) do
      local track_name = track.name:lower()
      local is_ghost_track = track_name:match("ghost$") ~= nil
      
      local base_label = track_name
      if is_ghost_track then
        base_label = track_name:gsub("%s*ghost$", "")
      end
      
      local matching_instruments = find_instruments_by_label(song, base_label, is_ghost_track)
      
      for hex_key, label_data in pairs(labels) do
        if label_data.label and label_data.label ~= "---------" then
          local slice_note = label_data.slice_note
          local matches, matches_table = note_matches_slice(slice_note, swappable_notes, track_name, label_set)
          
          if label_data.label:lower() == base_label then
            local pattern = song.patterns[pattern_index]
            if pattern and pattern.tracks[track_index] then
              if #matching_instruments > 0 then
                if matches then
                  for _, match in ipairs(matches_table) do
                    local should_place = false
                    if label_data.ghost_note then
                      if is_ghost_track or not ghost_track_exists(song, base_label) then
                        should_place = true
                      end
                    else
                      should_place = not is_ghost_track
                    end
            
                    if should_place then
                      local slot_key = string.format("%d_%d", track_index, match.line)
                      if not occupied_slots[slot_key] then
                        local transfer_line = pattern.tracks[track_index]:line(match.line)
                        transfer_line.note_columns[1].note_value = 48
                        transfer_line.note_columns[1].instrument_value = matching_instruments[1] - track_offset
                        transfer_line.note_columns[1].delay_value = match.delay
                        transfer_line.note_columns[1].volume_value = match.volume
                        transfer_line.note_columns[1].panning_value = match.pan
                        
                        occupied_slots[slot_key] = true
                      end
                    end
                  end
                end
              end
            end
          end
        end
      
        -- Process secondary label (Label 2)
        if label_data.label2 and label_data.label2 ~= "---------" then
          local slice_note = label_data.slice_note
          local matches, matches_table = note_matches_slice(slice_note, swappable_notes, track_name, label_set)
      
          if label_data.label2:lower() == base_label then
            local pattern = song.patterns[pattern_index]
            if pattern and pattern.tracks[track_index] then
              if #matching_instruments > 0 then
                if matches then
                  for _, match in ipairs(matches_table) do
                    local should_place = false
                    if label_data.ghost_note then
                      if is_ghost_track or not ghost_track_exists(song, base_label) then
                        should_place = true
                      end
                    else
                      should_place = not is_ghost_track
                    end
      
                    if should_place then
                      local slot_key = string.format("%d_%d", track_index, match.line)
                      if not occupied_slots[slot_key] then
                        local transfer_line = pattern.tracks[track_index]:line(match.line)
                        transfer_line.note_columns[1].note_value = 48
                        transfer_line.note_columns[1].instrument_value = matching_instruments[1] - track_offset
                        transfer_line.note_columns[1].delay_value = match.delay
                        transfer_line.note_columns[1].volume_value = match.volume
                        transfer_line.note_columns[1].panning_value = match.pan                        
                        occupied_slots[slot_key] = true
                      end
                    end
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

return swapper