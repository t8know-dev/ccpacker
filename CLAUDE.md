# CCPacker — AE2 Item Packing Station for CC:Tweaked

Numismatics-powered AE2 item packing machine. Players insert items into an input barrel, pay spurs via an Andesite Depositor, and receive a filled AE2 storage cell. Built with PixelUI for the display and `parallel.waitForAny` for concurrent operation.

---

## Architecture Overview

```
ccpacker/
├── ccpacker.lua                 # Orchestrator: startup + 4 parallel coroutines
├── config.lua                   # ALL configuration: peripherals, cell types/prices, messages
├── pixelui.lua                  # PixelUI framework (vendor copy)
├── shrekbox.lua                 # PixelUI dependency (vendor copy)
├── pixelui_example.lua          # PixelUI examples (ignore)
└── modules/
    ├── peripherals.lua          # Peripheral wrappers: barrel, chute, IO port, depositor, relay
    ├── state.lua                # Observer-pattern state management
    ├── ui.lua                   # PixelUI screens (splash, idle, prompt, cell_choice, payment, packing, thankyou, error)
    ├── payment.lua              # Redstone relay input polling for payment detection
    └── vendor.lua               # Transaction state machine + cell selection algorithm
```

### Flow

```
splash (3s)
    ↓
idle  ←─────────────────────── timeout ──────────────────────┐
    │  (monitors barrel every 3s)                             │
    │  items found?                                           │
    ↓                                                         │
prompt ←── (SCREEN_TIMEOUT 120s) ─────────────────────────────┤
    │  "[ PACK ]" clicked?                                    │
    ↓                                                         │
cell_choice ←── (SCREEN_TIMEOUT 120s) ────────────────────────┤
    │  PORTABLE or NORMAL selected?                           │
    ↓       (calculates cell size, checks availability)       │
payment ←─── (ABORT or PAYMENT_TIMEOUT 60s) ──────────────────┤
    │  payment detected?                                       │
    ↓                                                         │
packing ─── (polls IO port every 1s) ─────────────────────────┤
    │  IO port returns finished cell?                         │
    ↓                                                         │
thankyou (5s) ────────────────────────────────────────────────┘
```

### Concurrency Model

Four coroutines run via `parallel.waitForAny`:

| # | Coroutine | Responsibility | I/O |
|---|-----------|---------------|-----|
| 1 | **runPixelUI** | Render monitor, handle button clicks | None (pullEvent only) |
| 2 | **vendorLoop** | Transaction state machine + cell selection | Depositor, relay, barrels, chute, IO port |
| 3 | **paymentMonitorLoop** | Poll relay inputs for payment signal | Relay getInput |
| 4 | **heartbeatLoop** | Check peripheral aliveness every 10s | All peripherals |

**Why top-level parallel, not PixelUI threads:** `peripheral.call()` internally yields the current coroutine waiting for a `peripheral_response` event. PixelUI's thread scheduler cannot handle this yield — it would desync the event queue and cause an infinite loop. All peripheral I/O runs in coroutines 2–4, which run at the `parallel.waitForAny` level where event dispatch works correctly. Coroutine 1 (PixelUI) handles only the monitor and `os.pullEvent`.

---

## Hardware Setup

### Required Peripherals (7 total)

| Config Name | Peripheral ID | Purpose |
|------------|--------------|---------|
| `MONITOR` | `monitor_18` | UI display (1×1 advanced monitor) |
| `DEPOSITOR` | `Numismatics_Depositor_14` | Coin payment (Andesite Depositor) |
| `RELAY` | `redstone_relay_17` | Depositor lock + payment detection |
| `INPUT_BARREL` | `minecraft:barrel_10` | Items to pack (also receives finished cell) |
| `CHUTE` | `create:chute_0` | Feeds empty AE2 cells into the IO port |
| `IO_PORT` | `ae2:io_port_1` | Packs items into AE2 storage cells |
| `CELL_BARREL` | `"top"` (computer top face) | Contains empty AE2 cells of various sizes |

### Redstone Relay Wiring

The relay serves two roles:

1. **Output (depositor lock):** Relay output on `RELAY_LOCK_SIDE` (default: `"top"`) connects to the depositor's redstone input. HIGH = locked (coins rejected), LOW = unlocked (coins accepted).
2. **Input (payment detection):** Relay input on `PAYMENT_DETECTION_SIDE` (default: `"top"`) reads the signal from the depositor. When the depositor accepts payment, it emits a redstone signal on ALL sides, which the relay detects.

```
┌─────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Andesite       │     │  Redstone Relay  │     │  Computer        │
│  Depositor      │     │                  │     │                  │
│                 │     │  Input (top)   ◄─┼─────┤ getInput(top)    │
│  Redstone IN ◄──┼─────┼──► Output (top)  │     │  setOutput(top)  │
│                 │     │                  │     │                  │
└─────────────────┘     └──────────────────┘     └──────────────────┘
```

### Barrel / Chute / IO Port Setup

```
┌──────────────────────┐     ┌──────────────────────┐
│  CELL BARREL (top)   │     │  INPUT BARREL         │
│  (empty cells:       │     │  (items to pack +     │
│   1k, 4k, 16k)      │     │   finished cell out)  │
└──────┬───────────────┘     └───────────────────────┘
       │ pushItems(slot,1)                            ▲
       ▼                                              │
┌──────────────┐       ┌──────────────────┐      pullCellFromIoPort()
│  CHUTE       │──────►│  IO PORT         │      (pushItem by name)
│  create:0    │ drop  │  ae2:io_port_1   │──────────┘
└──────────────┘       │  (packs items     │
                       │   into cell)      │
                       └──────────────────┘
                           ▲
                           │ pulls items from
                           │ INPUT_BARREL automatically
```

### Cell Barrel (Computer Top Face)

- **CELL_BARREL** (`"top"` peripheral): Fill this with empty AE2 storage cells.
- The system selects a cell based on barrel contents, then pushes one from this barrel into the chute.
- The chute drops the cell into the IO port which recognises it.

---

## Configuration (`config.lua`)

All user-facing settings are in `config.lua`. No code changes needed to configure the machine.

### Peripheral Names

Edit these to match your in-world peripheral names (check with `wired_modem` or peripheral inspection):

```lua
MONITOR        = "monitor_18"
DEPOSITOR      = "Numismatics_Depositor_14"
RELAY          = "redstone_relay_17"
INPUT_BARREL   = "minecraft:barrel_10"
CHUTE          = "create:chute_0"
IO_PORT        = "ae2:io_port_1"
CELL_BARREL    = "top"   -- Computer top face — barrel with empty AE2 cells
```

### Cell Type Definitions

```lua
CELL_TYPES = {
    normal = {
        { id = "ae2:item_storage_cell_1k",  label = "1k",  itemCap = 4096,  typeCap = 54,  price = 1 },
        { id = "ae2:item_storage_cell_4k",  label = "4k",  itemCap = 12288, typeCap = 45,  price = 4 },
        { id = "ae2:item_storage_cell_16k", label = "16k", itemCap = 49152, typeCap = 36,  price = 16 },
    },
    portable = {
        { id = "ae2:portable_item_cell_1k",  label = "1k",  itemCap = 4096,  typeCap = 54,  price = 2 },
        { id = "ae2:portable_item_cell_4k",  label = "4k",  itemCap = 12288, typeCap = 45,  price = 8 },
        { id = "ae2:portable_item_cell_16k", label = "16k", itemCap = 49152, typeCap = 36,  price = 32 },
    },
}
```

The selection algorithm picks the **smallest** cell whose item AND type capacities both fit the measured barrel contents. When none fits, an error is shown.

### Timing

```lua
PERIPHERAL_SCAN_INTERVAL = 1     -- Startup peripheral polling interval
BARREL_CHECK_INTERVAL   = 3     -- How often to check input barrel for items
PACKING_POLL_INTERVAL   = 1     -- How often to poll IO port during packing
SCREEN_TIMEOUT          = 120   -- General timeout: returns to idle
PAYMENT_TIMEOUT         = 60    -- Seconds to wait for payment
THANKYOU_DELAY          = 5     -- Seconds to show confirmation
ERROR_DELAY             = 2     -- Seconds to show error message
SPLASH_DELAY            = 3     -- Seconds to show splash screen
TRANSFER_TICK_INTERVAL  = 0.1   -- Vendor loop poll interval
```

### UI Messages (`MSG` block)

All on-screen text is in the `MSG` table. Monitor scale 0.5 on a 1×1 monitor fits roughly 26×8 characters. Keep text SHORT.

### Debug Logging

```lua
DEBUG     = true          -- Toggle debug logging
DEBUG_LOG = "/ccpacker/debug.log"  -- Log file path on the computer
```

Use `dlog(...)` for debug output — writes to native terminal AND the log file. `dclear()` clears the log. The `dlog` and `dclear` functions are global (defined in `config.lua`) and available everywhere after `dofile("/ccpacker/config.lua")`.

---

## Screen Reference

All screens are rendered by `modules/ui.lua` via `updateScreen(state)`. Widgets are created once in `createUI()` and shown/hidden by visibility toggles.

### Splash Screen
```
┌──────────────────────────┐  ← header (red bg)
│        CCPACKER          │
├──────────────────────────┤
│        CCPACKER          │  ← splash_line1 (row 3)
│                          │
│      Item Packer         │  ← splash_line2 (row 5)
│                          │
│         v1.0             │  ← splash_line3 (row 6)
└──────────────────────────┘
```
Duration: `SPLASH_DELAY` (3s) seconds.

### Idle Screen
```
┌──────────────────────────┐  ← header (red bg)
│        CCPACKER          │
├──────────────────────────┤
│                          │
│    < order pickup        │  ← blink label (row 4, arrow blinks every 0.5s)
│                          │
└──────────────────────────┘
```
Arrow `<` toggles visibility every 0.5s. Checks input barrel every 3s for items.

### Prompt Screen
```
┌──────────────────────────┐  ← header
│        CCPACKER          │
├──────────────────────────┤
│    Pack items to         │  ← msgLine1 (row 3)
│                          │
│    an AE2 cell?          │  ← msgLine2 (row 5)
│                          │
│      [ PACK ]            │  ← green button, 3 lines high (rows 6-8)
└──────────────────────────┘
```
Timeout: `SCREEN_TIMEOUT` seconds → idle.

### Cell Choice Screen
```
┌──────────────────────────┐  ← header
│        CCPACKER          │
├──────────────────────────┤
│   Choose cell type       │  ← title (row 3)
│                          │
│   [ PORTABLE ]           │  ← gray button (row 5)
│                          │
│   [ NORMAL ]             │  ← gray button (row 7)
└──────────────────────────┘
```
Timeout: `SCREEN_TIMEOUT` seconds → idle.

### Payment Screen
```
┌──────────────────────────┐  ← header
│        CCPACKER          │
├──────────────────────────┤
│     Please insert        │  ← yellow, row 3
│       4 spur(s)          │  ← yellow, row 4
│     into the             │  ← yellow, row 5
│     depositor            │  ← yellow, row 6
├──────────────────────────┤
│        ABORT             │  ← orange button (row 8)
└──────────────────────────┘
```
Timeout: `PAYMENT_TIMEOUT` (60s) seconds → error.

### Packing Screen
```
┌──────────────────────────┐  ← header
│        CCPACKER          │
├──────────────────────────┤
│      Packing...          │  ← yellow (row 3)
├──────────────────────────┤
│  ████████░░░░░░░░░░░░░   │  ← progress bar (row 4)
├──────────────────────────┤
│     100/100 (100%)       │  ← progress text (row 6, green when ≥100%)
└──────────────────────────┘
```
Progress is based on input barrel emptying: `(initialItems - currentItems) / initialItems * 100`.

### Thank You Screen
```
┌──────────────────────────┐  ← header
│        CCPACKER          │
├──────────────────────────┤
│      Thank you!          │  ← green, row 3
│    Packing complete.     │  ← green, row 4
│   Collect your cell      │  ← green, row 5
│   from the barrel.       │  ← green, row 6
└──────────────────────────┘
```
Duration: `THANKYOU_DELAY` (5s) seconds.

### Error Screen
```
┌──────────────────────────┐  ← header
│        CCPACKER          │
├──────────────────────────┤
│    Timeout!              │  ← red, row 3 (dynamic error message)
│      Error!              │  ← red, row 4
└──────────────────────────┘
```
Duration: `ERROR_DELAY` (2s) seconds.
Error messages: "Timeout!", "No items to pack!", "Cell not available!", "Items exceed!", "Depositor error!", "IO port error!", "Transaction failed!" depending on context.

---

## Module Reference

### `ccpacker.lua` — Orchestrator

Entry point. On boot:
1. Loads `config.lua` (globals)
2. Loads and initialises all modules
3. Waits for peripherals via `periphs.init()` (blocking, polls each every 1s)
4. Sets relay to HIGH (locked)
5. Probes depositor, relay, chute, and IO port methods for API verification
6. Creates PixelUI app, shows splash for 3s
7. Enters idle screen
8. Enters `parallel.waitForAny` with 4 coroutines

### `modules/peripherals.lua` — Hardware Abstraction

All interactions with CC:Tweaked peripherals. Key design choices:
- **Lazy getters** with 5-second re-wrap cooldown (wrappers cleared by heartbeat on death)
- **Blocking `waitForPeripheral(name, label)`** at init for each peripheral (all 7)
- **Barrel operations** use `barrel:list()` for inventory, `barrel:pushItems(dest, slot, qty)` for cell-to-chute transfers, and `io_port:pushItem(dest, name, count)` for finished cell retrieval (by item NAME, not slot)
- New functions for ccpacker: `getBarrelItems()`, `findCellInBarrel()`, `pushCellToChute()`, `getIoPortItems()`, `pullCellFromIoPort()`

### `modules/state.lua` — State Management

Observer pattern:
- `getState(key)` — read a single field or full state table
- `updateState(changes)` — merge changes, notify subscribers only on actual value changes (`state[k] ~= v`)
- `subscribe(callback)` — register a change listener
- `resetTransaction()` — clear all transaction tracking fields

State fields:
- `screen` — current screen (splash, idle, prompt, cell_choice, payment, packing, thankyou, error)
- `cellType`, `cellSize`, `selectedCell` — cell selection tracking
- `totalBarrelItems`, `uniqueItemTypes`, `initialItemCount` — barrel analysis
- `totalPrice`, `paymentDeadline`, `paymentBaseline`, `paymentPaid` — payment tracking
- `transferred`, `cellPushed` — packing progress
- `blinkVisible` — idle screen arrow animation
- `screenEntryTime` — general timeout tracking
- `errorMsg` — dynamic error text

### `modules/ui.lua` — PixelUI Screens

- Widgets created once in `createUI(monitor, callbacks)`, toggled via visibility
- 8 screens: splash, idle, prompt, cell_choice, payment, packing, thankyou, error
- `updateScreen(state)` — full screen switch (hides all, shows relevant widgets)
- `updateProgress(state)` — live progress bar update during packing (barrel-based %)
- Callbacks passed as table: `{ onPackClick, onPortableClick, onNormalClick, onCancelClick }`

### `modules/payment.lua` — Payment Detection

Three detection methods in priority order:

1. **Baseline comparison (primary):** Compare current relay input on `PAYMENT_DETECTION_SIDE` against the pre-unlock snapshot. Any change = payment.
2. **All-sides fallback:** The depositor emits on all six redstone sides. Check every side for changes vs baseline.
3. **Rising-edge detection (fallback):** When no baseline exists, track the last-known value and flag any transition.

The monitoring loop (`paymentMonitorLoop`) **only** sets `paymentPaid = true`. It never changes screens — that's the vendor loop's job. This prevents race conditions between the two coroutines.

### `modules/vendor.lua` — Transaction State Machine

Runs as a loop in its own coroutine. Handles:

| Screen | Action |
|--------|--------|
| `idle` | Toggle blink animation (0.5s). Check barrel every 3s → prompt |
| `prompt` | Wait for PACK click or timeout → idle. Re-check barrel. |
| `cell_choice` | Wait for PORTABLE/NORMAL or timeout → idle |
| `payment` (first entry) | Re-check barrel, set up depositor, unlock relay, record baseline + deadline |
| `payment` (subsequent) | Wait for `paymentPaid=true` or timeout |
| `packing` (phase 1) | Push selected cell from cell barrel to chute → IO port picks it up |
| `packing` (phase 2) | Poll barrel progress + IO port every 1s. When IO port returns non-empty `items()`, cell is ready |
| `packing` (phase 2 done) | Move finished cell from IO port to input barrel via `pushItem(INPUT_BARREL, cellName, 1)` |
| `thankyou` | Sleep `THANKYOU_DELAY`, reset state, go to idle |
| `error` | Lock relay, sleep `ERROR_DELAY`, reset state, go to idle |

Key helper: `_calculateRequiredCell(totalItems, uniqueTypes, cellType)` — selects smallest cell that fits both item and type capacities.

---

## API Reference: Numismatics Depositor

The depositor supports these methods (verified at startup via `probeMethods`):

```lua
depositor:setTotalPrice(spurAmount)       -- Set total price in spurs
depositor:getTotalPrice()                 -- Get current total price (returns number)
depositor:setCoinAmount(coinName, amount) -- Set price per coin type
depositor:getPrice(coinName)              -- Get price in specific coin type (returns number)
```

When the required amount is deposited, the depositor emits a redstone signal on **all six sides** simultaneously. This signal is detected by the relay on `PAYMENT_DETECTION_SIDE`.

---

## API Reference: AE2 IO Port (Confirmed)

Tested methods:

```lua
io_port:items()                                    -- Returns: {} (empty) or {{name = "ae2:item_storage_cell_1k", ...}}
io_port:pushItem(destName, itemName, count)        -- Push by item name (NOT slot!)
```

**Important — `pushItem` vs `pushItems`:** The IO port uses `pushItem(destName, itemName, count)` — identifies items by their **Minecraft item name**, not slot number. This is DIFFERENT from vanilla barrels which use `pushItems(destName, slot, count)`.

When the IO port has a filled cell ready, `items()` returns a non-empty table. Use `pushItem(INPUT_BARREL, cellName, 1)` to move it to the input barrel.

---

## Barrel API Reference

Vanilla Minecraft barrels support:

```lua
barrel:list()                         -- Returns {slot = {name, count, ...}}
barrel:pushItems(destName, slot, qty) -- Push from this barrel to another inventory (by slot!)
barrel:pullItems(sourceName, slot, qty) -- Pull from another inventory to this barrel (by slot!)
barrel:size()                         -- Total slot count
barrel:getItemDetail(slot)            -- Item details in a specific slot
```

**Important:** Vanilla barrels do NOT support `pushItem(itemName, qty)` — only `pushItems(destName, slot, qty)`. The push-by-name pattern (`pushItem`) is AE2/Create-specific.

---

## Cell Selection Algorithm

When the user chooses NORMAL or PORTABLE, the system:

1. Reads the input barrel: measures `totalItems` and `uniqueItemTypes`
2. Iterates cell types from smallest to largest (1k → 4k → 16k)
3. Selects the **first** cell where BOTH conditions are met:
   - `totalItems <= cell.itemCap`
   - `uniqueItemTypes <= cell.typeCap`
4. Verifies the cell exists in the cell barrel
5. Transitions to payment

**Cell capacities:**

| Cell | Item Capacity | Type Capacity | Normal Price | Portable Price |
|------|--------------|---------------|-------------|---------------|
| 1k | 4,096 | 54 | 1 spur | 2 spur |
| 4k | 12,288 | 45 | 4 spur | 8 spur |
| 16k | 49,152 | 36 | 16 spur | 32 spur |

---

## Startup Behaviour

1. Native terminal prints "=== CCPACKER ==="
2. Polls each peripheral sequentially (1s intervals), printing status:
   - Yellow "Waiting for: Monitor: monitor_18" while unavailable
   - Green "OK  Monitor: monitor_18" when found
3. Sets relay to HIGH (locked) — depositor blocked
4. Probes depositor, relay, chute, and IO port methods (logged to debug)
5. Creates PixelUI app on monitor
6. Shows splash screen for 3s
7. Enters idle screen — waits for items to appear in input barrel
8. Enters parallel coroutines

If any peripheral is permanently unavailable, the script blocks at startup printing "Waiting for..." — the computer must be in a loaded chunk for peripherals to appear.

---

## Error Handling Strategy

All peripheral calls are wrapped in `pcall`. Errors are logged via `dlog()` and handled per context:

| Layer | Error Handling |
|-------|---------------|
| **vendorLoop** | `pcall` wraps the entire loop body. On error: lock depositor, continue. |
| **paymentMonitorLoop** | `pcall` wraps each tick. On error: sleep 1s, continue. |
| **heartbeatLoop** | `pcall` wraps each iteration. Dead wrappers set to nil (lazy getters re-wrap on next use). |
| **UI callbacks** | `pcall(callbacks.*)` — button errors never crash the UI loop. |
| **Startup** | Entire startup wrapped in `pcall`. On fatal error: print to native terminal. |

### Transaction Safety

- Relay starts HIGH (locked). Player cannot insert coins before a transaction begins.
- On error at any stage: relay is set to HIGH (locked).
- Cell availability is checked BEFORE transitioning to payment.
- Barrel contents are verified at prompt, at cell type selection, and again in payment handler.
- `paymentSetupDone` flag prevents duplicate depositor configuration.
- `paymentMonitorLoop` only sets `paymentPaid=true` — no screen transitions from the monitor coroutine avoids race conditions.
- `cellPushed` flag ensures the cell is pushed to the chute exactly once.
- All IO port calls (items, pushItem) are wrapped in `pcall`.

---

## Troubleshooting

### "Waiting for: Monitor" indefinitely
- Ensure the computer's chunk is loaded. Use a chunk loader or `/forceload`.
- Check the monitor is connected to the same wired/wireless network as the computer.
- Verify the monitor name in `config.lua` matches (use `wired_modem` or `peripheral.list()`).

### Payment never detected
- Check `PAYMENT_DETECTION_SIDE` matches the relay side connected to the depositor's redstone output.
- Ensure the relay is on the same network as the computer.
- Check the debug log (`dlog` calls log baseline values and detection attempts).
- The depositor emits on ALL sides — try changing `PAYMENT_DETECTION_SIDE` to another side.
- Verify `depositor:setCoinAmount(amount)` returns true (check `probeMethods` output in debug log).

### Cell not inserted into chute
- Verify the cell barrel on the computer's top face contains empty AE2 cells.
- Check cell names match the `id` fields in `CELL_TYPES` config.
- The chute must be below the cell barrel or receiving items via pipe/conveyor.
- Check debug log for `pushCellToChute` error messages.

### IO port not picking up the cell
- The chute must be positioned to drop items into the IO port (directly above or via pipes).
- Check the IO port is configured to accept the cell type.
- Verify `io_port:items()` returns `{}` when empty (confirm IO port is connected).

### IO port packing never completes
- Verify the input barrel contains items the IO port can read.
- Check that items are being removed from the input barrel as packing progresses.
- The progress bar reflects barrel emptying — if no items are removed, check IO port configuration.
- Add a packing timeout check if needed (the system polls indefinitely during packing).

### Cell not retrievable from IO port
- Check `io_port:pushItem(INPUT_BARREL, cellName, 1)` — this uses item NAME (not slot).
- Verify the input barrel has at least one free slot.
- The `pullCellFromIoPort` function retries once before reporting an error.

### "Items exceed capacity!" on cell selection
- The barrel has more items or item types than any available cell can hold.
- Use a larger cell or reduce the number of item types in the barrel.
- Check `totalBarrelItems` and `uniqueItemTypes` in the debug log.

### Debug log is empty
- Set `DEBUG = true` in `config.lua`.
- Check file path — the script runs from root `/ccpacker/debug.log`.
- Run `dclear()` to clear and verify file creation.

---

## Dependencies

- **PixelUI** (`pixelui.lua` + `shrekbox.lua`): Copied from sibling project `ccunloader`/`ccloader`. Provides the UI framework. No external download needed.
- **Numismatics mod**: Required for the Andesite Depositor and spur coins.
- **AE2 (Applied Energistics 2)**: Required for storage cells and the IO port.
- **Create mod**: Required for the Chute.
- **CC:Tweaked**: Required for ComputerCraft Lua environment.

---

## Design Principles

This project follows the same patterns as sibling projects (`ccunloader`, `ccloader`, `displayshop`):

1. **`parallel.waitForAny`** for concurrency (not PixelUI threads) because `peripheral.call()` yields for `peripheral_response`.
2. **Observer-pattern state** with change-detection to avoid unnecessary re-renders.
3. **Module-per-file** with explicit dependency injection via `init()`.
4. **Configuration in `config.lua`** as global variables — no config module, no state duplication.
5. **`dlog()` / `dclear()`** globals for consistent debug logging.
6. **`pcall` on all peripheral I/O** — hardware failures never crash the main loop.
7. **All widgets created once** — visibility toggles instead of destroy/recreate.

## Workflow Orchestration

### 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately — don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### 3. Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes — don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests — then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Task Management

1. **Plan First**: Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `tasks/todo.md`
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.
