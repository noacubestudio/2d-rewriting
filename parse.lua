-- parse image data to return a new state table

function parseState(imageData)

    io.write("parsing state image, ")

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

    print(#rows .. "x" .. #rows[1])
    return rows
end

-- parse image data to return a list of rules
-- each rule contains patterns and keywords like: 
-- {
--   { {0, 1, nil}, {1, 1, 1}, {0, 1, 0} }, -- before
--   { {1, 0, 1}, {0, 0, nil}, {1, 0, 1} }, -- after, option 1
--   { {0, 1, nil}, {1, 1, 0}, {0, 1, 0} }, -- after, option 2 ... etc
--   'and',                                 -- &
--   { {1, 1, 1}, {1, 1, 1}, {1, 1, 1} },   -- before 
--   { {1, 1, 1}, {1, 1, 1}, {1, 1, 1} },   -- after, option 1 ... etc
-- }

function getRotatedRules(rotateCount, originalRules)
    local rotatedRules = {}
    if rotateCount == 0 then
        return originalRules -- note that this is a shallow copy
    end
    for i, rule in ipairs(originalRules) do
        rotatedRules[i] = rotateAllPatterns(rule)
        for _ = 1, rotateCount - 1 do
            rotatedRules[i] = rotateAllPatterns(rotatedRules[i]) -- do repeatedly
        end
    end
    return rotatedRules
end

function rotateAllPatterns(rule)
    local newRule = {}
    local symmetrical = true
    for i, pattern in ipairs(rule) do
        newRule[i] = rotatePattern(pattern)
        if newRule[i] == nil then
            newRule[i] = pattern -- reset
        else
            symmetrical = false
        end
    end
    return newRule
end

function parseRules(imageData)
    
    local function parseColor(r, g, b)
        if r == 0 and g == 0 and b == 0 then -- black pixel
            return 0 
        elseif r == 1 and g == 1 and b == 1 then -- white pixel
            return 1 
        elseif r == g and g == b then -- gray pixel
            return -1 -- wildcard
        else
            return nil
        end
    end

    local height = imageData:getHeight()
    local width = imageData:getWidth()
    print("parsing rules image, " .. width .. "x" .. height)

    -- go down the image and collect rules
    -- rules contain 2d arrays of numbers representing black and white pixels / the changing pixels
    -- the first array is the left side of the rule, the following are options for the right side
    local rules = {}
    local currentRulePatterns = {}
    local lastRowEmpty = true
    for y=0, height-1 do

        -- go through row and collect pixels into sections separated by empty pixels
        local rowSections = {}
        local lastPixelEmpty = true
        for x=0, width-1 do
            local r, g, b, a = imageData:getPixel(x, y)
            local pixel = parseColor(r, g, b, a)

            if pixel ~= nil then
                if lastPixelEmpty then
                    table.insert(rowSections, {}) -- new section
                end

                -- add pixel to the current section
                local toPattern = rowSections[#rowSections]
                toPattern = table.insert(toPattern, pixel)
            end
            lastPixelEmpty = pixel == nil
        end

        if #rowSections > 0 then
            if lastRowEmpty then
                -- new rule
                currentRulePatterns = {}
                for i, section in ipairs(rowSections) do
                    table.insert(currentRulePatterns, {}) -- establish number of sections to match row
                end
                io.write("(1 -> " .. #currentRulePatterns - 1 .. ") ")
            end
            -- add the row sections to the patterns
            for i, section in ipairs(rowSections) do
                table.insert(currentRulePatterns[i], section)
            end
        else
            -- reached an empty row, so we complete the rule
            if not lastRowEmpty then
                rotations = { currentRulePatterns }
                for i = 1, 3 do
                    -- add 3 more rotations unless it's entirely symmetrical
                    local result = rotateAllPatterns(rotations[#rotations])
                    if result then table.insert(rotations, rotateAllPatterns(rotations[#rotations])) end
                end
                print("-------- " .. #rotations)
                for _, rule in ipairs(rotations) do
                    table.insert(rules, rule)
                    printPatternsSideBySide(rule)
                    print()
                end
            end
        end
        lastRowEmpty = #rowSections == 0
    end

    print("parsed " .. #rules .. " rules.")
    print()
    return rules
end