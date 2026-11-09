-- Snapshot native names around an ordinary save/restart in the private lab.
assert(os.getenv('FORTHAMMER_PROBE_LAB'),'private lab only')
local json=require('json')
local ctx=assert(reqscript('internal/forthammer-names/adapter').eligibility())
local mode=... or 'check'
local path=os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-persistence.json'
local names={}
local function add(key,n)
 local value={first=dfhack.df2utf(n.first_name),nickname=dfhack.df2utf(n.nickname),language=n.language,type=n.type,has_name=n.has_name,words={},parts={}}
 for i=0,6 do value.words[i+1]=n.words[i];value.parts[i+1]=n.parts_of_speech[i] end
 names[key]=value
end
for _,collection in ipairs{{'unit',df.global.world.units.active},{'entity',df.global.world.entities.all},{'site',df.global.world.world_data.sites},{'figure',df.global.world.history.figures},{'squad',df.global.world.squads.all}} do
 for _,obj in ipairs(collection[2]) do add(collection[1]..obj.id,obj.name) end
end
for _,site in ipairs(df.global.world.world_data.sites) do
 for _,loc in ipairs(site.buildings) do add('location'..site.id..':'..loc.id,loc.name) end
end
for _,record in ipairs(df.global.world.artifacts.all) do add('artifact'..record.id,record.name) end
for _,construction in ipairs(df.global.world.world_data.constructions.list) do add('construction'..construction.id,construction.name) end
for _,u in ipairs(df.global.world.units.active) do if u.status.current_soul then add('soul'..u.id,u.status.current_soul.name) end end
if mode=='snapshot' then
 local f=assert(io.open(path,'w'));f:write(json.encode{site=ctx.site,names=names});f:close();print('Saved native-name snapshot');return
end
local f=assert(io.open(path));local saved=json.decode(f:read('*a'));f:close()
assert(ctx.site==saved.site,'wrong fortress')
local count=0
for key,value in pairs(saved.names) do assert(names[key] and json.encode(names[key])==json.encode(value),'name changed on reload: '..key);count=count+1 end
saved.result='PASS';saved.compared=count
f=assert(io.open(path,'w'));f:write(json.encode(saved));f:close()
print('PASS '..count..' native names identical after save/restart/load, including civilization, government, squad, site, unit, soul, historical figure')
