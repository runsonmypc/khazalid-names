-- Guard models on temporary native location objects; parent tests real UI input.
assert(os.getenv('FORTHAMMER_PROBE_LAB'),'private lab only')
assert(df.global.pause_state,'pause the disposable fortress before creation fixtures')
local creation=reqscript('internal/forthammer-names/creation')
local adapter=reqscript('internal/forthammer-names/adapter')
local core=reqscript('internal/forthammer-names/core')
local json=require('json')
local ctx=assert(adapter.eligibility())
local site=df.world_site.find(ctx.site)
local fort=df.historical_entity.find(ctx.group)
local initial_next,initial_count=site.next_building_id,#site.buildings
assert(initial_count==0 or site.buildings[initial_count-1].id<initial_next,'invalid native next-building ID')
local cleanup={function()site.next_building_id=initial_next end}
local stats={}
local function snap(name)
 local value={name.first_name,name.nickname,name.language,name.type,name.has_name}
 for i=0,6 do value[#value+1]=name.words[i];value[#value+1]=name.parts_of_speech[i]end
 return json.encode(value)
end
local function names()
 local out={};for _,object in ipairs(site.buildings)do out[object.id]=snap(object.name)end;return out
end
local function unchanged(before)
 local after=names();for id,name in pairs(before)do assert(after[id]==name,'pre-existing location changed: '..id)end
end
local original_names=names()
local classes={hospital='hospital',library='library',tavern='inn_tavern',guildhall='guildhall',temple='temple'}
local types={hospital='Hospital',library='Library',tavern='FoodStore',guildhall='Guildhall',temple='Temple'}
local function add(category,builder)
 local object=df['abstract_building_'..classes[category]..'st']:new()
 cleanup[#cleanup+1]=function()object:delete()end
 object.id=site.next_building_id;site.next_building_id=site.next_building_id+1
 object.site_owner_id=builder;object.name.type=df.language_name_type[types[category]]
 object.name.first_name='Provisional';object.name.has_name=true
 site.buildings:insert('#',object)
 cleanup[#cleanup+1]=function()assert(site.buildings[#site.buildings-1]==object,'fixture order changed');site.buildings:erase(#site.buildings-1)end
 return object
end
local function first(limit)assert(limit>0);return 1 end
local function no_random()error('a non-creation guard consumed random input')end
local function rejected(state,object,needle)
 local before=snap(object.name)
 local ok,err=creation.finish(state,no_random)
 assert(not ok and err:find(needle,1,true),'creation guard not rejected: '..tostring(err))
 assert(snap(object.name)==before,'rejected creation changed its provisional name')
 unchanged(original_names)
end
local ok,err=xpcall(function()
 local state=assert(creation.snapshot())
 local success,result=creation.finish(state,no_random)
 assert(success and not result.created,'no-new-object input was treated as creation')
 assert(not creation.finish(state,no_random),'finished input snapshot replayed')
 unchanged(original_names);stats.no_new_object=true;stats.replay_rejected=true
 -- Discarding a snapshot models a canceled input; snapshot itself cannot mutate.
 state=assert(creation.snapshot());unchanged(original_names);state=nil;stats.cancel_snapshot_model=true

 for _,category in ipairs{'hospital','library','tavern','guildhall'}do
  local before=names();state=assert(creation.snapshot())
  local object=add(category,fort.id)
  local name_type=object.name.type
  success,result=creation.finish(state,first)
  assert(success and result.created and result.category==category,'approved location not initialized')
  local rendered=dfhack.translation.translateName(object.name)
  assert(core.normalize(rendered)==core.normalize(result.name),'initial name rendered incorrectly')
  assert(object.name.type==name_type,'native location name type changed')
  for i=0,6 do assert((i==df.language_name_component.TheX)==(object.name.words[i]>=0),'extra name component')end
  unchanged(before);stats[category..'_initialized']=true
 end

 state=assert(creation.snapshot());local object=add('hospital',-1)
 rejected(state,object,'constructed by this Dwarf community');stats.ineligible_builder_rejected=true
 state=assert(creation.snapshot());object=add('hospital',fort.id)
 state.ids[object.id]=true -- Model an ID already present at the start of input.
 local existing_before=snap(object.name)
 success,result=creation.finish(state,no_random)
 assert(success and not result.created and snap(object.name)==existing_before,'an existing ID received an initial name')
 stats.existing_id_not_initialized=true
 state=assert(creation.snapshot());object=add('hospital',fort.id);state.context.epoch=state.context.epoch-1
 rejected(state,object,'session changed');stats.stale_session_rejected=true
 state=assert(creation.snapshot());object=add('library',fort.id);add('hospital',fort.id)
 rejected(state,object,'Multiple new locations');stats.multiple_new_objects_rejected=true
 state=assert(creation.snapshot());object=add('library',fort.id)
 local correct_next=site.next_building_id;site.next_building_id=correct_next+1
 local good,failure=pcall(rejected,state,object,'creation sequence changed')
 site.next_building_id=correct_next;assert(good,failure);stats.sequence_changed_rejected=true
 state=assert(creation.snapshot());object=add('library',fort.id);state.count=state.count+1
 rejected(state,object,'creation sequence changed');stats.count_mismatch_rejected=true
 state=assert(creation.snapshot());object=add('temple',fort.id)
 local temple_before=snap(object.name)
 success,result=creation.finish(state,no_random)
 assert(success and not result.created and result.excluded and snap(object.name)==temple_before,'temple altered')
 stats.temple_excluded=true
 state=assert(creation.snapshot());object=add('library',fort.id)
 local invalid_before=snap(object.name)
 success,result=creation.finish(state,function()return 0 end)
 assert(not success and result:find('invalid index',1,true) and snap(object.name)==invalid_before,'invalid random source wrote a name')
 stats.invalid_random_rejected=true
 state=assert(creation.snapshot());object=add('library',fort.id)
 local missing_before=snap(object.name)
 local generate=core.generate
 core.generate=function()return {name='Missing raw provider model',token='FH_KHAZ_MISSING_CREATION_PROBE'}end
 local ran,initialized,explanation=pcall(creation.finish,state,first)
 core.generate=generate
 assert(ran and not initialized and explanation:find('lacks the reviewed location naming raws',1,true),'missing raw provider model did not fail closed')
 assert(snap(object.name)==missing_before,'missing raw provider model changed a name')
 stats.missing_raw_provider_model=true

 -- All finite hospital names occupied, including locations not eligible to edit.
 local language,words=nil,{}
 for i,value in ipairs(df.global.world.raws.language.translations)do if value.name=='FORTHAMMER_KHAZALID'then language=i end end
 for i,value in ipairs(df.global.world.raws.language.words)do words[value.word]=i end
 assert(language,'missing naming language')
 local reviewed={}
 for _,candidate in ipairs(core.candidates('hospital'))do
  reviewed[candidate.name]=true
  local blocker=add('hospital',-1)
  blocker.name.first_name='';blocker.name.language=language
  for i=0,6 do blocker.name.words[i]=-1;blocker.name.parts_of_speech[i]=df.part_of_speech.Noun end
  blocker.name.words[df.language_name_component.TheX]=assert(words[candidate.token])
 end
 local before=names();state=assert(creation.snapshot());object=add('hospital',fort.id)
 local draws=0
 success,result=creation.finish(state,function(limit)draws=draws+1;return first(limit)end)
 assert(success and result.created and result.repeated and reviewed[result.name],'exhaustion did not use a reviewed duplicate')
 assert(draws==1,'exhaustion did not use exactly one bounded fallback draw')
 assert(core.normalize(dfhack.translation.translateName(object.name))==core.normalize(result.name),'exhaustion manufactured a suffix')
 unchanged(before);stats.exhaustion_reviewed_duplicate=true
 unchanged(original_names)
end,debug.traceback)
for i=#cleanup,1,-1 do cleanup[i]()end
assert(ok,err)
assert(#site.buildings==initial_count and site.next_building_id==initial_next,'fixture allocation state not restored')
unchanged(original_names)
local report={result='PASS',coverage='Temporary native objects and same-input guard models; actual native UI creation tested separately',checks=stats,existing_names_unchanged=true,fixtures_removed=true}
local file=assert(io.open(os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-creation-guards.json','w'))
file:write(json.encode(report));file:close();print(json.encode(report))
