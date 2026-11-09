-- Populate only the eligible civilization's native selectors. Never edit names.
--@ module = true
local HOOK = 'forthammer-local/khazalid-name-pools'

function install()
    if not dfhack.isWorldLoaded() then return false end
    local active = false
    for _,mod in ipairs(require('script-manager').get_active_mods()) do
        if mod.id == 'ForthammerLocal' then active = true end
    end
    if not active then return false end
    local language = df.global.world.raws.language
    local entity
    for _,raw in ipairs(df.global.world.raws.entities.all) do
        if raw.code == 'MOUNTAIN' and raw.translation == 'FORTHAMMER_KHAZALID' then entity = raw end
    end
    if not entity then return false end -- old caches are intentionally not migrated
    local entries = {{},{},{},{},{},{}}
    local families = {}
    local function add(slot, index, part)
        table.insert(entries[slot+1], {index=index, part=part})
    end
    for i,word in ipairs(language.words) do
        if word.word:match('^FH_KHAZ_GIVEN_') then
            add(2,i,df.part_of_speech.Noun)
        elseif word.word:match('^FH_KHAZ_MOTIF_') then
            add(0,i,df.part_of_speech.Noun)
            -- The native adjective slot can hold a noun aspect; its English form
            -- is the reviewed motif gloss, not a fabricated word form.
            add(3,i,df.part_of_speech.Noun)
        elseif word.word:match('^FH_KHAZ_CRAFT_') then
            for _,slot in ipairs{1,4,5} do add(slot,i,df.part_of_speech.Noun) end
        elseif word.word:match('^FH_KHAZ_FAMILY_') then
            families[#families+1] = {index=i, part=df.part_of_speech.Noun}
        end
    end
    -- Complete reviewed labels prevent unapproved pairings when the vocabulary
    -- grows. Old cached raws lack these tokens and retain their original pools.
    if #families > 0 then
        entries[1] = families
        entries[2] = {{index=-1, part=df.part_of_speech.Noun}}
    end
    for _,slot in ipairs(entries) do
        if #slot == 0 then
            dfhack.printerr('Forthammer names: incomplete naming raws; native pools left unchanged.')
            return false
        end
    end
    for _,selector in ipairs{entity.symbols.symbols_major[df.entity_name_type.OTHER],
            entity.symbols.symbols_minor[df.entity_name_type.OTHER]} do
        for slot=0,5 do
            selector.words[slot]:resize(0)
            selector.parts[slot]:resize(0)
            for _,entry in ipairs(entries[slot+1]) do
                selector.words[slot]:insert('#', entry.index)
                selector.parts[slot]:insert('#', entry.part)
            end
        end
    end
    local pools = reqscript('internal/forthammer-names/pools')
    pools.install_dedicated()
    pools.install_api_guard()
    return true
end

dfhack.onStateChange[HOOK] = function(event)
    if event == SC_WORLD_LOADED then install() end
end
-- Active mod modules are imported on world load, including new world generation.
install()
if not dfhack_flags.module then
    print(install() and 'Khazalid native pools ready; existing names unchanged.'
        or 'No eligible world with the new naming raws is loaded.')
end
