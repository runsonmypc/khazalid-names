-- Pure naming policy; native objects and mutation belong in the adapter.
--@ module = true
local data = reqscript('internal/forthammer-names/data').data

function normalize(value)
    return value:lower():gsub('[^a-z0-9]', '')
end

local reserved = {}
for _,name in ipairs(data.reserved) do reserved[normalize(name)] = true end

function is_reserved(name) return reserved[normalize(name)] or false end

local function title(s) return s:sub(1,1):upper() .. s:sub(2) end

local function entry(name, roots, gloss, status, token)
    local sources, seen = {}, {}
    for _,root in ipairs(roots) do
        local source = data.roots[root].source
        if not seen[source] then sources[#sources+1] = source; seen[source] = true end
    end
    return {name=name, roots=roots, gloss=gloss,
        status=status or 'Adapted symbolic compound; no history or ownership implied.',
        sources=sources, token=token}
end

function categories()
    local result = {'forename-male', 'forename-female', 'person-male', 'person-female',
        'family', 'clan', 'hold', 'settlement', 'mountain', 'pass', 'cavern', 'stream', 'lake'}
    local extra = {}
    for category in pairs(data.types or {}) do extra[#extra+1] = category end
    table.sort(extra)
    for _,category in ipairs(extra) do result[#result+1] = category end
    return result
end

local function family_entries()
    local result = {}
    for _,family in ipairs(data.families) do
        local item = entry(family.name, {table.unpack(family.roots)}, family.gloss, family.status, family.token)
        item.sources = {table.unpack(family.sources)}
        item.grouping = family.grouping
        result[#result+1] = item
    end
    return result
end

function candidates(category)
    if type(category) ~= 'string' then return nil, 'Category must be a string.' end
    if data.types and data.types[category] then
        local result = {}
        for _,candidate in ipairs(data.types[category].candidates) do
            local copy = {}
            for key,value in pairs(candidate) do
                copy[key] = type(value) == 'table' and {table.unpack(value)} or value
            end
            result[#result+1] = copy
        end
        return result -- previews and callers cannot mutate the reviewed catalog
    end
    local result = {}
    local sex = category:match('^forename%-(%a+)$') or category:match('^person%-(%a+)$')
    if sex and data.forenames[sex] then
        local families = category:match('^person') and family_entries()
        for _,first in ipairs(data.forenames[sex]) do
            if category:match('^forename') then
                result[#result+1] = {name=first, gloss='Attested forename; no translation assigned.',
                    status='Attested forename.', roots={}, sources={'DPG:39'}}
            else
                for _,family in ipairs(families) do
                    -- The reviewed family already carries complete provenance;
                    -- do not rebuild and then discard root-source tables for
                    -- every member of the full personal-name product.
                    local item = {name=first..' '..family.name, roots={table.unpack(family.roots)},
                        gloss=family.gloss, sources={table.unpack(family.sources)},
                        grouping=family.grouping,
                        status='Attested forename + adapted DF family label; not a patronymic or earned epithet.'}
                    item.sources[#item.sources+1] = 'DPG:39'
                    result[#result+1] = item
                end
            end
        end
    elseif category == 'family' or category == 'clan' then
        result = family_entries()
        for _,item in ipairs(result) do
            item.status = category == 'clan'
                and 'Proposed clan label only; no membership, ancestor or recognition created.'
                or 'Adapted DF family label; no ancestry or earned epithet implied.'
        end
    elseif category == 'hold' then
        for _,item in ipairs(data.holds) do
            result[#result+1] = entry(item.name, item.roots, item.gloss, nil, item.token)
        end
    elseif data.place_heads[category] then
        local head = data.place_heads[category]
        for _,motif in ipairs(data.motifs) do
            result[#result+1] = entry(title(motif..head), {motif,head},
                data.roots[motif].gloss .. ' ' .. data.roots[head].gloss)
        end
        for _,family in ipairs(data.place_families) do
            local parts = {table.unpack(family.roots)}
            parts[#parts+1] = head
            result[#result+1] = entry(family.name..head, parts,
                family.gloss .. ' ' .. data.roots[head].gloss)
        end
    else
        return nil, 'Unknown category: '..tostring(category)
    end
    local valid, seen = {}, {}
    for _,item in ipairs(result) do
        local key = normalize(item.name)
        if not reserved[key] and not seen[key] then
            valid[#valid+1] = item
            seen[key] = true
        end
    end
    return valid
end

-- occupied is a set keyed by names, not a list; normalize here so callers cannot
-- accidentally bypass a collision with a different case/spacing/hyphenation.
function generate_batch(category, count, random_index, occupied)
    if type(category) ~= 'string' then return nil, 'Category must be a string.' end
    if type(count) ~= 'number' or count % 1 ~= 0 or count < 1 then
        return nil, 'Count must be a positive integer.'
    end
    if type(random_index) ~= 'function' then return nil, 'A random-index function is required.' end
    local all, err = candidates(category)
    if not all then return nil, err end
    local blocked = {}
    for name,present in pairs(occupied or {}) do
        if present then blocked[normalize(name)] = true end
    end
    local available = {}
    for _,item in ipairs(all) do
        if not blocked[normalize(item.name)] then available[#available+1] = item end
    end
    if #available == 0 then return nil, 'No unused names remain in this category.' end
    if count > #available then
        return nil, ('Requested %s unique names, but only %d are available in %s.'):format(tostring(count), #available, category)
    end
    local result = {}
    for _=1,count do
        local index = random_index(#available)
        if type(index) ~= 'number' or index % 1 ~= 0 or index < 1 or index > #available then
            return nil, 'Random source returned an invalid index.'
        end
        result[#result+1] = available[index]
        -- Unordered removal keeps each draw uniform without shifting the pool.
        available[index] = available[#available]
        available[#available] = nil
    end
    return result
end

function generate(category, random_index, occupied)
    local items, err = generate_batch(category, 1, random_index, occupied)
    return items and items[1], err
end

function describe(item, concise)
    local refs, pages = {}, {}
    local titles = {DPG='Dwarf Players Guide (WFRP 4e)', WFB8='Warhammer Armies: Dwarfs (8e)',
        WFB8RB='Warhammer Rulebook (8e)', AOE1='Archives of the Empire I (WFRP 4e)', ALTDORF4='Altdorf: Crown of the Empire (WFRP 4e)'}
    for _,ref in ipairs(item.sources) do
        local key,location = ref:match('^([^:]+):(.+)$')
        local source = data.source_registry and data.source_registry[ref]
        if concise and key == 'DPG' and location:match('^%d+$') then
            pages[#pages+1] = tonumber(location)
        else
            refs[#refs+1] = source and (source.title..', '..source.location) or ((titles[key] or key or ref)..(location and (' '..location) or ''))
        end
    end
    if #pages > 0 then
        table.sort(pages)
        table.insert(refs,1,'Dwarf Players Guide (WFRP 4e), pp. '..table.concat(pages,', '))
    end
    return item.name .. ' -- ' .. item.gloss .. '\n'
        .. (item.grouping and ('Reading: '..item.grouping..'\n') or '')
        .. (concise and 'Adapted symbolic title using attested Khazalid words.' or item.status) .. '\n'
        .. 'Sources: ' .. table.concat(refs, '; ')
        .. (concise and '.' or ' (page numbers unless PDF/section is stated).')

end
