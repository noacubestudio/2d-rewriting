require "setup"
require "parse"
require "update"

require "TSerial"

app = {
    -- app state
    idle = true,
    paused = false,
    editing = false,
    error = false,
    viewingCode = false,
    viewingHeatmapForRule = 0, 
    viewingPreview = false,
    focused = true,
    printing = false,

    -- on each input
    input = {
        totalLoops = 0,
        totalChanges = 0,
        totalChecks = 0,
        -- key input
        key = nil,
        -- mouse input
        x = 0,
        y = 0,
        startX = nil,
        startY = nil,
        brushColor = 0,
        editedState = false,
    },

    -- update loop
    timeSinceLastUpdate = 0,

    -- settings. defaults before being rewritten by settings.lua
    settings = {
        updateInterval = 0.1, -- seconds
        pixelScale = 4,
        windowX = nil,
        windowY = nil,
        logRules = false,
    },
}

local data = {
    -- loaded images and their associated tables
    -- tables are generated by parsing the images
    -- the board gets updated by the rules.
    board = {
        table = {}, -- the current state
        imagedata = nil,
        imageHash = 0,
        width = 0,
        height = 0,
        heatmap = {}, -- for each rule
        lastChanges = {}, -- for each rule
    },
    rules = {
        table = {}, -- the rules
        imagedata = nil,
        imageHash = 0,
        width = 0,
        height = 0,
    },
    symbols = {
        table = {}, -- the special symbols
        imagedata = nil,
        imageHash = 0,
        width = 0,
        height = 0,
    },
    output = {
        -- output image
        -- no table or hash, as it's generated from the board or rules
        image = nil, -- the actual image being drawn
        imagedata = nil,
        width = 0,
        height = 0,
    },
    previewBoard = {
        table = {}, -- the preview board for editing
        -- matches the normal board.
        lastChanges = {}, -- for each rule
    },
    undo = {
        table = {}, -- the undo board
        -- matches the normal board.
    },
}

function love.load() 
    local cursor = love.mouse.getSystemCursor("crosshair")
    love.mouse.setCursor(cursor)
    loadSettings(app.settings, "settings.lua")
    loadImages(data)
end

function restartLoop()
    if (app.editing or app.input.key) and not app.viewingPreview then
        print("saving previous state for undo.")
        data.undo.table = deepCopy(data.board.table)
        --printPatternsSideBySide({data.undo.table})
    end
    if app.input.totalLoops > 0 then
        app.input.totalLoops = 0
        app.input.editedState = false
        if app.viewingPreview then
            io.write(", ")
        else
            print("reset loop counters.")
        end
    end
    app.input.totalChanges, app.input.totalChecks = 0, 0
end

function love.update(dt)

    -- update every <settings.updateInterval> seconds
    local updateNow = false
    app.timeSinceLastUpdate = app.timeSinceLastUpdate + dt
    if app.timeSinceLastUpdate > app.settings.updateInterval then
        app.timeSinceLastUpdate = app.timeSinceLastUpdate - app.settings.updateInterval
        updateNow = true
    end

    if updateNow then updateTitle(data) end

    if not app.focused and love.window.hasFocus() then
        -- resume when window regains focus
        app.focused = true
        print("regained focus.")   
        loadImages(data)

    elseif app.focused and not love.window.hasFocus() then
        app.focused = false
        print("lost focus.")         
        -- window position
        app.settings.windowX, app.settings.windowY = love.window.getPosition()
        return
    end

    if app.error or app.viewingCode or app.idle or app.paused then
        return
    end

    -- state is shown and unpaused and not idle (more potential changes to be made)
    if updateNow then
        -- new state, apply rules once
        local boardData = app.editing and data.previewBoard or data.board
        local madeChanges, hits, misses = updateBoard(boardData, data.rules.table)

        app.input.totalLoops = app.input.totalLoops + 1
        app.input.totalChanges = app.input.totalChanges + hits
        app.input.totalChecks = app.input.totalChecks + misses

        if #data.undo.table > 0 and patternsEqual(boardData.table, data.undo.table) and not app.editing then
            print("")
            print("   no visible changes!")
            app.idle = true
            printResults(app.input.totalLoops, app.input.totalChanges, app.input.totalChecks)
            app.input.totalChanges = 0
            return
        end

        if not madeChanges then
            -- no changes made, so we're done.
            app.idle = true
            printResults(app.input.totalLoops, app.input.totalChanges, app.input.totalChecks)
            -- no return here, so the image is still updated once more.
            -- this can be used for (resetting) visual effects.
            -- totals are reset when a new input is made.
        end
        -- update image
        updateImagedata(data.output.imagedata, boardData)
        data.output.image:replacePixels(data.output.imagedata)
    end
end

function printResults(loops, changes, checks, interrupted)
    if app.viewingPreview then
        return
    end
    local message = interrupted and "interrupted by input key" or "finished"
    print("   " .. message .. " after " .. loops .. " turns.")
    if changes > 0 then
        print("   total: " .. changes .. " / " .. checks + changes .. " match.")
        --print("   hit rate is " ..  string.format("%.3f", (changes / (checks + changes)) * 100)  .. "%.")
        local pixelCount = data.board.width * data.board.height
        print("   avg pixel: " .. string.format("%.3f", changes / pixelCount)
            .. " / " .. string.format("%.3f", (checks + changes) / pixelCount) .. " match.")
    elseif not app.editing then
        print("   no changes made.")
    end
    print()
end

function love.draw()
    if app.error then return end

    -- draw output image using the scale. matches window size.
    love.graphics.scale(app.settings.pixelScale, app.settings.pixelScale)
    love.graphics.draw(data.output.image, 0, 0)

    -- bounding box for editing
    if app.focused and love.mouse.getX() > 0 and love.mouse.getY() > 0 then
        local x, y = mouseToCoordinate(love.mouse.getX(), love.mouse.getY())
        if x > 0 and y > 0 and x <= data.output.imagedata:getWidth() and y <= data.output.imagedata:getHeight() then
            if app.editing then 
                love.graphics.setColor(1, 0, 0)
            else 
                love.graphics.setColor(0, 0.5, 1)
            end
            love.graphics.setLineWidth(1/app.settings.pixelScale)
            local x, y = app.input.x, app.input.y
            local startX, startY = app.input.startX, app.input.startY
            if startX == nil or startY == nil then
                love.graphics.rectangle("line", x - 1, y - 1, 1, 1)
            else
                love.graphics.rectangle("line", math.min(x, startX) - 1, math.min(y, startY) - 1, math.abs(x - startX) + 1, math.abs(y - startY) + 1)
            end
        end
    end

    love.graphics.reset()
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

        -- get out of special views
        app.viewingHeatmapForRule = 0
       
        -- output one more time, to show if paused or not
        updateImagedata(data.output.imagedata, data.board)
        data.output.image:replacePixels(data.output.imagedata)

    elseif key == "r" and not app.viewingCode then
        -- reset
        print("resetting state.")
        updatePallette()
        app.timeSinceLastUpdate = 0
        -- window position
        app.settings.windowX, app.settings.windowY = love.window.getPosition()
        setupWindow(data.board.width, data.board.height, app.settings)
        setupOutput(data) 

    elseif key == "u" and not app.viewingCode then
        -- undo
        if #data.undo.table > 0 and (app.input.totalChanges > 0 or app.input.editedState) then
            print("undoing last turn.")
            updatePallette()
            app.timeSinceLastUpdate = 0
            --
            data.board.table = deepCopy(data.undo.table)
            updateImagedata(data.output.imagedata, data.board)
            data.output.image:replacePixels(data.output.imagedata)
            app.input.totalLoops = 0
            app.input.totalChanges = 0
            app.input.totalChecks = 0
            app.input.editedState = false
        else
            print("no changes to undo.")
        end
    
    elseif key == "l" then
        -- reload symbols, board and rules
        loadImages(data)
    
    elseif key == "s" then
        -- save image
        if app.viewingCode then
            print("cannot save image while viewing code.")
            return
        end
        print("saving image")

        app.printing = true
        updateImagedata(data.output.imagedata, data.board)

        local fileData = data.output.imagedata:encode("png", "output.png")
        love.filesystem.write("output.png", fileData)
        print("image saved as output.png in path: " .. love.filesystem.getSaveDirectory())

        app.printing = false
        updateImagedata(data.output.imagedata, data.board)
    
    elseif key == "tab" then
        -- switch between rule and board display
        local toX, toY
        if app.viewingCode then
            app.viewingCode = false
            print("viewing board.")
            toX, toY = data.board.width, data.board.height
        else
            app.viewingCode = true
            print("viewing rules.")
            toX, toY = data.rules.width, data.rules.height
        end
        setupWindow(toX, toY, app.settings)
        setupOutput(data)

    elseif key == "up" or key == "down" or key == "left" or key == "right" then
        -- input keys for games, etc.
        if app.viewingCode or app.paused then
            app.paused = false
            print("unpaused.")
            if app.viewingCode then
                print("viewing board.")
                app.viewingCode = false
                toX, toY = data.board.width, data.board.height
                setupWindow(toX, toY, app.settings)
                setupOutput(data)
            end
            return
        end

        app.input.key = key -- for this next update, access the last key pressed. reset in the update fn.

        if app.idle then
            print("INPUT KEY: " .. key)
            restartLoop()
            app.timeSinceLastUpdate = 0
            app.idle = false
        else
            print()
            printResults(app.input.totalLoops, app.input.totalChanges, app.input.totalChecks, true)
            print("INPUT WHILE LOOPING: " .. key)
            restartLoop()
            app.timeSinceLastUpdate = 0
        end

    elseif key == "1" or key == "2" then
        -- show different heatmaps over the state that represent where each rule matched since last input
        app.viewingHeatmapForRule = app.viewingHeatmapForRule + (key == "1" and -1 or 1)

        -- cycle through rules
        if app.viewingHeatmapForRule < -1 then
            app.viewingHeatmapForRule = #data.rules.table
        elseif app.viewingHeatmapForRule > #data.rules.table then
            app.viewingHeatmapForRule = -1
        end

        -- 0 is the default state without heatmap
        if app.viewingHeatmapForRule == 0 then
            print("viewing state without heatmap.")
        else
            if app.viewingHeatmapForRule == -1 then
                print("viewing per-cycle heatmap for all rules.")
            else
                print("viewing heatmap for rule: " .. app.viewingHeatmapForRule)
                -- wip. what order are those heatmaps in? is the displayed rule the same?
                -- get the rule
                local rule = data.rules.table[app.viewingHeatmapForRule]
                ---- print to console
                for i, v in ipairs(rule.rewrites) do
                    local combinedTable = deepCopy(v.right)
                    table.insert(combinedTable, 1, v.left)
                    printPatternsSideBySide(combinedTable)
                end
            end
        end
        --print(#data.board.heatmap, #data.board.lastChanges)
        updateImagedata(data.output.imagedata, data.board)
        data.output.image:replacePixels(data.output.imagedata)
    else
        --print("key pressed: " .. key)
    end
end

-- scroll
function love.wheelmoved(x, y)

    --when holding shift, change update interval
    if love.keyboard.isDown("lshift") then
        app.settings.updateInterval = math.max(0.01, app.settings.updateInterval + y * 0.01)
        print("update interval: " .. app.settings.updateInterval)
        return
    end

    -- first get position of window
    app.settings.windowX, app.settings.windowY = love.window.getPosition()

    if y > 0 then
        -- scroll up
        app.settings.pixelScale = app.settings.pixelScale + 1
    elseif y < 0 then
        -- scroll down
        app.settings.pixelScale = math.max(1, app.settings.pixelScale - 1)
    end
    local baseWidth, baseHeight = data.output.imagedata:getWidth(), data.output.imagedata:getHeight()
    setupWindow(baseWidth, baseHeight, app.settings)
end

function love.mousepressed(x, y, button, istouch, presses)
    app.input.brushColor = button == 1 and 0 or 1
    if button == 1 or button == 2 then
        app.editing = true
        app.input.x, app.input.y = mouseToCoordinate(x, y)
        app.input.startX, app.input.startY = app.input.x, app.input.y
        print("editing at " .. app.input.x .. ", " .. app.input.y .. " with color " .. app.input.brushColor)

        if app.viewingCode then
            return
        end
        restartLoop()
        app.viewingPreview = true -- is after the restartLoop, so that still saves the undo state.
        app.idle = false
        data.previewBoard.table = deepCopy(data.board.table)
        drawInputRectInBoard(data.previewBoard.table)
        if app.paused then
            updateImagedata(data.output.imagedata, data.previewBoard)
            data.output.image:replacePixels(data.output.imagedata)
        end
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    app.input.x, app.input.y = mouseToCoordinate(x, y)
    if love.mouse.isDown(1) or love.mouse.isDown(2) then
        if app.viewingCode then
            return
        end
        restartLoop(true)
        app.idle = false
        data.previewBoard.table = deepCopy(data.board.table)
        drawInputRectInBoard(data.previewBoard.table)
        if app.paused then
            updateImagedata(data.output.imagedata, data.previewBoard)
            data.output.image:replacePixels(data.output.imagedata)
        end
    end
end

function love.mousereleased(x, y, button, istouch, presses)
    if button == 1 or button == 2 then
        app.editing = false
        app.idle = false
        app.viewingPreview = false
        app.input.x, app.input.y = mouseToCoordinate(x, y)

        if app.viewingCode then
            return
        end
        --app.input.totalChanges = app.input.totalChanges + 1
        app.input.editedState = true
        print()
        print("drawing in grid.")
        drawInputRectInBoard(data.board.table)
    end
    app.input.startX, app.input.startY = nil, nil
end

function mouseToCoordinate(x, y)
    x, y = math.floor(x / app.settings.pixelScale) + 1, math.floor(y / app.settings.pixelScale) + 1
    -- clamp to image size
    x = math.max(1, math.min(x, data.output.imagedata:getWidth()))
    y = math.max(1, math.min(y, data.output.imagedata:getHeight()))
    return x, y
end

function drawInputRectInBoard(board)
    local startX = app.input.startX or app.input.x
    local startY = app.input.startY or app.input.y
    local endX, endY = app.input.x, app.input.y
    if startX == endX and startY == endY then 
        board[app.input.y][app.input.x] = app.input.brushColor
    else 
        for i = math.min(startY, endY), math.max(startY, endY) do
            for j = math.min(startX, endX), math.max(startX, endX) do
                if i > 0 and j > 0 then board[i][j] = app.input.brushColor end
            end
        end
    end
end


-- helper functions

function printPatternsSideBySide(tables)
    print()
    local tallestSize = 0
    for _, symbol in ipairs(tables) do
        if type(symbol) ~= "string" then
            tallestSize = math.max(tallestSize, #symbol)
        end
    end

    for y = 1, tallestSize do -- for each row, print row of the symbols side by side
        io.write("   ")
        for _, symbol in ipairs(tables) do -- each symbol
            if type(symbol) == "string" then
                -- keyword
                if y == 1 then
                    io.write(symbol)
                else
                    -- match the width of the word with spaces underneath
                    for _ = 1, #symbol do
                        io.write(" ")
                    end
                end
            else 
                -- 2d table
                if type(symbol[1]) ~= "table" then
                    print("not a 2d table")
                    return
                end
                if y <= #symbol then
                    for x = 1, #symbol[y] do
                        local char = symbol[y][x] == 1 and "$$" or symbol[y][x] == 0 and "[]" or ". "
                        io.write(char)
                    end
                else
                    for _ = 1, #symbol[1] do
                        io.write("  ")
                    end
                end
            end
            io.write("  ") -- space between symbols
        end
        print()
    end
end

function swapAxes(t)
    local newTable = {}
    for y = 1, #t[1] do
        newTable[y] = {}
        for x = 1, #t do
            newTable[y][x] = t[x][y]
        end
    end
    return newTable
end

function deepCopy(table)
    local newTable = {}
    for i, part in ipairs(table) do
        if type(part) == "table" then
            newTable[i] = deepCopy(part)
        else
            newTable[i] = part
        end
    end
    return newTable
end

function shallowCopy(table)
    local newTable = {}
    for i, part in ipairs(table) do
        newTable[i] = part
    end
    return newTable
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
            newTable[y][x] = table[flipHorizontal and y or height - y + 1][flipHorizontal and width - x + 1 or x]
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
    if #matrix1 ~= #matrix2 or #matrix1[1] ~= #matrix2[1] then
        return false -- different dimensions, so not equal
    end
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
