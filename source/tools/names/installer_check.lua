-- Execute the shipping installer against isolated selector models, including old raws.
assert(os.getenv('FORTHAMMER_PROBE_LAB'),'private lab only')
local path=assert(dfhack.findScript('forthammer-name-pools'))
local function vector()
 local v={}
 function v:resize(n) assert(n==0);for i=#self,1,-1 do self[i]=nil end end
 function v:insert(where,value) assert(where=='#');table.insert(self,value) end
 return v
end
local function selector()
 local s={words={},parts={}}
 for i=0,5 do s.words[i]=vector();s.parts[i]=vector() end
 return s
end
local cases=0
for _,new_raws in ipairs{false,true} do
 local a,b=selector(),selector()
 local raw={code='MOUNTAIN',translation='FORTHAMMER_KHAZALID',symbols={symbols_major={[0]=a},symbols_minor={[0]=b}}}
 local words={{word='FH_KHAZ_GIVEN_BARDIN'},{word='FH_KHAZ_MOTIF_KOL'},{word='FH_KHAZ_CRAFT_KRON'}}
 if new_raws then words[#words+1]={word='FH_KHAZ_FAMILY_KOLKRON'} end
 local active,loaded=true,true
 local env=setmetatable({df={global={world={raws={language={words=words},entities={all={raw}}}}},entity_name_type={OTHER=0},part_of_speech={Noun=0}},
  dfhack={isWorldLoaded=function()return loaded end,onStateChange={},printerr=function()end},
  dfhack_flags={module=true},SC_WORLD_LOADED=5,
  require=function(module)assert(module=='script-manager');return {get_active_mods=function()return active and {{id='ForthammerLocal'}} or {} end}end,
  reqscript=function(module)assert(module=='internal/forthammer-names/pools');return {install_dedicated=function()end,install_api_guard=function()end}end}, {__index=_G})
 assert(loadfile(path,'t',env))()
 for _,s in ipairs{a,b} do
  assert(s.words[0][1]==(new_raws and 4 or 2),'incorrect complete/legacy front')
  assert(s.words[1][1]==(new_raws and -1 or 3),'incorrect complete/legacy rear')
  assert(s.words[2][1]==1 and s.words[3][1]==2 and s.words[4][1]==3 and s.words[5][1]==3,'unrelated slot changed')
 end
 cases=cases+1
 active=false;assert(not env.install());cases=cases+1
 active=true;loaded=false;assert(not env.install());cases=cases+1
 loaded=true;raw.translation='DWARF';assert(not env.install());cases=cases+1
 raw.translation='FORTHAMMER_KHAZALID';words[1].word='MISSING_GIVEN';assert(not env.install());cases=cases+1
 assert(a.words[2][1]==1 and b.words[2][1]==1,'incomplete install partially mutated selectors')
end
print('PASS '..cases..' installer model cases: complete family, legacy raws, inactive/unloaded/culture and incomplete atomic rejection')
