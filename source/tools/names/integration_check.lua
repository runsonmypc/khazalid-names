-- Repeated installation, nested failure cleanup, inactive-mod guard and timing.
assert(os.getenv('FORTHAMMER_PROBE_LAB'),'private lab only')
assert(dfhack.isMapLoaded() and df.global.pause_state,'load a paused disposable fortress')
local pools=reqscript('internal/forthammer-names/pools')
local installer=reqscript('forthammer-name-pools')
local core=reqscript('internal/forthammer-names/core')
local json=require('json')
local function selectors()
 local out={}
 local function append(t)
  for s=0,5 do
   out[#out+1]=table.concat({s,#t.words[s],#t.parts[s]},':')
   for i,w in ipairs(t.words[s]) do out[#out+1]=w..':'..t.parts[s][i] end
  end
 end
 local raw
 for _,r in ipairs(df.global.world.raws.entities.all) do if r.code=='MOUNTAIN' then raw=r;break end end
 assert(raw)
 for _,key in ipairs{'OTHER','CIV','SITE','LIBRARY','HOSPITAL','MERCHANT_COMPANY','CRAFT_GUILD','ROAD','TUNNEL','BRIDGE','WALL','MILITARY_UNIT'} do
  local cat=df.entity_name_type[key]
  append(raw.symbols.symbols_major[cat]);append(raw.symbols.symbols_minor[cat])
 end
 return table.concat(out,',')
end
local function names()
 local out={}
 for _,v in ipairs{{'unit',df.global.world.units.all},{'figure',df.global.world.history.figures},{'entity',df.global.world.entities.all},{'site',df.global.world.world_data.sites},{'squad',df.global.world.squads.all}} do
  for _,o in ipairs(v[2]) do out[v[1]..o.id]=dfhack.df2utf(dfhack.translation.translateName(o.name)) end
 end
 return json.encode(out)
end
print('integration: snapshot MOUNTAIN selectors and native names')
local before,names_before=selectors(),names()
local api=dfhack.translation.generateName
print('integration: repeated installation')
for _=1,5 do assert(installer.install());assert(selectors()==before,'installation changed selectors');assert(names()==names_before,'installation renamed something');assert(api==dfhack.translation.generateName,'API wrapper stacked') end
print('integration: nested cleanup')
local ok,err=pools.with_type('squad',function()
 local outer=selectors();assert(outer~=before,'squad scope absent')
 local inner_ok,inner_err=pools.with_type('hospital',function() assert(selectors()~=outer,'nested scope absent');error('intentional nested failure') end)
 assert(not inner_ok and inner_err:find('intentional nested failure'),'missing nested error')
 assert(selectors()==outer,'nested error lost outer scope')
 error('intentional outer failure')
end)
assert(not ok and err:find('intentional outer failure') and selectors()==before,'outer cleanup failed')
local scripts=require('script-manager')
local get_mods=scripts.get_active_mods
local raw=assert(pools.entity())
local lang=df.historical_entity.find(df.global.plotinfo.civ_id).name.language
local n=df.language_name:new()
print('integration: inactive-mod provider guard')
scripts.get_active_mods=function() return {} end
local inactive_ok,inactive_err=xpcall(function()
 assert(not installer.install(),'inactive installer accepted')
 assert(not pools.with_type('squad',function()error('must not call')end),'inactive scoped callback accepted')
 dfhack.translation.generateName(n,lang,df.language_name_type.Squad,raw.symbols.symbols_major[df.entity_name_type.OTHER],raw.symbols.symbols_minor[df.entity_name_type.OTHER])
 assert(df.global.world.raws.language.words[n.words.TheX].word:match('^FH_KHAZ_GIVEN_'),'inactive API replaced caller selectors')
 assert(selectors()==before and names()==names_before,'inactive guard changed world')
end,debug.traceback)
scripts.get_active_mods=get_mods;n:delete();assert(inactive_ok,inactive_err)
print('integration: 100-name batch benchmark')
local started=os.clock();local seen={}
for _,item in ipairs(assert(core.generate_batch('person-female',100,math.random))) do assert(not seen[item.name]);seen[item.name]=true end
local report={result='PASS',idempotent_installs=5,nested_failure_cleanup=true,existing_names_unchanged=true,inactive_mod_provider_guard=true,unique_person_batch=100,batch_cpu_seconds=os.clock()-started}
local f=assert(io.open(os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-integration.json','w'));f:write(json.encode(report));f:close();print(json.encode(report))
