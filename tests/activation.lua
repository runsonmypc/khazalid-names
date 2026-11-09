-- Production entrypoints must refuse inactive and conflicting worlds before edits.
local mods={}
package.preload['script-manager']=function() return {get_active_mods=function() return mods end} end
function reqscript() return {data={}} end
SC_WORLD_LOADED=1;SC_MAP_UNLOADED=2;SC_WORLD_UNLOADED=3
local raw={code='MOUNTAIN',translation='KHAZALID_NAMES'}
df={global={plotinfo={civ_id=1,race_id=1,site_id=1},world={world_data={},raws={entities={all={raw}},creatures={all={[1]={creature_id='DWARF'}}}}}}, historical_entity={find=function() return {entity_raw=raw} end}}
dfhack={onStateChange={},isWorldLoaded=function() return true end,isMapLoaded=function()return true end,world={isFortressMode=function()return true end}}
dfhack_flags={module=true}
local function load(path)
 local env=setmetatable({},{__index=_G});assert(loadfile(path,'t',env))();return env
end
local install=load('scripts_modactive/khazalid-name-pools.lua')
local pools=load('scripts_modactive/internal/khazalid-names/pools.lua')
local adapter=load('scripts_modactive/internal/khazalid-names/adapter.lua')
for _,list in ipairs{{},{{id='Other'}},{{id='KhazalidNames'},{id='ForthammerLocal'}},{{id='ForthammerLocal'},{id='KhazalidNames'}}} do
 mods=list
 assert(install.install()==false)
 assert(pools.entity()==nil)
 assert(adapter.eligibility()==nil)
end
mods={{id='KhazalidNames'}}
assert(pools.entity()==raw)
assert(adapter.eligibility())
print('PASS 14 standalone activation/conflict assertions; no name edits')
