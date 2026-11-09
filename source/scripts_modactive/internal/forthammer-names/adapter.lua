-- Explicit, guarded native name edits. Lifecycle hooks only invalidate proposals.
--@ module = true
local core = reqscript('internal/forthammer-names/core')
local targets = reqscript('internal/forthammer-names/targets')
local native = reqscript('internal/forthammer-names/native')
local artifact_facts = reqscript('internal/forthammer-names/artifact-facts')
local artifact_fit = reqscript('internal/forthammer-names/artifact-fit')

-- DF retains world_data across unloads, so its address is not a session ID.
-- Keep one Lua-only epoch across module/cache reloads; old GUI closures observe
-- this same state. Importing a replacement adapter also invalidates old previews.
local session_key = 'ForthammerLocal/names/session-state'
local session = package.loaded[session_key] or {epoch=0}
package.loaded[session_key] = session
session.epoch = session.epoch + 1
dfhack.onStateChange.forthammer_names_adapter = function(code)
    if code == SC_MAP_UNLOADED or code == SC_WORLD_UNLOADED then
        session.epoch = session.epoch + 1
    end
end

function eligibility()
    if not dfhack.isWorldLoaded() or not dfhack.isMapLoaded() or not dfhack.world.isFortressMode() then
        return nil, 'Load a ForthammerLocal Dwarf fortress first.'
    end
    local active = false
    for _,mod in ipairs(require('script-manager').get_active_mods()) do
        if mod.id == 'ForthammerLocal' then active = true end
    end
    local p = df.global.plotinfo
    local civ = df.historical_entity.find(p.civ_id)
    local race = df.global.world.raws.creatures.all[p.race_id]
    if not active or not civ or not civ.entity_raw or civ.entity_raw.code ~= 'MOUNTAIN'
            or not race or race.creature_id ~= 'DWARF' or p.site_id < 0 then
        return nil, 'This action requires a ForthammerLocal MOUNTAIN/DWARF fortress.'
    end
    return {world=df.global.world.world_data, site=p.site_id, civ=p.civ_id,
        group=p.group_id, epoch=session.epoch}
end

local function snapshot(name)
    local value = {first_name=name.first_name, nickname=name.nickname, language=name.language,
        type=name.type, has_name=name.has_name, words={}, parts_of_speech={}}
    for i=0,6 do
        value.words[i] = name.words[i]
        value.parts_of_speech[i] = name.parts_of_speech[i]
    end
    return value
end

local function same(name, value)
    for _,key in ipairs{'first_name','nickname','language','type','has_name'} do
        if name[key] ~= value[key] then return false end
    end
    for i=0,6 do
        if name.words[i] ~= value.words[i] or name.parts_of_speech[i] ~= value.parts_of_speech[i] then return false end
    end
    return true
end

local function unit_names(unit)
    local race = unit.race >= 0 and df.global.world.raws.creatures.all[unit.race]
    if not race or race.creature_id ~= 'DWARF' or unit.civ_id ~= df.global.plotinfo.civ_id then
        return nil, 'Select a Dwarf belonging to this civilization.'
    end
    if dfhack.units.getVisibleName(unit) ~= unit.name then
        return nil, 'Disguised or assumed identities are not supported.'
    end
    local names = {unit.name}
    if unit.status.current_soul then names[#names+1] = unit.status.current_soul.name end
    local hf = df.historical_figure.find(unit.hist_figure_id)
    if hf then
        if dfhack.units.getVisibleName(hf) ~= hf.name then
            return nil, 'Disguised historical identities are not supported.'
        end
        names[#names+1] = hf.name
    end
    for _,name in ipairs(names) do
        if not name.has_name then
            return nil, 'This action edits an existing native name; unnamed unit, soul or historical-figure names are not supported.'
        end
    end
    return names
end

local function assign(name, value)
    for _,key in ipairs{'first_name','nickname','language','type','has_name'} do name[key] = value[key] end
    for i=0,6 do
        name.words[i] = value.words[i]
        name.parts_of_speech[i] = value.parts_of_speech[i]
    end
end

local function format(value)
    local name = df.language_name:new()
    assign(name, value)
    local text = dfhack.translation.translateName(name)
    local full = native.full_name(name)
    name:delete()
    return text, full
end

local function resolve_raws(token)
    local language, prefix, suffix
    for i,v in ipairs(df.global.world.raws.language.translations) do
        if v.name == 'FORTHAMMER_KHAZALID' then language = i end
    end
    for i,v in ipairs(df.global.world.raws.language.words) do
        if v.word == 'FH_KHAZ_HOLD_PREFIX' then prefix = i end
        if v.word == token then suffix = i end
    end
    if not language or not prefix or not suffix then
        return nil, 'This save lacks the naming raws. Generate a new world; do not replace cached save raws.'
    end
    return language, prefix, suffix
end

local function collision(kind, full, visible, except_id, except_unit_id)
    local keys = {[core.normalize(full)]=true, [core.normalize(visible)]=true}
    local function matches(name)
        return name and name.has_name and (keys[core.normalize(native.full_name(name))]
            or keys[core.normalize(dfhack.translation.translateName(name))])
    end
    local function figure_matches(object)
        if matches(object.name) then return true end
        local visible = dfhack.units.getVisibleName(object)
        return visible ~= object.name and matches(visible)
    end
    local objects = kind == 'unit' and df.global.world.history.figures or df.global.world.world_data.sites
    for _,object in ipairs(objects) do
        if object.id ~= except_id and (kind == 'unit' and figure_matches(object)
                or kind ~= 'unit' and matches(object.name)) then return true end
    end
    if kind == 'unit' then
        for _,unit in ipairs(df.global.world.units.all) do
            if unit.id ~= except_unit_id and figure_matches(unit) then return true end
        end
    end
    return false
end

function preview(kind, id, item, namespace)
    local ctx, err = eligibility()
    if not ctx then return nil, err end
    local names, value, excluded, artifact_profile
    if kind == 'unit' then
        local unit = df.unit.find(id)
        if not unit then return nil, 'The selected Dwarf is no longer available.' end
        names, err = unit_names(unit)
        if not names then return nil, err end
        local category = unit.sex == 0 and 'forename-female' or unit.sex == 1 and 'forename-male' or nil
        if not category then return nil, 'No source-backed forename table for this sex value.' end
        local valid = false
        for _,candidate in ipairs(core.candidates(category)) do
            if candidate.name == item.name then valid = true; break end
        end
        if not valid then return nil, 'Choose an attested forename from the matching source table.' end
        value = snapshot(unit.name)
        value.first_name = item.name:lower()
        excluded = unit.hist_figure_id
    elseif kind == 'site' and id == ctx.site then
        local site = df.world_site.find(id)
        if not site then return nil, 'The fortress is no longer available.' end
        local valid = false
        for _,candidate in ipairs(core.candidates('hold')) do
            if candidate.name == item.name and candidate.token == item.token then valid = true; break end
        end
        if not valid then return nil, 'Choose a generated hold proposal.' end
        local language, prefix, suffix = resolve_raws(item.token)
        if not language then return nil, prefix end
        names = {site.name}
        value = {first_name='',nickname='',language=language,type=df.language_name_type.Site,
            has_name=true,words={},parts_of_speech={}}
        for i=0,6 do value.words[i]=-1; value.parts_of_speech[i]=df.part_of_speech.Noun end
        value.words[0],value.words[1]=prefix,suffix
        value.parts_of_speech[0]=df.part_of_speech.Prefix
        excluded = id
    else
        local candidates = core.candidates(kind)
        local valid = false
        for _,candidate in ipairs(candidates or {}) do
            if candidate.name == item.name and candidate.token == item.token then
                valid = true
                item = candidate -- meanings/evidence come from the reviewed catalog
                break
            end
        end
        if not valid then return nil, 'Choose a reviewed candidate of the matching type.' end
        local target
        target, err = targets.resolve(kind,id,ctx,namespace)
        if not target then return nil, err end
        namespace = target.namespace
        if kind == 'artifact' then
            artifact_profile = artifact_facts.read(target.object.item)
            local _, _, compatible = artifact_fit.assess(item,artifact_profile)
            if not compatible then
                return nil, 'That title requires unsupported item properties. Generate a compatible proposal.'
            end
        end
        local language,token
        for i,v in ipairs(df.global.world.raws.language.translations) do
            if v.name == 'FORTHAMMER_KHAZALID' then language=i end
        end
        for i,v in ipairs(df.global.world.raws.language.words) do
            if v.word == item.token then token=i end
        end
        if not language or not token then return nil, 'This world lacks the expanded naming raws. Keep its cache; use a new world for the new raws.' end
        names = {target.name}
        value = {first_name='',nickname='',language=language,type=target.name.type,
            has_name=true,words={},parts_of_speech={}}
        for i=0,6 do value.words[i]=-1; value.parts_of_speech[i]=df.part_of_speech.Noun end
        value.words[0] = token
        -- Retain the real native name type (e.g. tavern FoodStore), not an enum guess.
        excluded = id
        for _,other in ipairs(targets.occupied(kind,ctx)) do
            if (other.id ~= id or other.namespace ~= namespace)
                    and core.normalize(other.name) == core.normalize(item.name) then
                return nil, 'That name is already in use by another target of this type.', 'collision'
            end
        end
    end
    local visible_text, full_text = format(value)
    if core.is_reserved(full_text) or core.is_reserved(visible_text)
            or ((kind == 'unit' or kind == 'site') and collision(kind, full_text, visible_text, excluded, kind == 'unit' and id or nil)) then
        return nil, 'That complete name is reserved or already in use. Generate another.', 'collision'
    end
    local before = {}
    for _,name in ipairs(names) do before[#before+1] = snapshot(name) end
    return {kind=kind,id=id,namespace=namespace,context=ctx,before=before,after=value,
        old_text=kind == 'unit' and native.full_name(names[1]) or dfhack.translation.translateName(names[1]),
        new_text=kind == 'unit' and full_text or visible_text,item=item,
        artifact_signature=artifact_profile and artifact_profile.signature,
        fit_text=artifact_profile and artifact_fit.explain(item,artifact_profile)}
end

-- Find an unused proposal with a finite bound. Typed names can exclude occupied
-- strings up front; forenames still need complete-name checks with the existing
-- family/nickname, so those candidates are previewed at most once each.
function suggest(kind,id,category,random_index,namespace)
    local ctx,err = eligibility()
    if not ctx then return nil,err end
    local occupied, artifact_profile = {}, nil
    if kind == 'unit' then
        local unit = df.unit.find(id)
        if not unit then return nil,'The selected Dwarf is no longer available.' end
        local names
        names,err = unit_names(unit)
        if not names then return nil,err end
        local expected = unit.sex == 0 and 'forename-female' or unit.sex == 1 and 'forename-male'
        if not expected or category ~= expected then return nil,'Choose the matching source-backed forename category.' end
        occupied[unit.name.first_name] = true
    elseif kind == 'site' then
        if id ~= ctx.site or category ~= 'hold' or not df.world_site.find(id) then
            return nil,'Choose a hold proposal for this fortress.'
        end
        for _,site in ipairs(df.global.world.world_data.sites) do
            occupied[dfhack.translation.translateName(site.name)] = true
            occupied[native.full_name(site.name)] = true
        end
    else
        if category ~= kind then return nil,'Choose the matching naming category.' end
        local target
        target,err = targets.resolve(kind,id,ctx,namespace)
        if not target then return nil,err end
        namespace = target.namespace
        if kind == 'artifact' then artifact_profile = artifact_facts.read(target.object.item) end
        occupied[dfhack.translation.translateName(target.name)] = true
        for _,other in ipairs(targets.occupied(kind,ctx)) do occupied[other.name] = true end
    end
    local all
    all,err = core.candidates(category)
    if not all then return nil,err end
    if artifact_profile then
        local item
        item,err = artifact_fit.choose(all,artifact_profile,random_index,occupied)
        if not item then return nil,err end
        return preview(kind,id,item,namespace)
    end
    for _=1,#all do
        local item
        item,err = core.generate(category,random_index,occupied)
        if not item then
            if err:find('No unused',1,true) then break end
            return nil,err
        end
        occupied[item.name] = true
        local proposal,reason
        proposal,err,reason = preview(kind,id,item,namespace)
        if proposal then return proposal end
        if reason ~= 'collision' then return nil,err end
    end
    return nil,'No unused alternative names remain for this target in the reviewed '..category..' pool.'
end

-- A list is a session-local snapshot, not a reservation or a saved name deck.
function artifact_options(id, random_index, namespace)
    local ctx,err = eligibility()
    if not ctx then return nil,err end
    local target
    target,err = targets.resolve('artifact',id,ctx,namespace)
    if not target then return nil,err end
    local profile = artifact_facts.read(target.object.item)
    local occupied = {[dfhack.translation.translateName(target.name)]=true}
    for _,other in ipairs(targets.occupied('artifact',ctx)) do occupied[other.name] = true end
    local options
    options,err = artifact_fit.alternatives(core.candidates('artifact'),profile,random_index,occupied)
    if not options then return nil,err end
    return {id=id,namespace=target.namespace,context=ctx,before=snapshot(target.name),
        signature=profile.signature,options=options}
end

function preview_option(list, index)
    local ctx,err = eligibility()
    if not ctx then return nil,err end
    for _,key in ipairs{'world','site','civ','group','epoch'} do
        if ctx[key] ~= list.context[key] then return nil,'The fortress session changed. Reopen the name choices.' end
    end
    local option = list.options[index]
    if not option then return nil,'Choose an available option.' end
    -- preview re-resolves the target, canonical candidate, facts and collisions.
    local proposal
    proposal,err = preview('artifact',list.id,option.item,list.namespace)
    if not proposal then return nil,err end
    if proposal.artifact_signature ~= list.signature then return nil,'The item properties changed. Reopen the name choices.' end
    if not same(proposal.before[1],list.before) then return nil,'The name changed. Reopen the name choices.' end
    return proposal
end

function accept(proposal)
    local ctx, err = eligibility()
    if not ctx then return false, err end
    if ctx.epoch ~= proposal.context.epoch or ctx.world ~= proposal.context.world
            or ctx.site ~= proposal.context.site or ctx.civ ~= proposal.context.civ
            or ctx.group ~= proposal.context.group then
        return false, 'The fortress session changed. Generate a new proposal.'
    end
    -- Re-resolve IDs, raw indices, collision checks and target names at acceptance.
    local fresh
    fresh, err = preview(proposal.kind, proposal.id, proposal.item, proposal.namespace)
    if not fresh then return false, err end
    if fresh.artifact_signature ~= proposal.artifact_signature then
        return false, 'The item properties changed. Generate a new proposal.'
    end
    if #fresh.before ~= #proposal.before then return false, 'The target changed. Generate a new proposal.' end
    for i,name in ipairs(fresh.before) do
        if not same(name, proposal.before[i]) then return false, 'The name changed. Generate a new proposal.' end
    end
    if not same(fresh.after, proposal.after) then return false, 'The proposal changed. Generate a new proposal.' end
    local names
    if proposal.kind == 'unit' then names = unit_names(df.unit.find(proposal.id))
    elseif proposal.kind == 'site' then names = {df.world_site.find(proposal.id).name}
    else names = {assert(targets.resolve(proposal.kind,proposal.id,ctx,proposal.namespace)).name} end
    local ok, failure = pcall(function()
        for _,name in ipairs(names) do
            if proposal.kind == 'unit' then name.first_name = proposal.after.first_name
            else assign(name, proposal.after) end
        end
    end)
    if not ok then
        local restored, restore_error = pcall(function()
            for i,name in ipairs(names) do assign(name, proposal.before[i]) end
        end)
        return false, 'Name write failed: '..tostring(failure)
            .. (restored and ' Original names restored.' or ' Restoration failed: '..tostring(restore_error))
    end
    return true
end
