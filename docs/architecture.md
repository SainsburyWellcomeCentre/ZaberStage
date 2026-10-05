# Architecture

How the `zaberstage` package is built and why. The API is in [`api-reference.md`](api-reference.md),
and the library calls are in [`zaber-motion.md`](zaber-motion.md).

## 1. Goals and non-goals

**Goals**
- Move one Zaber axis in micrometres from MATLAB, standalone or inside a script or protocol.
- Make it hard to drive the stage where it should not go: limits set by the user and refused
  outside them, and nothing that moves on its own.
- Testable without hardware.

**Non-goals**
- Several axes moving together, streams, PVT, triggers, joystick setup. Use the Zaber Motion
  Library directly for those. A second axis is a second `Stage` object.
- Focus finding or scans. Those belong to the client (`example_scan.m` shows the pattern).

## 2. Decisions

### D1. The Zaber Motion Library, not raw ASCII

The library is installed on the rig, is what the previous code used, and handles device
detection, unit conversion and reply matching. Writing the ASCII protocol ourselves would
duplicate it and lose its unit tables.

### D2. Layered package; the transport is injectable

`Stage` holds the policy: which axis, the limits, the state, the log. A transport does what it
is told on any device and axis, in micrometres. The two transports are:
- `MotionLibraryTransport`, for the real stage
- `SimulatedTransport`, which keeps positions and homed state, refuses as the controller does,
  and can fail or lose its cable

### D3. Connecting never moves

`connect` only reads: devices, the axis's travel (`limit.min`, `limit.max`) and whether it is
homed. Homing runs the axis to its end of travel, so it is always an explicit `home()` (README,
*Safety*).

### D4. Limits are the user's, inside the axis's travel

- `LimitsUm` defaults to the axis's travel. The user narrows it and can never widen it beyond
  the travel.
- Every move is checked before anything is sent: absolute moves against their target, relative
  moves against the position read now plus the step. A move outside is refused
  (`outsideLimits`), never shortened.
- `home()` is the one move the limits cannot govern.

### D5. Stop on every software exit

`disconnect`, `delete` and closing a window that owns the stage call `stop()`. `stop()` never
throws and is tried in every state where the port is open.

### D6. Library errors pass through, logged

An unhomed axis, a stall or a pulled cable raises the library's own exception. `Stage` logs the
command with the message and rethrows. It does not translate the exception, so the library's
documentation still applies. The object stays Ready, because the controller answered.

### D7. The GUI is a programmatic uifigure

The window is built the same way as OBISLaser's and DoricLED's. Every button goes through
`Stage`, so the limits apply to clicks too. Esc is STOP. The position readback timer is safe
during scripted moves (D1: the library matches replies).

## 3. Class overview

| Class / function | Role |
|---|---|
| `zaberstage.Stage` | One axis: connection, moves, limits, log, record |
| `zaberstage.transport.Transport` | Abstract device/axis operations in um |
| `zaberstage.transport.MotionLibraryTransport` | `zaber.motion.ascii.Connection` and `Axis` |
| `zaberstage.transport.SimulatedTransport` | The stage without hardware, with fault injection |
| `zaberstage.gui.StageApp`, `zaberstage.app` | Control window |
| `zaberstage.config`, `version`, `listDevices` | Defaults (`setpref('zaberstage', ...)`), version, ports |

## 4. States

```
Disconnected --connect()--> Ready --disconnect()--> Disconnected
```

A failed `connect` closes the port and stays Disconnected. `Faulted` is reserved, and no path sets
it yet: the library reports its own failures per call (D6).

## 5. Repository layout

```
+zaberstage/              Stage, app, config, listDevices, version
+zaberstage/+transport/   Transport, MotionLibraryTransport, SimulatedTransport
+zaberstage/+gui/         StageApp
examples/                 example_basic, example_scan
tests/                    run_tests and test classes; hardware/ (manual, with permission)
docs/
```

## 6. Milestones

| Version | Date | What |
|---|---|---|
| 0.1.0 | 2026-10-05 | M1–M4: package, simulated stage, GUI, examples, docs, 47 tests; `LuminoseHF`'s `calibrate_z.m` uses it. Moved out of `LuminoseHF` (`zaber/ZaberModel.m`) |

Next is **M5**, rig verification (`rig-checks.md`).
