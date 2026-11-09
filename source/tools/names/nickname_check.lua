-- Actual native nickname preferences and identities; restore every fixture.
assert(os.getenv('FORTHAMMER_PROBE_LAB'), 'private lab only')
assert(dfhack.isMapLoaded() and df.global.pause_state, 'load a paused disposable fortress')
local adapter = reqscript('internal/forthammer-names/adapter')
local core = reqscript('internal/forthammer-names/core')
local json = require('json')
local diagnose = (...) == 'diagnose'
local ctx = assert(adapter.eligibility())
local cleanup, assertions, observations = {}, 0, {}
local function check(value, message)
    assert(value, message)
    assertions = assertions + 1
end
local function saved(name)
    local copy = df.language_name:new()
    copy:assign(name)
    cleanup[#cleanup+1] = function() name:assign(copy); copy:delete() end
    return copy
end
local function snap(name)
    local out = {name.first_name,name.nickname,name.language,name.type,name.has_name}
    for i=0,6 do out[#out+1]=name.words[i];out[#out+1]=name.parts_of_speech[i] end
    return json.encode(out)
end
local function set(name, value)
    for _,field in ipairs{'first_name','nickname','language','type','has_name'} do name[field]=value[field] end
    for i=0,6 do name.words[i]=value.words[i];name.parts_of_speech[i]=value.parts_of_speech[i] end
end
local policy = df.global.d_init.display.nickname
local game, original_policy = df.global.gametype, policy[df.global.gametype]
cleanup[#cleanup+1] = function() policy[game] = original_policy end
local ok, err = xpcall(function()
    local unit
    for _,u in ipairs(df.global.world.units.active) do
        if u.civ_id == ctx.civ and u.race == df.global.plotinfo.race_id and (u.sex == 0 or u.sex == 1) then
            unit = u; break
        end
    end
    assert(unit, 'no named Dwarf')
    local names = {unit.name,assert(unit.status.current_soul).name,
        assert(df.historical_figure.find(unit.hist_figure_id)).name}
    local original = {}
    for i,name in ipairs(names) do original[i]=saved(name) end
    local other_unit, other_figure
    for _,u in ipairs(df.global.world.units.all) do if u.id ~= unit.id then other_unit=u;break end end
    for _,f in ipairs(df.global.world.history.figures) do if f.id ~= unit.hist_figure_id then other_figure=f;break end end
    assert(other_unit and other_figure, 'missing collision actors')
    local unit_before, figure_before = saved(other_unit.name), saved(other_figure.name)
    local category = unit.sex == 0 and 'forename-female' or 'forename-male'
    for _,mode in ipairs{'CENTRALIZE','REPLACE_FIRST','REPLACE_ALL'} do
        policy[game] = df.d_init_nickname[mode]
        for i,name in ipairs(names) do name:assign(original[i]);name.nickname='quality-selected' end
        local p = assert(adapter.suggest('unit',unit.id,category,function() return 1 end))
        local before = {};for i,name in ipairs(names) do before[i]=snap(name) end
        local row = {preview_distinct=p.old_text~=p.new_text,old=p.old_text,new=p.new_text}
        -- Discarded previews leave all native copies untouched.
        for i,name in ipairs(names) do check(snap(name)==before[i], 'preview mutated identity') end
        if not diagnose then
            check(row.preview_distinct, 'nickname hides preview change: '..mode)
            check(p.new_text:find(p.item.name,1,true), 'preview omits actual new forename')
            check(p.old_text:lower():find(unit.name.first_name,1,true), 'preview omits old forename')
            local full = reqscript('internal/forthammer-names/native').full_name
            local copy = df.language_name:new();copy:assign(unit.name);copy.nickname=''
            local expected = dfhack.translation.translateName(copy);copy:delete()
            check(full(unit.name)==expected, 'full name differs from native nickname-free render')
        end
        for label,object in pairs{unit=other_unit,figure=other_figure} do
            local restore = label=='unit' and unit_before or figure_before
            set(object.name,p.after);object.name.nickname='quality-hidden-'..label
            local blocked,why = adapter.preview('unit',unit.id,p.item)
            row[label..'_collision_rejected'] = not blocked and why:find('already in use',1,true)~=nil
            if not diagnose then
                check(row[label..'_collision_rejected'], 'hidden '..label..' identity collision: '..mode)
                local accepted,reason = adapter.accept(p)
                check(not accepted and reason:find('already in use',1,true), 'accept missed new hidden collision')
            end
            object.name:assign(restore)
        end
        if not diagnose then
            check(adapter.accept(p), 'valid nicknamed edit rejected')
            for i,name in ipairs(names) do
                check(name.first_name==p.item.name:lower() and name.nickname=='quality-selected', 'forename/nickname mismatch')
                name.first_name=original[i].first_name
                check(snap(name)==before[i], 'accepted edit changed another native field')
            end
            check(policy[game]==df.d_init_nickname[mode], 'shipping code changed display preference')
        end
        observations[mode] = row
    end
    if not diagnose then
        -- A nicknamed world site still reserves its full native name.
        local site = df.world_site.find(ctx.site)
        local other
        for _,s in ipairs(df.global.world.world_data.sites) do if s.id~=site.id then other=s;break end end
        assert(other);local old=saved(other.name)
        for _,mode in ipairs{'CENTRALIZE','REPLACE_FIRST','REPLACE_ALL'} do
            other.name:assign(old);policy[game]=df.d_init_nickname[mode]
            local p=assert(adapter.suggest('site',site.id,'hold',function()return 1 end))
            local before=snap(site.name)
            set(other.name,p.after);other.name.nickname='quality-hidden-site'
            local proposal,why=adapter.preview('site',site.id,p.item)
            check(not proposal and why:find('already in use',1,true), 'hidden site collision')
            local accepted,reason=adapter.accept(p)
            check(not accepted and reason:find('already in use',1,true), 'accept missed hidden site collision')
            check(snap(site.name)==before, 'site collision changed target')
        end
    end
end, debug.traceback)
for i=#cleanup,1,-1 do cleanup[i]() end
assert(ok, err)
check(policy[game]==original_policy, 'test did not restore preference')
local report={result=diagnose and 'DIAGNOSTIC' or 'PASS',assertions=assertions,
    policies=observations,coverage='Actual native names and display preferences; temporary edits restored, no save'}
local f=assert(io.open(os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-nickname-'..(diagnose and 'before' or 'after')..'.json','w'))
f:write(json.encode(report));f:close();print(json.encode(report))
