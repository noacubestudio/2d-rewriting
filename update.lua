-- update state and image data

local recentHeatmap = {}
local heatmap = {}

function updateState(originalState, rules, app)
    
    function findFirstSubPattern(large_pattern, sub_pattern, startX, startY)
        local large_rows = #large_pattern
        local large_cols = #large_pattern[1]
        local sub_rows = #sub_pattern
        local sub_cols = #sub_pattern[1]
        local misses = 0
        for i = startX, large_rows - sub_rows + 1 do
            for j = startY, large_cols - sub_cols + 1 do
                local match = true
                for si = 1, sub_rows do
                    for sj = 1, sub_cols do
                        if large_pattern[i + si - 1][j + sj - 1] ~= sub_pattern[si][sj] and sub_pattern[si][sj] > -1 then
                            match = false
                            break
                        end
                    end
                    if not match then misses = misses + 1 break end
                end
                if match then
                    return i, j, misses -- Return the first match position
                end
            end
        end
        return nil, nil, misses -- No match found
    end

    function replaceSubPattern(large_pattern, sub_pattern, i, j, ruleIndex)
        local sub_rows = #sub_pattern
        local sub_cols = #sub_pattern[1]
    
        for si = 1, sub_rows do
            for sj = 1, sub_cols do
                -- only replace if the sub pattern has a value at this position
                if sub_pattern[si][sj] > -1 then
                    large_pattern[i + si - 1][j + sj - 1] = sub_pattern[si][sj]
                end
                -- indicate that the rule was applied here on the heatmap.
                -- set binary digit to 1 that corrensponds to index, so we can see which rules were applied where. other digits stay.
                heatmap[i + si - 1][j + sj - 1] = bit.bor(heatmap[i + si - 1][j + sj - 1], bit.lshift(1, ruleIndex))
                recentHeatmap[i + si - 1][j + sj - 1] = bit.bor(recentHeatmap[i + si - 1][j + sj - 1], bit.lshift(1, ruleIndex))
            end
        end
    end

    function newStartCoordinate(x, y, width, height)
        -- the last change was at x, y.
        -- we don't want to repeat matching from the first cell again.
        -- but a pattern in an earlier position might have been affected by the last change and should be checked again.
        -- so we shift over to the left and up by the width and height of the pattern.
        -- minimum x, y is 1, 1.
        local startX = math.max(1, x - width + 1)
        local startY = math.max(1, y - height + 1)
        return startX, startY
    end

    function turnOffAllHeat(index, heatmap)
        for i = 1, #heatmap do
            for j = 1, #heatmap[1] do
                local binary = heatmap[i][j]
                heatmap[i][j] = bit.band(binary, bit.bnot(bit.lshift(1, index)))
            end
        end
    end

    function findFirstOne(heatmap)
        for i = 1, #heatmap do
            for j = 1, #heatmap[1] do
                if heatmap[i][j] > 0 then
                    return i, j
                end
            end
        end
        return nil, nil
    end

    function findFirstChangedCell (heatmap, leftSpread, upSpread)
        -- changes start from the first cell that has heat.
        local firstChangedX, firstChangedY = findFirstOne(deeperCopy(heatmap))
        if firstChangedX then
            -- add padding
            x, y = newStartCoordinate(firstChangedX, firstChangedY, leftSpread, upSpread)
            return x, y
        end
    end

    function maxPointInReadingOrder(ax, ay, bx, by)
        if ay == by then 
            return math.max(ax, bx), ay
        elseif ay > bx then
            return ax, ay
        end
        return bx, by
    end


    local madeChange = false
    local state = shallowCopy(originalState) -- copy the before state to modify it

    -- initialize heatmaps. one is for the whole time, the other is for the last loop.
    -- the former is a nice visual representation of which rules were applied where.
    -- the latter is used to skip checking positions that didn't change since the last loop.
    if app.loopCount == 0 then
        heatmap = {}
        recentHeatmap = {}
        for i = 1, #state do
            heatmap[i] = {}
            recentHeatmap[i] = {}
            for j = 1, #state[1] do
                heatmap[i][j] = 0
                recentHeatmap[i][j] = 0
            end
        end
        print("   loop start. rewrites per turn:")
        io.write("<> ")
    end

    local totalHits = 0
    local totalMisses = 0
    for i, rule in ipairs(rules) do
        if true then -- might want to skip some rules in the future based on other conditions. keep as a reminder. TODO WIP
            local beforePattern = rule[1]
            local patternWidth, patternHeight = #beforePattern[1], #beforePattern
            -- io.write("<> " .. string.format("%02d", i) .. ": ")

            local minChangingX, minChangingY = 1, 1
            if app.loopCount > 0 then
                -- in later loops, we can skip a bunch of looping by checking if there is some heat in the cell.
                -- if there isn't, then no rule applied since last time.
                -- for this to work, we need to turn off the heat for the rule we are about to apply.
                turnOffAllHeat(i, recentHeatmap)
                minChangingX, minChangingY = findFirstChangedCell(recentHeatmap, patternWidth, patternHeight) or 1, 1
            end

            -- apply the rule to the state
            -- find the first matching pattern and replace it with a random choice from the rule
            -- repeat until no more matches are found.
            local ruleMisses = 0
            local ruleHits = 0
            local x, y, misses = findFirstSubPattern(state, beforePattern, minChangingX, minChangingY)
            ruleMisses = ruleMisses + (misses or 0)
            while x and y do
                ruleHits = ruleHits + 1
                local choice = math.random(2, #rule)
                
                replaceSubPattern(state, rule[choice], x, y, i)

                -- start from the next cell that isn't definitely unchanged/ wasn't matchning so far, rather than back from the top.
                local startX, startY = newStartCoordinate(x, y, patternWidth, patternHeight)
                startX, startY = maxPointInReadingOrder(startX, startY, minChangingX, minChangingY)

                -- look again for the next match from the new start onwards.
                x, y, misses = findFirstSubPattern(state, beforePattern, startX, startY)
                ruleMisses = ruleMisses + (misses or 0)
            end
            -- print(ruleHits .. " of " .. ruleHits + ruleMisses .. ".")
            totalHits = totalHits + ruleHits
            totalMisses = totalMisses + ruleMisses
        end
    end

    -- replace the original state with the modified one
    --print("<> " .. totalHits .. " of " .. totalHits + totalMisses .. ".")
    io.write(totalHits .." ")
    --print()
    if totalHits > 0 then
        for i = 1, #state do
            originalState[i] = state[i]
        end
        return true, totalHits, totalMisses
    end
    print()
    --print("end of update.")
    return false, totalHits, totalMisses
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
        -- TODO WIP, turn the rules data back into an image? would allow for some interesting visualizations.
        -- However it seems important to keep the color etc. as they were.
        -- Right now, the rule image can not be edited.
        return
    end
    local width = imageData:getWidth()
    local height = #state

    for y=0, height-1 do
        local row = state[y+1]
        for x=0, width-1 do
            if #heatmap > 0 and app.activeHeatmapRule > 0 then
                local heatmapBinary = heatmap[y+1][x+1]
                local digit = bit.band(bit.rshift(heatmapBinary, app.activeHeatmapRule), 1)
                imageData:setPixel(x, y, digit, row[x+1], row[x+1], 1)
            elseif app.printing then
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