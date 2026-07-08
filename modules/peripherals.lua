-- modules/peripherals.lua — Peripheral wrappers for ccpacker
-- Exports: init(), waitForPeripheral(), barrel analysis, cell helpers,
--          deposit/relay control, IO port polling, heartbeatLoop()
--
-- All peripheral I/O must run in a top-level parallel coroutine because
-- peripheral.call() yields for peripheral_response events which conflicts
-- with PixelUI's custom event scheduler.

local M = {}

-- Peripheral wrappers
local monitor    = nil  -- monitor_18 (UI display)
local depositor  = nil  -- Numismatics_Depositor_14 (coin payment)
local relay      = nil  -- redstone_relay_17 (depositor lock + payment detection)
local inputBbl   = nil  -- minecraft:barrel_10 (items to pack)
local chute      = nil  -- create:chute_0 (feeds cells to IO port)
local ioPort     = nil  -- ae2:io_port_1 (AE2 cell packing)
local cellBbl    = nil  -- "top" barrel (empty AE2 cells)

-- Cooldown tracking for lazy re-wrap
local _lastReWrapTime = {}

-- ============================================================================
-- Helpers
-- ============================================================================

-- Test if a peripheral wrapper is still alive by calling a generic method.
local function testPeripheral(p)
    if not p then return false end
    local ok = pcall(function()
        if p.getName then return p.getName()
        elseif p.getInput then return p.getInput("top")
        elseif p.list then return p.list()
        elseif p.items then return p.items()
        end
        return true
    end)
    return ok
end

-- ============================================================================
-- Lazy getters with 5-second cooldown on re-wrap
-- ============================================================================

local function getMonitor()
    if not monitor then
        local now = os.clock()
        if not _lastReWrapTime.monitor or now - _lastReWrapTime.monitor > 5 then
            _lastReWrapTime.monitor = now
            monitor = peripheral.wrap(MONITOR)
        end
    end
    return monitor
end

local function getDepositor()
    if not depositor then
        local now = os.clock()
        if not _lastReWrapTime.depositor or now - _lastReWrapTime.depositor > 5 then
            _lastReWrapTime.depositor = now
            depositor = peripheral.wrap(DEPOSITOR)
        end
    end
    return depositor
end

local function getRelay()
    if not relay then
        local now = os.clock()
        if not _lastReWrapTime.relay or now - _lastReWrapTime.relay > 5 then
            _lastReWrapTime.relay = now
            relay = peripheral.wrap(RELAY)
        end
    end
    return relay
end

local function getInputBarrel()
    if not inputBbl then
        local now = os.clock()
        if not _lastReWrapTime.inputBbl or now - _lastReWrapTime.inputBbl > 5 then
            _lastReWrapTime.inputBbl = now
            inputBbl = peripheral.wrap(INPUT_BARREL)
        end
    end
    return inputBbl
end

local function getChute()
    if not chute then
        local now = os.clock()
        if not _lastReWrapTime.chute or now - _lastReWrapTime.chute > 5 then
            _lastReWrapTime.chute = now
            chute = peripheral.wrap(CHUTE)
        end
    end
    return chute
end

local function getIoPort()
    if not ioPort then
        local now = os.clock()
        if not _lastReWrapTime.ioPort or now - _lastReWrapTime.ioPort > 5 then
            _lastReWrapTime.ioPort = now
            ioPort = peripheral.wrap(IO_PORT)
        end
    end
    return ioPort
end

local function getCellBarrel()
    if not cellBbl then
        local now = os.clock()
        if not _lastReWrapTime.cellBbl or now - _lastReWrapTime.cellBbl > 5 then
            _lastReWrapTime.cellBbl = now
            cellBbl = peripheral.wrap(CELL_BARREL)
        end
    end
    return cellBbl
end

-- Expose getters so vendor module can access them
M.getInputBarrel  = getInputBarrel
M.getCellBarrel   = getCellBarrel
M.getChute        = getChute
M.getIoPort       = getIoPort
M.getDepositor    = getDepositor
M.getRelay        = getRelay

-- ============================================================================
-- Probe peripheral methods at startup (debug helper)
-- ============================================================================

local function probeMethods(name, label)
    dlog("probeMethods(" .. label .. "): peripheral.getMethods(" .. tostring(name) .. ")")
    local ok, methods = pcall(function() return peripheral.getMethods(name) end)
    if ok and type(methods) == "table" then
        local strs = {}
        for _, m in ipairs(methods) do strs[#strs + 1] = tostring(m) end
        dlog("probeMethods(" .. label .. "): methods: " .. table.concat(strs, ", "))
    elseif ok then
        dlog("probeMethods(" .. label .. "): methods returned " .. type(methods))
    else
        dlog("probeMethods(" .. label .. "): methods threw: " .. tostring(methods))
    end
end

-- ============================================================================
-- Initialisation — blocking peripheral polling
-- ============================================================================

function M.init()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    print("=== CCPACKER ===")
    print("Scanning for peripherals...")
    print("")

    dlog("init: waiting for monitor '" .. tostring(MONITOR) .. "'")
    monitor = M.waitForPeripheral(MONITOR, "Monitor: " .. MONITOR)

    dlog("init: waiting for depositor '" .. tostring(DEPOSITOR) .. "'")
    depositor = M.waitForPeripheral(DEPOSITOR, "Depositor: " .. DEPOSITOR)

    dlog("init: waiting for relay '" .. tostring(RELAY) .. "'")
    relay = M.waitForPeripheral(RELAY, "Relay: " .. RELAY)

    dlog("init: waiting for input barrel '" .. tostring(INPUT_BARREL) .. "'")
    inputBbl = M.waitForPeripheral(INPUT_BARREL, "Input: " .. INPUT_BARREL)

    dlog("init: waiting for chute '" .. tostring(CHUTE) .. "'")
    chute = M.waitForPeripheral(CHUTE, "Chute: " .. CHUTE)

    dlog("init: waiting for IO port '" .. tostring(IO_PORT) .. "'")
    ioPort = M.waitForPeripheral(IO_PORT, "IO Port: " .. IO_PORT)

    dlog("init: waiting for cell barrel '" .. tostring(CELL_BARREL) .. "'")
    cellBbl = M.waitForPeripheral(CELL_BARREL, "Cell Bbl: " .. CELL_BARREL)

    -- Set relay output HIGH on startup to lock the depositor
    do
        local ok, err = pcall(function() relay:setOutput(RELAY_LOCK_SIDE, true) end)
        if ok then
            dlog("init: relay setOutput HIGH on " .. tostring(RELAY_LOCK_SIDE) .. " = true")
        else
            dlog("init: relay setOutput FAILED on " .. tostring(RELAY_LOCK_SIDE) .. ": " .. tostring(err))
        end
    end
    M.verifyLock(true)
    dlog("init: relay.getOutput(" .. tostring(RELAY_LOCK_SIDE) .. ")=" .. tostring(relay.getOutput(RELAY_LOCK_SIDE)))
    dlog("init: relay.getInput(" .. tostring(RELAY_LOCK_SIDE) .. ")=" .. tostring(relay.getInput(RELAY_LOCK_SIDE)))

    -- Probe peripheral methods to verify APIs
    probeMethods(RELAY, "relay")
    probeMethods(DEPOSITOR, "depositor")
    probeMethods(CHUTE, "chute")
    probeMethods(IO_PORT, "io_port")

    dlog("init: all peripherals found successfully")
end

-- Cross-chunk peripheral scanner (blocking — used only at init)
function M.waitForPeripheral(name, label)
    label = label or tostring(name)
    local attempts = 0
    while true do
        local ok, periph = pcall(peripheral.wrap, name)
        if ok and periph then
            if attempts > 0 then
                term.setTextColor(colors.green)
                print("[CCPACK] OK  " .. label)
                term.setTextColor(colors.white)
                dlog("waitForPeripheral(" .. label .. "): appeared after " .. tostring(attempts) .. " attempt(s)")
            end
            return periph
        end
        attempts = attempts + 1
        if attempts == 1 then
            term.setTextColor(colors.yellow)
            print("[CCPACK] Waiting for: " .. label)
            term.setTextColor(colors.gray)
            print("  peripheral: " .. tostring(name))
            print("  (chunk may not be loaded)")
            term.setTextColor(colors.white)
            dlog("waitForPeripheral: " .. label .. " (" .. tostring(name) .. ") not available yet")
        end
        os.sleep(PERIPHERAL_SCAN_INTERVAL)
    end
end

-- ============================================================================
-- Barrel inventory helpers
-- ============================================================================

-- Get total count of ALL items in the input barrel (regardless of type).
-- Uses barrel:list() which returns a sparse table {slot = {name, count, ...}}.
-- Returns 0 on error.
function M.getTotalItemCount()
    local bbl = getInputBarrel()
    if not bbl then
        dlog("getTotalItemCount: input barrel is nil")
        return 0
    end

    local ok, items = pcall(function() return bbl.list() end)
    if not ok or type(items) ~= "table" then
        dlog("getTotalItemCount: list() failed: " .. tostring(items))
        return 0
    end

    local total = 0
    for _, item in pairs(items) do
        total = total + (item.count or 0)
    end

    dlog("getTotalItemCount: " .. tostring(total) .. " items")
    return total
end

-- Count unique item types (unique 'name' values) in the input barrel.
-- Returns 0 on error.
function M.getUniqueItemTypes()
    local bbl = getInputBarrel()
    if not bbl then
        dlog("getUniqueItemTypes: input barrel is nil")
        return 0
    end

    local ok, items = pcall(function() return bbl.list() end)
    if not ok or type(items) ~= "table" then
        dlog("getUniqueItemTypes: list() failed: " .. tostring(items))
        return 0
    end

    local seen = {}
    local count = 0
    for _, item in pairs(items) do
        if item and item.name and not seen[item.name] then
            seen[item.name] = true
            count = count + 1
        end
    end

    dlog("getUniqueItemTypes: " .. tostring(count) .. " types")
    return count
end

-- Get both total items and unique types in one call (avoids double list()).
-- Returns {totalItems = int, uniqueTypes = int}.
function M.getBarrelItems()
    local bbl = getInputBarrel()
    if not bbl then
        dlog("getBarrelItems: input barrel is nil")
        return { totalItems = 0, uniqueTypes = 0 }
    end

    local ok, items = pcall(function() return bbl.list() end)
    if not ok or type(items) ~= "table" then
        dlog("getBarrelItems: list() failed: " .. tostring(items))
        return { totalItems = 0, uniqueTypes = 0 }
    end

    local total = 0
    local seen = {}
    for _, item in pairs(items) do
        total = total + (item.count or 0)
        if item and item.name then
            seen[item.name] = true
        end
    end

    local types = 0
    for _ in pairs(seen) do types = types + 1 end

    dlog("getBarrelItems: " .. tostring(total) .. " items, " .. tostring(types) .. " types")
    return { totalItems = total, uniqueTypes = types }
end

-- Check if input barrel has any items at all.
function M.hasAnyItems()
    return M.getTotalItemCount() > 0
end

-- ============================================================================
-- Cell barrel helpers
-- ============================================================================

-- Find a specific cell item in the cell barrel (top barrel).
-- Returns {slot = int, count = int} or nil if not found.
function M.findCellInBarrel(cellName)
    local bbl = getCellBarrel()
    if not bbl then
        dlog("findCellInBarrel: cell barrel is nil")
        return nil
    end

    local ok, items = pcall(function() return bbl.list() end)
    if not ok or type(items) ~= "table" then
        dlog("findCellInBarrel: list() failed: " .. tostring(items))
        return nil
    end

    for slot, item in pairs(items) do
        if item and item.name == cellName then
            dlog("findCellInBarrel: found " .. tostring(cellName) .. " at slot " .. tostring(slot) .. " (count=" .. tostring(item.count) .. ")")
            return { slot = slot, count = item.count }
        end
    end

    dlog("findCellInBarrel: " .. tostring(cellName) .. " NOT found in cell barrel")
    return nil
end

-- Push an empty cell from the cell barrel into the chute.
-- The chute drops it into the IO port which recognises it.
-- Returns true on success, false on failure.
function M.pushCellToChute(cellName)
    local src = getCellBarrel()
    local dst = getChute()
    if not src or not dst then
        dlog("pushCellToChute: cell barrel or chute is nil")
        return false
    end

    local cell = M.findCellInBarrel(cellName)
    if not cell then
        dlog("pushCellToChute: " .. tostring(cellName) .. " not found in cell barrel")
        return false
    end

    dlog("pushCellToChute: pushing " .. tostring(cellName) .. " from slot " .. tostring(cell.slot) .. " to chute")
    local ok, moved = pcall(function()
        return src.pushItems(CHUTE, cell.slot, 1)
    end)

    if ok and moved and moved > 0 then
        dlog("pushCellToChute: success, moved " .. tostring(moved) .. " item(s)")
        return true
    else
        dlog("pushCellToChute: pushItems failed: " .. tostring(moved))
        -- Fallback: try pullItems from chute side
        local ok2, moved2 = pcall(function()
            return dst.pullItems(CELL_BARREL, cell.slot, 1)
        end)
        if ok2 and moved2 and moved2 > 0 then
            dlog("pushCellToChute: pullItems fallback worked")
            return true
        end
        dlog("pushCellToChute: all methods failed")
        return false
    end
end

-- ============================================================================
-- IO port helpers
-- ============================================================================

-- Poll the IO port's items() method.
-- Returns: {} (empty) = still packing, or {{name = "ae2:...", ...}} = done.
-- Returns {} on error.
function M.getIoPortItems()
    local port = getIoPort()
    if not port then
        dlog("getIoPortItems: IO port is nil")
        return {}
    end

    local ok, items = pcall(function() return port.items() end)
    if not ok or type(items) ~= "table" then
        dlog("getIoPortItems: items() failed: " .. tostring(items))
        return {}
    end

    if #items == 0 then
        dlog("getIoPortItems: empty (still packing)")
    else
        dlog("getIoPortItems: " .. tostring(#items) .. " item(s) found")
    end
    return items
end

-- Pull a finished AE2 cell from the IO port back to the input barrel.
-- Uses pushItem (by item NAME) — confirmed working.
-- Returns true on success, false on failure.
function M.pullCellFromIoPort(cellName)
    local port = getIoPort()
    local bbl = getInputBarrel()
    if not port or not bbl then
        dlog("pullCellFromIoPort: IO port or input barrel is nil")
        return false
    end

    dlog("pullCellFromIoPort: pulling " .. tostring(cellName) .. " -> " .. tostring(INPUT_BARREL))
    local ok, moved = pcall(function()
        return port.pushItem(INPUT_BARREL, cellName, 1)
    end)

    if ok and moved and moved > 0 then
        dlog("pullCellFromIoPort: success, moved " .. tostring(moved) .. " x " .. tostring(cellName))
        return true
    else
        dlog("pullCellFromIoPort: pushItem failed: " .. tostring(moved))
        return false
    end
end

-- ============================================================================
-- Relay output verification
-- ============================================================================

-- Verify relay output state using getOutput().
-- Retries once if mismatch. Returns true if output matches expected.
function M.verifyLock(expected)
    local rl = getRelay()
    if not rl then return false end
    os.sleep(0.05)
    local current = rl.getOutput(RELAY_LOCK_SIDE)
    if current == expected then
        dlog("verifyLock: OK, output=" .. tostring(expected) .. " on " .. tostring(RELAY_LOCK_SIDE))
        return true
    end
    dlog("verifyLock: MISMATCH — expected=" .. tostring(expected) .. ", got=" .. tostring(current) .. " on " .. tostring(RELAY_LOCK_SIDE))
    -- Retry once
    pcall(function() rl.setOutput(RELAY_LOCK_SIDE, expected) end)
    os.sleep(0.1)
    current = rl.getOutput(RELAY_LOCK_SIDE)
    if current == expected then
        dlog("verifyLock: retry OK")
        return true
    end
    dlog("verifyLock: retry FAILED — still " .. tostring(current))
    return false
end

-- ============================================================================
-- Depositor / relay helpers
-- ============================================================================

-- Set the total price on the depositor using setCoinAmount("spur", amount).
function M.setCoinAmount(amount)
    local dep = getDepositor()
    if not dep then
        dlog("setCoinAmount: depositor nil")
        return false
    end
    local ok, err = pcall(function() dep.setCoinAmount("spur", amount) end)
    if ok then
        dlog("setCoinAmount: set spur " .. tostring(amount))
        return true
    else
        dlog("setCoinAmount: failed: " .. tostring(err))
        return false
    end
end

-- Lock the depositor (set relay output HIGH — blocks coin insertion).
function M.lockDepositor()
    local rl = getRelay()
    if rl then
        local ok, err = pcall(function() rl.setOutput(RELAY_LOCK_SIDE, true) end)
        if ok then
            dlog("lockDepositor: relay setOutput HIGH on " .. tostring(RELAY_LOCK_SIDE) .. " = true")
        else
            dlog("lockDepositor: relay setOutput FAILED on " .. tostring(RELAY_LOCK_SIDE) .. ": " .. tostring(err))
        end
        M.verifyLock(true)
    else
        dlog("lockDepositor: relay nil")
    end
end

-- Unlock the depositor (set relay output LOW — accepts coins).
function M.unlockDepositor()
    local rl = getRelay()
    if rl then
        local ok, err = pcall(function() rl.setOutput(RELAY_LOCK_SIDE, false) end)
        if ok then
            dlog("unlockDepositor: relay setOutput LOW on " .. tostring(RELAY_LOCK_SIDE) .. " = false")
        else
            dlog("unlockDepositor: relay setOutput FAILED on " .. tostring(RELAY_LOCK_SIDE) .. ": " .. tostring(err))
        end
        M.verifyLock(false)
    else
        dlog("unlockDepositor: relay nil")
    end
end

-- Get all relay input sides as table side→value.
-- Returns empty table on error.
function M.getAllRelayInputs()
    local rl = getRelay()
    if not rl then
        dlog("getAllRelayInputs: relay nil")
        return {}
    end
    local sides = {"bottom", "top", "front", "back", "left", "right"}
    local inputs = {}
    for _, side in ipairs(sides) do
        local ok, val = pcall(function() return rl.getInput(side) end)
        if ok then
            inputs[side] = val
        elseif DEBUG then
            dlog("getAllRelayInputs: getInput(" .. side .. ") error: " .. tostring(val))
            inputs[side] = nil
        end
    end
    return inputs
end

-- ============================================================================
-- Heartbeat — checks peripheral aliveness every 10s
-- ============================================================================

function M.heartbeatLoop()
    dlog("heartbeatLoop: started (interval: 10s)")
    while true do
        os.sleep(10)
        local ok, err = pcall(function()
            if monitor and not testPeripheral(monitor) then
                monitor = nil; dlog("heartbeat: monitor dead")
            end
            if depositor and not testPeripheral(depositor) then
                depositor = nil; dlog("heartbeat: depositor dead")
            end
            if relay and not testPeripheral(relay) then
                relay = nil; dlog("heartbeat: relay dead")
            end
            if inputBbl and not testPeripheral(inputBbl) then
                inputBbl = nil; dlog("heartbeat: input barrel dead")
            end
            if chute and not testPeripheral(chute) then
                chute = nil; dlog("heartbeat: chute dead")
            end
            if ioPort and not testPeripheral(ioPort) then
                ioPort = nil; dlog("heartbeat: IO port dead")
            end
            if cellBbl and not testPeripheral(cellBbl) then
                cellBbl = nil; dlog("heartbeat: cell barrel dead")
            end
        end)
        if not ok then
            dlog("heartbeatLoop: error — " .. tostring(err))
        end
    end
end

return M
