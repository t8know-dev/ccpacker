-- modules/ui.lua — PixelUI screens for ccpacker
-- Exports: init(pixelui), createUI(monitor, callbacks), updateScreen(state), updateProgress(state)
--
-- Screens: splash, idle, prompt, cell_choice, payment, packing, thankyou, error
-- Monitor: 1x1 advanced, scale 0.5 ≈ 26×8 chars. Keep text SHORT.

local M = {}
local pixelui

local app
local root

-- Widget references
local headerLabel
local splashLabel1, splashLabel2, splashLabel3
local idleLabel
local msgLine1, msgLine2, msgLine3, msgLine4
local packButton
local cellChoiceTitle
local portableBtn, normalBtn
local cancelButton
local progressBar, progressTextLabel
local thanksLine1, thanksLine2, thanksLine3, thanksLine4, thanksLine5

local w, h

-- ============================================================================
-- Helpers
-- ============================================================================

local function centerText(text, width)
    local pad = math.max(0, math.floor((width - #text) / 2))
    local rightPad = math.max(0, width - #text - pad)
    return string.rep(" ", pad) .. text .. string.rep(" ", rightPad)
end

local function hideAllDynamic()
    if splashLabel1 then splashLabel1.visible = false end
    if splashLabel2 then splashLabel2.visible = false end
    if splashLabel3 then splashLabel3.visible = false end
    if idleLabel then idleLabel.visible = false end
    if msgLine1 then msgLine1.visible = false end
    if msgLine2 then msgLine2.visible = false end
    if msgLine3 then msgLine3.visible = false end
    if msgLine4 then msgLine4.visible = false end
    if packButton then packButton.visible = false end
    if cellChoiceTitle then cellChoiceTitle.visible = false end
    if portableBtn then portableBtn.visible = false end
    if normalBtn then normalBtn.visible = false end
    if cancelButton then cancelButton.visible = false end
    if progressBar then progressBar.visible = false end
    if progressTextLabel then progressTextLabel.visible = false end
    if thanksLine1 then thanksLine1.visible = false end
    if thanksLine2 then thanksLine2.visible = false end
    if thanksLine3 then thanksLine3.visible = false end
    if thanksLine4 then thanksLine4.visible = false end
    if thanksLine5 then thanksLine5.visible = false end
end

-- ============================================================================
-- Init
-- ============================================================================

function M.init(pixeluiRef)
    pixelui = pixeluiRef
end

-- ============================================================================
-- UI creation — all widgets created once, shown/hidden by updateScreen
-- ============================================================================

function M.createUI(monitor, callbacks)
    if not pixelui then error("ui.init() not called before createUI") end

    monitor.setTextScale(0.5)
    w, h = monitor.getSize()

    local viewport = window.create(monitor, 1, 1, w, h, true)

    app = pixelui.create({
        window = viewport,
        background = colors.black,
        animationInterval = 0.05,
    })
    root = app:getRoot()

    -- Header: rows 1-2, red background (all screens except splash)
    headerLabel = app:createLabel({
        x = 1, y = 1,
        width = w, height = 2,
        text = centerText(MSG.header or "CCPACKER", w),
        align = "center",
        bg = colors.red,
        fg = colors.white,
        visible = false,
    })
    root:addChild(headerLabel)

    -- Splash screen (rows 3, 5, 6)
    if h >= 3 then
        splashLabel1 = app:createLabel({
            x = 1, y = 3,
            width = w, height = 1,
            text = centerText(MSG.splash_line1 or "CCPACKER", w),
            align = "center",
            bg = colors.black,
            fg = colors.white,
            visible = false,
        })
        root:addChild(splashLabel1)

        splashLabel2 = app:createLabel({
            x = 1, y = 5,
            width = w, height = 1,
            text = centerText(MSG.splash_line2 or "Item Packer", w),
            align = "center",
            bg = colors.black,
            fg = colors.lightGray,
            visible = false,
        })
        root:addChild(splashLabel2)

        splashLabel3 = app:createLabel({
            x = 1, y = 6,
            width = w, height = 1,
            text = centerText(APP_VERSION or "v1.0", w),
            align = "center",
            bg = colors.black,
            fg = colors.gray,
            visible = false,
        })
        root:addChild(splashLabel3)
    end

    -- Idle screen: blink label "< order pickup" (row 4)
    if h >= 4 then
        idleLabel = app:createLabel({
            x = 1, y = 4,
            width = w, height = 1,
            text = centerText(MSG.idle_line1 or "< order pickup", w),
            align = "center",
            bg = colors.black,
            fg = colors.white,
            visible = false,
        })
        root:addChild(idleLabel)
    end

    -- Message lines (reused across prompt, payment, error screens)
    if h >= 3 then
        msgLine1 = app:createLabel({
            x = 1, y = 3,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.white,
            visible = false,
        })
        root:addChild(msgLine1)

        msgLine2 = app:createLabel({
            x = 1, y = 4,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.white,
            visible = false,
        })
        root:addChild(msgLine2)

        msgLine3 = app:createLabel({
            x = 1, y = 5,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.white,
            visible = false,
        })
        root:addChild(msgLine3)

        msgLine4 = app:createLabel({
            x = 1, y = 6,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.white,
            visible = false,
        })
        root:addChild(msgLine4)
    end

    -- Thank you screen labels (rows 3-6)
    if h >= 3 then
        thanksLine1 = app:createLabel({
            x = 1, y = 3,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.green,
            visible = false,
        })
        root:addChild(thanksLine1)

        thanksLine2 = app:createLabel({
            x = 1, y = 4,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.green,
            visible = false,
        })
        root:addChild(thanksLine2)

        thanksLine3 = app:createLabel({
            x = 1, y = 5,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.green,
            visible = false,
        })
        root:addChild(thanksLine3)

        thanksLine4 = app:createLabel({
            x = 1, y = 6,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.green,
            visible = false,
        })
        root:addChild(thanksLine4)

        thanksLine5 = app:createLabel({
            x = 1, y = 7,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.green,
            visible = false,
        })
        root:addChild(thanksLine5)
    end

    -- Cell choice title (row 3)
    if h >= 3 then
        cellChoiceTitle = app:createLabel({
            x = 1, y = 3,
            width = w, height = 1,
            text = centerText(MSG.cell_choice_title or "Choose cell type", w),
            align = "center",
            bg = colors.black,
            fg = colors.white,
            visible = false,
        })
        root:addChild(cellChoiceTitle)
    end

    -- PORTABLE button (row 5)
    if h >= 5 then
        local btnWidth = 14
        local btnX = math.floor((w - btnWidth) / 2)
        portableBtn = app:createButton({
            x = btnX + 1, y = 5,
            width = btnWidth, height = 1,
            label = " [ " .. (MSG.portable_btn or "PORTABLE") .. " ]",
            bg = colors.gray,
            fg = colors.white,
            onClick = function() pcall(callbacks.onPortableClick) end,
            visible = false,
        })
        root:addChild(portableBtn)
    end

    -- NORMAL button (row 7)
    if h >= 7 then
        local btnWidth = 14
        local btnX = math.floor((w - btnWidth) / 2)
        normalBtn = app:createButton({
            x = btnX + 1, y = 7,
            width = btnWidth, height = 1,
            label = " [ " .. (MSG.normal_btn or "NORMAL") .. " ]",
            bg = colors.gray,
            fg = colors.white,
            onClick = function() pcall(callbacks.onNormalClick) end,
            visible = false,
        })
        root:addChild(normalBtn)
    end

    -- Progress bar (row 4)
    if h >= 4 then
        progressBar = app:createProgressBar({
            x = 2, y = 4,
            width = math.max(1, w - 4), height = 1,
            border = false,
            min = 0,
            max = 1,
            value = 0,
            label = "",
            showPercent = false,
            trackColor = colors.gray,
            fillColor = colors.lightGray,
            bg = colors.black,
            fg = colors.white,
            visible = false,
        })
        root:addChild(progressBar)
    end

    -- Progress text (row 6)
    if h >= 6 then
        progressTextLabel = app:createLabel({
            x = 1, y = 6,
            width = w, height = 1,
            text = "",
            align = "center",
            bg = colors.black,
            fg = colors.lightGray,
            visible = false,
        })
        root:addChild(progressTextLabel)
    end

    -- PACK button (3 lines high, green, rows 6-8)
    if h >= 8 then
        local btnWidth = 14
        local btnX = math.floor((w - btnWidth) / 2)
        packButton = app:createButton({
            x = btnX + 1, y = 6,
            width = btnWidth, height = 3,
            label = " " .. (MSG.pack_btn or "PACK"),
            bg = colors.green,
            fg = colors.white,
            onClick = function() pcall(callbacks.onPackClick) end,
            visible = false,
        })
        root:addChild(packButton)
    end

    -- CANCEL/ABORT button (row 8)
    if h >= 8 then
        local btnWidth = 13
        local btnX = math.floor((w - btnWidth) / 2)
        cancelButton = app:createButton({
            x = btnX + 1, y = 8,
            width = btnWidth, height = 1,
            label = MSG.cancel_btn or "ABORT",
            bg = colors.orange,
            fg = colors.white,
            onClick = function() pcall(callbacks.onCancelClick) end,
            visible = false,
        })
        root:addChild(cancelButton)
    end

    return app
end

-- ============================================================================
-- Screen renderer — switches between all screens
-- ============================================================================

function M.updateScreen(st)
    if not app then return end
    hideAllDynamic()

    if st.screen == "splash" then
        if headerLabel then headerLabel.visible = true end
        if splashLabel1 then splashLabel1.visible = true end
        if splashLabel2 then splashLabel2.visible = true end
        if splashLabel3 then splashLabel3.visible = true end

    elseif st.screen == "idle" then
        if headerLabel then headerLabel.visible = true end
        if idleLabel then
            if st.blinkVisible then
                idleLabel:setText(centerText(MSG.idle_line1 or "< order pickup", w))
                idleLabel.fg = colors.white
            else
                idleLabel:setText(centerText("  order pickup", w))
                idleLabel.fg = colors.gray
            end
            idleLabel.visible = true
        end

    elseif st.screen == "prompt" then
        if headerLabel then headerLabel.visible = true end
        if msgLine1 then
            msgLine1:setText(MSG.prompt_line1 or "Pack items to")
            msgLine1.fg = colors.white
            msgLine1.visible = true
        end
        if msgLine2 then
            msgLine2:setText(MSG.prompt_line2 or "an AE2 cell?")
            msgLine2.fg = colors.white
            msgLine2.visible = true
        end
        if packButton then packButton.visible = true end

    elseif st.screen == "cell_choice" then
        if headerLabel then headerLabel.visible = true end
        if cellChoiceTitle then cellChoiceTitle.visible = true end
        if portableBtn then portableBtn.visible = true end
        if normalBtn then normalBtn.visible = true end

    elseif st.screen == "payment" then
        if headerLabel then headerLabel.visible = true end
        if msgLine1 then
            msgLine1:setText(MSG.payment_line1 or "Please insert")
            msgLine1.fg = colors.yellow
            msgLine1.visible = true
        end
        if msgLine2 then
            msgLine2:setText(string.format(MSG.payment_line2 or "%d spur(s)", st.totalPrice))
            msgLine2.fg = colors.yellow
            msgLine2.visible = true
        end
        if msgLine3 then
            msgLine3:setText(MSG.payment_line3 or "into the")
            msgLine3.fg = colors.yellow
            msgLine3.visible = true
        end
        if msgLine4 then
            msgLine4:setText(MSG.payment_line4 or "depositor")
            msgLine4.fg = colors.yellow
            msgLine4.visible = true
        end
        if cancelButton then cancelButton.visible = true end

    elseif st.screen == "packing" then
        if headerLabel then headerLabel.visible = true end
        if msgLine1 then
            msgLine1:setText(MSG.packing_title or "Packing...")
            msgLine1.fg = colors.yellow
            msgLine1.visible = true
        end
        if progressBar then
            local total = math.max(st.initialItemCount or 1, 1)
            local done = math.min(st.transferred, total)
            progressBar:setRange(0, total)
            progressBar:setValue(done)
            -- Fill colour: green if complete
            if st.transferred >= st.initialItemCount and st.initialItemCount > 0 then
                progressBar.fillColor = colors.green
            else
                progressBar.fillColor = colors.lightGray
            end
            progressBar.visible = true
        end
        if progressTextLabel then
            local total = math.max(st.initialItemCount or 1, 1)
            local pct = math.floor((st.transferred / total) * 100)
            progressTextLabel:setText(string.format(MSG.progress_text or "%d/%d (%d%%)", st.transferred, total, pct))
            progressTextLabel.fg = (pct >= 100) and colors.green or colors.lightGray
            progressTextLabel.visible = true
        end

    elseif st.screen == "thankyou" then
        if headerLabel then headerLabel.visible = true end
        if thanksLine1 then
            thanksLine1:setText(MSG.thanks_line1 or "Thank you!")
            thanksLine1.visible = true
        end
        if thanksLine2 then
            thanksLine2:setText(MSG.thanks_line2 or "Packing complete.")
            thanksLine2.visible = true
        end
        if thanksLine3 then
            thanksLine3:setText(MSG.thanks_line3 or "Collect your cell")
            thanksLine3.visible = true
        end
        if thanksLine4 then
            thanksLine4:setText(MSG.thanks_line4 or "from the barrel.")
            thanksLine4.visible = true
        end

    elseif st.screen == "error" then
        if headerLabel then headerLabel.visible = true end
        if msgLine1 then
            msgLine1:setText(st.errorMsg or "Error!")
            msgLine1.fg = colors.red
            msgLine1.visible = true
        end
        if msgLine2 then
            msgLine2:setText(MSG.error_line1 or "Error!")
            msgLine2.fg = colors.red
            msgLine2.visible = true
        end
    end

    app:render()
end

-- ============================================================================
-- Live progress update (calls app:render but skips full screen switch)
-- ============================================================================

function M.updateProgress(st)
    if not app or st.screen ~= "packing" then return end
    if not progressBar or not progressTextLabel then return end

    local total = math.max(st.initialItemCount or 1, 1)
    local done = math.min(st.transferred, total)
    progressBar:setRange(0, total)
    progressBar:setValue(done)

    if st.transferred >= st.initialItemCount and st.initialItemCount > 0 then
        progressBar.fillColor = colors.green
    else
        progressBar.fillColor = colors.lightGray
    end

    local pct = math.floor((st.transferred / total) * 100)
    progressTextLabel:setText(string.format(MSG.progress_text or "%d/%d (%d%%)", st.transferred, total, pct))
    progressTextLabel.fg = (pct >= 100) and colors.green or colors.lightGray

    app:render()
end

return M
