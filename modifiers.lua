local modifiers = {}
local vb = renoise.ViewBuilder()
local duplicator = require("duplicator")

local function copy_line(source_line, target_line)
  for note_column_index = 1, 12 do
    local source_note_column = source_line:note_column(note_column_index)
    local target_note_column = target_line:note_column(note_column_index)
    target_note_column:copy_from(source_note_column)
  end
  
  for effect_column_index = 1, 8 do
    local source_effect_column = source_line:effect_column(effect_column_index)
    local target_effect_column = target_line:effect_column(effect_column_index)
    target_effect_column:copy_from(source_effect_column)
  end
end

function modifiers.modify_phrase_by_halves(new_phrase, start_quarter, end_quarter)
  local length = new_phrase.number_of_lines
  local quarter_length = math.ceil(length / 4)
  
  for line = 1, quarter_length * 2 do
    local source_line = new_phrase:line(line + (start_quarter - 1) * quarter_length)
    local target_line = new_phrase:line(line)
    copy_line(source_line, target_line)
  end
  
  new_phrase.number_of_lines = quarter_length * 2
end

function modifiers.modify_phrase_by_section(new_phrase, section, divisor)
  local length = new_phrase.number_of_lines
  local section_length = math.ceil(length / divisor)
  
  for line = 1, section_length do
    local source_line = new_phrase:line(line + (section - 1) * section_length)
    local target_line = new_phrase:line(line)
    copy_line(source_line, target_line)
  end
  
  new_phrase.number_of_lines = section_length
end

function modifiers.get_cycle_indices(saved_labels)
  local cycle_indices = {}
  
  for hex_key, label_data in pairs(saved_labels) do
    if label_data.cycle then
      local index = tonumber(hex_key, 16) - 1
      table.insert(cycle_indices, index)
    end
  end
  
  table.sort(cycle_indices)
  print("Cycle indices:", table.concat(cycle_indices, ", "))
  return cycle_indices
end

local function factorial(n)
  if n == 0 then return 1 end
  local result = 1
  for i = 2, n do
    result = result * i
  end
  return result
end

function modifiers.collect_cyclable_slices(original_phrase, cycle_indices)
  local cyclable_slices = {}
  for line_index, line in ipairs(original_phrase.lines) do
    for note_column_index, note_column in ipairs(line.note_columns) do
      if table.contains(cycle_indices, note_column.instrument_value) then
        table.insert(cyclable_slices, {
          note = note_column.note_value,
          instrument = note_column.instrument_value,
        })
      end
    end
  end
  print("Collected cyclable slices:", #cyclable_slices)
  return cyclable_slices
end

function modifiers.calculate_permutations(copied_phrase, cycle_indices)
  local slots = 0
  local cyclable_notes = #cycle_indices

  for _, line in ipairs(copied_phrase.lines) do
    for _, note_column in ipairs(line.note_columns) do
      local instrument_value = note_column.instrument_value
      if instrument_value ~= 255 and table.contains(cycle_indices, instrument_value) then
        slots = slots + 1
      end
    end
  end

  local permutations = 0
  if cyclable_notes >= slots then
    permutations = math.floor(factorial(cyclable_notes) / factorial(cyclable_notes - slots))
  end

  print("Calculated permutations:", permutations)
  return permutations, slots, cyclable_notes
end

function modifiers.substitute_cyclable_slices(new_phrases, cycle_indices, cyclable_slices)
  print("Entering substitute_cyclable_slices function")
  
  for perm_index, phrase_entry in ipairs(new_phrases) do
    local new_phrase = phrase_entry.phrase
    print(string.format("Processing permutation %d, Phrase name: %s", perm_index, new_phrase.name))
    
    local cyclable_index = 1
    
    for line_index, line in ipairs(new_phrase.lines) do
      for note_column_index, note_column in ipairs(line.note_columns) do
        if table.contains(cycle_indices, note_column.instrument_value) then
          local cyclable_slice = cyclable_slices[cyclable_index]
          
          print(string.format("Substituting slice: Old (Note=%d, Instrument=%d) -> New (Note=%d, Instrument=%d)",
            note_column.note_value, note_column.instrument_value,
            cyclable_slice.note, cyclable_slice.instrument))
          
          note_column.note_value = cyclable_slice.note
          note_column.instrument_value = cyclable_slice.instrument
          
          cyclable_index = (cyclable_index % #cyclable_slices) + 1
        end
      end
    end
    
    table.insert(cyclable_slices, table.remove(cyclable_slices, 1))
    new_phrase.name = string.format("%s Perm %d", new_phrase.name, perm_index)
    print("Updated phrase name:", new_phrase.name)
  end
  
  print("Exiting substitute_cyclable_slices function")
end

local function generate_permutations(items, slot_count)
  if slot_count == 1 then
      local result = {}
      for _, item in ipairs(items) do
          table.insert(result, {item})
      end
      return result
  end

  local result = {}
  local function permute(arr, start)
      if start > slot_count then
          local perm = {}
          for i = 1, slot_count do perm[i] = arr[i] end
          table.insert(result, perm)
      else
          for i = start, #arr do
              arr[start], arr[i] = arr[i], arr[start]
              permute(arr, start + 1)
              arr[start], arr[i] = arr[i], arr[start]
          end
      end
  end
  permute(items, 1)
  return result
end

function modifiers.apply_cyclable_permutations(new_phrases, original_phrase, cycle_indices)
  print("Entering apply_cyclable_permutations function")

  local cyclable_notes = modifiers.collect_cyclable_slices(original_phrase, cycle_indices)
  print("Number of cyclable notes found:", #cyclable_notes)

  local slot_count = 0
  for _, line in ipairs(new_phrases[1].phrase.lines) do
      for _, note_column in ipairs(line.note_columns) do
          if table.contains(cycle_indices, note_column.instrument_value) then
              slot_count = slot_count + 1
          end
      end
  end
  print("Number of cyclable slots in source copied phrase:", slot_count)

  local permutations = generate_permutations(cyclable_notes, slot_count)
  print("Total permutations generated:", #permutations)

  local current_instrument = renoise.song().selected_instrument
  local start_index = #current_instrument.phrases - #new_phrases + 1

  for i, phrase_entry in ipairs(new_phrases) do
      local new_phrase = phrase_entry.phrase
      local permutation = permutations[(i - 1) % #permutations + 1]
      print(string.format("Applying permutation %d, Phrase name: %s", i, new_phrase.name))

      local is_duplicate = true
      local perm_index = 1

      for line_index, line in ipairs(new_phrase.lines) do
          for note_column_index, note_column in ipairs(line.note_columns) do
              if table.contains(cycle_indices, note_column.instrument_value) then
                  local new_instrument = permutation[perm_index].instrument

                  print(string.format("Replacing note at line %d, column %d: Old (Note=%d, Instrument=%d) -> New (Note=%d, Instrument=%d)",
                      line_index, note_column_index,
                      note_column.note_value, note_column.instrument_value,
                      note_column.note_value, new_instrument))

                  if note_column.instrument_value ~= new_instrument then
                      is_duplicate = false
                  end

                  note_column.instrument_value = new_instrument
                  perm_index = perm_index % slot_count + 1
              end
          end
      end

      if is_duplicate then
          print(string.format("Duplicate phrase detected: %s. Deleting.", new_phrase.name))
          current_instrument:delete_phrase_at(start_index + i - 1)
      else
          new_phrase.name = string.format("%s Perm %d", new_phrase.name, i)
          print("Updated phrase name:", new_phrase.name)
      end
  end

  print("Exiting apply_cyclable_permutations function")
end

function modifiers.modify_phrases_by_labels(copied_phrase, original_phrase, saved_labels)
  local info = "Modifying phrase with labels...\n\n"
  
  info = info .. "Copied Phrase:\n"
  info = info .. string.format("  Number of lines: %d\n", copied_phrase.number_of_lines)
  info = info .. string.format("  Name: %s\n\n", copied_phrase.name)
  
  info = info .. "Original Phrase:\n"
  info = info .. string.format("  Number of lines: %d\n", original_phrase.number_of_lines)
  info = info .. string.format("  Name: %s\n\n", original_phrase.name)
  
  info = info .. "Saved Labels:\n"
  for k, v in pairs(saved_labels) do
    info = info .. string.format("  %s: Label=%s, Ghost Note=%s, Cycle=%s\n", 
                                 k, v.label, tostring(v.ghost_note), tostring(v.cycle))
  end

  local cycle_indices = modifiers.get_cycle_indices(saved_labels)
  
  local total_permutations, slots, cyclable_notes = modifiers.calculate_permutations(copied_phrase, cycle_indices)
  
  local instrument = renoise.song().selected_instrument
  local new_phrases = duplicator.duplicate_for_permutations(instrument, copied_phrase, total_permutations)
  
  modifiers.apply_cyclable_permutations(new_phrases, original_phrase, cycle_indices)
  
  info = info .. "\nSlices to be cycled:\n"
  for _, index in ipairs(cycle_indices) do
    info = info .. string.format("  Slice %d\n", index)
  end
  
  info = info .. string.format("\nNumber of cyclable notes: %d", cyclable_notes)
  info = info .. string.format("\nNumber of slots: %d", slots)
  info = info .. string.format("\nTotal number of permutations: %d\n", total_permutations)
  
  for _, entry in ipairs(new_phrases) do
    local new_phrase = entry.phrase
    local index = entry.index
    info = info .. string.format("\nCreated new phrase: %s - Index: %d", new_phrase.name, index)
  end
  
  local dialog_content = vb:column {
    margin = 10,
    vb:text {
      text = "Phrase Modification and Permutation Information"
    },
    vb:multiline_textfield {
      text = info,
      width = 400,
      height = 300,
      font = "mono"
    }
  }
  
end

function table.contains(table, element)
  for _, value in pairs(table) do
    if value == element then
      return true
    end
  end
  return false
end

return modifiers