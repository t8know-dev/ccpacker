-- config.lua — CCPacker machine configuration
-- Packs items from an input barrel into AE2 storage cells via an AE2 IO Port.
--
-- Peripherals:
--   MONITOR      monitor_18             (UI display, 1x1)
--   DEPOSITOR    Numismatics_Depositor_14 (coin payment)
--   RELAY        redstone_relay_17       (depositor lock + payment detection)
--   INPUT_BARREL  minecraft:barrel_10    (items to pack, receives finished cell)
--   CHUTE        create:chute_0          (feeds empty cells into IO port)
--   IO_PORT      ae2:io_port_1           (packs items into AE2 cells)
--   CELL_BARREL  "top" (computer top)    (contains empty AE2 cells)

-- Peripherals
MONITOR        = "monitor_1170"
DEPOSITOR      = "Numismatics_Depositor_33"
RELAY          = "redstone_relay_73"
INPUT_BARREL   = "expandedstorage:netherite_chest_0"
CHUTE          = "create:chute_6"
IO_PORT        = "ae2:io_port_2"
CELL_BARREL    = "expandedstorage:netherite_barrel_10"   -- Computer top face — barrel with empty AE2 cells

-- Direction from the cell barrel to the chute (side, not peripheral name).
-- If the chute is below the barrel, use "bottom". Adjust for your layout.
CELL_CHUTE_DIR = "top"

-- Redstone relay configuration
RELAY_LOCK_SIDE         = "top"   -- Relay output → depositor lock (HIGH = locked)
PAYMENT_DETECTION_SIDE  = "top"   -- Relay input ← depositor payment signal

-- Coin name for depositor API
COIN_NAME = "spur"

-- Cell type definitions -------------------------------------------------------
-- Each entry: id (AE2 item ID), label (display name), itemCap (max items),
--             typeCap (max unique item types), price (in spurs)
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

-- Timing (seconds)
PERIPHERAL_SCAN_INTERVAL = 1     -- Peripheral scan interval at startup
BARREL_CHECK_INTERVAL   = 3     -- How often to check input barrel for items
PACKING_POLL_INTERVAL   = 1     -- How often to poll IO port during packing
SCREEN_TIMEOUT          = 120   -- General timeout: screens return to idle after this
PAYMENT_TIMEOUT         = 60    -- Seconds to wait for payment after unlocking depositor
THANKYOU_DELAY          = 5     -- Seconds to show thank-you screen
ERROR_DELAY             = 2     -- Seconds to show error screen
SPLASH_DELAY            = 3     -- Seconds to show splash screen
TRANSFER_TICK_INTERVAL  = 0.1   -- Vendor loop poll interval

-- Version
APP_VERSION = "v0.6"

-- UI Messages — monitor scale 0.5, 1×1 monitor ≈ 26×8 chars. Keep text SHORT.
MSG = {
    header            = "CC PACKER",
    splash_line1      = "CC PACKER",
    splash_line2      = "Item Packer",
    splash_line3      = APP_VERSION,

    idle_line1        = "Order pickup",

    prompt_line1      = "Pack items to",
    prompt_line2      = "an AE2 cell?",
    pack_btn          = "PACK",

    cell_choice_title = "Choose",
    cell_choice_line2 = "cell type",
    portable_btn      = "PORTABLE",
    normal_btn        = "NORMAL",

    payment_line1     = "Please insert",
    payment_line2     = "%d spur(s)",
    payment_line3     = "into the",
    payment_line4     = "depositor",
    cancel_btn        = "ABORT",

    packing_title     = "Packing...",
    progress_text     = "%d/%d (%d%%)",

    thanks_line1      = "Thank you!",
    thanks_line2      = "Packing done",
    thanks_line4      = "Collect",
    thanks_line5      = "your cell",

    error_timeout     = "Timeout!",
    error_stock       = "No items to pack!",
    error_cell        = "Cell not",
    error_cell_line2  = "available",
    error_capacity    = "Items exceed!",
    error_depositor   = "Depositor error!",
    error_transaction = "Transaction failed!",
    error_port        = "IO port error!",
    error_line1       = "Error!",
}

-- Debug
DEBUG     = false
DEBUG_LOG = "/ccpacker/debug.log"

-- Temporary native-terminal redirect + print, then restore.
local function sprint(...)
    local prev = term.redirect(term.native())
    print(...)
    if prev then term.redirect(prev) end
end

-- Debug log: prints to native terminal AND appends to debug.log.
function dlog(...)
    if not DEBUG then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    local msg = table.concat(parts, " ")
    local line = "[" .. os.clock() .. "] [CCPACK] " .. msg
    pcall(sprint, line)
    local f = fs.open(DEBUG_LOG, "a")
    if f then
        f:writeLine(line)
        f:close()
    end
end

-- Clear debug log file.
function dclear()
    if not DEBUG then return end
    local f = fs.open(DEBUG_LOG, "w")
    if f then f:close() end
    dlog("=== debug log cleared ===")
end
