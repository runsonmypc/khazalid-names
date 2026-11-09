-- Observable item facts only; naming never creates materials, images or history.
--@ module = true
local function set(words)
    local result = {}
    for word in words:gmatch('%S+') do result[word] = true end
    return result
end

local axes = set('ITEM_WEAPON_AXE_BATTLE ITEM_WEAPON_AXE_GREAT')
local hammers = set('ITEM_WEAPON_HAMMER_WAR ITEM_WEAPON_MAUL')
local tools = set([[ITEM_TOOL_LADLE ITEM_TOOL_MORTAR ITEM_TOOL_PESTLE
    ITEM_TOOL_KNIFE_CARVING ITEM_TOOL_KNIFE_BONING ITEM_TOOL_KNIFE_SLICING
    ITEM_TOOL_KNIFE_MEAT_CLEAVER ITEM_TOOL_FORK_CARVING ITEM_TOOL_STONE_AXE]])
local armour_types = set('ARMOR HELM GLOVES SHOES PANTS')

-- Positive raw-ID lists avoid mod materials whose game flags serve mechanics:
-- Forthammer gunpowder is IS_STONE and warpstone is both IS_STONE and IS_METAL.
-- The ordinary metal and rock IDs come from DF 53.14's material raws; the two
-- additional metals are the fork's explicit mundane material definitions.
local metals = set([[IRON GOLD SILVER COPPER NICKEL ZINC BRONZE BRASS STEEL
    PIG_IRON PLATINUM ELECTRUM TIN PEWTER_FINE PEWTER_TRIFLE PEWTER_LAY LEAD
    ALUMINUM NICKEL_SILVER BILLON STERLING_SILVER BLACK_BRONZE ROSE_GOLD
    BISMUTH BISMUTH_BRONZE ADAMANTINE GROMRIL ITHILMAR]])
local stones = set([[SANDSTONE SILTSTONE MUDSTONE SHALE CLAYSTONE ROCK_SALT
    LIMESTONE CONGLOMERATE DOLOMITE CHERT CHALK GRANITE DIORITE GABBRO
    RHYOLITE BASALT ANDESITE DACITE OBSIDIAN QUARTZITE SLATE PHYLLITE SCHIST
    GNEISS MARBLE HEMATITE LIMONITE GARNIERITE NATIVE_GOLD NATIVE_SILVER
    NATIVE_COPPER MALACHITE GALENA SPHALERITE CASSITERITE NATIVE_PLATINUM
    CINNABAR COBALTITE TETRAHEDRITE HORN_SILVER GYPSUM TALC JET PUDDINGSTONE
    PETRIFIED_WOOD GRAPHITE BRIMSTONE KIMBERLITE BISMUTHINITE REALGAR ORPIMENT
    STIBNITE MARCASITE SYLVITE CRYOLITE PERICLASE ILMENITE RUTILE MAGNETITE
    CHROMITE PYROLUSITE PITCHBLENDE BAUXITE NATIVE_ALUMINUM BORAX OLIVINE
    HORNBLENDE KAOLINITE SERPENTINE ORTHOCLASE MICROCLINE MICA CALCITE
    SALTPETER ALABASTER SELENITE SATINSPAR ANHYDRITE ALUNITE]])
-- Exact bodies only: alloys, ores and decorations are not the named metal.
-- Angaz is DPG p.44's ironwork; the other senses are Stone and Steel pp.101/103.
local exact_metals = {IRON='angaz', SILVER='agril', COPPER='izor'}
local exact_metal_descriptions = {IRON='iron', SILVER='silver', COPPER='copper'}
local dragons = set('DRAGON STAR_DRAGON BLACK_DRAGON FOREST_DRAGON CHAOS_DRAGON SUN_DRAGON')
local giants = set('GIANT GIANT_CIV')

local function image_reference(object)
    if df.item_statuest:is_instance(object) or df.item_figurinest:is_instance(object)
            or df.itemimprovement_art_imagest:is_instance(object)
            or df.itemimprovement_sewn_imagest:is_instance(object)
            or df.itemimprovement_illustrationst:is_instance(object) then
        return object.image
    end
end

function read(item)
    local facts = {type={}, material={}, image={}}
    local signature = {}
    local function stamp(...)
        for i=1,select('#',...) do
            local value = tostring(select(i,...))
            signature[#signature+1] = #value..':'..value
        end
    end
    local kind, subtype = item:getType(), item:getSubtype()
    local kind_name = df.item_type[kind]
    local definition = dfhack.items.getSubtypeDef(kind, subtype)
    local rawid = definition and definition.id or ''
    stamp('item',item.id,kind,subtype,rawid)

    if kind == df.item_type.WEAPON then
        facts.type.makaz = 'item type: weapon'
        if axes[rawid] then facts.type.az = 'item type: war axe' end
        if hammers[rawid] then facts.type.grund = 'item type: hammer' end
        if rawid == 'ITEM_WEAPON_HANDGUN' then
            facts.type.thrund = 'item type: handgun'
        end
    elseif kind == df.item_type.ANVIL then
        facts.type.grong = 'item type: anvil'
    elseif kind == df.item_type.STATUE then
        -- Stone and Steel p.105: Zunthrum, "Statues, monuments". A figurine
        -- has a distinct native type and is not assumed to be a full statue.
        facts.type.zunthrum = 'item type: statue'
    elseif kind == df.item_type.TOOL and tools[rawid] then
        facts.type.makaz = 'item type: tool'
    elseif armour_types[kind_name] and definition then
        stamp('armour-level',definition.armorlevel)
        if definition.armorlevel > 0 then
            facts.type.klad = 'item type: protective armour'
        end
    end

    -- The actual-material methods never return a race/caste pair (df.item.xml).
    local mat_type, mat_index = item:getActualMaterial(), item:getActualMaterialIndex()
    local material = dfhack.matinfo.decode(mat_type,mat_index)
    stamp('body',mat_type,mat_index,material and material:getToken() or '')
    if material and material.material then
        local flags = material.material.flags
        local id = material.inorganic and material.inorganic.id
        if material.mode == 'inorganic' and metals[id] and flags.IS_METAL then
            facts.material.azul = 'body material: metal'
            local root = exact_metals[id]
            if root then
                facts.material[root] = 'body material: '..exact_metal_descriptions[id]
            end
        elseif material.mode == 'inorganic' and stones[id] and flags.IS_STONE then
            facts.material.duraz = 'body material: stone'
            -- Mizpal means volcanic glass, not manufactured glass or any dark stone.
            if id == 'OBSIDIAN' then
                facts.material.mizpal = 'body material: volcanic glass (obsidian)'
            end
        elseif material.mode == 'creature' and material.material.id == 'BONE' and flags.BONE then
            facts.material.uzkul = 'body material: bone'
        end
    end

    -- Agrul selects DPG p.44's "stone carving" sense. A statue/figurine
    -- supplies the carved-object shape only when its actual body is stone;
    -- neither a metal casting nor a stone decoration proves this property.
    if (kind == df.item_type.STATUE or kind == df.item_type.FIGURINE)
            and facts.material.duraz then
        facts.type.agrul = 'item type: stone carving'
    end

    local function inspect_image(reference, origin)
        if not reference then return end
        stamp('image-reference',origin,reference.id,reference.subid)
        if reference.id < 0 or reference.subid < 0 or reference.subid >= 500 then return end
        -- Read loaded image records directly, without requesting native lazy art
        -- generation/loading. Missing, unsupported or unloaded art is unknown.
        local chunk = df.art_image_chunk.find(reference.id)
        local image = chunk and chunk.images[reference.subid].art_image
        if not image then return end
        for index, element in ipairs(image.elements) do
            if df.art_image_element_creaturest:is_instance(element) then
                local creature = element.race >= 0 and df.global.world.raws.creatures.all[element.race]
                local creature_id = creature and creature.creature_id or ''
                stamp('creature',origin,index,element.race,element.caste,element.count,creature_id)
                local root = dragons[creature_id] and 'drakk' or giants[creature_id] and 'gronti'
                if element.count > 0 and root and not facts.image[root] then
                    facts.image[root] = (origin == 'item' and 'item depicts a ' or 'decoration depicts a ')
                        ..(root == 'drakk' and 'dragon' or 'giant')
                end
            end
        end
    end
    inspect_image(image_reference(item),'item')
    if df.item_constructed:is_instance(item) then
        for index, improvement in ipairs(item.improvements) do
            local displayed = improvement:isDecoration()
            -- Decoration material is never promoted into a body-material fact.
            stamp('improvement',index,improvement:getType(),improvement.mat_type,
                improvement.mat_index,displayed)
            if displayed then inspect_image(image_reference(improvement),'improvement-'..index) end
        end
    end
    -- Include derived text so changed raw flags or interpreted evidence invalidate
    -- a preview even when the numeric item/material references remain unchanged.
    for _,group in ipairs{'type','material','image'} do
        local roots = {}
        for root in pairs(facts[group]) do roots[#roots+1] = root end
        table.sort(roots)
        for _,root in ipairs(roots) do stamp(group,root,facts[group][root]) end
    end
    return {item_id=item.id,signature=table.concat(signature),facts=facts}
end
