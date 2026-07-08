-- modules/vendor.lua — Transaction state machine for ccpacker
-- Exports: init(st, periphs, ui, pay), vendorLoop(), cancelPayment()
--
-- State flow:
--   splash → idle → prompt → cell_choice → payment → packing → thankyou → idle
--              ↑       ↑          ↑            ↑          ↓          ↓
--              └───────┴──────────┴────────────┴─ timeout ┘    error ──┘
--
-- Runs as a top-level parallel coroutine (not inside PixelUI threads).

local M = {}

local st       -- state module
local periphs  -- peripherals module
local ui       -- ui module
local pay      -- payment module

-- Local flags for state machine
local paymentSetupDone    = false
local idleBlinkTimer      = 0     -- os.clock() tracker for blink toggle
local idleCheckTimer      = 0     -- os.clock() tracker for barrel check
local promptCheckTimer    = 0     -- os.clock() tracker for prompt barrel check
local blinkState          = true  -- current blink state

function M.init(stateModule, peripheralsModule, uiModule, paymentModule)
    st = stateModule
    periphs = peripheralsModule
    ui = uiModule
    pay = paymentModule
end

-- ============================================================================
-- Helper: calculate the smallest AE2 cell that fits both item and type counts
-- ============================================================================

function M._calculateRequiredCell(totalItems, uniqueTypes, cellType)
    local cells = CELL_TYPES[cellType]
    if not cells then
        dlog("_calculateRequiredCell: unknown cellType '" .. tostring(cellType) .. "'")
        return nil
    end
    for _, cell in ipairs(cells) do
        if totalItems <= cell.itemCap and uniqueTypes <= cell.typeCap then
            dlog("_calculateRequiredCell: selected " .. tostring(cell.id)
                .. " for " .. tostring(totalItems) .. " items, " .. tostring(uniqueTypes) .. " types")
            return cell
        end
    end
    dlog("_calculateRequiredCell: NO cell fits " .. tostring(totalItems) .. " items, " .. tostring(uniqueTypes) .. " types")
    return nil
end

-- ============================================================================
-- Main vendor loop
-- ============================================================================

function M.vendorLoop()
    dlog("vendorLoop: started")
    while true do
        local ok, err = pcall(function()
            local state = st.getState()
            local screen = state.screen

            if screen == "idle" then
                M._handleIdleState()

            elseif screen == "prompt" then
                M._handlePromptState()

            elseif screen == "cell_choice" then
                M._handleCellChoiceState()

            elseif screen == "payment" then
                M._handlePaymentState()

            elseif screen == "packing" then
                M._handlePackingState()

            elseif screen == "thankyou" then
                dlog("vendorLoop: thankyou screen, waiting " .. tostring(THANKYOU_DELAY) .. "s")
                periphs.lockDepositor()
                os.sleep(THANKYOU_DELAY)
                st.resetTransaction()
                st.updateState({ screen = "idle", screenEntryTime = os.clock() })

            elseif screen == "error" then
                dlog("vendorLoop: error screen, waiting " .. tostring(ERROR_DELAY) .. "s")
                periphs.lockDepositor()
                os.sleep(ERROR_DELAY)
                st.resetTransaction()
                st.updateState({ screen = "idle", screenEntryTime = os.clock() })
            end
        end)
        if not ok then
            dlog("vendorLoop: error — " .. tostring(err))
            pcall(periphs.lockDepositor)
            paymentSetupDone = false
        end
        os.sleep(TRANSFER_TICK_INTERVAL)
    end
end

-- ============================================================================
-- Idle state: blink animation + periodic barrel check
-- ============================================================================

function M._handleIdleState()
    local now = os.clock()
    local state = st.getState()

    -- Toggle blink every 0.5s
    if now - idleBlinkTimer >= 0.5 then
        idleBlinkTimer = now
        blinkState = not blinkState
        if blinkState ~= state.blinkVisible then
            st.updateState({ blinkVisible = blinkState })
        end
    end

    -- Check barrel every BARREL_CHECK_INTERVAL
    if now - idleCheckTimer >= BARREL_CHECK_INTERVAL then
        idleCheckTimer = now
        local items = periphs.getBarrelItems()
        if items.totalItems > 0 then
            dlog("_handleIdleState: " .. tostring(items.totalItems) .. " items found, transitioning to prompt")
            st.updateState({
                screen = "prompt",
                screenEntryTime = os.clock(),
                hasStock = true,
                totalBarrelItems = items.totalItems,
                uniqueItemTypes = items.uniqueTypes,
            })
        end
    end
end

-- ============================================================================
-- Prompt state: wait for PACK click or timeout
-- ============================================================================

function M._handlePromptState()
    local state = st.getState()
    local entryTime = state.screenEntryTime or 0
    local now = os.clock()

    -- Timeout check
    if now >= entryTime + SCREEN_TIMEOUT then
        dlog("_handlePromptState: timeout, returning to idle")
        st.updateState({ screen = "idle", screenEntryTime = now })
        return
    end

    -- Throttle barrel check to BARREL_CHECK_INTERVAL — list() is expensive
    if now - promptCheckTimer < BARREL_CHECK_INTERVAL then
        return
    end
    promptCheckTimer = now

    -- If items are removed while on this screen and the barrel becomes empty,
    -- transition to error.
    local items = periphs.getBarrelItems()
    if items.totalItems <= 0 then
        dlog("_handlePromptState: barrel became empty")
        st.updateState({
            screen = "error",
            errorMsg = MSG.error_stock or "No items to pack!",
        })
        return
    end

    -- Re-measure in case items changed
    st.updateState({
        totalBarrelItems = items.totalItems,
        uniqueItemTypes = items.uniqueTypes,
    })
end

-- ============================================================================
-- Cell choice state: wait for PORTABLE/NORMAL selection or timeout
-- ============================================================================

function M._handleCellChoiceState()
    local state = st.getState()
    local entryTime = state.screenEntryTime or 0

    -- Timeout check
    if os.clock() >= entryTime + SCREEN_TIMEOUT then
        dlog("_handleCellChoiceState: timeout, returning to idle")
        st.updateState({ screen = "idle", screenEntryTime = os.clock() })
        return
    end
end

-- ============================================================================
-- Called when user clicks PORTABLE or NORMAL
-- ============================================================================

function M.selectCellType(cellType)
    dlog("selectCellType: " .. tostring(cellType))

    local state = st.getState()
    local totalItems = state.totalBarrelItems
    local uniqueTypes = state.uniqueItemTypes

    -- Re-measure barrel in case contents changed
    local items = periphs.getBarrelItems()
    if items.totalItems <= 0 then
        dlog("selectCellType: barrel is empty")
        st.updateState({
            screen = "error",
            errorMsg = MSG.error_stock or "No items to pack!",
        })
        return
    end
    totalItems = items.totalItems
    uniqueTypes = items.uniqueTypes
    st.updateState({
        totalBarrelItems = totalItems,
        uniqueItemTypes = uniqueTypes,
    })

    -- Calculate required cell size
    local cell = M._calculateRequiredCell(totalItems, uniqueTypes, cellType)
    if not cell then
        dlog("selectCellType: no cell fits " .. tostring(totalItems) .. " items, " .. tostring(uniqueTypes) .. " types")
        st.updateState({
            screen = "error",
            errorMsg = MSG.error_capacity or "Items exceed capacity!",
        })
        return
    end

    -- Check if cell is available in the cell barrel
    local found = periphs.findCellInBarrel(cell.id)
    if not found then
        dlog("selectCellType: " .. tostring(cell.id) .. " not in cell barrel")
        st.updateState({
            screen = "error",
            errorMsg = MSG.error_cell or "Cell not available!",
        })
        return
    end

    -- Transition to payment
    dlog("selectCellType: selected " .. tostring(cell.id) .. " (price=" .. tostring(cell.price) .. ")")
    st.updateState({
        screen = "payment",
        screenEntryTime = os.clock(),
        cellType = cellType,
        cellSize = cell.label,
        selectedCell = cell,
        totalPrice = cell.price,
    })
end

-- ============================================================================
-- Payment state handler (adapted from ccpacker's predecessor)
-- ============================================================================

function M._handlePaymentState()
    local state = st.getState()

    if not paymentSetupDone then
        -- FIRST ENTRY — set up the depositor

        if st.getState("screen") ~= "payment" then
            dlog("_handlePaymentState: payment cancelled before setup")
            return
        end

        local price = state.totalPrice

        -- Guard: re-check barrel has items
        local items = periphs.getBarrelItems()
        if items.totalItems <= 0 then
            dlog("_handlePaymentState: barrel empty before payment")
            periphs.lockDepositor()
            st.updateState({
                screen = "error",
                errorMsg = MSG.error_stock or "No items to pack!",
            })
            return
        end
        st.updateState({
            totalBarrelItems = items.totalItems,
            uniqueItemTypes = items.uniqueTypes,
        })

        -- Configure depositor
        local priceOk = periphs.setCoinAmount(price)
        if not priceOk then
            dlog("_handlePaymentState: setCoinAmount failed")
            periphs.lockDepositor()
            st.updateState({
                screen = "error",
                errorMsg = MSG.error_depositor or "Depositor error!",
            })
            return
        end

        -- Guard: re-check screen before unlocking
        if st.getState("screen") ~= "payment" then
            dlog("_handlePaymentState: cancelled during setup")
            pcall(periphs.setCoinAmount, 0)
            return
        end

        -- Unlock depositor to accept payment
        periphs.unlockDepositor()
        os.sleep(0.5)

        -- Guard: re-check screen after stabilisation yield
        if st.getState("screen") ~= "payment" then
            dlog("_handlePaymentState: cancelled during stabilisation, re-locking")
            periphs.lockDepositor()
            pcall(periphs.setCoinAmount, 0)
            return
        end

        -- Record baseline relay inputs
        local baseline = periphs.getAllRelayInputs()
        dlog("_handlePaymentState: baseline recorded: " .. textutils.serialize(baseline))

        st.updateState({
            paymentBaseline = baseline,
            paymentDeadline = os.clock() + PAYMENT_TIMEOUT,
            paymentPaid = false,
        })

        paymentSetupDone = true
        dlog("_handlePaymentState: payment setup complete, waiting for coins")

    else
        -- SUBSEQUENT TICKS — check payment status
        local paid = st.getState("paymentPaid")
        local deadline = st.getState("paymentDeadline")

        if paid then
            dlog("_handlePaymentState: payment received!")
            periphs.lockDepositor()
            paymentSetupDone = false

            -- Snapshot the current barrel contents as the progress baseline.
            -- This is the moment the IO port will start pulling from, so
            -- measure fresh rather than using the potentially-stale
            -- totalBarrelItems from the first-enter setup.
            local items = periphs.getBarrelItems()
            local currentItems = items.totalItems

            st.updateState({
                screen = "packing",
                screenEntryTime = os.clock(),
                initialItemCount = currentItems,
                transferred = 0,
            })

        elseif deadline and os.clock() >= deadline then
            dlog("_handlePaymentState: payment timeout")
            periphs.lockDepositor()
            paymentSetupDone = false
            st.updateState({
                screen = "error",
                paymentPaid = false,
                errorMsg = MSG.error_timeout or "Timeout!",
            })
        end
    end
end

-- ============================================================================
-- Packing state handler
-- ============================================================================

function M._handlePackingState()
    local state = st.getState()

    -- PHASE 1: Push the cell to chute (one-shot, first entry only)
    if not state.cellPushed then
        local selectedCell = state.selectedCell
        if not selectedCell then
            dlog("_handlePackingState: no selectedCell in state")
            st.updateState({
                screen = "error",
                errorMsg = MSG.error_transaction or "Transaction failed!",
            })
            return
        end

        dlog("_handlePackingState: pushing " .. tostring(selectedCell.id) .. " to chute")
        local ok = periphs.pushCellToChute(selectedCell.id)
        if not ok then
            dlog("_handlePackingState: pushCellToChute failed")
            periphs.lockDepositor()
            st.updateState({
                screen = "error",
                errorMsg = MSG.error_port or "IO port error!",
            })
            return
        end
        dlog("_handlePackingState: cell pushed successfully")
        st.updateState({ cellPushed = true })

        -- Take an initial progress reading so the bar can start filling
        -- even before the next vendor loop tick.
        local items = periphs.getBarrelItems()
        local initial = state.initialItemCount or items.totalItems
        if initial > 0 then
            local removed = initial - items.totalItems
            if removed < 0 then removed = 0 end
            st.updateState({ transferred = removed })
            ui.updateProgress(st.getState())
        end
        return -- next vendor loop tick will re-enter at PHASE 2
    end

    -- PHASE 2: Update progress from barrel emptying, then check IO port
    local items = periphs.getBarrelItems()
    local initial = state.initialItemCount
    if initial and initial > 0 then
        local removed = initial - items.totalItems
        if removed < 0 then removed = 0 end
        st.updateState({ transferred = removed })

        -- Live UI update before checking IO port
        local s = st.getState()
        ui.updateProgress(s)
    end

    -- Now check IO port for completion
    local ioItems = periphs.getIoPortItems()

    if #ioItems > 0 then
        -- IO port has items! Packing is complete.
        dlog("_handlePackingState: IO port has finished packing")

        -- Set progress to 100% and render so player sees it
        st.updateState({ transferred = state.initialItemCount or 1 })
        ui.updateProgress(st.getState())
        os.sleep(0.5) -- brief moment to show 100% green bar

        -- Extract cell name from the items table
        local cellName = nil
        for _, item in ipairs(ioItems) do
            if item and item.name then
                cellName = item.name
                break
            end
        end
        if not cellName then
            cellName = state.selectedCell and state.selectedCell.id
        end

        if cellName then
            -- Pull the finished cell from IO port to input barrel
            dlog("_handlePackingState: pulling " .. tostring(cellName) .. " from IO port")
            local ok = periphs.pullCellFromIoPort(cellName)
            if not ok then
                dlog("_handlePackingState: pullCellFromIoPort failed, retrying once")
                os.sleep(1)
                ok = periphs.pullCellFromIoPort(cellName)
                if not ok then
                    dlog("_handlePackingState: pullCellFromIoPort failed after retry")
                    st.updateState({
                        screen = "error",
                        errorMsg = MSG.error_port or "IO port error!",
                    })
                    return
                end
            end
            dlog("_handlePackingState: cell retrieved successfully")
        end

        -- Show thankyou screen
        st.updateState({ screen = "thankyou" })
        return
    end

    -- IO port is still empty — packing is in progress, wait for next tick.
    -- No sleep needed here; vendorLoop's own TRANSFER_TICK_INTERVAL handles pacing.
end

-- ============================================================================
-- Cancel an in-progress payment
-- ============================================================================

function M.cancelPayment()
    dlog("cancelPayment: cancelling current transaction")
    st.updateState({ screen = "idle", screenEntryTime = os.clock() })
    pcall(periphs.lockDepositor)
    paymentSetupDone = false
    st.resetTransaction()
end

return M
