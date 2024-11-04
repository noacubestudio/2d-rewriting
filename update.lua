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
                    return i, j -- Return the first match position
                end
            end
        end
        return nil -- No match found
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

-- use the state table to update the image data
-- visual-only effects can be applied here

local palette = { 
    -- wip: changing the palette means the parser needs to be updated? 
    -- ideally should be able to change the palette without changing the parser
    -- but then reading back the image to parse again is not possible
    {0, 0, 0},
    {0.6, 0.9, 0.8}
}

function updateImagedata(imageData, rows)
    local width = imageData:getWidth()
    local height = #rows

    for y=0, height-1 do
        local row = rows[y+1]
        for x=0, width-1 do
            local color = palette[row[x+1]+1]
            imageData:setPixel(x, y, color[1], color[2], color[3], 1)
        end
    end
end