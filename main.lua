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
    rewriteState = parseInitialState(output.imageData)

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
    if gameState ~= "running" then
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
        output.updateInterval = output.updateInterval == 99999 and 0.04 or 99999
    end
    -- reset
    if key == "r" then
        print("resetting to initial state")
        output.imageData = initialImageData:clone()
        rewriteState = parseInitialState(output.imageData)
        -- first update
        updateImagedata(output.imageData, rewriteState)
        output.image:replacePixels(output.imageData)
    end
end




-- initial read of the images to create rewrite rules and state

function parseInitialState(imageData)

    print("parsing initial state...")

    local function color2number(r, g, b)
        if r == 0 and g == 0 and b == 0 then
            return 0
        elseif r == 1 and g == 1 and b == 1 then
            return 1
        else
            -- for initial state, unknown pixels are randomly set to black or white
            return love.math.random() > 0.5 and 1 or 0
        end
    end

    -- make 2d table of 1 and 0
    local rows = {}

    for y=0, imageData:getHeight()-1 do
        local row = {}
        for x=0, imageData:getWidth()-1 do
            local r, g, b = imageData:getPixel(x, y)
            table.insert(row, color2number(r, g, b))
        end
        table.insert(rows, row)
    end

    print("done - " .. #rows .. "x" .. #rows[1])
    return rows
end

function parseRules(imageData)
    
    local function color2bits(r, g, b, a)
        -- returns color bit and mask bit
        if a == 0 then
            return nil, nil -- empty pixel
        elseif r == 0 and g == 0 and b == 0 then
            return 0, 1 -- black pixel
        elseif r == 1 and g == 1 and b == 1 then
            return 1, 1 -- white pixel
        else
            return 0, 0 -- wildcard, the color won't be considered when rules are applied
        end
    end

    local function rotateRule(rule)
        local rotatedRule = {
            before = rotate2DTable(rule.before),
            after = rotate2DTable(rule.after),
            beforeMask = rotate2DTable(rule.beforeMask),
            afterMask = rotate2DTable(rule.afterMask)
        }
        return rotatedRule
    end

    local height = imageData:getHeight()
    local width = imageData:getWidth()
    print("parsing rules... - " .. width .. "x" .. height)

    -- go down the image and collect rules
    local rules = {}
    local currentRule = {}
    for y=0,height-1 do

        -- rules contain 2d arrays of numbers representing black and white pixels / the changing pixels
        if currentRule.before == nil then
            io.write("? - ")
            currentRule = {
                before = {},
                after = {},
                beforeMask = {},
                afterMask = {}
            }
        end

        -- process next row
        local row = {
            before = {},
            after = {},
            beforeMask = {},
            afterMask = {}
        }

        -- go through pixels and collect the left and right side of the rule
        local beforeSideIndex = nil
        local afterSideIndex = nil
        for x=0,width-1 do
            local r, g, b, a = imageData:getPixel(x, y)
            local colorBit, maskBit = color2bits(r, g, b, a)

            -- empty pixel
            if colorBit == nil or maskBit == nil then
                -- rule has a left side, so the next pixel is part of the right side
                if beforeSideIndex ~= nil and afterSideIndex == nil then
                    afterSideIndex = x + 1
                end
                -- right side actually not started yet, lets look further on the right
                if afterSideIndex == x then
                    afterSideIndex = afterSideIndex + 1
                end
            else
                -- left side starts here
                if beforeSideIndex == nil then
                    beforeSideIndex = x
                end

                -- add pixel to the correct side of the row
                local side = afterSideIndex == nil and row.before or row.after
                local mask = afterSideIndex == nil and row.beforeMask or row.afterMask
                side = table.insert(side, colorBit)
                mask = table.insert(mask, maskBit)
            end
        end

        -- if the row is not empty, add it to the current rule
        if #row.before > 0 then
            table.insert(currentRule.before,     row.before)
            table.insert(currentRule.beforeMask, row.beforeMask)
            if #row.after > 0 then
                table.insert(currentRule.after,     row.after)
                table.insert(currentRule.afterMask, row.afterMask)
            end
            --print(currentRule.before)
        else
            -- if the row is empty, finish the current rule
            if #currentRule.before > 0 then
                rotations = { currentRule }
                for i = 1, 3 do
                    table.insert(rotations, rotateRule(rotations[#rotations]))
                end
                print("parsed a rule, " .. #currentRule.before .. "x" .. #currentRule.after)
                for _, rule in ipairs(rotations) do
                    table.insert(rules, rule)
                    print2DTablesSideBySide({rule.before, rule.after, rule.beforeMask, rule.afterMask})
                    print()
                end
                currentRule = {}
            end
        end
    end

    print("done - total count " .. #rules)
    return rules
end




-- update state and image data

function updateState(originalState, rules)
    local state = shallowCopy(originalState) -- copy the before state to modify it

    function findFirstSubPattern(large_pattern, sub_pattern, sub_mask)
        local large_rows = #large_pattern
        local large_cols = #large_pattern[1]
        local sub_rows = #sub_pattern
        local sub_cols = #sub_pattern[1]
    
        for i = 1, large_rows - sub_rows + 1 do
            for j = 1, large_cols - sub_cols + 1 do
                local match = true
                for si = 1, sub_rows do
                    for sj = 1, sub_cols do
                        if large_pattern[i + si - 1][j + sj - 1] ~= sub_pattern[si][sj] and sub_mask[si][sj] == 1 then
                            match = false
                            break
                        end
                    end
                    if not match then break end
                end
                if match then
                    return i, j  -- Return the first match position
                end
            end
        end
        return nil  -- No match found
    end

    function replaceSubPattern(large_pattern, sub_pattern, sub_mask, i, j)
        local sub_rows = #sub_pattern
        local sub_cols = #sub_pattern[1]
    
        for si = 1, sub_rows do
            for sj = 1, sub_cols do
                if sub_mask[si][sj] == 1 then
                    large_pattern[i + si - 1][j + sj - 1] = sub_pattern[si][sj]
                end
            end
        end
    end

    for _, rule in ipairs(rules) do
        local leftSide = rule.before
        local rightSide = rule.after
        local leftSideMask = rule.beforeMask
        local rightSideMask = rule.afterMask

        local x, y = findFirstSubPattern(state, leftSide, leftSideMask)

        while x and y do
            replaceSubPattern(state, rightSide, rightSideMask, x, y)
            x, y = findFirstSubPattern(state, leftSide, leftSideMask)
        end
    end

    -- replace the original state with the modified one
    for i = 1, #state do
        originalState[i] = state[i]
    end
end

function updateImagedata(imageData, rows)
    local width = imageData:getWidth()
    local height = #rows

    for y=0, height-1 do
        local row = rows[y+1]
        for x=0, width-1 do
            local color = row[x+1]
            imageData:setPixel(x, y, color, color, color, 1)
        end
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

function printBinary(num, width)
    for i = width - 1, 0, -1 do --backwards
        local bit = bit.band(bit.rshift(num, i), 1)
        io.write(bit == 1 and "1" or "0")
    end
    print()
end

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