-- Resolve type-specific selectors without touching global language tables.
--@ module = true
local data = reqscript('internal/forthammer-names/data').data

function entity()
    if not dfhack.isWorldLoaded() then return end
    local active = false
    for _,mod in ipairs(require('script-manager').get_active_mods()) do
        if mod.id == 'ForthammerLocal' then active = true end
    end
    if not active then return end
    for _,raw in ipairs(df.global.world.raws.entities.all) do
        if raw.code == 'MOUNTAIN' and raw.translation == 'FORTHAMMER_KHAZALID' then return raw end
    end
end

function resolve(category)
    local definition = data.native_pools and data.native_pools[category]
    if not definition then return nil, 'No reviewed pool for '..tostring(category) end
    if #definition ~= 6 then return nil, 'Incomplete naming pool.' end
    local indices = {}
    for i,word in ipairs(df.global.world.raws.language.words) do indices[word.word] = i end
    local slots = {}
    for slot,tokens in ipairs(definition) do
        slots[slot] = {}
        for _,token in ipairs(tokens) do
            -- -1 is DF's absent-name-component sentinel, not a word index.
            -- Keep its selector nonempty so native generation never falls back
            -- to an arbitrary word. No other numeric token is accepted.
            local index = token == -1 and -1 or type(token) == 'string' and indices[token]
            if index == nil or index == false then return nil, 'This world lacks the expanded naming raws.' end
            slots[slot][#slots[slot]+1] = {index=index,part=df.part_of_speech.Noun}
        end
        if #slots[slot] == 0 then return nil, 'Incomplete naming pool.' end
    end
    return slots
end

local function read(selector)
    local slots = {}
    for slot=0,5 do
        slots[slot+1] = {}
        for i,index in ipairs(selector.words[slot]) do
            slots[slot+1][#slots[slot+1]+1] = {index=index,part=selector.parts[slot][i]}
        end
    end
    return slots
end

function write(selector, slots)
    for slot=0,5 do
        selector.words[slot]:resize(0)
        selector.parts[slot]:resize(0)
        for _,entry in ipairs(slots[slot+1]) do
            selector.words[slot]:insert('#',entry.index)
            selector.parts[slot]:insert('#',entry.part)
        end
    end
end

-- Synchronous scope only: never leave squad vocabulary installed between ticks.
function with_type(category, callback)
    local raw = entity()
    local slots, err = resolve(category)
    if not raw or not slots then return false, err or 'No eligible naming world.' end
    local major,minor = raw.symbols.symbols_major[df.entity_name_type.OTHER], raw.symbols.symbols_minor[df.entity_name_type.OTHER]
    local before_major,before_minor = read(major),read(minor)
    local result = table.pack(xpcall(function()
        write(major,slots); write(minor,slots)
        return callback()
    end,debug.traceback))
    write(major,before_major); write(minor,before_minor)
    return table.unpack(result,1,result.n)
end

function install_dedicated()
    local raw = entity()
    if not raw then return false end
    local mapping = {CIV='civilization',SITE='government',
        LIBRARY='library',HOSPITAL='hospital',MERCHANT_COMPANY='business',CRAFT_GUILD='business',
        ROAD='road',TUNNEL='tunnel',BRIDGE='bridge',WALL='wall'}
    -- Resolve everything first; old caches retain their matching original pools.
    local pending = {}
    for key,category in pairs(mapping) do
        local slots = resolve(category)
        if not slots then return false end
        pending[key] = slots
    end
    for key,slots in pairs(pending) do
        write(raw.symbols.symbols_major[df.entity_name_type[key]],slots)
        write(raw.symbols.symbols_minor[df.entity_name_type[key]],slots)
    end
    return true
end

-- DFHack callers (including gui/rename) also use the native template API.
-- This does not intercept DF's internal C++ calls; the creation overlay covers
-- the native fortress squad UI separately.
function install_api_guard()
    if original_generate then return end
    original_generate = dfhack.translation.generateName
    dfhack.translation.generateName = function(name,language,kind,major,minor)
        local raw = entity()
        local translation = language >= 0 and df.global.world.raws.language.translations[language]
        if kind ~= df.language_name_type.Squad or not raw or not translation or translation.name ~= 'FORTHAMMER_KHAZALID'
                or major ~= raw.symbols.symbols_major[df.entity_name_type.OTHER]
                or minor ~= raw.symbols.symbols_minor[df.entity_name_type.OTHER]
                or not resolve('squad') then
            return original_generate(name,language,kind,major,minor)
        end
        local ok,err = with_type('squad',function()
            return original_generate(name,language,kind,major,minor)
        end)
        if not ok then error(err) end
    end
end
