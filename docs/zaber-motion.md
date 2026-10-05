# Zaber Motion Library notes

What this package uses from the Zaber Motion Library for MATLAB, and what is known about the
rig's stage. Each fact is marked with its source:
- **rig** — seen on the stage, with the date
- **lab code** — called by `LuminoseHF`'s `ZaberModel`, which ran `calibrate_z.m` on this stage
- **library** — read in the installed library's source (9.3.2)
- **verify** — from Zaber's documentation, not yet seen here

## 1. Installation

| Fact | Value | Source |
|---|---|---|
| Version on the rig | 9.3.2, MATLAB add-on | library (`resources/addons_core.xml`) |
| Implementation | MATLAB classes under `+zaber/+motion`, calling a native gateway | library |
| Units | `zaber.motion.Units.LengthMicrometres` | lab code, library |

## 2. Calls used

| Call | Used by | Source |
|---|---|---|
| `zaber.motion.ascii.Connection.openSerialPort(port, 'baudRate', b, 'direct', tf)` | `open` | lab code (port only); library (options) |
| `connection.detectDevices()` | `listDevices` | lab code |
| `device.DeviceAddress`, `.Name`, `.SerialNumber`, `.AxisCount` | `listDevices` | library |
| `device.getAxis(n)` | every axis call | lab code |
| `axis.PeripheralName` | `axisInfo` | library |
| `axis.Settings.get('limit.min' / 'limit.max', Units.LengthMicrometres)` | `axisInfo` | library; verify the values |
| `axis.isHomed()` | `axisInfo` | library |
| `axis.home('waitUntilIdle', tf)` | `home` | library |
| `axis.moveAbsolute(um, Units.LengthMicrometres, 'waitUntilIdle', tf)` | `moveAbsolute` | lab code (waiting form) |
| `axis.moveRelative(um, Units.LengthMicrometres, 'waitUntilIdle', tf)` | `moveRelative` | lab code (waiting form) |
| `axis.stop()` | `stop` | library |
| `axis.getPosition(Units.LengthMicrometres)` | `positionUm` | lab code |
| `axis.isBusy()`, `axis.waitUntilIdle()` | `isMoving`, `waitUntilIdle` | library |
| `connection.close()` | `close` | lab code |

## 3. Behaviour

| Fact | Source |
|---|---|
| Without `direct`, a port held by Zaber Launcher is shared through it | library (help text) |
| A move on an unhomed axis fails (the axis has no position reference after power-up) | verify |
| A target outside `limit.min`/`limit.max` is rejected by the controller | verify |
| `home` moves to the home sensor at the minimum end | verify |

## 4. This rig

| Fact | Value | Source |
|---|---|---|
| Port, axis | `COM14`, axis 1 (Z) | lab code (`luminose_config.yaml`) |
| Nominal focus | 29.79 mm | lab code (`calibrate_z.m`) |
| Device name, travel | unknown until the first connect | — |
