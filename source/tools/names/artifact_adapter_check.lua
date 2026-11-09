-- Native artifact edits in a paused disposable fortress. Every fixture and
-- borrowed item property is restored even when an assertion fails.
assert(os.getenv('FORTHAMMER_PROBE_LAB'), 'private lab only')
assert(df.global.pause_state, 'pause before temporary artifact fixtures')
local adapter = reqscript('internal/forthammer-names/adapter')
local core = reqscript('internal/forthammer-names/core')
local targets = reqscript('internal/forthammer-names/targets')
local facts = reqscript('internal/forthammer-names/artifact-facts')
local fit = reqscript('internal/forthammer-names/artifact-fit')
local json = require('json')
local ctx = assert(adapter.eligibility())
local cleanup, assertions, guards = {}, 0, {}
local function check(value, message)
    assert(value, message)
    assertions = assertions+1
end
local function allocated(object)
    cleanup[#cleanup+1] = function() object:delete() end
    return object
end
local function append(vector,object)
    vector:insert('#',object)
    cleanup[#cleanup+1] = function()
        assert(vector[#vector-1] == object, 'fixture vector order changed')
        vector:erase(#vector-1)
    end
end
local function snapshot(name)
    local result = {name.first_name,name.nickname,name.language,name.type,name.has_name}
    for i=0,6 do result[#result+1]=name.words[i]; result[#result+1]=name.parts_of_speech[i] end
    return json.encode(result)
end
local function name_as(name,value)
    for _,key in ipairs{'first_name','nickname','language','type','has_name'} do name[key]=value[key] end
    for i=0,6 do name.words[i]=value.words[i]; name.parts_of_speech[i]=value.parts_of_speech[i] end
end
local function replace_literal(text,old,new)
    local out, position = {}, 1
    while true do
        local first,last = text:find(old,position,true)
        if not first then out[#out+1]=text:sub(position); return table.concat(out) end
        out[#out+1]=text:sub(position,first-1);out[#out+1]=new;position=last+1
    end
end
local report = {result='PASS',guards=guards}
local ok,err = xpcall(function()
    local maker
    for _,figure in ipairs(df.global.world.history.figures) do
        if figure.civ_id == ctx.civ and figure.race == df.global.plotinfo.race_id then
            maker=figure.id;break
        end
    end
    check(maker ~= nil, 'no verified Dwarf maker fixture')
    local weapons = {}
    for _,item in ipairs(df.global.world.items.all) do
        if df.item_weaponst:is_instance(item) and item.subtype and not item.flags.artifact
                and not item.flags.garbage_collect
                and not dfhack.items.getGeneralRef(item,df.general_ref_type.IS_ARTIFACT) then
            weapons[#weapons+1] = item
            if #weapons == 2 then break end
        end
    end
    check(#weapons == 2, 'need two initialized native weapons for item-replacement guard')
    local item, replacement = weapons[1],weapons[2]
    local next_id = 1000000
    for _,record in ipairs(df.global.world.artifacts.all) do next_id=math.max(next_id,record.id+1) end
    local record = allocated(df.artifact_record:new())
    record.id,record.item = next_id,item
    record.name.type,record.name.has_name = df.language_name_type.Artifact,true
    record.name.first_name = 'fixture artifact original'
    record.name.nickname = ''
    for i=0,6 do record.name.words[i]=-1;record.name.parts_of_speech[i]=df.part_of_speech.Noun end

    for _,weapon in ipairs(weapons) do
        local old_maker,old_artifact,old_crafted = weapon:getMaker(),weapon.flags.artifact,weapon.flags.artifact_mood
        local old_description,old_signature = dfhack.items.getReadableDescription(weapon),facts.read(weapon).signature
        local old_subtype,old_type,old_index = weapon.subtype,weapon.mat_type,weapon.mat_index
        cleanup[#cleanup+1] = function()
            weapon:setMaker(old_maker);weapon.flags.artifact=old_artifact;weapon.flags.artifact_mood=old_crafted
            weapon.subtype=old_subtype;weapon.mat_type=old_type;weapon.mat_index=old_index
            assert(facts.read(weapon).signature == old_signature, 'borrowed item facts not restored')
            assert(dfhack.items.getReadableDescription(weapon) == old_description, 'borrowed native description not restored')
        end
        weapon:setMaker(maker);weapon.flags.artifact=true
        local link = allocated(df.general_ref_is_artifactst:new())
        link.artifact_id=record.id
        append(weapon.general_refs,link)
    end
    append(df.global.world.artifacts.all,record)
    check(targets.resolve('artifact',record.id,ctx).object.item == item, 'native artifact linkage missing')
    local original = snapshot(record.name)
    local function proposal()
        return assert(adapter.suggest('artifact',record.id,'artifact',function()return 1 end))
    end
    -- The full picker makes weaker fits reachable without consuming the best
    -- title. Listing and inspecting alternatives never writes or reserves names.
    local options = assert(adapter.artifact_options(record.id,function(n)return n end))
    local option_names, lower = {}, nil
    for index,option in ipairs(options.options) do
        check(not option_names[option.item.name], 'duplicate alternative')
        option_names[option.item.name]=true
        if option.tier ~= 'Best fit' and not lower then lower=index end
    end
    check(lower ~= nil, 'no lower tier available despite neutral imagery')
    local alternative = assert(adapter.preview_option(options,lower))
    check(alternative.item.name == options.options[lower].item.name, 'wrong alternative previewed')
    check(snapshot(record.name) == original, 'alternative inspection changed name')
    local old_nickname=record.name.nickname
    record.name.nickname='fixture changed name'
    check(not adapter.preview_option(options,lower), 'stale list name accepted')
    record.name.nickname=old_nickname
    local old_material=item.mat_index
    local copper=assert(dfhack.matinfo.find('INORGANIC:COPPER'))
    local iron=assert(dfhack.matinfo.find('INORGANIC:IRON'))
    item.mat_index=old_material == copper.index and iron.index or copper.index
    check(not adapter.preview_option(options,lower), 'stale list material accepted')
    item.mat_index=old_material
    check(adapter.accept(assert(adapter.preview_option(options,lower))), 'lower-tier acceptance failed')
    name_as(record.name,alternative.before[1])
    check(snapshot(record.name) == original, 'list test failed to restore name')
    guards.complete_alternatives_and_stale_list=true
    local started=os.clock()
    for _=1,50 do assert(adapter.artifact_options(record.id,function(n)return n end)) end
    report.alternative_listing={iterations=50,cpu_seconds=os.clock()-started,
        choices=#options.options,name_unchanged=snapshot(record.name)==original}
    local gui_check=assert(loadfile(assert(dfhack.findScript('fh-quality-gui-quality-check'))))()
    local gui_before=proposal().before[1]
    report.gui=gui_check(record,snapshot)
    name_as(record.name,gui_before)
    check(snapshot(record.name)==original,'GUI fixture name restoration failed')
    local p = proposal()
    check(snapshot(record.name) == original, 'preview changed native name')
    p = nil
    check(snapshot(record.name) == original, 'cancel changed native name')
    p = proposal()
    local profile = facts.read(item)
    check(p.artifact_signature == profile.signature and p.fit_text == fit.explain(p.item,profile),
        'preview did not capture actual item facts')
    local best,occupied = -1,{}
    for _,row in ipairs(targets.occupied('artifact',ctx)) do occupied[core.normalize(row.name)]=true end
    for _,candidate in ipairs(core.candidates('artifact')) do
        if not occupied[core.normalize(candidate.name)] then
            local score=fit.assess(candidate,profile)
            best=math.max(best,score)
        end
    end
    check(fit.assess(p.item,profile) == best, 'adapter did not use strongest available fit')
    report.initial_fit = {name=p.item.name,score=best,explanation=p.fit_text}

    -- Direct previews and acceptance must enforce the same compatibility gate
    -- as random suggestions; caller-supplied roots cannot hide a mismatch.
    for _,name in ipairs{'Drakkagrul','Durazdok'} do
        local candidate
        for _,entry in ipairs(core.candidates('artifact')) do
            if entry.name == name then candidate=entry;break end
        end
        assert(candidate,'missing incompatible regression candidate '..name)
        local forged_type={name=candidate.name,token=candidate.token,roots={'bryn','dok'}}
        local rejected,reason=adapter.preview('artifact',record.id,forged_type)
        check(not rejected and reason:find('unsupported item properties',1,true),
            'direct preview admitted unsupported concrete words: '..name)
        local pending=proposal();pending.item=forged_type
        local accepted,accept_error=adapter.accept(pending)
        check(not accepted and accept_error:find('unsupported item properties',1,true),
            'acceptance bypassed concrete compatibility: '..name)
        check(snapshot(record.name)==original,'rejected concrete title changed native name')
    end
    guards.direct_incompatible_type_and_material_rejected=true

    local forged = {name=p.item.name,token=p.item.token,roots={'invented'},
        gloss='invented meaning',sources={'invented source'},status='invented history'}
    local canonical = assert(adapter.preview('artifact',record.id,forged))
    check(canonical.item ~= forged and canonical.item.gloss == p.item.gloss
        and canonical.item.status == p.item.status
        and json.encode(canonical.item.roots) == json.encode(p.item.roots)
        and json.encode(canonical.item.sources) == json.encode(p.item.sources),
        'caller metadata was not replaced with reviewed catalog metadata')
    check(canonical.fit_text == p.fit_text and snapshot(record.name) == original,
        'forged roots affected fit evidence or changed the native name')
    guards.forged_metadata_canonicalized=true
    canonical.item.gloss='fixture forged proposal meaning'
    canonical.item.roots[1]='fixture invented root'
    canonical.item.sources[1]='fixture invented source'
    local isolated = assert(adapter.preview('artifact',record.id,canonical.item))
    check(isolated.item.gloss == p.item.gloss and isolated.fit_text == p.fit_text
        and json.encode(isolated.item.roots) == json.encode(p.item.roots)
        and json.encode(isolated.item.sources) == json.encode(p.item.sources),
        'proposal metadata aliases or contaminates the reviewed catalog')
    guards.proposal_metadata_isolated=true

    local function stale(label,change,restore)
        local before = snapshot(record.name)
        local pending = proposal()
        local call_ok,accepted,reason,changed
        local scope_ok,scope_error = xpcall(function()
            change()
            changed = facts.read(record.item).signature ~= pending.artifact_signature
            call_ok,accepted,reason = pcall(adapter.accept,pending)
        end,debug.traceback)
        restore()
        assert(scope_ok,scope_error)
        check(changed, label..' did not change the observed item context')
        check(call_ok and not accepted and (reason:find('item properties changed',1,true)
                or reason:find('unsupported item properties',1,true)),
            'stale '..label..' accepted or wrong rejection: '..tostring(reason))
        check(snapshot(record.name) == before, 'stale '..label..' changed native name')
        guards[label]=true
    end
    local original_type,original_index = item.mat_type,item.mat_index
    local alternate = assert(dfhack.matinfo.find('INORGANIC:COPPER'))
    if original_type == alternate.type and original_index == alternate.index then
        alternate=assert(dfhack.matinfo.find('INORGANIC:IRON'))
    end
    stale('body_material_changed',function() item.mat_type=alternate.type;item.mat_index=alternate.index end,
        function() item.mat_type=original_type;item.mat_index=original_index end)
    local subtype = item.subtype
    local changed_subtype
    for _,definition in ipairs(df.global.world.raws.itemdefs.weapons) do
        if definition ~= subtype and definition.id == 'ITEM_WEAPON_HAMMER_WAR' then changed_subtype=definition;break end
    end
    if not changed_subtype then
        for _,definition in ipairs(df.global.world.raws.itemdefs.weapons) do
            if definition ~= subtype and definition.id == 'ITEM_WEAPON_AXE_BATTLE' then changed_subtype=definition;break end
        end
    end
    check(changed_subtype ~= nil, 'no distinct supported weapon subtype fixture')
    stale('weapon_subtype_changed',function()item.subtype=changed_subtype end,function()item.subtype=subtype end)
    stale('linked_item_replaced',function()record.item=replacement end,function()record.item=item end)

    -- A real native image decoration exercises the fact snapshot at acceptance.
    -- Its material must never become the primary body-material evidence.
    local chunks = df.global.world.art_image_chunks.all
    local chunk = allocated(df.art_image_chunk:new())
    chunk.id = #chunks > 0 and chunks[#chunks-1].id+1 or 0
    append(chunks,chunk)
    local picture = allocated(df.art_image:new())
    chunk.images[0].art_image=picture
    cleanup[#cleanup+1]=function()chunk.images[0].art_image=nil end
    local dragon,giant
    for index,raw in ipairs(df.global.world.raws.creatures.all) do
        if raw.creature_id == 'STAR_DRAGON' then dragon=index end
        if raw.creature_id == 'GIANT' or raw.creature_id == 'GIANT_CIV' then giant=index end
    end
    check(dragon ~= nil and giant ~= nil, 'missing exact creature raw fixtures')
    local element = allocated(df.art_image_element_creaturest:new())
    element.race,element.caste,element.count=dragon,0,1
    append(picture.elements,element)
    local improvement = allocated(df.itemimprovement_art_imagest:new())
    local gold = assert(dfhack.matinfo.find('INORGANIC:GOLD'))
    improvement.mat_type,improvement.mat_index=gold.type,gold.index
    improvement.image.id,improvement.image.subid=chunk.id,0
    append(item.improvements,improvement)
    check(facts.read(item).facts.image.drakk ~= nil, 'real image fixture not read')
    local pictured = proposal()
    report.depicted_fit = {name=pictured.item.name,explanation=pictured.fit_text,
        score=fit.assess(pictured.item,facts.read(item))}
    stale('depicted_creature_changed',function()element.race=giant end,function()element.race=dragon end)
    stale('depicted_count_changed',function()element.count=0 end,function()element.count=1 end)
    stale('image_reference_changed',function()improvement.image.subid=1 end,function()improvement.image.subid=0 end)
    stale('decoration_material_changed',function()improvement.mat_index=alternate.index end,
        function()improvement.mat_index=gold.index end)

    -- An occupied native record reserves its name even without an editable item.
    local blocker = allocated(df.artifact_record:new())
    blocker.id=next_id+1
    append(df.global.world.artifacts.all,blocker)
    local pending = proposal()
    name_as(blocker.name,pending.after)
    local before = snapshot(record.name)
    local accepted,reason = adapter.accept(pending)
    check(not accepted and reason:find('already in use',1,true), 'new occupied name was accepted')
    check(snapshot(record.name) == before, 'collision rejection changed native name')
    check(proposal().item.name ~= pending.item.name, 'suggestion ignored occupied artifact record')
    guards.new_collision=true

    local final = proposal()
    local physical_before = facts.read(item).signature
    local old_name = dfhack.translation.translateName(record.name)
    local old_display = old_name..', '..dfhack.translation.translateName(record.name,true)
    local description_before = dfhack.items.getReadableDescription(item)
    local physical_description_before = dfhack.items.getDescription(item,0,true)
    check(description_before:find(old_name,1,true) ~= nil, 'fixture name not visible on linked native item')
    local final_gloss,final_roots = final.item.gloss,json.encode(final.item.roots)
    final.item.gloss='fixture forged acceptance meaning';final.item.roots[1]='fixture invented root'
    local refreshed = assert(adapter.preview('artifact',record.id,final.item))
    check(refreshed.item.gloss == final_gloss and json.encode(refreshed.item.roots) == final_roots,
        'mutated proposal metadata reached a subsequent canonical preview')
    check(adapter.accept(final), 'explicit artifact acceptance failed')
    local new_name = dfhack.translation.translateName(record.name)
    local new_display = new_name..', '..dfhack.translation.translateName(record.name,true)
    local description_after = dfhack.items.getReadableDescription(item)
    check(new_name == final.new_text, 'accepted name differs from displayed proposal')
    check(description_after:find(new_name,1,true) ~= nil, 'native item omitted accepted artifact name')
    -- DFHack 53.14-r2 Items.cpp get_base_desc renders both native and English
    -- titles before the type. Both title renderings legitimately change here.
    check(description_before:sub(1,#old_display) == old_display
        and description_after:sub(1,#new_display) == new_display,
        'readable description lacks the documented native/English title prefix')
    local normalized_description=replace_literal(description_after,new_display,old_display)
    check(normalized_description == description_before,
        'physical description changed beyond the artifact name: '..json.encode({
            before=description_before,after=description_after,normalized=normalized_description,
            old_name=old_name,new_name=new_name,old_display=old_display,new_display=new_display}))
    check(dfhack.items.getDescription(item,0,true) == physical_description_before,
        'physical item description or quality changed during name acceptance')
    check(facts.read(item).signature == physical_before, 'acceptance changed physical item facts')
    check(record.item == item and item:getMaker() == maker and item.flags.artifact
        and dfhack.items.getGeneralRef(item,df.general_ref_type.IS_ARTIFACT).artifact_id == record.id,
        'acceptance changed maker or native artifact linkage')
    check(not adapter.accept(final), 'accepted proposal replayed successfully')
    check(proposal().item.name ~= new_name, 'suggestion repeated current artifact name')
    report.accepted = {name=new_name,description=description_after,
        physical_description=physical_description_before,physical_state_preserved=true,
        linkage_preserved=true,replay_rejected=true,current_name_excluded=true}

    -- The new carving sense depends on BOTH actual shape and primary material.
    -- Exercise its invalidation through the real adapter, not just the reader.
    local carving=allocated(df.item_statuest:new())
    carving.id=-1;carving:setMaker(maker);carving.flags.artifact=true
    local stone=assert(dfhack.matinfo.find('INORGANIC:GRANITE'))
    carving:setMaterial(stone.type);carving:setMaterialIndex(stone.index)
    local carving_link=allocated(df.general_ref_is_artifactst:new())
    carving_link.artifact_id=record.id;append(carving.general_refs,carving_link)
    record.item=carving
    cleanup[#cleanup+1]=function()record.item=item end
    local carved=proposal()
    check(carved.fit_text:find('stone carving',1,true) or carved.fit_text:find('statue',1,true),
        'stone statue proposal lacks observed type')
    stale('stone_carving_material_changed',function()
        carving:setMaterial(gold.type);carving:setMaterialIndex(gold.index)
    end,function()
        carving:setMaterial(stone.type);carving:setMaterialIndex(stone.index)
    end)
    check(facts.read(carving).facts.type.agrul,'stone carving fact not restored')
    report.carving_fit={name=carved.item.name,explanation=carved.fit_text}
end,debug.traceback)
local cleanup_errors = {}
for i=#cleanup,1,-1 do
    local cleaned,problem = pcall(cleanup[i])
    if not cleaned then cleanup_errors[#cleanup_errors+1]=tostring(problem) end
end
assert(#cleanup_errors == 0, 'fixture cleanup failed: '..table.concat(cleanup_errors,'; '))
assert(ok,err)
report.assertions=assertions
report.cleanup='All temporary native records/images/references removed; borrowed items restored.'
local f = assert(io.open(os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-artifact-adapter.json','w'))
f:write(json.encode(report));f:close();print(json.encode(report))
