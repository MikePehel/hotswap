local rerender = {}
local labeler = require("labeler")
local swapper = require("swapper")


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

local function create_pattern_from_phrase(source_instrument, instrument_idx)
  print("SOURCE INSTRUMENT INDEX")
  print(instrument_idx)
  local song = renoise.song()
  
  if #source_instrument.phrases == 0 then
    return nil, "No phrase found in source instrument"
  end
  
  -- Note: This function returns:
  -- 1) The sequence index for the new pattern
  -- 2) Track object for the pattern
  -- 3) The pattern index in song.patterns
  
  local source_phrase = source_instrument.phrases[1]
  
  local new_pattern_index = #song.sequencer.pattern_sequence + 1
  renoise.song().sequencer:insert_new_pattern_at(new_pattern_index)
  local new_pattern = song:pattern(#song.patterns)
  
  
  new_pattern.number_of_lines = source_phrase.number_of_lines
  
  local track = new_pattern:track(1)
  
  for line_idx = 1, source_phrase.number_of_lines do
    local phrase_line = source_phrase:line(line_idx)
    local pattern_line = track:line(line_idx)
    
    for col_idx = 1, #phrase_line.note_columns do
      local src_note = phrase_line:note_column(col_idx)
      local dst_note = pattern_line:note_column(col_idx)
      
      dst_note.note_value = src_note.note_value
      if src_note.note_value < 121 then
        dst_note.instrument_value = instrument_idx - 1
      end
      dst_note.volume_value = src_note.volume_value
      dst_note.panning_value = src_note.panning_value
      dst_note.delay_value = src_note.delay_value
    end
    
    for col_idx = 1, #phrase_line.effect_columns do
      local src_fx = phrase_line:effect_column(col_idx)
      local dst_fx = pattern_line:effect_column(col_idx)
      
      dst_fx.number_string = src_fx.number_string
      dst_fx.amount_value = src_fx.amount_value
    end
  end
  
  return new_pattern_index, track, #song.patterns
end

-- Add default configuration
rerender.config = {
  start_sequence = nil,  
  end_sequence = nil,    
  start_line = 1,
  end_line = nil,        
  sample_rate = 44100,
  bit_depth = 32,
  interpolation = "default",
  priority = "high",
  marker_placement = "pattern"  -- Options: "pattern" or "source"
}

rerender.saved_settings = {
  sample_rate = 44100,
  bit_depth = 32
}

function rerender.save_settings()
  rerender.saved_settings.sample_rate = rerender.config.sample_rate
  rerender.saved_settings.bit_depth = rerender.config.bit_depth
end

function rerender.load_saved_settings()
  rerender.config.sample_rate = rerender.saved_settings.sample_rate
  rerender.config.bit_depth = rerender.saved_settings.bit_depth
end

function rerender.set_render_options(options)
  if type(options) == "table" then
    for k, v in pairs(options) do
      if rerender.config[k] ~= nil then
        rerender.config[k] = v
      end
    end
  end
end

function rerender.get_current_pattern_info()
  local song = renoise.song()
  local sequence_index = song.selected_sequence_index
  local pattern_index = song.sequencer:pattern(sequence_index)
  local pattern = song:pattern(pattern_index)
  
  return {
    sequence_index = sequence_index,
    pattern_index = pattern_index,
    num_lines = pattern.number_of_lines,
    total_sequences = #song.sequencer.pattern_sequence
  }
end

local function copy_slice_markers(source_instrument, target_instrument)
  if not source_instrument.samples[1] or not target_instrument.samples[1] then
    return
  end
  
  local source_sample = source_instrument.samples[1]
  local target_sample = target_instrument.samples[1]
  
  target_sample.slice_markers = {}
  
  local source_frames = source_sample.sample_buffer.number_of_frames
  local target_frames = target_sample.sample_buffer.number_of_frames
  
  for _, marker_pos in ipairs(source_sample.slice_markers) do
    local relative_pos = marker_pos / source_frames
    local adjusted_pos = math.max(1, math.min(target_frames, math.floor(relative_pos * target_frames)))
    target_sample:insert_slice_marker(adjusted_pos)
  end
end



local function place_markers_from_pattern_notes(pattern_index, target_sample)
  local song = renoise.song()
  local pattern = song:pattern(pattern_index)
  local track_index = 1  -- This will typically be track 1 where notes are placed
  
  -- Get timing information
  local bpm = song.transport.bpm
  local lpb = song.transport.lpb
  local sample_rate = target_sample.sample_buffer.sample_rate
  local total_frames = target_sample.sample_buffer.number_of_frames
  
  -- Calculate frames per line
  local seconds_per_line = 60 / (bpm * lpb)
  local frames_per_line = seconds_per_line * sample_rate
  
  -- Calculate total pattern length in frames
  local pattern_frames = pattern.number_of_lines * frames_per_line
  
  -- Scaling factor in case the sample doesn't match pattern length exactly
  local scaling_factor = total_frames / pattern_frames
  
  -- Clear existing markers
  target_sample.slice_markers = {}
  
  -- For each line in the pattern
  for line_idx = 1, pattern.number_of_lines do
    local line = pattern:track(track_index):line(line_idx)
    
    -- Check all note columns for notes
    for note_col_idx = 1, #line.note_columns do
      local note_column = line:note_column(note_col_idx)
      
      -- If there's a note and it's not OFF or EMPTY
      if note_column.note_value < 120 then
        -- Calculate exact position accounting for delay
        local line_frames = (line_idx - 1) * frames_per_line
        local delay_frames = (note_column.delay_value / 255) * frames_per_line
        
        -- Get precise frame position with scaling
        local marker_pos = math.floor((line_frames + delay_frames) * scaling_factor)
        
        -- Ensure position is within valid range
        marker_pos = math.max(1, math.min(total_frames, marker_pos))
        
        -- Insert the marker
        target_sample:insert_slice_marker(marker_pos)
        
        print(string.format("Added slice marker at line %d, delay %d (frame %d of %d)", 
                            line_idx, note_column.delay_value, marker_pos, total_frames))
      end
    end
  end
  
  -- Sort markers to ensure they're in ascending order
  table.sort(target_sample.slice_markers)
  
  -- Remove duplicates that might be too close together
  for i = #target_sample.slice_markers, 2, -1 do
    if math.abs(target_sample.slice_markers[i] - target_sample.slice_markers[i-1]) < 100 then
      table.remove(target_sample.slice_markers, i)
    end
  end
  
  print(string.format("Placed %d slice markers based on pattern notes", 
                      #target_sample.slice_markers))
end

local function load_rendered_sample(file_name, pattern_idx)
  local song = renoise.song()
  local new_instrument = song:insert_instrument_at(song.selected_instrument_index + 1)
  new_instrument.name = "Rendered Pattern"
  
  new_instrument:insert_sample_at(1)
  local new_sample = new_instrument.samples[1]
  
  new_sample.sample_buffer:load_from(file_name)
  
  os.remove(file_name)
  
  -- Choose marker placement method based on config
  if rerender.config.marker_placement == "pattern" and pattern_idx then
    place_markers_from_pattern_notes(pattern_idx, new_sample)
  else
    copy_slice_markers(song.selected_instrument, new_instrument)
  end
end

-- New core rendering function
local function render_to_wav(start_seq, end_seq, start_line, end_line, file_name)
  local song = renoise.song()
  
  local options = {
    start_pos = renoise.SongPos(start_seq, start_line),
    end_pos = renoise.SongPos(end_seq, end_line),
    sample_rate = rerender.config.sample_rate,
    bit_depth = rerender.config.bit_depth,
    interpolation = rerender.config.interpolation,
    priority = rerender.config.priority
  }
  
  local function rendering_done()
    load_rendered_sample(file_name)
  end
  
  return song:render(options, file_name, rendering_done)
end

function rerender.render_current_pattern()
  local song = renoise.song()
  local pattern_info = rerender.get_current_pattern_info()
  local file_name = os.tmpname() .. ".wav"
  local pattern_to_delete = nil
  
  -- Set default values if not configured
  rerender.config.start_sequence = rerender.config.start_sequence or pattern_info.sequence_index
  rerender.config.end_sequence = rerender.config.end_sequence or pattern_info.sequence_index
  rerender.config.end_line = rerender.config.end_line or pattern_info.num_lines
  
  if not rerender.config.sample_rate then
    rerender.load_saved_settings()
  end
  
  -- Store pattern indices corresponding to our sequences
  local start_pattern = song.sequencer:pattern(rerender.config.start_sequence)
  local end_pattern = song.sequencer:pattern(rerender.config.end_sequence)
  
  -- Debug info
  print("Selected sequence: " .. pattern_info.sequence_index .. 
        " (pattern: " .. pattern_info.pattern_index .. ")")
  
  -- Update sample rate from locked instrument if available
  -- Update sample rate from locked instrument if available
  if labeler.is_locked and labeler.locked_instrument_index then
    local source_instrument = song:instrument(labeler.locked_instrument_index)
    print("LOCKED INSTRUMENT")
    print(labeler.locked_instrument_index)
    if source_instrument and #source_instrument.samples > 0 then
      rerender.config.sample_rate = source_instrument.samples[1].sample_buffer.sample_rate
      
      local new_sequence_idx, err, num_patterns = create_pattern_from_phrase(source_instrument, labeler.locked_instrument_index)
      print("NEW SEQUENCE INDEX")
      print(new_sequence_idx)
      print("PATTERN NUMBER")
      print(num_patterns)
      if new_sequence_idx then
        pattern_to_delete = new_sequence_idx
        rerender.config.start_sequence = new_sequence_idx
        rerender.config.end_sequence = new_sequence_idx
        
        -- Get the actual pattern index for the new sequence
        start_pattern = song.sequencer:pattern(rerender.config.start_sequence)
        end_pattern = start_pattern
        
        print("Created pattern from phrase. Sequence: " .. new_sequence_idx .. 
              ", Pattern: " .. start_pattern)
        
        rerender.config.end_line = song:pattern(start_pattern).number_of_lines

        -- For clarity, pass the pattern index, not sequence index
        swapper.place_notes_on_matching_tracks(1, start_pattern)

        renoise.song().tracks[1]:mute()
      else
        renoise.app():show_warning("Failed to create pattern from phrase: " .. (err or "unknown error"))
        return
      end
    end
  end
  
  local function rendering_finished()
    local pattern_idx = pattern_to_delete and start_pattern or nil
    load_rendered_sample(file_name, pattern_idx)
    if pattern_to_delete then
      renoise.song().tracks[1]:unmute()
      renoise.song().sequencer:delete_sequence_at(pattern_to_delete)
    end
    rerender.config.start_sequence = nil
    rerender.config.end_sequence = nil
    rerender.config.end_line = nil
    labeler.unlock_instrument()
  end

  -- Add debug info before rendering
  print("Rendering from sequence " .. rerender.config.start_sequence .. 
        " (pattern " .. start_pattern .. ") line " .. rerender.config.start_line .. 
        " to sequence " .. rerender.config.end_sequence .. 
        " (pattern " .. end_pattern .. ") line " .. rerender.config.end_line)
        
  local success, error_message = song:render({
    start_pos = renoise.SongPos(rerender.config.start_sequence, rerender.config.start_line),
    end_pos = renoise.SongPos(rerender.config.end_sequence, rerender.config.end_line),
    sample_rate = rerender.config.sample_rate,
    bit_depth = rerender.config.bit_depth,
    interpolation = rerender.config.interpolation,
    priority = rerender.config.priority
  }, file_name, rendering_finished)
  
  if not success then
    renoise.app():show_warning("Rendering failed: " .. error_message)
  end
end

return rerender