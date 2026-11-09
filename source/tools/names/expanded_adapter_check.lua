-- Native-object fixtures only, in a paused disposable fortress; removed on exit.
assert(os.getenv('FORTHAMMER_PROBE_LAB'),'private lab only')
assert(df.global.pause_state,'pause before temporary native fixtures')
local adapter=reqscript('internal/forthammer-names/adapter')
local core=reqscript('internal/forthammer-names/core')
local targets=reqscript('internal/forthammer-names/targets')
local ctx=assert(adapter.eligibility())
local site=df.world_site.find(ctx.site)
local fort=df.historical_entity.find(df.global.plotinfo.group_id)
local civ=df.historical_entity.find(ctx.civ)
local function snap(n)
 local t={n.first_name,n.nickname,n.language,n.type,n.has_name}
 for i=0,6 do t[#t+1]=n.words[i];t[#t+1]=n.parts_of_speech[i] end
 return require('json').encode(t)
end
local cleanup={}
local function allocated(obj) cleanup[#cleanup+1]=function() obj:delete() end;return obj end
local function append(v,obj)
 v:insert('#',obj);cleanup[#cleanup+1]=function() assert(v[#v-1]==obj,'fixture order changed');v:erase(#v-1) end
end
local function restore_name(name)
 local old=allocated(df.language_name:new());old:assign(name)
 cleanup[#cleanup+1]=function()name:assign(old)end
end
local stats={}
local name_guards={}
local sequence=1000000
for _,objects in ipairs{df.global.world.entities.all,df.global.world.squads.all,site.buildings,
 df.global.world.artifacts.all,df.global.world.world_data.constructions.list,
 df.global.world.history.figures,df.global.world.history.events}do
 for _,object in ipairs(objects)do sequence=math.max(sequence,object.id+1)end
end
local function exercise(category,id,namespace)
 print('names-adapter: exercise '..category..' ['..id..']')
 local target=assert(targets.resolve(category,id,ctx,namespace))
 local original=snap(target.name)
 local original_type=target.name.type
 local item
 for _,candidate in ipairs(core.candidates(category)) do
  if adapter.preview(category,id,candidate,namespace) then item=candidate;break end
 end
 assert(item,'no unused fixture name '..category)
 local p=assert(adapter.preview(category,id,item,namespace))
 assert(snap(target.name)==original,'preview mutated '..category)
 -- Discard is cancellation; next preview must see exactly the same native state.
 p=assert(adapter.preview(category,id,item,namespace))
 local old=target.name.nickname;target.name.nickname='temporary-test'
 assert(not adapter.accept(p),'stale target accepted '..category)
 target.name.nickname=old
 assert(adapter.accept(p),'accept '..category)
 assert(target.name.type==original_type,'native name type changed '..category)
 assert(core.normalize(dfhack.translation.translateName(target.name))==core.normalize(item.name),'write mismatch '..category)
 assert(not adapter.accept(p),'replayed proposal '..category)
 stats[category]={preview_cancel=true,stale_rejected=true,accepted=true,name=item.name,native_type_preserved=true}
end
local ok,err=xpcall(function()
 -- Real existing polity targets, restored at end; no fabrication of polity history.
 for category,id in pairs{civilization=ctx.civ,government=fort.id} do
  restore_name(assert(targets.resolve(category,id,ctx)).name);exercise(category,id)
 end
 -- Forename edits require established native names in every existing copy.
 local selected,forename,baseline
 for _,unit in ipairs(df.global.world.units.active)do
  if unit.civ_id==ctx.civ and unit.race==df.global.plotinfo.race_id and(unit.sex==0 or unit.sex==1)then
   for _,candidate in ipairs(core.candidates(unit.sex==0 and'forename-female'or'forename-male'))do
    local p=adapter.preview('unit',unit.id,candidate)
    if p then selected=unit;forename=candidate;baseline=p;break end
   end
  end
  if selected then break end
 end
 assert(selected,'no eligible named Dwarf for unnamed-name guards')
 local copies={{label='unit',name=selected.name}}
 if selected.status.current_soul then copies[#copies+1]={label='soul',name=selected.status.current_soul.name}end
 local figure=df.historical_figure.find(selected.hist_figure_id)
 if figure then copies[#copies+1]={label='historical_figure',name=figure.name}end
 for _,copy in ipairs(copies)do
  local before={};for i,value in ipairs(copies)do before[i]=snap(value.name)end
  local had_name=copy.name.has_name;copy.name.has_name=false
  local good,p,preview_error=pcall(adapter.preview,'unit',selected.id,forename)
  local accepted_ok,accepted,accept_error=pcall(adapter.accept,baseline)
  copy.name.has_name=had_name
  assert(good and not p and preview_error:find('unnamed',1,true),'unnamed '..copy.label..' preview not rejected')
  assert(accepted_ok and not accepted and accept_error:find('unnamed',1,true),'unnamed '..copy.label..' accept not rejected')
  for i,value in ipairs(copies)do assert(snap(value.name)==before[i],'unnamed-name guard mutated '..value.label)end
  name_guards[copy.label..'_unnamed_rejected']=true
 end
 -- Model only the visible-name provider, leaving real identity records untouched.
 -- The proposed complete name must be occupied even when another actor's base
 -- name differs from the identity displayed to the player.
 local visible=allocated(df.language_name:new())
 for _,field in ipairs{'first_name','nickname','language','type','has_name'}do visible[field]=baseline.after[field]end
 for i=0,6 do visible.words[i]=baseline.after.words[i];visible.parts_of_speech[i]=baseline.after.parts_of_speech[i]end
 local get_visible=dfhack.units.getVisibleName
 for _,case in ipairs{{label='historical_figure',all=df.global.world.history.figures,except=selected.hist_figure_id},
  {label='unit',all=df.global.world.units.all,except=selected.id}}do
  local other
  for _,object in ipairs(case.all)do if object.id~=case.except then other=object;break end end
  assert(other,'no other actor for visible-name collision model')
  local before={};for i,value in ipairs(copies)do before[i]=snap(value.name)end
  dfhack.units.getVisibleName=function(object)if object==other then return visible end;return get_visible(object)end
  local good,p,preview_error=pcall(adapter.preview,'unit',selected.id,forename)
  local accepted_ok,accepted,accept_error=pcall(adapter.accept,baseline)
  dfhack.units.getVisibleName=get_visible
  assert(good and not p and preview_error:find('already in use',1,true),'visible '..case.label..' collision preview not rejected')
  assert(accepted_ok and not accepted and accept_error:find('already in use',1,true),'visible '..case.label..' collision accept not rejected')
  for i,value in ipairs(copies)do assert(snap(value.name)==before[i],'visible-name collision mutated '..value.label)end
  name_guards['visible_'..case.label..'_collision_provider_model']=true
 end
 local squad=allocated(df.squad:new());squad.id=sequence;sequence=sequence+1;squad.entity_id=fort.id;squad.name.type=df.language_name_type.Squad
 append(df.global.world.squads.all,squad);append(fort.squads,squad.id)
 exercise('squad',squad.id)
 local classes={tavern='inn_tavern',guildhall='guildhall',library='library',hospital='hospital',business='market'}
 for category,class in pairs(classes) do
  local obj=allocated(df['abstract_building_'..class..'st']:new());obj.id=sequence;sequence=sequence+1;obj.site_owner_id=fort.id
  obj.name.type=category=='tavern' and df.language_name_type.FoodStore or df.language_name_type[category:sub(1,1):upper()..category:sub(2)] or df.language_name_type.GeneralStore
  append(site.buildings,obj);exercise(category,obj.id,'location')
  obj.site_owner_id=-1;assert(not targets.resolve(category,obj.id,ctx,'location'),'unknown builder accepted');obj.site_owner_id=fort.id
 end
 local entity=allocated(df.historical_entity:new());entity.id=sequence;sequence=sequence+1;entity.type=df.historical_entity_type.MerchantCompany;entity.entity_raw=civ.entity_raw
 local link=df.entity_entity_link:new();link.type=df.entity_entity_link_type.PARENT;link.target=ctx.civ;entity.entity_links:insert('#',link)
 entity.name.type=df.language_name_type.MerchantCompany;append(df.global.world.entities.all,entity)
 exercise('business',entity.id,'entity')
 local maker
 for _,hf in ipairs(df.global.world.history.figures) do
  if hf.civ_id==ctx.civ and hf.race==df.global.plotinfo.race_id then maker=hf.id;break end
 end
 assert(maker,'no Dwarf maker fixture')
 print('names-adapter: select initialized native weapon for artifact linkage')
 local item
 for _,candidate in ipairs(df.global.world.items.all)do
  if df.item_weaponst:is_instance(candidate)and not candidate.flags.artifact
    and not candidate.flags.garbage_collect and candidate.subtype
    and not dfhack.items.getGeneralRef(candidate,df.general_ref_type.IS_ARTIFACT)then item=candidate;break end
 end
 assert(item,'no initialized unnamed native weapon for artifact fixture')
 local original_maker=item:getMaker()
 local original_artifact=item.flags.artifact
 local original_crafted=item.flags.artifact_mood
 print('names-adapter: read original native weapon description')
 local original_description=dfhack.items.getReadableDescription(item)
 cleanup[#cleanup+1]=function()
  item:setMaker(original_maker);item.flags.artifact=original_artifact;item.flags.artifact_mood=original_crafted
  assert(dfhack.items.getReadableDescription(item)==original_description,'native weapon description not restored')
 end
 item:setMaker(maker);item.flags.artifact=true
 local record=allocated(df.artifact_record:new());record.id=sequence;sequence=sequence+1;record.item=item;record.name.type=df.language_name_type.Artifact
 local artifact_ref=allocated(df.general_ref_is_artifactst:new());artifact_ref.artifact_id=record.id
 append(item.general_refs,artifact_ref)
 append(df.global.world.artifacts.all,record);exercise('artifact',record.id)
 print('names-adapter: read linked named-weapon description')
 local displayed=dfhack.items.getReadableDescription(item)
 local expected=dfhack.translation.translateName(record.name)
 assert(displayed:find(expected,1,true),'artifact record edit missing from item description')
 stats.artifact.item_description=displayed
 stats.artifact.linked_record=true
 stats.artifact.fixture='Initialized native weapon with temporary artifact linkage; original maker, flags and description restored'
 local negatives={}
 local function rejects(label,change,restore)
  local old=snap(record.name)
  print('names-adapter: artifact negative '..label)
  change()
  local good,result=pcall(targets.resolve,'artifact',record.id,ctx)
  restore()
  assert(good,'artifact negative threw: '..label..': '..tostring(result))
  assert(not result,'artifact negative accepted: '..label)
  assert(snap(record.name)==old,'artifact negative mutated name: '..label)
  negatives[label]=true
 end
 rejects('missing_item',function()record.item=nil end,function()record.item=item end)
 rejects('garbage_collect',function()item.flags.garbage_collect=true end,function()item.flags.garbage_collect=false end)
 rejects('missing_artifact_flag',function()item.flags.artifact=false end,function()item.flags.artifact=true end)
 rejects('missing_artifact_ref',function()item.general_refs:erase(#item.general_refs-1)end,function()item.general_refs:insert('#',artifact_ref)end)
 rejects('wrong_artifact_ref',function()artifact_ref.artifact_id=record.id+1 end,function()artifact_ref.artifact_id=record.id end)
 local get_book_title=dfhack.items.getBookTitle
 rejects('written_title_provider_model',function()
  dfhack.items.getBookTitle=function(value)if value==item then return 'Fixture written-work title'end;return get_book_title(value)end
 end,function()dfhack.items.getBookTitle=get_book_title end)
 rejects('unknown_maker',function()item:setMaker(-1)end,function()item:setMaker(maker)end)
 -- Independent native identity fixtures avoid temporarily changing a real maker.
 local foreign=allocated(df.historical_entity:new());foreign.id=sequence;sequence=sequence+1
 foreign.type=df.historical_entity_type.Civilization;foreign.entity_raw=civ.entity_raw
 append(df.global.world.entities.all,foreign)
 local foreign_maker=allocated(df.historical_figure:new());foreign_maker.id=sequence;sequence=sequence+1
 foreign_maker.race=df.global.plotinfo.race_id;foreign_maker.civ_id=foreign.id
 append(df.global.world.history.figures,foreign_maker)
 rejects('foreign_maker',function()item:setMaker(foreign_maker.id)end,function()item:setMaker(maker)end)
 local other_race
 for i,race in ipairs(df.global.world.raws.creatures.all)do if race.creature_id~='DWARF'then other_race=i;break end end
 assert(other_race,'no non-Dwarf raw for maker negative')
 local non_dwarf=allocated(df.historical_figure:new());non_dwarf.id=sequence;sequence=sequence+1
 non_dwarf.race=other_race;non_dwarf.civ_id=ctx.civ
 append(df.global.world.history.figures,non_dwarf)
 rejects('non_dwarf_maker',function()item:setMaker(non_dwarf.id)end,function()item:setMaker(maker)end)
 stats.artifact.rejected=negatives
 -- artifact_mood is not used as the linkage test; exercise both bit values.
 for _,crafted in ipairs{false,true}do
  print('names-adapter: artifact crafted bit '..tostring(crafted))
  item.flags.artifact_mood=crafted
  assert(targets.resolve('artifact',record.id,ctx),'crafted-artifact flag affected eligibility')
  assert(dfhack.items.getReadableDescription(item):find(expected,1,true),'crafted-artifact flag affected displayed name')
 end
 stats.artifact.crafted_flag_independent=true
 for _,category in ipairs{'road','tunnel','bridge','wall'} do
  local obj=allocated(df['world_construction_'..category..'st']:new());obj.id=sequence;sequence=sequence+1
  obj.name.type=df.language_name_type[category:sub(1,1):upper()..category:sub(2)]
  append(df.global.world.world_data.constructions.list,obj)
  assert(not targets.resolve(category,obj.id,ctx),'missing event accepted')
  local event=allocated(df.history_event_created_world_constructionst:new());event.id=sequence;sequence=sequence+1;event.civ=ctx.civ;event.construction=obj.id
  append(df.global.world.history.events,event);exercise(category,obj.id)
 end
end,debug.traceback)
for i=#cleanup,1,-1 do cleanup[i]() end
assert(ok,err)
local report={result='PASS',coverage='Native object fixtures; temporary targets removed, real polity names restored',categories=stats,name_guards=name_guards}
local json=require('json');local f=assert(io.open(os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-expanded-adapter.json','w'));f:write(json.encode(report));f:close();print(json.encode(report))
