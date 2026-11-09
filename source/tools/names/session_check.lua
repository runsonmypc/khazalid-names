-- Development-only session invalidation probe. Parent drives real save/unload/load.
assert(os.getenv('FORTHAMMER_PROBE_LAB'),'private lab only')
local adapter=reqscript('internal/forthammer-names/adapter')
local core=reqscript('internal/forthammer-names/core')
local json=require('json')
local ctx=assert(adapter.eligibility())
local mode=... or 'model'
local key='forthammer_names_session_probe'
local function snapshot(name)
 local out={name.first_name,name.nickname,name.language,name.type,name.has_name}
 for i=0,6 do out[#out+1]=name.words[i];out[#out+1]=name.parts_of_speech[i]end
 return json.encode(out)
end
local function proposal()
 local name=df.historical_entity.find(ctx.civ).name
 for _,candidate in ipairs(core.candidates('civilization'))do
  local p=adapter.preview('civilization',ctx.civ,candidate)
  if p and p.new_text~=p.old_text then return p,snapshot(name)end
 end
 error('no unused civilization proposal for session probe')
end
local function rejected(api,p,before)
 local ok,err=api.accept(p)
 assert(not ok and err:find('session changed',1,true),'stale session proposal was not rejected: '..tostring(err))
 assert(snapshot(df.historical_entity.find(ctx.civ).name)==before,'session rejection mutated name')
end
if mode=='model'then
 for _,event in ipairs{SC_MAP_UNLOADED,SC_WORLD_UNLOADED}do
  local p,before=proposal()
  dfhack.onStateChange.forthammer_names_adapter(event)
  local current=assert(adapter.eligibility())
  assert(current.world==p.context.world and current.site==p.context.site and current.civ==p.context.civ,'model changed target context')
  assert(current.epoch>p.context.epoch,'event did not advance epoch')
  rejected(adapter,p,before)
 end
 print('PASS modeled map/world unload invalidates proposals with identical pointers, IDs and names')
elseif mode=='retain'then
 local p,before=proposal()
 _G[key]={proposal=p,before=before,adapter=adapter}
 print('Retained proposal in Lua state; save normally, return to title, reload the same save, then run session-check reload')
elseif mode=='reload'then
 local saved=assert(_G[key],'retain a proposal in this same process before unloading')
 local p=saved.proposal
 assert(ctx.site==p.context.site and ctx.civ==p.context.civ,'reload the same fortress for this probe')
 assert(ctx.epoch>p.context.epoch,'real unload/reload did not advance epoch')
 assert(snapshot(df.historical_entity.find(ctx.civ).name)==saved.before,'name changed while proposal retained')
 rejected(saved.adapter,p,saved.before)
 rejected(adapter,p,saved.before)
 local report={result='PASS',same_world_data_pointer=ctx.world==p.context.world,
  same_site=true,same_civ=true,same_name=true,old_epoch=p.context.epoch,new_epoch=ctx.epoch,
  retained_adapter_rejected=true,current_adapter_rejected=true}
 local f=assert(io.open(os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-session.json','w'))
 f:write(json.encode(report));f:close();_G[key]=nil
 print(json.encode(report))
else error('expected model, retain or reload')end
