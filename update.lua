-- update state and image data

function updateState(originalState, rules)
    local madeChange = false
    local state = shallowCopy(originalState) -- copy the before state to modify it

    function findFirstSubPattern(large_pattern, sub_pattern)
        local large_rows = #large_pattern
        local large_cols = #large_pattern[1]
        local sub_rows = #sub_pattern
        local sub_cols = #sub_pattern[1]
    
        for i = 1, large_rows - sub_rows + 1 do
            for j = 1, large_cols - sub_cols + 1 do
                local match = true
                for si = 1, sub_rows do
                    for sj = 1, sub_cols do
                        if large_pattern[i + si - 1][j + sj - 1] ~= sub_pattern[si][sj] and sub_pattern[si][sj] > -1 then
                            match = false
                            break
                        end
                    end
                    if not match then break end
                end
                if match then
                    return i, j -- Return the first match position
                end
            end
        end
        return nil -- No match found
    end

    function replaceSubPattern(large_pattern, sub_pattern, i, j)
        local sub_rows = #sub_pattern
        local sub_cols = #sub_pattern[1]
    
        for si = 1, sub_rows do
            for sj = 1, sub_cols do
                if sub_pattern[si][sj] > -1 then
                    large_pattern[i + si - 1][j + sj - 1] = sub_pattern[si][sj]
                end
            end
        end
    end

    for i, rule in ipairs(rules) do
        local beforePattern = rule[1]
        local x, y = findFirstSubPattern(state, beforePattern)
        while x and y do
            madeChange = true
            local choice = math.random(2, #rule)
            --io.write("(" .. x .. " " .. y .. ") ")
            io.write(" " .. i)
            if choice > 2 then io.write("(" .. choice - 1 .. ")") end
            replaceSubPattern(state, rule[choice], x, y)
            x, y = findFirstSubPattern(state, beforePattern)
        end
    end

    -- replace the original state with the modified one
    if madeChange then
        for i = 1, #state do
            originalState[i] = state[i]
        end
        return true
    end
    print()
    print("no more matches left.")
    return false
end

-- use the state table to update the image data
-- visual-only effects can be applied here

local palette = { 
    -- replaced with basePalette while saving screenshots
    {0, 0, 0},
    {0.6, 0.9, 0.8}
}
local basePalette = {
    {0, 0, 0},
    {1, 1, 1}
}

function updatePallette()
    -- randomize light color
    palette[2] = {love.math.random(200, 255)/255, love.math.random(200, 255)/255, love.math.random(200, 255)/255}
end

function updateImagedata(imageData, state, app)
    if app.viewingCode then
        -- wip?
        return
    end
    local width = imageData:getWidth()
    local height = #state

    for y=0, height-1 do
        local row = state[y+1]
        for x=0, width-1 do
            if app.printing then
                local color = basePalette[row[x+1]+1]
                imageData:setPixel(x, y, 
                    color[1], 
                    color[2], 
                    color[3], 
                1)
            else
                local color = palette[row[x+1]+1]
                local randomFactor = not (app.editing or app.paused or app.idle) and 0.95 + love.math.random() * 0.05 or 1
                imageData:setPixel(x, y, 
                    color[1] * randomFactor, 
                    color[2] * randomFactor, 
                    color[3] * randomFactor, 
                1)
            end
        end
    end
end