# HotSwap - Sample Note to New Instrument Conversion Tool

HotSwap is a Renoise tool designed to streamline the process of managing and swapping sample based instruments with new instruments in your tracks through a comprehensive labeling system. It enables quick organization and manipulation of instruments through labels and automated note placement.

Labels can be used and swapped with BreakPal(https://github.com/MikePehel/breakpal) tool label files. M

## Features

### Core Functions

1. **Label Management System**
   - Comprehensive slice labeling interface
   - Support for primary and secondary labels
   - Multiple label categories: Kick, Snare, Hi Hat (Closed/Open), Crash, Tom, Ride, Shaker, Tambourine, Cowbell
   - Import/Export functionality for label data

3. **Automatic Note Placement**
   - Matches labeled slices to corresponding tracks
   - Supports ghost note placement on dedicated ghost tracks
   - Preserves original note properties (delay, volume, panning)
   - Intelligent handling of duplicate placements


### Key Components

1. **Label Editor**
   - Visual interface for managing slice labels
   - Support for dual labeling system (primary and secondary labels)
   - Visual feedback for label assignments
   - Real-time validation of breakpoint limits

2. **Import/Export System**
   - CSV-based label data storage
   - Preserves all label properties and assignments
   - Support for reference fields (instrument index, slice notes)
   - Maintains backward compatibility with different CSV formats

3. **Track Matching System**
   - Intelligent track name matching
   - Support for ghost note track detection and handling
   - Prevents duplicate note placement
   - Maintains original note properties

## Usage

### Basic Workflow

1. **Access the Tool**
   - Via Main Menu: Tools > HotSwap
   - Using the global keybinding (customizable)

2. **Label Management**
   - Open the Label Editor
   - Assign primary and secondary labels to slices
   - Set appropriate flags (Breakpoint, Cycle, Roll, Ghost Note, Shuffle)
    - Only Ghost Note is utilized by HotSwap, all flags except Label 2 are used in **BreakPal**
   - Save labels to persist your settings

3. **Import/Export Labels**
   - Export labels to CSV for backup or sharing
   - Import labels from previously saved configurations
   - Labels are stored per-instrument

4. **Note Placement**
   - Ensure tracks are named to match your labels
    - "Ghost" should appear after the label name if utilzing different tracks for Ghost Notes
   - Ensure instruments are named with "_{{LABEL}}" to match instruments to tracks
    - "_Ghost" should appear after the label name for ghost note instruments.
    - A ghost note instrument will be required if you want to differentiate ghost notes
   - Use the "Place Notes" function to automatically distribute notes
   - Ghost notes will be placed on dedicated ghost tracks if available

### Label Editor Interface

- Slice column shows hex indices (#00-#FF)
- Label dropdowns for primary and secondary assignments
- Checkbox toggles for special properties
- Save button to persist changes
- Support for showing/hiding secondary labels

## Technical Notes

- Labels are stored per-instrument and persist between sessions
- Maximum of 4 breakpoints per instrument
- Ghost notes can be placed on either dedicated ghost tracks or main tracks
- Track matching is case-insensitive and supports prefix matching
- Note properties (delay, volume, panning) are preserved during placement
- Grouped tracks are not supported currently

## Tips and Best Practices

1. **Labeling Strategy**
   - Use primary labels for main instrument categories
   - Use secondary labels for kit pieces or isntruments that occur simultaneously in the sample
   - Be consistent with your naming conventions

2. **Track Organization**
   - Name tracks to match the labels you want to match
   - Create dedicated ghost tracks for complex patterns
   - Keep track names simple and consistent
   - Do not group tracks (for now)

3. **Note Placement**
   - Clear existing notes before placement if needed
   - Check track names match exactly with labels
   - Verify ghost track setup for ghost notes

## Upcoming Features
- Place notes on phrases

# Move Fast and Break Beats
