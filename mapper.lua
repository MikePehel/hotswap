-- mapper.lua
local mapper = {}
local labeler = require("labeler")

local dialog = nil

-- Location options (must match labeler.location_options)
local LOCATION_OPTIONS = {"Off-Center", "Center", "Edge", "Rim", "Alt"}

-- Mute group options (0 = None, 1-8 = group number)
local MUTE_GROUP_OPTIONS = {"None", "1", "2", "3", "4", "5", "6", "7", "8"}

-- Type keys based on ghost/counterstroke combinations
local TYPE_KEYS = {
    regular = "regular",
    ghost = "ghost",
    counterstroke = "counterstroke",
    ghost_counterstroke = "ghost_counterstroke"
}

-- Ordered iteration of type keys (pairs() has unpredictable order)
local TYPE_KEY_ORDER = {"regular", "ghost", "counterstroke", "ghost_counterstroke"}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

local function note_value_to_string(note_value)
    local note_names = {"C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"}
    local octave = math.floor(note_value / 12) - 1
    local note_index = (note_value % 12) + 1
    return note_names[note_index] .. octave
end

local function get_current_instrument_index()
    local song = renoise.song()
    return labeler.is_locked and labeler.locked_instrument_index or song.selected_instrument_index
end

--------------------------------------------------------------------------------
-- Config Management (Per-Instrument)
--------------------------------------------------------------------------------

local function get_mapper_config()
    local current_index = get_current_instrument_index()
    local stored_data = labeler.saved_labels_by_instrument[current_index] or {}

    return stored_data.mapper_config or {
        use_location = false,
        use_ghost = false,
        use_counterstroke = false,
        global_mute_group = 0
    }
end

local function save_mapper_config(config)
    local current_index = get_current_instrument_index()

    if not labeler.saved_labels_by_instrument[current_index] then
        labeler.saved_labels_by_instrument[current_index] = {}
    end

    labeler.saved_labels_by_instrument[current_index].mapper_config = config
end

--------------------------------------------------------------------------------
-- Mapping Structure Helpers
--------------------------------------------------------------------------------

local function create_empty_type_mappings()
    return {
        regular = {},
        ghost = {},
        counterstroke = {},
        ghost_counterstroke = {}
    }
end

local function create_empty_label_mappings()
    local mappings = {}
    for _, location in ipairs(LOCATION_OPTIONS) do
        mappings[location] = create_empty_type_mappings()
    end
    return mappings
end

local function ensure_mapping_structure(mappings, label)
    if not mappings[label] then
        mappings[label] = create_empty_label_mappings()
    else
        for _, location in ipairs(LOCATION_OPTIONS) do
            if not mappings[label][location] then
                mappings[label][location] = create_empty_type_mappings()
            else
                for _, type_key in pairs(TYPE_KEYS) do
                    if not mappings[label][location][type_key] then
                        mappings[label][location][type_key] = {}
                    end
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Label and Slice Analysis
--------------------------------------------------------------------------------

local function get_used_labels()
    local current_index = get_current_instrument_index()
    local stored_data = labeler.saved_labels_by_instrument[current_index] or {}
    local current_labels = stored_data.labels or stored_data or {}

    local used_labels = {}

    for hex_key, label_data in pairs(current_labels) do
        if type(label_data) == "table" then
            if label_data.label and label_data.label ~= "---------" then
                used_labels[label_data.label] = true
            end
            if label_data.label2 and label_data.label2 ~= "---------" then
                used_labels[label_data.label2] = true
            end
        end
    end

    return used_labels
end

local function get_slice_type_key(label_data)
    local is_ghost = label_data.ghost or false
    local is_counterstroke = label_data.counterstroke or false

    if is_ghost and is_counterstroke then
        return TYPE_KEYS.ghost_counterstroke
    elseif is_ghost then
        return TYPE_KEYS.ghost
    elseif is_counterstroke then
        return TYPE_KEYS.counterstroke
    else
        return TYPE_KEYS.regular
    end
end

-- Get full instance counts with all dimensions (location x type)
-- This is used for smart filtering - always returns full granularity
local function get_full_instance_counts()
    local current_index = get_current_instrument_index()
    local stored_data = labeler.saved_labels_by_instrument[current_index] or {}
    local current_labels = stored_data.labels or stored_data or {}

    local counts = {}

    for hex_key, label_data in pairs(current_labels) do
        if type(label_data) ~= "table" then
            goto continue
        end

        local labels_to_count = {}
        if label_data.label and label_data.label ~= "---------" then
            table.insert(labels_to_count, label_data.label)
        end
        if label_data.label2 and label_data.label2 ~= "---------" then
            table.insert(labels_to_count, label_data.label2)
        end

        for _, label in ipairs(labels_to_count) do
            if not counts[label] then
                counts[label] = {}
                for _, location in ipairs(LOCATION_OPTIONS) do
                    counts[label][location] = {
                        regular = 0,
                        ghost = 0,
                        counterstroke = 0,
                        ghost_counterstroke = 0
                    }
                end
            end

            local location = label_data.location or "Off-Center"
            local type_key = get_slice_type_key(label_data)

            counts[label][location][type_key] = counts[label][location][type_key] + 1
        end

        ::continue::
    end

    return counts
end

-- Get the effective count for a label/location/type based on config
-- This collapses counts when toggles are off
local function get_effective_count(full_counts, label, location, type_key, config)
    if not full_counts[label] then return 0 end

    local count = 0

    -- Determine which locations to sum
    local locations_to_check = {}
    if config.use_location then
        locations_to_check = {location}
    else
        locations_to_check = LOCATION_OPTIONS
    end

    -- Determine which types to sum based on the requested type_key and config
    local types_to_check = {}

    if config.use_ghost and config.use_counterstroke then
        -- Full granularity - just use the exact type
        types_to_check = {type_key}
    elseif config.use_ghost and not config.use_counterstroke then
        -- Ghost enabled, CS disabled
        if type_key == "regular" then
            types_to_check = {"regular", "counterstroke"}
        elseif type_key == "ghost" then
            types_to_check = {"ghost", "ghost_counterstroke"}
        end
    elseif not config.use_ghost and config.use_counterstroke then
        -- Ghost disabled, CS enabled
        if type_key == "regular" then
            types_to_check = {"regular", "ghost"}
        elseif type_key == "counterstroke" then
            types_to_check = {"counterstroke", "ghost_counterstroke"}
        end
    else
        -- Both disabled - sum all types
        if type_key == "regular" then
            types_to_check = {"regular", "ghost", "counterstroke", "ghost_counterstroke"}
        end
    end

    -- Sum the counts
    for _, loc in ipairs(locations_to_check) do
        if full_counts[label][loc] then
            for _, t in ipairs(types_to_check) do
                count = count + (full_counts[label][loc][t] or 0)
            end
        end
    end

    return count
end

--------------------------------------------------------------------------------
-- Track and Instrument Options
--------------------------------------------------------------------------------

local function get_track_options()
    local song = renoise.song()
    local track_options = {}

    for i, track in ipairs(song.tracks) do
        if track.type == renoise.Track.TRACK_TYPE_SEQUENCER then
            table.insert(track_options, string.format("%d: %s", i, track.name))
        end
    end

    return track_options
end

local function get_instrument_options()
    local song = renoise.song()
    local instrument_options = {}

    for i, instrument in ipairs(song.instruments) do
        table.insert(instrument_options, string.format("%02X: %s", i-1, instrument.name))
    end

    return instrument_options
end

local function get_sample_keys_for_instrument(instrument_index)
    local song = renoise.song()

    if instrument_index < 1 or instrument_index > #song.instruments then
        return {}
    end

    local instrument = song:instrument(instrument_index)
    local keys = {}
    local seen_notes = {}

    -- sample_mappings is a table with layers: [1] = note-on, [2] = note-off
    -- Each layer contains an array of sample mappings
    -- Access: instrument.sample_mappings[layer][mapping_index].base_note
    if instrument.sample_mappings then
        local note_on_layer = instrument.sample_mappings[1]
        if note_on_layer then
            -- Iterate through all mappings in the note-on layer
            for i = 1, #note_on_layer do
                local mapping = note_on_layer[i]
                if mapping and mapping.base_note then
                    local base_note = mapping.base_note
                    if not seen_notes[base_note] then
                        seen_notes[base_note] = true
                        table.insert(keys, base_note)
                    end
                end
            end
        end
    end

    table.sort(keys)
    return keys
end

-- Get sample info (name and base_note) for instruments with multiple samples
local function get_sample_info_for_instrument(instrument_index)
    local song = renoise.song()

    if instrument_index < 1 or instrument_index > #song.instruments then
        return {}, {}
    end

    local instrument = song:instrument(instrument_index)
    local sample_info = {}  -- Array of {name, base_note}
    local seen_notes = {}

    if instrument.sample_mappings then
        local note_on_layer = instrument.sample_mappings[1]
        if note_on_layer then
            for i = 1, #note_on_layer do
                local mapping = note_on_layer[i]
                if mapping and mapping.base_note and mapping.sample then
                    local base_note = mapping.base_note
                    if not seen_notes[base_note] then
                        seen_notes[base_note] = true
                        local sample_name = mapping.sample.name
                        if not sample_name or sample_name == "" then
                            sample_name = string.format("Sample %d", i)
                        end
                        table.insert(sample_info, {
                            name = sample_name,
                            base_note = base_note
                        })
                    end
                end
            end
        end
    end

    -- Sort by base_note
    table.sort(sample_info, function(a, b) return a.base_note < b.base_note end)

    return sample_info
end

local function get_sample_key_options(instrument_index)
    local keys = get_sample_keys_for_instrument(instrument_index)
    local options = {}

    if #keys <= 1 then
        return options, keys[1]
    end

    for _, key in ipairs(keys) do
        table.insert(options, note_value_to_string(key))
    end

    return options, keys
end

-- Get sample options with names for dropdown
local function get_sample_options(instrument_index)
    local sample_info = get_sample_info_for_instrument(instrument_index)
    local options = {}
    local keys = {}

    if #sample_info <= 1 then
        return options, keys
    end

    for _, info in ipairs(sample_info) do
        table.insert(options, info.name)
        table.insert(keys, info.base_note)
    end

    return options, keys
end

--------------------------------------------------------------------------------
-- Mapping Storage
--------------------------------------------------------------------------------

local function get_current_mappings()
    local current_index = get_current_instrument_index()
    local stored_data = labeler.saved_labels_by_instrument[current_index] or {}

    return stored_data.mappings or {}
end

local function save_mappings(mappings)
    local current_index = get_current_instrument_index()

    if not labeler.saved_labels_by_instrument[current_index] then
        labeler.saved_labels_by_instrument[current_index] = {}
    end

    labeler.saved_labels_by_instrument[current_index].mappings = mappings
end

--------------------------------------------------------------------------------
-- Summary and Type Helpers
--------------------------------------------------------------------------------

local function build_summary_string(mapping, inst_index_1based)
    local track_num = mapping.track_index and tostring(mapping.track_index) or "?"
    local inst_hex = mapping.instrument_index and string.format("%02X", mapping.instrument_index) or "??"
    local summary = "Track " .. track_num .. " > Inst " .. inst_hex

    if mapping.sample_key then
        local sample_info = get_sample_info_for_instrument(inst_index_1based)
        if #sample_info > 1 then
            for _, info in ipairs(sample_info) do
                if info.base_note == mapping.sample_key then
                    local name = info.name
                    if #name > 20 then
                        name = name:sub(1, 17) .. "..."
                    end
                    summary = summary .. " (" .. name .. ")"
                    break
                end
            end
        end
    end

    local mg = mapping.mute_group or 0
    if mg > 0 then
        summary = summary .. " (MG:" .. mg .. ")"
    end

    return summary
end

local function get_type_label_text(type_key, config)
    if not config.use_ghost and not config.use_counterstroke then
        return "Mappings:"
    end
    local labels = {
        regular = "Regular Mappings:",
        ghost = "Ghost Mappings:",
        counterstroke = "CounterStroke Mappings:",
        ghost_counterstroke = "Ghost+CS Mappings:"
    }
    return labels[type_key] or "Mappings:"
end

local function is_type_active(type_key, config)
    if type_key == "regular" then return true end
    if type_key == "ghost" then return config.use_ghost end
    if type_key == "counterstroke" then return config.use_counterstroke end
    if type_key == "ghost_counterstroke" then return config.use_ghost and config.use_counterstroke end
    return false
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

function mapper.cleanup()
    if dialog and dialog.visible then
        dialog:close()
        dialog = nil
    end
end

--------------------------------------------------------------------------------
-- UI Creation
--------------------------------------------------------------------------------

function mapper.create_ui()
    if dialog and dialog.visible then
        dialog:close()
        dialog = nil
    end

    local vb = renoise.ViewBuilder()
    local config = get_mapper_config()
    local used_labels = get_used_labels()
    local full_counts = get_full_instance_counts()
    local track_options = get_track_options()
    local instrument_options = get_instrument_options()
    local current_mappings = get_current_mappings()

    if not next(used_labels) then
        renoise.app():show_warning("No labels found. Please create and save labels first.")
        return
    end

    for label in pairs(used_labels) do
        ensure_mapping_structure(current_mappings, label)
    end

    local sorted_labels = {}
    for label in pairs(used_labels) do
        table.insert(sorted_labels, label)
    end
    table.sort(sorted_labels)

    -- Compute total slices per label (absolute max mappings any section could need)
    local total_label_count = {}
    for _, label in ipairs(sorted_labels) do
        local total = 0
        if full_counts[label] then
            for _, location in ipairs(LOCATION_OPTIONS) do
                if full_counts[label][location] then
                    for _, type_key in ipairs(TYPE_KEY_ORDER) do
                        total = total + (full_counts[label][location][type_key] or 0)
                    end
                end
            end
        end
        total_label_count[label] = math.max(total, 1)
    end

    ----------------------------------------------------------------------------
    -- Update section visibility based on current config
    ----------------------------------------------------------------------------
    local function update_section_visibility()
        for _, label in ipairs(sorted_labels) do
            local label_safe = label:gsub("%s", "_"):gsub("[^%w_]", "")

            for _, location in ipairs(LOCATION_OPTIONS) do
                local location_safe = location:gsub("-", ""):gsub("%s", "_")

                -- Determine if this location has any slices
                local loc_has_slices = false
                if full_counts[label] and full_counts[label][location] then
                    for _, tk in ipairs(TYPE_KEY_ORDER) do
                        if (full_counts[label][location][tk] or 0) > 0 then
                            loc_has_slices = true
                            break
                        end
                    end
                end

                local loc_visible
                if config.use_location then
                    loc_visible = loc_has_slices
                else
                    loc_visible = (location == "Off-Center")
                end

                -- Location header
                local loc_header = vb.views["loc_header_" .. label_safe .. "_" .. location_safe]
                if loc_header then
                    loc_header.visible = config.use_location and loc_visible
                end

                -- Type sections
                for _, type_key in ipairs(TYPE_KEY_ORDER) do
                    local section_id = label_safe .. "_" .. location_safe .. "_" .. type_key
                    local section_view = vb.views["section_" .. section_id]

                    if section_view then
                        local type_active = is_type_active(type_key, config)
                        local eff_count = get_effective_count(full_counts, label, location, type_key, config)
                        section_view.visible = loc_visible and type_active and eff_count > 0

                        -- Update type label text
                        local type_label_view = vb.views["type_label_" .. section_id]
                        if type_label_view then
                            type_label_view.text = get_type_label_text(type_key, config)
                        end

                        -- Update add button text
                        local add_btn = vb.views["add_btn_" .. section_id]
                        if add_btn then
                            local current_count = #(current_mappings[label][location][type_key] or {})
                            add_btn.text = string.format("Add Mapping (%d of %d)", current_count, eff_count)
                        end
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------------------
    -- Build dialog content
    ----------------------------------------------------------------------------
    local dialog_content = vb:column {
        margin = 5,
        spacing = 8
    }

    dialog_content:add_child(vb:text {
        text = "Label Track Mapping",
        font = "big",
        style = "strong"
    })

    -- Granularity Options Row
    local granularity_row = vb:row {
        spacing = 10,
        vb:column {
            style = "panel",
            margin = 5,
            spacing = 4,
            vb:text { text = "Granularity", style = "strong" },
            vb:row {
                spacing = 3,
                vb:checkbox {
                    value = config.use_location,
                    tooltip = "Enable location-based mapping differentiation",
                    notifier = function(value)
                        config.use_location = value
                        save_mapper_config(config)
                        update_section_visibility()
                    end
                },
                vb:text { text = "Location" }
            },
            vb:row {
                spacing = 3,
                vb:checkbox {
                    value = config.use_ghost,
                    tooltip = "Enable separate mappings for ghost notes",
                    notifier = function(value)
                        config.use_ghost = value
                        save_mapper_config(config)
                        update_section_visibility()
                    end
                },
                vb:text { text = "Ghost" }
            },
            vb:row {
                spacing = 3,
                vb:checkbox {
                    value = config.use_counterstroke,
                    tooltip = "Enable separate mappings for counterstrokes",
                    notifier = function(value)
                        config.use_counterstroke = value
                        save_mapper_config(config)
                        update_section_visibility()
                    end
                },
                vb:text { text = "CounterStroke" }
            }
        },
        vb:column {
            style = "panel",
            margin = 5,
            spacing = 4,
            vb:text { text = "Mute Group", style = "strong" },
            vb:row {
                spacing = 3,
                vb:text { text = "Global:" },
                vb:popup {
                    items = MUTE_GROUP_OPTIONS,
                    value = (config.global_mute_group or 0) + 1,
                    width = 60,
                    tooltip = "Default choke group — instruments in the same group cut each other off",
                    notifier = function(value)
                        config.global_mute_group = value - 1
                        save_mapper_config(config)
                    end
                }
            }
        }
    }
    dialog_content:add_child(granularity_row)

    dialog_content:add_child(vb:space { height = 5 })

    ----------------------------------------------------------------------------
    -- Build label sections in columns
    ----------------------------------------------------------------------------
    local max_labels_per_column = 4
    local num_columns = math.ceil(#sorted_labels / max_labels_per_column)

    local columns_container = vb:row { spacing = 10 }

    for col = 1, num_columns do
        local column = vb:column { spacing = 8 }

        local start_idx = (col - 1) * max_labels_per_column + 1
        local end_idx = math.min(col * max_labels_per_column, #sorted_labels)

        for label_idx = start_idx, end_idx do
            local label = sorted_labels[label_idx]
            local label_safe = label:gsub("%s", "_"):gsub("[^%w_]", "")
            local max_slots = total_label_count[label]

            local label_section = vb:column {
                style = "panel",
                margin = 8,
                spacing = 6
            }

            label_section:add_child(vb:text {
                text = "Label: " .. label,
                font = "bold"
            })

            -- Build ALL location × type sections (visibility controlled)
            for _, location in ipairs(LOCATION_OPTIONS) do
                local location_safe = location:gsub("-", ""):gsub("%s", "_")

                -- Determine initial location visibility
                local loc_has_slices = false
                if full_counts[label] and full_counts[label][location] then
                    for _, tk in ipairs(TYPE_KEY_ORDER) do
                        if (full_counts[label][location][tk] or 0) > 0 then
                            loc_has_slices = true
                            break
                        end
                    end
                end

                local loc_visible
                if config.use_location then
                    loc_visible = loc_has_slices
                else
                    loc_visible = (location == "Off-Center")
                end

                -- Location header
                label_section:add_child(vb:text {
                    id = "loc_header_" .. label_safe .. "_" .. location_safe,
                    text = "[" .. location .. "]",
                    font = "bold",
                    style = "strong",
                    visible = config.use_location and loc_visible
                })

                -- Type sections for this location
                for _, type_key in ipairs(TYPE_KEY_ORDER) do
                    local type_active = is_type_active(type_key, config)
                    local eff_count = get_effective_count(full_counts, label, location, type_key, config)
                    local section_visible = loc_visible and type_active and eff_count > 0

                    local section_id = label_safe .. "_" .. location_safe .. "_" .. type_key
                    local type_mappings = current_mappings[label][location][type_key] or {}

                    local type_section = vb:column {
                        id = "section_" .. section_id,
                        visible = section_visible,
                        spacing = 3
                    }

                    type_section:add_child(vb:text {
                        id = "type_label_" .. section_id,
                        text = get_type_label_text(type_key, config),
                        style = "strong"
                    })

                    local mappings_container = vb:column { spacing = 3 }

                    ----------------------------------------------------------------
                    -- Pre-allocate mapping slots (1..max_slots)
                    ----------------------------------------------------------------
                    for slot_idx = 1, max_slots do
                        local mapping_id = string.format("%s_%s_%s_%d",
                            label_safe, location_safe, type_key, slot_idx)
                        local mapping = type_mappings[slot_idx]
                        local has_data = mapping ~= nil
                        local is_committed = has_data and (mapping.committed or false)

                        -- Instrument info for this slot
                        local inst_index_1based = has_data
                            and ((mapping.instrument_index or 0) + 1)
                            or 1
                        local sample_options, sample_keys = get_sample_options(inst_index_1based)
                        local has_samples = #sample_options > 1

                        -- Current sample index
                        local current_sample_index = 1
                        if has_data and mapping.sample_key and sample_keys then
                            for idx, key in ipairs(sample_keys) do
                                if key == mapping.sample_key then
                                    current_sample_index = idx
                                    break
                                end
                            end
                        end

                        -- Summary for collapsed view
                        local summary_text = ""
                        if has_data then
                            summary_text = build_summary_string(mapping, inst_index_1based)
                        end

                        -- Closure variables
                        local this_label = label
                        local this_location = location
                        local this_type_key = type_key
                        local this_slot_idx = slot_idx

                        -- Collapsed view
                        local collapsed_view = vb:row {
                            id = "collapsed_" .. mapping_id,
                            visible = has_data and is_committed,
                            spacing = 3,
                            vb:text {
                                id = "summary_" .. mapping_id,
                                text = summary_text
                            },
                            vb:button {
                                text = "Edit",
                                width = 45,
                                tooltip = "Edit this mapping",
                                notifier = function()
                                    vb.views["collapsed_" .. mapping_id].visible = false
                                    vb.views["expanded_" .. mapping_id].visible = true
                                end
                            },
                            vb:button {
                                text = "X",
                                width = 25,
                                tooltip = "Remove this mapping",
                                notifier = function()
                                    table.remove(
                                        current_mappings[this_label][this_location][this_type_key],
                                        this_slot_idx)
                                    save_mappings(current_mappings)
                                    dialog:close()
                                    mapper.create_ui()
                                end
                            }
                        }

                        -- Expanded view
                        local expanded_view = vb:column {
                            id = "expanded_" .. mapping_id,
                            visible = has_data and not is_committed,
                            spacing = 2,
                            -- Main row: Track, Inst, Done, X
                            vb:row {
                                spacing = 5,
                                vb:text { text = "Track:", width = 55, align = "right" },
                                vb:popup {
                                    id = "track_" .. mapping_id,
                                    items = track_options,
                                    value = has_data and (mapping.track_index or 1) or 1,
                                    width = 160
                                },
                                vb:text { text = "Inst:", width = 55, align = "right" },
                                vb:popup {
                                    id = "inst_" .. mapping_id,
                                    items = instrument_options,
                                    value = inst_index_1based,
                                    width = 160,
                                    notifier = function(new_value)
                                        -- Update sample row in place
                                        local new_opts, new_keys = get_sample_options(new_value)
                                        local sample_popup = vb.views["sample_" .. mapping_id]
                                        local sample_row = vb.views["sample_row_" .. mapping_id]
                                        if sample_popup then
                                            if #new_opts > 1 then
                                                sample_popup.items = new_opts
                                                sample_popup.value = 1
                                            else
                                                sample_popup.items = {"(default)"}
                                                sample_popup.value = 1
                                            end
                                        end
                                        if sample_row then
                                            sample_row.visible = (#new_opts > 1)
                                        end
                                    end
                                },
                                vb:button {
                                    text = "Done",
                                    width = 50,
                                    tooltip = "Save and collapse this mapping",
                                    notifier = function()
                                        local track_popup = vb.views["track_" .. mapping_id]
                                        local inst_popup = vb.views["inst_" .. mapping_id]
                                        local sample_popup = vb.views["sample_" .. mapping_id]
                                        local mute_group_popup = vb.views["mute_group_" .. mapping_id]

                                        if not (track_popup and inst_popup) then return end

                                        local track_str = track_popup.items[track_popup.value]
                                        local track_index = tonumber(track_str:match("^(%d+):"))
                                        local instrument_index = inst_popup.value - 1

                                        local sample_key = nil
                                        local sample_row = vb.views["sample_row_" .. mapping_id]
                                        if sample_popup and sample_row and sample_row.visible then
                                            local smp_opts, smp_keys = get_sample_options(inst_popup.value)
                                            if smp_keys and #smp_keys > 0
                                                and sample_popup.value <= #smp_keys then
                                                sample_key = smp_keys[sample_popup.value]
                                            end
                                        end

                                        local mute_group = 0
                                        if mute_group_popup then
                                            mute_group = mute_group_popup.value - 1
                                        end

                                        current_mappings[this_label][this_location][this_type_key][this_slot_idx] = {
                                            track_index = track_index,
                                            instrument_index = instrument_index,
                                            sample_key = sample_key,
                                            mute_group = mute_group,
                                            committed = true
                                        }
                                        save_mappings(current_mappings)

                                        -- Update summary text
                                        vb.views["summary_" .. mapping_id].text =
                                            build_summary_string(
                                                current_mappings[this_label][this_location][this_type_key][this_slot_idx],
                                                inst_popup.value)

                                        -- Swap visibility (NO rebuild)
                                        vb.views["expanded_" .. mapping_id].visible = false
                                        vb.views["collapsed_" .. mapping_id].visible = true
                                    end
                                },
                                vb:button {
                                    text = "X",
                                    width = 25,
                                    tooltip = "Remove this mapping",
                                    notifier = function()
                                        table.remove(
                                            current_mappings[this_label][this_location][this_type_key],
                                            this_slot_idx)
                                        save_mappings(current_mappings)
                                        dialog:close()
                                        mapper.create_ui()
                                    end
                                }
                            },
                            -- Sample row (always created, visibility controlled)
                            vb:row {
                                id = "sample_row_" .. mapping_id,
                                visible = has_samples,
                                spacing = 5,
                                vb:text { text = "Sample:", width = 55, align = "right" },
                                vb:popup {
                                    id = "sample_" .. mapping_id,
                                    items = has_samples and sample_options or {"(default)"},
                                    value = current_sample_index,
                                    width = 160
                                }
                            },
                            -- Mute group row
                            vb:row {
                                spacing = 5,
                                vb:text { text = "Mute Grp:", width = 55, align = "right" },
                                vb:popup {
                                    id = "mute_group_" .. mapping_id,
                                    items = MUTE_GROUP_OPTIONS,
                                    value = has_data and ((mapping.mute_group or 0) + 1) or 1,
                                    width = 160
                                }
                            }
                        }

                        -- Container holds both collapsed and expanded views
                        local mapping_container = vb:column {
                            id = "mapping_container_" .. mapping_id,
                            visible = has_data,
                            spacing = 2
                        }
                        mapping_container:add_child(collapsed_view)
                        mapping_container:add_child(expanded_view)

                        mappings_container:add_child(mapping_container)
                    end

                    ----------------------------------------------------------------
                    -- Add Mapping button
                    ----------------------------------------------------------------
                    local initial_count = #type_mappings
                    mappings_container:add_child(vb:button {
                        id = "add_btn_" .. section_id,
                        text = string.format("Add Mapping (%d of %d)", initial_count, eff_count),
                        width = 180,
                        tooltip = "Add a new mapping for this label",
                        notifier = function()
                            local type_data = current_mappings[label][location][type_key]
                            if not type_data then
                                type_data = {}
                                current_mappings[label][location][type_key] = type_data
                            end
                            local cur_count = #type_data
                            local cur_eff = get_effective_count(
                                full_counts, label, location, type_key, config)

                            if cur_count < cur_eff and cur_count < max_slots then
                                table.insert(type_data, {
                                    track_index = 1,
                                    instrument_index = 0,
                                    sample_key = nil,
                                    mute_group = 0,
                                    committed = false
                                })
                                save_mappings(current_mappings)

                                local new_index = #type_data
                                local slot_id = string.format("%s_%s_%s_%d",
                                    label_safe, location_safe, type_key, new_index)

                                -- Show the pre-allocated slot in expanded state
                                vb.views["mapping_container_" .. slot_id].visible = true
                                vb.views["expanded_" .. slot_id].visible = true
                                vb.views["collapsed_" .. slot_id].visible = false

                                -- Update add button text
                                vb.views["add_btn_" .. section_id].text =
                                    string.format("Add Mapping (%d of %d)", new_index, cur_eff)
                            else
                                renoise.app():show_warning(string.format(
                                    "Maximum of %d %s mappings reached for label '%s' at location '%s'.",
                                    cur_eff, type_key, label, location))
                            end
                        end
                    })

                    type_section:add_child(mappings_container)
                    label_section:add_child(type_section)
                end
            end

            column:add_child(label_section)
        end

        columns_container:add_child(column)
    end

    dialog_content:add_child(columns_container)

    ----------------------------------------------------------------------------
    -- Control buttons
    ----------------------------------------------------------------------------
    dialog_content:add_child(vb:horizontal_aligner {
        mode = "right",
        margin = 10,
        spacing = 8,
        vb:button {
            text = "Clear All",
            width = 100,
            tooltip = "Remove all mappings",
            notifier = function()
                local choice = renoise.app():show_prompt(
                    "Clear All",
                    "Remove all mappings for this instrument?",
                    {"Yes", "Cancel"})
                if choice == "Cancel" then return end
                for lbl in pairs(used_labels) do
                    current_mappings[lbl] = create_empty_label_mappings()
                end
                save_mappings(current_mappings)
                dialog:close()
                mapper.create_ui()
            end
        },
        vb:button {
            text = "Close",
            width = 100,
            tooltip = "Close the mapping editor",
            notifier = function()
                if dialog and dialog.visible then
                    dialog:close()
                    dialog = nil
                end
            end
        }
    })

    dialog = renoise.app():show_custom_dialog("Label Track Mapping", dialog_content)
end

--------------------------------------------------------------------------------
-- Public API for Swapper
--------------------------------------------------------------------------------

function mapper.resolve_mapping(label, slice_data)
    local config = get_mapper_config()
    local mappings = get_current_mappings()

    if not mappings[label] then
        return nil
    end

    -- Determine location key
    local location_key
    if config.use_location then
        location_key = slice_data.location or "Off-Center"
    else
        location_key = "Off-Center"
    end

    -- Fallback if location doesn't exist
    if not mappings[label][location_key] then
        if mappings[label]["Off-Center"] then
            location_key = "Off-Center"
        else
            for _, loc in ipairs(LOCATION_OPTIONS) do
                if mappings[label][loc] then
                    location_key = loc
                    break
                end
            end
        end
    end

    if not mappings[label][location_key] then
        return nil
    end

    -- Determine type key based on config
    local type_key
    if config.use_ghost and config.use_counterstroke then
        type_key = get_slice_type_key(slice_data)
    elseif config.use_ghost then
        type_key = slice_data.ghost and "ghost" or "regular"
    elseif config.use_counterstroke then
        type_key = slice_data.counterstroke and "counterstroke" or "regular"
    else
        type_key = "regular"
    end

    return mappings[label][location_key][type_key] or {}
end

function mapper.get_config()
    return get_mapper_config()
end

-- Returns a table mapping mute_group_number -> list of {track_index, instrument_index}
-- This is used by the swapper to know which tracks to send OFF notes to
function mapper.get_mute_group_tracks()
    local config = get_mapper_config()
    local mappings = get_current_mappings()
    local mute_groups = {}

    for label, location_mappings in pairs(mappings) do
        if type(location_mappings) ~= "table" then
            goto continue_label
        end
        for location, type_mappings in pairs(location_mappings) do
            if type(type_mappings) ~= "table" then
                goto continue_location
            end
            for type_key, mapping_list in pairs(type_mappings) do
                if type(mapping_list) ~= "table" then
                    goto continue_type
                end
                for _, mapping in ipairs(mapping_list) do
                    -- Use global mute group if set, otherwise per-mapping
                    local mg = config.global_mute_group
                    if mg == 0 then
                        mg = mapping.mute_group or 0
                    end

                    if mg > 0 and mapping.track_index then
                        if not mute_groups[mg] then
                            mute_groups[mg] = {}
                        end
                        table.insert(mute_groups[mg], {
                            track_index = mapping.track_index,
                            instrument_index = mapping.instrument_index
                        })
                    end
                end
                ::continue_type::
            end
            ::continue_location::
        end
        ::continue_label::
    end

    return mute_groups
end

-- Returns the effective mute group for a given mapping entry
function mapper.get_effective_mute_group(mapping)
    local config = get_mapper_config()
    if config.global_mute_group > 0 then
        return config.global_mute_group
    end
    return mapping.mute_group or 0
end

return mapper
