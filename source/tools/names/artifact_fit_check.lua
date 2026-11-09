-- Pure policy regressions against independent fixture expectations.
-- Run in the private naming lab; these synthetic labels never enter the game.
assert(os.getenv('FORTHAMMER_PROBE_LAB'), 'private lab only')
local fit = reqscript('internal/forthammer-names/artifact-fit')
local core = reqscript('internal/forthammer-names/core')
local json = require('json')
local assertions = 0
local function check(value, message)
    assert(value, message)
    assertions = assertions + 1
end
local function candidate(name, ...)
    return {name=name, roots={...}}
end
local function profile(types, materials, images)
    return {facts={type=types or {}, material=materials or {}, image=images or {}}}
end
local hammer = profile({grund='actual hammer', makaz='actual weapon'},
    {azul='metal body'}, {drakk='depicted dragon'})
local highest = candidate('Fixture highest', 'azul', 'grund', 'drakk')
local same_tier = candidate('Fixture second', 'grund', 'azul', 'drakk')
local typed_image = candidate('Fixture typed image', 'grund', 'drakk')
local material_image = candidate('Fixture material image', 'azul', 'drakk')
local typed = candidate('Fixture typed', 'grund', 'bryn')
local broad = candidate('Fixture broad', 'makaz', 'bryn')
local symbolic = candidate('Fixture symbolic', 'bryn', 'karaz')
local wrong_type = candidate('Fixture wrong type', 'az', 'azul', 'drakk')
local wrong_material = candidate('Fixture wrong material', 'grund', 'duraz', 'drakk')
local expected = {
    {highest,9}, {same_tier,9}, {typed_image,7}, {material_image,5},
    {typed,4}, {broad,2}, {symbolic,0}, {wrong_type,0}, {wrong_material,0},
}
for _,case in ipairs(expected) do
    local score, evidence, compatible = fit.assess(case[1],hammer)
    check(compatible == (case[1] ~= wrong_type and case[1] ~= wrong_material),
        'compatibility confused neutral imagery with concrete mismatch')
    check(score == case[2], 'unexpected independently specified score: '..case[1].name)
    check((score > 0) == (#evidence > 0), 'incompatible title leaked evidence')
end
local _, evidence = fit.assess(highest,hammer)
check(table.concat(evidence,';') == 'metal body;actual hammer;depicted dragon',
    'fit evidence does not identify the actual matching facts')
check(fit.explain(highest,hammer):find('Fits this item:',1,true)
    and fit.explain(highest,hammer):find('Other imagery',1,true), 'fitted explanation not qualified')
for _,item in ipairs{symbolic} do
    local text = fit.explain(item,hammer)
    check(text:find('General symbolic suggestion',1,true)
        and text:find('does not describe physical properties',1,true), 'fallback not explicit')
end

for _,item in ipairs{wrong_type,wrong_material} do
    check(fit.explain(item,hammer):find('does not match the item',1,true),
        'incompatible title was described as safe symbolic fallback')
end

-- Depicting a different kind of equipment supports its image without changing
-- the underlying object. A bare generic equipment word must not imply an axe.
check(fit.assess(candidate('Fixture depicted axe','az','grund'),
    profile({grund='hammer'}, {}, {az='depicted war axe'})) == 7, 'depicted tool rejected')
check(fit.assess(candidate('Fixture axe','az'),profile({makaz='weapon'})) == 0,
    'generic weapon evidence asserted a war axe')
check(fit.assess(candidate('Fixture carving','agrul','drakk'),
    profile({agrul='stone carving'}, {duraz='stone body'}, {drakk='depicted dragon'})) == 7,
    'supported carving and depicted creature did not combine')
check(fit.assess(candidate('Fixture carving','agrul','drakk'),
    profile({}, {azul='metal body'}, {drakk='depicted dragon'})) == 0,
    'dragon depiction turned a metal statue into stone carving')
check(fit.assess(candidate('Fixture carving','agrul','drakk'),
    profile({}, {duraz='stone body'}, {drakk='depicted dragon'})) == 0,
    'stone and dragon alone invented a carved-object type')
check(fit.assess(candidate('Fixture material image','duraz','grund'),
    profile({grund='hammer'}, {}, {duraz='depicted stone object'})) == 7,
    'depicted material could not support an image')
check(fit.assess(candidate('Fixture repeated class','grund','makaz','drakk','gor'),
    profile({grund='hammer',makaz='weapon'}, {}, {drakk='dragon',gor='wild beast'})) == 7,
    'multiple roots from one fact class inflated its contribution')

local candidates = {symbolic,typed_image,highest,wrong_type,same_tier,
    typed,broad,material_image,wrong_material}
local before = json.encode(candidates)
local available = {}
for i=1,2 do
    local chosen = assert(fit.choose(candidates,hammer,function(limit)
        check(limit == 2, 'weaker or incompatible name entered the strongest tier')
        return i
    end))
    available[chosen.name] = true
end
check(available[highest.name] and available[same_tier.name], 'strongest tier not uniformly reachable')
local occupied = {[highest.name:upper():gsub(' ','-')]=true, [same_tier.name]=false}
local occupied_before = json.encode(occupied)
check(assert(fit.choose(candidates,hammer,function(n)
    check(n == 1, 'normalized occupied name not excluded'); return 1
end,occupied)).name == same_tier.name, 'false occupancy excluded an available name')
check(json.encode(occupied) == occupied_before and json.encode(candidates) == before,
    'selector mutated caller data')
occupied[same_tier.name] = true
check(assert(fit.choose(candidates,hammer,function(n)
    check(n == 1, 'lower fitted tier has unexpected size'); return 1
end,occupied)).name == typed_image.name, 'exhausted strongest tier blocked the next fitting tier')

local ordered_paths = {}
for first=1,3 do
    for second=1,2 do
        local pool = {highest,same_tier,candidate('Fixture third','azul','grund','drakk')}
        local used = {}
        local one = assert(fit.choose(pool,hammer,function(n)
            check(n == 3, 'first fair draw range'); return first
        end,used))
        used[one.name] = true
        local two = assert(fit.choose(pool,hammer,function(n)
            check(n == 2, 'second fair draw range'); return second
        end,used))
        local key = one.name..'/'..two.name
        check(one.name ~= two.name and not ordered_paths[key], 'biased or repeated ordered pair')
        ordered_paths[key] = true
    end
end

local used, previous_score, draws = {}, math.huge, 0
for _=1,#candidates-2 do
    local item = assert(fit.choose(candidates,hammer,function(n)
        check(n > 0, 'empty draw'); draws = draws+1; return n
    end,used))
    local score, _, compatible = fit.assess(item,hammer)
    check(compatible, 'incompatible title entered exhaustion fallback')
    check(not used[item.name] and score <= previous_score, 'repeat or incorrect tier ordering')
    used[item.name], previous_score = true, score
end
local exhausted, error_text = fit.choose(candidates,hammer,function()
    error('exhaustion consumed randomness')
end,used)
check(not exhausted and error_text:find('No unused',1,true), 'compatible catalog not exhausted while mismatched names remain')
local fallback = assert(fit.choose({symbolic},profile(),function(n)
    check(n == 1, 'fallback range'); return 1
end))
check(fallback == symbolic and fit.explain(fallback,profile()):find('General symbolic',1,true),
    'unknown facts did not offer a labelled fallback')
-- Unsupported shapes/materials must not acquire titles of unrelated objects.
local barrel = profile()
local incompatible = {candidate('Fixture stone carving','drakk','agrul'),
    candidate('Fixture handgun','kol','drakk','thrund'),
    candidate('Fixture metal','azul','drakk'),candidate('Fixture bone','uzkul','dok')}
local barrel_pool = {symbolic}
for _,item in ipairs(incompatible) do barrel_pool[#barrel_pool+1] = item end
check(assert(fit.choose(barrel_pool,barrel,function(n)
    check(n == 1,'barrel fallback includes unsupported concrete nouns'); return 1
end)) == symbolic,'unsupported barrel did not retain neutral imagery')
local missing, why = fit.choose(barrel_pool,barrel,function()
    error('incompatible-only fallback consumed randomness')
end,{[symbolic.name]=true})
check(not missing and why:find('No unused compatible',1,true),
    'exhausted neutral barrel imagery fell back to incompatible names')
local missing_only, why_only = fit.choose(incompatible,barrel,function()
    error('incompatible-only catalog consumed randomness')
end)
check(not missing_only and why_only:find('No unused compatible',1,true),
    'catalog containing only mismatches produced a suggestion')
for _,bad in ipairs{false,'1',0,-1,1.5,3,math.huge,-math.huge,0/0} do
    local value, reason = fit.choose({highest,same_tier},hammer,function() return bad end)
    check(not value and reason:find('invalid index',1,true), 'invalid RNG result accepted')
end
local value, reason = fit.choose({highest},hammer,function() return nil end)
check(not value and reason:find('invalid index',1,true), 'nil RNG result accepted')
for _,rng in ipairs{false,1,'random'} do
    local ok, value, reason = pcall(fit.choose,{highest},hammer,rng)
    check(ok and not value and type(reason) == 'string', 'non-function RNG threw or was accepted')
end
local ok, value, reason = pcall(fit.choose,{highest},hammer,nil)
check(ok and not value and type(reason) == 'string', 'missing RNG threw or was accepted')

-- Report actual finite-catalog capacities separately from synthetic policy
-- fixtures. Only compatible neutral imagery remains after fitted tiers empty.
-- Context-free catalog generation is deliberately unaffected.
local capacity = {}
local profiles = {
    metal_war_axe=profile({az='war axe',makaz='weapon'},{azul='metal body'}),
    metal_hammer=profile({grund='hammer',makaz='weapon'},{azul='metal body'}),
    metal_handgun=profile({thrund='handgun',makaz='weapon'},{azul='metal body'}),
    bone_item_dragon_image=profile({}, {uzkul='bone body'}, {drakk='depicted dragon'}),
    stone_anvil=profile({grong='anvil'},{duraz='stone body'}),
    stone_carving=profile({agrul='stone carving'},{duraz='stone body'}),
    stone_carving_dragon_image=profile({agrul='stone carving'},{duraz='stone body'},{drakk='depicted dragon'}),
    metal_hammer_dragon_image=profile({grund='hammer',makaz='weapon'},{azul='metal body'},{drakk='depicted dragon'}),
    silver_container=profile({}, {azul='metal body',agril='silver body'}),
    copper_container=profile({}, {azul='metal body',izor='copper body'}),
    iron_armour=profile({klad='armour'}, {azul='metal body',angaz='iron body'}),
    obsidian_object=profile({}, {duraz='stone body',mizpal='obsidian body'}),
    silver_statue=profile({zunthrum='statue'}, {azul='metal body',agril='silver body'}),
    stone_statue=profile({zunthrum='statue',agrul='stone carving'}, {duraz='stone body'}),
    unknown=profile(),
}
local catalog = assert(core.candidates('artifact'))
local exposed = assert(core.candidates('artifact'))[1]
local canonical_name,canonical_gloss = exposed.name,exposed.gloss
local canonical_root,canonical_source = exposed.roots[1],exposed.sources[1]
exposed.gloss='fixture forged meaning';exposed.roots[1]='fixture invented root'
exposed.sources[1]='fixture invented source';exposed.status='fixture invented history'
local untouched = assert(core.candidates('artifact'))[1]
check(untouched.name == canonical_name and untouched.gloss == canonical_gloss
    and untouched.roots[1] == canonical_root and untouched.sources[1] == canonical_source,
    'returned candidate aliases the reviewed catalog or nested arrays')
for label,context in pairs(profiles) do
    local tiers, fitted, peak, peak_count, neutral, excluded = {}, 0, 0, 0, 0, 0
    for _,item in ipairs(catalog) do
        local score, _, compatible = fit.assess(item,context)
        if compatible then
            tiers[tostring(score)] = (tiers[tostring(score)] or 0)+1
            if score > 0 then fitted = fitted+1 else neutral = neutral+1 end
            if score > peak then peak,peak_count = score,0 end
            if score == peak then peak_count = peak_count+1 end
        else excluded = excluded+1 end
    end
    check(label == 'unknown' and fitted == 0 or label ~= 'unknown' and fitted > 0,
        'catalog lacks expected fitted/fallback coverage: '..label)
    capacity[label] = {total=#catalog,fitted=fitted,strongest_score=peak,
        strongest_count=peak_count,tiers=tiers,neutral=neutral,excluded=excluded,
        compatible=fitted+neutral}
end
local barrel_used = {}
for _=1,capacity.unknown.compatible do
    local item = assert(fit.choose(catalog,profiles.unknown,function(n) return n end,barrel_used))
    local score, _, compatible = fit.assess(item,profiles.unknown)
    check(compatible and score == 0 and not barrel_used[item.name],
        'actual catalog barrel fallback repeated or admitted concrete mismatch')
    barrel_used[item.name] = true
end
local no_barrel, no_barrel_reason = fit.choose(catalog,profiles.unknown,function()
    error('actual neutral catalog exhaustion consumed randomness')
end,barrel_used)
check(not no_barrel and no_barrel_reason:find('No unused compatible',1,true),
    'actual neutral catalog exhaustion admitted unrelated equipment/material names')
check(capacity.unknown.compatible > 0 and capacity.unknown.excluded > 0,
    'unknown-profile capacity did not separate imagery from concrete nouns')
for _,label in ipairs{'metal_war_axe','metal_hammer','metal_handgun'} do
    check(capacity[label].strongest_count > 6,'strongest tier did not expand beyond version185: '..label)
end
local report = {result='PASS',assertions=assertions,equally_reachable_ordered_pairs=6,
    exhaustive_fixture_draws=draws,capacity=capacity}
local f = assert(io.open(os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-artifact-fit.json','w'))
f:write(json.encode(report)); f:close(); print(json.encode(report))
