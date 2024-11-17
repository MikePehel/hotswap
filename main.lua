-- main.lua
local vb = renoise.ViewBuilder()
local duplicator = require("duplicator")
local modifiers = require("modifiers")
local evaluators = require("evaluators")
local labeler = require("labeler")
local rollers = require("rollers") 
local shuffles = require("shuffles")

local dialog = nil

local function copy_and_modify_phrases(instrument_index)
  local song = renoise.song()
  local instrument = song:instrument(instrument_index)
  local phrases = instrument.phrases
  
  if #phrases < 1 then
    renoise.app():show_warning("No phrases found in the selected instrument.")
    return
  end
  
  local first_phrase = phrases[1]
  
  local new_phrases = duplicator.duplicate_phrases(instrument, first_phrase, 15)
  
  modifiers.modify_phrase_by_halves(new_phrases[15], 1, 2)
  modifiers.modify_phrase_by_halves(new_phrases[14], 2, 3)
  modifiers.modify_phrase_by_halves(new_phrases[13], 3, 4)
  modifiers.modify_phrase_by_section(new_phrases[12], 1, 4)
  modifiers.modify_phrase_by_section(new_phrases[11], 2, 4)
  modifiers.modify_phrase_by_section(new_phrases[10], 3, 4)
  modifiers.modify_phrase_by_section(new_phrases[9], 4, 4)
  modifiers.modify_phrase_by_section(new_phrases[8], 1, 8)
  modifiers.modify_phrase_by_section(new_phrases[7], 2, 8)
  modifiers.modify_phrase_by_section(new_phrases[6], 3, 8)
  modifiers.modify_phrase_by_section(new_phrases[5], 4, 8)
  modifiers.modify_phrase_by_section(new_phrases[4], 5, 8)
  modifiers.modify_phrase_by_section(new_phrases[3], 6, 8)
  modifiers.modify_phrase_by_section(new_phrases[2], 7, 8)
  modifiers.modify_phrase_by_section(new_phrases[1], 8, 8)
  
  renoise.app():show_status("Phrases copied and modified successfully.")

  return first_phrase, new_phrases[1]
end

local function evaluate_phrase(instrument_index)
  local song = renoise.song()
  local instrument = song:instrument(instrument_index)
  local phrases = instrument.phrases
  
  if #phrases < 1 then
    renoise.app():show_warning("No phrases found in the selected instrument.")
    return
  end
  
  local first_phrase = phrases[1]
  
  evaluators.evaluate_note_length(first_phrase)
end

local function modify_phrases_with_labels(instrument_index)
  local song = renoise.song()
  local instrument = song:instrument(instrument_index)
  local phrases = instrument.phrases
  
  if #phrases < 15 then
    renoise.app():show_warning("Not enough phrases found in the selected instrument. At least 15 phrases are required.")
    return
  end
  
  local original_phrase = phrases[1]
  
  for i = 15, 2, -1 do
    local copied_phrase = phrases[i]
    
    modifiers.modify_phrases_by_labels(copied_phrase, original_phrase, labeler.saved_labels)
    
    renoise.app():show_status(string.format("Phrase %d modified based on labels.", i))
  end
  
  renoise.app():show_status("All phrases modified based on labels successfully.")
end

local function create_roller_patterns(instrument_index)
  local song = renoise.song()
  local instrument = song:instrument(instrument_index)
  local phrases = instrument.phrases
  
  if #phrases < 1 then
    renoise.app():show_warning("No phrases found in the selected instrument.")
    return
  end
  
  local original_phrase = phrases[1]

  local new_phrases = rollers.create_alternating_patterns(instrument, original_phrase, labeler.saved_labels)

  rollers.show_results(new_phrases)

  
  renoise.app():show_status("Roller patterns created successfully.")
end

local function create_shuffle_patterns(instrument_index)
  local song = renoise.song()
  local instrument = song:instrument(instrument_index)
  local phrases = instrument.phrases
  
  if #phrases < 1 then
    renoise.app():show_warning("No phrases found in the selected instrument.")
    return
  end
  
  local original_phrase = phrases[1]

  local new_phrases = shuffles.create_shuffles(instrument, original_phrase, labeler.saved_labels)
  
  
  renoise.app():show_status("Shuffle patterns created successfully.")
end

function rollers.show_alternating_patterns_dialog(phrases)
    local vb = renoise.ViewBuilder()
    
    local phrase_info = {}
    for i, phrase in ipairs(phrases) do
        table.insert(phrase_info, {
            index = i,
            name = phrase.name
        })
    end
    
    local dialog_content = vb:column {
        margin = 10,
        spacing = 5,
        vb:text {
            text = "Alternating Patterns Phrases"
        },
        vb:row {
            vb:text {
                text = "Index",
                width = 50
            },
            vb:text {
                text = "Phrase Name",
                width = 250
            }
        }
    }
    
    for _, info in ipairs(phrase_info) do
        dialog_content:add_child(
            vb:row {
                vb:text {
                    text = tostring(info.index),
                    width = 50
                },
                vb:text {
                    text = info.name,
                    width = 250
                }
            }
        )
    end
    
    renoise.app():show_custom_dialog("Alternating Patterns Phrases", dialog_content)
end


local function show_dialog()

  if dialog and dialog.visible then
    dialog:close()
    dialog = nil
  end

  local song = renoise.song()
  local instrument_count = #song.instruments

  if instrument_count < 1 then
    renoise.app():show_warning("No instruments found in the song.")
    return
  end

  local dialog_vb = renoise.ViewBuilder()

  local dialog_content = dialog_vb:column {
    margin = 10,
    dialog_vb:row {
      dialog_vb:text {
        text = "Instrument Index:",
        font = "big",
        style = "strong"
      },
      dialog_vb:valuebox {
        id = 'instrument_index',
        min = 1,
        max = instrument_count,
        value = song.selected_instrument_index,
        notifier = function(value)
          song.selected_instrument_index = value
        end
      }
    },
    dialog_vb:vertical_aligner { height = 10 },
    dialog_vb:row {
      dialog_vb:text {
        text = "Tag",
        font="big",
        style="strong"
      }
    },
    dialog_vb:vertical_aligner { height = 10 },
    dialog_vb:row {
      spacing = 5,
      dialog_vb:button {
        text = "Label Slices",
        notifier = function()
          labeler.create_ui()
        end
      },
      dialog_vb:button {
        text = "Recall Labels",
        notifier = function()
          labeler.recall_labels()
        end
      }
    },
    dialog_vb:vertical_aligner { height = 10 },
    dialog_vb:row {
      dialog_vb:text {
        text = "Generate",
        font="big",
        style="strong"
      }
    },
    dialog_vb:vertical_aligner { height = 10 },
    dialog_vb:row {
      spacing = 5,
      dialog_vb:button {
        text = "Copy and Modify Phrases",
        notifier = function()
          local instrument_index = dialog_vb.views.instrument_index.value
          copy_and_modify_phrases(instrument_index)
        end
      },
      dialog_vb:button {
        text = "Modify Phrases with Labels",
        notifier = function()
          local instrument_index = dialog_vb.views.instrument_index.value
          modify_phrases_with_labels(instrument_index)
        end
      },
      dialog_vb:button {
        text = "Make Rollers",
        notifier = function()
          local instrument_index = dialog_vb.views.instrument_index.value
          create_roller_patterns(instrument_index)
        end
      },
      dialog_vb:button {
        text = "Make Shuffles",
        notifier = function()
          local instrument_index = dialog_vb.views.instrument_index.value
          create_shuffle_patterns(instrument_index)
        end
      },
    },
    dialog_vb:vertical_aligner { height = 10 },
    dialog_vb:row {
      dialog_vb:text {
        text = "Inspect",
        font="big",
        style="strong"
      }
    },
    dialog_vb:vertical_aligner { height = 10 },
    dialog_vb:row {
      spacing = 5,
      dialog_vb:button {
        text = "Evaluate Phrase",
        notifier = function()
          local instrument_index = dialog_vb.views.instrument_index.value
          evaluate_phrase(instrument_index)
        end
      },
      dialog_vb:button {
        text = "Show Phrases",
        notifier = function()
          local song = renoise.song()
          local current_instrument = song.selected_instrument
          if #current_instrument.phrases > 0 then
            local info = "Modified Phrases:\n\n"
            for i, phrase in ipairs(current_instrument.phrases) do
              info = info .. string.format("Phrase %d: %s\n", i, phrase.name)
              info = info .. string.format("  Lines: %d, LPB: %d\n\n", 
                phrase.number_of_lines, phrase.lpb)
            end
            
            local dialog_content = vb:column {
              margin = 10,
              dialog_vb:text { text = "Phrase Results" },
              vb:multiline_textfield {
                text = info,
                width = 400,
                height = 300,
                font = "mono"
              }
            }
            
            renoise.app():show_custom_dialog("Phrase Results", dialog_content)
          else
            renoise.app():show_warning("No modified phrases found.")
          end
        end
    },

      
    }
  }
  
  renoise.app():show_custom_dialog("BreakPal", dialog_content)
end

renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:BreakPal...",
  invoke = function()
    show_dialog()
  end
}

-- When closing the tool or reloading scripts, add:
function cleanup()
  if dialog and dialog.visible then
    dialog:close()
    dialog = nil
  end
end

print("LibGen tool loaded successfully")
