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
    print("loaded " .. filename)
    print()
    print("    pixelScale: " .. settings.pixelScale)
    print("    windowX: " .. settings.windowX)
    print("    windowY: " .. settings.windowY)
    print("    logRules: " .. tostring(settings.logRules))
    print()
end

-- load latest image file, compare hash, and update if changed.
function loadLatestFile(filename, data, destinationKey, notFoundMessage) 
    if love.filesystem.getInfo(filename) == nil then
        print(filename .. " not found")
        love.window.showMessageBox(filename .. " not found", notFoundMessage, "error")
        app.error = true
        return false
    end

    -- load and first check if the image has changed
    local newImageData = love.image.newImageData(filename)
    local newHash = imageHash(newImageData)
    if newHash == data[destinationKey].imageHash then
        print("no change in " .. filename)
        return false
    end
    data[destinationKey].imageHash = newHash
    data[destinationKey].imagedata = newImageData
    data[destinationKey].width = newImageData:getWidth()
    data[destinationKey].height = newImageData:getHeight()
    print("found new " .. filename)
    return true
end

function loadImages(data)
    -- symbols
    local changed = loadLatestFile('symbols.png', data, "symbols", 
        "The PNG is required to generate the builtin symbols.")
    if changed then 
        data.symbols.table = parseSymbolsImage(data.symbols.imagedata)
        restartLoop()
    end

    -- state
    changed = loadLatestFile('source.png', data, "board", 
        "The PNG is required to generate the initial state.")
    if changed then 
        -- display the state as the output image
        setupWindow(data.board.width, data.board.height, app.settings)
        setupOutput(data) -- also restarts the loop
        print()
        print("   loaded new state.")
        print()
    end

    -- rules
    changed = loadLatestFile('rules.png', data, "rules", 
        "The PNG is required to generate the rewrite rules.")
    if changed then 
        -- parse rules
        -- symbols table contains keys
        local symbolCount = 0
        for key, value in pairs(data.symbols.table) do
            symbolCount = symbolCount + 1
        end
        if symbolCount == 0 then
            print("no symbols loaded yet, can't parse rules.")
            app.error = true
            return
        end

        data.rules.table = parseRulesImage(data.rules, data.symbols.table)
        restartLoop()
    end
end


-- set up the output image and window. 
function setupOutput(data)
    
    if not app.viewingCode then
        -- show board, make initial edits. (gray turns into 1 or 0)
        data.output.imagedata = data.board.imagedata:clone()
        data.board.table = parseBoardImage(data.output.imagedata)
        updateImagedata(data.output.imagedata, data.board.table)

        -- start looping
        app.idle = false
        restartLoop()
    else
        -- show rules image
        data.output.imagedata = data.rules.imagedata:clone()
    end

    data.output.image = love.graphics.newImage(data.output.imagedata)
    data.output.image:replacePixels(data.output.imagedata)
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
        local rulecount = #data.rules.table
        title = title .. " - " .. rulecount .. " rule" .. (rulecount == 1 and "" or "s")
    elseif app.printing then
        title = title .. " - saving image..."
    elseif app.paused then
        title = title .. " - paused (space to resume)"
    elseif app.editing then
        --title = title .. " - editing"
    elseif app.viewingHeatmapForRule > 0 then
        title = title .. " - showing pixels changed by rule " .. app.viewingHeatmapForRule .. " (of " .. #data.rules.table .. ")"
    elseif app.viewingHeatmapForRule == -1 then
        title = title .. " - global heatmap of current cycle"
    elseif app.hitsSinceInput > 0 then
        local appliedCount = app.hitsSinceInput
        title = title .. " - " .. appliedCount .. " changes..."
    end

    love.window.setTitle(title)
end