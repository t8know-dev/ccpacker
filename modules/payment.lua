-- modules/payment.lua — Payment detection for ccpacker
-- Exports: init(), checkPaymentDetection(st, periphs), paymentMonitorLoop(st, periphs, ui)
--
-- Detects payment by monitoring the redstone relay input on PAYMENT_DETECTION_SIDE.
-- The depositor emits a redstone signal on ALL sides when payment is accepted.
-- The relay detects this signal on its PAYMENT_DETECTION_SIDE input.
--
-- Mechanism: before unlocking the depositor, record the current relay input
-- value on PAYMENT_DETECTION_SIDE as the "baseline". After unlocking, poll
-- the relay input. When the value differs from baseline, payment has been made.
--
-- Depositor emits on all sides, so any configured side works for detection.
-- Run as a top-level parallel coroutine (not inside PixelUI threads).

local M = {}

-- Payments may be detected by comparing against a baseline or by looking for
-- a rising edge. This module supports both: baseline comparison is primary,
-- rising-edge detection is a fallback.
local _lastRelayState = nil  -- tracks last known value for edge detection

function M.init()
    _lastRelayState = nil
end

-- Check whether payment has been detected.
-- Called from vendorLoop and paymentMonitorLoop.
-- Returns true if payment detected, false otherwise.
function M.checkPaymentDetection(st, periphs)
    local screen = st.getState("screen")
    local paymentPaid = st.getState("paymentPaid")

    -- Only check when in payment screen and not already paid
    if screen ~= "payment" or paymentPaid then
        return false
    end

    local paymentDeadline = st.getState("paymentDeadline")
    if not paymentDeadline then
        return false
    end

    -- Check timeout
    if os.clock() >= paymentDeadline then
        dlog("payment: timeout reached")
        return "timeout"
    end

    -- Get baseline (recorded just after unlock)
    local baseline = st.getState("paymentBaseline")

    -- Read current relay inputs
    local current = periphs.getAllRelayInputs()
    local detectionSide = PAYMENT_DETECTION_SIDE

    -- Method 1: Baseline comparison (primary)
    if baseline and baseline[detectionSide] ~= nil and current[detectionSide] ~= nil then
        if current[detectionSide] ~= baseline[detectionSide] then
            dlog("payment: DETECTED on " .. tostring(detectionSide)
                .. " (baseline=" .. tostring(baseline[detectionSide])
                .. " current=" .. tostring(current[detectionSide]) .. ")")
            return true
        end
    end

    -- Method 2: All-sides fallback — the depositor emits on ALL sides,
    -- so check every side for changes.
    if baseline then
        for side, baselineVal in pairs(baseline) do
            if current[side] ~= nil and current[side] ~= baselineVal then
                dlog("payment: DETECTED on side " .. tostring(side)
                    .. " (baseline=" .. tostring(baselineVal)
                    .. " current=" .. tostring(current[side]) .. ")")
                return true
            end
        end
    end

    -- Method 3: Rising edge detection (fallback when baseline unavailable)
    if not baseline then
        local currentVal = current[detectionSide]
        if currentVal ~= nil then
            if _lastRelayState ~= nil and currentVal ~= _lastRelayState then
                dlog("payment: DETECTED via edge on " .. tostring(detectionSide)
                    .. " (" .. tostring(_lastRelayState) .. " -> " .. tostring(currentVal) .. ")")
                _lastRelayState = currentVal
                return true
            end
            _lastRelayState = currentVal
        end
    end

    return false
end

-- Payment monitor loop — runs as a top-level parallel coroutine.
-- ONLY sets paymentPaid = true when payment is detected.
-- State transitions (timeout, error, dispense) are handled by vendorLoop.
-- This avoids race conditions between two coroutines modifying screen state.
function M.paymentMonitorLoop(st, periphs)
    dlog("paymentMonitorLoop: started")
    while true do
        local ok, err = pcall(function()
            local paid = st.getState("paymentPaid")
            if not paid then
                local result = M.checkPaymentDetection(st, periphs)
                if result == true then
                    dlog("paymentMonitorLoop: payment detected")
                    st.updateState({ paymentPaid = true })
                end
                -- timeout is handled by vendorLoop, not here
            end
            os.sleep(0.02)  -- 20ms — fast enough to catch short pulses
        end)
        if not ok then
            dlog("paymentMonitorLoop error: " .. tostring(err))
            os.sleep(1)
        end
    end
end

return M
