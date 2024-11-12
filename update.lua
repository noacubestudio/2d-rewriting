-- update board and output image data

local heatmapPerCycle = {}
local heatmapPerInput = {}

function updateBoard(originalBoard, rules)

    function matchesInitialConditions(keywords)
        local matching = true
        for _, keyword in ipairs(keywords) do
            if string.find(keyword, "input_") then
                local directionKey = string.sub(keyword, 7)
                if app.lastInputKey ~= directionKey then
                    matching = false
                    break
                end
            end
        end
        return matching
    end
    
    function findFirstSubPattern(large_pattern, sub_pattern, startX, startY, tilesStartPosition)
        local large_rows = #large_pattern
        local large_cols = #large_pattern[1]
        local sub_rows = #sub_pattern
        local sub_cols = #sub_pattern[1]
        local misses = 0

        local startX = startX or 1
        local startY = startY or 1
        --local tileWidth = 1
        --local tileHeight = 1
        --if tilesStartPosition and tilesStartPosition.x and tilesStartPosition.y then
        --    tileWidth = sub_cols + 1
        --    tileHeight = sub_rows + 1
        --    -- skip all checks that are not on the top left corner of a tile.
        --    -- to do this, we need to find the top left corner of the tile after the start position.
        --    -- the tilesStartPosition can contain an offset from the start position.
        --
        --    -- with the offset calculation this would be:
        --    startX = math.ceil((startX - tilesStartPosition.x) / tileWidth) * tileWidth + 1
        --    startY = math.ceil((startY - tilesStartPosition.y) / tileHeight) * tileHeight + 1
        --end
        for outy = startY, large_rows - sub_rows + 1 do -- vertical
            for outx = startX, large_cols - sub_cols + 1 do -- horizontal
                local match = true
                if outx == large_cols - sub_cols + 1 then
                    startX = 1
                end
                for iny = 1, sub_rows do
                    for inx = 1, sub_cols do
                        if large_pattern[outy + iny - 1][outx + inx - 1] ~= sub_pattern[iny][inx] and sub_pattern[iny][inx] > -1 then
                            match = false
                            break
                        end
                    end
                    if not match then misses = misses + 1 break end
                end
                if match then
                    --tileStartPosition = tileStartPosition and {x = i, y = j} or nil
                    return outx, outy, misses -- Return the first match position
                end
            end
        end
        return nil, nil, misses -- No match found
    end

    function replaceSubPattern(source_pattern, replacement_options, x, y, ruleIndex)
        -- choose a random replacement from the options
        local sub_pattern = replacement_options[love.math.random(1, #replacement_options)]
        local sub_rows = #sub_pattern
        local sub_cols = #sub_pattern[1]
    
        for suby = 1, sub_rows do
            for subx = 1, sub_cols do
                -- only replace if the sub pattern has a value at this position
                if sub_pattern[suby][subx] > -1 then
                    source_pattern[y + suby - 1][x + subx - 1] = sub_pattern[suby][subx]
                end
                -- indicate that the rule was applied here on the heatmapPerInput.
                -- set binary digit to 1 that corrensponds to index, so we can see which rules were applied where. other digits stay.
                --TODO WIP fix this - it should probably be per rewrite, not per rule.
                heatmapPerInput[y + suby - 1][x + subx - 1] = bit.bor(heatmapPerInput[y + suby - 1][x + subx - 1], bit.lshift(1, ruleIndex))
                heatmapPerCycle[y + suby - 1][x + subx - 1] = bit.bor(heatmapPerCycle[y + suby - 1][x + subx - 1], bit.lshift(1, ruleIndex))
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
        for y = 1, #heatmap do
            for x = 1, #heatmap[1] do
                local binary = heatmap[y][x]
                heatmap[y][x] = bit.band(binary, bit.bnot(bit.lshift(1, index)))
            end
        end
    end

    function findFirstOne(heatmapPerInput)
        for y = 1, #heatmapPerInput do
            for x = 1, #heatmapPerInput[1] do
                if heatmapPerInput[y][x] > 0 then
                    return x, y
                end
            end
        end
        return nil, nil
    end

    function findFirstChangedCell (heatmapPerInput, leftSpread, upSpread)
        -- changes start from the first cell that has heat.
        local firstChangedX, firstChangedY = findFirstOne(deepCopy(heatmapPerInput))
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
    local newBoard = shallowCopy(originalBoard) -- copy the before board to modify it

    -- initialize heatmaps. one is for the whole time, the other is for the last loop.
    -- the former is a nice visual representation of which rules were applied where.
    -- the latter is used to skip checking positions that didn't change since the last loop.
    if app.loopsSinceInput == 0 then
        heatmapPerInput = {}
        heatmapPerCycle = {}
        for y = 1, #newBoard do
            heatmapPerInput[y] = {}
            heatmapPerCycle[y] = {}
            for x = 1, #newBoard[1] do
                heatmapPerInput[y][x] = 0
                heatmapPerCycle[y][x] = 0
            end
        end
        print("   loop start. rewrites per turn:")
        io.write("<> ")
    end

    local totalHits = 0
    local totalMisses = 0
    for i, rule in ipairs(rules) do

        local rewrites = rule.rewrites
        local keywords = rule.keywords
        -- WIP TODO
        --local indexBeforeExpanding = rule.ruleIndex -- could use this to loop through group before the next
        
        local rewriteStats = {}
        for _, rewrite in ipairs(rewrites) do
            table.insert(rewriteStats, {
                hits = 0, 
                misses = 0,
                lastHitX = 1,
                lastHitY = 1,
            })
        end

        -- WIP: heatmap optimization
        -- not individual rewrites, but the whole rule. at least for now.
        if app.loopsSinceInput > 0 then
            -- in later loops, we can skip a bunch of looping by checking if there is some heat in the cell.
            -- if there isn't, then no rule applied since last time.
            -- for this to work, we need to turn off the heat for the rule we are about to apply.
            turnOffAllHeat(i, heatmapPerCycle)
            local maxWidthOfRewrites = 0 -- wip this doesn't make that much sense, would be better to do this per rewrite.
            local maxHeightOfRewrites = 0
            for _, rewrite in ipairs(rewrites) do
                maxWidthOfRewrites = math.max(maxWidthOfRewrites, rewrite.width)
                maxHeightOfRewrites = math.max(maxHeightOfRewrites, rewrite.height)
            end
            local minChangingX, minChangingY = findFirstChangedCell(heatmapPerCycle, maxWidthOfRewrites, maxHeightOfRewrites) or 1, 1
            for _, rewrite in ipairs(rewriteStats) do
                rewrite.lastHitX, rewrite.lastHitY = maxPointInReadingOrder(rewrite.lastHitX, rewrite.lastHitY, minChangingX, minChangingY)
            end
        end

        local moreMatchesPossible = matchesInitialConditions(keywords)
        if #rewrites == 0 then
            moreMatchesPossible = false
        end
        local allRewritesHadMatches = false
        while moreMatchesPossible do
            -- go through the left side of the rewrites.
            -- if the left side doesn't match, we don't need to check the rest of the rewrites.
            for r, rewrite in ipairs(rewrites) do
                if rewrite.left and rewrite.right and moreMatchesPossible then
                    local stats = rewriteStats[r]
                    if (stats.hits > 0 ) then
                        -- had a match already! this means all rewrites had a match.
                        allRewritesHadMatches = true
                    end

                    -- find a match
                    -- these matches are not exclusive, so a cell can be matched by multiple rewrites.
                    -- should we keep track of that? TODO
                    local x, y, misses = findFirstSubPattern(newBoard, rewrite.left, stats.lastHitX, stats.lastHitY, {x=1, y=1}) 
                    local misses = misses or 0
                    stats.misses = stats.misses + misses

                    if x and y then
                        -- found match. updating coordinates so the next time we start from the next cell.
                        stats.hits = stats.hits + 1
                        stats.lastHitX = x
                        stats.lastHitY = y
                    else
                        -- if we don't have a match for one of the rules, we don't need to check the rest of the rewrites.
                        moreMatchesPossible = false
                    end
                end
            end
            -- if we still have matches, apply the rewrites using the last coordinates.
            if moreMatchesPossible then
                for r, rewrite in ipairs(rewrites) do
                    local stats = rewriteStats[r]
                    if stats.hits > 0 then
                        local currentRuleIndex = i
                        replaceSubPattern(newBoard, rewrite.right, stats.lastHitX, stats.lastHitY, currentRuleIndex)
                        -- change coordinates for the next match.
                        -- need to find the last cell that has no overlap with the change we just made.
                        stats.lastHitX, stats.lastHitY = newStartCoordinate(stats.lastHitX, stats.lastHitY, rewrite.width, rewrite.height)
                    end
                end
            end
        end

        if allRewritesHadMatches then
            -- combine the stats for all rewrites of this rule.
            for r, rewrite in ipairs(rewrites) do
                local stats = rewriteStats[r]
                totalHits = totalHits + stats.hits
                totalMisses = totalMisses + stats.misses
            end
        end
    end

    -- reset properties that are only relevant for the current loop
    app.lastInputKey = nil -- reset the input key so we can check again next time

    -- replace the original board with the new one
    if totalHits > 0 then
        for y = 1, #newBoard do
            originalBoard[y] = newBoard[y]
        end
        io.write(totalHits .. " ")
        return true, totalHits, totalMisses
    end

    io.write(totalHits .. " ")
    print()

    return false, totalHits, totalMisses
end






-- use the board table to update the image data
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

function updateImagedata(imageData, boardTable)
    if app.viewingCode then
        -- TODO WIP, turn the rules data back into an image? would allow for some interesting visualizations.
        -- However it seems important to keep the color etc. as they were.
        -- Right now, the rule image can not be edited.
        return
    end
    local width = imageData:getWidth()
    local height = #boardTable

    for y=0, height-1 do
        local row = boardTable[y+1]
        for x=0, width-1 do
            if #heatmapPerCycle > 0 and app.viewingHeatmapForRule == -1 then
                local heatmapBinary = heatmapPerCycle[y+1][x+1]
                local digit = heatmapBinary > 0 and 0.3 + row[x+1] * 0.5 or row[x+1] 
                imageData:setPixel(x, y, digit, digit, digit, 1)
            elseif #heatmapPerInput > 0 and app.viewingHeatmapForRule > 0 then
                local heatmapBinary = heatmapPerInput[y+1][x+1]
                local digit = bit.band(bit.rshift(heatmapBinary, app.viewingHeatmapForRule), 1)
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
                -- increase randomness with loop count
                local randomness = math.min(app.loopsSinceInput * 0.002, 0.2)
                local noise = not (app.editing or app.paused or app.idle) and 1-randomness + love.math.random() * randomness or 1
                imageData:setPixel(x, y, 
                    color[1] * noise, 
                    color[2] * noise, 
                    color[3] * noise, 
                1)
            end
        end
    end
end