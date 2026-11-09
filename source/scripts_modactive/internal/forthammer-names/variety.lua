-- Presentation diversity only: this does not define Khazalid grammar or change
-- the uniform probability contract of core.generate/core.generate_batch.
--@ module = true
local appearance = {kol=true,zan=true,gorl=true,skarrenruf=true,bryn=true}

function key(candidate)
    local parts = {}
    for _,root in ipairs(candidate.roots) do
        if not appearance[root] then parts[#parts+1] = root end
    end
    return #parts > 0 and table.concat(parts,'/') or candidate.name
end

local function shuffle(items, random_index)
    for i=#items,2,-1 do
        local j = random_index(i)
        if type(j) ~= 'number' or j % 1 ~= 0 or j < 1 or j > i then
            return nil,'Random source returned an invalid index.'
        end
        items[i],items[j] = items[j],items[i]
    end
    return items
end

-- Each composition family gets a turn before any family repeats. Both family
-- order and variants are shuffled; callers retain ownership of their inputs.
function interleave(candidates, random_index)
    if type(random_index) ~= 'function' then return nil,'A random-index function is required.' end
    local groups, by_key = {}, {}
    for _,candidate in ipairs(candidates) do
        local k = key(candidate)
        if not by_key[k] then by_key[k] = {}; groups[#groups+1] = by_key[k] end
        local group = by_key[k]
        group[#group+1] = candidate
    end
    local _,err = shuffle(groups,random_index)
    if err then return nil,err end
    for _,group in ipairs(groups) do
        _,err = shuffle(group,random_index)
        if err then return nil,err end
    end
    local result, round, active = {}, 1, true
    while active do
        active = false
        for _,group in ipairs(groups) do
            if group[round] then result[#result+1] = group[round]; active = true end
        end
        round = round+1
    end
    return result
end
