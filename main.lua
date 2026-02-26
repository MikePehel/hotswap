-- main.lua
local labeler = require("labeler")
local utils = require("utils")
local rerender = require("rerender")
local swapper = require("swapper")
local mapper = require("mapper")

--------------------------------------------------------------------------------
-- Dialog Management
--------------------------------------------------------------------------------

-- Store dialog reference
local main_dialog = nil

-- Observable stacking guards
local lock_notifier_added = false
local instrument_notifier_added = false

local function update_lock_state(dialog_vb)
  local song = renoise.song()
  local instrument_selector = dialog_vb.views.instrument_index
  local lock_button = dialog_vb.views.lock_button

  if instrument_selector and lock_button then
      instrument_selector.active = not labeler.is_locked
      lock_button.text = labeler.is_locked and "Lock" or "Unlock"

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

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

local function get_track_options()
  local song = renoise.song()
  local track_options = {}
  for i = 1, #song.tracks do
    if song.tracks[i].type == renoise.Track.TRACK_TYPE_SEQUENCER then
      table.insert(track_options, string.format("%d: %s", i, song.tracks[i].name))
    end
  end
  return track_options
end

local function find_rate_index(rate)
  local rates = {22050, 44100, 48000, 88200, 96000, 192000}
  for i, r in ipairs(rates) do
    if r == rate then return i end
  end
  return 2 -- default to 44100
end

local function find_depth_index(depth)
  local depths = {16, 24, 32}
  for i, d in ipairs(depths) do
    if d == depth then return i end
  end
  return 3 -- default to 32
end

local function refresh_render_tab(vb)
  local song = renoise.song()
  local pattern_info = rerender.get_current_pattern_info()
  vb.views.render_start_seq.max = #song.sequencer.pattern_sequence
  vb.views.render_end_seq.max = #song.sequencer.pattern_sequence
  vb.views.render_start_line.max = pattern_info.num_lines
  vb.views.render_end_line.max = pattern_info.num_lines
end

local function update_status_line(vb)
  local status_view = vb.views.status_line
  if not status_view then return end

  local song = renoise.song()
  local current_index = labeler.is_locked and labeler.locked_instrument_index
    or song.selected_instrument_index

  local label_count = 0
  local mapping_count = 0

  local instrument_data = labeler.saved_labels_by_instrument[current_index]
  if instrument_data then
    if instrument_data.labels then
      for _ in pairs(instrument_data.labels) do
        label_count = label_count + 1
      end
    end
    if instrument_data.mappings then
      for _ in pairs(instrument_data.mappings) do
        mapping_count = mapping_count + 1
      end
    end
  end

  status_view.text = string.format(
    "Labels: %d saved  |  Mappings: %d configured",
    label_count, mapping_count
  )
end

--------------------------------------------------------------------------------
-- Sub-Dialogs (Phrase Copy, Track Copy)
--------------------------------------------------------------------------------

-- Store reference to phrase copy dialog
local phrase_copy_dialog = nil

local function show_phrase_copy_dialog()
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
  local track_options = get_track_options()

  -- Dialog content
  local dialog_content = vb:column {
    margin = 12,
    spacing = 10,

    vb:text {
      text = "Advanced Phrase to Track Copy",
      font = "big",
      style = "strong"
    },

    vb:text {
      text = "Copy phrase note data to a pattern track with timing options.",
      style = "disabled"
    },

    vb:row {
      spacing = 10,
      vb:text { text = "Source Phrase:", width = 120, align = "right" },
      vb:popup {
        id = "source_phrase_selector",
        width = 200,
        items = phrase_options,
        value = 1
      }
    },

    vb:row {
      spacing = 10,
      vb:text { text = "Transfer Phrase:", width = 120, align = "right" },
      vb:popup {
        id = "transfer_phrase_selector",
        width = 200,
        items = phrase_options,
        value = 1
      }
    },

    vb:row {
      spacing = 10,
      vb:text { text = "Target Track:", width = 120, align = "right" },
      vb:popup {
        id = "track_selector",
        width = 200,
        items = track_options,
        value = math.min(song.selected_track_index, #track_options)
      }
    },

    vb:row {
      spacing = 10,
      vb:text { text = "Overflow Mode:", width = 120, align = "right" },
      vb:popup {
        id = "overflow_mode",
        width = 200,
        items = {"Truncate", "Overflow", "Condense"},
        value = 1,
        tooltip = "Truncate: cut notes exceeding pattern length. Overflow: extend into next pattern. Condense: fit notes into available space."
      }
    },

    vb:row {
      spacing = 10,
      vb:text { text = "Pattern Length:", width = 120, align = "right" },
      vb:popup {
        id = "pattern_length_mode",
        width = 200,
        items = {"No Change", "Match Source", "Match Transfer"},
        value = 1,
        tooltip = "No Change: keep current length. Match Source: resize to source phrase length. Match Transfer: resize to transfer phrase length."
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

    vb:space { height = 10 },

    vb:horizontal_aligner {
      mode = "right",
      spacing = 8,
      vb:button {
        text = "Cancel",
        width = 100,
        tooltip = "Close without copying",
        notifier = function()
          if phrase_copy_dialog and phrase_copy_dialog.visible then
            phrase_copy_dialog:close()
          end
        end
      },
      vb:button {
        text = "Copy",
        width = 100,
        tooltip = "Copy phrase data to the selected track",
        notifier = function()
          local source_phrase_selector = vb.views.source_phrase_selector
          local transfer_phrase_selector = vb.views.transfer_phrase_selector
          local track_selector = vb.views.track_selector
          local overflow_mode = vb.views.overflow_mode
          local pattern_length_mode = vb.views.pattern_length_mode
          local clear_track = vb.views.clear_track.value

          -- Extract actual indices from selections
          local source_phrase_index = source_phrase_selector.value
          local transfer_phrase_index = transfer_phrase_selector.value
          local track_index_str = track_selector.items[track_selector.value]
          local track_index = tonumber(track_index_str:match("^(%d+):"))

          -- Map overflow mode
          local overflow_modes = {"truncate", "overflow", "condense"}
          local selected_overflow_mode = overflow_modes[overflow_mode.value]

          -- Map pattern length mode
          local pattern_length_modes = {"none", "source", "transfer"}
          local selected_pattern_length_mode = pattern_length_modes[pattern_length_mode.value]

          -- Use the swapper function with all the advanced options
          local success = swapper.copy_phrase_to_track(
            transfer_phrase_index, -- This becomes the main phrase_index for backward compatibility
            track_index,
            {
              source_phrase_index = source_phrase_index,
              transfer_phrase_index = transfer_phrase_index,
              clear_track = clear_track,
              overflow_mode = selected_overflow_mode,
              pattern_length_mode = selected_pattern_length_mode
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
    "Advanced Phrase to Track Copy",
    dialog_content
  )
end

-- Store reference to track copy dialog
local track_copy_dialog = nil

local function show_track_copy_dialog()
  -- Close existing dialog if open
  if track_copy_dialog and track_copy_dialog.visible then
    track_copy_dialog:close()
  end

  local vb = renoise.ViewBuilder()
  local song = renoise.song()

  -- Check if an instrument is locked
  if not labeler.is_locked or not labeler.locked_instrument_index then
    renoise.app():show_warning("Please lock an instrument first to use this feature.")
    return
  end

  -- Get the locked instrument
  local instrument = song:instrument(labeler.locked_instrument_index)
  local max_phrases = #instrument.phrases

  if max_phrases == 0 then
    renoise.app():show_warning("The locked instrument has no phrases.")
    return
  end

  -- Populate phrase options
  local phrase_options = {}
  for i = 1, max_phrases do
    local phrase_name = instrument.phrases[i].name
    if phrase_name == "" then
      phrase_name = string.format("Phrase %d", i)
    end
    table.insert(phrase_options, string.format("%d: %s", i, phrase_name))
  end

  -- Create track options
  local track_options = get_track_options()

  -- Dialog content
  local dialog_content = vb:column {
    margin = 12,
    spacing = 10,

    vb:text {
      text = "Track to Phrase Copy",
      font = "big",
      style = "strong"
    },

    vb:text {
      text = "Convert pattern track notes into a phrase on the locked instrument.",
      style = "disabled"
    },

    vb:row {
      spacing = 10,
      vb:text { text = "Source Track:", width = 120, align = "right" },
      vb:popup {
        id = "track_selector",
        width = 200,
        items = track_options,
        value = song.selected_track_index
      }
    },

    vb:row {
      spacing = 10,
      vb:text { text = "Conversion Mode:", width = 120, align = "right" },
      vb:popup {
        id = "conversion_mode",
        width = 200,
        items = {
          "Note Mode",
          "Mapping Mode"
        },
        value = 1,
        tooltip = "Note Mode: maps C-2 to Sample 1, C#2 to Sample 2, etc. Mapping Mode: uses existing HotSwap label-to-track mappings."
      }
    },

    vb:space { height = 10 },

    vb:horizontal_aligner {
      mode = "right",
      spacing = 8,
      vb:button {
        text = "Cancel",
        width = 100,
        tooltip = "Close without copying",
        notifier = function()
          if track_copy_dialog and track_copy_dialog.visible then
            track_copy_dialog:close()
          end
        end
      },
      vb:button {
        text = "Copy",
        width = 100,
        tooltip = "Convert the selected track into a phrase",
        notifier = function()
          local track_selector = vb.views.track_selector
          local conversion_mode_popup = vb.views.conversion_mode

          -- Extract actual indices from selections
          local track_index_str = track_selector.items[track_selector.value]
          local track_index = tonumber(track_index_str:match("^(%d+):"))

          -- Determine conversion mode
          local conversion_mode = (conversion_mode_popup.value == 1) and "note" or "mapping"

          -- Use the swapper function
          local success = swapper.copy_track_to_phrase(
            track_index,
            conversion_mode,
            {}
          )

          if success and track_copy_dialog and track_copy_dialog.visible then
            track_copy_dialog:close()
          end
        end
      }
    }
  }


  track_copy_dialog = renoise.app():show_custom_dialog(
    "Track to Phrase Copy",
    dialog_content
  )
end

--------------------------------------------------------------------------------
-- Main Dialog
--------------------------------------------------------------------------------

local function create_main_dialog()
  if main_dialog and main_dialog.visible then
    main_dialog:close()
  end

  local vb = renoise.ViewBuilder()
  local song = renoise.song()
  local pattern_info = rerender.get_current_pattern_info()

  if not lock_notifier_added then
    labeler.lock_state_observable:add_notifier(function()
      if main_dialog and main_dialog.visible then
          update_lock_state(vb)
          update_status_line(vb)
      end
    end)
    lock_notifier_added = true
  end

  -- Tag Tab
  local tag_tab = vb:column {
    id = "tab_tag",
    visible = true,
    spacing = 10,
    margin = 10,

    vb:button {
      text = "Label Editor",
      width = 300, height = 30,
      tooltip = "Open the slice label editor for the current instrument",
      notifier = function() labeler.create_ui() end
    },
    vb:space { height = 5 },
    vb:text { text = "Import / Export", style = "strong" },
    vb:row {
      spacing = 8,
      vb:button { text = "Import", width = 95, height = 28,
        tooltip = "Import labels from CSV or JSON",
        notifier = function() labeler.import_labels() end },
      vb:button { text = "Export CSV", width = 95, height = 28,
        tooltip = "Export labels as BreakPal-compatible CSV",
        notifier = function() labeler.export_labels() end },
      vb:button { text = "Export JSON", width = 95, height = 28,
        tooltip = "Export labels as JSON with full metadata",
        notifier = function() labeler.export_labels_json() end },
    }
  }

  -- Map Tab
  local map_tab = vb:column {
    id = "tab_map",
    visible = false,
    spacing = 10,
    margin = 10,

    vb:button {
      text = "Track Mapping Editor",
      width = 300, height = 30,
      tooltip = "Open the label-to-track mapping editor",
      notifier = function() mapper.create_ui() end
    },
    vb:space { height = 5 },
    vb:text { text = "Import / Export", style = "strong" },
    vb:row {
      spacing = 8,
      vb:button { text = "Import", width = 145, height = 28,
        tooltip = "Import track mappings from JSON",
        notifier = function() labeler.import_mappings() end },
      vb:button { text = "Export", width = 145, height = 28,
        tooltip = "Export track mappings to JSON",
        notifier = function() labeler.export_mappings() end },
    }
  }

  -- Swap Tab
  local swap_tab = vb:column {
    id = "tab_swap",
    visible = false,
    spacing = 10,
    margin = 10,

    vb:text { text = "Place Notes", style = "strong" },
    vb:button {
      text = "Place Notes on Matching Tracks",
      width = 300, height = 30,
      tooltip = "Distribute source pattern notes to mapped tracks based on labels",
      notifier = function() swapper.place_notes_on_matching_tracks(1) end
    },

    vb:space { height = 10 },
    vb:text { text = "Linear Swap", style = "strong" },
    vb:row {
      spacing = 8,
      vb:text { text = "Track:", width = 40 },
      vb:popup {
        id = "linear_swap_track",
        width = 180,
        items = get_track_options(),
        value = math.min(song.selected_track_index, math.max(1, #get_track_options()))
      },
      vb:button {
        text = "Execute",
        width = 70, height = 28,
        tooltip = "Replace all notes in track with C-4 using sequential instruments",
        notifier = function()
          local popup = vb.views.linear_swap_track
          local track_str = popup.items[popup.value]
          local track_index = tonumber(track_str:match("^(%d+):"))
          if track_index then
            swapper.linear_swap(track_index)
          end
        end
      }
    },

    vb:space { height = 10 },
    vb:text { text = "Advanced", style = "strong" },
    vb:row {
      spacing = 8,
      vb:button {
        text = "Phrase to Track...",
        width = 145, height = 28,
        tooltip = "Copy phrase note data to a pattern track (opens dialog)",
        notifier = function() show_phrase_copy_dialog() end
      },
      vb:button {
        text = "Track to Phrase...",
        width = 145, height = 28,
        tooltip = "Convert pattern track into an instrument phrase (opens dialog)",
        notifier = function() show_track_copy_dialog() end
      }
    }
  }

  -- Render Tab
  local render_tab = vb:column {
    id = "tab_render",
    visible = false,
    spacing = 8,
    margin = 10,

    vb:text { text = "Range", style = "strong" },
    vb:row {
      spacing = 10,
      vb:column {
        vb:text { text = "Start Seq" },
        vb:valuebox { id = "render_start_seq", min = 1,
          max = #song.sequencer.pattern_sequence,
          value = rerender.config.start_sequence or 1,
          notifier = function(v) rerender.config.start_sequence = v end }
      },
      vb:column {
        vb:text { text = "End Seq" },
        vb:valuebox { id = "render_end_seq", min = 1,
          max = #song.sequencer.pattern_sequence,
          value = rerender.config.end_sequence or #song.sequencer.pattern_sequence,
          notifier = function(v) rerender.config.end_sequence = v end }
      }
    },
    vb:row {
      spacing = 10,
      vb:column {
        vb:text { text = "Start Line" },
        vb:valuebox { id = "render_start_line", min = 1,
          max = pattern_info.num_lines,
          value = rerender.config.start_line or 1,
          notifier = function(v) rerender.config.start_line = v end }
      },
      vb:column {
        vb:text { text = "End Line" },
        vb:valuebox { id = "render_end_line", min = 1,
          max = pattern_info.num_lines,
          value = rerender.config.end_line or pattern_info.num_lines,
          notifier = function(v) rerender.config.end_line = v end }
      }
    },

    vb:space { height = 5 },
    vb:text { text = "Format", style = "strong" },
    vb:row {
      spacing = 10,
      vb:column {
        vb:text { text = "Sample Rate" },
        vb:popup { id = "render_sample_rate",
          items = {"22050", "44100", "48000", "88200", "96000", "192000"},
          value = find_rate_index(rerender.config.sample_rate),
          notifier = function(v)
            local rates = {22050, 44100, 48000, 88200, 96000, 192000}
            rerender.config.sample_rate = rates[v]
          end }
      },
      vb:column {
        vb:text { text = "Bit Depth" },
        vb:popup { id = "render_bit_depth",
          items = {"16", "24", "32"},
          value = find_depth_index(rerender.config.bit_depth),
          notifier = function(v)
            local depths = {16, 24, 32}
            rerender.config.bit_depth = depths[v]
          end }
      }
    },

    vb:space { height = 5 },
    vb:text { text = "Markers", style = "strong" },
    vb:popup { id = "render_markers", width = 200,
      items = {"From Pattern Notes", "From Source Sample"},
      value = (rerender.config.marker_placement == "source") and 2 or 1,
      notifier = function(v)
        rerender.config.marker_placement = (v == 2) and "source" or "pattern"
      end },

    vb:space { height = 10 },
    vb:horizontal_aligner {
      mode = "right",
      spacing = 8,
      vb:button { text = "Save Settings", width = 100, height = 28,
        tooltip = "Save render settings for this session",
        notifier = function() rerender.save_settings() end },
      vb:button { text = "Render", width = 100, height = 28,
        tooltip = "Render the configured range to a new instrument",
        notifier = function()
          rerender.save_settings()
          rerender.render_current_pattern()
        end }
    }
  }

  local dialog_content = vb:column {
    margin = 12,
    spacing = 10,

    -- Instrument selector row
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
        tooltip = "Instrument index in hexadecimal (00-FF)",
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
        text = labeler.is_locked and "Lock" or "Unlock",
        tooltip = "Lock the instrument selector to keep it fixed while navigating",
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
    },

    -- Tab switch control
    vb:switch {
      id = "main_tabs",
      width = 360,
      items = {"Tag", "Map", "Swap", "Render"},
      value = 1,
      notifier = function(index)
        vb.views.tab_tag.visible = (index == 1)
        vb.views.tab_map.visible = (index == 2)
        vb.views.tab_swap.visible = (index == 3)
        vb.views.tab_render.visible = (index == 4)
        if index == 4 then refresh_render_tab(vb) end
        update_status_line(vb)
      end
    },

    -- Tab content panels
    tag_tab,
    map_tab,
    swap_tab,
    render_tab,

    -- Status line
    vb:text {
      id = "status_line",
      text = "",
      style = "disabled"
    }
  }

  if not instrument_notifier_added then
    song.selected_instrument_observable:add_notifier(function()
      if not labeler.is_locked and main_dialog and main_dialog.visible then
          local instrument_selector = vb.views.instrument_index
          if instrument_selector then
              local new_index = song.selected_instrument_index - 1
              if new_index <= instrument_selector.max and new_index >= instrument_selector.min then
                  instrument_selector.value = new_index
              end
          end
          update_status_line(vb)
      end
    end)
    instrument_notifier_added = true
  end

  main_dialog = renoise.app():show_custom_dialog("HotSwap", dialog_content)
  update_status_line(vb)
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
  lock_notifier_added = false
  instrument_notifier_added = false
  labeler.cleanup()
  mapper.cleanup()
end)

tool.app_release_document_observable:add_notifier(function()
  if main_dialog and main_dialog.visible then
    main_dialog:close()
  end
  lock_notifier_added = false
  instrument_notifier_added = false
  labeler.cleanup()
  mapper.cleanup()
end)
