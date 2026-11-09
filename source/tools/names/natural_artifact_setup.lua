-- Private fixture preparation only. No mood, artifact, history, name, cooldown,
-- pause-state or construction-stage writes. DF must perform construction itself.
-- Modes: plan (default), apply, status. apply is deliberately single-use per lab.
-- DFHack 53.14-r2: Lua API buildings.constructBuilding / items.createItem;
-- hack/scripts/modtools/create-item.lua provides the drink-in-barrel pattern.
local lab=assert(os.getenv('FORTHAMMER_PROBE_LAB'),'private naming lab only')
assert(lab=='/tmp/forthammer-probe-cc9yblvy','this setup belongs to the naming lab')
local mode=... or 'plan'
assert(mode=='plan' or mode=='apply' or mode=='status','use plan, apply or status')
local json=require('json')
require('dfhack.buildings')
local adapter=reqscript('internal/forthammer-names/adapter')
local ctx=assert(adapter.eligibility())
local path=lab..'/results/names-natural-artifact-setup.json'
local function point(pos)return {x=pos.x,y=pos.y,z=pos.z}end
local function now()return {year=df.global.cur_year,tick=df.global.cur_year_tick}end
local function write(report)
    local file=assert(io.open(path,'w'));file:write(json.encode(report),'\n');file:close()
end
local function load_report()
    local file=io.open(path)
    if not file then return nil end
    local text=file:read('*a');file:close()
    return json.decode(text)
end
local existing=load_report()
if mode=='status' then
    assert(existing,'no setup report exists')
    assert(existing.site_id==ctx.site and existing.civ_id==ctx.civ,'setup belongs to another fortress')
    local result={stage=existing.stage,report=path,workshops={},created_item_count=#existing.items}
    for _,entry in ipairs(existing.workshops) do
        local building=df.building.find(entry.id)
        result.workshops[#result.workshops+1]={id=entry.id,kind=entry.kind,exists=building~=nil,
            build_stage=building and building:getBuildStage(),
            max_build_stage=building and building:getMaxBuildStage()}
    end
    print(json.encode(result))
    return
end
assert(not existing,'setup was already attempted; inspect status/report, do not create duplicate fixtures')
assert(df.global.pause_state,'pause the game before planning or applying setup')

local creator
local citizen_count=0
for _,unit in ipairs(df.global.world.units.active) do
    if unit.civ_id==ctx.civ and dfhack.units.isCitizen(unit) then
        local raw=unit.race>=0 and df.global.world.raws.creatures.all[unit.race]
        if raw and raw.creature_id=='DWARF' then
            citizen_count=citizen_count+1
            assert(not unit.flags1.has_mood,'a citizen is already in a mood; do not apply initial setup now')
            if not creator and dfhack.maps.getTileBlock(unit.pos)
                    and dfhack.maps.getWalkableGroup(unit.pos)>0 then creator=unit end
        end
    end
end
assert(creator,'no citizen has a usable floor position; allow native walkability to update first')
assert(citizen_count>=20,'this natural-trigger fixture expects at least 20 native Dwarf citizens')
local origin=point(creator.pos)
local group=dfhack.maps.getWalkableGroup(origin)
local material_tokens={stone='INORGANIC:GRANITE',wood='PLANT:OAK:WOOD',
    food='PLANT:MUSHROOM_HELMET_PLUMP:STRUCTURAL',drink='PLANT:MUSHROOM_HELMET_PLUMP:DRINK'}
local materials={}
for key,token in pairs(material_tokens) do
    materials[key]=assert(dfhack.matinfo.find(token),'required fixture material is unavailable: '..token)
end
local allowed_shapes={[df.tiletype_shape.FLOOR]=true,[df.tiletype_shape.BOULDER]=true,
    [df.tiletype_shape.PEBBLES]=true}
local function floor(pos)
    local designation,occupancy=dfhack.maps.getTileFlags(pos)
    if not designation or designation.hidden or designation.flow_size~=0 or occupancy.building~=0 then return false end
    local tile=dfhack.maps.getTileType(pos)
    return tile~=nil and allowed_shapes[df.tiletype.attrs[tile].shape]
        and not dfhack.maps.getPlantAtTile(pos) and not dfhack.buildings.findAtTile(pos)
        and dfhack.maps.getWalkableGroup(pos)==group
end
local reserved={}
local function key(x,y)return x..':'..y end
local function search(min_radius,max_radius,predicate)
    for radius=min_radius,max_radius do
        for dy=-radius,radius do
            for dx=-radius,radius do
                if math.max(math.abs(dx),math.abs(dy))==radius then
                    local pos={x=origin.x+dx,y=origin.y+dy,z=origin.z}
                    if predicate(pos) then return pos end
                end
            end
        end
    end
end
local staging=assert(search(0,8,floor),'no clear accessible staging floor within eight tiles')
reserved[key(staging.x,staging.y)]=true
local function workshop_floor(pos)
    -- Reserve a visible dry 5x5 square, keeping an unbuilt walking border around
    -- each actual 3x3 workshop. No digging, trees, fluids or existing buildings.
    for dy=-1,3 do
        for dx=-1,3 do
            local x,y=pos.x+dx,pos.y+dy
            if reserved[key(x,y)] or not floor{x=x,y=y,z=pos.z} then return false end
        end
    end
    return true
end
local planned={}
for _,kind in ipairs{'Craftsdwarfs','Carpenters','Masons'} do
    assert(df.workshop_type[kind]~=nil,'unsupported native workshop enum: '..kind)
    local pos=assert(search(4,30,workshop_floor),'no clear accessible workshop footprint for '..kind)
    planned[#planned+1]={kind=kind,pos=pos}
    for dy=-1,3 do
        for dx=-1,3 do reserved[key(pos.x+dx,pos.y+dy)]=true end
    end
end
local report={schema=1,stage='planned',site_id=ctx.site,civ_id=ctx.civ,at=now(),
    creator_id=creator.id,creator_hfid=creator.hist_figure_id,citizen_count=citizen_count,
    origin=origin,staging=staging,planned_workshops=planned,materials=material_tokens,
    supplies={loose_granite_boulders=20,loose_oak_logs=20,food_stacks=4,
        food_stack_size=100,wine_barrels=4,wine_stack_size=100,construction_boulders=3},
    note='Synthetic unnamed private test resources; workshop jobs are queued through the construction API. '
        ..'No mood trigger, artifact item/job/name, cooldown, artifact counter, or history is created or changed. '
        ..'Native mood demands may need additional recorded supplies after inspection with showmood.',
    items={},workshops={}}
if mode=='plan' then print(json.encode(report));return end

-- Write intent before the first native mutation. Even a partial failure blocks
-- replay: the operator can inspect precisely which objects were created.
report.stage='applying';write(report)
local function create(item_type,material_key,purpose,stack_size)
    local material=materials[material_key]
    local created=dfhack.items.createItem(creator,item_type,-1,material.type,material.index)
    assert(created and #created>0,'native resource production returned no items for '..purpose)
    for _,item in ipairs(created) do
        report.items[#report.items+1]={id=item.id,type=item:getType(),subtype=item:getSubtype(),
            mat_type=item:getActualMaterial(),mat_index=item:getActualMaterialIndex(),
            material=material_tokens[material_key],purpose=purpose,maker_hfid=item:getMaker(),
            position=point(item.pos),stack_size=item:getStackSize()}
    end
    write(report)
    assert(#created==1,'unexpected resource multiplicity; all returned IDs are recorded')
    local item=created[1]
    assert(not item.flags.artifact and not item.flags.artifact_mood,'unexpected artifact resource')
    assert(dfhack.items.moveToGround(item,staging),'could not place fixture resource on staging floor')
    if stack_size then item:setStackSize(stack_size) end
    local entry=report.items[#report.items]
    entry.position=point(item.pos);entry.stack_size=item:getStackSize();write(report)
    return item,entry
end
local ok,err=xpcall(function()
    for _,entry in ipairs(planned) do
        local boulder=create(df.item_type.BOULDER,'stone','construction: '..entry.kind)
        local building,problem=dfhack.buildings.constructBuilding{pos=entry.pos,
            type=df.building_type.Workshop,subtype=df.workshop_type[entry.kind],items={boulder},
            width=3,height=3,full_rectangle=true}
        assert(building,problem)
        local jobs={}
        for _,job in ipairs(building.jobs) do jobs[#jobs+1]={id=job.id,type=job.job_type} end
        report.workshops[#report.workshops+1]={id=building.id,kind=entry.kind,pos=entry.pos,
            construction_item_id=boulder.id,initial_build_stage=building:getBuildStage(),jobs=jobs}
        write(report)
        assert(building:getBuildStage()<building:getMaxBuildStage(),'workshop unexpectedly completed without native construction')
        assert(#jobs>0,'workshop has no queued native construction job')
    end
    for _=1,20 do create(df.item_type.BOULDER,'stone','loose stone supply') end
    for _=1,20 do create(df.item_type.WOOD,'wood','loose wood supply') end
    for _=1,4 do create(df.item_type.PLANT,'food','edible plump helmet supply',100) end
    for _=1,4 do
        local barrel=create(df.item_type.BARREL,'wood','wine container')
        local drink,entry=create(df.item_type.DRINK,'drink','dwarven wine supply',100)
        assert(dfhack.items.moveToContainer(drink,barrel),'could not place wine in its barrel')
        entry.container_id=barrel.id;entry.position=point(drink.pos);write(report)
    end
    report.stage='queued';report.completed_at=now();write(report)
end,debug.traceback)
if not ok then report.stage='failed';report.error=tostring(err);write(report);error(err) end
print(json.encode({stage=report.stage,created_items=#report.items,workshops=#report.workshops,
    creator_id=creator.id,staging=staging,report=path,
    next='Allow DF to construct workshops normally; use status to inspect their build stages.'}))
