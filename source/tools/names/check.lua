-- Development-only probe; install in the private lab, never the shipping mod.
assert(os.getenv('FORTHAMMER_PROBE_LAB'), 'isolated lab only')
local core = reqscript('internal/forthammer-names/core')
local data = reqscript('internal/forthammer-names/data').data
local assertions = 0
local function check(value, message)
    assert(value, message)
    assertions = assertions + 1
end
local capacity = {}
for _,category in ipairs(core.categories()) do
    local entries = assert(core.candidates(category))
    capacity[category] = #entries
    local seen = {}
    for _,item in ipairs(entries) do
        check(item.name:match('^[A-Za-z ]+$'), 'encoding: '..item.name)
        check(#item.name <= 64, 'length: '..item.name)
        local key = core.normalize(item.name)
        check(not seen[key], 'duplicate: '..item.name)
        check(not core.is_reserved(item.name), 'canon collision: '..item.name)
        check(#item.sources > 0 and item.gloss ~= '', 'missing provenance')
        if #item.roots == 3 and (category == 'family' or category == 'clan'
                or category:match('^person%-')) then
            check(item.grouping and item.grouping:find('[',1,true), 'family grouping lost')
        end
        for _,word in ipairs(item.roots) do
            local roots = data.types[category] and data.types[category].roots or data.roots
            check(roots[word] ~= nil, 'unknown root')
        end
        seen[key] = true
    end
    local item, err = core.generate(category, math.random, seen)
    check(item == nil and err:find('No unused'), 'exhaustion did not fail')
    local first = entries[1]
    local only = {}
    for i=2,#entries do only[entries[i].name:upper():gsub(' ', '-')] = true end
    check(core.generate(category, function(n) check(n==1, 'normalization failed'); return 1 end, only).name == first.name,
        'occupied-name filtering')
end
local family = assert(core.candidates('family'))
local grouped
for _,item in ipairs(family) do
    if item.grouping then grouped = item; break end
end
check(grouped ~= nil, 'missing grouped family labels')
check(core.describe(grouped):find('Reading: '..grouped.grouping,1,true), 'family reading not displayed')
local original_root = grouped.roots[1]
grouped.roots[1] = 'caller mutation'
for _,item in ipairs(assert(core.candidates('family'))) do
    if item.name == grouped.name then check(item.roots[1] == original_root, 'family candidate aliases catalog') end
end
local people = assert(core.candidates('person-male'))
local first_root = people[1].roots[1]
people[1].roots[1] = 'caller mutation'
check(people[#family+1].roots[1] == first_root, 'personal candidates share mutable roots')
check(core.candidates('family')[1].roots[1] == first_root, 'personal candidate aliases catalog')
for _,bad in ipairs{0,-1,0.5,1e9,'1'} do
    local item, err = core.generate('family', function() return bad end)
    check(not item and err:find('invalid index'), 'invalid RNG accepted')
end
check(not core.generate('patronymic', math.random), 'invented ancestry endpoint')
check(not core.generate('epithet', math.random), 'invented epithet endpoint')
check(not core.generate(false, math.random), 'invalid category accepted')
check(not core.generate('family', nil), 'missing RNG accepted')
check(core.is_reserved('  kARAZ A-karak '), 'reserved normalization')
local seen = {}
for _=1,capacity.family do
    local item = assert(core.generate('family', math.random, seen))
    check(not seen[item.name], 'repeat before exhaustion')
    seen[item.name]=true
end
check(not core.generate('family',math.random,seen), 'family exhaustion')
print(require('json').encode({assertions=assertions,capacity=capacity,result='PASS'}))
