-- Private save/UI fixture only. This creates a linked named-item fixture when
-- needed; it is not evidence that DF's artifact-creation mechanics ran.
local lab = assert(os.getenv('FORTHAMMER_PROBE_LAB'), 'private lab only')
assert(df.global.pause_state, 'pause before artifact persistence checks')
local mode,requested_item = ...
mode = mode or 'setup'
requested_item = requested_item and tonumber(requested_item)
assert(mode == 'setup' or mode == 'check' or mode == 'reload', 'use setup [item-id], check, or reload')
local adapter = reqscript('internal/forthammer-names/adapter')
local targets = reqscript('internal/forthammer-names/targets')
local facts = reqscript('internal/forthammer-names/artifact-facts')
local json = require('json')
local ctx = assert(adapter.eligibility())
local path = lab..'/results/names-artifact-persistence.json'
local function read()
    local f=assert(io.open(path));local value=f:read('*a');f:close();return json.decode(value)
end
local function write(value)
    local f=assert(io.open(path,'w'));f:write(json.encode(value));f:close()
end
local function name_snapshot(name)
    local result = {name.first_name,name.nickname,name.language,name.type,name.has_name}
    for i=0,6 do result[#result+1]=name.words[i];result[#result+1]=name.parts_of_speech[i] end
    return result
end
local function verified_maker(item)
    local maker=df.historical_figure.find(item:getMaker())
    local race=maker and maker.race >= 0 and df.global.world.raws.creatures.all[maker.race]
    return race and race.creature_id == 'DWARF' and maker.civ_id == ctx.civ
end
if mode == 'setup' then
    local existing_file=io.open(path)
    if existing_file then
        existing_file:close()
        local saved=read()
        if saved.site_id == ctx.site and df.artifact_record.find(saved.artifact_id) then
            error('Persistence fixture already recorded; use check/reload or choose a fresh results directory.')
        end
    end
    local record,fixture
    for _,candidate in ipairs(df.global.world.artifacts.all) do
        local target=targets.resolve('artifact',candidate.id,ctx)
        if target and (not requested_item or candidate.item.id == requested_item) then
            record,fixture=candidate,'Existing eligible native artifact; its existing maker and linkage are retained.'
            break
        end
    end
    local created,original_flag,link,item,old_counter
    if not record then
        for _,candidate in ipairs(df.global.world.items.all) do
            if (not requested_item or candidate.id == requested_item)
                    and df.item_weaponst:is_instance(candidate) and candidate.subtype
                    and not candidate.flags.artifact and not candidate.flags.garbage_collect
                    and not dfhack.items.getGeneralRef(candidate,df.general_ref_type.IS_ARTIFACT)
                    and verified_maker(candidate) then
                item=candidate;break
            end
        end
        assert(item, 'No initialized weapon with an already verified Dwarf maker. Create a private test item through dfhack.items.createItem using a real citizen; do not rewrite an existing maker.')
        -- Symbol name is verified in the matching DFHack hack/symbols.xml.
        old_counter=df.global.artifact_next_id
        assert(type(old_counter) == 'number' and old_counter >= 0, 'missing native artifact ID counter')
        local all=df.global.world.artifacts.all
        assert(#all == 0 or old_counter > all[#all-1].id, 'native artifact counter is not above existing IDs')
        record=df.artifact_record:new()
        record.id,record.item=old_counter,item
        record.name.type,record.name.has_name=df.language_name_type.Artifact,true
        record.name.first_name='private fixture'
        record.name.nickname=''
        for i=0,6 do record.name.words[i]=-1;record.name.parts_of_speech[i]=df.part_of_speech.Noun end
        -- Unknown location/claim fields stay unknown; only the loaded site is
        -- established. No owner, historical event, claim or achievement is made.
        for _,field in ipairs{'abs_tile_x','abs_tile_y','abs_tile_z','last_local_bld_id',
            'structure_local','site_building_profile','subregion','feature_layer','owner_hf',
            'storage_structure_local','loss_region','last_layer','holder_hf','year','season_tick'} do
            record[field]=-1
        end
        record.site,record.storage_site=ctx.site,ctx.site
        link=df.general_ref_is_artifactst:new();link.artifact_id=record.id
        original_flag=item.flags.artifact
        item.general_refs:insert('#',link);all:insert('#',record)
        item.flags.artifact=true;df.global.artifact_next_id=old_counter+1
        created=true
        fixture='Artificial named-item fixture using an initialized native weapon and its unchanged verified maker. Not a native artifact-creation-mechanic test.'
    end
    local ok,result=xpcall(function()
        local target=assert(targets.resolve('artifact',record.id,ctx))
        local physical=target.object.item
        local profile=facts.read(physical)
        assert(next(profile.facts.type) or next(profile.facts.material), 'fixture lacks supported item facts')
        local proposal=assert(adapter.suggest('artifact',record.id,'artifact',function()return 1 end))
        local saved={stage='ready_for_gui',fixture=fixture,site_id=ctx.site,civ_id=ctx.civ,
            artifact_id=record.id,item_id=physical.id,maker_id=physical:getMaker(),
            original_name=dfhack.translation.translateName(record.name),
            original_name_snapshot=name_snapshot(record.name),physical_signature=profile.signature,
            original_description=dfhack.items.getReadableDescription(physical),
            physical_description=dfhack.items.getDescription(physical,0,true),
            offered_name=proposal.new_text,offered_fit=proposal.fit_text,
            artifact_mood=physical.flags.artifact_mood}
        write(saved)
        return saved
    end,debug.traceback)
    if not ok and created then
        item.flags.artifact=original_flag
        assert(df.global.world.artifacts.all[#df.global.world.artifacts.all-1] == record)
        df.global.world.artifacts.all:erase(#df.global.world.artifacts.all-1)
        assert(item.general_refs[#item.general_refs-1] == link)
        item.general_refs:erase(#item.general_refs-1)
        link:delete();record:delete();df.global.artifact_next_id=old_counter
    end
    assert(ok,result)
    print(json.encode(result))
    return
end

local saved=read()
assert(ctx.site == saved.site_id and ctx.civ == saved.civ_id, 'different fortress session loaded')
local target=assert(targets.resolve('artifact',saved.artifact_id,ctx))
local item=target.object.item
assert(item.id == saved.item_id and item:getMaker() == saved.maker_id, 'artifact item or original maker changed')
assert(item.flags.artifact and item.flags.artifact_mood == saved.artifact_mood, 'artifact flags changed')
assert(facts.read(item).signature == saved.physical_signature, 'physical item context changed')
assert(dfhack.items.getDescription(item,0,true) == saved.physical_description,
    'physical item description or quality changed')
assert(dfhack.items.getGeneralRef(item,df.general_ref_type.IS_ARTIFACT).artifact_id == saved.artifact_id,
    'artifact linkage changed')
local text=dfhack.translation.translateName(target.name)
local description=dfhack.items.getReadableDescription(item)
assert(description:find(text,1,true), 'accepted name absent from native item description')
if mode == 'check' then
    assert(text ~= saved.original_name, 'GUI has not accepted a different artifact name')
    saved.stage='accepted_before_save'
    saved.accepted_name=text
    saved.accepted_name_snapshot=name_snapshot(target.name)
    saved.accepted_description=description
    write(saved)
    print(json.encode({result='PASS',stage=saved.stage,artifact_id=saved.artifact_id,
        name=text,physical_state_preserved=true,original_maker_preserved=true}))
else
    assert(saved.stage == 'accepted_before_save' or saved.stage == 'fresh_process_reload_passed',
        'record an accepted GUI edit with check before reload validation')
    assert(text == saved.accepted_name, 'accepted name did not survive save/reload')
    assert(json.encode(name_snapshot(target.name)) == json.encode(saved.accepted_name_snapshot),
        'native name fields changed across save/reload')
    assert(description == saved.accepted_description, 'native description changed across save/reload')
    saved.stage='fresh_process_reload_passed';saved.reload_result='PASS';write(saved)
    print(json.encode({result='PASS',stage=saved.stage,artifact_id=saved.artifact_id,
        name=text,native_name_preserved=true,physical_state_preserved=true,
        linkage_preserved=true,original_maker_preserved=true}))
end
