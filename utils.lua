local utils = {}
local vb = renoise.ViewBuilder()

function utils.get_current_instrument()
    local song = renoise.song()
    if labeler and labeler.is_locked and labeler.locked_instrument_index then
        return song:instrument(labeler.locked_instrument_index)
    end
    return song.selected_instrument
end


function utils.generate_curve(curveType, start, endValue, intervals)
    local result = {}
    local range = endValue - start
    print("INTERVALS")
    print(intervals)
    
    for i = 0, intervals - 1 do
        local t = i / (intervals - 1)
        local value
        
        if curveType == "linear" then
            value = start + t * range
        elseif curveType == "logarithmic" then
            value = start + math.log(1 + t) / math.log(2) * range
        elseif curveType == "exponential" then
            value = start + (math.exp(t) - 1) / (math.exp(1) - 1) * range
        elseif curveType == "upParabola" then
            value = start + 4 * range * (t - 0.5)^2
        elseif curveType == "downParabola" then
            value = endValue - 4 * range * (t - 0.5)^2
        elseif curveType == "upCycloid" then
            if t < 0.5 then
                value = start + (1 - math.cos(t * math.pi)) * range / 2
            else
                value = endValue - (1 - math.cos((t - 0.5) * math.pi)) * range / 2
            end
        elseif curveType == "downCycloid" then
            if t < 0.5 then
                value = start + math.sin(t * math.pi) * range / 2
            else
                value = endValue - math.sin((t - 0.5) * math.pi) * range / 2
            end
        else
            error("Invalid curve type")
        end
        
        table.insert(result, math.floor(value + 0.5))
    end
    
    return result
end


function utils.augment_phrase(augmentation, phrase)
    local fx_column = 1
    local start_value = 0x10  -- Start at 16 (hexadecimal)
    local increment = 0x10    -- Increment by 16 (hexadecimal)

    if augmentation == "Upshift" or augmentation == "Downshift" or augmentation == "Stretch" then
        local flag = (augmentation == "Upshift" and "0U") or (augmentation == "Downshift" and "0D") or "0S"
        local value = start_value
        local first_note_found = false
        for i = 1, phrase.number_of_lines do
            local line = phrase:line(i)
            if line.note_columns[1].note_value ~= renoise.PatternLine.EMPTY_NOTE then
                if first_note_found then
                    line.effect_columns[fx_column].number_string = flag
                    line.effect_columns[fx_column].amount_string = string.format("%02X", value)
                    value = value + increment
                    if value > 0xFF then value = 0xFF end  -- Cap at FF (255)
                else
                    first_note_found = true
                end
            end
        end
    elseif augmentation == "Staccato" then
        local i = 1
        while i <= phrase.number_of_lines do
            local line = phrase:line(i)
            if line.note_columns[1].note_value ~= renoise.PatternLine.EMPTY_NOTE then
                local next_line = phrase:line(i + 1)
                if next_line then
                    next_line.note_columns[1].note_string = "OFF"
                    i = i + 2  
                else
                    break  
                end
            else
                i = i + 1 
            end
        end
    elseif augmentation == "Backwards" then
        for i = 1, phrase.number_of_lines do
            local line = phrase:line(i)
            if line.note_columns[1].note_value ~= renoise.PatternLine.EMPTY_NOTE then
                line.effect_columns[fx_column].number_string = "0B"
                line.effect_columns[fx_column].amount_string = "00"
            end
        end
    elseif augmentation == "Reversal" then
        local reverse_flag = true
        for i = 1, phrase.number_of_lines do
            local line = phrase:line(i)
            if line.note_columns[1].note_value ~= renoise.PatternLine.EMPTY_NOTE then
                line.effect_columns[fx_column].number_string = "0B"
                line.effect_columns[fx_column].amount_string = reverse_flag and "00" or "01"
                reverse_flag = not reverse_flag
            end
        end
    end
end

function utils.multiply_phrase_length(phrase, length)
    if not phrase then
        print("Invalid phrase provided")
        return nil
    end

    local current_lines = phrase.number_of_lines
    local new_lines = current_lines * length

    print("Current lines: " .. current_lines)
    print("New lines: " .. new_lines)


    phrase.number_of_lines = new_lines
    print("Phrase resized to: " .. phrase.number_of_lines .. " lines")

    for i = current_lines + 1, new_lines do
        local source_line = phrase:line((i - 1) % current_lines + 1)
        local dest_line = phrase:line(i)
        dest_line:copy_from(source_line)
    end

    print("Content duplicated to fill new length")

    return phrase
end

function utils.clear_phrase(phrase)
    for _, line in ipairs(phrase.lines) do
        for _, note_column in ipairs(line.note_columns) do note_column:clear() end
        for _, effect_column in ipairs(line.effect_columns) do effect_column:clear() end
    end
end

function utils.get_slices_by_label(saved_labels, target_label)
    local slices = {roll = {}, ghost = {}, shuffle = {}}
    for hex_key, label_data in pairs(saved_labels) do
        if label_data.label == target_label then
            local index = tonumber(hex_key, 16) - 1
            if label_data.roll then
                table.insert(slices.roll, index)
            end
            if label_data.ghost_note then
                table.insert(slices.ghost, index)
            end
            if label_data.shuffle then 
                table.insert(slices.shuffle, index)
            end
        end
    end
    return slices
end

return utils