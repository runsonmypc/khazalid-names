-- Native collision fixtures in the private paused lab; no fixture is saved.
assert(os.getenv('FORTHAMMER_PROBE_LAB'),'private lab only')
assert(df.global.pause_state,'pause the fortress before collision fixtures')
local adapter=reqscript('internal/forthammer-names/adapter')
local core=reqscript('internal/forthammer-names/core')
local targets=reqscript('internal/forthammer-names/targets')
local json=require('json')
local ctx=assert(adapter.eligibility())
local world=df.global.world
local site=df.world_site.find(ctx.site)
local fort=df.historical_entity.find(df.global.plotinfo.group_id)
local civ=df.historical_entity.find(ctx.civ)
local cleanup,stats={},{}
local policy = df.global.d_init.display.nickname
local game, old_policy = df.global.gametype, policy[df.global.gametype]
cleanup[#cleanup+1] = function() policy[game] = old_policy end
local nickname_checks = 0
local sequence=1000000
for _,v in ipairs{world.entities.all,world.squads.all,site.buildings,world.artifacts.all,
 world.world_data.constructions.list,world.history.events}do
 if #v>0 then sequence=math.max(sequence,v[#v-1].id+1)end
end
local function next_id()local id=sequence;sequence=sequence+1;return id end
local function allocated(obj)cleanup[#cleanup+1]=function()obj:delete()end;return obj end
local function append(v,obj)
 v:insert('#',obj)
 cleanup[#cleanup+1]=function()assert(v[#v-1]==obj,'fixture vector order changed');v:erase(#v-1)end
end
local function snap(name)
 local out={name.first_name,name.nickname,name.language,name.type,name.has_name}
 for i=0,6 do out[#out+1]=name.words[i];out[#out+1]=name.parts_of_speech[i]end
 return json.encode(out)
end
local language,words=nil,{}
for i,t in ipairs(world.raws.language.translations)do if t.name=='FORTHAMMER_KHAZALID'then language=i end end
for i,w in ipairs(world.raws.language.words)do words[w.word]=i end
assert(language,'missing naming translation')
local function name_as(name,candidate,name_type)
 name.first_name='';name.nickname='';name.type=name_type;name.language=language;name.has_name=candidate~=nil
 for i=0,6 do name.words[i]=-1;name.parts_of_speech[i]=df.part_of_speech.Noun end
 if candidate then name.words[0]=assert(words[candidate.token])end
end
local function available(category)
 local occupied={}
 for _,n in ipairs(targets.occupied(category,ctx))do occupied[core.normalize(n.name)]=true end
 for _,candidate in ipairs(core.candidates(category))do
  if not occupied[core.normalize(candidate.name)]then return candidate end
 end
 error('no unused '..category..' candidate for collision fixture')
end
local function blocked(category,id,candidate,namespace)
 local target=assert(targets.resolve(category,id,ctx,namespace))
 local before=snap(target.name)
 local p,err=adapter.preview(category,id,candidate,namespace)
 assert(not p and err:find('already in use',1,true),category..' collision not rejected: '..tostring(err))
 assert(snap(target.name)==before,category..' collision mutated target')
end
local function hidden(category,object,candidate,id,namespace)
 local nickname,previous=object.name.nickname,policy[game]
 for _,mode in ipairs{'CENTRALIZE','REPLACE_FIRST','REPLACE_ALL'}do
  object.name.nickname='quality-hidden';policy[game]=df.d_init_nickname[mode]
  local full,visible=false,false
  for _,row in ipairs(targets.occupied(category,ctx))do
   if row.id==object.id then
    full=full or row.name==candidate.name
    visible=visible or row.name==dfhack.translation.translateName(object.name)
   end
  end
  assert(full and visible,'hidden underlying/visible '..category..' name missing: '..mode)
  if id then blocked(category,id,candidate,namespace)end
  nickname_checks=nickname_checks+1
 end
 object.name.nickname=nickname;policy[game]=previous
end
local function entity(kind,id)
 local obj=allocated(df.historical_entity:new());obj.id=id or next_id();obj.type=kind
 append(world.entities.all,obj);return obj
end
local function location(class,builder,id)
 local obj=allocated(df[class]:new());obj.id=id or next_id();obj.site_owner_id=builder
 append(site.buildings,obj);return obj
end
local ok,err=xpcall(function()
 -- A custom alias blocks the same visible name even though its squad is not editable.
 local candidate=available('squad')
 local squads={}
 for _=1,2 do
  local squad=allocated(df.squad:new());squad.id=next_id();squad.entity_id=fort.id
  name_as(squad.name,nil,df.language_name_type.Squad)
  append(world.squads.all,squad);append(fort.squads,squad.id);squads[#squads+1]=squad
 end
 local p=assert(adapter.preview('squad',squads[1].id,candidate))
 local before=snap(squads[1].name)
 squads[2].alias=candidate.name
 assert(not targets.resolve('squad',squads[2].id,ctx),'aliased squad became editable')
 blocked('squad',squads[1].id,candidate)
 local accepted,failure=adapter.accept(p)
 assert(not accepted and failure:find('already in use',1,true),'new collision after preview was accepted')
 assert(snap(squads[1].name)==before,'accept-time collision mutated squad')
 stats.squad_alias=true;stats.accept_time_collision=true
 squads[2].alias='Fixture alias'
 name_as(squads[2].name,candidate,df.language_name_type.Squad)
 blocked('squad',squads[1].id,candidate);stats.squad_underlying_aliased_name=true
 hidden('squad',squads[2],candidate,squads[1].id)
 local calls=0
 local function first(n)calls=calls+1;assert(n>0,'empty random selection');return 1 end
 local suggested=assert(adapter.suggest('squad',squads[1].id,'squad',first))
 assert(suggested.item.name~=candidate.name,'suggestion reused occupied squad name')
 assert(calls>0 and calls<=#core.candidates('squad'),'suggestion exceeded finite bound')
 assert(snap(squads[1].name)==before,'suggestion mutated target')
 stats.bounded_suggestion_skips_collision=true
 -- Occupy every reviewed name through aliases, which remain protected from edits.
 for _,entry in ipairs(core.candidates('squad'))do
  local blocker=allocated(df.squad:new());blocker.id=next_id();blocker.entity_id=fort.id;blocker.alias=entry.name
  name_as(blocker.name,nil,df.language_name_type.Squad)
  append(world.squads.all,blocker);append(fort.squads,blocker.id)
 end
 calls=0
 local exhausted,explanation=adapter.suggest('squad',squads[1].id,'squad',first)
 assert(not exhausted and explanation:find('No unused alternative names',1,true),'exhausted target did not explain exhaustion')
 assert(calls==0,'exhausted typed pool called random source')
 assert(snap(squads[1].name)==before,'exhaustion mutated target')
 stats.suggestion_exhaustion=true
 local bad_target,bad_error=adapter.suggest('squad',-1,'squad',first)
 assert(not bad_target and bad_error:find('valid native target ID',1,true)and calls==0,'invalid target consumed suggestions')
 stats.suggestion_target_validation=true
 assert(not targets.resolve('squad',squads[1].id,ctx,'entity'),'unexpected squad namespace accepted')
 for _,bad in ipairs{-1,1.5,'1',false}do assert(not targets.resolve('squad',bad,ctx),'malformed target ID accepted')end
 stats.invalid_ids_and_namespace=true

 -- Foreign/unaffiliated polities still occupy their names; neither is editable here.
 for category,kind in pairs{civilization=df.historical_entity_type.Civilization,government=df.historical_entity_type.SiteGovernment}do
  candidate=available(category)
  local other=entity(kind)
  name_as(other.name,candidate,category=='civilization'and df.language_name_type.Civilization or df.language_name_type.EntitySite)
  assert(not targets.resolve(category,other.id,ctx),'foreign polity became editable')
  blocked(category,category=='civilization'and ctx.civ or fort.id,candidate)
  hidden(category,other,candidate,category=='civilization'and ctx.civ or fort.id)
  stats[category..'_foreign_collision']=true
 end

 -- Ineligible builders cannot make existing location names available.
 local classes={tavern='abstract_building_inn_tavernst',guildhall='abstract_building_guildhallst',
  library='abstract_building_libraryst',hospital='abstract_building_hospitalst'}
 local name_types={tavern='FoodStore',guildhall='Guildhall',library='Library',hospital='Hospital'}
 for category,class in pairs(classes)do
  candidate=available(category)
  local current=location(class,fort.id)
  local other=location(class,-1)
  name_as(current.name,nil,df.language_name_type[name_types[category]])
  name_as(other.name,candidate,df.language_name_type[name_types[category]])
  assert(not targets.resolve(category,other.id,ctx,'location'),'unknown builder became editable')
  assert(not targets.resolve(category,current.id,ctx,'entity'),'wrong location namespace accepted')
  blocked(category,current.id,candidate,'location')
  hidden(category,other,candidate,current.id,'location')
  stats[category..'_ineligible_builder_collision']=true
 end

 -- Site-local building IDs overlap global entity IDs. Neither is the other's self.
 candidate=available('business')
 local id=next_id()
 local market=location('abstract_building_marketst',fort.id,id)
 local company=entity(df.historical_entity_type.MerchantCompany,id);company.entity_raw=civ.entity_raw
 local link=allocated(df.entity_entity_link:new());link.type=df.entity_entity_link_type.PARENT;link.target=ctx.civ
 append(company.entity_links,link)
 name_as(market.name,nil,df.language_name_type.GeneralStore)
 name_as(company.name,candidate,df.language_name_type.MerchantCompany)
 blocked('business',market.id,candidate,'location')
 hidden('business',company,candidate,market.id,'location')
 name_as(company.name,nil,df.language_name_type.MerchantCompany)
 name_as(market.name,candidate,df.language_name_type.GeneralStore)
 blocked('business',company.id,candidate,'entity')
 hidden('business',market,candidate,company.id,'entity')
 name_as(company.name,candidate,df.language_name_type.MerchantCompany)
 local labels={}
 for _,row in ipairs(targets.list('business',ctx))do if row.id==id then labels[row.namespace]=row.text end end
 assert(labels.entity and labels.location and labels.entity~=labels.location,'business namespaces have indistinguishable labels')
 assert(not targets.resolve('business',id,ctx),'ambiguous business ID accepted without namespace')
 assert(not targets.resolve('business',id,ctx,'unknown'),'unknown business namespace accepted')
 stats.business_same_id_cross_namespace=true;stats.business_distinct_menu_labels=true
 -- An unaffiliated guild must also be present in occupancy, despite no edit permission.
 local guild=entity(df.historical_entity_type.Guild)
 name_as(guild.name,candidate,df.language_name_type.MerchantCompany)
 local found=false
 for _,row in ipairs(targets.occupied('business',ctx))do if row.id==guild.id and row.namespace=='entity'then found=true end end
 assert(found and not targets.resolve('business',guild.id,ctx,'entity'),'unaffiliated guild occupancy/edit separation failed')
 stats.business_unaffiliated_guild_occupied=true

 -- Even an unavailable physical artifact reserves its surviving record name.
 candidate=available('artifact')
 local record=allocated(df.artifact_record:new());record.id=next_id()
 name_as(record.name,candidate,df.language_name_type.Artifact);append(world.artifacts.all,record)
 found=false
 for _,row in ipairs(targets.occupied('artifact',ctx))do
  if row.id==record.id and row.name==dfhack.translation.translateName(record.name)then found=true end
 end
 assert(found and not targets.resolve('artifact',record.id,ctx),'itemless record occupancy/edit separation failed')
 hidden('artifact',record,candidate)
 stats.artifact_itemless_record_occupied=true

 -- Foreign/unknown construction provenance prevents editing, but not collision checks.
 for _,category in ipairs{'road','tunnel','bridge','wall'}do
  candidate=available(category)
  local objects={}
  for _=1,2 do
   local object=allocated(df['world_construction_'..category..'st']:new());object.id=next_id()
   name_as(object.name,nil,df.language_name_type[category:sub(1,1):upper()..category:sub(2)])
   append(world.world_data.constructions.list,object);objects[#objects+1]=object
  end
  local event=allocated(df.history_event_created_world_constructionst:new());event.id=next_id();event.civ=ctx.civ;event.construction=objects[1].id
  append(world.history.events,event)
  name_as(objects[2].name,candidate,objects[2].name.type)
  assert(not targets.resolve(category,objects[2].id,ctx),'unverified construction became editable')
  blocked(category,objects[1].id,candidate)
  hidden(category,objects[2],candidate,objects[1].id)
  stats[category..'_unverified_builder_collision']=true
 end
end,debug.traceback)
for i=#cleanup,1,-1 do cleanup[i]()end
assert(ok,err)
assert(policy[game]==old_policy,'nickname policy not restored')
local report={result='PASS',coverage='Temporary native collision fixtures; no generated target name applied; all fixtures removed',checks=stats,nickname_policy_cases=nickname_checks}
local f=assert(io.open(os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-collisions.json','w'))
f:write(json.encode(report));f:close();print(json.encode(report))
