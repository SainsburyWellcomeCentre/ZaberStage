# GUI: `zaberstage.gui.StageApp`

```matlab
zaberstage.app()                      % owns a new Stage
zaberstage.app('Port', 'COM14')       % owned, with options
zaberstage.app(stage)                 % attached: never disconnects it
zaberstage.app(..., 'Visible', false, 'AutoRefresh', false)
```

| Area | Controls |
|---|---|
| Connection | Port, Scan, Connect/Disconnect, state |
| Identity | device, axis name, serial, axis number, travel, homed or NOT HOMED |
| Position | the position (every `RefreshS`, 0.5 s, with Auto refresh), Read, Home, Go to with Go, Step with - Step and + Step |
| Your limits | Min and Max: set `LimitsUm` at once (no traffic) |
| Log | commands that move or change something, then the window's errors |
| **STOP (Esc)** | `stop()` at once |

- **Every button goes through `zaberstage.Stage`**, so your limits apply. A refused move or
  limit appears in the log and in an alert, and is never thrown.
- **A limit outside the travel** is refused, and the fields go back to the limits in force.
- **Closing** a window that owns the stage stops and disconnects it. An attached window leaves
  the stage as it is.
- `tests/GuiTest.m` drives every control on the simulated stage. A human pass is pending
  (`rig-checks.md`).
