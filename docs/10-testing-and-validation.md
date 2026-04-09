# Testing and Validation

## Testing Goals

The test strategy must reduce risk in the parts of the product most likely to fail:

- state synchronization
- focus and input routing
- scene lifecycle
- monitor resolution adaptation
- session durability

## Test Layers

### Unit Tests

Primary targets:

- reducers in `DesktopStore`
- geometry and snapping logic in `WindowManager`
- input routing resolution in `InputKit`
- persistence serialization
- connection metadata validation

### Integration Tests

Primary targets:

- scene attach and detach behavior
- runtime reattachment after scene recreation
- SSH session state transitions
- VNC connection and render pipeline
- browser metadata restore

### UI Tests

Primary targets:

- app launch
- desktop shell bootstrapping
- basic window open and close flows
- simple layout restore

### Manual Validation

Required because hardware and monitor combinations matter:

- external display connect and disconnect
- keyboard-only workflows
- pointer behavior
- drag and resize under load
- browser text input
- terminal text selection
- VNC control quality

## Monitor Test Matrix

Minimum matrix for MVP:

- iPhone plus 1920 x 1080 display
- iPhone plus 2560 x 1440 display
- iPhone plus 3840 x 2160 display
- one ultrawide profile if available

Validation goals:

- cursor scale feels correct
- window restore remains visible
- text readability remains acceptable
- no major hit-testing drift

## Input Test Matrix

Validate:

- touch-only control mode
- hardware keyboard attached at launch
- hardware keyboard attached after launch
- pointer device attached
- switching between terminal, browser, and VNC focus targets

## Session Durability Tests

Validate:

- external display disconnect during active session
- app background and foreground cycle
- scene recreation
- reconnect after transient network interruption

## Performance Validation

Track:

- frame pacing on desktop compositor
- memory growth after opening multiple windows
- VNC render latency
- browser window cost
- terminal rendering under scroll and resize

## Release Checklist

Before MVP release candidate:

1. Complete the monitor test matrix.
2. Complete the input test matrix.
3. Verify persistence and restore flows.
4. Review crash telemetry from internal testing.
5. Reconfirm browser and VNC quality against original acceptance criteria.

