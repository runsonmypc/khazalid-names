-- Observe a native UI-created squad in the isolated lab; never create/rename it.
assert(os.getenv('FORTHAMMER_PROBE_LAB'),'private lab only')
local json=require('json')
local mode=... or 'after'
local path=os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-squad-ui.json'
local core=reqscript('internal/forthammer-names/core')
local raw=assert(reqscript('internal/forthammer-names/pools').entity())
local function snapshot()
 local names={}
 for _,collection in ipairs{{'unit',df.global.world.units.active},{'entity',df.global.world.entities.all},{'site',df.global.world.world_data.sites},{'figure',df.global.world.history.figures}} do
  for _,obj in ipairs(collection[2]) do names[collection[1]..obj.id]=dfhack.df2utf(dfhack.translation.translateName(obj.name)) end
 end
 local selectors={}
 for _,s in ipairs{raw.symbols.symbols_major[df.entity_name_type.OTHER],raw.symbols.symbols_minor[df.entity_name_type.OTHER]} do
  for slot=0,5 do for i,w in ipairs(s.words[slot]) do selectors[#selectors+1]=slot..':'..w..':'..s.parts[slot][i] end end
 end
 return names,table.concat(selectors,',')
end
local names,selectors=snapshot()
if mode=='before' then
 local squads={};for _,s in ipairs(df.global.world.squads.all) do squads[tostring(s.id)]=true end
 local f=assert(io.open(path,'w'));f:write(json.encode{before=names,selectors=selectors,squads=squads});f:close();print('Captured native squad UI baseline');return
end
local f=assert(io.open(path));local saved=json.decode(f:read('*a'));f:close()
assert(selectors==saved.selectors,'personal selectors changed')
for key,value in pairs(saved.before) do assert(names[key]==value,'existing name changed '..key) end
local found={}
for _,s in ipairs(df.global.world.squads.all) do
 if not saved.squads[tostring(s.id)] then
  local count=0
  for i=0,6 do if s.name.words[i]>=0 then
   count=count+1
   assert(df.global.world.raws.language.words[s.name.words[i]].word:find('FH_KHAZ_TYPE_SQUAD_',1,true)==1,'wrong native squad vocabulary')
  end end
  assert(count==1,'native squad must have exactly one reviewed component')
  local text=dfhack.translation.translateName(s.name)
  local reviewed=false
  for _,candidate in ipairs(core.candidates('squad'))do if core.normalize(text)==core.normalize(candidate.name)then reviewed=true;break end end
  assert(reviewed and text~='' and not core.is_reserved(text),'unreviewed native squad name')
  found[#found+1]={id=s.id,name=dfhack.translation.translateName(s.name),english=dfhack.translation.translateName(s.name,true)}
 end
end
assert(#found==1,'expected exactly one newly created native squad')
saved.result='PASS';saved.created=found;saved.existing_names_unchanged=true;saved.selectors_restored=true
f=assert(io.open(path,'w'));f:write(json.encode(saved));f:close();print(json.encode{result=saved.result,created=found,existing_names_unchanged=true,selectors_restored=true})
