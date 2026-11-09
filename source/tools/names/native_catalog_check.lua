-- Exhaust new family and hold raw rendering without changing world objects.
assert(os.getenv('FORTHAMMER_PROBE_LAB'),'private lab only')
local core=reqscript('internal/forthammer-names/core')
local raw=df.global.world.raws.language
local tokens,language={}
for i,w in ipairs(raw.words)do tokens[w.word]=i end
for i,t in ipairs(raw.translations)do if t.name=='FORTHAMMER_KHAZALID'then language=i end end
assert(language)
local name=df.language_name:new()
local counts={}
local ok,err=xpcall(function()
 for _,category in ipairs{'family','hold'}do
  counts[category]=0
  for _,item in ipairs(core.candidates(category))do
   name.first_name='';name.nickname='';name.language=language;name.has_name=true;name.type=df.language_name_type.Site
   for i=0,6 do name.words[i]=-1;name.parts_of_speech[i]=df.part_of_speech.Noun end
   if category=='hold'then
    name.words[0]=assert(tokens.FH_KHAZ_HOLD_PREFIX);name.parts_of_speech[0]=df.part_of_speech.Prefix
    name.words[1]=assert(tokens[item.token])
   else name.words[0]=assert(tokens[item.token])end
   assert(dfhack.translation.translateName(name)==item.name,'native rendering mismatch: '..item.name)
   local english=dfhack.translation.translateName(name,true)
   assert(english~='' and not english:find('%?'),'missing English forms')
   counts[category]=counts[category]+1
  end
 end
end,debug.traceback)
name:delete();assert(ok,err)
print(require('json').encode{result='PASS',exhaustive_native_rendering=counts})
