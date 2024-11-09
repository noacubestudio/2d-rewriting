require "setup"
require "parse"
require "update"

require "TSerial"

app = {
    -- state
    idle = true,
    paused = false,
    editing = false,
    error = false,
    viewingCode = false,
    viewingHeatmapForRule = 0, 
    focused = true,
    printing = false,

    -- reset on input
    loopsSinceInput = 0,
    hitsSinceInput = 0,
    missesSinceInput = 0,

    -- update loop
    timeSinceLastUpdate = 0,
    updateInterval = 0.05,

    -- settings
    settings = {
        pixelScale = 4,
        windowX = nil,
        windowY = nil,
    },
}

local mouseInput = {
    startX = 0,
    startY = 0,
    brushColor = 0,
}

local data = {
    outputImage = nil,
    outputImagedata = nil,
    sourceImagedata = nil,
    rulesImagedata = nil,

    sourceImageHash = 0,
    rulesImageHash = 0,

    rules = {},
    grid = {},
}

function love.load() 
    loadSettings(app.settings, "settings.lua")
    loadState(data, "source.png")
    loadRules(data, "rules.png")
end

function love.update(dt)

    -- update every <updateInterval> seconds
    local updateNow = false
    app.timeSinceLastUpdate = app.timeSinceLastUpdate + dt
    if app.timeSinceLastUpdate > app.updateInterval then
        app.timeSinceLastUpdate = app.timeSinceLastUpdate - app.updateInterval
        updateNow = true
    end

    if updateNow then updateTitle(data) end

    if not app.focused and love.window.hasFocus() then
        -- resume when window regains focus
        app.focused = true
        print("regained focus.")   
        loadState(data, "source.png")
        loadRules(data, "rules.png")

    elseif app.focused and not love.window.hasFocus() then
        app.focused = false
        print("lost focus.")         
        return
    end

    if app.error or app.viewingCode or app.idle or app.paused then
        return
    end

    -- state is shown and unpaused and not idle (more potential changes to be made)
    if updateNow then

        -- new state, apply rules once
        local madeChanges, hits, misses = applyRulesToGrid(data.grid, data.rules)
        app.loopsSinceInput = app.loopsSinceInput + 1
        app.hitsSinceInput = app.hitsSinceInput + hits
        app.missesSinceInput = app.missesSinceInput + misses
        -- print("turn " .. app.loopsSinceInput .. ".")
        if not madeChanges then
            app.idle = true
            print("   idle after " .. app.loopsSinceInput .. " turns.")
            print("   total: " .. app.hitsSinceInput .. "/" .. app.missesSinceInput + app.hitsSinceInput .. " matches.")
            print("   hit rate is " ..  string.format("%.3f", (app.hitsSinceInput / (app.missesSinceInput + app.hitsSinceInput)) * 100)  .. "%.")
            app.hitsSinceInput, app.missesSinceInput = 0, 0
            print()
            -- no return here, so the image is still updated once more
        end
        -- update image
        updateImagedata(data.outputImagedata, data.grid)
        data.outputImage:replacePixels(data.outputImagedata)
    end
end

function love.draw()
    if app.error then
        return
    end
    -- draw output image using the scale. matches window size.
    love.graphics.scale(app.settings.pixelScale, app.settings.pixelScale)
    love.graphics.draw(data.outputImage, 0, 0)
    love.graphics.reset()

    --love.graphics.setColor(1, 0, 0)
    --love.graphics.print("FPS: "..tostring(love.timer.getFPS( )), 0, 0)
    
    love.graphics.setColor(1, 1, 1)
end

function love.quit()
    -- window position
    app.settings.windowX, app.settings.windowY = love.window.getPosition()

    -- save settings on quit
    local contents = TSerial.pack(app.settings, false, true)
    love.filesystem.write("settings.lua", contents)
end

-- input handling

function love.keypressed(key, scancode, isrepeat) 
    if key == "escape" then
        -- quit
        love.event.quit()

    elseif key == "space" and not app.viewingCode then
        -- pause
        app.paused = not app.paused
        print(app.paused and "paused." or "unpaused.")
       
        -- output one more time, to show if paused or not
        updateImagedata(data.outputImagedata, data.grid)
        data.outputImage:replacePixels(data.outputImagedata)

    elseif key == "r" and not app.viewingCode then
        -- reset
        print("resetting state.")
        updatePallette()
        newWidth, newHeight = data.sourceImagedata:getWidth(), data.sourceImagedata:getHeight()
        setupWindow(newWidth, newHeight, app.settings)
        setupOutput(data) 
    
    elseif key == "l" then
        -- reload state and rules
        loadState(data, "source.png")
        loadRules(data, "rules.png")
    
    elseif key == "s" then
        -- save image
        if app.viewingCode then
            print("cannot save image while viewing code.")
            return
        end
        print("saving image")

        app.printing = true
        updateImagedata(data.outputImagedata, data.grid)

        local fileData = data.outputImagedata:encode("png", "output.png")
        love.filesystem.write("output.png", fileData)
        print("image saved as output.png in path: " .. love.filesystem.getSaveDirectory())

        app.printing = false
        updateImagedata(data.outputImagedata, data.grid)
    
    elseif key == "tab" then
        -- switch between rule and state display
        local newWidth, newHeight
        if app.viewingCode then
            app.viewingCode = false
            print("viewing state.")
            newWidth, newHeight = data.sourceImagedata:getWidth(), data.sourceImagedata:getHeight()
        else
            app.viewingCode = true
            print("viewing code.")
            newWidth, newHeight = data.rulesImagedata:getWidth(), data.rulesImagedata:getHeight()
        end
        setupWindow(newWidth, newHeight, app.settings)
        setupOutput(data)

    elseif key == "up" or key == "down" or key == "left" or key == "right" then
        -- input keys for games, etc.
        -- rotate all patterns in the rules in a local copy
        -- amount to rotate depends on the key pressed
        local rotateCountPerDirection = {up = 3, down = 1, left = 2, right = 0}
        local rotateCount = rotateCountPerDirection[key]
        local rotatedRules = getRotatedRules(rotateCount, data.rules)
        print("input " .. key)
        
        -- update and output. on the first turn, pass 
        app.idle = false
        app.playerInput = true
        if app.loopsSinceInput > 0 then
            app.loopsSinceInput = 0
            --print("restarted loop and heatmap.")
        end
        timeSinceLastUpdate = 0
        applyRulesToGrid(data.grid, rotatedRules)
        updateImagedata(data.outputImagedata, data.grid)
        data.outputImage:replacePixels(data.outputImagedata)
        app.playerInput = false

    elseif key == "1" or key == "2" then
        -- show different heatmaps over the state that represent where each rule matched since last input
        app.viewingHeatmapForRule = app.viewingHeatmapForRule + (key == "1" and -1 or 1)

        -- cycle through rules
        if app.viewingHeatmapForRule < 0 then
            app.viewingHeatmapForRule = #data.rules
        elseif app.viewingHeatmapForRule > #data.rules then
            app.viewingHeatmapForRule = 0
        end

        -- 0 is the default state without heatmap
        if app.viewingHeatmapForRule == 0 then
            print("viewing state without heatmap.")
        else
            print("viewing heatmap for rule: " .. app.viewingHeatmapForRule)
        end
        updateImagedata(data.outputImagedata, data.grid)
        data.outputImage:replacePixels(data.outputImagedata)
    else
        --print("key pressed: " .. key)
    end
end

-- scroll
function love.wheelmoved(x, y)

    -- first get position of window
    app.settings.windowX, app.settings.windowY = love.window.getPosition()

    if y > 0 then
        -- scroll up
        app.settings.pixelScale = app.settings.pixelScale + 1
    elseif y < 0 then
        -- scroll down
        app.settings.pixelScale = math.max(1, app.settings.pixelScale - 1)
    end
    local baseWidth, baseHeight = data.outputImagedata:getWidth(), data.outputImagedata:getHeight()
    setupWindow(baseWidth, baseHeight, app.settings)
end

function love.mousepressed(x, y, button, istouch, presses)
    mouseInput.brushColor = button == 1 and 0 or 1
    if button == 1 or button == 2 then
        app.editing = true
        local x, y = mouseToCoordinate(x, y)
        mouseInput.startX, mouseInput.startY = x, y

        if app.viewingCode then
            return
        end
        local previewState = deeperCopy(data.grid)
        drawInGrid(previewState, x, y, mouseInput)
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    if love.mouse.isDown(1) or love.mouse.isDown(2) then
        local x, y = mouseToCoordinate(x, y)

        if app.viewingCode then
            return
        end
        local previewState = deeperCopy(data.grid)
        drawInGrid(previewState, x, y, mouseInput)
    end
end

function love.mousereleased(x, y, button, istouch, presses)
    if button == 1 or button == 2 then
        app.editing = false
        app.idle = false
        local x, y = mouseToCoordinate(x, y)

        if app.viewingCode then
            return
        end
        drawInGrid(data.grid, x, y, mouseInput)
    end
    mouseInput.startX, mouseInput.startY = 0, 0
end

function mouseToCoordinate(x, y)
    x, y = math.floor(x / app.settings.pixelScale) + 1, math.floor(y / app.settings.pixelScale) + 1
    -- clamp to image size
    x = math.max(1, math.min(x, data.outputImagedata:getWidth()))
    y = math.max(1, math.min(y, data.outputImagedata:getHeight()))
    return x, y
end

function drawInGrid(grid, endX, endY, mouseInput)
    local startX, startY = mouseInput.startX, mouseInput.startY
    if startX == x and startY == y then 
        grid[y][x] = mouseInput.brushColor
    else 
        for i = math.min(startY, endY), math.max(startY, endY) do
            for j = math.min(startX, endX), math.max(startX, endX) do
                if i > 0 and j > 0 then grid[i][j] = mouseInput.brushColor end
            end
        end
    end
    if app.loopsSinceInput > 0 then
        app.loopsSinceInput = 0
    end
    updateImagedata(data.outputImagedata, grid)
    data.outputImage:replacePixels(data.outputImagedata)
end


-- helper functions

function shallowCopy(orig)
    local copy = {}
    for i, v in ipairs(orig) do
        copy[i] = v
    end
    return copy
end

function deeperCopy(orig)
    local copy = {}
    for i, v in ipairs(orig) do
        copy[i] = shallowCopy(v)
    end
    return copy
end

function shiftPattern(table, dx, dy)
    local width = #table[1]
    local height = #table
    local newTable = {}
    for y = 1, height do
        newTable[y] = {}
        for x = 1, width do
            newTable[y][x] = table[(y + dy - 1) % height + 1][(x + dx - 1) % width + 1]
        end
    end
    return newTable
end

function flipPattern(table, flipHorizontal)
    local width = #table[1]
    local height = #table
    local newTable = {}
    for y = 1, height do
        newTable[y] = {}
        for x = 1, width do
            newTable[y][x] = table[y][flipHorizontal and width - x + 1 or x]
        end
    end
    return newTable
end

function rotatePattern(table)
    local width = #table[1]
    local height = #table
    local newTable = {}
    for x = 1, width do
        newTable[x] = {}
        for y = 1, height do
            newTable[x][y] = table[height - y + 1][x]
        end
    end
    if patternsEqual(table, newTable) then
        return nil
    end
    return newTable
end

function patternsEqual(matrix1, matrix2)
    local rows, cols = #matrix1, #matrix1[1]
    for i = 1, rows do
        for j = 1, cols do
            if matrix1[i][j] ~= matrix2[i][j] then
                return false
            end
        end
    end
    return true
end

function printPatternsSideBySide(tables)
    for y = 1, #tables[1] do
        io.write(" ")
        for i = 1, #tables do
            for x = 1, #tables[i][1] do
                local char = tables[i][y][x] == 1 and "+" or tables[i][y][x] == 0 and "0" or " "
                io.write(char)
            end
            io.write("  ")
        end
        print()
    end
end

function imageHash(imageData)
    local hash = 0
    local width, height = imageData:getDimensions()

    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local r, g, b, a = imageData:getPixel(x, y)
            hash = hash + (r * 31 + g * 37 + b * 41 + a * 43)
        end
    end
    return hash
end
