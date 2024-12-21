-- evaluators.lua

local evaluators = {}
local vb = renoise.ViewBuilder()

-- Modified function in evaluators.lua
function evaluators.evaluate_note_length(phrase)
  local note_data = {}
  local lines = phrase.number_of_lines
  
  for i = 1, lines do
    local line = phrase:line(i)
    local note_column = line:note_column(1)
    local note = note_column.note_string
    local instrument = note_column.instrument_value
    local delay_value = note_column.delay_value
    
    local distance = 0
    local found_next_note = false
    
    for j = i + 1, lines do
      local next_line = phrase:line(j)
      local next_note_column = next_line:note_column(1)
      
      if next_note_column.note_string ~= "---" then
        local lines_to_next_note = j - i
        local next_delay_value = next_note_column.delay_value
        distance = (lines_to_next_note * 256) - delay_value + next_delay_value
        found_next_note = true
        break
      end
    end
    
    -- If no next note was found, calculate distance to end of phrase
    if not found_next_note then
      local lines_to_end = (lines + 1) - i
      distance = (lines_to_end * 256) - delay_value
    end
    
    note_data[i] = {note, instrument, distance}
  end
  
  -- Calculate total phrase length in ticks
  local total_phrase_ticks = lines * 256
  
  local note_data_str = ""
  for k, v in pairs(note_data) do
    note_data_str = note_data_str .. string.format("Line %d: Note=%s, Instrument=%d, Distance=%d\n", k, v[1], v[2], v[3])
  end
  
  -- Add total phrase length information
  note_data_str = note_data_str .. string.format("\nTotal Phrase Length: %d ticks", total_phrase_ticks)
  
  local dialog_view = vb:column {
    vb:multiline_text {
      text = note_data_str,
      width = 400,
      height = 300
    }
  }
  
  renoise.app():show_custom_prompt("Note Data", dialog_view, {"OK"})
  
  return note_data
end

function evaluators.get_note_distances(phrase)
  local note_data = {}
  local lines = phrase.number_of_lines
  
  for i = 1, lines do
    local line = phrase:line(i)
    local note_column = line:note_column(1)
    
    -- Only store data for actual notes, not empty lines
    if note_column.note_string ~= "---" then
      local delay_value = note_column.delay_value
      
      local distance = 0
      local found_next_note = false
      
      for j = i + 1, lines do
        local next_line = phrase:line(j)
        local next_note_column = next_line:note_column(1)
        
        if next_note_column.note_string ~= "---" then
          local lines_to_next_note = j - i
          local next_delay_value = next_note_column.delay_value
          distance = (lines_to_next_note * 256) - delay_value + next_delay_value
          found_next_note = true
          break
        end
      end
      
      if not found_next_note then
        local lines_to_end = (lines + 1) - i
        distance = (lines_to_end * 256) - delay_value
      end
      
      note_data[i] = {
        line = i,
        note = note_column.note_string,
        instrument = note_column.instrument_value,
        volume = note_column.volume_value,
        delay = delay_value,
        -- Determinge if this delay value is correct
        distance = distance
      }
    end
  end
  
  return note_data
end


-- evaluators.lua

local evaluators = {}
local vb = renoise.ViewBuilder()

function evaluators.evaluate_note_length(phrase)
  local note_data = {}
  local lines = phrase.number_of_lines
  
  for i = 1, lines do
    local line = phrase:line(i)
    local note_column = line:note_column(1)
    local note = note_column.note_string
    local instrument = note_column.instrument_value
    local delay_value = note_column.delay_value
    
    local distance = 0
    local found_next_note = false
    
    for j = i + 1, lines do
      local next_line = phrase:line(j)
      local next_note_column = next_line:note_column(1)
      
      if next_note_column.note_string ~= "---" then
        local lines_to_next_note = j - i
        local next_delay_value = next_note_column.delay_value
        distance = (lines_to_next_note * 256) - delay_value + next_delay_value
        found_next_note = true
        break
      end
    end
    
    -- If no next note was found, calculate distance to end of phrase
    if not found_next_note then
      local lines_to_end = (lines + 1) - i
      distance = (lines_to_end * 256) - delay_value
    end
    
    note_data[i] = {note, instrument, distance}
  end
  
  -- Calculate total phrase length in ticks
  local total_phrase_ticks = lines * 256
  
  local note_data_str = ""
  for k, v in pairs(note_data) do
    note_data_str = note_data_str .. string.format("Line %d: Note=%s, Instrument=%d, Distance=%d\n", k, v[1], v[2], v[3])
  end
  
  -- Add total phrase length information
  note_data_str = note_data_str .. string.format("\nTotal Phrase Length: %d ticks", total_phrase_ticks)
  
  local dialog_view = vb:column {
    vb:multiline_text {
      text = note_data_str,
      width = 400,
      height = 300
    }
  }
  
  renoise.app():show_custom_prompt("Note Data", dialog_view, {"OK"})
  
  return note_data
end

function evaluators.get_note_distances(phrase)
  local note_data = {}
  local lines = phrase.number_of_lines
  
  for i = 1, lines do
    local line = phrase:line(i)
    local note_column = line:note_column(1)
    
    -- Only store data for actual notes, not empty lines
    if note_column.note_string ~= "---" then
      local delay_value = note_column.delay_value
      
      local distance = 0
      local found_next_note = false
      
      for j = i + 1, lines do
        local next_line = phrase:line(j)
        local next_note_column = next_line:note_column(1)
        
        if next_note_column.note_string ~= "---" then
          local lines_to_next_note = j - i
          local next_delay_value = next_note_column.delay_value
          distance = (lines_to_next_note * 256) - delay_value + next_delay_value
          found_next_note = true
          break
        end
      end
      
      if not found_next_note then
        local lines_to_end = (lines + 1) - i
        distance = (lines_to_end * 256) - delay_value
      end
      
      note_data[i] = {
        line = i,
        note = note_column.note_string,
        instrument = note_column.instrument_value,
        volume = note_column.volume_value,
        delay = delay_value,
        distance = distance
      }
    end
  end
  
  return note_data
end

function evaluators.get_line_analysis(phrase)
  -- Initialize result table
  local analysis = {}
  local lines = phrase.number_of_lines
  
  -- First pass: collect all note data
  for i = 1, lines do
      local line = phrase:line(i)
      local note_column = line:note_column(1)
      
      analysis[i] = {
          note_value = note_column.note_value,
          instrument_value = note_column.instrument_value,
          delay_value = note_column.delay_value,
          distance = 0,  -- Will be calculated in second pass
          is_last = false -- Will be set in second pass
      }
  end
  
  -- Second pass: calculate distances and identify last note
  local last_note_index = nil
  
  -- Find the last actual note
  for i = lines, 1, -1 do
      if analysis[i].note_value ~= renoise.PatternLine.EMPTY_NOTE then
          last_note_index = i
          analysis[i].is_last = true
          break
      end
  end
  
  -- Calculate distances
  for i = 1, lines do
      if analysis[i].note_value ~= renoise.PatternLine.EMPTY_NOTE then
          local current_delay = analysis[i].delay_value
          local found_next = false
          
          -- Look for next note
          for j = i + 1, lines do
              if analysis[j].note_value ~= renoise.PatternLine.EMPTY_NOTE then
                  local lines_to_next = j - i
                  local next_delay = analysis[j].delay_value
                  analysis[i].distance = (lines_to_next * 256) - current_delay + next_delay
                  found_next = true
                  break
              end
          end
          
          -- If no next note found, calculate distance to imaginary note
          if not found_next then
              local lines_to_end = (lines + 1) - i
              analysis[i].distance = (lines_to_end * 256) - current_delay
          end
      end
  end
  
  -- Debug output to terminal
  print("\nPhrase Analysis Results:")
  print(string.format("Total Lines: %d", lines))
  print("Line-by-line analysis:")
  print(string.format("%-6s %-12s %-12s %-12s %-12s %-8s", 
      "Line", "Note", "Instrument", "Delay", "Distance", "Is Last"))
  print(string.rep("-", 70))
  
  for i = 1, lines do
      local entry = analysis[i]
      if entry.note_value ~= renoise.PatternLine.EMPTY_NOTE then
          print(string.format("%-6d %-12d %-12d %-12d %-12d %-8s",
              i,
              entry.note_value,
              entry.instrument_value,
              entry.delay_value,
              entry.distance,
              tostring(entry.is_last)
          ))
      end
  end
  print(string.rep("-", 70))
  
  return analysis
end

return evaluators
