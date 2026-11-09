assert(os.getenv('KHAZALID_NAMES_PROBE_LAB'))
local json=require('json')
local facts=reqscript('internal/khazalid-names/artifact-facts')
local path=os.getenv('KHAZALID_NAMES_PROBE_LAB')..'/results/item-persistence.json'
local mode=... or 'check'
if mode=='snapshot' then
 local items={}
 for _,item in ipairs(df.global.world.items.all) do
  if item:getType()==df.item_type.WEAPON then
   items[tostring(item.id)]={signature=facts.read(item).signature,description=dfhack.items.getReadableDescription(item)}
  end
 end
 assert(next(items));local f=assert(io.open(path,'w'));f:write(json.encode{items=items});f:close();print('Saved native weapon facts');return
end
local f=assert(io.open(path));local data=json.decode(f:read('*a'));f:close();local count=0
for id,old in pairs(data.items) do
 local item=assert(df.item.find(tonumber(id)))
 assert(facts.read(item).signature==old.signature)
 assert(dfhack.items.getReadableDescription(item)==old.description)
 count=count+1
end
data.result='PASS';data.compared=count
f=assert(io.open(path,'w'));f:write(json.encode(data));f:close();print('PASS '..count..' native weapon facts/descriptions unchanged')
