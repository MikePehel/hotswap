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

-- Enhanced function to copy phrase to track with additional options
-- Enhanced function to copy phrase to track with additional options
-- Enhanced function to copy phrase to track with additional options
-- Enhanced function to copy phrase to track with additional options
function swapper.copy_phrase_to_track(phrase_index, track_index, options)
  local song = renoise.song()
  
  -- Default options
  options = options or {}
  local clear_track = options.clear_track or false
  local adjust_pattern = options.adjust_pattern or false
  local debug_mode = options.debug_mode or true -- Enable debugging by default
  
  -- Debug output function
  local function debug_print(message)
    if debug_mode then
      print("[Phrase2Track Debug] " .. message)
    end
  end
  
  debug_print("Starting copy operation...")
  debug_print(string.format("Phrase index: %d, Track index: %d", phrase_index, track_index))
  
  -- Check if an instrument is locked
  if not labeler.is_locked or not labeler.locked_instrument_index then
    renoise.app():show_warning("Please lock an instrument first to use this feature.")
    return false
  end
  
  -- Get the source instrument and phrase
  local instrument = song:instrument(labeler.locked_instrument_index)
  debug_print(string.format("Locked instrument: %s (#%d)", 
    instrument.name, labeler.locked_instrument_index))
  
  -- Validate phrase index
  if not phrase_index or phrase_index < 1 or phrase_index > #instrument.phrases then
    renoise.app():show_warning(string.format(
      "Invalid phrase index. The instrument has %d phrases.", 
      #instrument.phrases))
    return false
  end
  
  local source_phrase = instrument.phrases[phrase_index]
  debug_print(string.format("Source phrase: %s (Lines: %d)", 
    source_phrase.name ~= "" and source_phrase.name or "Unnamed", source_phrase.number_of_lines))
  
  -- Get the current pattern and the target track
  local pattern_index = song.selected_pattern_index
  local pattern = song:pattern(pattern_index)
  
  -- Validate track index
  if not track_index or track_index < 1 or track_index > #song.tracks then
    renoise.app():show_warning(string.format(
      "Invalid track index. The song has %d tracks.", 
      #song.tracks))
    return false
  end
  
  -- Check if it's a valid sequencer track
  if song.tracks[track_index].type ~= renoise.Track.TRACK_TYPE_SEQUENCER then
    renoise.app():show_warning("The selected track is not a sequencer track.")
    return false
  end
  
  local target_track = pattern:track(track_index)
  debug_print(string.format("Target track: %s (#%d)", 
    song.tracks[track_index].name, track_index))
  
  -- Adjust pattern length if requested
  if adjust_pattern and source_phrase.number_of_lines ~= pattern.number_of_lines then
    local old_length = pattern.number_of_lines
    pattern.number_of_lines = source_phrase.number_of_lines
    debug_print(string.format("Pattern length adjusted from %d to %d lines", 
      old_length, source_phrase.number_of_lines))
  end
  
  -- Check pattern and phrase line count
  local phrase_lines = source_phrase.number_of_lines
  local pattern_lines = pattern.number_of_lines
  
  if phrase_lines > pattern_lines and not adjust_pattern then
    debug_print(string.format(
      "WARNING: Phrase (%d lines) is longer than pattern (%d lines). Truncating copy.", 
      phrase_lines, pattern_lines))
  end
  
  -- Clear the target track if requested
  if clear_track then
    debug_print("Clearing target track...")
    for line_idx = 1, pattern_lines do
      local pattern_line = target_track:line(line_idx)
      for col_idx = 1, #pattern_line.note_columns do
        pattern_line:note_column(col_idx):clear()
      end
      for col_idx = 1, #pattern_line.effect_columns do
        pattern_line:effect_column(col_idx):clear()
      end
    end
  end
  
  -- Copy data from phrase to pattern track
  local lines_to_copy = math.min(phrase_lines, pattern_lines)
  debug_print(string.format("Will copy %d lines of content", lines_to_copy))
  
  -- Create a debug table to track note values
  local debug_notes = {}
  
  -- Note value conversion function - based on your suggestion:
  -- Instrument 1 = D#3 (51), Instrument 2 = E-3 (52), etc.
  local function instrument_to_note(instrument_value)
    -- D#3 is MIDI note 51, so we'll add 50 to the instrument value
    -- Since instrument indexing starts at 1, and we want instrument 1 to be D#3 (51)
    if instrument_value < 1 then return nil end
    return 50 + instrument_value
  end
  
  for line_idx = 1, lines_to_copy do
    local phrase_line = source_phrase:line(line_idx)
    local pattern_line = target_track:line(line_idx)
    
    -- Copy note columns
    for col_idx = 1, math.min(#phrase_line.note_columns, #pattern_line.note_columns) do
      local src_note = phrase_line:note_column(col_idx)
      local dst_note = pattern_line:note_column(col_idx)
      
      -- Skip empty notes
      if src_note.note_value ~= renoise.PatternLine.EMPTY_NOTE then
        -- Debug the original note data
        debug_print(string.format(
          "Line %03d Col %d: Original: note_value=%d, note_string='%s', ins=%d", 
          line_idx, col_idx, 
          src_note.note_value, 
          src_note.note_string, 
          src_note.instrument_value))
        
        -- Determine the target note value
        local target_note_value
        
        -- Handle special notes (OFF, etc.)
        if src_note.note_value >= 121 then  -- OFF or other special notes
          target_note_value = src_note.note_value
        else
          -- Convert instrument value to note value
          -- If no instrument value, or it's invalid, try to use the note_value directly
          if src_note.instrument_value >= 0 then
            target_note_value = instrument_to_note(src_note.instrument_value + 1) -- +1 because Renoise uses 0-based indexing
            debug_print(string.format("Converting ins %d to note %d", 
              src_note.instrument_value, target_note_value or -1))
          else
            -- If there's no instrument value, keep the original note value
            target_note_value = src_note.note_value
            debug_print("Using original note value (no instrument value)")
          end
        end
        
        -- Set the note value in the destination
        if target_note_value then
          dst_note.note_value = target_note_value
          
          -- Set the instrument value
          dst_note.instrument_value = labeler.locked_instrument_index - 1 -- 0-based
        else
          -- If we couldn't determine a valid note value, use the original
          dst_note.note_value = src_note.note_value
          dst_note.instrument_value = labeler.locked_instrument_index - 1
          debug_print("WARNING: Could not determine note value, using original")
        end
        
        -- Copy other properties
        if src_note.volume_value ~= renoise.PatternLine.EMPTY_VOLUME then
          dst_note.volume_value = src_note.volume_value
        end
        
        if src_note.panning_value ~= renoise.PatternLine.EMPTY_PANNING then
          dst_note.panning_value = src_note.panning_value
        end
        
        dst_note.delay_value = src_note.delay_value
        
        -- Store for debugging
        table.insert(debug_notes, {
          line = line_idx,
          col = col_idx,
          src_value = src_note.note_value,
          src_string = src_note.note_string,
          src_ins = src_note.instrument_value,
          dst_value = dst_note.note_value,
          dst_string = dst_note.note_string,
          dst_ins = dst_note.instrument_value
        })
      end
    end
    
    -- Copy effect columns
    for col_idx = 1, math.min(#phrase_line.effect_columns, #pattern_line.effect_columns) do
      local src_fx = phrase_line:effect_column(col_idx)
      local dst_fx = pattern_line:effect_column(col_idx)
      
      -- Only copy non-empty effects
      if src_fx.number_string ~= "" and src_fx.number_string ~= "00" then
        debug_print(string.format(
          "Line %03d FX %d: number='%s', amount='%s'", 
          line_idx, col_idx, 
          src_fx.number_string, 
          src_fx.amount_string))
          
        dst_fx.number_string = src_fx.number_string
        dst_fx.amount_value = src_fx.amount_value
      end
    end
  end
  
  -- Print final debug summary of note copying
  debug_print("--- Note Copy Summary ---")
  for _, note_info in ipairs(debug_notes) do
    debug_print(string.format(
      "Line %03d Col %d: Source note=%d (%s), ins=%d → Dest note=%d (%s), ins=%d", 
      note_info.line, note_info.col, 
      note_info.src_value, note_info.src_string, note_info.src_ins,
      note_info.dst_value, note_info.dst_string, note_info.dst_ins))
  end
  
  renoise.app():show_status(string.format(
    "Copied phrase %d to track %d (%d lines)", 
    phrase_index, track_index, lines_to_copy))
  
  return true
end

return swapper