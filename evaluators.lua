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
    for j = i + 1, lines do
      local next_line = phrase:line(j)
      local next_note_column = next_line:note_column(1)
      
      if next_note_column.note_string ~= "---" then
        local lines_to_next_note = j - i
        local next_delay_value = next_note_column.delay_value
        distance = (lines_to_next_note * 256) - delay_value + next_delay_value
        break
      end
    end
    
    note_data[i] = {note, instrument, distance}
  end
  
  local note_data_str = ""
  for k, v in pairs(note_data) do
    note_data_str = note_data_str .. string.format("Line %d: Note=%s, Instrument=%d, Distance=%d\n", k, v[1], v[2], v[3])
  end
  
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

return evaluators
