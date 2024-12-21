-- duplicator.lua

local duplicator = {}

function duplicator.duplicate_phrases(instrument, first_phrase, num_copies)
    local phrases = instrument.phrases
    local new_phrases = {}

    for i = 1, num_copies do
        local new_phrase = instrument:insert_phrase_at(#phrases + 1)
        new_phrase:copy_from(first_phrase)
        table.insert(new_phrases, new_phrase)
    end

    return new_phrases
end

function duplicator.duplicate_for_permutations(instrument, source_phrase, num_permutations)
    local new_phrases = {}
    for i = 1, num_permutations do
      local new_phrase_index = #instrument.phrases + 1
      local new_phrase = instrument:insert_phrase_at(new_phrase_index)
      new_phrase:copy_from(source_phrase)
      new_phrase.name = string.format("%s Slt %d", source_phrase.name, i)
      table.insert(new_phrases, {phrase = new_phrase, index = new_phrase_index})
    end
    return new_phrases
  end

function duplicator.duplicate_instrument(label, division)
  local song = renoise.song()
  local current_instrument_index = song.selected_instrument_index
  local current_instrument = song.instruments[current_instrument_index]
  
  local new_instrument = song:insert_instrument_at(current_instrument_index + 1)
  
  new_instrument:copy_from(current_instrument)

  if division > 0 then
    new_instrument.name = string.format("%s-1/%d", label, division)
  else
    new_instrument.name = string.format(label)
  end
  
  while #new_instrument.phrases > 1 do
    new_instrument:delete_phrase_at(#new_instrument.phrases)
  end
  
  song.selected_instrument_index = current_instrument_index + 1
  
  return new_instrument
end

function duplicator.deep_copy(original)
  local orig_type = type(original)
  local copy
  if orig_type == 'table' then
      copy = {}
      for orig_key, orig_value in next, original, nil do
          copy[duplicator.deep_copy(orig_key)] = duplicator.deep_copy(orig_value)
      end
      setmetatable(copy, duplicator.deep_copy(getmetatable(original)))
  else
      copy = original
  end
  return copy
end

  
return duplicator