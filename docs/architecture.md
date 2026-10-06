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
  Library directly for those. A second axis is a second `Stage` object; axes on one port share
  one transport, each `Stage` made with `'Transport', t, 'SharedTransport', true`, and the
  caller closes `t` (a port can be opened only once).
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
- `SafeLimitsUm` is the box the axis may never leave, where it would hit something. It is set
  before `connect` and locked while connected, so a script that narrows `LimitsUm` to its scan
  cannot widen it by mistake: `LimitsUm` defaults to it and is refused outside it
  (`limitsOutsideSafe`). Since homing cannot be limited, `home()` is refused
  (`homeOutsideSafe`) when the home end lies outside it.

### D5. Stop on every software exit

`disconnect`, `delete` and closing a window that owns the stage call `stop()`. `stop()` never
throws and is tried in every state where the port is open.

### D6. Library errors pass through, logged

An unhomed axis, a stall or a pulled cable raises the library's own exception. `Stage` logs the
command with the message and rethrows. It does not translate the exception, so the library's
documentation still applies. The object stays Ready, because the controller answered.

### D7. The GUI is a programmatic uifigure: one panel for every axis

The window is built the same way as OBISLaser's and DoricLED's. Every button goes through
`Stage`, so the limits apply to clicks too. Esc is STOP. The position readback timer is safe
during scripted moves (D1: the library matches replies).

Since 2026-10-06 (operator's request) the panel shows every axis of a controller, one row each
(the rig's X, Y and Z share one port), laid out like the OBIS laser and Hamamatsu camera panels:
STOP stops them all, Connect finds the Zaber port from Windows' device list (USB vendor 2939)
and detects the axes, moves return at once so STOP always answers, and the port, the limits and
the log fold under Details. `Stage` stays one axis: the panel makes one per axis on a shared
transport, or attaches to a client's (`LuminoseHF`'s `rigStages`). With `'Parent'` it is built
inside the client's GUI, which hosts it rather than making stage controls of its own.

### D8. A reversed axis is mirrored in software, not on the controller

`'Reversed', true` makes positions increase the other way. `Stage` mirrors every position
across the axis's travel (`min + max -` the controller's position) and turns relative steps
round, so `DeviceLimitsUm`, `LimitsUm` and the GUI keep the same range. The controller is not
touched: flipping its `driver.dir` alone reverses the motor but not its encoder or home sensor,
and the axis then runs off to one end. `home()` still goes to the home sensor, which then
reads the top of the travel. The log and `record()` hold the reversed values, and
`record().Reversed` says so.

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
| 0.2.0 | 2026-10-06 | The panel for every axis (D7), embeddable; `listDevices` `IsZaber` from the registry; 62 tests |

Next is **M5**, rig verification (`rig-checks.md`).
