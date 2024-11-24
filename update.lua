-- update board and output image data

-- WIP TODO: fix the heatmap display
-- WIP TODO: on key input, only check rules that match on the input, but recurse each with allowing any partial overlap.
-- WIP TODO: on mouse input, only check in the area as provided, but allowing any partial overlap.
-- WIP TODO: on following turns more generally, we can skip checking the whole board and only check the changed cells?

local function checkMatch(board, pattern, startX, startY, width, height)
    local endX = startX + width - 1
    local endY = startY + height - 1
    for y = startY, endY do
        for x = startX, endX do
            local p = pattern[y - startY + 1][x - startX + 1]
            if board[y][x] ~= p and p >= 0 then
                return false
            end
        end
    end
    return true
end

local function checkConditions(rule)
    for _, keyword in ipairs(rule.keywords) do
        if string.find(keyword, "input_") then
            local directionKey = string.sub(keyword, 7)
            if app.input.key ~= directionKey then
                return false
            end
        end
    end
    return true
end

local function findFirstMatch(board, rewrite, startX, startY, endX, endY, skipToIndex, repeatedRule)
    -- note: if a repeated rule, we can't check the final cell
    local totalChecks = 0
    local max = (endX - startX + 1) * (endY - startY + 1) - (repeatedRule and 1 or 0)
    --io.write(skipToIndex, " to ", max, " ")

    for i = skipToIndex or 1, max do
        totalChecks = totalChecks + 1
        local x = startX + (i - 1) % (endX - startX + 1)
        local y = startY + math.floor((i - 1) / (endX - startX + 1))
        local match = checkMatch(board, rewrite.left, x, y, rewrite.width, rewrite.height)
        if match then
            return x, y, totalChecks
        end
    end
    return nil, nil, totalChecks -- out of bounds, no match
end

local function applyRewrite(board, rewrite, match)
    local newPattern = rewrite.right[love.math.random(1, #rewrite.right)]
    for y = 1, rewrite.height do
        for x = 1, rewrite.width do
            if newPattern[y][x] >= 0 then
                board[match.y + y - 1][match.x + x - 1] = newPattern[y][x]
            end
        end
    end
end

function updateBoardNew(boardData, rules)

    local newBoard = shallowCopy(boardData.table)
    local boardWidth = #newBoard[1]
    local boardHeight = #newBoard

    if app.input.totalLoops == 0 then
        print("   loop start. rewrites per turn:")
        io.write("<> ")
    end

    function recursiveCheck(rules, ruleCount, changedX, changedY, changedX2, changedY2, maxDimensions, depth)
        local depth = depth or 1
        local expandTopLeft = depth > 1
        local expandBottomRight = false -- not implemented yet and usually not necessary
        local totalMatches = 0
        local totalChecks = 0
    
        --print("")
        --io.write(string.rep(" ", depth * 3), "check ", ruleCount, " rules for (", changedX, ",", changedY, ") to (", changedX2, ",", changedY2, ") ")
    
        for r = 1, ruleCount do -- apply rules until rule n.
            local rule = rules[r]
            local expectedMatches = #rule.rewrites -- if each rewrite in the rule has a match, we can apply them all.
            if expectedMatches == 0 then
                print("error: rule " .. r .. " has no rewrites.")
                return nil, nil
            end
    
            -- walk through the board, moving windows the size of the rewrites.
            -- every time all can find new matches, apply them and recurse, then continue.
            --print("")
            --io.write(string.rep(" ", depth * 3),"r ", r,  "? ")
            local windows = {} -- current subgrid index each rewrite has searched
            local bounds  = {} -- boundaries the index can move within
            local searching = checkConditions(rule) -- end if no more matches can be found for any rewrite
            while searching do
                
                local collectedMatches = {}
                for re, rewrite in ipairs(rule.rewrites) do
                    -- expand area to search by the dimensions of the rewrite - 1, but always keep within maxDimensions.
                    bounds[re] = bounds[re] or {   -- in these bounds
                        x1 = math.max(expandTopLeft and changedX - rewrite.width  + 1 or changedX, maxDimensions.x1),
                        y1 = math.max(expandTopLeft and changedY - rewrite.height + 1 or changedY, maxDimensions.y1),
                        x2 = math.min(expandBottomRight and changedX2 or (changedX2 - rewrite.width  + 1), maxDimensions.x2),
                        y2 = math.min(expandBottomRight and changedY2 or (changedY2 - rewrite.height + 1), maxDimensions.y2),
                    }
                    windows[re] = windows[re] or 1 -- last match index
                    local b = bounds[re]
                    --o.write("search in bounds (", b.x1, ",", b.y1, " to ", b.x2, ",", b.y2, ") ")
                    if b.x1 > b.x2 or b.y1 > b.y2 then
                        searching = false
                        break
                    end
                    local repeatedRule = depth > 1 and r == ruleCount
                    --if re > 1 then io.write("->", re, "? ") end--" (", b.x1, ", ", b.y1, " to ", b.x2, ", ", b.y2, ") >= ", windows[re], "? ")
                    local foundX, foundY, checks = findFirstMatch(newBoard, rewrite, b.x1, b.y1, b.x2, b.y2, windows[re], repeatedRule)
                    totalChecks = totalChecks + checks
                    if foundX then
                        local rows = b.y2 - b.y1 + 1
                        local foundIndex = (foundY - b.y1) * (b.x2 - b.x1 + 1) + (foundX - b.x1)
                        table.insert(collectedMatches, {x = foundX, y = foundY})
                        --io.write(" found r ", r,  "(", foundX, ",", foundY, ") at i=", foundIndex, " in bounds (", b.x1, ",", b.y1, " to ", b.x2, ",", b.y2, ") ")
                        windows[re] = foundIndex + 1
                    else
                        searching = false
                        break
                    end
                end
                --print("")
                if #collectedMatches == expectedMatches then
                    for m, match in ipairs(collectedMatches) do
                        local rewrite = rule.rewrites[m]
                        applyRewrite(newBoard, rewrite, match)
                        local matches, checks = recursiveCheck(
                            rules, r, 
                            match.x, match.y,
                            match.x + rewrite.width - 1, match.y + rewrite.height - 1, 
                            maxDimensions,
                            depth + 1
                        )
                        -- after recursion
                        --io.write(string.rep(" ", depth * 3),"--",r,"? ")
                        totalMatches = totalMatches + matches + 1
                        totalChecks = totalChecks + checks
                    end
                else
                    --io.write("no match. ")
                    break
                end
            end
        end
        --print("")
        depth = depth - 1
        --print(string.rep(" ", depth * 3).."   end")
        return totalMatches, totalChecks
    end

    local maxDimensions = {x1 = 1, y1 = 1, x2 = boardWidth, y2 = boardHeight}
    --local checkDimensions = {x1 = 1, y1 = 1, x2 = boardWidth, y2 = boardHeight}

    -- start at depth 1, which considers the dimensions as absolute.
    -- inner levels cover the area that each rewrite shares with the dimensions.
    local matches, checks = recursiveCheck(rules, #rules, 1, 1, boardWidth, boardHeight, maxDimensions, 1)


    -- update the board
    boardData.table = newBoard

    io.write(matches, "/", checks, " ")
    return matches, checks - matches
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

function updateImagedata(imageData, boardData)
    if app.viewingCode then
        -- TODO WIP, turn the rules data back into an image? would allow for some interesting visualizations.
        -- However it seems important to keep the color etc. as they were.
        -- Right now, the rule image can not be edited.
        return
    end
    local boardTable = boardData.table
    local width = imageData:getWidth()
    local height = #boardTable
    local heatmapPerCycle = boardData.lastChanges or {}
    local heatmapPerInput = boardData.heatmap or {}
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
                local randomness = math.min(app.input.totalLoops * 0.002, 0.2)
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