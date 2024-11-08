-- see if there is a new state image, and if so, set its' data as the starting state.
function loadState(data, filename)
    if love.filesystem.getInfo(filename) == nil then
        print(filename .. " not found")
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
    setupWindow(data.sourceImagedata:getWidth(), data.sourceImagedata:getHeight(), app.zoomLevel)
    setupOutput(data)
    print("loaded new state.")
end


-- see if there is a new rules image, parse it to overwrite the current rules.
function loadRules(data, filename)
    if love.filesystem.getInfo(filename) == nil then
        print(filename .. " not found")
        app.error = true
        return
    end

    -- load and first check if the image has changed
    local newImageData = love.image.newImageData(filename)
    local newHash = imageHash(newImageData)
    if newHash == data.rulesImageHash then
        print("no change in " .. filename)
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
    print("loaded new rules.")
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
function setupWindow(newWidth, newHeight, scale)
    love.graphics.setDefaultFilter('nearest', 'nearest')

    local width, height, flags = love.window.getMode()
    local sizeChanged = (width ~= newWidth * scale or height ~= newHeight * scale)
    
    if sizeChanged then
        love.window.setMode(newWidth * scale, newHeight * scale, {resizable=false, borderless=true})
    end
end