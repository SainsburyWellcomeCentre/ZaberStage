# API reference

## `zaberstage.Stage` (handle)

```matlab
stage = zaberstage.Stage('Port', 'COM14', 'DeviceAddress', 1, 'AxisNumber', 1, ...
                         'LimitsUm', [20000 40000])
stage = zaberstage.Stage('Transport', zaberstage.transport.SimulatedTransport())
```

The constructor never touches the hardware.

| Property | Access | Meaning |
|---|---|---|
| `State` | read | `'Disconnected'`, `'Ready'` (`'Faulted'` reserved) |
| `Transport` | read | the transport in use |
| `Identity` | read | `DeviceName`, `SerialNumber`, `PeripheralName`, `DeviceAddress` |
| `DeviceLimitsUm` | read | the axis's own travel |
| `IsHomed` | read | homed when last checked |
| `Port`, `BaudRate`, `DeviceAddress`, `AxisNumber` | read/write | only while Disconnected |
| `LimitsUm` | read/write | your `[min max]`; must lie within `DeviceLimitsUm` and `SafeLimitsUm` |
| `Verbose`, `LogCapacity` | read/write | printing; log length (1000) |
| `SafeLimitsUm` | read/write | the `[min max]` the axis may never leave (default `[]`, the whole travel; `-Inf`/`Inf` is that end of the travel, e.g. `[35000 Inf]`); only while Disconnected, so a script cannot widen it. `LimitsUm` defaults to it and must lie within it; `home()` is refused when the home end is outside it |
| `Reversed` | read/write | `true`: positions, moves and limits count the other way, mirrored across the travel (min + max − the controller's position), so home reads the top of the travel; the controller is not changed (default `false`; only while Disconnected) |
| `SharedTransport` | read/write | `true`: the `Transport` given is shared with other axes, so `disconnect()` and a failed `connect()` stop this axis but leave the port open; whoever made the transport closes it (default `false`) |

| Method | Does |
|---|---|
| `connect()` | open, find the device and axis, read travel and homed state; moves nothing |
| `disconnect()` | stop the axis, close; idempotent, never throws |
| `home('Wait', true)` | home the axis (ignores `LimitsUm`) |
| `moveAbsolute(um, 'Wait', true)` | move to a position; refused outside `LimitsUm` |
| `moveRelative(um, 'Wait', true)` | move by a step; refused if position + step is outside `LimitsUm` |
| `ok = stop()` | decelerate to rest; never throws |
| `um = positionUm()` | position now |
| `tf = isMoving()` | moving now |
| `waitUntilIdle()` | block until it stops |
| `s = record()` | plain struct with identity, limits and log |
| `t = log()` | table `Time`, `Command`, `Value`, `Ok`, `Message`, `DurationMs` |

Events: `StateChanged`, `MoveCompleted`.

Errors (`zaberstage:Stage:*`): `notReady`, `noPort`, `noDevice`, `outsideLimits`, `badValue`,
`limitsOutsideDevice`, `limitsOutsideSafe`, `homeOutsideSafe`, `portLocked`, `invalidOption`. Library and transport errors pass through
with their own identifiers.

## Transports

`zaberstage.transport.Transport` is abstract. Its methods are:
- `open()`, `close()`, `isOpen()`
- `listDevices()` → struct `Address`, `Name`, `SerialNumber`, `AxisCount`
- `axisInfo(device, axisNumber)` → struct `Name`, `LimitsUm`, `IsHomed`
- `home`, `moveAbsolute`, `moveRelative` (each with a `wait` argument)
- `stop`, `positionUm`, `isBusy`, `waitUntilIdle`

The concrete transports are:
- `MotionLibraryTransport(port, 'BaudRate', 115200, 'Direct', false)`. Errors:
  `zaberstage:MotionLibraryTransport:noLibrary`, `openFailed`, `notOpen` and `noDevice`.
- `SimulatedTransport(...)`:

  | Members | What they are |
  |---|---|
  | `Devices`, `LimitsUm`, `PeripheralName`, `SpeedUmPerS`, `StartHomed` | settings |
  | `Calls`, `PositionsUm` | read-only state |
  | `failNext(command, identifier)`, `unplug()`, `clearCalls()`, `callsOf(command)` | faults and the calls log |

## Functions

| Function | Does |
|---|---|
| `zaberstage.app(...)` | the control panel for every axis of a controller ([`gui.md`](gui.md)); with no `'Axes'` it uses `zaberstage.config().Axes` |
| `zaberstage.config(...)` | `RootDir`, `Port`, `BaudRate`, `Axes` (default axes: a struct of structs of `Stage` options, `struct()` when none), `Version`; preferences `setpref('zaberstage', ...)` |
| `zaberstage.config(...)` | `RootDir`, `Port`, `BaudRate`, `Version`; `setpref('zaberstage', ...)` |
| `zaberstage.listDevices('Probe', false)` | table `Port`, `Available`, `IsZaber` (a Zaber USB controller, USB vendor 2939, from the Windows registry: no traffic), `Description`, `Devices` (only when probed) |
| `zaberstage.version()` | package version |
