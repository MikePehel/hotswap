-- labeler.lua
-- BreakFast-compatible labeler module for HotSwap
-- Data structure aligned with BreakFast labeler format
-- Features: SRC display, Slice preview, Advanced Data

local labeler = {}
local json = require("json")

local dialog = nil
labeler.dialog_closed_callback = nil

local show_dialog = nil

function labeler.set_show_dialog_callback(callback)
    show_dialog = callback
end

-- Core state variables
labeler.locked_instrument_index = nil
labeler.is_locked = false
labeler.saved_labels = {}
labeler.saved_labels_by_instrument = {}
labeler.saved_labels_observable = renoise.Document.ObservableBoolean(false)
labeler.lock_state_observable = renoise.Document.ObservableBoolean(false)
labeler.show_label2 = false
labeler.show_advanced_data = false

-- BreakFast-compatible location options
labeler.location_options = {"Off-Center", "Center", "Edge", "Rim", "Alt"}

-- Label options (matching BreakFast builtin labels)
labeler.label_options = {
    "---------", "Kick", "Snare", "Hi Hat Closed", "Hi Hat Open", 
    "Crash", "Tom", "Ride", "Shaker", "Tambourine", "Cowbell"
}

--------------------------------------------------------------------------------
-- Slice Preview State (Phase 6 feature from BreakFast)
--------------------------------------------------------------------------------

local slice_preview_state = {
    is_playing = false,
    current_note = nil,
    current_instrument = nil,
    current_button_id = nil,
    dialog_vb = nil,
    auto_stop_time = nil
}

-- Auto-stop timer handle
local preview_timer_active = false

local function stop_preview_timer()
    if preview_timer_active then
        if renoise.tool():has_timer(labeler.auto_stop_preview) then
            renoise.tool():remove_timer(labeler.auto_stop_preview)
        end
        preview_timer_active = false
    end
end

function labeler.auto_stop_preview()
    if slice_preview_state.is_playing then
        labeler.stop_slice_preview()
    end
    stop_preview_timer()
end

function labeler.start_slice_preview(instrument_index, note_value, button_id, dialog_vb)
    local song = renoise.song()
    
    -- Stop any existing preview
    if slice_preview_state.is_playing then
        labeler.stop_slice_preview()
    end
    
    -- Start new preview
    slice_preview_state.is_playing = true
    slice_preview_state.current_note = note_value
    slice_preview_state.current_instrument = instrument_index
    slice_preview_state.current_button_id = button_id
    slice_preview_state.dialog_vb = dialog_vb
    
    -- Trigger note on (using track 1, velocity 1.0 = full volume)
    -- Note: velocity is 0.0 to 1.0, not 0-127
    local track_index = 1
    song:trigger_instrument_note_on(instrument_index, track_index, note_value, 1.0)
    
    -- Update button to show stop symbol
    if dialog_vb and dialog_vb.views[button_id] then
        dialog_vb.views[button_id].text = "[]"
    end
    
    -- Start auto-stop timer (2 seconds)
    stop_preview_timer()
    preview_timer_active = true
    renoise.tool():add_timer(labeler.auto_stop_preview, 2000)
end

function labeler.stop_slice_preview()
    if not slice_preview_state.is_playing then
        return
    end
    
    local song = renoise.song()
    
    -- Trigger note off
    if slice_preview_state.current_instrument and slice_preview_state.current_note then
        local track_index = 1
        song:trigger_instrument_note_off(
            slice_preview_state.current_instrument, 
            track_index, 
            slice_preview_state.current_note
        )
    end
    
    -- Update button to show play symbol
    if slice_preview_state.dialog_vb and slice_preview_state.current_button_id then
        local button = slice_preview_state.dialog_vb.views[slice_preview_state.current_button_id]
        if button then
            button.text = ">"
        end
    end
    
    -- Reset state
    slice_preview_state.is_playing = false
    slice_preview_state.current_note = nil
    slice_preview_state.current_instrument = nil
    slice_preview_state.current_button_id = nil
    
    -- Stop timer
    stop_preview_timer()
end

function labeler.toggle_slice_preview(instrument_index, note_value, button_id, dialog_vb)
    -- If same slice is playing, stop it
    if slice_preview_state.is_playing and 
       slice_preview_state.current_instrument == instrument_index and
       slice_preview_state.current_note == note_value then
        labeler.stop_slice_preview()
    else
        -- Start new preview (will stop any existing)
        labeler.start_slice_preview(instrument_index, note_value, button_id, dialog_vb)
    end
end

function labeler.is_slice_previewing()
    return slice_preview_state.is_playing
end

function labeler.is_previewing_slice(instrument_index, note_value)
    return slice_preview_state.is_playing and
           slice_preview_state.current_instrument == instrument_index and
           slice_preview_state.current_note == note_value
end

--------------------------------------------------------------------------------
-- Core Functions
--------------------------------------------------------------------------------

function labeler.update_lock()
    if dialog and dialog.visible then
        dialog:close()
        labeler.create_ui()
    end
end

function labeler.store_labels_for_instrument(instrument_index, labels)
    local copied_labels = table.copy(labels)
    copied_labels.show_label2 = labeler.show_label2
    copied_labels.show_advanced_data = labeler.show_advanced_data
    
    -- Preserve existing mappings if they exist
    local existing_data = labeler.saved_labels_by_instrument[instrument_index] or {}
    local existing_mappings = existing_data.mappings or {}
    
    labeler.saved_labels_by_instrument[instrument_index] = {
        labels = copied_labels,
        mappings = existing_mappings,
        show_label2 = labeler.show_label2,
        show_advanced_data = labeler.show_advanced_data
    }
    labeler.saved_labels = labels
end

function labeler.count_breakpoints(labels)
    local count = 0
    for _, data in pairs(labels) do
        if data.breakpoint then 
            count = count + 1 
        end
    end
    return count
end

function labeler.get_labels_for_instrument(instrument_index)
    local stored_data = labeler.saved_labels_by_instrument[instrument_index] or {}
    return stored_data.labels or stored_data or {}
end

function labeler.get_mappings_for_instrument(instrument_index)
    local stored_data = labeler.saved_labels_by_instrument[instrument_index] or {}
    return stored_data.mappings or {}
end

local function calculate_scale_factor(num_slices)
    local base_slices = 16 
    return math.max(0.5, math.min(1, base_slices / num_slices))
end

--------------------------------------------------------------------------------
-- Note to String Conversion
--------------------------------------------------------------------------------

local function note_value_to_string(note_value)
    local note_names = {"C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"}
    local octave = math.floor(note_value / 12) - 1
    local note_index = (note_value % 12) + 1
    return note_names[note_index] .. octave
end

--------------------------------------------------------------------------------
-- CSV Helper Functions
--------------------------------------------------------------------------------

local function escape_csv_field(field)
    if type(field) == "string" and (field:find(',') or field:find('"')) then
        return '"' .. field:gsub('"', '""') .. '"'
    end
    return tostring(field)
end

local function unescape_csv_field(field)
    if field:sub(1,1) == '"' and field:sub(-1) == '"' then
        return field:sub(2, -2):gsub('""', '"')
    end
    return field
end

local function parse_csv_line(line)
    local fields = {}
    local field = ""
    local in_quotes = false
    
    local i = 1
    while i <= #line do
        local char = line:sub(i,i)
        
        if char == '"' then
            if in_quotes and line:sub(i+1,i+1) == '"' then
                field = field .. '"'
                i = i + 2
            else
                in_quotes = not in_quotes
                i = i + 1
            end
        elseif char == ',' and not in_quotes then
            table.insert(fields, field)
            field = ""
            i = i + 1
        else
            field = field .. char
            i = i + 1
        end
    end
    
    table.insert(fields, field)
    return fields
end

local function get_current_sample_name()
    local song = renoise.song()
    local instrument = song.selected_instrument
    if instrument and #instrument.samples > 0 then
        local name = instrument.samples[1].name:gsub("[%c%p%s]", "_")
        return name
    end
    return "default"
end

--------------------------------------------------------------------------------
-- CSV Export (BreakFast-compatible format)
--------------------------------------------------------------------------------

function labeler.export_labels()
    local filename = get_current_sample_name() .. "_labels.csv"
    local filepath = renoise.app():prompt_for_filename_to_write("csv", "Export Labels")
    
    if not filepath or filepath == "" then return end
    
    if not filepath:lower():match("%.csv$") then
        filepath = filepath .. ".csv"
    end
    
    local file, err = io.open(filepath, "w")
    if not file then
        renoise.app():show_error("Unable to open file for writing: " .. tostring(err))
        return
    end
    
    -- Breakfast-compatible header
    file:write("Index,Label,Label 2,Breakpoint,Location,Cycle,Ghost,Counterstroke,[Ref]Instrument,[Ref]SliceNote\n")

    -- Sort keys for consistent output
    local sorted_keys = {}
    for hex_key in pairs(labeler.saved_labels) do
        table.insert(sorted_keys, hex_key)
    end
    table.sort(sorted_keys)

    for _, hex_key in ipairs(sorted_keys) do
        local data = labeler.saved_labels[hex_key]
        local instrument_0based = (data.instrument_index or 1) - 1
        if instrument_0based < 0 then instrument_0based = 0 end
        local slice_note = 36 + tonumber(hex_key, 16)
        local values = {
            hex_key,
            escape_csv_field(data.label or "---------"),
            escape_csv_field(data.label2 or "---------"),
            tostring(data.breakpoint or false),
            escape_csv_field(data.location or "Off-Center"),
            tostring(data.cycle or false),
            tostring(data.ghost or false),
            tostring(data.counterstroke or false),
            tostring(instrument_0based),
            tostring(slice_note)
        }

        file:write(table.concat(values, ",") .. "\n")
    end
    
    file:close()
    renoise.app():show_status("Labels exported to " .. filepath)
end

--------------------------------------------------------------------------------
-- JSON Export (Full BreakFast Alphabet format)
--------------------------------------------------------------------------------

function labeler.export_labels_json()
    local filename = get_current_sample_name() .. "_labels.json"
    local filepath = renoise.app():prompt_for_filename_to_write("json", "Export Labels (JSON)")
    
    if not filepath or filepath == "" then return end
    
    if not filepath:lower():match("%.json$") then
        filepath = filepath .. ".json"
    end
    
    local export_data = {
        version = "2.0",
        saved_labels = {}
    }
    
    for hex_key, data in pairs(labeler.saved_labels) do
        export_data.saved_labels[hex_key] = {
            label = data.label,
            label2 = data.label2,
            breakpoint = data.breakpoint,
            instrument_index = data.instrument_index,
            note_value = data.note_value,
            is_slice = data.is_slice ~= false,
            location = data.location or "Off-Center",
            ghost = data.ghost or false,
            counterstroke = data.counterstroke or false,
            cycle = data.cycle or false
        }
    end
    
    local file, err = io.open(filepath, "w")
    if not file then
        renoise.app():show_error("Unable to open file for writing: " .. tostring(err))
        return
    end
    
    local json_str = json.encode(export_data)
    file:write(json_str)
    file:close()
    
    renoise.app():show_status("Labels exported to " .. filepath)
end

--------------------------------------------------------------------------------
-- Import (Auto-detect CSV or JSON)
--------------------------------------------------------------------------------

function labeler.import_labels()
    -- Reset lock state before import
    labeler.is_locked = false
    labeler.locked_instrument_index = nil
    
    local filepath = renoise.app():prompt_for_filename_to_read({"*.csv", "*.json"}, "Import Labels")
    
    if not filepath or filepath == "" then return end
    
    if filepath:lower():match("%.json$") then
        labeler.import_labels_json(filepath)
    else
        labeler.import_labels_csv(filepath)
    end
end

function labeler.import_labels_json(filepath)
    local file, err = io.open(filepath, "r")
    if not file then
        renoise.app():show_error("Unable to open file: " .. tostring(err))
        return
    end
    
    local content = file:read("*all")
    file:close()
    
    local success, data = pcall(json.decode, content)
    if not success or not data then
        renoise.app():show_error("Invalid JSON format")
        return
    end
    
    if not data.saved_labels then
        renoise.app():show_error("Invalid label file format: missing saved_labels")
        return
    end
    
    local new_labels = {}
    for hex_key, label_data in pairs(data.saved_labels) do
        new_labels[hex_key] = {
            label = label_data.label or "---------",
            label2 = label_data.label2,
            breakpoint = label_data.breakpoint or false,
            instrument_index = label_data.instrument_index or 0,
            note_value = label_data.note_value or 0,
            is_slice = label_data.is_slice ~= false,
            location = label_data.location or "Off-Center",
            ghost = label_data.ghost or false,
            counterstroke = label_data.counterstroke or false,
            cycle = label_data.cycle or false
        }
    end
    
    -- Update state
    local current_index = renoise.song().selected_instrument_index
    labeler.saved_labels = new_labels
    labeler.saved_labels_by_instrument[current_index] = {
        labels = table.copy(new_labels),
        mappings = (labeler.saved_labels_by_instrument[current_index] or {}).mappings or {}
    }
    
    labeler.locked_instrument_index = current_index
    labeler.is_locked = true
    
    labeler.saved_labels_observable.value = not labeler.saved_labels_observable.value
    labeler.lock_state_observable.value = not labeler.lock_state_observable.value
    
    renoise.app():show_status("Labels imported from " .. filepath)
    
    if dialog and dialog.visible then
        dialog:close()
        labeler.create_ui()
    end
end

function labeler.import_labels_csv(filepath)
    local file, err = io.open(filepath, "r")
    if not file then
        renoise.app():show_error("Unable to open file: " .. tostring(err))
        return
    end
    
    local header = file:read()
    if not header or not header:lower():match("index") then
        renoise.app():show_error("Invalid CSV format: Missing or incorrect header")
        file:close()
        return
    end

    -- Build column index map from header (header-based detection)
    local header_fields = parse_csv_line(header)
    local col = {}
    for i, name in ipairs(header_fields) do
        local n = name:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if n == "index" then col.index = i
        elseif n == "label" then col.label = i
        elseif n == "label 2" or n == "label2" then col.label2 = i
        elseif n == "breakpoint" then col.breakpoint = i
        elseif n == "location" then col.location = i
        elseif n == "cycle" then col.cycle = i
        elseif n == "ghost" then col.ghost = i
        elseif n == "counterstroke" then col.counterstroke = i
        elseif n == "instrumentindex" or n == "[ref]instrument" then col.instrument = i
        elseif n == "notevalue" or n == "[ref]slicenote" then col.note_value = i
        elseif n == "isslice" then col.is_slice = i
        end
    end

    if not col.index then
        renoise.app():show_error("Invalid CSV format: Missing 'Index' column")
        file:close()
        return
    end

    local new_labels = {}
    local line_number = 1

    local function str_to_bool(str)
        return str and str:lower() == "true"
    end

    for line in file:lines() do
        line_number = line_number + 1
        local fields = parse_csv_line(line)

        local index = fields[col.index]
        if not index or not index:match("^%x%x$") then
            renoise.app():show_error(string.format(
                "Invalid index format at line %d: %s",
                line_number, tostring(index)))
            file:close()
            return
        end

        local label = col.label and unescape_csv_field(fields[col.label] or "---------") or "---------"
        local label2 = col.label2 and unescape_csv_field(fields[col.label2] or "---------") or "---------"
        local breakpoint = col.breakpoint and str_to_bool(fields[col.breakpoint]) or false
        local location = col.location and unescape_csv_field(fields[col.location] or "Off-Center") or "Off-Center"
        local cycle = col.cycle and str_to_bool(fields[col.cycle]) or false
        local ghost = col.ghost and str_to_bool(fields[col.ghost]) or false
        local counterstroke = col.counterstroke and str_to_bool(fields[col.counterstroke]) or false

        -- Instrument index: stored internally as 1-based; old HotSwap exported 1-based,
        -- Breakfast exports 0-based. Detect by column name.
        local instrument_index = 0
        if col.instrument then
            local raw = tonumber(fields[col.instrument]) or 0
            -- If the header was "[Ref]Instrument" (Breakfast, 0-based), convert to 1-based
            local hdr_name = header_fields[col.instrument]:lower():gsub("^%s+", ""):gsub("%s+$", "")
            if hdr_name == "[ref]instrument" then
                instrument_index = raw + 1
            else
                instrument_index = raw
            end
        end

        local note_value
        if col.note_value then
            note_value = tonumber(fields[col.note_value]) or (36 + tonumber(index, 16))
        else
            note_value = 36 + tonumber(index, 16)
        end

        local is_slice
        if col.is_slice then
            is_slice = str_to_bool(fields[col.is_slice])
        else
            is_slice = true
        end

        new_labels[index] = {
            label = label,
            label2 = label2,
            breakpoint = breakpoint,
            instrument_index = instrument_index,
            note_value = note_value,
            is_slice = is_slice,
            location = location,
            ghost = ghost,
            counterstroke = counterstroke,
            cycle = cycle
        }
    end
    
    file:close()
    
    -- Update state
    local current_index = renoise.song().selected_instrument_index
    labeler.saved_labels = new_labels
    labeler.saved_labels_by_instrument[current_index] = {
        labels = table.copy(new_labels),
        mappings = (labeler.saved_labels_by_instrument[current_index] or {}).mappings or {}
    }
    
    labeler.locked_instrument_index = current_index
    labeler.is_locked = true
    
    labeler.saved_labels_observable.value = not labeler.saved_labels_observable.value
    labeler.lock_state_observable.value = not labeler.lock_state_observable.value
    
    renoise.app():show_status("Labels imported from " .. filepath)
    
    if dialog and dialog.visible then
        dialog:close()
        labeler.create_ui()
    end
end

--------------------------------------------------------------------------------
-- Mappings Export/Import
--------------------------------------------------------------------------------

function labeler.export_mappings()
    local song = renoise.song()
    local current_index = labeler.is_locked and labeler.locked_instrument_index 
                        or song.selected_instrument_index
    local stored_data = labeler.saved_labels_by_instrument[current_index] or {}
    local mappings = stored_data.mappings or {}
    
    if not next(mappings) then
        renoise.app():show_warning("No mappings to export.")
        return
    end
    
    local filename = get_current_sample_name() .. "_mappings.csv"
    local filepath = renoise.app():prompt_for_filename_to_write("csv", "Export Mappings")
    
    if not filepath or filepath == "" then return end
    
    if not filepath:lower():match("%.csv$") then
        filepath = filepath .. ".csv"
    end
    
    local file, err = io.open(filepath, "w")
    if not file then
        renoise.app():show_error("Unable to open file for writing: " .. tostring(err))
        return
    end
    
    -- New header with location and sample_key support
    file:write("Label,Location,Type,Track,Instrument,SampleKey\n")
    
    for label, location_mappings in pairs(mappings) do
        if type(location_mappings) == "table" then
            for location, type_mappings in pairs(location_mappings) do
                if type(type_mappings) == "table" then
                    for type_key, mapping_list in pairs(type_mappings) do
                        if type(mapping_list) == "table" then
                            for _, mapping in ipairs(mapping_list) do
                                file:write(string.format("%s,%s,%s,%d,%d,%s\n", 
                                    escape_csv_field(label),
                                    escape_csv_field(location),
                                    type_key,
                                    mapping.track_index or 1,
                                    mapping.instrument_index or 0,
                                    tostring(mapping.sample_key or "")))
                            end
                        end
                    end
                end
            end
        end
    end
    
    file:close()
    renoise.app():show_status("Mappings exported to " .. filepath)
end

function labeler.import_mappings()
    local filepath = renoise.app():prompt_for_filename_to_read({"*.csv"}, "Import Mappings")
    
    if not filepath or filepath == "" then return end
    
    local file, err = io.open(filepath, "r")
    if not file then
        renoise.app():show_error("Unable to open file: " .. tostring(err))
        return
    end
    
    local header = file:read()
    if not header then
        renoise.app():show_error("Invalid mapping CSV format: empty file")
        file:close()
        return
    end
    
    local header_lower = header:lower()
    local is_new_format = header_lower:match("location")
    
    local new_mappings = {}
    local line_number = 1
    
    -- Location options for initializing structure
    local location_options = {"Off-Center", "Center", "Edge", "Rim", "Alt"}
    local type_keys = {"regular", "ghost", "counterstroke", "ghost_counterstroke"}
    
    -- Helper to ensure full mapping structure exists
    local function ensure_structure(label)
        if not new_mappings[label] then
            new_mappings[label] = {}
            for _, loc in ipairs(location_options) do
                new_mappings[label][loc] = {}
                for _, tk in ipairs(type_keys) do
                    new_mappings[label][loc][tk] = {}
                end
            end
        end
    end
    
    for line in file:lines() do
        line_number = line_number + 1
        local fields = parse_csv_line(line)
        
        if is_new_format then
            -- New format: Label,Location,Type,Track,Instrument,SampleKey
            if #fields < 5 then
                renoise.app():show_error(string.format("Invalid CSV format at line %d", line_number))
                file:close()
                return
            end
            
            local label = unescape_csv_field(fields[1])
            local location = unescape_csv_field(fields[2])
            local type_key = fields[3]
            local track_index = tonumber(fields[4])
            local instrument_index = tonumber(fields[5])
            local sample_key = fields[6] and fields[6] ~= "" and tonumber(fields[6]) or nil
            
            ensure_structure(label)
            
            -- Ensure location exists
            if not new_mappings[label][location] then
                new_mappings[label][location] = {}
                for _, tk in ipairs(type_keys) do
                    new_mappings[label][location][tk] = {}
                end
            end
            
            -- Ensure type exists
            if not new_mappings[label][location][type_key] then
                new_mappings[label][location][type_key] = {}
            end
            
            table.insert(new_mappings[label][location][type_key], {
                track_index = track_index,
                instrument_index = instrument_index,
                sample_key = sample_key,
                committed = true
            })
        else
            -- Legacy format: Label,Type,Track,Instrument
            if #fields < 4 then
                renoise.app():show_error(string.format("Invalid CSV format at line %d", line_number))
                file:close()
                return
            end
            
            local label = unescape_csv_field(fields[1])
            local mapping_type = fields[2]
            local track_index = tonumber(fields[3])
            local instrument_index = tonumber(fields[4])
            
            ensure_structure(label)
            
            -- Legacy format only had regular/ghost, map to Off-Center location
            local type_key = mapping_type
            if type_key ~= "regular" and type_key ~= "ghost" then
                type_key = "regular"
            end
            
            table.insert(new_mappings[label]["Off-Center"][type_key], {
                track_index = track_index,
                instrument_index = instrument_index,
                sample_key = nil,
                committed = true
            })
        end
    end
    
    file:close()
    
    local song = renoise.song()
    local current_index = song.selected_instrument_index
    
    if not labeler.saved_labels_by_instrument[current_index] then
        labeler.saved_labels_by_instrument[current_index] = {}
    end
    
    labeler.saved_labels_by_instrument[current_index].mappings = new_mappings
    
    renoise.app():show_status("Mappings imported from " .. filepath)
end

--------------------------------------------------------------------------------
-- Unlock Function
--------------------------------------------------------------------------------

function labeler.unlock_instrument()
    labeler.locked_instrument_index = nil
    labeler.is_locked = false
    labeler.lock_state_observable.value = not labeler.lock_state_observable.value
    if dialog and dialog.visible then
        dialog:close()
        labeler.create_ui()
    end
end

--------------------------------------------------------------------------------
-- UI Creation (BreakFast-compatible with SRC display and Preview)
--------------------------------------------------------------------------------

function labeler.create_ui(closed_callback)
    if dialog and dialog.visible then
        dialog:close()
        dialog = nil
    end
    
    -- Stop any active preview
    labeler.stop_slice_preview()
    
    labeler.dialog_closed_callback = closed_callback
    
    local vb = renoise.ViewBuilder()
    local preview_col_width = 25
    local note_col_width = 45
    local sample_col_width = 120
    local column_width = 90
    local narrow_column = 70
    local spacing = 8
    
    local slice_data = {}
    
    local song = renoise.song()
    local instrument = labeler.is_locked and song:instrument(labeler.locked_instrument_index) 
                    or song.selected_instrument
    local samples = instrument.samples
    
    local current_index = labeler.is_locked and labeler.locked_instrument_index 
                    or song.selected_instrument_index
    
    local current_labels = labeler.saved_labels_by_instrument[current_index] or {}
    if current_labels.labels then
        current_labels = current_labels.labels
    end
    
    if current_labels.show_label2 ~= nil then
        labeler.show_label2 = current_labels.show_label2
    end
    if current_labels.show_advanced_data ~= nil then
        labeler.show_advanced_data = current_labels.show_advanced_data
    end
    
    -- Check if instrument has slices
    local has_slices = #samples > 1 and samples[1].slice_markers and #samples[1].slice_markers > 0
    
    -- Build slice data
    -- First, add SRC (root sample) if we have slices - this is display only
    if has_slices and #samples > 1 then
        local src_sample = samples[1]
        table.insert(slice_data, {
            index = 0,  -- Special index for SRC
            hex_key = "00",
            sample_name = "SRC: " .. (src_sample.name ~= "" and src_sample.name or "Root"),
            note_value = 36,  -- C-1
            is_src = true,  -- Flag to identify SRC row
            is_slice = false
        })
    end
    
    -- Then add all slices (starting from index 1)
    for j = 2, #samples do
        local sample = samples[j]
        local slice_index = j - 1  -- Slice 1 = index 1
        local hex_key = string.format("%02X", slice_index)  -- Slice 1 = "01"
        local note_value = 36 + slice_index  -- Slice 1 = note 37 (C#1)
        
        local saved_label = current_labels[hex_key] or {
            label = "---------",
            label2 = "---------",
            breakpoint = false,
            instrument_index = current_index,
            note_value = note_value,
            is_slice = true,
            location = "Off-Center",
            ghost = false,
            counterstroke = false,
            cycle = false
        }
        
        table.insert(slice_data, {
            index = slice_index,
            hex_key = hex_key,
            sample_name = string.format("S#%02d: %s", slice_index, sample.name ~= "" and sample.name or "Slice"),
            label = saved_label.label,
            label2 = saved_label.label2,
            breakpoint = saved_label.breakpoint,
            instrument_index = current_index,
            note_value = note_value,
            is_src = false,
            is_slice = true,
            location = saved_label.location or "Off-Center",
            ghost = saved_label.ghost,
            counterstroke = saved_label.counterstroke,
            cycle = saved_label.cycle
        })
    end
    
    local scale_factor = calculate_scale_factor(#slice_data)
    local padding = math.max(0, math.min(5, 5 * scale_factor))
    local row_height = math.max(13, math.min(25, 25 * scale_factor))
    
    local dialog_content = vb:column {
        margin = 10,
        spacing = spacing
    }
    
    local grid = vb:column {
        spacing = padding
    }
    
    -- Toggle controls row
    local toggle_controls = vb:row {
        spacing = spacing * 2,
        vb:row {
            vb:text { text = "Label 2:", style = "strong" },
            vb:button {
                text = "+",
                width = 20,
                notifier = function()
                    labeler.stop_slice_preview()
                    labeler.show_label2 = true
                    if dialog and dialog.visible then
                        dialog:close()
                        labeler.create_ui(labeler.dialog_closed_callback)
                    end
                end,
                active = not labeler.show_label2
            },
            vb:button {
                text = "-",
                width = 20,
                notifier = function()
                    labeler.stop_slice_preview()
                    labeler.show_label2 = false
                    if dialog and dialog.visible then
                        dialog:close()
                        labeler.create_ui(labeler.dialog_closed_callback)
                    end
                end,
                active = labeler.show_label2
            }
        },
        vb:row {
            vb:text { text = "Advanced Data:", style = "strong" },
            vb:button {
                text = "+",
                width = 20,
                notifier = function()
                    labeler.stop_slice_preview()
                    labeler.show_advanced_data = true
                    if dialog and dialog.visible then
                        dialog:close()
                        labeler.create_ui(labeler.dialog_closed_callback)
                    end
                end,
                active = not labeler.show_advanced_data
            },
            vb:button {
                text = "-",
                width = 20,
                notifier = function()
                    labeler.stop_slice_preview()
                    labeler.show_advanced_data = false
                    if dialog and dialog.visible then
                        dialog:close()
                        labeler.create_ui(labeler.dialog_closed_callback)
                    end
                end,
                active = labeler.show_advanced_data
            }
        }
    }
    
    -- Header row (with Preview column)
    local header_row = vb:row {
        spacing = spacing,
        vb:text { text = ">", width = preview_col_width, align = "center", style = "strong" },
        vb:text { text = "Note", width = note_col_width, align = "center", style = "strong" },
        vb:text { text = "Sample", width = sample_col_width, align = "left", style = "strong" },
        vb:text { text = "Label", width = column_width, align = "center", style = "strong" }
    }
    
    if labeler.show_label2 then
        header_row:add_child(vb:text { 
            text = "Label 2", 
            width = column_width, 
            align = "center",
            style = "strong"
        })
    end
    
    header_row:add_child(vb:text { text = "BP", width = 40, align = "center", style = "strong" })
    
    if labeler.show_advanced_data then
        header_row:add_child(vb:text { text = "Location", width = narrow_column, align = "center", style = "strong" })
        header_row:add_child(vb:text { text = "Ghost", width = 50, align = "center", style = "strong" })
        header_row:add_child(vb:text { text = "CS", width = 40, align = "center", style = "strong" })
        header_row:add_child(vb:text { text = "Cycle", width = 50, align = "center", style = "strong" })
    end
    
    grid:add_child(toggle_controls)
    grid:add_child(header_row)
    
    -- Slice rows (including SRC)
    for _, slice in ipairs(slice_data) do
        local is_src = slice.is_src
        local button_id = "preview_" .. slice.index
        
        local row = vb:row {
            spacing = spacing,
            height = row_height,
            
            -- Preview button (first column)
            vb:button {
                id = button_id,
                text = ">",
                width = preview_col_width,
                height = row_height,
                notifier = function()
                    labeler.toggle_slice_preview(current_index, slice.note_value, button_id, vb)
                end
            },
            
            -- Note column
            vb:text { 
                text = note_value_to_string(slice.note_value), 
                width = note_col_width, 
                align = "center",
                style = is_src and "disabled" or "normal"
            },
            
            -- Sample name column
            vb:text { 
                text = slice.sample_name, 
                width = sample_col_width, 
                align = "left",
                style = is_src and "disabled" or "normal"
            }
        }
        
        -- Label column (disabled for SRC)
        if is_src then
            row:add_child(vb:text {
                text = "(no labels)",
                width = column_width,
                align = "center",
                style = "disabled"
            })
        else
            row:add_child(vb:popup {
                id = "label_" .. slice.index,
                items = labeler.label_options,
                width = column_width,
                value = table.find(labeler.label_options, slice.label) or 1
            })
        end
        
        -- Label 2 column
        if labeler.show_label2 then
            if is_src then
                row:add_child(vb:text {
                    text = "---",
                    width = column_width,
                    align = "center",
                    style = "disabled"
                })
            else
                row:add_child(vb:popup {
                    id = "label2_" .. slice.index,
                    items = labeler.label_options,
                    width = column_width,
                    value = table.find(labeler.label_options, slice.label2) or 1
                })
            end
        end
        
        -- Breakpoint checkbox (disabled for SRC)
        if is_src then
            row:add_child(vb:text {
                text = "---",
                width = 40,
                align = "center",
                style = "disabled"
            })
        else
            row:add_child(vb:horizontal_aligner {
                mode = "center",
                width = 40,
                vb:checkbox {
                    id = "breakpoint_" .. slice.index,
                    value = slice.breakpoint,
                    width = 20,
                    height = math.max(15, math.min(20, 20 * scale_factor)),
                    notifier = function(value)
                        if value then
                            local current_count = 0
                            for _, other_slice in ipairs(slice_data) do
                                if not other_slice.is_src then
                                    local other_checkbox = vb.views["breakpoint_" .. other_slice.index]
                                    if other_checkbox and other_checkbox.value and other_slice.index ~= slice.index then
                                        current_count = current_count + 1
                                    end
                                end
                            end
                            
                            if current_count >= 4 then
                                vb.views["breakpoint_" .. slice.index].value = false
                                renoise.app():show_warning(
                                    "You have reached the limit! You can select up to 4 breakpoints per instrument."
                                )
                            end
                        end
                    end
                }
            })
        end
        
        -- Advanced Data fields (disabled for SRC)
        if labeler.show_advanced_data then
            if is_src then
                row:add_child(vb:text { text = "---", width = narrow_column, align = "center", style = "disabled" })
                row:add_child(vb:text { text = "---", width = 50, align = "center", style = "disabled" })
                row:add_child(vb:text { text = "---", width = 40, align = "center", style = "disabled" })
                row:add_child(vb:text { text = "---", width = 50, align = "center", style = "disabled" })
            else
                row:add_child(vb:popup {
                    id = "location_" .. slice.index,
                    items = labeler.location_options,
                    width = narrow_column,
                    value = table.find(labeler.location_options, slice.location) or 1
                })
                
                row:add_child(vb:horizontal_aligner {
                    mode = "center",
                    width = 50,
                    vb:checkbox {
                        id = "ghost_" .. slice.index,
                        value = slice.ghost,
                        width = 20,
                        height = math.max(15, math.min(20, 20 * scale_factor))
                    }
                })
                
                row:add_child(vb:horizontal_aligner {
                    mode = "center",
                    width = 40,
                    vb:checkbox {
                        id = "counterstroke_" .. slice.index,
                        value = slice.counterstroke,
                        width = 20,
                        height = math.max(15, math.min(20, 20 * scale_factor))
                    }
                })
                
                row:add_child(vb:horizontal_aligner {
                    mode = "center",
                    width = 50,
                    vb:checkbox {
                        id = "cycle_" .. slice.index,
                        value = slice.cycle,
                        width = 20,
                        height = math.max(15, math.min(20, 20 * scale_factor))
                    }
                })
            end
        end
        
        grid:add_child(row)
    end
    
    dialog_content:add_child(grid)
    
    -- Button row
    dialog_content:add_child(vb:horizontal_aligner {
        mode = "right",
        margin = 10,
        spacing = 10,
        vb:button {
            text = "Save Labels",
            notifier = function()
                -- Stop preview before saving
                labeler.stop_slice_preview()
                
                local saved_labels = {}
                local breakpoint_count = 0
                
                -- Count breakpoints (exclude SRC)
                for _, slice in ipairs(slice_data) do
                    if not slice.is_src and vb.views["breakpoint_" .. slice.index] then
                        if vb.views["breakpoint_" .. slice.index].value then
                            breakpoint_count = breakpoint_count + 1
                        end
                    end
                end
                
                if breakpoint_count > 4 then
                    renoise.app():show_warning(
                        "You have reached the limit! You can select up to 4 breakpoints per instrument."
                    )
                    return
                end
                
                -- Save labels (skip SRC)
                for _, slice in ipairs(slice_data) do
                    -- Skip SRC sample - it's display only
                    if slice.is_src then
                        goto continue_save_loop
                    end
                    
                    local hex_key = slice.hex_key
                    
                    local label2_value = nil
                    if labeler.show_label2 and vb.views["label2_" .. slice.index] then
                        label2_value = labeler.label_options[vb.views["label2_" .. slice.index].value]
                    end
                    
                    local location_value = "Off-Center"
                    if labeler.show_advanced_data and vb.views["location_" .. slice.index] then
                        location_value = labeler.location_options[vb.views["location_" .. slice.index].value]
                    end
                    
                    local ghost_value = false
                    if labeler.show_advanced_data and vb.views["ghost_" .. slice.index] then
                        ghost_value = vb.views["ghost_" .. slice.index].value
                    end
                    
                    local counterstroke_value = false
                    if labeler.show_advanced_data and vb.views["counterstroke_" .. slice.index] then
                        counterstroke_value = vb.views["counterstroke_" .. slice.index].value
                    end
                    
                    local cycle_value = false
                    if labeler.show_advanced_data and vb.views["cycle_" .. slice.index] then
                        cycle_value = vb.views["cycle_" .. slice.index].value
                    end
                    
                    saved_labels[hex_key] = {
                        label = labeler.label_options[vb.views["label_" .. slice.index].value],
                        label2 = label2_value,
                        breakpoint = vb.views["breakpoint_" .. slice.index].value,
                        instrument_index = current_index,
                        note_value = slice.note_value,
                        is_slice = true,
                        location = location_value,
                        ghost = ghost_value,
                        counterstroke = counterstroke_value,
                        cycle = cycle_value
                    }
                    
                    ::continue_save_loop::
                end
                
                local song = renoise.song()
                local instrument_index = song.selected_instrument_index
                
                labeler.locked_instrument_index = instrument_index
                labeler.is_locked = true
                
                -- Store with metadata
                labeler.saved_labels_by_instrument[instrument_index] = {
                    labels = table.copy(saved_labels),
                    mappings = (labeler.saved_labels_by_instrument[instrument_index] or {}).mappings or {},
                    show_label2 = labeler.show_label2,
                    show_advanced_data = labeler.show_advanced_data
                }
                labeler.saved_labels = saved_labels
                
                if dialog and dialog.visible then
                    dialog:close()
                    dialog = nil
                end
                
                labeler.saved_labels_observable.value = not labeler.saved_labels_observable.value
                labeler.lock_state_observable.value = not labeler.lock_state_observable.value
                
                if labeler.dialog_closed_callback then
                    labeler.dialog_closed_callback()
                end
            end
        }
    })
    
    dialog = renoise.app():show_custom_dialog("Slice Labeler", dialog_content)
end

--------------------------------------------------------------------------------
-- Recall Labels (Debug)
--------------------------------------------------------------------------------

function labeler.recall_labels()
    local vb = renoise.ViewBuilder()
    local saved_labels_str = ""
    
    for k, v in pairs(labeler.saved_labels) do
        saved_labels_str = saved_labels_str .. string.format(
            "%s: Label=%s, BP=%s, Location=%s, Ghost=%s, CS=%s, Cycle=%s\n", 
            k, v.label, tostring(v.breakpoint), v.location or "Off-Center",
            tostring(v.ghost), tostring(v.counterstroke), tostring(v.cycle))
    end
    
    renoise.app():show_custom_prompt("Recalled Labels", vb:column {
        vb:multiline_text {
            text = saved_labels_str,
            width = 500,
            height = 300
        }
    }, {"OK"})
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

function labeler.cleanup()
    -- Stop any active preview
    labeler.stop_slice_preview()
    stop_preview_timer()
    
    if dialog and dialog.visible then
        dialog:close()
        dialog = nil
    end 
    labeler.dialog_closed_callback = nil
end

return labeler