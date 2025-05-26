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

  local function get_mappings_for_label(label, is_ghost)
    local song = renoise.song()
    local current_index = labeler.is_locked and labeler.locked_instrument_index 
                        or song.selected_instrument_index
    local stored_data = labeler.saved_labels_by_instrument[current_index] or {}
    local mappings = stored_data.mappings or {}
    
    if not mappings[label] then return {} end
    
    return is_ghost and mappings[label].ghost or mappings[label].regular
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
  print("SWAPPABLE NOTES")
  utils.print_table(swappable_notes)
    

        -- Get all mappings for current instrument
    local song = renoise.song()
    local current_index = labeler.is_locked and labeler.locked_instrument_index 
                        or song.selected_instrument_index
    local stored_data = labeler.saved_labels_by_instrument[current_index] or {}
    local all_mappings = stored_data.mappings or {}
    
    if not next(all_mappings) then
      renoise.app():show_warning("No mappings found. Please create mappings first using Track Mapping dialog.")
      return
    end
    
    -- Round-robin counters for each label type
    local regular_counters = {}
    local ghost_counters = {}
    
    -- Process each label that has mappings
    print("DEBUG: Starting placement with mappings:")
    for label_name, label_mappings in pairs(all_mappings) do
      print(string.format("  Label '%s': %d regular, %d ghost mappings", 
            label_name, #label_mappings.regular, #label_mappings.ghost))
    end
    
    -- Process each label that has mappings
    for label_name, label_mappings in pairs(all_mappings) do
      print(string.format("DEBUG: Processing label '%s'", label_name))
      -- Initialize counters
      regular_counters[label_name] = 0
      ghost_counters[label_name] = 0
      
      -- Process each slice with this label
      for hex_key, label_data in pairs(labels) do
        -- Calculate slice note from hex key (hex_key is like "02", "03", etc.)
        print(string.format("DEBUG: Processing hex_key '%s' for label '%s'", tostring(hex_key), label_name))
        local slice_index = tonumber(hex_key, 16)
        
        if slice_index then
          local slice_note = 36 + slice_index  -1 -- A-2 (36) + slice offset
          local is_primary = (label_data.label == label_name)
          local is_secondary = (label_data.label2 == label_name)
          
          if is_primary or is_secondary then
            print(string.format("DEBUG: Found slice %s (index %d) with note %d for label '%s'", 
                  hex_key, slice_index, slice_note, label_name))
            
            -- Find matching notes in swappable_notes
            local matching_notes = {}
            for _, note_data in ipairs(swappable_notes) do
              if note_data.note == slice_note then
                table.insert(matching_notes, note_data)
                print(string.format("DEBUG: Found matching note %d at line %d track %d", 
                      note_data.note, note_data.line, note_data.track))
              end
            end
            
            print(string.format("DEBUG: Found %d matching notes", #matching_notes))
            
            -- Place notes using appropriate mappings
            for _, note_match in ipairs(matching_notes) do
              local use_ghost = label_data.ghost_note
              local available_mappings = use_ghost and label_mappings.ghost or label_mappings.regular
              local counter = use_ghost and ghost_counters or regular_counters
              
              print(string.format("DEBUG: Use ghost: %s, Available mappings: %d", 
                    tostring(use_ghost), #available_mappings))
              
              if #available_mappings > 0 then
                -- Round-robin selection (reverse order to match UI visual order)
                local mapping_index = #available_mappings - (counter[label_name] % #available_mappings)
                counter[label_name] = counter[label_name] + 1
                local selected_mapping = available_mappings[mapping_index]
                
                local target_track = selected_mapping.track_index
                local target_instrument = selected_mapping.instrument_index
                
                print(string.format("DEBUG: Placing note on track %d, instrument %d, line %d", 
                      target_track, target_instrument, note_match.line))
                
                -- Place the note
                local slot_key = string.format("%d_%d", target_track, note_match.line)
                if not occupied_slots[slot_key] then
                  local pattern = song.patterns[pattern_index]
                  if pattern and pattern.tracks[target_track] then
                    local transfer_line = pattern.tracks[target_track]:line(note_match.line)
                    transfer_line.note_columns[1].note_value = 48
                    transfer_line.note_columns[1].instrument_value = target_instrument
                    transfer_line.note_columns[1].delay_value = note_match.delay
                    transfer_line.note_columns[1].volume_value = note_match.volume
                    transfer_line.note_columns[1].panning_value = note_match.pan
                    
                    occupied_slots[slot_key] = true
                    print(string.format("DEBUG: Successfully placed note at track %d line %d", 
                          target_track, note_match.line))
                  else
                    print(string.format("DEBUG: Failed - no pattern or track %d", target_track))
                  end
                else
                  print(string.format("DEBUG: Slot %s already occupied", slot_key))
                end
              else
                print("DEBUG: No available mappings for this note type")
              end
            end
          end
        else
          print(string.format("DEBUG: Invalid hex_key '%s' - skipping", tostring(hex_key)))
        end
      end
    end
    
    print("DEBUG: Placement complete")
  

  
  renoise.app():show_status("Notes placed on matching tracks")
end

function swapper.linear_swap(track_index, pattern_index)
  local song = renoise.song()
  local pattern_index = pattern_index or song.selected_pattern_index
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
  
  local track = pattern:track(track_index)
  local lines = pattern.number_of_lines
  
  -- Find all notes in the track
  local notes = {}
  for line_idx = 1, lines do
    local pattern_line = track:line(line_idx)
    
    for col_idx = 1, #pattern_line.note_columns do
      local note_column = pattern_line:note_column(col_idx)
      
      -- Only include actual notes (not OFF or EMPTY)
      if note_column.note_value ~= renoise.PatternLine.EMPTY_NOTE and 
         note_column.note_value < 120 then  -- 120 is OFF
        table.insert(notes, {
          line = line_idx,
          column = col_idx,
          delay = note_column.delay_value,
          volume = note_column.volume_value,
          panning = note_column.panning_value
        })
      end
    end
  end
  
  -- Count valid instruments (sequencer instruments, not sends or master)
  local valid_instruments = {}
  for i = 1, #song.instruments do
    -- Check if the instrument has samples or plugins
    if #song.instruments[i].samples > 0 or song.instruments[i].plugin_properties.plugin_loaded then
      table.insert(valid_instruments, i - 1)  -- Convert to 0-based index for note_column.instrument_value
    end
  end
  
  -- If no notes or instruments found, exit
  if #notes == 0 then
    renoise.app():show_warning("No notes found in the selected track.")
    return false
  end
  
  if #valid_instruments == 0 then
    renoise.app():show_warning("No valid instruments found in the song.")
    return false
  end
  
  -- Clear the track first
  for line_idx = 1, lines do
    local pattern_line = track:line(line_idx)
    for col_idx = 1, #pattern_line.note_columns do
      pattern_line:note_column(col_idx):clear()
    end
  end
  
  -- Place new notes with sequential instruments
  local c4_note_value = 48  -- C-4 in Renoise
  
  for i, note_data in ipairs(notes) do
    local instrument_idx = valid_instruments[(i - 1) % #valid_instruments + 1]
    local note_column = track:line(note_data.line):note_column(note_data.column)
    
    note_column.note_value = c4_note_value
    note_column.instrument_value = instrument_idx
    note_column.delay_value = note_data.delay
    note_column.volume_value = note_data.volume
    note_column.panning_value = note_data.panning
  end
  
  renoise.app():show_status(string.format(
    "Linear Swap: Replaced %d notes with C-4 across %d instruments", 
    #notes, #valid_instruments))
  
  return true
end

-- Enhanced function to copy phrase to track with additional options
-- Enhanced function to copy phrase to track with additional options
-- Enhanced function to copy phrase to track with additional options
-- Enhanced function to copy phrase to track with additional options
-- Enhanced function to copy phrase to track with additional options
function swapper.copy_phrase_to_track(phrase_index, track_index, options)
  local song = renoise.song()
  
  -- Default options - maintain backward compatibility while adding new features
  options = options or {}
  local clear_track = options.clear_track or false
  local adjust_pattern = options.adjust_pattern or false
  local pattern_index = options.pattern_index or song.selected_pattern_index
  local debug_mode = options.debug_mode or false

  -- New advanced options from the old version
  local source_phrase_index = options.source_phrase_index or phrase_index
  local transfer_phrase_index = options.transfer_phrase_index or phrase_index
  local pattern_length_mode = options.pattern_length_mode or "none" -- "none", "source", "transfer"
  local overflow_mode = options.overflow_mode or "truncate" -- "truncate", "overflow", "condense"
  
  -- Debug output function
  local function debug_print(message)
    if debug_mode then
      print("[Phrase2Track Debug] " .. message)
    end
  end
  
  debug_print("Starting copy operation...")
  debug_print(string.format("Source Phrase index: %d, Transfer Phrase index: %d, Track index: %d", 
    source_phrase_index, transfer_phrase_index, track_index))
  debug_print(string.format("Pattern length mode: %s, Overflow mode: %s", 
    pattern_length_mode, overflow_mode))
  
  -- Check if an instrument is locked
  if not labeler.is_locked or not labeler.locked_instrument_index then
    renoise.app():show_warning("Please lock an instrument first to use this feature.")
    return false
  end
  
  -- Get the source instrument and phrases
  local instrument = song:instrument(labeler.locked_instrument_index)
  debug_print(string.format("Locked instrument: %s (#%d)", 
    instrument.name, labeler.locked_instrument_index))
  
  -- Validate phrase indices
  if not source_phrase_index or source_phrase_index < 1 or source_phrase_index > #instrument.phrases then
    renoise.app():show_warning(string.format(
      "Invalid source phrase index. The instrument has %d phrases.", 
      #instrument.phrases))
    return false
  end
  
  if not transfer_phrase_index or transfer_phrase_index < 1 or transfer_phrase_index > #instrument.phrases then
    renoise.app():show_warning(string.format(
      "Invalid transfer phrase index. The instrument has %d phrases.", 
      #instrument.phrases))
    return false
  end
  
  local source_phrase = instrument.phrases[source_phrase_index]
  local transfer_phrase = instrument.phrases[transfer_phrase_index]
  
  debug_print(string.format("Source phrase: %s (Lines: %d)", 
    source_phrase.name ~= "" and source_phrase.name or "Unnamed", source_phrase.number_of_lines))
  debug_print(string.format("Transfer phrase: %s (Lines: %d)", 
    transfer_phrase.name ~= "" and transfer_phrase.name or "Unnamed", transfer_phrase.number_of_lines))
  
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
  if pattern_length_mode == "source" and source_phrase.number_of_lines ~= pattern.number_of_lines then
    local old_length = pattern.number_of_lines
    pattern.number_of_lines = source_phrase.number_of_lines
    debug_print(string.format("Pattern length adjusted from %d to %d lines (source)", 
      old_length, source_phrase.number_of_lines))
  elseif pattern_length_mode == "transfer" and transfer_phrase.number_of_lines ~= pattern.number_of_lines then
    local old_length = pattern.number_of_lines
    pattern.number_of_lines = transfer_phrase.number_of_lines
    debug_print(string.format("Pattern length adjusted from %d to %d lines (transfer)", 
      old_length, transfer_phrase.number_of_lines))
  elseif adjust_pattern and source_phrase.number_of_lines ~= pattern.number_of_lines then
    -- Backward compatibility
    local old_length = pattern.number_of_lines
    pattern.number_of_lines = source_phrase.number_of_lines
    debug_print(string.format("Pattern length adjusted from %d to %d lines (backward compatibility)", 
      old_length, source_phrase.number_of_lines))
  end
  
  -- Get the number of lines to copy and scaling factor for condensing
  local transfer_lines = transfer_phrase.number_of_lines
  local pattern_lines = pattern.number_of_lines
  local lines_to_copy = transfer_lines
  local scaling_factor = 1.0
  
  -- Determine number of lines to copy based on overflow mode
  if overflow_mode == "truncate" then
    lines_to_copy = math.min(transfer_lines, pattern_lines)
    debug_print(string.format("Truncating copy to %d lines", lines_to_copy))
  elseif overflow_mode == "overflow" then
    -- Will handle overflow later by creating additional patterns
    lines_to_copy = transfer_lines
    debug_print(string.format("Will copy all %d lines with overflow if needed", lines_to_copy))
  elseif overflow_mode == "condense" then
    lines_to_copy = transfer_lines
    if transfer_lines > pattern_lines then
      scaling_factor = pattern_lines / transfer_lines
      debug_print(string.format("Condensing %d transfer lines into %d pattern lines (factor: %.3f)", 
        transfer_lines, pattern_lines, scaling_factor))
    end
  end
  
  -- Clear the target track(s) if requested
  if clear_track then
    debug_print("Clearing target track...")
    
    -- Clear first pattern
    for line_idx = 1, pattern_lines do
      local pattern_line = target_track:line(line_idx)
      for col_idx = 1, #pattern_line.note_columns do
        pattern_line:note_column(col_idx):clear()
      end
      for col_idx = 1, #pattern_line.effect_columns do
        pattern_line:effect_column(col_idx):clear()
      end
    end
    
    -- Clear any overflow patterns if needed
    if overflow_mode == "overflow" and transfer_lines > pattern_lines then
      local num_overflow_patterns = math.ceil(transfer_lines / pattern_lines) - 1
      
      for overflow_idx = 1, num_overflow_patterns do
        -- Check if we have enough patterns
        if pattern_index + overflow_idx <= #song.patterns then
          local overflow_pattern = song:pattern(pattern_index + overflow_idx)
          local overflow_track = overflow_pattern:track(track_index)
          
          for line_idx = 1, overflow_pattern.number_of_lines do
            local pattern_line = overflow_track:line(line_idx)
            for col_idx = 1, #pattern_line.note_columns do
              pattern_line:note_column(col_idx):clear()
            end
            for col_idx = 1, #pattern_line.effect_columns do
              pattern_line:effect_column(col_idx):clear()
            end
          end
        end
      end
    end
  end
  
  -- Create a debug table to track note values
  local debug_notes = {}
  
  -- Note value conversion function - starting with C2 (36)
  local function instrument_to_note(instrument_value)
    -- C2 is MIDI note 36, so we'll add 35 to the instrument value
    -- Since instrument indexing starts at 1, and we want instrument 1 to be C2 (36)
    if instrument_value < 1 then return nil end
    return 35 + instrument_value
  end
  
  -- Build the cipher/mapping from the source phrase
  local instrument_note_map = {}
  debug_print("Building instrument-to-note mapping from source phrase:")
  
  -- First pass: analyze source phrase to build the mapping
  for line_idx = 1, source_phrase.number_of_lines do
    local line = source_phrase:line(line_idx)
    
    for col_idx = 1, #line.note_columns do
      local note = line:note_column(col_idx)
      
      if note.note_value ~= renoise.PatternLine.EMPTY_NOTE and note.note_value < 121 then
        if note.instrument_value >= 0 then
          -- Map this instrument value to the note value
          if not instrument_note_map[note.instrument_value] then
            local mapped_note = instrument_to_note(note.instrument_value + 1) -- +1 for 0-based to 1-based
            instrument_note_map[note.instrument_value] = mapped_note
            debug_print(string.format("  Instrument %d maps to note %d (%s)", 
              note.instrument_value, mapped_note, note.note_string))
          end
        end
      end
    end
  end
  
  -- Helper function to calculate condense position
  local function get_condensed_line_index(source_line_idx)
    return math.floor((source_line_idx - 1) * scaling_factor) + 1
  end

  -- Helper function to scale delay values for condensing
  local function get_condensed_delay(delay_value)
    -- Simply scale the delay value by the same factor used for lines
    local scaled_delay = math.floor(delay_value * scaling_factor)
    -- Ensure it stays within the valid range (0-255)
    return math.min(255, math.max(0, scaled_delay))
  end
  
  -- Helper function to get the correct pattern and line for overflow
  local function get_pattern_and_line(source_line_idx)
    if overflow_mode ~= "overflow" or source_line_idx <= pattern_lines then
      return pattern, source_line_idx
    else
      debug_print(string.format("Handling overflow for line %d (pattern size: %d)", 
                              source_line_idx, pattern_lines))
      
      -- Start from the currently selected sequence
      local current_sequence_idx = song.selected_sequence_index
      local lines_processed = pattern_lines  -- We've already processed the first pattern's worth
      local target_sequence_idx = current_sequence_idx
      local target_line_idx = source_line_idx
      
      -- Find which sequence and line this source line maps to
      while lines_processed < source_line_idx do
        -- Move to next sequence
        target_sequence_idx = target_sequence_idx + 1
        
        -- Check if we need to create a new pattern
        if target_sequence_idx > #song.sequencer.pattern_sequence then
          debug_print("Creating new pattern in sequence")
          song.sequencer:insert_new_pattern_at(#song.sequencer.pattern_sequence + 1)
        end
        
        -- Get pattern at this sequence and its line count
        local next_pattern_idx = song.sequencer:pattern(target_sequence_idx)
        local next_pattern = song:pattern(next_pattern_idx)
        local next_pattern_lines = next_pattern.number_of_lines
        
        debug_print(string.format("Sequence %d: Pattern %d with %d lines", 
                                target_sequence_idx, next_pattern_idx, next_pattern_lines))
        
        -- If we've found the right pattern
        if lines_processed + next_pattern_lines >= source_line_idx then
          target_line_idx = source_line_idx - lines_processed
          debug_print(string.format("Found target: Sequence %d, Line %d", 
                                  target_sequence_idx, target_line_idx))
          break
        end
        
        -- Otherwise keep accumulating lines
        lines_processed = lines_processed + next_pattern_lines
      end
      
      -- Get the appropriate pattern and return
      local target_pattern_idx = song.sequencer:pattern(target_sequence_idx)
      local target_pattern = song:pattern(target_pattern_idx)
      
      return target_pattern, target_line_idx
    end
  end
  
  -- Process each line from the transfer phrase
  for line_idx = 1, lines_to_copy do
    -- Skip if beyond transfer phrase length
    if line_idx > transfer_phrase.number_of_lines then
      break
    end
    
    -- Get transfer phrase line
    local transfer_line = transfer_phrase:line(line_idx)
    
    -- Determine target line index based on overflow/condense mode
    local target_pattern, target_line_idx
    
    if overflow_mode == "condense" then
      target_pattern = pattern
      target_line_idx = get_condensed_line_index(line_idx)
    else
      target_pattern, target_line_idx = get_pattern_and_line(line_idx)
    end
    
    -- Get target pattern line
    local target_track_in_pattern = target_pattern:track(track_index)
    local pattern_line = target_track_in_pattern:line(target_line_idx)
    
    -- Copy note columns from the transfer phrase, using the mapping from the source phrase
    for col_idx = 1, math.min(#transfer_line.note_columns, #pattern_line.note_columns) do
      local transfer_note = transfer_line:note_column(col_idx)
      local dst_note = pattern_line:note_column(col_idx)
      
      -- Skip empty notes
      if transfer_note.note_value ~= renoise.PatternLine.EMPTY_NOTE then
        -- Debug the original note data
        debug_print(string.format(
          "Line %03d Col %d: Transfer: note_value=%d, note_string='%s', ins=%d", 
          line_idx, col_idx, 
          transfer_note.note_value, 
          transfer_note.note_string, 
          transfer_note.instrument_value))
        
        -- Determine the target note value using the mapping from source phrase
        local target_note_value
        
        -- Handle special notes (OFF, etc.)
        if transfer_note.note_value >= 121 then  -- OFF or other special notes
          target_note_value = transfer_note.note_value
        else
          -- Use the mapping from the source phrase if available
          if transfer_note.instrument_value >= 0 and instrument_note_map[transfer_note.instrument_value] then
            target_note_value = instrument_note_map[transfer_note.instrument_value]
            debug_print(string.format("Using mapping: ins %d -> note %d", 
              transfer_note.instrument_value, target_note_value))
          else
            -- Fallback to direct conversion if no mapping exists
            target_note_value = instrument_to_note(transfer_note.instrument_value + 1)
            debug_print(string.format("No mapping, using direct conversion: ins %d -> note %d", 
              transfer_note.instrument_value, target_note_value or -1))
          end
        end
        
        -- Set the note value in the destination
        if target_note_value then
          dst_note.note_value = target_note_value
          
          -- Set the instrument value
          dst_note.instrument_value = labeler.locked_instrument_index - 1 -- 0-based
        else
          -- If we couldn't determine a valid note value, use OFF
          dst_note.note_value = 120 -- OFF
          dst_note.instrument_value = labeler.locked_instrument_index - 1
          debug_print("WARNING: Could not determine note value, using OFF")
        end
        
        -- Copy other properties from transfer phrase
        if transfer_note.volume_value ~= renoise.PatternLine.EMPTY_VOLUME then
          dst_note.volume_value = transfer_note.volume_value
        end
        
        if transfer_note.panning_value ~= renoise.PatternLine.EMPTY_PANNING then
          dst_note.panning_value = transfer_note.panning_value
        end
        
        if overflow_mode == "condense" then
          -- Apply the scaled delay value
          dst_note.delay_value = get_condensed_delay(transfer_note.delay_value)
          
          debug_print(string.format("Condensed delay: original=%d, scaled=%d", 
            transfer_note.delay_value, dst_note.delay_value))
        else
          -- Use original delay for non-condense modes
          dst_note.delay_value = transfer_note.delay_value
        end
        
        -- Store for debugging
        table.insert(debug_notes, {
          line = line_idx,
          target_line = target_line_idx,
          col = col_idx,
          transfer_value = transfer_note.note_value,
          transfer_string = transfer_note.note_string,
          transfer_ins = transfer_note.instrument_value,
          dst_value = dst_note.note_value,
          dst_string = dst_note.note_string,
          dst_ins = dst_note.instrument_value
        })
      end
    end
    
    -- Copy effect columns from transfer phrase
    for col_idx = 1, math.min(#transfer_line.effect_columns, #pattern_line.effect_columns) do
      local transfer_fx = transfer_line:effect_column(col_idx)
      local dst_fx = pattern_line:effect_column(col_idx)
      
      -- Only copy non-empty effects
      if transfer_fx.number_string ~= "" and transfer_fx.number_string ~= "00" then
        debug_print(string.format(
          "Line %03d FX %d: number='%s', amount='%s'", 
          line_idx, col_idx, 
          transfer_fx.number_string, 
          transfer_fx.amount_string))
          
        dst_fx.number_string = transfer_fx.number_string
        dst_fx.amount_value = transfer_fx.amount_value
      end
    end
  end
  
  -- Print final debug summary of note copying
  debug_print("--- Note Copy Summary ---")
  for _, note_info in ipairs(debug_notes) do
    debug_print(string.format(
      "Transfer Line %03d -> Target Line %03d, Col %d: Transfer note=%d (%s), ins=%d → Dest note=%d (%s), ins=%d", 
      note_info.line, note_info.target_line, note_info.col, 
      note_info.transfer_value, note_info.transfer_string, note_info.transfer_ins,
      note_info.dst_value, note_info.dst_string, note_info.dst_ins))
  end
  
  renoise.app():show_status(string.format(
    "Copied phrases to track %d (%d transfer lines)", 
    track_index, lines_to_copy))
  
  return true
end

-- Track to Phrase conversion function
function swapper.copy_track_to_phrase(track_index, conversion_mode, options)
  local song = renoise.song()
  
  -- Default options - maintain backward compatibility while adding new features
  options = options or {}
  local clear_track = options.clear_track or false
  local adjust_pattern = options.adjust_pattern or false
  local debug_mode = options.debug_mode or true
  
  -- Debug output function
  local function debug_print(message)
    if debug_mode then
      print("[Track2Phrase Debug] " .. message)
    end
  end
  
  debug_print("Starting track to phrase conversion...")
  debug_print(string.format("Track index: %d, Mode: %s", 
    track_index, conversion_mode))
  
  -- Check if an instrument is locked
  if not labeler.is_locked or not labeler.locked_instrument_index then
    renoise.app():show_warning("Please lock an instrument first to use this feature.")
    return false
  end
  
  -- Get the locked instrument and validate phrase
  local instrument = song:instrument(labeler.locked_instrument_index)
  debug_print(string.format("Locked instrument: %s (#%d)", 
    instrument.name, labeler.locked_instrument_index))
  
  -- Create a new phrase
  local new_phrase = instrument:insert_phrase_at(#instrument.phrases + 1)
  new_phrase.name = string.format("Track %d Copy", track_index)
  local target_phrase = new_phrase
  debug_print(string.format("Created new phrase: %s", target_phrase.name))
  
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
  
  -- Get source pattern and track
  local pattern_index = options.pattern_index or song.selected_pattern_index
  local pattern = song:pattern(pattern_index)
  local source_track = pattern:track(track_index)
  debug_print(string.format("Source track: %s (#%d)", 
    song.tracks[track_index].name, track_index))
  
  -- Validate instrument has samples
  if #instrument.samples == 0 then
    renoise.app():show_warning("The locked instrument has no samples.")
    return false
  end
  
  local num_samples = #instrument.samples
  debug_print(string.format("Instrument has %d samples", num_samples))
  
  -- Setup phrase properties from global song state
  target_phrase.lpb = song.transport.lpb
  target_phrase.number_of_lines = pattern.number_of_lines
  debug_print(string.format("Set phrase LPB: %d, Lines: %d", 
    target_phrase.lpb, target_phrase.number_of_lines))

  
  -- Build reverse mapping for mapping mode
  local reverse_map = nil
  local mappable_note_count = 0
  
  if conversion_mode == "mapping" then
    debug_print("Building reverse mapping...")
    
    -- Get current mappings
    local current_index = labeler.locked_instrument_index
    local stored_data = labeler.saved_labels_by_instrument[current_index] or {}
    local all_mappings = stored_data.mappings or {}
    
    if not next(all_mappings) then
      renoise.app():show_warning("No mappings found. Please create mappings first using Track Mapping dialog.")
      return false
    end
    
    -- Get current labels for sample resolution
    local current_labels = labeler.saved_labels_by_instrument[current_index] or {}
    
    -- Helper function to find samples for a label
    local function find_samples_for_label(target_label)
      local sample_indices = {}
      for hex_key, label_data in pairs(current_labels) do
        if (label_data.label == target_label or label_data.label2 == target_label) and
           label_data.label ~= "---------" and label_data.label2 ~= "---------" then
          local slice_index = tonumber(hex_key, 16)
          if slice_index then
            table.insert(sample_indices, slice_index)
          end
        end
      end
      table.sort(sample_indices) -- Consistent ordering
      return sample_indices
    end
    
    -- Build reverse mapping
    reverse_map = {}
    
    for label, mappings in pairs(all_mappings) do
      local sample_indices = find_samples_for_label(label)
      
      if #sample_indices > 0 then
        debug_print(string.format("Label '%s' maps to %d samples", label, #sample_indices))
        
        -- Map regular mappings with round-robin
        for i, mapping in ipairs(mappings.regular) do
          local key = string.format("%d_%d", mapping.track_index, mapping.instrument_index)
          local sample_idx = sample_indices[((i - 1) % #sample_indices) + 1]
          reverse_map[key] = {sample_index = sample_idx, is_ghost = false}
          debug_print(string.format("  Regular mapping: T%d_I%d -> Sample %d", 
            mapping.track_index, mapping.instrument_index, sample_idx))
        end
        
        -- Map ghost mappings with round-robin
        for i, mapping in ipairs(mappings.ghost) do
          local key = string.format("%d_%d", mapping.track_index, mapping.instrument_index)
          local sample_idx = sample_indices[((i - 1) % #sample_indices) + 1]
          reverse_map[key] = {sample_index = sample_idx, is_ghost = true}
          debug_print(string.format("  Ghost mapping: T%d_I%d -> Sample %d (ghost)", 
            mapping.track_index, mapping.instrument_index, sample_idx))
        end
      end
    end
    
    -- Count mappable notes in the source track
    for line_idx = 1, pattern.number_of_lines do
      local track_line = source_track:line(line_idx)
      for col_idx = 1, #track_line.note_columns do
        local note_column = track_line:note_column(col_idx)
        if note_column.note_value ~= renoise.PatternLine.EMPTY_NOTE and note_column.note_value < 121 then
          local key = string.format("%d_%d", track_index, note_column.instrument_value)
          if reverse_map[key] then
            mappable_note_count = mappable_note_count + 1
          end
        end
      end
    end
    
    debug_print(string.format("Found %d mappable notes in source track", mappable_note_count))
    
    if mappable_note_count == 0 then
      local result = renoise.app():show_prompt("No Mappable Notes", 
        "No notes in the source track match existing mappings. Continue anyway?", 
        {"Continue", "Cancel"})
      if result == "Cancel" then
        return false
      end
    end
  end
  
  -- Convert notes
  local converted_count = 0
  local skipped_count = 0
  
  for line_idx = 1, pattern.number_of_lines do
    local track_line = source_track:line(line_idx)
    local phrase_line = target_phrase:line(line_idx)
    
    -- Copy note columns
    for col_idx = 1, math.min(#track_line.note_columns, #phrase_line.note_columns) do
      local src_note = track_line:note_column(col_idx)
      local dst_note = phrase_line:note_column(col_idx)
      
      -- Skip empty notes
      if src_note.note_value ~= renoise.PatternLine.EMPTY_NOTE then
        local target_sample_index = nil
        
        if conversion_mode == "note" then
          -- Note mode: direct mathematical mapping
          if src_note.note_value < 121 then -- Not OFF or special notes
            local sample_index = (src_note.note_value - 36) + 1
            
            -- Handle wrapping
            if sample_index < 1 then
              sample_index = num_samples + (sample_index % num_samples)
            elseif sample_index > num_samples then
              sample_index = ((sample_index - 1) % num_samples) + 1
            end
            
            target_sample_index = sample_index
            debug_print(string.format("Note mode: Note %d -> Sample %d", 
              src_note.note_value, target_sample_index))
          else
            -- Handle OFF and special notes directly
            target_sample_index = "special"
          end
          
        elseif conversion_mode == "mapping" then
          -- Mapping mode: use reverse lookup
          if src_note.note_value < 121 then -- Not OFF or special notes
            local key = string.format("%d_%d", track_index, src_note.instrument_value)
            local mapping_info = reverse_map[key]
            
            if mapping_info then
              target_sample_index = mapping_info.sample_index
              debug_print(string.format("Mapping mode: T%d_I%d -> Sample %d%s", 
                track_index, src_note.instrument_value, target_sample_index,
                mapping_info.is_ghost and " (ghost)" or ""))
            else
              debug_print(string.format("Mapping mode: No mapping for T%d_I%d, skipping", 
                track_index, src_note.instrument_value))
              skipped_count = skipped_count + 1
            end
          else
            -- Handle OFF and special notes directly
            target_sample_index = "special"
          end
        end
        
        -- Apply the conversion
        if target_sample_index then
          if target_sample_index == "special" then
            -- Copy special notes (OFF, etc.) directly
            dst_note.note_value = src_note.note_value
            dst_note.instrument_value = labeler.locked_instrument_index - 1
          else
            -- Convert to sample-based note
            dst_note.note_value = 35 + target_sample_index -- C-2 is 36, so sample 1 = C-2
            dst_note.instrument_value = labeler.locked_instrument_index - 1
          end
          
          -- Copy other properties
          if src_note.volume_value ~= renoise.PatternLine.EMPTY_VOLUME then
            dst_note.volume_value = src_note.volume_value
          end
          if src_note.panning_value ~= renoise.PatternLine.EMPTY_PANNING then
            dst_note.panning_value = src_note.panning_value
          end
          dst_note.delay_value = src_note.delay_value
          
          converted_count = converted_count + 1
        end
      end
    end
    
    -- Copy effect columns directly
    for col_idx = 1, math.min(#track_line.effect_columns, #phrase_line.effect_columns) do
      local src_fx = track_line:effect_column(col_idx)
      local dst_fx = phrase_line:effect_column(col_idx)
      
      if src_fx.number_string ~= "" and src_fx.number_string ~= "00" then
        dst_fx.number_string = src_fx.number_string
        dst_fx.amount_value = src_fx.amount_value
        debug_print(string.format("Copied effect: %s %02X", 
          src_fx.number_string, src_fx.amount_value))
      end
    end
  end
  
  -- Report results
  local status_message = string.format(
    "Converted %d notes from track %d to new phrase '%s'", 
    converted_count, track_index, target_phrase.name)
  
  if skipped_count > 0 then
    status_message = status_message .. string.format(" (%d notes skipped)", skipped_count)
  end
  
  renoise.app():show_status(status_message)
  debug_print("Conversion complete: " .. status_message)
  
  return true
end

return swapper