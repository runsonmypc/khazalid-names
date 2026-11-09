-- Development-only native name/persistence test, on this feature's own disposable fort.
assert(os.getenv('FORTHAMMER_PROBE_LAB'), 'isolated lab only')
local adapter=reqscript('internal/forthammer-names/adapter')
local core=reqscript('internal/forthammer-names/core')
local json=require('json')
local ctx=assert(adapter.eligibility())
local mode=... or 'edit'
local path=os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-edits.json'
local function read() local f=assert(io.open(path)); local s=f:read('*a'); f:close(); return json.decode(s) end
local function name(n) return dfhack.translation.translateName(n) end
if mode=='reload' then
 local saved=read()
 assert(name(df.world_site.find(ctx.site).name)==saved.site_after,'site did not persist')
 local unit=assert(df.unit.find(saved.unit_id))
 assert(name(unit.name)==saved.unit_after,'unit did not persist')
 assert(name(unit.status.current_soul.name)==saved.unit_after,'soul did not persist')
 assert(name(df.historical_figure.find(unit.hist_figure_id).name)==saved.unit_after,'histfig did not persist')
 print('PASS native save/reload site, unit, soul and historical figure names')
 return
end
local site=df.world_site.find(ctx.site)
local old_site=name(site.name)
local item=assert(core.generate('hold',math.random))
local proposal=assert(adapter.preview('site',ctx.site,item))
assert(name(site.name)==old_site,'preview changed site')
-- Discard/cancel leaves native name intact, then accept a fresh preview.
proposal=nil
assert(name(site.name)==old_site,'cancel changed site')
proposal=assert(adapter.preview('site',ctx.site,item))
assert(adapter.accept(proposal))
local new_site=name(site.name)
assert(new_site~=old_site,'site did not change')
assert(not adapter.accept(proposal),'stale site proposal accepted twice')
local unit
for _,u in ipairs(df.global.world.units.active) do
 if u.civ_id==ctx.civ and df.global.world.raws.creatures.all[u.race].creature_id=='DWARF' then unit=u;break end
end
assert(unit,'no dwarf')
local old_unit=name(unit.name)
local category=unit.sex==0 and 'forename-female' or 'forename-male'
local up,err=adapter.suggest('unit',unit.id,category,math.random);assert(up,err)
assert(up.item.name:lower()~=unit.name.first_name,'suggestion repeated current forename')
local nickname=unit.name.nickname
local last=dfhack.translation.translateName(unit.name,false,true)
assert(name(unit.name)==old_unit,'unit preview mutated')
assert(adapter.accept(up))
local new_unit=name(unit.name)
assert(new_unit==up.new_text,'accepted name differs from displayed suggestion')
assert(unit.name.nickname==nickname and dfhack.translation.translateName(unit.name,false,true)==last,'other components changed')
assert(name(unit.status.current_soul.name)==new_unit,'soul not synchronized')
assert(name(df.historical_figure.find(unit.hist_figure_id).name)==new_unit,'histfig not synchronized')
assert(not adapter.accept(up),'stale unit proposal accepted twice')
-- Actual rejection branches with temporarily substituted providers, restored immediately.
local scripts=require('script-manager');local mods=scripts.get_active_mods
scripts.get_active_mods=function() return {} end
local ok,res=pcall(adapter.eligibility);scripts.get_active_mods=mods
assert(ok and not res,'unrelated world accepted')
local out={site_id=ctx.site,site_before=old_site,site_after=new_site,unit_id=unit.id,unit_before=old_unit,unit_after=new_unit,
 unit_suggestion='PASS (finite suggestion accepted exactly as previewed)',preview_cancel='PASS',stale='PASS',synchronization='PASS',unrelated_guard='PASS (provider substitution)'}
local f=assert(io.open(path,'w'));f:write(json.encode(out));f:close();print(json.encode(out))
