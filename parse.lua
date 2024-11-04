-- parse image data to return a new state table

function parseState(imageData)

    print("parsing image to set initial state...")

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

-- parse image data to return a list of rules

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