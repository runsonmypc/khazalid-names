-- Initial names for locations created during one synchronous native UI input.
-- No timers, load observers, or edits to locations present before that input.
--@ module = true
local adapter = reqscript('internal/forthammer-names/adapter')
local core = reqscript('internal/forthammer-names/core')
local targets = reqscript('internal/forthammer-names/targets')

local classes = {
    hospital='abstract_building_hospitalst', library='abstract_building_libraryst',
    tavern='abstract_building_inn_tavernst', guildhall='abstract_building_guildhallst',
}

function snapshot()
    local ctx,err = adapter.eligibility()
    if not ctx then return nil,err end
    local site = df.world_site.find(ctx.site)
    if not site then return nil,'The current fortress site is unavailable.' end
    local ids = {}
    for _,object in ipairs(site.buildings) do ids[object.id] = true end
    return {context=ctx,ids=ids,count=#site.buildings,next_id=site.next_building_id}
end

function finish(before, random_index)
    if not before or before.finished then return false,'This creation input has already finished.' end
    before.finished = true
    local ctx,err = adapter.eligibility()
    if not ctx then return false,err end
    for _,field in ipairs{'world','epoch','site','civ','group'} do
        if ctx[field] ~= before.context[field] then
            return false,'The fortress session changed during location creation.'
        end
    end
    local site = df.world_site.find(ctx.site)
    if not site then return false,'The current fortress site is unavailable.' end
    local created = {}
    for _,object in ipairs(site.buildings) do
        if not before.ids[object.id] then created[#created+1] = object end
    end
    if #created == 0 then return true,{created=false} end
    if #created ~= 1 then return false,'Multiple new locations appeared; no initial names changed.' end
    local object,category = created[1]
    for kind,class in pairs(classes) do
        if df[class]:is_instance(object) then category=kind;break end
    end
    if not category then return true,{created=false,excluded=true} end
    if object.id ~= before.next_id or site.next_building_id ~= before.next_id+1
            or #site.buildings ~= before.count+1 then
        return false,'The native location creation sequence changed; no initial name applied.'
    end
    local target
    target,err = targets.resolve(category,object.id,ctx,'location')
    if not target or target.object ~= object then
        return false,err or 'The newly created location no longer matches.'
    end
    local occupied = {}
    for _,other in ipairs(targets.occupied(category,ctx)) do occupied[other.name] = true end
    local candidate,repeated
    candidate,err = core.generate(category,random_index,occupied)
    if not candidate and err:find('No unused',1,true) then
        -- Native names can repeat. Exhaustion must not retain an unrelated
        -- provisional DF name or invent suffixes; explicit edits remain strict.
        candidate,err = core.generate(category,random_index)
        repeated = true
    end
    if not candidate then return false,err end
    local language,word
    for i,value in ipairs(df.global.world.raws.language.translations) do
        if value.name == 'FORTHAMMER_KHAZALID' then language=i;break end
    end
    for i,value in ipairs(df.global.world.raws.language.words) do
        if value.word == candidate.token then word=i;break end
    end
    if language == nil or word == nil then
        return false,'This world lacks the reviewed location naming raws; keep its cache and use the new version for a new world.'
    end
    local old = df.language_name:new()
    old:assign(target.name)
    local ok,failure = pcall(function()
        target.name.first_name='';target.name.nickname=''
        target.name.language=language;target.name.has_name=true
        for i=0,6 do target.name.words[i]=-1;target.name.parts_of_speech[i]=df.part_of_speech.Noun end
        target.name.words[df.language_name_component.TheX] = word
        -- Preserve the actual native name.type and every non-name field.
    end)
    if not ok then
        local restored,restore_error = pcall(function() target.name:assign(old) end)
        old:delete()
        return false,'Initial location name failed: '..tostring(failure)
            ..(restored and ' Provisional name restored.' or ' Restoration failed: '..tostring(restore_error))
    end
    old:delete()
    return true,{created=true,id=object.id,category=category,name=candidate.name,repeated=repeated or false}
end
