-- Run with Lua 5.4 from the repo for models, or in the private DFHack lab for both.
local native = df ~= nil
if native then assert(os.getenv('FORTHAMMER_PROBE_LAB'),'private lab only') end
local path = native and assert(dfhack.findScript('internal/forthammer-names/artifact-facts'))
    or 'scripts_modactive/internal/forthammer-names/artifact-facts.lua'
local assertions = 0
local function check(value,message)
    assertions = assertions+1
    assert(value,message)
end
local model_df = {item_type={},global={world={raws={creatures={all={}}}}}}
for i,name in ipairs{'WEAPON','ANVIL','TOOL','ARMOR','HELM','GLOVES','SHOES','PANTS','STATUE','FIGURINE','AMULET'} do
    model_df.item_type[name],model_df.item_type[i] = i,name
end
for _,class in ipairs{'item_statuest','item_figurinest','itemimprovement_art_imagest',
    'itemimprovement_sewn_imagest','itemimprovement_illustrationst','art_image_element_creaturest'} do
    model_df[class] = {is_instance=function(_,object)return object.class == class end}
end
model_df.item_constructed = {is_instance=function(_,object)return object.constructed == true end}
local definitions, materials, chunks = {}, {}, {}
model_df.art_image_chunk = {find=function(id)return chunks[id] end}
local env = setmetatable({df=model_df,dfhack={items={getSubtypeDef=function(kind,subtype)
    return definitions[kind..':'..subtype]
end},matinfo={decode=function(kind,index)return materials[kind..':'..index] end}}},{__index=_G})
assert(loadfile(path,'t',env))()
local function material(kind,index,id,mode,flags)
    local value={mode=mode,material={id=id,flags=flags}}
    if mode=='inorganic' then value.inorganic={id=id} end
    function value:getToken()return self.mode..':'..id end
    materials[kind..':'..index]=value
end
material(0,1,'IRON','inorganic',{IS_METAL=true})
material(0,2,'GRANITE','inorganic',{IS_STONE=true})
material(1,3,'BONE','creature',{BONE=true})
material(1,4,'HORN','creature',{HORN=true})
material(1,5,'TOOTH','creature',{TOOTH=true})
material(1,6,'SHELL','creature',{SHELL=true})
material(0,7,'WARPSTONE','inorganic',{IS_STONE=true,IS_METAL=true})
material(0,8,'GUNPOWDER','inorganic',{IS_STONE=true})
material(0,9,'UNKNOWN','inorganic',{IS_METAL=true})
material(2,10,'WOOD','plant',{WOOD=true})
material(0,11,'SILVER','inorganic',{IS_METAL=true})
material(0,12,'COPPER','inorganic',{IS_METAL=true})
material(0,13,'OBSIDIAN','inorganic',{IS_STONE=true})
material(0,14,'STEEL','inorganic',{IS_METAL=true})
material(0,15,'PIG_IRON','inorganic',{IS_METAL=true})
material(0,16,'STERLING_SILVER','inorganic',{IS_METAL=true})
material(0,17,'BRONZE','inorganic',{IS_METAL=true})
material(0,18,'NATIVE_SILVER','inorganic',{IS_STONE=true})
material(0,19,'NATIVE_COPPER','inorganic',{IS_STONE=true})
material(3,20,'GLASS_GREEN','builtin',{IS_GLASS=true})
material(3,21,'GLASS_CLEAR','builtin',{IS_GLASS=true})
material(3,22,'GLASS_CRYSTAL','builtin',{IS_GLASS=true})
material(0,23,'SILVER','inorganic',{IS_STONE=true})
material(1,24,'COPPER','creature',{IS_METAL=true})
material(0,25,'OBSIDIAN','inorganic',{IS_METAL=true})
local function item(kind,id)
    local value={id=1,kind=model_df.item_type[kind],sub=0,mat=0,index=1,constructed=true,improvements={}}
    definitions[value.kind..':0']={id=id,armorlevel=0,skill_melee='HAMMER'}
    function value:getType()return self.kind end
    function value:getSubtype()return self.sub end
    function value:getActualMaterial()return self.mat end
    function value:getActualMaterialIndex()return self.index end
    return value
end
local function has(value,group,root)return env.read(value).facts[group][root] ~= nil end
for _,id in ipairs{'ITEM_WEAPON_AXE_BATTLE','ITEM_WEAPON_AXE_GREAT'} do
    local value=item('WEAPON',id)
    check(has(value,'type','az'),'war axe lost');check(has(value,'type','makaz'),'weapon lost')
end
for _,id in ipairs{'ITEM_WEAPON_HAMMER_WAR','ITEM_WEAPON_MAUL'} do
    check(has(item('WEAPON',id),'type','grund'),'hammer lost')
end
for _,id in ipairs{'ITEM_WEAPON_HANDGUN','ITEM_WEAPON_PISTOL','ITEM_WEAPON_CANNON',
    'ITEM_WEAPON_CROSSBOW','ITEM_WEAPON_AXE_TRAINING','ITEM_WEAPON_HALBERD'} do
    local value=item('WEAPON',id)
    check(not has(value,'type','grund'),'shared HAMMER skill invented hammer')
    check(not has(value,'type','az'),'non-war-axe invented war axe')
    check(has(value,'type','thrund')==(id=='ITEM_WEAPON_HANDGUN'),'handgun classification')
end
check(has(item('ANVIL',''),'type','grong'),'anvil lost')
check(has(item('TOOL','ITEM_TOOL_KNIFE_CARVING'),'type','makaz'),'functional tool lost')
for _,id in ipairs{'ITEM_TOOL_BOOK_BINDING','RUNE_SMITING','ITEM_TOOL_DIE','UNKNOWN'} do
    check(not has(item('TOOL',id),'type','makaz'),'tool enum invented functional tool')
end
for _,kind in ipairs{'ARMOR','HELM','GLOVES','SHOES','PANTS'} do
    local value=item(kind,'ARMOUR')
    check(not has(value,'type','klad'),'clothing invented armour')
    definitions[value.kind..':0'].armorlevel=1
    check(has(value,'type','klad'),'protective armour lost')
end
local value=item('AMULET','')
check(has(value,'material','azul'),'iron lost')
check(has(value,'material','angaz'),'exact ironwork lost')
value.index=2;check(has(value,'material','duraz'),'granite lost')
value.mat=1;value.index=3;check(has(value,'material','uzkul'),'bone lost')
for _,pair in ipairs{{1,4},{1,5},{1,6},{0,7},{0,8},{0,9},{2,10},{-1,-1}} do
    value.mat,value.index=table.unpack(pair)
    check(next(env.read(value).facts.material)==nil,'unsupported material acquired a material fact')
end
-- Materials from decoration, containment and contamination are not body facts.
value.mat,value.index=1,3
value.improvements={{mat_type=0,mat_index=1,getType=function()return 1 end,isDecoration=function()return true end}}
check(has(value,'material','uzkul') and not has(value,'material','azul'),'decoration became body material')
check(not has(value,'material','wutroth'),'generic wood acquired ancient-oak provenance')

local exact_roots={'angaz','agril','izor','mizpal'}
for _,fixture in ipairs{{0,1,'angaz','azul'},{0,11,'agril','azul'},
        {0,12,'izor','azul'},{0,13,'mizpal','duraz'}} do
    value.mat,value.index=fixture[1],fixture[2]
    local profile=env.read(value)
    check(profile.facts.material[fixture[4]],'exact body lost its broad material')
    for _,root in ipairs(exact_roots) do
        check((profile.facts.material[root]~=nil)==(root==fixture[3]),'exact body acquired another material')
    end
end
for _,fixture in ipairs{{0,14},{0,15},{0,16},{0,17},{0,18},{0,19},
        {3,20},{3,21},{3,22},{0,23},{1,24},{0,25}} do
    value.mat,value.index=table.unpack(fixture)
    local profile=env.read(value)
    for _,root in ipairs(exact_roots) do
        check(not profile.facts.material[root],'alloy, ore, glass, wrong mode or missing flag became an exact body')
    end
end
value.mat,value.index=1,3
for _,fixture in ipairs{{0,1},{0,11},{0,12},{0,13}} do
    value.improvements[1].mat_type,value.improvements[1].mat_index=table.unpack(fixture)
    for _,root in ipairs(exact_roots) do
        check(not has(value,'material',root),'exact decoration material became body material')
    end
end

for _,kind in ipairs{'STATUE','FIGURINE'} do
    local carving=item(kind,'')
    carving.index=2
    local carved=env.read(carving)
    check(carved.facts.type.agrul=='item type: stone carving','stone artwork lost its carving sense')
    check((carved.facts.type.zunthrum~=nil)==(kind=='STATUE'),'statue and figurine conflated')
    check(carved.facts.material.duraz,'stone carving lost its body material')
    for _,pair in ipairs{{0,1},{1,3},{2,10},{0,7},{0,8},{-1,-1}} do
        carving.mat,carving.index=table.unpack(pair)
        check(not has(carving,'type','agrul'),'non-stone artwork acquired stone-carving meaning')
        check(has(carving,'type','zunthrum')==(kind=='STATUE'),'statue affinity depended on body material')
        check(carved.signature~=env.read(carving).signature,'changed carving body retained old signature')
    end
end
local stone_amulet=item('AMULET','');stone_amulet.index=2
check(not has(stone_amulet,'type','agrul'),'stone material alone invented a carving')
check(not has(stone_amulet,'type','zunthrum'),'stone material alone invented a statue')

model_df.global.world.raws.creatures.all[0]={creature_id='STAR_DRAGON'}
model_df.global.world.raws.creatures.all[1]={creature_id='GIANT_CIV'}
model_df.global.world.raws.creatures.all[2]={creature_id='GIANT_CAVE_SPIDER'}
local element={class='art_image_element_creaturest',race=0,caste=0,count=1}
chunks[8]={images={[0]={art_image={elements={element}}}}}
local improvement=value.improvements[1]
improvement.class='itemimprovement_art_imagest';improvement.image={id=8,subid=0}
check(has(value,'image','drakk'),'dragon image lost')
check(env.read(value).facts.image.drakk=='decoration depicts a dragon','decoration explanation leaked implementation details')
check(not has(value,'material','azul'),'depicted metal ornament changed bone body')
local signature=env.read(value).signature
check(signature==env.read(value).signature,'signature unstable')
element.race=1
check(has(value,'image','gronti') and not has(value,'image','drakk'),'image did not follow exact race')
check(signature~=env.read(value).signature,'changed image did not invalidate signature')
element.race=2;check(next(env.read(value).facts.image)==nil,'giant prefix invented giant')
element.race=999;check(next(env.read(value).facts.image)==nil,'invalid race acquired image')
element.race=0;element.count=0;check(next(env.read(value).facts.image)==nil,'zero images acquired motif')
element.count=1
improvement.isDecoration=function()return false end
check(next(env.read(value).facts.image)==nil,'undisplayed improvement acquired motif')
improvement.isDecoration=function()return true end
for _,ref in ipairs{{id=-1,subid=0},{id=8,subid=-1},{id=8,subid=500},{id=99,subid=0}} do
    improvement.image=ref;check(next(env.read(value).facts.image)==nil,'invalid/unloaded image acquired motif')
end
improvement.image={id=8,subid=0}
for _,class in ipairs{'itemimprovement_sewn_imagest','itemimprovement_illustrationst'} do
    improvement.class=class;check(has(value,'image','drakk'),'supported image improvement lost')
end
value.improvements={};value.image={id=8,subid=0}
for _,class in ipairs{'item_statuest','item_figurinest'} do
    value.class=class;check(has(value,'image','drakk'),'primary art image lost')
    check(env.read(value).facts.image.drakk=='item depicts a dragon','primary image explanation called decoration')
end
signature=env.read(value).signature;value.id=2
check(signature~=env.read(value).signature,'replacement item did not invalidate signature')
signature=env.read(value).signature;value.mat,value.index=0,1
check(signature~=env.read(value).signature,'changed material did not invalidate signature')
signature=env.read(value).signature;value.sub=1
check(signature~=env.read(value).signature,'changed subtype did not invalidate signature')

local model_assertions=assertions
local native_items=0
if native then
    local reader=reqscript('internal/forthammer-names/artifact-facts')
    -- Read every extant native item, ensuring all item subclasses can be handled.
    for _,actual in ipairs(df.global.world.items.all) do
        if not actual.flags.garbage_collect then
            local profile=reader.read(actual)
            check(profile.item_id==actual.id,'native item identity lost')
            check(profile.signature==reader.read(actual).signature,'native signature unstable')
            native_items=native_items+1
        end
    end
    local allocated, detach = {}, {}
    local function new(class)local obj=class:new();allocated[#allocated+1]=obj;return obj end
    local function body(actual,token)
        local info=assert(dfhack.matinfo.find(token),'missing fixture material '..token)
        actual:setMaterial(info.type);actual:setMaterialIndex(info.index)
    end
    local function weapon(id)
        local actual=new(df.item_weaponst)
        local subtype=dfhack.items.findSubtype('WEAPON:'..id)
        check(subtype>=0,'missing fixture weapon '..id)
        actual.subtype=dfhack.items.getSubtypeDef(df.item_type.WEAPON,subtype)
        body(actual,'INORGANIC:IRON')
        return actual
    end
    local ok,err=xpcall(function()
        local axe=weapon('ITEM_WEAPON_AXE_BATTLE')
        local axe_profile=reader.read(axe)
        check(axe_profile.facts.type.az and axe_profile.facts.type.makaz and axe_profile.facts.material.azul,'native iron axe')
        body(axe,'INORGANIC:COPPER')
        check(axe_profile.signature~=reader.read(axe).signature,'native metal replacement signature')
        local hammer=weapon('ITEM_WEAPON_HAMMER_WAR')
        check(reader.read(hammer).facts.type.grund,'native hammer lost')
        local gun=weapon('ITEM_WEAPON_HANDGUN')
        check(reader.read(gun).facts.type.thrund and not reader.read(gun).facts.type.grund,'native handgun confused by skill')
        local crossbow=weapon('ITEM_WEAPON_CROSSBOW')
        check(not reader.read(crossbow).facts.type.grund,'native crossbow confused by skill')
        local amulet=new(df.item_amuletst)
        for _,fixture in ipairs{{'INORGANIC:IRON','angaz','azul'},
                {'INORGANIC:SILVER','agril','azul'},{'INORGANIC:COPPER','izor','azul'},
                {'INORGANIC:OBSIDIAN','mizpal','duraz'}} do
            body(amulet,fixture[1])
            local profile=reader.read(amulet)
            check(profile.facts.material[fixture[3]],'native exact material lost broad affinity')
            for _,root in ipairs(exact_roots) do
                check((profile.facts.material[root]~=nil)==(root==fixture[2]),'native exact body conflated')
            end
        end
        for _,token in ipairs{'INORGANIC:STEEL','INORGANIC:PIG_IRON','INORGANIC:STERLING_SILVER',
                'INORGANIC:BRONZE','INORGANIC:NATIVE_SILVER','INORGANIC:NATIVE_COPPER',
                'GLASS_GREEN','GLASS_CLEAR','GLASS_CRYSTAL'} do
            body(amulet,token)
            for _,root in ipairs(exact_roots) do
                check(not reader.read(amulet).facts.material[root],'native alloy, ore or manufactured glass became exact material')
            end
        end
        body(amulet,'CREATURE:DWARF:BONE')
        check(reader.read(amulet).facts.material.uzkul,'native bone lost')
        local ornament=new(df.itemimprovement_art_imagest)
        local gold=assert(dfhack.matinfo.find('INORGANIC:GOLD'))
        ornament.mat_type,ornament.mat_index=gold.type,gold.index
        amulet.improvements:insert('#',ornament)
        detach[#detach+1]=function()amulet.improvements:erase(0)end
        check(ornament:isDecoration(),'native fixture image is not displayed')
        check(not reader.read(amulet).facts.material.azul,'native gold decoration became primary metal')
        local chunk=new(df.art_image_chunk)
        local chunks_live=df.global.world.art_image_chunks.all
        chunk.id=#chunks_live>0 and chunks_live[#chunks_live-1].id+1 or 0
        chunks_live:insert('#',chunk)
        detach[#detach+1]=function()chunks_live:erase(#chunks_live-1)end
        local picture=new(df.art_image)
        chunk.images[0].art_image=picture
        detach[#detach+1]=function()chunk.images[0].art_image=nil end
        local creature=new(df.art_image_element_creaturest)
        for race,raw in ipairs(df.global.world.raws.creatures.all) do
            if raw.creature_id=='STAR_DRAGON' then creature.race=race;break end
        end
        check(df.global.world.raws.creatures.all[creature.race].creature_id=='STAR_DRAGON','missing dragon fixture raw')
        creature.count=1;creature.caste=0
        picture.elements:insert('#',creature)
        detach[#detach+1]=function()picture.elements:erase(0)end
        ornament.image.id,ornament.image.subid=chunk.id,0
        local profile=reader.read(amulet)
        check(profile.facts.image.drakk and profile.facts.material.uzkul and not profile.facts.material.azul,'native decorated bone dragon')
        creature.count=0
        check(not reader.read(amulet).facts.image.drakk and profile.signature~=reader.read(amulet).signature,'native changed image stale signature')
        body(amulet,'INORGANIC:GUNPOWDER');check(next(reader.read(amulet).facts.material)==nil,'native gunpowder became stone')
        body(amulet,'INORGANIC:WARPSTONE');check(next(reader.read(amulet).facts.material)==nil,'native warpstone became mundane metal/stone')
        for _,class in ipairs{df.item_statuest,df.item_figurinest} do
            local carving=new(class)
            body(carving,'INORGANIC:GRANITE')
            local carved=reader.read(carving)
            check(carved.facts.type.agrul and carved.facts.material.duraz,'native stone carving not recognized')
            local is_statue=carving:getType()==df.item_type.STATUE
            check((carved.facts.type.zunthrum~=nil)==is_statue,'native statue/figurine conflated')
            for _,token in ipairs{'INORGANIC:IRON','CREATURE:DWARF:BONE','INORGANIC:WARPSTONE'} do
                body(carving,token)
                local changed=reader.read(carving)
                check(not changed.facts.type.agrul,'native non-stone artwork became stone carving')
                check((changed.facts.type.zunthrum~=nil)==is_statue,'native statue depends on body material')
                check(carved.signature~=changed.signature,'native changed carving retained stale facts')
            end
        end
    end,debug.traceback)
    for i=#detach,1,-1 do detach[i]() end
    for i=#allocated,1,-1 do allocated[i]:delete() end
    assert(ok,err)
    local result={model_assertions=model_assertions,native_assertions=assertions-model_assertions,native_items=native_items,
        fixture='Temporary unregistered items and a temporary registered image chunk; detached and deleted after checks.'}
    local f=assert(io.open(os.getenv('FORTHAMMER_PROBE_LAB')..'/results/artifact-facts.json','w'))
    f:write(require('json').encode(result));f:close()
end
print('PASS '..assertions..' artifact fact assertions ('..model_assertions..' model; '..native_items..' native items)')
