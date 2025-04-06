-- main.lua
local labeler = require("labeler")
local utils = require("utils")
local rerender = require("rerender")
local swapper = require("swapper")

--------------------------------------------------------------------------------
-- Dialog Management
--------------------------------------------------------------------------------

-- Store dialog reference
local main_dialog = nil
local render_config_dialog = nil

local function update_lock_state(dialog_vb)
  local song = renoise.song()
  local instrument_selector = dialog_vb.views.instrument_index
  local lock_button = dialog_vb.views.lock_button
  
  if instrument_selector and lock_button then
      instrument_selector.active = not labeler.is_locked
      lock_button.text = labeler.is_locked and "[-]" or "[O]"
      
      if not labeler.is_locked then
          local new_index = song.selected_instrument_index - 1
          if new_index > instrument_selector.max then
              new_index = instrument_selector.max
          elseif new_index < instrument_selector.min then
              new_index = instrument_selector.min
          end
          instrument_selector.value = new_index
      end
  end
end

local function show_render_config_dialog()
  if not main_dialog or not main_dialog.visible then
    return
  end

  local vb = renoise.ViewBuilder()
  local song = renoise.song()
  local pattern_info = rerender.get_current_pattern_info()
  
  local sample_rates = {"22050", "44100", "48000", "88200", "96000", "192000"}
  local default_rate_index = 1

  local current_sample_rate = 44100 -- fallback default
  if labeler.is_locked and labeler.locked_instrument_index then
    local source_instrument = song:instrument(labeler.locked_instrument_index)
    if source_instrument and #source_instrument.samples > 0 then
      current_sample_rate = source_instrument.samples[1].sample_buffer.sample_rate
    end
  end  

  for i, rate in ipairs(sample_rates) do
    if tonumber(rate) == rerender.config.sample_rate then
      default_rate_index = i
      break
    end
  end

  rerender.config.sample_rate = current_sample_rate
  
  local bit_depths = {"16", "24", "32"}
  local default_depth_index = 3 -- 32-bit default
  
  local dialog_content = vb:column {
    margin = 10,
    spacing = 10,
    
    vb:row {
      spacing = 10,
      vb:column {
        vb:text { text = "Start Sequence:" },
        vb:valuebox {
          min = 1,
          max = #song.sequencer.pattern_sequence,
          value = pattern_info.pattern_index,
          notifier = function(value)
            rerender.config.start_sequence = value
          end
        }
      },
      vb:column {
        vb:text { text = "End Sequence:" },
        vb:valuebox {
          min = 1,
          max = #song.sequencer.pattern_sequence,
          value = pattern_info.pattern_index,
          notifier = function(value)
            rerender.config.end_sequence = value
          end
        }
      }
    },
    
    vb:row {
      spacing = 10,
      vb:column {
        vb:text { text = "Start Line:" },
        vb:valuebox {
          min = 1,
          max = pattern_info.num_lines,
          value = rerender.config.start_line,
          notifier = function(value)
            rerender.config.start_line = value
          end
        }
      },
      vb:column {
        vb:text { text = "End Line:" },
        vb:valuebox {
          min = 1,
          max = pattern_info.num_lines,
          value = pattern_info.num_lines,
          notifier = function(value)
            rerender.config.end_line = value
          end
        }
      }
    },
    
    vb:row {
      spacing = 10,
      vb:column {
        vb:text { text = "Sample Rate:" },
        vb:popup {
          items = sample_rates,
          value = default_rate_index,
          notifier = function(index)
            rerender.config.sample_rate = tonumber(sample_rates[index])
          end
        }
      },
      vb:column {
        vb:text { text = "Bit Depth:" },
        vb:popup {
          items = bit_depths,
          value = default_depth_index,
          notifier = function(index)
            rerender.config.bit_depth = tonumber(bit_depths[index])
          end
        }
      }
    },

    vb:row {
      spacing = 10,
      vb:column {
        vb:text { text = "Slice Markers:" },
        vb:popup {
          width = 150,
          items = {"From Pattern Notes", "From Source Sample"},
          value = (rerender.config.marker_placement == "pattern") and 1 or 2,
          notifier = function(index)
            rerender.config.marker_placement = (index == 1) and "pattern" or "source"
          end
        }
      }
    },
    
    vb:space { height = 10 },
    
    vb:horizontal_aligner {
      mode = "right",
      spacing = 10,
      vb:button {
        text = "Cancel",
        notifier = function()
          if render_config_dialog and render_config_dialog.visible then
            render_config_dialog:close()
          end
        end
      },
      vb:button {
        text = "Save Settings",
        notifier = function()
          rerender.save_settings()
          if render_config_dialog and render_config_dialog.visible then
            render_config_dialog:close()
          end
          renoise.app():show_status("Render settings saved")
        end
      },
      vb:button {
        text = "Render",
        notifier = function()
          if render_config_dialog and render_config_dialog.visible then
            render_config_dialog:close()
          end
          rerender.render_current_pattern()
        end
      }
    }
  }
  
  render_config_dialog = renoise.app():show_custom_dialog(
    "Render Configuration", 
    dialog_content
  )
end

-- Store reference to phrase copy dialog
local phrase_copy_dialog = nil

local function show_phrase_copy_dialog()
  if not main_dialog or not main_dialog.visible then
    return
  end
  
  -- Close existing dialog if open
  if phrase_copy_dialog and phrase_copy_dialog.visible then
    phrase_copy_dialog:close()
  end
  
  local vb = renoise.ViewBuilder()
  local song = renoise.song()
  local phrase_options = {}
  local max_phrases = 1
  
  -- Check if an instrument is locked
  if not labeler.is_locked or not labeler.locked_instrument_index then
    renoise.app():show_warning("Please lock an instrument first to use this feature.")
    return
  end
  
  -- Get the source instrument
  local instrument = song:instrument(labeler.locked_instrument_index)
  max_phrases = #instrument.phrases
  
  if max_phrases == 0 then
    renoise.app():show_warning("The locked instrument has no phrases.")
    return
  end
  
  -- Populate phrase options
  for i = 1, max_phrases do
    local phrase_name = instrument.phrases[i].name
    if phrase_name == "" then
      phrase_name = string.format("Phrase %d", i)
    end
    table.insert(phrase_options, string.format("%d: %s", i, phrase_name))
  end
  
  -- Create track options
  local track_options = {}
  for i = 1, #song.tracks do
    if song.tracks[i].type == renoise.Track.TRACK_TYPE_SEQUENCER then
      table.insert(track_options, string.format("%d: %s", i, song.tracks[i].name))
    end
  end
  
  -- Dialog content
  local dialog_content = vb:column {
    margin = 10,
    spacing = 10,
    
    vb:text {
      text = "Copy Phrase to Track",
      font = "big",
      style = "strong"
    },
    
    vb:space { height = 5 },
    
    vb:row {
      spacing = 10,
      vb:text { text = "Source Phrase:" },
      vb:popup {
        id = "phrase_selector",
        width = 200,
        items = phrase_options,
        value = 1
      }
    },
    
    vb:row {
      spacing = 10,
      vb:text { text = "Target Track:" },
      vb:popup {
        id = "track_selector",
        width = 200,
        items = track_options,
        value = song.selected_track_index
      }
    },
    
    vb:row {
      spacing = 10,
      vb:checkbox {
        id = "clear_track",
        value = true
      },
      vb:text { text = "Clear destination track before copying" }
    },
    
    vb:row {
      spacing = 10,
      vb:checkbox {
        id = "adjust_pattern",
        value = false
      },
      vb:text { text = "Adjust pattern length to match phrase" }
    },
    
    vb:space { height = 10 },
    
    vb:horizontal_aligner {
      mode = "right",
      spacing = 10,
      vb:button {
        text = "Cancel",
        width = 90,
        notifier = function()
          if phrase_copy_dialog and phrase_copy_dialog.visible then
            phrase_copy_dialog:close()
          end
        end
      },
      vb:button {
        text = "Copy",
        width = 90,
        notifier = function()
          local phrase_selector = vb.views.phrase_selector
          local track_selector = vb.views.track_selector
          local clear_track = vb.views.clear_track.value
          local adjust_pattern = vb.views.adjust_pattern.value
          
          -- Extract actual indices from selections
          local phrase_index = phrase_selector.value
          local track_index_str = track_selector.items[track_selector.value]
          local track_index = tonumber(track_index_str:match("^(%d+):"))
          
          -- Use the swapper function with the additional options
          local success = swapper.copy_phrase_to_track(
            phrase_index, 
            track_index, 
            {
              clear_track = clear_track,
              adjust_pattern = adjust_pattern
            }
          )
          
          if success and phrase_copy_dialog and phrase_copy_dialog.visible then
            phrase_copy_dialog:close()
          end
        end
      }
    }
  }
  
  phrase_copy_dialog = renoise.app():show_custom_dialog(
    "Phrase to Track Copy", 
    dialog_content
  )
end

local function create_main_dialog()
  if main_dialog and main_dialog.visible then
    main_dialog:close()
  end

  local vb = renoise.ViewBuilder()
  local song = renoise.song()  

  labeler.lock_state_observable:add_notifier(function()
    if main_dialog and main_dialog.visible then
        update_lock_state(vb)
    end
  end)
  
  local dialog_content = vb:column {
    margin = 10,
    spacing = 10,
    
    vb:row {
        vb:text {
            text = "Instrument Index:",
            font = "big",
            style = "strong"
        },
        vb:valuebox {
          id = 'instrument_index',
          min = 0,
          max = #song.instruments - 1,
          value = (labeler.locked_instrument_index or song.selected_instrument_index) - 1,
          active = not labeler.is_locked,
          tostring = function(value) 
              return string.format("%02X", value)
          end,
          tonumber = function(str)
              return tonumber(str, 16)
          end,
          notifier = function(value)
              if not labeler.is_locked then
                  song.selected_instrument_index = value + 1
              end
          end
        },
        vb:button {
          id = 'lock_button',
          text = labeler.is_locked and "[-]" or "[O]",
          notifier = function()
            labeler.is_locked = not labeler.is_locked
            if labeler.is_locked then
                labeler.locked_instrument_index = song.selected_instrument_index
            else
                labeler.locked_instrument_index = nil
                local instrument_selector = vb.views.instrument_index
                if instrument_selector then
                    local new_index = song.selected_instrument_index - 1
                    if new_index <= instrument_selector.max and new_index >= instrument_selector.min then
                        instrument_selector.value = new_index
                    end
                end
            end
            labeler.lock_state_observable.value = not labeler.lock_state_observable.value
            update_lock_state(vb)
          end
        },
        vb:text {
          text = "Lock",
          font = "big",
          style = "strong"
        },
    },
    
    vb:horizontal_aligner {
      mode = "center",
      margin = 10,
      
      vb:column {
        style = "panel",
        margin = 10,
        spacing = 10,
        width = 200,
        
        
        vb:button {
          text = "Label Editor",
          width = "100%",
          height = 30,
          notifier = function()
            labeler.create_ui(function()
              -- When labeler closes, show main dialog again
              if not main_dialog or not main_dialog.visible then
                create_main_dialog()
              end
            end)
            -- Close the main dialog when opening the labeler
            if main_dialog and main_dialog.visible then
              main_dialog:close()
            end
          end
        },
        
        vb:button {
          text = "Import Labels",
          width = "100%",
          height = 30,
          notifier = function()
            labeler.import_labels()
          end
        },
        
        vb:button {
          text = "Export Labels",
          width = "100%",
          height = 30,
          notifier = function()
            labeler.export_labels()
          end
        },
        
        vb:button {
          text = "Place Notes",
          width = "100%",
          height = 30,
          notifier = function()
            swapper.place_notes_on_matching_tracks(1)
          end
        },

        vb:button {
          text = "Rerender",
          width = "100%",
          height = 30,
          notifier = function()
            rerender.render_current_pattern()
          end
        },
        vb:button {
          text = "Render Config",
          width = "100%",
          height = 30,
          notifier = function()
            show_render_config_dialog()
          end
        },
        
        vb:space { height = 10 },
        
        vb:button {
          text = "Phrase to Track",
          width = "100%",
          height = 30,
          notifier = function()
            show_phrase_copy_dialog()
          end
        }
      }
    }
  }

  song.selected_instrument_observable:add_notifier(function()
    if not labeler.is_locked and main_dialog and main_dialog.visible then
        local instrument_selector = vb.views.instrument_index
        if instrument_selector then
            local new_index = song.selected_instrument_index - 1
            if new_index <= instrument_selector.max and new_index >= instrument_selector.min then
                instrument_selector.value = new_index
            end
        end
    end
  end)
  
  main_dialog = renoise.app():show_custom_dialog("HotSwap", dialog_content)
end

local function find_instruments_by_label(song, label, is_ghost)
  local matching_instruments = {}
  local label_lower = string.lower(label)
  
  for i = 1, #song.instruments do
    local instrument = song.instruments[i]
    local instrument_name = string.lower(instrument.name)
    
    if is_ghost then
      if string.find(instrument_name, "_" .. label_lower .. "_ghost") then
        table.insert(matching_instruments, i - 1)  -- Instrument indices are 0-based
      end
    else
      if string.find(instrument_name, label_lower) and 
         (string.match(instrument_name, "^_") or string.match(instrument_name, "%s_")) and
         not string.find(instrument_name, "_ghost") then
        table.insert(matching_instruments, i - 1)
      end
    end
  end
  return matching_instruments
end

-- Tool Registration
labeler.set_show_dialog_callback(function()
  if main_dialog and main_dialog.visible then
    main_dialog:close()
  end
  labeler.create_ui()
end)

renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:HotSwap",
  invoke = create_main_dialog
}

renoise.tool():add_keybinding {
  name = "Global:Tools:Show HotSwap",
  invoke = create_main_dialog
}

-- Cleanup

local tool = renoise.tool()
tool.app_new_document_observable:add_notifier(function()
  if main_dialog and main_dialog.visible then
    main_dialog:close()
  end
  labeler.cleanup()
end)

tool.app_release_document_observable:add_notifier(function()
  if main_dialog and main_dialog.visible then
    main_dialog:close()
  end
  labeler.cleanup()
end) 