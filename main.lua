require "update"
require "parse"

-- graphics!
-- The program reads two images, source.png and rules.png.
-- THe output image is created from the source image and is updated by applying rules from the rules image.
local output = {
    updateInterval = 0.04,
    zoomLevel = 8,
    timeSinceLastUpdate = 0,
    image = nil,
    imageData = nil,
}

-- the state is represented as a 2d table of 1 and 0
-- the table is updated by applying rewrite rules to it
-- rules are read from the rules image.
-- each rule contains a before and after state as well as a mask for each state
local rewriteState = {}
local rewriteRules = {}
local initialImageData = nil
local gameState = "running"

function love.load() 
    -- create output image
    if love.filesystem.getInfo("source.png") == nil then
        print("source.png not found")
        gameState = "error"
        return
    end
    if love.filesystem.getInfo("rules.png") == nil then
        print("rules.png not found")
        gameState = "error"
        return
    end

    output.imageData = love.image.newImageData("source.png")
    setupWindow(output)
    output.image = love.graphics.newImage(output.imageData)

    -- get initial image and initial rewrite state
    initialImageData = output.imageData:clone()
    rewriteState = parseState(output.imageData)

    -- load rules
    local rulesImgData = love.image.newImageData("rules.png")
    rewriteRules = parseRules(rulesImgData)
    
    -- set image to represent the initial state
    updateImagedata(output.imageData, rewriteState)
    output.image:replacePixels(output.imageData)
end

function setupWindow(output)
    --print("window size: " .. output.imageData:getWidth(), output.imageData:getHeight(), output.zoomLevel)
    love.graphics.setDefaultFilter('nearest', 'nearest')
    love.graphics.setBackgroundColor(0.5, 0.5, 0.5)
    love.window.setMode(
        output.imageData:getWidth() * output.zoomLevel, 
        output.imageData:getHeight() * output.zoomLevel, 
    {resizable=false})
end

function love.update(dt)
    if gameState ~= "running" then
        return
    end
    output.timeSinceLastUpdate = output.timeSinceLastUpdate + dt
    if output.timeSinceLastUpdate > output.updateInterval then
        output.timeSinceLastUpdate = output.timeSinceLastUpdate - output.updateInterval

        -- new state, apply rules once
        updateState(rewriteState, rewriteRules)

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
        updateImagedata(output.imageData, rewriteState)
        output.image:replacePixels(output.imageData)
    end
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

-- function printBinary(num, width)
--     for i = width - 1, 0, -1 do --backwards
--         local bit = bit.band(bit.rshift(num, i), 1)
--         io.write(bit == 1 and "1" or "0")
--     end
--     print()
-- end

function shift2DTable(table, dx, dy)
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

function flip2DTable(table, flipHorizontal)
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

function rotate2DTable(table)
    local width = #table[1]
    local height = #table
    local newTable = {}
    for x = 1, width do
        newTable[x] = {}
        for y = 1, height do
            newTable[x][y] = table[height - y + 1][x]
        end
    end
    return newTable
end

function print2DTablesSideBySide(tables)
    for y = 1, #tables[1] do
        for i = 1, #tables do
            for x = 1, #tables[i][1] do
                io.write(tables[i][y][x] == 1 and "1" or "0")
            end
            io.write("  ")
        end
        print()
    end
end