local pprint = require('pprint')

-- update board and output image data

-- WIP TODO: fix the heatmap display
-- WIP TODO: on key input, only check rules that match on the input, but recurse each with allowing any partial overlap.
-- WIP TODO: on mouse input, only check in the area as provided, but allowing any partial overlap.
-- WIP TODO: on following turns more generally, we can skip checking the whole board and only check the changed cells?

local function setHeat(boardData, x, y, rulesetIndex, ruleIndex)
    boardData.heatmap[rulesetIndex] = boardData.heatmap[rulesetIndex] or {}
    boardData.heatmap[rulesetIndex][ruleIndex] = boardData.heatmap[rulesetIndex][ruleIndex] or {}
    local heatmap = boardData.heatmap[rulesetIndex][ruleIndex]
    heatmap[y] = heatmap[y] or {}
    heatmap[y][x] = heatmap[y][x] or 0
    heatmap[y][x] = heatmap[y][x] + 1
    --pprint("set heatmap for rule " .. ruleIndex .. " at " .. x .. ", " .. y, heatmap)
end

local function getHeat(heatmap, x, y)
    if not heatmap[y] then return 0 end
    return heatmap[y][x] or 0
end

local function getHeatmap(boardData, rulesetIndex, ruleIndex)
    local heatmap = boardData.heatmap or {}
    if not heatmap[rulesetIndex] or not heatmap[rulesetIndex][ruleIndex] then
        return {}
    end
    --print("found heatmap for rule " .. ruleIndex .. " with" .. #heatmap[rulesetIndex][ruleIndex])
    --pprint("heatmap for rule " .. ruleIndex, heatmap[rulesetIndex][ruleIndex])
    return heatmap[rulesetIndex][ruleIndex]
end

-- todo: also compare to right side. if identical, do not consider the pattern a match.
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

local function findFirstMatch(board, rewrite, bounds, skipToIndex)-- heatmap)
    local startX, startY, endX, endY = bounds.x1, bounds.y1, bounds.x2, bounds.y2
    local totalChecks = 0
    local max = (endX - startX + 1) * (endY - startY + 1)
    for i = skipToIndex or 1, max do
        totalChecks = totalChecks + 1
        local x = startX + (i - 1) % (endX - startX + 1)
        local y = startY + math.floor((i - 1) / (endX - startX + 1))
        --local matchedBefore = getHeat(heatmap, x, y) > 0
        --if not matchedBefore then
            local match = checkMatch(board, rewrite.left, x, y, rewrite.width, rewrite.height)
            if match then
                return x, y, totalChecks
            end
        --end
    end
    return nil, nil, totalChecks -- out of bounds, no match
end

local function applyRewrite(board, rewrite, match)
    local newPattern = rewrite.right[love.math.random(1, #rewrite.right)]
    local madeChange = false
    for y = 1, rewrite.height do
        for x = 1, rewrite.width do
            if newPattern[y][x] >= 0 then
                madeChange = board[match.y + y - 1][match.x + x - 1] ~= newPattern[y][x] or madeChange
                board[match.y + y - 1][match.x + x - 1] = newPattern[y][x]
            end
        end
    end
    return madeChange
end

local function updateBoard(boardData, rulesets)
    local newBoard = shallowCopy(boardData.table)
    local boardWidth = #newBoard[1]
    local boardHeight = #newBoard

    if app.input.totalLoops == 0 then
        io.write("<> ")
    end

    function recursiveCheck(rulesetIndex, rules, ruleCount, changedX, changedY, changedX2, changedY2, maxDimensions, depth)
        local depth = depth or 1
        local expandTopLeft = depth > 1
        local expandBottomRight = false -- not implemented yet and usually not necessary
        local totalMatches = 0
        local totalChecks = 0

        for r = 1, ruleCount do -- apply rules until rule n.
            local rule = rules[r]
            local expectedMatches = #rule.rewrites -- if each rewrite in the rule has a match, we can apply them all.
            if expectedMatches == 0 then
                print("error: rule " .. r .. " has no rewrites.")
                return nil, nil
            end
            -- walk through the board, moving windows the size of the rewrites.
            -- every time all can find new matches, apply them and recurse, then continue.
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
                    if b.x1 > b.x2 or b.y1 > b.y2 then
                        searching = false
                        break
                    end
                    --local repeatedRule = depth > 1 and r == ruleCount
                    --local heatmap = getHeatmap(boardData, rulesetIndex, r)
                    local foundX, foundY, checks = findFirstMatch(newBoard, rewrite, b, windows[re]) --heatmap)
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
                        -- make sure the pattern is even different from the original while trying to apply it
                        local madeChange = applyRewrite(newBoard, rewrite, match)
                        if depth > 128 then
                            io.write("max depth. ")
                        elseif madeChange then
                            --if boardData.heatmap then setHeat(boardData, match.x, match.y, rulesetIndex, r) end
                            local matches, checks = recursiveCheck(
                                rulesetIndex, rules, r, 
                                match.x, match.y,
                                match.x + rewrite.width - 1, match.y + rewrite.height - 1, 
                                maxDimensions,
                                depth + 1
                            )
                            -- after recursion
                            totalMatches = totalMatches + matches + 1
                            totalChecks = totalChecks + checks
                        else 
                            --io.write("no change. ")
                            --return totalMatches, totalChecks
                        end
                    end
                else
                    --io.write("no match. ")
                    break
                end
            end
        end
        depth = depth - 1
        return totalMatches, totalChecks
    end

    local maxDimensions = {x1 = 1, y1 = 1, x2 = boardWidth, y2 = boardHeight}

    -- start at depth 1, which considers the dimensions as absolute.
    -- inner levels cover the area that each rewrite shares with the dimensions.
    local matches, checks = 0, 0
    for setI, rules in ipairs(rulesets) do
        newMatches, newChecks = recursiveCheck(setI, rules, #rules, 1, 1, boardWidth, boardHeight, maxDimensions, 1)
        io.write(newMatches, "/", newChecks, " ")
        matches = matches + newMatches
        checks = checks + newChecks
    end

    --pprint(boardData.heatmap)

    -- update the board
    boardData.table = newBoard
    return matches, checks - matches
end

function applyCommandToBoard(boardData, rules, ioRules, command)
    -- if #ioRules == 0 then
    --     print("no io rules")
    --     return 0, 0
    -- end
    
    local rulesets = {{}, rules}

    -- find all rules that match the command
    for i, rule in ipairs(ioRules) do
        if rule.command == command then
            table.insert(rulesets[1], rule)
        end
    end

    if #rulesets[1] == 0 then
        return 0, 0
    end
    print()
    print("applying command " .. command .. " with " .. #rulesets[1] .. " rules")
    print("then applying " .. #rules .. " rules")

    local matches, misses = updateBoard(boardData, rulesets)
    return matches, misses
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