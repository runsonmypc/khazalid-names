-- Development-only: requires a fresh isolated world containing the final raws.
assert(os.getenv('FORTHAMMER_PROBE_LAB'), 'isolated lab only')
local core=reqscript('internal/forthammer-names/core')
local l=df.global.world.raws.language
local e
for _,v in ipairs(df.global.world.raws.entities.all) do if v.code=='MOUNTAIN' then e=v end end
assert(e and e.translation=='FORTHAMMER_KHAZALID','wrong world')
local function foreign(t)
 local n=0
 for slot=0,5 do for _,i in ipairs(t.words[slot]) do
  if i>=0 and l.words[i].word:match('^FH_KHAZ_') then n=n+1 end
 end end
 return n
end
local global_leaks=0
for side=0,1 do for cat=0,df.language_name_category._last_item do
 global_leaks=global_leaks+foreign(l.word_table[side][cat])
end end
assert(global_leaks==0,'custom words leaked into global pools: '..global_leaks)
local allowed={}
for _,key in ipairs{'OTHER','CIV','SITE','LIBRARY','HOSPITAL','MERCHANT_COMPANY','CRAFT_GUILD','ROAD','TUNNEL','BRIDGE','WALL'} do allowed[df.entity_name_type[key]]=true end
local other_leaks=0
for _,v in ipairs(df.global.world.raws.entities.all) do
 for cat=0,df.entity_name_type._last_item do
  if v~=e or not allowed[cat] then
   other_leaks=other_leaks+foreign(v.symbols.symbols_major[cat])+foreign(v.symbols.symbols_minor[cat])
  end
 end
end
assert(other_leaks==0,'custom words leaked into other entity selectors')
local sizes={}
for _,t in ipairs{e.symbols.symbols_major[df.entity_name_type.OTHER],e.symbols.symbols_minor[df.entity_name_type.OTHER]} do
 local row={}
 for slot=0,5 do
  assert(#t.words[slot]>0 and #t.words[slot]==#t.parts[slot],'empty/mismatched selector')
  row[#row+1]=#t.words[slot]
  for _,i in ipairs(t.words[slot]) do
   if slot==1 then assert(i==-1,'family rear must be absent')
   else assert(i>=0 and l.words[i].word:match('^FH_KHAZ_'),'vanilla pool leak') end
   if slot==0 then assert(l.words[i].word:match('^FH_KHAZ_FAMILY_'),'unreviewed native family') end
  end
 end
 sizes[#sizes+1]=row
end
local language
for i,t in ipairs(l.translations) do if t.name=='FORTHAMMER_KHAZALID' then language=i end end
local families={}
for _,v in ipairs(core.candidates('family')) do families[core.normalize(v.name)]=true end
local firsts={}
for _,sex in ipairs{'male','female'} do for _,v in ipairs(core.candidates('forename-'..sex)) do firsts[v.name:lower()]=true end end
local stats={}
for _,kind in ipairs{'Figure','Site'} do
 local seen,examples={},{}
 local name=df.language_name:new()
 for i=1,2000 do
  dfhack.translation.generateName(name,language,df.language_name_type[kind],e.symbols.symbols_major[df.entity_name_type.OTHER],e.symbols.symbols_minor[df.entity_name_type.OTHER])
  local text=dfhack.translation.translateName(name)
  local family=dfhack.translation.translateName(name,false,true)
  assert(families[core.normalize(family)],'invalid native compound '..text)
  if kind=='Figure' then assert(firsts[name.first_name],'invalid first name '..name.first_name) end
  assert(not core.is_reserved(text),'reserved native name')
  if #examples<8 then examples[#examples+1]=text end
  seen[text]=(seen[text] or 0)+1
 end
 name:delete()
 local unique=0
 for _ in pairs(seen) do unique=unique+1 end
 stats[kind]={draws=2000,unique=unique,repeats=2000-unique,examples=examples}
end
local historical={valid=0,invalid={}}
for _,h in ipairs(df.global.world.history.figures) do
 local r=h.race>=0 and df.global.world.raws.creatures.all[h.race]
 if r and r.creature_id=='DWARF' and h.civ_id>=0 then
  local civ=df.historical_entity.find(h.civ_id)
  if civ and civ.entity_raw==e then
   local last=dfhack.translation.translateName(h.name,false,true)
   if firsts[h.name.first_name] and families[core.normalize(last)] then historical.valid=historical.valid+1
   else historical.invalid[#historical.invalid+1]=dfhack.translation.translateName(h.name) end
  end
 end
end
local report={global_leaks=global_leaks,other_entity_leaks=other_leaks,selectors=sizes,samples=stats,historical=historical}
local json=require('json')
local f=assert(io.open(os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-native.json','w'));f:write(json.encode(report));f:close()
print(json.encode(report))
assert(historical.valid>0 and #historical.invalid==0,'worldgen missed native pool installation')
