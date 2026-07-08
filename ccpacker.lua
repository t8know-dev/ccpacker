-- ccpacker.lua — AE2 Item Packing Station for CC:Tweaked
-- Packs items from an input barrel into AE2 storage cells via an IO Port.
--
-- Flow: splash (3s) → idle → prompt → cell_choice → payment → packing → thankyou (5s) → idle
--                                              ↑       ↑          ↓          ↓
--                                         ABORT / timeout ────┴──── error ──┘
--
-- Runs four parallel coroutines at top level:
--   1. PixelUI event loop  (handles monitor input, renders UI)
--   2. Vendor loop         (transaction state machine)
--   3. Payment monitor     (poll relay inputs for payment detection)
--   4. Heartbeat           (peripheral aliveness checks)

dofile("/ccpacker/config.lua")
local pixelui = require("pixelui")
dclear()

-- ---------------------------------------------------------------------------
-- Module loading with error reporting
-- ---------------------------------------------------------------------------

local function loadMod(path)
    local ok, mod = pcall(dofile, "/ccpacker/" .. path .. ".lua")
    if not ok then error("Failed to load " .. path .. ": " .. tostring(mod)) end
    return mod
end

local periphs = loadMod("modules/peripherals")
local st      = loadMod("modules/state")
local ui      = loadMod("modules/ui")
local pay     = loadMod("modules/payment")
local vend    = loadMod("modules/vendor")

-- Initialise modules
periphs.init()
ui.init(pixelui)
pay.init()
vend.init(st, periphs, ui, pay)

-- State subscriber: re-render UI on screen/state changes
st.subscribe(function(changes)
    if changes.screen ~= nil or changes.blinkVisible ~= nil then
        ui.updateScreen(st.getState())
    end
end)

-- ---------------------------------------------------------------------------
-- Custom PixelUI event loop compatible with parallel.waitForAny
-- ---------------------------------------------------------------------------

local function runPixelUI(app)
    app.running = true
    app:render()
    while app.running do
        local event = { os.pullEvent() }
        if event[1] == "terminate" then
            app.running = false
        else
            app:step(table.unpack(event))
        end
    end
end

-- ---------------------------------------------------------------------------
-- Callbacks for UI buttons
-- ---------------------------------------------------------------------------

local function onPackClick()
    if st.getState("screen") == "prompt" then
        dlog("PACK clicked")
        st.updateState({
            screen = "cell_choice",
            screenEntryTime = os.clock(),
        })
    end
end

local function onPortableClick()
    if st.getState("screen") == "cell_choice" then
        dlog("PORTABLE clicked")
        vend.selectCellType("portable")
    end
end

local function onNormalClick()
    if st.getState("screen") == "cell_choice" then
        dlog("NORMAL clicked")
        vend.selectCellType("normal")
    end
end

local function onCancelClick()
    if st.getState("screen") == "payment" then
        dlog("ABORT clicked during payment")
        vend.cancelPayment()
    end
end

-- ---------------------------------------------------------------------------
-- Main startup
-- ---------------------------------------------------------------------------

local startupOk, startupErr = pcall(function()
    -- Monitor is already wrapped by periphs.init() — create the UI
    local mon = peripheral.wrap(MONITOR)
    if not mon then
        error("Monitor '" .. tostring(MONITOR) .. "' not available after init!")
    end

    -- Create the PixelUI app with all widgets
    local app = ui.createUI(mon, {
        onPackClick     = onPackClick,
        onPortableClick = onPortableClick,
        onNormalClick   = onNormalClick,
        onCancelClick   = onCancelClick,
    })

    -- Show splash screen
    st.updateState({ screen = "splash" })
    ui.updateScreen(st.getState())
    dlog("splash: showing for " .. tostring(SPLASH_DELAY) .. "s")
    os.sleep(SPLASH_DELAY)

    -- Transition to idle screen
    dlog("startup: entering idle screen")
    st.updateState({
        screen = "idle",
        screenEntryTime = os.clock(),
    })

    -- Run parallel coroutines:
    --   1. PixelUI event loop  (UI only)
    --   2. Vendor loop         (transaction state machine)
    --   3. Payment monitor     (relay input polling)
    --   4. Heartbeat           (peripheral aliveness)
    dlog("starting parallel coroutines")
    parallel.waitForAny(
        function() runPixelUI(app) end,
        function() vend.vendorLoop() end,
        function() pay.paymentMonitorLoop(st, periphs) end,
        function() periphs.heartbeatLoop() end
    )
end)

if not startupOk then
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print("ccpacker: FATAL ERROR")
    print(tostring(startupErr))
    term.setTextColor(colors.white)
    dlog("FATAL: " .. tostring(startupErr))
end
