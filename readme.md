# HotSwap - Sample Slice Labeling, Mapping, and Rerendering Tool

HotSwap is a Renoise tool for managing sample-based instruments. It lets you label slices in drum samples, map those labels to tracks and instruments, automatically place notes on matching tracks, and render results back into new sampled instruments with preserved slice markers.

Labels are compatible with the [BreakPal](https://github.com/MikePehel/breakpal) tool format.

## Interface

HotSwap opens as a single tabbed dialog (Tools > HotSwap or the Global keybinding). An instrument selector with hex index and lock button sits at the top. Four tabs organize all functionality:

| Tab | Purpose |
|-----|---------|
| **Tag** | Open the Label Editor, import/export labels (CSV, JSON) |
| **Map** | Open the Track Mapping Editor, import/export mappings |
| **Swap** | Place notes on matching tracks, linear swap, phrase/track conversions |
| **Render** | Configure and execute rendering with slice marker transfer |

A status line at the bottom shows label and mapping counts for the current instrument.

## Features

### Label Editor (Tag tab)

Floating dialog for labeling slices in a sample-based instrument.

- Primary and secondary labels per slice
- Label categories: Kick, Snare, Hi Hat Closed, Hi Hat Open, Crash, Tom, Ride, Shaker, Tambourine, Cowbell
- Location modifiers: Off-Center, Center, Edge, Rim, Alt
- Flags per slice: Ghost, Counterstroke, Breakpoint, Cycle
- Slice audio preview
- Labels saved per-instrument, persist between sessions
- Import from CSV or JSON, export as BreakPal-compatible CSV or full JSON

### Track Mapping Editor (Map tab)

Floating dialog for defining how labels route to tracks and instruments.

- Map each label to one or more target track/instrument pairs
- Granularity options: location-based, ghost note, and counterstroke differentiation
- Mute groups (choke groups) — instruments in the same group cut each other off with OFF notes
- Per-instrument mapping configuration
- Edit/Done toggle updates mappings in-place without dialog flicker
- Import/export mappings as JSON

### Note Placement (Swap tab)

- **Place Notes on Matching Tracks** — reads source pattern notes, resolves labels through the mapper, and distributes notes to target tracks with round-robin across multiple mappings
- **Linear Swap** — replaces all notes in a selected track with C-4 using sequential instruments
- **Phrase to Track** — copies phrase note data to a pattern track with overflow, condense, and pattern length options
- **Track to Phrase** — converts pattern track notes into an instrument phrase (Note Mode or Mapping Mode)

### Rendering (Render tab)

- Sequence and line range selection
- Sample rate (22050–192000 Hz), automatically matches source instrument when locked
- Bit depth (16/24/32-bit)
- Slice marker placement: from pattern notes or from source sample
- Renders pattern range to WAV and creates a new instrument with transferred slice markers

## Workflow

1. **Lock an instrument** using the hex selector and Lock button at the top of the dialog
2. **Tag tab** — open the Label Editor and label each slice (Kick, Snare, etc.) with location and type flags. Save labels. Optionally import/export.
3. **Map tab** — open the Track Mapping Editor. For each label, assign target tracks and instruments. Enable location/ghost/counterstroke granularity as needed. Set mute groups for choke behavior.
4. **Swap tab** — click "Place Notes on Matching Tracks" to distribute notes from the source pattern to mapped tracks. Use Linear Swap or Phrase/Track conversions as needed.
5. **Render tab** — set the sequence/line range, sample rate, bit depth, and marker source. Click Render to produce a new sampled instrument with slice markers.

## Naming Conventions

- **Tracks**: name them to match labels (case-insensitive). Append "Ghost" for ghost note tracks (e.g., "Snare Ghost").
- **Instruments**: use `_{{LABEL}}` suffix for mapping (e.g., `_Kick`). Append `_Ghost` for ghost instruments.

## Technical Notes

- Labels stored per-instrument as hex-keyed tables (`"00"`, `"01"`, etc.)
- Mapping resolution: `mappings[label][location][type_key]` → array of targets
- Type keys: `regular`, `ghost`, `counterstroke`, `ghost_counterstroke`
- Round-robin counters distribute notes across multiple mappings for the same label
- Maximum 4 breakpoints per instrument
- Note properties (delay, volume, panning) preserved during placement
- Slice markers transferred proportionally to rendered samples
- Renoise Lua 5.1 runtime, no external dependencies

## Upcoming Features

- Place notes on phrases

# Move Fast and Break Beats