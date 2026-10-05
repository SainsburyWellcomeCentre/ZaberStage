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
| `LimitsUm` | read/write | your `[min max]`; must lie within `DeviceLimitsUm` |
| `Verbose`, `LogCapacity` | read/write | printing; log length (1000) |

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
`limitsOutsideDevice`, `portLocked`, `invalidOption`. Library and transport errors pass through
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
| `zaberstage.app(...)` | the control window ([`gui.md`](gui.md)) |
| `zaberstage.config(...)` | `RootDir`, `Port`, `BaudRate`, `Version`; `setpref('zaberstage', ...)` |
| `zaberstage.listDevices('Probe', false)` | table `Port`, `Available`, `Devices` |
| `zaberstage.version()` | package version |
