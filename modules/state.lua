-- modules/state.lua — Centralized state management for ccpacker
-- Exports: getState(), updateState(changes), subscribe(callback)
-- Observer pattern: subscribers notified only on actual value changes.

local M = {}

local state = {
    screen        = "splash",   -- splash | idle | prompt | cell_choice | payment | packing | thankyou | error
    hasStock      = false,      -- true when input barrel has any items

    -- Cell selection
    cellType      = nil,        -- "portable" | "normal" (user choice)
    cellSize      = nil,        -- "1k" | "4k" | "16k" (calculated)
    selectedCell  = nil,        -- full entry from CELL_TYPES table (id, label, itemCap, typeCap, price)

    -- Barrel contents info
    totalBarrelItems  = 0,      -- total item count in input barrel when calculated
    uniqueItemTypes   = 0,      -- unique item types count in input barrel
    initialItemCount  = 0,      -- barrel item count snapshot when packing starts (for progress)

    -- Payment
    totalPrice      = 0,
    paymentDeadline = nil,      -- os.clock() deadline for payment
    paymentBaseline = nil,      -- table {side=value} of relay inputs before unlock
    paymentPaid     = false,

    -- Packing
    transferred     = 0,        -- items removed from barrel so far (for progress bar)
    cellPushed      = false,    -- true once the empty cell has been pushed to chute

    -- Idle screen blink
    blinkVisible    = true,     -- toggled for idle screen arrow animation

    -- Screen entry time (general timeout)
    screenEntryTime = nil,

    -- Error
    errorMsg        = "",
    errorMsgLine2   = "",   -- second line for multi-line error messages
}

local subscribers = {}

-- Public API

function M.getState(key)
    if key then return state[key] end
    return state
end

function M.updateState(changes)
    local hasChanges = false
    for k, v in pairs(changes) do
        if state[k] ~= v then
            state[k] = v
            hasChanges = true
        end
    end
    if hasChanges then
        for _, cb in ipairs(subscribers) do
            pcall(cb, changes)
        end
    end
end

function M.subscribe(callback)
    table.insert(subscribers, callback)
end

function M.resetTransaction()
    state.cellType = nil
    state.cellSize = nil
    state.selectedCell = nil
    state.transferred = 0
    state.totalBarrelItems = 0
    state.uniqueItemTypes = 0
    state.initialItemCount = 0
    state.cellPushed = false
    state.paymentDeadline = nil
    state.paymentBaseline = nil
    state.paymentPaid = false
    state.errorMsg = ""
    state.errorMsgLine2 = ""
end

return M
