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
  priority = "high"
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
  local pattern_index = song.selected_sequence_index
  local pattern = song:pattern(pattern_index)
  
  return {
    pattern_index = pattern_index,
    num_lines = pattern.number_of_lines
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

local function load_rendered_sample(file_name)
  local song = renoise.song()
  local new_instrument = song:insert_instrument_at(song.selected_instrument_index + 1)
  new_instrument.name = "Rendered Pattern"
  
  new_instrument:insert_sample_at(1)
  local new_sample = new_instrument.samples[1]
  
  new_sample.sample_buffer:load_from(file_name)
  
  os.remove(file_name)
  
  copy_slice_markers(song.selected_instrument, new_instrument)
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
  rerender.config.start_sequence = rerender.config.start_sequence or pattern_info.pattern_index
  rerender.config.end_sequence = rerender.config.end_sequence or pattern_info.pattern_index
  rerender.config.end_line = rerender.config.end_line or pattern_info.num_lines
  
  if not rerender.config.sample_rate then
    rerender.load_saved_settings()
  end
  
  -- Update sample rate from locked instrument if available
  if labeler.is_locked and labeler.locked_instrument_index then
    local source_instrument = song:instrument(labeler.locked_instrument_index)
    print("LOCKED INSTRUMENT")
    print(labeler.locked_instrument_index)
    if source_instrument and #source_instrument.samples > 0 then
      rerender.config.sample_rate = source_instrument.samples[1].sample_buffer.sample_rate
      
      local new_pattern_idx, err, num_patterns = create_pattern_from_phrase(source_instrument, labeler.locked_instrument_index)
      print("NEW PATTERN INDEX")
      print(new_pattern_idx)
      print("PATTERN NUMBER")
      print(num_patterns)
      if new_pattern_idx then
        pattern_to_delete = new_pattern_idx
        rerender.config.start_sequence = new_pattern_idx
        rerender.config.end_sequence = new_pattern_idx
        rerender.config.end_line = song:pattern(new_pattern_idx).number_of_lines

        swapper.place_notes_on_matching_tracks(1, num_patterns)

        renoise.song().tracks[1]:mute()
        
        
      else
        renoise.app():show_warning("Failed to create pattern from phrase: " .. (err or "unknown error"))
        return
      end
    end
  end
  
  
  local function rendering_finished()
    load_rendered_sample(file_name)
    if pattern_to_delete then
      renoise.song().tracks[1]:unmute()
      renoise.song().sequencer:delete_sequence_at(pattern_to_delete)
    end
    rerender.config.start_sequence = nil
    rerender.config.end_sequence = nil
    rerender.config.end_line = nil
    labeler.unlock_instrument()
  end

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