require "update"
require "parse"

local output = {
    updateInterval = 0.05,
    zoomLevel = 8,
    timeSinceLastUpdate = 0,
    image = nil,
    imageData = nil,
}

local rewriteState = {}
local initialImageData = nil
local initialImageHash = 0

local rewriteRules = {}
local rulesImageData = nil
local rulesImageHash = 0

local app = {
    idle = true,
    paused = false,
    editing = false,
    error = false,
    viewingCode = false,
    focused = true,
    printing = false,
    loopCount = 0, -- gets reset when rules or state are changed manually
    activeHeatmapRule = 0, 
}

-- the app parses two images, source.png and rules.png.
-- the output image is created from the source image and is updated by applying rules from the rules image.

-- patterns are represented as 2d tables of 1 and 0 (-1 for wildcard)
-- the state table is updated by applying rewrite rules from the rules table
-- each rule contains a before pattern and one or more after patterns

function love.load() 
    local found = loadState("source.png")
    if found == false then return end
    loadRules("rules.png")
end

function loadState(filename)
    if love.filesystem.getInfo(filename) == nil then
        print(filename .. " not found")
        app.error = true
        return false -- failed to load
    end

    -- load and first check if the image has changed
    local newImageData = love.image.newImageData(filename)
    local newHash = imageHash(newImageData)
    if newHash == initialImageHash then
        print("no change in " .. filename)
        return nil -- no change
    end
    initialImageHash = newHash

    -- continue loading image data
    print("found new " .. filename)
    initialImageData = newImageData

    -- display the state as the output image
    setupWindow(initialImageData:getWidth(), initialImageData:getHeight(), output.zoomLevel)
    setupOutput(output, initialImageData)
    return true
end

function loadRules(filename)
    if love.filesystem.getInfo(filename) == nil then
        print(filename .. " not found")
        app.error = true
        return false -- failed to load
    end

    -- load and first check if the image has changed
    local newImageData = love.image.newImageData(filename)
    local newHash = imageHash(newImageData)
    if newHash == rulesImageHash then
        print("no change in " .. filename)
        return nil -- no change
    end
    rulesImageHash = newHash

    -- continue loading image data
    print("found new " .. filename)
    rulesImageData = newImageData

    -- parse rules
    rewriteRules = parseRules(rulesImageData)
    if app.loopCount > 0 then
        app.loopCount = 0
        print("restarted loop and heatmap.")
    end
    return true
end

function setupOutput(output, outputImageData)
    -- output image and window. window size is based on the image size and zoom level
    -- only reloads the window size if it has changed
    output.imageData = outputImageData:clone()
    output.image = love.graphics.newImage(output.imageData)
    
    if app.viewingCode == false then
        -- parse initial state
        rewriteState = parseState(output.imageData)
        if app.loopCount > 0 then
            app.loopCount = 0
            print("restarted loop and heatmap.")
        end
        -- set image to represent the initial state
        updateImagedata(output.imageData, rewriteState, app)
        app.idle = false
        for key, value in ipairs(app) do
            print(key, value)
        end
    end

    output.image:replacePixels(output.imageData)
end

function setupWindow(newWidth, newHeight, zoomLevel)
    love.graphics.setDefaultFilter('nearest', 'nearest')
    love.graphics.setBackgroundColor(0.5, 0.5, 0.5)

    local width, height, flags = love.window.getMode()
    local sizeChanged = (width ~= newWidth * zoomLevel or height ~= newHeight * zoomLevel)
    
    if sizeChanged then
        love.window.setMode(newWidth * zoomLevel, newHeight * zoomLevel, {resizable=false, borderless=true})
    end
end

local hitsUntilIdle, missesUntilIdle = 0, 0

function love.update(dt)
    if not app.focused and love.window.hasFocus() then
        -- resume when window regains focus
        app.focused = true
        print("regained focus.")   
        -- reload state and rules
        local stateChanged = loadState("source.png")
        local rulesChanged = loadRules("rules.png")
        if stateChanged then
            print("loaded new state.")
        end
        if rulesChanged then
            print("loaded new rules.")
        end
    end
    if love.window.hasFocus() == false and app.focused then
        -- pause when window loses focus
        app.focused = false
        print("lost focus.")         
        return
    end
    if app.error or app.viewingCode or app.idle or app.paused then
        -- do nothing
        return
    end

    -- if viewing state, update the state and image in some interval

    output.timeSinceLastUpdate = output.timeSinceLastUpdate + dt
    if output.timeSinceLastUpdate > output.updateInterval then
        output.timeSinceLastUpdate = output.timeSinceLastUpdate - output.updateInterval

        -- new state, apply rules once
        local madeChanges, hits, misses = updateState(rewriteState, rewriteRules, app)
        app.loopCount = app.loopCount + 1
        hitsUntilIdle = hitsUntilIdle + hits
        missesUntilIdle = missesUntilIdle + misses
        -- print("turn " .. app.loopCount .. ".")
        if not madeChanges then
            app.idle = true
            print("   idle.")
            print("   total " .. hitsUntilIdle .. "/" .. missesUntilIdle + hitsUntilIdle .. " matches during " .. app.loopCount .. " turns.")
            print("   hit rate is " ..  string.format("%.3f", (hitsUntilIdle / (missesUntilIdle + hitsUntilIdle)) * 100)  .. "%.")
            hitsUntilIdle, missesUntilIdle = 0, 0
            print()
            -- no return here, so the image is still updated once more
        end
        -- update image
        updateImagedata(output.imageData, rewriteState, app)
        output.image:replacePixels(output.imageData)
    end
end

function love.draw()
    if app.error then
        return
    end
    -- draw output image using the scale. matches window size.
    love.graphics.scale(output.zoomLevel, output.zoomLevel)
    love.graphics.draw(output.image, 0, 0)
    love.graphics.reset()
    
    local fps = love.timer.getFPS()
    if fps < 30 then
        love.graphics.setColor(1, 0, 0)
        love.graphics.print("FPS: "..tostring(love.timer.getFPS( )), 0, 0)
    end
    love.graphics.setColor(1, 1, 1)
end

function love.keypressed(key, scancode, isrepeat) 
    if key == "escape" then
        love.event.quit()
    elseif key == "space" and not app.viewingCode then
        -- pause
        app.paused = not app.paused
        print(app.paused and "paused." or "unpaused.")
       
        -- output one more time, to show if paused or not
        updateImagedata(output.imageData, rewriteState, app)
        output.image:replacePixels(output.imageData)

    elseif key == "r" and not app.viewingCode then
        -- reset
        print("resetting state.")
        updatePallette()
        setupWindow(initialImageData:getWidth(), initialImageData:getHeight(), output.zoomLevel)
        setupOutput(output, initialImageData) 
    
    elseif key == "l" then
        -- reload state and rules
        local stateChanged = loadState("source.png")
        local rulesChanged = loadRules("rules.png")
        if stateChanged then
            print("loaded new state.")
        end
        if rulesChanged then
            print("loaded new rules.")
        end
    
    elseif key == "s" then
        -- save image
        if app.viewingCode then
            print("cannot save image while viewing code.")
            return
        end
        print("saving image")

        app.printing = true
        updateImagedata(output.imageData, rewriteState, app)

        local fileData = output.imageData:encode("png", "output.png")
        love.filesystem.write("output.png", fileData)
        print("image saved as output.png in path: " .. love.filesystem.getSaveDirectory())

        app.printing = false
        updateImagedata(output.imageData, rewriteState, app)
    
    elseif key == "tab" then
        -- switch between rule and state display
        if app.viewingCode then
            app.viewingCode = false
            print("viewing state.")
            setupWindow(initialImageData:getWidth(), initialImageData:getHeight(), output.zoomLevel)
            setupOutput(output, initialImageData)
        else
            app.viewingCode = true
            print("viewing code.")
            setupWindow(rulesImageData:getWidth(), rulesImageData:getHeight(), output.zoomLevel)
            setupOutput(output, rulesImageData)
        end
    elseif key == "up" or key == "down" or key == "left" or key == "right" then

        -- rotate all patterns in the rules in a local copy
        -- amount to rotate depends on the key pressed
        local rotateCountPerDirection = {up = 3, down = 1, left = 2, right = 0}
        local rotateCount = rotateCountPerDirection[key]
        local rotatedRules = getRotatedRules(rotateCount, rewriteRules)
        print("input " .. key)
        
        -- update and output. on the first turn, pass 
        app.idle = false
        app.playerInput = true
        if app.loopCount > 0 then
            app.loopCount = 0
            --print("restarted loop and heatmap.")
        end
        timeSinceLastUpdate = 0
        updateState(rewriteState, rotatedRules, app)
        updateImagedata(output.imageData, rewriteState, app)
        output.image:replacePixels(output.imageData)
        app.playerInput = false

    elseif key == "1" or key == "2" then
        -- increment or decrement the active heatmap rule index
        app.activeHeatmapRule = app.activeHeatmapRule + (key == "1" and -1 or 1)
        if app.activeHeatmapRule <= 0 then
            app.activeHeatmapRule = 0
            print("viewing state without heatmap.")
        else
            print("viewing heatmap for rule: " .. app.activeHeatmapRule)
        end
        updateImagedata(output.imageData, rewriteState, app)
        output.image:replacePixels(output.imageData)
    else
        --print("key pressed: " .. key)
    end
end

local startX, startY = 0, 0
local brushColor = 0

function love.mousepressed(x, y, button, istouch, presses)
    brushColor = button == 1 and 0 or 1
    if button == 1 or button == 2 then
        app.editing = true
        local x, y = mouseToCoordinate(x, y)
        startX, startY = x, y

        if app.viewingCode then
            return
        end
        local previewState = deeperCopy(rewriteState)
        updateStateFromMouseInput(previewState, startX, x, startY, y, brushColor)
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    if love.mouse.isDown(1) or love.mouse.isDown(2) then
        local x, y = mouseToCoordinate(x, y)

        if app.viewingCode then
            return
        end
        local previewState = deeperCopy(rewriteState)
        updateStateFromMouseInput(previewState, startX, x, startY, y, brushColor)
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
        updateStateFromMouseInput(rewriteState, startX, x, startY, y, brushColor)
    end
    startX, startY = 0, 0
end

function updateStateFromMouseInput(state, startX, endX, startY, endY, brushColor)
    if startX == x and startY == y then 
        state[y][x] = brushColor
    else 
        for i = math.min(startY, endY), math.max(startY, endY) do
            for j = math.min(startX, endX), math.max(startX, endX) do
                if i > 0 and j > 0 then state[i][j] = brushColor end
            end
        end
    end
    if app.loopCount > 0 then
        app.loopCount = 0
        print("   restarted loop and heatmap.")
    end
    updateImagedata(output.imageData, state, app)
    output.image:replacePixels(output.imageData)
end


-- helper functions

function mouseToCoordinate(x, y)
    x, y = math.floor(x / output.zoomLevel) + 1, math.floor(y / output.zoomLevel) + 1
    -- clamp to image size
    x = math.max(1, math.min(x, output.imageData:getWidth()))
    y = math.max(1, math.min(y, output.imageData:getHeight()))
    return x, y
end

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

-- Function to check if two 2D arrays are equal
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
