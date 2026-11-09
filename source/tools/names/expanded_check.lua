-- Disposable native-object tests, never installed in normal games.
assert(os.getenv('FORTHAMMER_PROBE_LAB'),'private lab only')
local core=reqscript('internal/forthammer-names/core')
local data=reqscript('internal/forthammer-names/data').data
local pools=reqscript('internal/forthammer-names/pools')
local adapter=reqscript('internal/forthammer-names/adapter')
local targets=reqscript('internal/forthammer-names/targets')
local ctx=assert(adapter.eligibility())
local l=df.global.world.raws.language
local raw=assert(pools.entity())
local language
for i,t in ipairs(l.translations) do if t.name=='FORTHAMMER_KHAZALID' then language=i end end
local function selector_signature(t)
 local v={}
 for s=0,5 do for i,w in ipairs(t.words[s]) do v[#v+1]=s..':'..w..':'..t.parts[s][i] end end
 return table.concat(v,',')
end
local major=raw.symbols.symbols_major[df.entity_name_type.OTHER]
local minor=raw.symbols.symbols_minor[df.entity_name_type.OTHER]
local before=selector_signature(major)..selector_signature(minor)
local stats={}
local type_names={squad='Squad',civilization='Civilization',government='EntitySite',tavern='FoodStore',guildhall='Guildhall',library='Library',hospital='Hospital',business='MerchantCompany',artifact='Artifact',road='Road',tunnel='Tunnel',bridge='Bridge',wall='Wall'}
for category,pack in pairs(data.types) do
 local n=df.language_name:new()
 local sample,seen={},{}
 for _,item in ipairs(core.candidates(category)) do
  local token
  for i,w in ipairs(l.words) do if w.word==item.token then token=i;break end end
  assert(token,'missing raw '..item.token)
  n.first_name='';n.nickname='';n.language=language;n.type=df.language_name_type[type_names[category]];n.has_name=true
  for i=0,6 do n.words[i]=-1;n.parts_of_speech[i]=df.part_of_speech.Noun end
  n.words[0]=token
  local text=dfhack.translation.translateName(n)
  assert(core.normalize(text)==core.normalize(item.name),category..' native rendering mismatch '..text)
  assert(not core.is_reserved(text),'reserved name')
 end
 if data.native_pools[category] then
  local slots=assert(pools.resolve(category))
  local a,b=df.language_word_table:new(),df.language_word_table:new()
  pools.write(a,slots);pools.write(b,slots)
  local reviewed={}
  for _,item in ipairs(core.candidates(category)) do reviewed[core.normalize(item.name)]=true end
  for i=1,300 do
   pools.original_generate(n,language,df.language_name_type[type_names[category]],a,b)
   local text=dfhack.translation.translateName(n)
   assert(reviewed[core.normalize(text)],'native output is not a complete reviewed name: '..text)
   assert(not core.is_reserved(text),'reserved native name '..text)
   local count=0
   for j=0,6 do if n.words[j]>=0 then
    count=count+1
    assert(l.words[n.words[j]].word:find('FH_KHAZ_TYPE_'..category:upper()..'_',1,true)==1,'foreign type word')
   end end
   assert(count==1,'native template added unreviewed components')
   if #sample<3 then sample[#sample+1]=text end
   seen[text]=true
  end
  a:delete();b:delete()
 end
 n:delete()
 local distinct=0;for _ in pairs(seen) do distinct=distinct+1 end
 stats[category]={candidates=#pack.candidates,native_draws=data.native_pools[category] and 300 or 0,distinct=distinct,examples=sample}

end
local n=df.language_name:new()
for _=1,200 do
 dfhack.translation.generateName(n,language,df.language_name_type.Squad,major,minor)
 for j=0,6 do if n.words[j]>=0 then assert(not l.words[n.words[j]].word:find('GIVEN_'),'forename leaked into squad') end end
end
n:delete()
assert(before==selector_signature(major)..selector_signature(minor),'API guard failed to restore personal selectors')
local ok=pools.with_type('squad',function() error('intentional test failure') end)
assert(not ok and before==selector_signature(major)..selector_signature(minor),'failure restoration')
local global=0
for side=0,1 do for cat=0,df.language_name_category._last_item do for s=0,5 do
 for _,idx in ipairs(l.word_table[side][cat].words[s]) do if idx>=0 and l.words[idx].word:match('^FH_KHAZ_') then global=global+1 end end
end end end
assert(global==0,'global word leakage')
local json=require('json')
local report={result='PASS',categories=stats,global_leaks=global,api_squad_draws=200,scope_restoration=true}
local f=assert(io.open(os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-expanded.json','w'));f:write(json.encode(report));f:close()
print(json.encode(report))
