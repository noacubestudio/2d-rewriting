require "update"
require "parse"

local output = {
    updateInterval = 0.04,
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

local gameState = "running"
local windowHasFocus = true

-- the program parses two images, source.png and rules.png.
-- the output image is created from the source image and is updated by applying rules from the rules image.

-- patterns are represented as 2d tables of 1 and 0 (-1 for wildcard)
-- the state table is updated by applying rewrite rules from the rules table
-- each rule contains a before pattern and one or more after patterns

function love.load() 
    local found = loadState("source.png")
    if found == false then return end
    loadRules("rules.png")
    print("running.")
end

function loadState(filename)
    if love.filesystem.getInfo(filename) == nil then
        print(filename .. " not found")
        gameState = "error"
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
    print("loading or reloading state from " .. filename)
    initialImageData = newImageData
    output.imageData = initialImageData:clone() -- this one will be modified

    -- output image and window. window size is based on the image size and zoom level
    -- only reloads the window size if it has changed
    setupWindow(output)
    output.image = love.graphics.newImage(output.imageData)

    -- parse initial state
    rewriteState = parseState(output.imageData)

    -- set image to represent the initial state
    updateImagedata(output.imageData, rewriteState)
    output.image:replacePixels(output.imageData)
    return true
end

function loadRules(filename)
    if love.filesystem.getInfo(filename) == nil then
        print(filename .. " not found")
        gameState = "error"
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
    print("loading or reloading rules from " .. filename)
    rulesImageData = newImageData

    -- parse rules
    rewriteRules = parseRules(rulesImageData)
    return true
end

function setupWindow(output)
    --print("window size: " .. output.imageData:getWidth(), output.imageData:getHeight(), output.zoomLevel)
    love.graphics.setDefaultFilter('nearest', 'nearest')
    love.graphics.setBackgroundColor(0.5, 0.5, 0.5)
    width, height, flags = love.window.getMode()
    if width ~= output.imageData:getWidth() * output.zoomLevel or height ~= output.imageData:getHeight() * output.zoomLevel then
        love.window.setMode(
            output.imageData:getWidth() * output.zoomLevel, 
            output.imageData:getHeight() * output.zoomLevel, 
        {resizable=false})
    end
end

function love.update(dt)
    if love.window.hasFocus() == false then
        windowHasFocus = false
        if gameState == "running" then
            gameState = "paused"
            print("paused.")
        end
        return
    end
    if gameState ~= "running" then
        if love.window.hasFocus() == true and not windowHasFocus then
            windowHasFocus = true
            gameState = "running"
            print("resuming.")
            -- try reloading state and rules if the files have changed
            loadState("source.png")
            loadRules("rules.png")
        else
            return
        end
    end

    output.timeSinceLastUpdate = output.timeSinceLastUpdate + dt
    if output.timeSinceLastUpdate > output.updateInterval then
        output.timeSinceLastUpdate = output.timeSinceLastUpdate - output.updateInterval

        -- new state, apply rules once
        local madeChanges = updateState(rewriteState, rewriteRules)
        if not madeChanges then
            gameState = "paused"
            print("paused.")
            return
        end
        -- update image
        updateImagedata(output.imageData, rewriteState)
        output.image:replacePixels(output.imageData)
    end
end

function love.draw()
    if gameState == "error" then
        return
    end
    -- draw output image using the scale. matches window size.
    love.graphics.scale(output.zoomLevel, output.zoomLevel)
    love.graphics.draw(output.image, 0, 0)
    love.graphics.reset()
    love.graphics.setColor(1, 0, 0)
    love.graphics.print("FPS: "..tostring(love.timer.getFPS( )), 0, 0)
    love.graphics.setColor(1, 1, 1)
end

function love.keypressed(key, scancode, isrepeat)
    print("key pressed: " .. key)
    -- pause
    if key == "space" then
        if gameState == "running" then
            gameState = "paused"
            print("paused.")
        else
            gameState = "running"
            print("running.")
        end
    end
    -- reset
    if key == "r" then
        print("resetting to initial state")
        output.imageData = initialImageData:clone()
        rewriteState = parseState(output.imageData)
        -- first update
        gameState = "running"
        print("running.")
        updatePallette()
        updateImagedata(output.imageData, rewriteState)
        output.image:replacePixels(output.imageData)
    end
    -- reload state and rules
    if key == "l" then
        gameState = "running"
        print("running.")
        local found = loadState("source.png")
        if found == false then return end
        loadRules("rules.png")
    end
    -- save image
    if key == "s" then
        print("saving image")
        updateImagedata(output.imageData, rewriteState, "print")

        local fileData = output.imageData:encode("png", "output.png")
        love.filesystem.write("output.png", fileData)
        print("image saved as output.png in path: " .. love.filesystem.getSaveDirectory())

        updateImagedata(output.imageData, rewriteState)
    end
end

local startX, startY = 0, 0
local brushColor = 0

function love.mousepressed(x, y, button, istouch, presses)
    brushColor = button == 1 and 0 or 1
    if button == 1 or button == 2 then
        gameState = "paused"
        local x, y = mouseToCoordinate(x, y)
        startX, startY = x, y
        local previewState = deeperCopy(rewriteState)
        previewState[y][x] = brushColor
        updateImagedata(output.imageData, previewState, 'preview')
        output.image:replacePixels(output.imageData)
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    if love.mouse.isDown(1) or love.mouse.isDown(2) then
        local x, y = mouseToCoordinate(x, y)
        local previewState = deeperCopy(rewriteState)
        for i = math.min(startY, y), math.max(startY, y) do
            for j = math.min(startX, x), math.max(startX, x) do
                if i > 0 and j > 0 then previewState[i][j] = brushColor end
            end
        end
        updateImagedata(output.imageData, previewState, 'preview')
        output.image:replacePixels(output.imageData)
    end
end

function love.mousereleased(x, y, button, istouch, presses)
    if button == 1 or button == 2 then
        local x, y = mouseToCoordinate(x, y)
        --print(math.min(startY, y), math.max(startY, y), math.min(startX, x), math.max(startX, x))
        for i = math.min(startY, y), math.max(startY, y) do
            for j = math.min(startX, x), math.max(startX, x) do
                if i > 0 and j > 0 then rewriteState[i][j] = brushColor end
            end
        end
        gameState = "running"
        print("running.")
        updateImagedata(output.imageData, rewriteState)
        output.image:replacePixels(output.imageData)
    end
    startX, startY = 0, 0
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
