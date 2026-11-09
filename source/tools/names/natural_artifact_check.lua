-- Observe only: no moods, jobs, items, names, history, pause state or saves are written.
-- baseline [setup note], observe, watch [tick interval], stop, select [artifact-id],
-- snapshot, cancel, check, reload. Root operates the native UI and normal save.
local lab=assert(os.getenv('FORTHAMMER_PROBE_LAB'),'private naming lab only')
assert(lab=='/tmp/forthammer-probe-cc9yblvy','this lifecycle probe belongs to the naming lab')
local mode,argument=...
mode=mode or 'observe'
local json=require('json')
local adapter=reqscript('internal/forthammer-names/adapter')
local targets=reqscript('internal/forthammer-names/targets')
local facts=reqscript('internal/forthammer-names/artifact-facts')
local ctx=assert(adapter.eligibility())
local path=lab..'/results/names-natural-artifact.json'
local watch_key='forthammer/natural-artifact-probe-watch'
local edit_process_key='forthammer/natural-artifact-probe-edit-process'
local function utf(text)return dfhack.df2utf(text)end
local function read()
    local f=assert(io.open(path),'run baseline before observing');local text=f:read('*a');f:close()
    local result=json.decode(text)
    assert(result.site_id==ctx.site and result.civ_id==ctx.civ,'lifecycle report belongs to a different fortress')
    return result
end
local function write(result)
    local f=assert(io.open(path,'w'));f:write(json.encode(result),'\n');f:close()
end
local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function now()return {year=df.global.cur_year,tick=df.global.cur_year_tick}end
local function name_snapshot(name)
    local result={utf(name.first_name),utf(name.nickname),name.language,name.type,name.has_name}
    for i=0,6 do result[#result+1]=name.words[i];result[#result+1]=name.parts_of_speech[i] end
    return result
end
local function citizen(unit)
    local creature=unit.race>=0 and df.global.world.raws.creatures.all[unit.race]
    return creature and creature.creature_id=='DWARF' and unit.civ_id==ctx.civ and dfhack.units.isCitizen(unit)
end
local function unit_snapshot(unit)
    local job=unit.job.current_job
    local result={id=unit.id,hfid=unit.hist_figure_id,name=utf(dfhack.units.getReadableName(unit)),
        has_mood=unit.flags1.has_mood,had_mood=unit.flags1.had_mood,mood=unit.mood,
        mood_name=df.mood_type[unit.mood],stage=unit.moodstage,skill=unit.job.mood_skill,
        artifact_name=name_snapshot(unit.status.artifact_name),
        artifact_text=utf(dfhack.translation.translateName(unit.status.artifact_name))}
    if job then
        local holder=dfhack.job.getHolder(job)
        result.job={id=job.id,type=job.job_type,type_name=df.job_type[job.job_type],
            items={},requirements={}}
        if holder then result.job.workshop={id=holder.id,type=holder:getType(),subtype=holder:getSubtype()} end
        for _,ref in ipairs(job.items) do
            if ref.item then result.job.items[#result.job.items+1]=ref.item.id end
        end
        for _,requirement in ipairs(job.job_items.elements) do
            result.job.requirements[#result.job.requirements+1]={type=requirement.item_type,
                subtype=requirement.item_subtype,mat_type=requirement.mat_type,mat_index=requirement.mat_index,
                quantity=requirement.quantity,flags1=requirement.flags1.whole,
                flags2=requirement.flags2.whole,flags3=requirement.flags3.whole}
        end
    end
    return result
end
local function event_snapshot(event)
    return {id=event.id,year=event.year,seconds=event.seconds,artifact_id=event.artifact_id,
        creator_unit_id=event.creator_unit_id,creator_hfid=event.creator_hfid,
        entity=event.entity,site=event.site,name_only=event.flags2.name_only,
        flags2=event.flags2.whole,circumstance=event.circumstance.type,reason=event.reason.type}
end
local function creation_event(id)
    for _,event in ipairs(df.global.world.history.events) do
        if df.history_event_artifact_createdst:is_instance(event) and event.artifact_id==id
                and not event.flags2.name_only then return event end
    end
end
local function by_id(list,id)
    for _,value in ipairs(list) do if value.id==id then return value end end
end
local function is_new(result,id)
    for _,old in ipairs(result.baseline_artifact_ids) do if old==id then return false end end
    return true
end
local function completed(result,record)
    if not is_new(result,record.id) then return nil,'artifact existed at baseline' end
    local target,err=targets.resolve('artifact',record.id,ctx)
    if not target then return nil,err end
    local item=target.object.item
    if not item.flags.artifact_mood then return nil,'item was not created by an artifact mood' end
    local event=creation_event(record.id)
    if not event then return nil,'no native non-naming creation event exists' end
    local observed=by_id(result.moody_units,event.creator_unit_id)
    if not observed then return nil,'creator was never observed in a strange mood' end
    if observed.hfid~=event.creator_hfid or item:getMaker()~=event.creator_hfid or event.site~=ctx.site then
        return nil,'creator/item/event/site attribution disagrees'
    end
    if event.id<=result.baseline_last_event_id then return nil,'creation event predates baseline' end
    return {id=record.id,item_id=item.id,maker_hfid=item:getMaker(),
        name=utf(dfhack.translation.translateName(record.name)),event=event_snapshot(event),observed_at=now()}
end
local function observe(result)
    local row={at=now(),mood_cooldown=df.global.plotinfo.mood_cooldown,
        artifact_count=df.global.plotinfo.tasks.num_artifacts,units={}}
    for _,unit in ipairs(df.global.world.units.active) do
        if citizen(unit) and (unit.flags1.has_mood or by_id(result.moody_units,unit.id)) then
            local value=unit_snapshot(unit)
            row.units[#row.units+1]=value
            if unit.flags1.has_mood and not by_id(result.moody_units,unit.id) then
                result.moody_units[#result.moody_units+1]={id=unit.id,hfid=unit.hist_figure_id,
                    first_observed=now(),initial=value}
            end
        end
    end
    local previous=result.samples[#result.samples]
    -- Keep transitions and infrequent progress; do not emit thousands of identical polls.
    if not previous or not same(previous.units,row.units) or previous.at.year~=row.at.year
            or row.at.tick-previous.at.tick>=1200 then result.samples[#result.samples+1]=row end
    result.last_observation=row.at
    for _,record in ipairs(df.global.world.artifacts.all) do
        if not by_id(result.completed,record.id) then
            local value=completed(result,record)
            if value then result.completed[#result.completed+1]=value end
        end
    end
    if #result.completed>0 and result.stage=='observing' then result.stage='native_completion_observed' end
    write(result)
    return result
end
local function physical_snapshot(record)
    local item=record.item
    local reference=assert(dfhack.items.getGeneralRef(item,df.general_ref_type.IS_ARTIFACT),'missing native artifact reference')
    local profile=facts.read(item)
    local material=dfhack.matinfo.decode(item:getActualMaterial(),item:getActualMaterialIndex())
    local result={artifact_id=record.id,item_id=item.id,maker_hfid=item:getMaker(),type=item:getType(),
        subtype=item:getSubtype(),mat_type=item:getActualMaterial(),mat_index=item:getActualMaterialIndex(),
        material=material and utf(material:getToken()) or '',quality=item:getQuality(),wear=item:getWear(),
        stack_size=item:getStackSize(),dimension=item:getTotalDimension(),artifact=item.flags.artifact,
        artifact_mood=item.flags.artifact_mood,link_id=reference.artifact_id,
        signature=utf(profile.signature),description=utf(dfhack.items.getDescription(item,0,true)),improvements={}}
    if df.item_constructed:is_instance(item) then
        for _,improvement in ipairs(item.improvements) do
            result.improvements[#result.improvements+1]={type=improvement:getType(),mat_type=improvement.mat_type,
                mat_index=improvement.mat_index,quality=improvement.quality,maker=improvement.maker}
        end
    end
    return result
end
local name_vectors={figure=function()return df.global.world.history.figures end,
    site=function()return df.global.world.world_data.sites end,
    entity=function()return df.global.world.entities.all end,
    artifact=function()return df.global.world.artifacts.all end}
local finders={figure=df.historical_figure.find,site=df.world_site.find,
    entity=df.historical_entity.find,artifact=df.artifact_record.find}
local function unrelated_names(except)
    local result={}
    for _,kind in ipairs{'figure','site','entity','artifact'} do
        for _,object in ipairs(name_vectors[kind]()) do
            if kind~='artifact' or object.id~=except then
                result[#result+1]={kind=kind,id=object.id,name=name_snapshot(object.name)}
            end
        end
    end
    return result
end
local function selected(result)
    assert(result.selected_id,'use select after a verified native completion')
    local record=assert(df.artifact_record.find(result.selected_id),'selected native artifact disappeared')
    local value,err=completed(result,record)
    assert(value,err)
    return record,value
end
local function verify_preservation(result,record)
    assert(result.before,'run snapshot before using the naming GUI')
    assert(same(result.before.physical,physical_snapshot(record)),'physical item, maker, materials or linkage changed')
    assert(same(result.before.event,event_snapshot(assert(creation_event(record.id)))),'native creation history changed')
    for _,entry in ipairs(result.before.unrelated_names) do
        local object=assert(finders[entry.kind](entry.id),'unrelated named object disappeared')
        assert(same(entry.name,name_snapshot(object.name)),'unrelated '..entry.kind..' '..entry.id..' name changed')
    end
end
local function brief(result)
    print(json.encode({stage=result.stage,moody_units=#result.moody_units,completed=#result.completed,
        selected_id=result.selected_id,last_observation=result.last_observation,report=path}))
end

if mode=='baseline' then
    assert(df.global.pause_state,'pause for the initial lifecycle baseline')
    local existing=io.open(path)
    if existing then existing:close();error('baseline already exists; preserve it before starting another lifecycle run') end
    local result={schema_version=1,stage='observing',site_id=ctx.site,civ_id=ctx.civ,baseline_at=now(),
        setup_note=argument or 'Consult recorded setup commands; no interventions are inferred by this observer.',
        observer_policy='Read-only snapshots. Trigger provenance must be established by the separate command log.',
        baseline_artifact_ids={},baseline_last_event_id=-1,baseline_citizens={},moody_units={},samples={},completed={}}
    for _,record in ipairs(df.global.world.artifacts.all) do result.baseline_artifact_ids[#result.baseline_artifact_ids+1]=record.id end
    for _,event in ipairs(df.global.world.history.events) do result.baseline_last_event_id=math.max(result.baseline_last_event_id,event.id) end
    for _,unit in ipairs(df.global.world.units.active) do
        if citizen(unit) then
            assert(not unit.flags1.has_mood,'baseline must precede all active strange moods')
            result.baseline_citizens[#result.baseline_citizens+1]=unit_snapshot(unit)
        end
    end
    package.loaded[edit_process_key]=true
    write(result);brief(observe(result));return
elseif mode=='stop' then
    local state=package.loaded[watch_key];if state then state.active=false end
    print('Observer stopped; no game state changed.');return
elseif mode=='watch' then
    local interval=argument and tonumber(argument) or 25
    assert(interval and interval%1==0 and interval>=1 and interval<=1200,'watch interval must be 1–1200 ticks')
    local old=package.loaded[watch_key];if old then old.active=false end
    local state={active=true};package.loaded[watch_key]=state
    local function sample()
        if not state.active then return end
        if not dfhack.isMapLoaded() or df.global.plotinfo.site_id~=ctx.site then state.active=false;return end
        local ok,err=xpcall(function()
            local result=observe(read())
            if #result.completed>0 then state.active=false;brief(result)
            else dfhack.timeout(interval,'ticks',sample) end
        end,debug.traceback)
        if not ok then
            state.active=false
            local result=read();result.observer_error=utf(tostring(err));write(result)
            dfhack.printerr(err)
        end
    end
    sample();print('Read-only observer armed; root controls simulation and pause.');return
end

local result=read()
if mode=='observe' then brief(observe(result));return end
assert(df.global.pause_state,'pause before selecting or checking the artifact')
if mode=='select' then
    result=observe(result)
    assert(#result.completed>0,'No verified native artifact completion observed; this is not a pass.')
    local id=argument and tonumber(argument) or result.completed[1].id
    assert(id and by_id(result.completed,id),'requested artifact has no observed native completion')
    result.selected_id=id;result.stage='selected_native_artifact';write(result);brief(result);return
end
local record=selected(result)
if mode=='snapshot' then
    assert(not result.before,'pre-edit snapshot already exists; it must not be overwritten')
    result.before={at=now(),physical=physical_snapshot(record),event=event_snapshot(assert(creation_event(record.id))),
        name=name_snapshot(record.name),text=utf(dfhack.translation.translateName(record.name)),
        description=utf(dfhack.items.getReadableDescription(record.item)),unrelated_names=unrelated_names(record.id)}
    result.stage='ready_for_gui';write(result);brief(result);return
end
assert(mode=='cancel' or mode=='check' or mode=='reload','use baseline, observe, watch, stop, select, snapshot, cancel, check or reload')
verify_preservation(result,record)
local current=name_snapshot(record.name)
local text=utf(dfhack.translation.translateName(record.name))
local description=utf(dfhack.items.getReadableDescription(record.item))
assert(description:find(text,1,true),'artifact name is absent from the actual native item description')
if mode=='cancel' then
    assert(same(result.before.name,current),'cancel changed the native name')
    result.cancel_verified_at=now();result.cancel_result='PASS'
elseif mode=='check' then
    assert(result.cancel_result=='PASS','verify actual GUI cancellation before checking acceptance')
    assert(not same(result.before.name,current) and text~=result.before.text,'no changed artifact name has been accepted')
    result.accepted={at=now(),name=current,text=text,description=description}
    result.stage='accepted_before_save'
    package.loaded[edit_process_key]=true
else
    assert(not package.loaded[edit_process_key],'reload must run in a fresh game process, not the editing process')
    assert(result.accepted,'check an accepted GUI name before reload verification')
    assert(same(result.accepted.name,current) and result.accepted.text==text,'accepted native name did not persist')
    assert(result.accepted.description==description,'accepted item description did not persist')
    result.reload_verified_at=now();result.reload_result='PASS';result.stage='reload_verified'
    result.reload_scope='Native data persistence verified outside the marked editing Lua process; launcher log records the process restart.'
end
write(result);brief(result)
