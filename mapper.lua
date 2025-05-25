-- mapper.lua
local mapper = {}
local labeler = require("labeler")

local dialog = nil
mapper.dialog_closed_callback = nil

function mapper.cleanup()
  if dialog and dialog.visible then
    dialog:close()
    dialog = nil
  end
  mapper.dialog_closed_callback = nil
end

local function get_used_labels()
  local song = renoise.song()
  local current_index = labeler.is_locked and labeler.locked_instrument_index 
                      or song.selected_instrument_index
  local current_labels = labeler.saved_labels_by_instrument[current_index] or {}
  
  local used_labels = {}
  local ghost_labels = {}
  
  for hex_key, label_data in pairs(current_labels) do
    if label_data.label and label_data.label ~= "---------" then
      used_labels[label_data.label] = true
      if label_data.ghost_note then
        ghost_labels[label_data.label] = true
      end
    end
    if label_data.label2 and label_data.label2 ~= "---------" then
      used_labels[label_data.label2] = true
      if label_data.ghost_note then
        ghost_labels[label_data.label2] = true
      end
    end
  end
  
  return used_labels, ghost_labels
end

local function get_label_instance_counts()
  local song = renoise.song()
  local current_index = labeler.is_locked and labeler.locked_instrument_index 
                      or song.selected_instrument_index
  local current_labels = labeler.saved_labels_by_instrument[current_index] or {}
  
  local regular_counts = {}
  local ghost_counts = {}
  
  for hex_key, label_data in pairs(current_labels) do
    -- Count primary labels
    if label_data.label and label_data.label ~= "---------" then
      if label_data.ghost_note then
        -- Ghost notes only count toward ghost mappings
        ghost_counts[label_data.label] = (ghost_counts[label_data.label] or 0) + 1
      else
        -- Regular notes only count toward regular mappings
        regular_counts[label_data.label] = (regular_counts[label_data.label] or 0) + 1
      end
    end
    
    -- Count secondary labels
    if label_data.label2 and label_data.label2 ~= "---------" then
      if label_data.ghost_note then
        -- Ghost notes only count toward ghost mappings
        ghost_counts[label_data.label2] = (ghost_counts[label_data.label2] or 0) + 1
      else
        -- Regular notes only count toward regular mappings
        regular_counts[label_data.label2] = (regular_counts[label_data.label2] or 0) + 1
      end
    end
  end
  
  return regular_counts, ghost_counts
end

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

local function get_current_mappings()
  local song = renoise.song()
  local current_index = labeler.is_locked and labeler.locked_instrument_index 
                      or song.selected_instrument_index
  local stored_data = labeler.saved_labels_by_instrument[current_index] or {}
  
  return stored_data.mappings or {}
end

local function save_mappings(mappings)
  local song = renoise.song()
  local current_index = labeler.is_locked and labeler.locked_instrument_index 
                      or song.selected_instrument_index
  
  if not labeler.saved_labels_by_instrument[current_index] then
    labeler.saved_labels_by_instrument[current_index] = {}
  end
  
  labeler.saved_labels_by_instrument[current_index].mappings = mappings
end

function mapper.create_ui(closed_callback)
  if dialog and dialog.visible then
    dialog:close()
    dialog = nil
  end
  
  mapper.dialog_closed_callback = closed_callback
  
  local vb = renoise.ViewBuilder()
  local used_labels, ghost_labels = get_used_labels()
  local regular_counts, ghost_counts = get_label_instance_counts()
  local track_options = get_track_options()
  local instrument_options = get_instrument_options()
  local current_mappings = get_current_mappings()
  
  if not next(used_labels) then
    renoise.app():show_warning("No labels found. Please create and save labels first.")
    return
  end
  
  -- Initialize mappings structure if empty
  for label in pairs(used_labels) do
    if not current_mappings[label] then
      current_mappings[label] = {
        regular = {},
        ghost = {}
      }
    end
  end
  
  local dialog_content = vb:column {
    margin = 5,
    spacing = 8
  }
  
  -- Title
  dialog_content:add_child(vb:text {
    text = "Label Track Mapping",
    font = "big",
    style = "strong"
  })
  
  -- Create sections for each label organized in columns
  local sorted_labels = {}
  for label in pairs(used_labels) do
    table.insert(sorted_labels, label)
  end
  table.sort(sorted_labels)
  
  -- Organize labels into columns (max 3 labels per column)
  local labels_per_column = 3
  local num_columns = math.ceil(#sorted_labels / labels_per_column)
  
  local columns_container = vb:row {
    spacing = 10
  }
  
  for col = 1, num_columns do
    local column = vb:column {
      spacing = 8
    }
    
    local start_idx = (col - 1) * labels_per_column + 1
    local end_idx = math.min(col * labels_per_column, #sorted_labels)
    
    for i = start_idx, end_idx do
      local label = sorted_labels[i]
    local label_section = vb:column {
      style = "panel",
      margin = 5,
      spacing = 5
    }
    
    -- Label title
    label_section:add_child(vb:text {
      text = "Label: " .. label,
      font = "bold"
    })
    
    -- Regular mappings section
    local regular_section = vb:column {
      spacing = 3
    }
    
    regular_section:add_child(vb:text {
      text = "Regular Mappings:",
      style = "strong"
    })
    
    local regular_container = vb:column {
      id = "regular_" .. label:gsub("%s", "_"),
      spacing = 3
    }
    
    -- Add existing regular mappings
    for i, mapping in ipairs(current_mappings[label].regular) do
      local mapping_row = vb:row {
        spacing = 10,
        vb:text { text = "Track:", width = 40 },
        vb:popup {
          id = string.format("track_regular_%s_%d", label:gsub("%s", "_"), i),
          items = track_options,
          value = mapping.track_index or 1,
          width = 150
        },
        vb:text { text = "Inst:", width = 30 },
        vb:popup {
          id = string.format("inst_regular_%s_%d", label:gsub("%s", "_"), i),
          items = instrument_options,
          value = (mapping.instrument_index or 0) + 1,
          width = 150
        },
        vb:button {
          text = "[-]",
          width = 25,
          notifier = function()
            -- Remove this mapping and rebuild dialog
            table.remove(current_mappings[label].regular, i)
            save_mappings(current_mappings)
            dialog:close()
            mapper.create_ui(mapper.dialog_closed_callback)
          end
        }
      }
      regular_container:add_child(mapping_row)
    end
    
    -- Add button for regular mappings
    local max_regular = regular_counts[label] or 0
    regular_container:add_child(vb:button {
      text = string.format("[+] Add Regular Mapping (%d/%d)", #current_mappings[label].regular, max_regular),
      width = 200,
      notifier = function()
        if #current_mappings[label].regular < max_regular then
          -- Collect current UI state first
          local updated_mappings = {}
          for lbl in pairs(used_labels) do
            updated_mappings[lbl] = { regular = {}, ghost = {} }
            
            -- Collect regular mappings
            for i = 1, #current_mappings[lbl].regular do
              local track_popup = vb.views[string.format("track_regular_%s_%d", lbl:gsub("%s", "_"), i)]
              local inst_popup = vb.views[string.format("inst_regular_%s_%d", lbl:gsub("%s", "_"), i)]
              
              if track_popup and inst_popup then
                local track_str = track_popup.items[track_popup.value]
                local track_index = tonumber(track_str:match("^(%d+):"))
                
                table.insert(updated_mappings[lbl].regular, {
                  track_index = track_index,
                  instrument_index = inst_popup.value - 1
                })
              end
            end
            
            -- Collect ghost mappings
            if ghost_labels[lbl] then
              for i = 1, #current_mappings[lbl].ghost do
                local track_popup = vb.views[string.format("track_ghost_%s_%d", lbl:gsub("%s", "_"), i)]
                local inst_popup = vb.views[string.format("inst_ghost_%s_%d", lbl:gsub("%s", "_"), i)]
                
                if track_popup and inst_popup then
                  local track_str = track_popup.items[track_popup.value]
                  local track_index = tonumber(track_str:match("^(%d+):"))
                  
                  table.insert(updated_mappings[lbl].ghost, {
                    track_index = track_index,
                    instrument_index = inst_popup.value - 1
                  })
                end
              end
            end
          end
          
          -- Add new regular mapping
          table.insert(updated_mappings[label].regular, {
            track_index = 1,
            instrument_index = 0
          })
          
          save_mappings(updated_mappings)
          dialog:close()
          mapper.create_ui(mapper.dialog_closed_callback)
        else
          renoise.app():show_warning(string.format("Maximum of %d regular mappings reached for label '%s' (%d regular instances in slices).", 
                                                   max_regular, label, max_regular))
        end
      end
    })
    
    regular_section:add_child(regular_container)
    label_section:add_child(regular_section)
    
    -- Ghost mappings section (only if this label has ghost notes)
    if ghost_labels[label] then
      local ghost_section = vb:column {
        spacing = 3
      }
      
      ghost_section:add_child(vb:space { height = 3 })
      ghost_section:add_child(vb:text {
        text = "Ghost Mappings:",
        style = "strong"
      })
      
      local ghost_container = vb:column {
        id = "ghost_" .. label:gsub("%s", "_"),
        spacing = 3
      }
      
      -- Add existing ghost mappings
      for i, mapping in ipairs(current_mappings[label].ghost) do
        local mapping_row = vb:row {
          spacing = 10,
          vb:text { text = "Track:", width = 40 },
          vb:popup {
            id = string.format("track_ghost_%s_%d", label:gsub("%s", "_"), i),
            items = track_options,
            value = mapping.track_index or 1,
            width = 150
          },
          vb:text { text = "Inst:", width = 30 },
          vb:popup {
            id = string.format("inst_ghost_%s_%d", label:gsub("%s", "_"), i),
            items = instrument_options,
            value = (mapping.instrument_index or 0) + 1,
            width = 150
          },
          vb:button {
            text = "[-]",
            width = 25,
            notifier = function()
              -- Remove this mapping and rebuild dialog
              table.remove(current_mappings[label].ghost, i)
              save_mappings(current_mappings)
              dialog:close()
              mapper.create_ui(mapper.dialog_closed_callback)
            end
          }
        }
        ghost_container:add_child(mapping_row)
      end
      
      -- Add button for ghost mappings
      local max_ghost = ghost_counts[label] or 0
      ghost_container:add_child(vb:button {
        text = string.format("[+] Add Ghost Mapping (%d/%d)", #current_mappings[label].ghost, max_ghost),
        width = 200,
        notifier = function()
          if #current_mappings[label].ghost < max_ghost then
            table.insert(current_mappings[label].ghost, {
              track_index = 1,
              instrument_index = 0
            })
            save_mappings(current_mappings)
            dialog:close()
            mapper.create_ui(mapper.dialog_closed_callback)
          else
            renoise.app():show_warning(string.format("Maximum of %d ghost mappings reached for label '%s' (%d ghost instances in slices).", 
                                                     max_ghost, label, max_ghost))
          end
        end
      })
      
      ghost_section:add_child(ghost_container)
      label_section:add_child(ghost_section)
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
          current_mappings[label] = {
            regular = {},
            ghost = {}
          }
        end
        save_mappings(current_mappings)
        dialog:close()
        mapper.create_ui(mapper.dialog_closed_callback)
      end
    },
    vb:button {
      text = "Cancel",
      notifier = function()
        if dialog and dialog.visible then
          dialog:close()
          dialog = nil
        end
        if mapper.dialog_closed_callback then
          mapper.dialog_closed_callback()
        end
      end
    },
    vb:button {
      text = "Save Mappings",
      notifier = function()
        -- Collect all mapping data from UI
        local final_mappings = {}
        
        for label in pairs(used_labels) do
          final_mappings[label] = {
            regular = {},
            ghost = {}
          }
          
          -- Collect regular mappings
          for i = 1, #current_mappings[label].regular do
            local track_popup = vb.views[string.format("track_regular_%s_%d", label:gsub("%s", "_"), i)]
            local inst_popup = vb.views[string.format("inst_regular_%s_%d", label:gsub("%s", "_"), i)]
            
            if track_popup and inst_popup then
              -- Extract track index from "1: Track Name" format
              local track_str = track_popup.items[track_popup.value]
              local track_index = tonumber(track_str:match("^(%d+):"))
              
              table.insert(final_mappings[label].regular, {
                track_index = track_index,
                instrument_index = inst_popup.value - 1  -- Convert to 0-based
              })
            end
          end
          
          -- Collect ghost mappings (if section exists)
          if ghost_labels[label] then
            for i = 1, #current_mappings[label].ghost do
              local track_popup = vb.views[string.format("track_ghost_%s_%d", label:gsub("%s", "_"), i)]
              local inst_popup = vb.views[string.format("inst_ghost_%s_%d", label:gsub("%s", "_"), i)]
              
              if track_popup and inst_popup then
                -- Extract track index from "1: Track Name" format
                local track_str = track_popup.items[track_popup.value]
                local track_index = tonumber(track_str:match("^(%d+):"))
                
                table.insert(final_mappings[label].ghost, {
                  track_index = track_index,
                  instrument_index = inst_popup.value - 1  -- Convert to 0-based
                })
              end
            end
          end
        end
        
        save_mappings(final_mappings)
        
        if dialog and dialog.visible then
          dialog:close()
          dialog = nil
        end
        
        if mapper.dialog_closed_callback then
          mapper.dialog_closed_callback()
        end
        
        renoise.app():show_status("Mappings saved successfully")
      end
    }
  })
  
  dialog = renoise.app():show_custom_dialog("Label Track Mapping", dialog_content)
end

return mapper