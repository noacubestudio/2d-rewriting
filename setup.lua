-- load settings, otherwise use defaults.
function loadSettings(settings, filename)
    if love.filesystem.getInfo(filename) == nil then
        print(filename .. " not found, using default settings.")
        return
    end

    local contents, size = love.filesystem.read(filename)
    if contents == nil then return end

    local loadedSettings = TSerial.unpack(contents, true)
    if loadedSettings == nil then return end

    for key, value in pairs(loadedSettings) do
        settings[key] = value
    end
    print("loaded settings.")
end


-- see if there is a new state image, and if so, set its' data as the starting state.
function loadState(data, filename)
    if love.filesystem.getInfo(filename) == nil then
        print(filename .. " not found")
        love.window.showMessageBox(filename .. "not found", "The PNG is used to generate the initial state.", "error")
        app.error = true
        return
    end

    -- load and first check if the image has changed
    local newImageData = love.image.newImageData(filename)
    local newHash = imageHash(newImageData)
    if newHash == data.sourceImageHash then
        print("no change in " .. filename)
        return
    end
    data.sourceImageHash = newHash

    -- continue loading image data
    print("found new " .. filename)
    data.sourceImagedata = newImageData

    -- display the state as the output image
    newWidth, newHeight = data.sourceImagedata:getWidth(), data.sourceImagedata:getHeight()
    setupWindow(newWidth, newHeight, app.settings)
    setupOutput(data)
    print("loaded new state.")
end


-- see if there is a new rules image, parse it to overwrite the current rules.
function loadRules(data, filename)
    if love.filesystem.getInfo(filename) == nil then
        print(filename .. " not found")
        love.window.showMessageBox(filename .. "not found", "The PNG is parsed to generate the rewrite rules.", "error")
        app.error = true
        return
    end

    -- load and first check if the image has changed
    local newImageData = love.image.newImageData(filename)
    local newHash = imageHash(newImageData)
    if newHash == data.rulesImageHash then
        print("no change in " .. filename)
        print()
        return
    end
    data.rulesImageHash = newHash

    -- continue loading image data
    print("found new " .. filename)
    data.rulesImagedata = newImageData

    -- parse rules
    data.rules = parseRules(data.rulesImagedata)
    if app.loopsSinceInput > 0 then
        app.loopsSinceInput = 0
        print("restarted loop and heatmap.")
    end
end


-- set up the output image and window. 
function setupOutput(data)
    
    if not app.viewingCode then
        -- show source image, make initial edits. (gray turns into 1 or 0)
        data.outputImagedata = data.sourceImagedata:clone()
        data.grid = parseState(data.outputImagedata)
        updateImagedata(data.outputImagedata, data.grid)

        -- start looping
        app.idle = false
        if app.loopsSinceInput > 0 then
            app.loopsSinceInput = 0
            print("restarted loop and heatmap.")
        end
    else
        -- show rules image
        data.outputImagedata = data.rulesImagedata:clone()
    end

    data.outputImage = love.graphics.newImage(data.outputImagedata)
    data.outputImage:replacePixels(data.outputImagedata)
end


-- set the graphics, window dimensions (if changed) and zoom level.
function setupWindow(newWidth, newHeight, settings)
    love.graphics.setDefaultFilter('nearest', 'nearest')
    love.window.setTitle("untitled 2d rewrite project (" .. settings.pixelScale * 100 .. "%)")

    local width, height, flags = love.window.getMode()
    local x, y = settings.windowX, settings.windowY
    local scale = settings.pixelScale
    local sizeChanged = (width ~= newWidth * scale or height ~= newHeight * scale)
    
    love.window.setPosition(x, y)
    if sizeChanged then
        love.window.updateMode(newWidth * scale, newHeight * scale, {resizable=false, borderless=false, centered=false})
    end
    
    if x == nil or y == nil then
        x = (love.graphics.getWidth() - newWidth * scale) / 2
        y = (love.graphics.getHeight() - newHeight * scale) / 2
    end
    --love.timer.sleep(0.1) -- wait for window to update
    love.window.setPosition(x, y)
end


-- set title to include some info about the current state.
function updateTitle(data)
    local title = "Untitled 2D Rewrite Project"

    -- zoom % and fps
    title = title .. " (" .. app.settings.pixelScale * 100 .. "%"
    title = title .. " - " .. love.timer.getFPS() .. " fps)"

    if app.viewingCode then
        local rulecount = #data.rules
        title = title .. " - " .. rulecount .. " rule" .. (rulecount == 1 and "" or "s")
    elseif app.printing then
        title = title .. " - saving image..."
    elseif app.paused then
        title = title .. " - paused (space to resume)"
    elseif app.editing then
        --title = title .. " - editing"
    elseif app.viewingHeatmapForRule > 0 then
        title = title .. " - showing pixels changed by rule " .. app.viewingHeatmapForRule .. " (of " .. #data.rules .. ")"
    elseif not app.idle then
        local appliedCount = app.hitsSinceInput
        title = title .. " - " .. appliedCount .. "..."
    end

    love.window.setTitle(title)
end