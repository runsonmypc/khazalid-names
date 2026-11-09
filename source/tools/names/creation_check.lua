-- Observe native DF-created names; this probe never creates or renames objects.
assert(os.getenv('FORTHAMMER_PROBE_LAB'),'private lab only')
local core=reqscript('internal/forthammer-names/core')
local pools=reqscript('internal/forthammer-names/pools')
local json=require('json')
local mode=... or 'world'
local raw=assert(pools.entity())
local report={mode=mode,objects={}}
local function check(category,object)
 local text=dfhack.translation.translateName(object.name)
 local found=false
 for _,item in ipairs(core.candidates(category))do if core.normalize(item.name)==core.normalize(text)then found=true;break end end
 assert(found,'unreviewed native '..category..': '..text)
 local count=0
 for i=0,6 do if object.name.words[i]>=0 then count=count+1 end end
 assert(count==1,'native '..category..' stacked components: '..text)
 assert(not core.is_reserved(text),'reserved native creation: '..text)
 report.objects[#report.objects+1]={category=category,id=object.id,name=text,english=dfhack.translation.translateName(object.name,true),native_components=count}
end
local path=os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-creation-baseline.json'
local function namesnapshot(n)
 local value={n.first_name,n.nickname,n.type,n.language,n.has_name}
 for i=0,6 do value[#value+1]=n.words[i];value[#value+1]=n.parts_of_speech[i]end
 return json.encode(value)
end
if mode=='locations-before'then
 local ctx=assert(reqscript('internal/forthammer-names/adapter').eligibility())
 local before={site=ctx.site,names={},reports={}}
 for _,loc in ipairs(df.world_site.find(ctx.site).buildings)do before.names[tostring(loc.id)]=namesnapshot(loc.name)end
 for _,r in ipairs(df.global.world.status.reports)do before.reports[tostring(r.id)]=true end
 local f=assert(io.open(path,'w'));f:write(json.encode(before));f:close()
 print('Captured existing location names and reports before native UI creation');return
elseif mode=='world'then
 for _,entity in ipairs(df.global.world.entities.all)do
  if entity.entity_raw==raw then
   if entity.type==df.historical_entity_type.Civilization then check('civilization',entity)
   elseif entity.type==df.historical_entity_type.SiteGovernment then check('government',entity)end
  end
 end
 assert(#report.objects>1,'need Dwarf worldgen civilization and government')
else
 local ctx=assert(reqscript('internal/forthammer-names/adapter').eligibility())
 local site=assert(df.world_site.find(ctx.site))
 local classes={hospital=df.abstract_building_hospitalst,library=df.abstract_building_libraryst,tavern=df.abstract_building_inn_tavernst,guildhall=df.abstract_building_guildhallst}
 local f=assert(io.open(path));local before=json.decode(f:read('*a'));f:close();assert(before.site==ctx.site,'wrong fortress')
 local seen={}
 for _,loc in ipairs(site.buildings)do
  if before.names[tostring(loc.id)]then
   assert(namesnapshot(loc.name)==before.names[tostring(loc.id)],'pre-existing location renamed')
  else
   for category,class in pairs(classes)do
    if class:is_instance(loc)then check(category,loc);seen[category]=true end
   end
  end
 end
 for category in pairs(classes)do assert(seen[category],'create native '..category..' through game UI first')end
 report.existing_locations_unchanged=true
 report.new_reports={}
 for _,r in ipairs(df.global.world.status.reports)do if not before.reports[tostring(r.id)]then report.new_reports[#report.new_reports+1]=dfhack.df2utf(r.text)end end
end
report.result='PASS'
local f=assert(io.open(os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-creation-'..mode..'.json','w'))
f:write(json.encode(report));f:close();print(json.encode(report))
