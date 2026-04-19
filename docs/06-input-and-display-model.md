# Input and Display Model

## Goals

The input system must make the desktop feel coherent across iPhone and external display while handling:

- touch gestures
- hardware keyboard
- pointer devices
- varying external monitor resolutions

## Input Architecture

The system should use a central `InputRouter`.

Responsibilities:

- normalize all input into a common event model
- resolve current focus target
- distinguish text input from command input
- bind routing to active iPhone work mode
- translate gestures into desktop actions
- send window-targeted events to runtimes

## Input Sources

### iPhone Touch Input

Primary behaviors:

- cursor movement in trackpad mode
- drag and drop gestures
- tap, double tap, long press
- window move and resize handles
- scroll gestures

### Hardware Keyboard

Primary behaviors:

- text entry into focused terminal, browser, or remote window
- global shortcuts
- local desktop shortcuts
- modified key combinations

Implementation notes:

- use UIKit key handling, not text-field-only shortcuts
- maintain explicit distinction between shortcut routing and text routing

### Pointer Devices

Primary behaviors:

- precise cursor movement
- hover effects
- context click
- drag operations
- resize handles

## Focus Model

The system needs three focus levels:

1. desktop focus
2. window focus
3. content focus

Examples:

- desktop focus decides which window receives general commands
- content focus inside terminal decides where text goes
- browser URL bar focus overrides page-level shortcuts

In addition, mode selection is explicit:

- `SSH` mode prefers terminal capture
- `VNC` mode prefers VNC capture
- `Browser` mode falls back to automatic capture and browser navigation controls

## Cursor Model

There should be one canonical cursor state:

- position in logical desktop coordinates
- button state
- drag state
- hover target
- cursor style

The external display renders the cursor. The iPhone controls or influences it.

## Display Model

### Logical Desktop Space

Do not store layouts in monitor pixels. Use a logical desktop coordinate system such as:

- base size `1440 x 900`
- normalized rectangles for window placement

This lets the same workspace adapt to:

- 1920 x 1080
- 2560 x 1440
- 3840 x 2160
- ultrawide formats

### Display Profile

Each connected monitor should resolve a display profile:

- actual bounds
- scale factor
- aspect ratio
- safe margins
- preferred render scale
- cursor scale

### Mapping Strategy

Coordinate transforms should be explicit:

- logical desktop to physical screen
- physical pointer delta to logical movement
- content viewport to window client area

Pointer routing should apply source-aware gain:

- touch trackpad
- hardware pointer
- keyboard-assisted nudging

## Window Layout Rules

Minimum rules:

- minimum readable size per window type
- title bar and resize affordance hit areas
- snap zones
- fullscreen mode
- safe restoration if a saved layout exceeds visible bounds

## Terminal-Specific Input Rules

- support raw text entry
- preserve modifier combinations
- send resize events when terminal window size changes
- map optional touch gestures to arrow keys or scroll only when explicitly enabled

## VNC-Specific Input Rules

- allow direct mode and trackpad mode
- map local keyboard accurately
- support remote clipboard exchange
- expose remote scaling and pointer sensitivity settings
- support explicit pointer button down/up semantics for drag operations
- support wheel up/down actions from control scene

## Reconnect Visibility Model

When VNC transport reconnect is in progress, reconnect state should be visible in both scenes:

- iPhone control scene shows latest status and event summary
- external desktop scene shows reconnect attempt and countdown overlay on the VNC window

## Browser-Specific Input Rules

- text focus must be explicit
- scroll routing must not conflict with window drag gestures
- browser shortcuts must be filtered against desktop shortcuts
- browser command actions (`back`, `forward`, `reload`, `navigate`) must be idempotent and acknowledged by command ID

## Edge Cases to Validate

- external display hot-plug while a drag is in progress
- keyboard attached after app launch
- window focused on a disconnected runtime
- resolution changes while windows are maximized
- text input after switching between terminal and browser
