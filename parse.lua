-- parse image data to return a new state table

function parseBoardImage(imageData)

    io.write("parsing board image, ")

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


-- parse macro image data to return a list of builtin symbols to be used in the rules.
-- each row corresponds to a symbol name. the symbols are parsed as 2D tables of 1s and 0s.

local function getIOSymbol(index)
    local options = {"load", "save", "up", "right", "down", "left", "loop"}
    return options[index]
end

function parseMacrosImage(imageData)
    
    local height = imageData:getHeight()
    local width = imageData:getWidth()
    print("parsing symbol image, " .. width .. "x" .. height)
    print()

    local symbols = {}
    local currentSymbol = nil
    for y=0, height-1 do
        local row = {}
        for x=0, width-1 do
            local r, g, b, a = imageData:getPixel(x, y)
            local pixel = a > 0 and parseColor(r, g, b) or nil
            if pixel ~= nil then
                table.insert(row, pixel)
            end
        end

        if #row > 0 then
            if currentSymbol == nil then
                currentSymbol = {}
            end
            table.insert(currentSymbol, row)
        elseif currentSymbol ~= nil then
            table.insert(symbols, currentSymbol)
            currentSymbol = nil
        end
    end

    --print("   found " .. #symbols .. " symbols.")
    --print()
    --printPatternsSideBySide(symbols)

    -- turn the symbols into names
    local macros = {
        rotate = symbols[1] or nil,
        flipH  = symbols[2] or nil,
        flipV  = symbols[3] or nil,
        grid   = symbols[4] or nil,
    }
    -- print which are not nil
    io.write("   macros: ")
    for keyword, symbol in pairs(macros) do
        if symbol then
            io.write(keyword, "(", #symbol, "x", #symbol[1], ") ")
        end
    end
    print()
    print()
    return macros
end


-- parsing rules

-- parse image data to return a list of rules

-- each parsed rule contains patterns and keywords like: 
-- {
--   { {0, 1, nil}, {1, 1, 1}, {0, 1, 0} }, -- before
--   { {1, 0, 1}, {0, 0, nil}, {1, 0, 1} }, -- after, option 1
--   { {0, 1, nil}, {1, 1, 0}, {0, 1, 0} }, -- after, option 2 ... etc
--   ';',                                   -- &
--   { {1, 1, 1}, {1, 1, 1}, {1, 1, 1} },   -- before 
--   { {1, 1, 1}, {1, 1, 1}, {1, 1, 1} },   -- after, option 1 ... etc
-- }
-- some keywords are already applied to the rules, like rotation, mirroring, etc., creating more rules.

function parseRulesImage(rulesData, symbolData)
    
    local parsingIO = not symbolData
    local imageData = rulesData.imagedata
    local height = rulesData.height
    local width = rulesData.width
    print((parsingIO and "parsing io rules, " or "parsing rules image, ") .. width .. "x" .. height)
    print()

    -- go down the image and find where rules start and stop. 
    -- rows that don't have b/w pixels separate rules.

    local rowPositions = {}
    local rowHeights = {}

    local lastRowWasEmpty = true
    for y=0, height-1 do
        
        local rowIsEmpty = true
        local x = 0
        while rowIsEmpty and x < width-1 do
            local r, g, b, a = imageData:getPixel(x, y)
            local pixel = a > 0 and parseColor(r, g, b) or nil
            if pixel ~= nil then
                rowIsEmpty = false
            end
            x = x + 1
        end
        if not rowIsEmpty and lastRowWasEmpty then
            table.insert(rowPositions, y) -- a rule starts here
        elseif rowIsEmpty and not lastRowWasEmpty then
            table.insert(rowHeights, y - rowPositions[#rowPositions]) -- a rule ends here
        end
        lastRowWasEmpty = rowIsEmpty
    end

    print("   found " .. #rowPositions .. " rules.")
    print()

    -- for each rule, collect patterns as 2D tables.
    -- if the dimensions of a finished pattern does not match the previous one, add the ';' keyword in the list first.
    -- that indicates that a separate rewrite or keyword is following it.

    local rules = {}
    for i, rowStart in ipairs(rowPositions) do
        local rowEnd = rowStart + rowHeights[i]
        local rule = {}
        
        -- go through line horizontally (check each column) and collect patterns
        local currentPattern = {}
        local currentPatternWidth = 0
        local currentPatternHeight = 0
        local lastPatternWidth = 0
        local lastPatternHeight = 0
        for x=0, width-1 do
            local currentColumn = {}
            for y=rowStart, rowEnd do
                local r, g, b, a = imageData:getPixel(x, y)
                local pixel = a > 0 and parseColor(r, g, b) or nil

                if pixel ~= nil then
                    table.insert(currentColumn, pixel)
                end
            end

            -- the column can either start a new pattern, get added to the current pattern, or end the current pattern.

            if #currentColumn > 0 then
                -- add column to the current pattern.
                table.insert(currentPattern, currentColumn)
                currentPatternWidth = currentPatternWidth + 1
                currentPatternHeight = math.max(currentPatternHeight, #currentColumn)

            elseif #currentPattern > 0 then
                -- reached an empty column, complete the current pattern.

                -- new size, so add ';' keyword
                local differentSize = currentPatternWidth ~= lastPatternWidth or currentPatternHeight ~= lastPatternHeight
                if #rule > 0 and differentSize then
                    table.insert(rule, ';')
                end

                -- add pattern to the rule
                local finalPattern = swapAxes(currentPattern) -- swap axes so the table contains rows
                table.insert(rule, finalPattern) 
                
                -- prepare for the next pattern
                lastPatternWidth, lastPatternHeight = currentPatternWidth, currentPatternHeight
                currentPattern = {}
                currentPatternWidth, currentPatternHeight = 0, 0
            end
        end

        -- add the rule to the list.
        table.insert(rules, rule)
    end


    -- recursively expand the rules
    -- this function is used below, which really should be swapped in order for clarity, but lua won't let me do that.

    -- go through a rule from left to right, looking for the word 'symbol' and the pattern that follows it.
    -- some symbols get added to the rule as a string, others directly modify the rest of the rule, e.g. rotate the patterns.
    -- this also applies to following symbols themselves, which might be rotated or mirrored before being parsed.
    -- builtin keywords expand the rules to all specified combinations, so this creates new rules.

    local function expandRule(ruleBefore, originalIndex)

        -- convert individual patterns to symbols if they match the builtin list of symbols.

        local function parseSymbol(pattern, symbolData)
            local symbol = nil
            local width = #pattern[1]
            local height = #pattern

            -- builtin symbols
            for keyword, symbolPattern in pairs(symbolData) do
                if #symbolPattern[1] == width and #symbolPattern == height then
                    local match = true
                    for y = 1, height do
                        for x = 1, width do
                            if symbolPattern[y][x] ~= pattern[y][x] and symbolPattern[y][x] ~= -1 then
                                match = false
                                break
                            end
                        end
                        if not match then break end
                    end
                    if match then
                        symbol = keyword
                        break
                    end
                end
            end
            return symbol -- nil if not a known symbol
        end
        
        -- what to do with the rest of the rule after a symbol is found.
        -- after both the keyword and the remaining pattern are passed to the function, the 'symbol' <pattern> can be removed.

        local function isModifier(symbol)
            return symbol == "rotate" or symbol == "flipV" or symbol == "flipH"
        end

        local function modifyRestOfRule(rest, modifier)
            if modifier == "rotate" then
                return {
                    rest,
                    rotateAllPatterns(rest),
                    rotateAllPatterns(rotateAllPatterns(rest)),
                    rotateAllPatterns(rotateAllPatterns(rotateAllPatterns(rest)))
                }
            elseif modifier == "flipV" then
                return {
                    rest,
                    flipAllPatterns(rest, false)
                }
            elseif modifier == "flipH" then
                return {
                    rest,
                    flipAllPatterns(rest, true)
                }
            end
        end

        if #ruleBefore == 0 then
            return {}
        end
        local rule = deepCopy(ruleBefore)

        -- find next word 'symbol' in the rule
        local symbolIndex = nil
        for i=1, #rule do
            if rule[i] == 'symbol' then
                table.remove(rule, i) -- remove the word 'symbol'
                symbolIndex = i -- index of the actual symbol pattern that follows
                break
            end
        end

        if not symbolIndex then
            return {rule} -- no symbol found, return the rule as is.
        end

        -- if a symbol was found, parse it and optionally modify the rest of the rule.
        local expandedRules = {}
        local parsedSymbol = parseSymbol(rule[symbolIndex], symbolData)

        -- now, three cases:
        -- 1. symbol is not recognized (nil): it is removed and the rest of the rule is processed.
        -- 2. symbol is recognized but not a modifier, so the symbol is left in the rule.
        -- 3. symbol is recognized and a modifier, so the rest of the rule is modified by the symbol.

        if not parsedSymbol then
            -- 1. not parsed, remove the symbol from the rule and process the rest.
            table.remove(rule, symbolIndex)
            expandedRules = expandRule(rule)
        else 
            --print("   found symbol: " .. parsedSymbol)
            if isModifier(parsedSymbol) then
                -- 3. modify remaining part of the rule, remove the symbol itself
                local base, rest = {}, {}
                for j = 1, #rule do
                    if j < symbolIndex then
                        table.insert(base, rule[j])
                    elseif j > symbolIndex then
                        table.insert(rest, rule[j])
                    end
                end
                local createdVariants = modifyRestOfRule(rest, parsedSymbol)
                for _, variant in ipairs(createdVariants) do
                    local newRule = deepCopy(base)
                    for _, part in ipairs(variant) do
                        table.insert(newRule, part)
                    end
                    local expanded = expandRule(newRule)
                    for _, newRule in ipairs(expanded) do
                        table.insert(expandedRules, newRule)
                    end
                end
            else
                -- 2. symbol is not a modifier, replace with the parsed version and add separator behind.
                rule[symbolIndex] = parsedSymbol
                table.insert(rule, symbolIndex + 1, ";") 
                expandedRules = expandRule(rule) -- keep looking for more symbols
            end
        end

        return #expandedRules > 0 and expandedRules or {rule} -- no more changes, return the rule as is.
    end

    local function prepareRuleForApplication(rule, ruleIndex)
        -- final steps.
        local finalRule = {
            rewrites = {}, -- left and right sides of the rule
            keywords = {},
            ruleIndex = ruleIndex,
            command = nil
        }

        if parsingIO then
            -- add the io keyword
            finalRule.command = getIOSymbol(ruleIndex)
            print("   rule " .. ruleIndex .. " has io keyword " .. getIOSymbol(ruleIndex))
        end
        
        local currentRewrite = {left = nil, right = {}}
        for j, part in ipairs(rule) do
            
            if type(part) == "table" and j == #rule then
                -- insert last table
                table.insert(currentRewrite.right, part)
                table.insert(finalRule.rewrites, {
                    left = currentRewrite.left, 
                    right = shallowCopy(currentRewrite.right),
                    width = #currentRewrite.left[1],
                    height = #currentRewrite.left
                })
            elseif part == ';' and #currentRewrite.right > 0 then
                -- is actually long enough to be a rewrite
                table.insert(finalRule.rewrites, {
                    left = currentRewrite.left, 
                    right = shallowCopy(currentRewrite.right),
                    width = #currentRewrite.left[1],
                    height = #currentRewrite.left
                })
                currentRewrite = {left = nil, right = {}}
            elseif type(part) == "table" then
                if currentRewrite.left == nil then
                    currentRewrite.left = part
                else
                    table.insert(currentRewrite.right, part)
                end
            elseif type(part) == "string" then
                table.insert(finalRule.keywords, part)
            end
        end

        --print("   rule " .. ruleIndex .. " has " .. #finalRule.rewrites .. " rewrites.")
        return finalRule
    end
    

    -- so far, the only keyword that is already a string is ';', which separates different rewrite rules.
    -- everything else is 2D tables of 1s and 0s (and wildcards with -1)

    -- the word 'symbol' is added before a pattern that is a symbol, so that the function knows to process it.
    -- example of the rules as processed by the next loop:
    
    -- symbol  []$$  . . . . . . . . $$$$$$$$$$. .   . . . . . . . . $$$$$$$$$$. .   ;  symbol  []  [][]$$$$$$[][]  [][]$$$$$$[][]
    --         $$[]  . . . . . . . . $$[][][]$$$$.   . . . . . . [][][]$$$$$$$$$$.                  [][]$$[]$$[][]  [][]$$[]$$[][]
    --               . . . . . . . . $$[]$$$$[]$$$$  . . . . . []$$$$[]$$$$$$$$$$$$                 $$$$$$[]$$$$$$  $$$$$$[]$$$$$$
    --               . . . . . . . . [][][]$$[]$$$$  . . . . []$$$$[][][][][]$$$$$$                 $$$$[][][][]$$  $$[][][][][]$$
    --               . . . . . . . . $$[]$$$$[]$$$$  . . . . . []$$$$[]$$$$$$$$$$$$                 $$$$$$[]$$$$$$  $$$$$$[]$$$$$$
    --               . . . . . . . . $$[][][]$$$$.   . . . . . . [][][]$$$$$$$$$$.                  [][]$$[]$$[][]  [][]$$[]$$[][]
    --               . . . . . . . . $$$$$$$$$$. .   . . . . . . . . $$$$$$$$$$. .                  [][]$$$$$$[][]  [][]$$$$$$[][]
    
    -- each rule ultimately is expanded to include all possible results of the special keywords, like rotation, mirroring, etc.
    -- the function expandRule is called recursively to expand the rules.

    local expandedRules = {}
    for i, rule in ipairs(rules) do

        -- first, find out which patterns are symbols. add the string 'symbol' before the pattern.
        local patternCountSinceLastWord = 0
        local currentRule = {}
        for j, symbol in ipairs(rule) do
            if type(symbol) == "table" then
                patternCountSinceLastWord = patternCountSinceLastWord + 1
                if j == #rule and patternCountSinceLastWord == 1 then
                    -- last pattern is a symbol
                    table.insert(currentRule, 'symbol')
                    table.insert(currentRule, symbol)
                else 
                    -- add as regular pattern
                    table.insert(currentRule, symbol)
                end
            elseif symbol == ';' then
                if patternCountSinceLastWord <= 1 then
                    -- last pattern is a symbol
                    -- remove the pattern and replace it with the symbol
                    -- get last
                    local lastPattern = currentRule[#currentRule]
                    table.remove(currentRule)
                    table.insert(currentRule, 'symbol')
                    table.insert(currentRule, lastPattern)
                else 
                    table.insert(currentRule, ';')
                end
                patternCountSinceLastWord = 0
            end
        end
        
        -- expand the rule using the function. this is finally where the keywords are processed.

        --printPatternsSideBySide(currentRule)
        local originalIndex = i
        local newRules = expandRule(currentRule, originalIndex)

        for _, expandedRule in ipairs(newRules) do
            -- trim ';' from the end if present
            if expandedRule[#expandedRule] == ';' then
                table.remove(expandedRule)
            end
            if app.settings.logRules then printPatternsSideBySide(expandedRule) end
            local finalRule = prepareRuleForApplication(expandedRule, i)
            table.insert(expandedRules, finalRule)
        end
    end


    -- done! print some stats and return the rules.
    print("   parsed " .. #rules .. " rules, expanded to " .. #expandedRules .. " rules.")
    print()
    return expandedRules
end

function parseColor(r, g, b)
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

function rotateAllPatterns(rule) -- doesn't require deep copy, apparently
    local newRule = {}
    local symmetrical = true
    for i, part in ipairs(rule) do
        if type(part) == "string" then
            table.insert(newRule, part)
        else
            local result = rotatePattern(part)
            if result == nil then
                table.insert(newRule, part)
            else
                table.insert(newRule, result)
                symmetrical = false
            end
        end
    end
    return newRule
end

function flipAllPatterns(rule, isH)
    local newRule = {}
    for i, part in ipairs(rule) do
        if type(part) == "string" then
            table.insert(newRule, part)
        else
            table.insert(newRule, flipPattern(part, isH))
        end
    end
    return newRule
end