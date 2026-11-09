-- Resolve actual native targets; never infer authorship from present ownership.
--@ module = true
local utils = require('utils')
local native = reqscript('internal/forthammer-names/native')
local classes = {
    tavern={'abstract_building_inn_tavernst'}, guildhall={'abstract_building_guildhallst'},
    library={'abstract_building_libraryst'}, hospital={'abstract_building_hospitalst'},
    business={'abstract_building_counting_housest','abstract_building_marketst'},
}
local supported = {squad=true,civilization=true,government=true,
    tavern=true,guildhall=true,library=true,hospital=true,
    business=true,artifact=true,road=true,tunnel=true,bridge=true,wall=true}

local function dwarf_entity(entity)
    return entity and entity.entity_raw and entity.entity_raw.code == 'MOUNTAIN'
end
local function belongs(entity, ctx)
    if not dwarf_entity(entity) then return false end
    if entity.id == ctx.civ or entity.id == df.global.plotinfo.group_id then return true end
    for _,link in ipairs(entity.entity_links) do
        if link.type == df.entity_entity_link_type.PARENT and link.target == ctx.civ then return true end
    end
    return false
end
local function location(category,id,ctx)
    local site = df.world_site.find(ctx.site)
    local loc = site and utils.binsearch(site.buildings,id,'id')
    if not loc then return end
    local valid = false
    for _,class in ipairs(classes[category] or {}) do
        if df[class] and df[class]:is_instance(loc) then valid = true end
    end
    if not valid or not belongs(df.historical_entity.find(loc.site_owner_id),ctx) then return end
    return loc
end

function resolve(category, id, ctx, namespace, builders)
    if not supported[category] then return nil, 'Unsupported native naming category.' end
    if type(id) ~= 'number' or id < 0 or id % 1 ~= 0 then return nil, 'Choose a valid native target ID.' end
    if category == 'business' then
        if namespace ~= 'entity' and namespace ~= 'location' then
            return nil, 'Choose an explicit business entity or location.'
        end
    elseif classes[category] then
        if namespace ~= nil and namespace ~= 'location' then return nil, 'This target requires the location namespace.' end
    elseif namespace ~= nil then
        return nil, 'This target does not use a separate namespace.'
    end
    local object, name
    if category == 'squad' then
        object = df.squad.find(id)
        if not object or object.entity_id ~= df.global.plotinfo.group_id then return nil, 'Choose a squad of this fortress.' end
        if object.alias ~= '' then return nil, 'This squad has a custom alias. Clear it deliberately before changing its generated name.' end
    elseif category == 'civilization' or category == 'government' then
        local expected = category == 'civilization' and ctx.civ or df.global.plotinfo.group_id
        object = df.historical_entity.find(id)
        local kind = category == 'civilization' and df.historical_entity_type.Civilization or df.historical_entity_type.SiteGovernment
        if id ~= expected or not belongs(object,ctx) or object.type ~= kind then return nil, 'Choose this fortress government or civilization.' end
    elseif category == 'business' and namespace == 'entity' then
        object = df.historical_entity.find(id)
        if not belongs(object,ctx) or (object.type ~= df.historical_entity_type.MerchantCompany
                and object.type ~= df.historical_entity_type.Guild) then return nil, 'Choose an affiliated Dwarf business.' end
    elseif classes[category] then
        object = location(category,id,ctx)
        if not object then return nil, 'Choose a matching location constructed by this Dwarf community.' end
    elseif category == 'artifact' then
        object = df.artifact_record.find(id)
        local item = object and object.item
        if not item or item.flags.garbage_collect then return nil, 'The named item is no longer available.' end
        -- Both crafted artifacts and existing items that acquire names use the
        -- artifact flag and IS_ARTIFACT link. A bare record pointer is insufficient:
        -- native item descriptions would not display the edited record's name.
        local ref = dfhack.items.getGeneralRef(item,df.general_ref_type.IS_ARTIFACT)
        if not item.flags.artifact or not ref or ref.artifact_id ~= id then
            return nil, 'The item and artifact record do not agree.'
        end
        if dfhack.items.getBookTitle(item) ~= '' then
            return nil, 'Written works use a separate title and are outside this naming expansion.'
        end
        local maker = df.historical_figure.find(item:getMaker())
        local race = maker and maker.race >= 0 and df.global.world.raws.creatures.all[maker.race]
        if not race or race.creature_id ~= 'DWARF' or maker.civ_id ~= ctx.civ then
            return nil, 'Named items require a verified Dwarf maker from this civilization.'
        end
    elseif category == 'road' or category == 'tunnel' or category == 'bridge' or category == 'wall' then
        object = df.world_construction.find(id)
        if not object or not df['world_construction_'..category..'st']:is_instance(object) then
            return nil, 'Choose the matching world construction, not a local building tile.'
        end
        -- Builder evidence is mandatory. The event schema is resolved explicitly
        -- by construction_events(), never guessed from geographical proximity.
        builders = builders or construction_events(ctx)
        if not builders[id] then return nil, 'No matching Dwarf construction event establishes its builder.' end
    else
        return nil, 'Unsupported native naming category.'
    end
    name = object.name
    return {object=object,name=name,
        namespace=classes[category] and (namespace == 'entity' and 'entity' or 'location') or nil}
end

function construction_events(ctx)
    local result = {}
    -- Populated from the documented event class below; no fallback to location.
    for _,event in ipairs(df.global.world.history.events) do
        if df.history_event_created_world_constructionst and df.history_event_created_world_constructionst:is_instance(event) then
            if belongs(df.historical_entity.find(event.civ),ctx) then result[event.construction] = true end
        end
    end
    return result
end

function list(category,ctx)
    local out = {}
    if not supported[category] then return out end
    local builders = (category == 'road' or category == 'tunnel' or category == 'bridge' or category == 'wall') and construction_events(ctx)
    local function add(id,namespace)
        local target = resolve(category,id,ctx,namespace,builders)
        if target then
            local label = dfhack.translation.translateName(target.name)
            if category == 'artifact' then
                label = dfhack.items.getReadableDescription(target.object.item)..' ['..id..']'
            elseif category == 'business' then
                label = label..' ['..namespace..' '..id..']'
            else
                label = label..' ['..id..']'
            end
            out[#out+1] = {id=id,namespace=target.namespace,text=label}
        end
    end
    if category == 'civilization' then add(ctx.civ)
    elseif category == 'government' then add(df.global.plotinfo.group_id)
    elseif category == 'squad' then
        local fort = df.historical_entity.find(df.global.plotinfo.group_id)
        for _,id in ipairs(fort.squads) do add(id) end
    elseif category == 'artifact' then
        for _,record in ipairs(df.global.world.artifacts.all) do add(record.id) end
    elseif classes[category] then
        for _,loc in ipairs(df.world_site.find(ctx.site).buildings) do add(loc.id,'location') end
        if category == 'business' then
            for _,entity in ipairs(df.global.world.entities.all) do add(entity.id,'entity') end
        end
    else
        for _,construction in ipairs(df.global.world.world_data.constructions.list) do
            if builders[construction.id] then add(construction.id) end
        end
    end
    return out
end

-- Name occupancy is broader than permission to edit. An aliased squad, foreign
-- builder or absent artifact item does not make its existing name available.
-- Return names separately from display labels, preserving overlapping ID spaces.
function occupied(category,ctx)
    local out = {}
    if not supported[category] then return out end
    local function add(object,namespace,name)
        local function append(text)
            if text ~= '' then out[#out+1] = {id=object.id,namespace=namespace,name=text} end
        end
        if name then append(name); return end -- explicit squad alias
        local full = native.full_name(object.name)
        local visible = dfhack.translation.translateName(object.name)
        append(full)
        if visible ~= full then append(visible) end
    end
    local function add_locations()
        local site = df.world_site.find(ctx.site)
        if not site then return end
        for _,loc in ipairs(site.buildings) do
            for _,class in ipairs(classes[category]) do
                if df[class] and df[class]:is_instance(loc) then add(loc,'location'); break end
            end
        end
    end
    if category == 'squad' then
        local fort = df.historical_entity.find(df.global.plotinfo.group_id)
        if not fort then return out end
        for _,id in ipairs(fort.squads) do
            local squad = df.squad.find(id)
            if squad and squad.entity_id == fort.id then
                add(squad)
                if squad.alias ~= '' then add(squad,nil,squad.alias) end
            end
        end
    elseif category == 'civilization' or category == 'government' or category == 'business' then
        local kind = category == 'civilization' and df.historical_entity_type.Civilization
            or category == 'government' and df.historical_entity_type.SiteGovernment
        for _,entity in ipairs(df.global.world.entities.all) do
            if (kind and entity.type == kind) or (category == 'business'
                    and (entity.type == df.historical_entity_type.MerchantCompany
                        or entity.type == df.historical_entity_type.Guild)) then
                add(entity,category == 'business' and 'entity' or nil)
            end
        end
        if category == 'business' then add_locations() end
    elseif classes[category] then
        add_locations()
    elseif category == 'artifact' then
        for _,record in ipairs(df.global.world.artifacts.all) do add(record) end
    else
        local class = df['world_construction_'..category..'st']
        for _,construction in ipairs(df.global.world.world_data.constructions.list) do
            if class:is_instance(construction) then add(construction) end
        end
    end
    return out
end
