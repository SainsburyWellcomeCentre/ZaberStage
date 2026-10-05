# Rig checks

Every run against the real stage is recorded here: date, who approved it, what ran and what was
seen. Each run needs the operator's explicit permission (`CLAUDE.md`). Before each run, record
what is mounted and the `LimitsUm` agreed.

## Pending

`tests/hardware/checkStage.m` runs steps 1 and 3–5.

### 1. Connection

`connect()` on `COM14`. Record:
- the device name, serial number, axis count and peripheral name
- `DeviceLimitsUm`
- `IsHomed`

Write the values into `zaber-motion.md` §4.

### 2. Homing

With the path clear and the operator watching, run `home()`. Record:
- the time it takes
- the position afterwards
- the direction of travel

### 3. Moves inside your limits

`moveAbsolute` to a known position near focus (29.79 mm), then `moveRelative` by ±50 um. Compare
`positionUm()` with a dial gauge or with the focus seen in the camera.

### 4. Refusals

Check that a target outside `LimitsUm` sends nothing (the controller's LED does not change, and
the log shows no `moveAbsolute`). Record what the library raises for a move on an unhomed axis
after power-up: its identifier goes in `zaber-motion.md` §3.

### 5. Stop

Start a long move with `'Wait', false`, then check that `stop()` and STOP in the window
(including Esc) bring it to rest.

### 6. `calibrate_z.m` end to end

With the camera.

## Log

No hardware runs yet.
