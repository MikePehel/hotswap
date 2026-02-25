-- mapper.lua
local mapper = {}
local labeler = require("labeler")

local dialog = nil
mapper.dialog_closed_callback = nil

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

-- Get type section info based on config
local function get_type_section_info(config)
    local sections = {}
    
    if not config.use_ghost and not config.use_counterstroke then
        table.insert(sections, {key = "regular", label = "Mappings"})
    elseif config.use_ghost and not config.use_counterstroke then
        table.insert(sections, {key = "regular", label = "Regular Mappings"})
        table.insert(sections, {key = "ghost", label = "Ghost Mappings"})
    elseif not config.use_ghost and config.use_counterstroke then
        table.insert(sections, {key = "regular", label = "Regular Mappings"})
        table.insert(sections, {key = "counterstroke", label = "CounterStroke Mappings"})
    else
        table.insert(sections, {key = "regular", label = "Regular Mappings"})
        table.insert(sections, {key = "ghost", label = "Ghost Mappings"})
        table.insert(sections, {key = "counterstroke", label = "CounterStroke Mappings"})
        table.insert(sections, {key = "ghost_counterstroke", label = "Ghost+CS Mappings"})
    end
    
    return sections
end

-- Get locations that have at least one slice for a given label
local function get_active_locations_for_label(full_counts, label, config)
    if not full_counts[label] then return {} end
    
    local active_locations = {}
    
    for _, location in ipairs(LOCATION_OPTIONS) do
        local has_slices = false
        local loc_counts = full_counts[label][location]
        
        if loc_counts then
            for _, type_key in pairs(TYPE_KEYS) do
                if loc_counts[type_key] and loc_counts[type_key] > 0 then
                    has_slices = true
                    break
                end
            end
        end
        
        if has_slices then
            table.insert(active_locations, location)
        end
    end
    
    return active_locations
end

-- Get type sections that have at least one slice for a given label and location
local function get_active_type_sections(full_counts, label, location, config)
    local all_sections = get_type_section_info(config)
    local active_sections = {}
    
    for _, section in ipairs(all_sections) do
        local count = get_effective_count(full_counts, label, location, section.key, config)
        if count > 0 then
            table.insert(active_sections, section)
        end
    end
    
    return active_sections
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
-- Cleanup
--------------------------------------------------------------------------------

function mapper.cleanup()
    if dialog and dialog.visible then
        dialog:close()
        dialog = nil
    end
    mapper.dialog_closed_callback = nil
end

--------------------------------------------------------------------------------
-- UI Creation
--------------------------------------------------------------------------------

function mapper.create_ui(closed_callback)
    if dialog and dialog.visible then
        dialog:close()
        dialog = nil
    end
    
    mapper.dialog_closed_callback = closed_callback
    
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
        spacing = 15,
        vb:text { text = "Granularity:", style = "strong" },
        vb:row {
            spacing = 3,
            vb:checkbox {
                id = "use_location_toggle",
                value = config.use_location,
                notifier = function(value)
                    config.use_location = value
                    save_mapper_config(config)
                    dialog:close()
                    mapper.create_ui(mapper.dialog_closed_callback)
                end
            },
            vb:text { text = "Location" }
        },
        vb:row {
            spacing = 3,
            vb:checkbox {
                id = "use_ghost_toggle",
                value = config.use_ghost,
                notifier = function(value)
                    config.use_ghost = value
                    save_mapper_config(config)
                    dialog:close()
                    mapper.create_ui(mapper.dialog_closed_callback)
                end
            },
            vb:text { text = "Ghost" }
        },
        vb:row {
            spacing = 3,
            vb:checkbox {
                id = "use_counterstroke_toggle",
                value = config.use_counterstroke,
                notifier = function(value)
                    config.use_counterstroke = value
                    save_mapper_config(config)
                    dialog:close()
                    mapper.create_ui(mapper.dialog_closed_callback)
                end
            },
            vb:text { text = "CounterStroke" }
        },
        vb:row {
            spacing = 3,
            vb:text { text = "Global Mute Grp:" },
            vb:popup {
                id = "global_mute_group",
                items = MUTE_GROUP_OPTIONS,
                value = (config.global_mute_group or 0) + 1,
                width = 60,
                notifier = function(value)
                    config.global_mute_group = value - 1
                    save_mapper_config(config)
                end
            }
        }
    }
    dialog_content:add_child(granularity_row)
    
    dialog_content:add_child(vb:space { height = 5 })
    
    -- Estimate section height for column layout
    -- This is approximate - accounts for location sections when enabled
    local avg_locations_per_label = config.use_location and 2 or 1
    local avg_types_per_location = 1.5
    local estimated_section_height = 60 + (avg_locations_per_label * avg_types_per_location * 50)
    local max_labels_per_column = math.max(1, math.floor(600 / estimated_section_height))
    local num_columns = math.ceil(#sorted_labels / max_labels_per_column)
    
    local columns_container = vb:row {
        spacing = 10
    }
    
    for col = 1, num_columns do
        local column = vb:column {
            spacing = 8
        }
        
        local start_idx = (col - 1) * max_labels_per_column + 1
        local end_idx = math.min(col * max_labels_per_column, #sorted_labels)
        
        for label_idx = start_idx, end_idx do
            local label = sorted_labels[label_idx]
            local label_safe = label:gsub("%s", "_"):gsub("[^%w_]", "")
            
            local label_section = vb:column {
                style = "panel",
                margin = 5,
                spacing = 5
            }
            
            label_section:add_child(vb:text {
                text = "Label: " .. label,
                font = "bold"
            })
            
            -- Determine which locations to show
            local locations_to_show
            if config.use_location then
                locations_to_show = get_active_locations_for_label(full_counts, label, config)
            else
                -- When location is off, use Off-Center as default
                locations_to_show = {"Off-Center"}
            end
            
            -- Build UI for each active location
            for _, location in ipairs(locations_to_show) do
                local location_safe = location:gsub("-", ""):gsub("%s", "_")
                
                -- Get active type sections for this location
                local active_sections = get_active_type_sections(full_counts, label, location, config)
                
                -- Skip this location if no active sections
                if #active_sections == 0 then
                    goto continue_location
                end
                
                -- Add location header if location granularity is enabled
                if config.use_location then
                    label_section:add_child(vb:text {
                        text = "[" .. location .. "]",
                        font = "bold",
                        style = "strong"
                    })
                end
                
                -- Build UI for each active type section
                for _, section in ipairs(active_sections) do
                    local type_key = section.key
                    local section_label = section.label
                    local max_count = get_effective_count(full_counts, label, location, type_key, config)
                    local type_mappings = current_mappings[label][location][type_key] or {}
                    
                    local type_section = vb:column {
                        spacing = 3
                    }
                    
                    type_section:add_child(vb:text {
                        text = section_label .. ":",
                        style = "strong"
                    })
                    
                    local mappings_container = vb:column {
                        spacing = 3
                    }
                    
                    -- Add existing mappings
                    for i, mapping in ipairs(type_mappings) do
                        local mapping_id = string.format("%s_%s_%s_%d", label_safe, location_safe, type_key, i)
                        
                        local inst_index = (mapping.instrument_index or 0) + 1
                        local sample_options, sample_keys = get_sample_options(inst_index)
                        local has_samples = #sample_options > 1
                        local is_committed = mapping.committed or false
                        
                        -- Create closure variables for this mapping
                        local this_label = label
                        local this_location = location
                        local this_type_key = type_key
                        local this_mapping_index = i
                        
                        -- Container for this mapping (can hold multiple rows)
                        local mapping_container = vb:column {
                            spacing = 2
                        }
                        
                        if is_committed then
                            -- COLLAPSED STATE: Show compact summary with edit button
                            local track_num = "?"
                            if mapping.track_index then
                                track_num = tostring(mapping.track_index)
                            end
                            
                            local inst_hex = "??"
                            if mapping.instrument_index then
                                inst_hex = string.format("%02X", mapping.instrument_index)
                            end
                            
                            local sample_name = ""
                            if mapping.sample_key and has_samples then
                                for idx, key in ipairs(sample_keys) do
                                    if key == mapping.sample_key then
                                        -- Truncate long sample names
                                        local name = sample_options[idx] or ""
                                        if #name > 20 then
                                            name = name:sub(1, 17) .. "..."
                                        end
                                        sample_name = name
                                        break
                                    end
                                end
                            end
                            
                            local collapsed_row = vb:row {
                                spacing = 3,
                                vb:text { text = "T:" .. track_num },
                                vb:text { text = "I:" .. inst_hex }
                            }
                            
                            if sample_name ~= "" then
                                collapsed_row:add_child(vb:text { text = ">" })
                                collapsed_row:add_child(vb:text { text = sample_name })
                            end
                            
                            -- Show mute group if set
                            local mg = mapping.mute_group or 0
                            if mg > 0 then
                                collapsed_row:add_child(vb:text { text = "MG:" .. mg })
                            end
                            
                            collapsed_row:add_child(vb:button {
                                text = "[Edit]",
                                width = 40,
                                notifier = function()
                                    -- Uncollapse this mapping
                                    current_mappings[this_label][this_location][this_type_key][this_mapping_index].committed = false
                                    save_mappings(current_mappings)
                                    dialog:close()
                                    mapper.create_ui(mapper.dialog_closed_callback)
                                end
                            })
                            collapsed_row:add_child(vb:button {
                                text = "[-]",
                                width = 25,
                                notifier = function()
                                    table.remove(current_mappings[this_label][this_location][this_type_key], this_mapping_index)
                                    save_mappings(current_mappings)
                                    dialog:close()
                                    mapper.create_ui(mapper.dialog_closed_callback)
                                end
                            })
                            
                            mapping_container:add_child(collapsed_row)
                        else
                            -- EXPANDED STATE: Show full editing UI
                            local main_row = vb:row {
                                spacing = 5,
                                vb:text { text = "Trk:", width = 25 },
                                vb:popup {
                                    id = "track_" .. mapping_id,
                                    items = track_options,
                                    value = mapping.track_index or 1,
                                    width = 120
                                },
                                vb:text { text = "Inst:", width = 28 },
                                vb:popup {
                                    id = "inst_" .. mapping_id,
                                    items = instrument_options,
                                    value = inst_index,
                                    width = 120,
                                    notifier = function(new_inst_index)
                                        -- When instrument changes, save and refresh to show/hide sample dropdown
                                        local track_popup = vb.views["track_" .. mapping_id]
                                        local track_str = track_popup.items[track_popup.value]
                                        local track_index = tonumber(track_str:match("^(%d+):"))
                                        
                                        current_mappings[this_label][this_location][this_type_key][this_mapping_index] = {
                                            track_index = track_index,
                                            instrument_index = new_inst_index - 1,
                                            sample_key = nil,
                                            mute_group = mapping.mute_group or 0,
                                            committed = false
                                        }
                                        save_mappings(current_mappings)
                                        dialog:close()
                                        mapper.create_ui(mapper.dialog_closed_callback)
                                    end
                                },
                                -- Commit button
                                vb:button {
                                    text = "[OK]",
                                    width = 25,
                                    notifier = function()
                                        local track_popup = vb.views["track_" .. mapping_id]
                                        local inst_popup = vb.views["inst_" .. mapping_id]
                                        local sample_popup = vb.views["sample_" .. mapping_id]
                                        
                                        if track_popup and inst_popup then
                                            local track_str = track_popup.items[track_popup.value]
                                            local track_index = tonumber(track_str:match("^(%d+):"))
                                            local instrument_index = inst_popup.value - 1
                                            
                                            local sample_key = nil
                                            if sample_popup then
                                                local smp_opts, smp_keys = get_sample_options(inst_popup.value)
                                                if smp_keys and #smp_keys > 0 and sample_popup.value <= #smp_keys then
                                                    sample_key = smp_keys[sample_popup.value]
                                                end
                                            end
                                            
                                            local mute_group_popup = vb.views["mute_group_" .. mapping_id]
                                            local mute_group = 0
                                            if mute_group_popup then
                                                mute_group = mute_group_popup.value - 1
                                            end
                                            
                                            current_mappings[this_label][this_location][this_type_key][this_mapping_index] = {
                                                track_index = track_index,
                                                instrument_index = instrument_index,
                                                sample_key = sample_key,
                                                mute_group = mute_group,
                                                committed = true
                                            }
                                            save_mappings(current_mappings)
                                            
                                            -- Refresh to show collapsed state
                                            dialog:close()
                                            mapper.create_ui(mapper.dialog_closed_callback)
                                        end
                                    end
                                },
                                -- Remove button
                                vb:button {
                                    text = "[-]",
                                    width = 25,
                                    notifier = function()
                                        table.remove(current_mappings[this_label][this_location][this_type_key], this_mapping_index)
                                        save_mappings(current_mappings)
                                        dialog:close()
                                        mapper.create_ui(mapper.dialog_closed_callback)
                                    end
                                }
                            }
                            
                            mapping_container:add_child(main_row)
                            
                            -- Sample row (below, left-aligned) - only if instrument has multiple samples
                            if has_samples then
                                local current_sample_index = 1
                                if mapping.sample_key and sample_keys then
                                    for idx, key in ipairs(sample_keys) do
                                        if key == mapping.sample_key then
                                            current_sample_index = idx
                                            break
                                        end
                                    end
                                end
                                
                                local sample_row = vb:row {
                                    spacing = 5,
                                    vb:text { text = "Sample:", width = 45 },
                                    vb:popup {
                                        id = "sample_" .. mapping_id,
                                        items = sample_options,
                                        value = current_sample_index,
                                        width = 200
                                    }
                                }
                                
                                mapping_container:add_child(sample_row)
                            end
                            
                            -- Mute group row (always shown in expanded state)
                            local mute_group_row = vb:row {
                                spacing = 5,
                                vb:text { text = "Mute Grp:", width = 55 },
                                vb:popup {
                                    id = "mute_group_" .. mapping_id,
                                    items = MUTE_GROUP_OPTIONS,
                                    value = (mapping.mute_group or 0) + 1,
                                    width = 60
                                }
                            }
                            mapping_container:add_child(mute_group_row)
                        end
                        
                        mappings_container:add_child(mapping_container)
                    end
                    
                    -- Add button
                    local current_count = #type_mappings
                    mappings_container:add_child(vb:button {
                        text = string.format("[+] Add (%d/%d)", current_count, max_count),
                        width = 120,
                        notifier = function()
                            if current_count < max_count then
                                table.insert(current_mappings[label][location][type_key], {
                                    track_index = 1,
                                    instrument_index = 0,
                                    sample_key = nil,
                                    mute_group = 0,
                                    committed = false
                                })
                                save_mappings(current_mappings)
                                dialog:close()
                                mapper.create_ui(mapper.dialog_closed_callback)
                            else
                                renoise.app():show_warning(string.format(
                                    "Maximum of %d %s mappings reached for label '%s' at location '%s'.",
                                    max_count, type_key, label, location))
                            end
                        end
                    })
                    
                    type_section:add_child(mappings_container)
                    label_section:add_child(type_section)
                end
                
                ::continue_location::
            end
            
            column:add_child(label_section)
        end
        
        columns_container:add_child(column)
    end
    
    dialog_content:add_child(columns_container)
    
    -- Control buttons
    dialog_content:add_child(vb:horizontal_aligner {
        mode = "right",
        margin = 10,
        spacing = 5,
        vb:button {
            text = "Clear All",
            notifier = function()
                for label in pairs(used_labels) do
                    current_mappings[label] = create_empty_label_mappings()
                end
                save_mappings(current_mappings)
                dialog:close()
                mapper.create_ui(mapper.dialog_closed_callback)
            end
        },
        vb:button {
            text = "Close",
            notifier = function()
                -- Close dialog - mappings are already saved via commit buttons
                if dialog and dialog.visible then
                    dialog:close()
                    dialog = nil
                end
                
                if mapper.dialog_closed_callback then
                    mapper.dialog_closed_callback()
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