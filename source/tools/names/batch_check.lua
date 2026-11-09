-- Command and batch regressions; install only in the private naming lab.
assert(os.getenv('FORTHAMMER_PROBE_LAB'), 'private lab only')
local core = reqscript('internal/forthammer-names/core')
local command = reqscript('forthammer-names')
local random = reqscript('internal/forthammer-names/random')
local json = require('json')
local assertions, draws = 0, 0
local function check(value, message)
    assert(value, message)
    assertions = assertions + 1
end
local function first(limit)
    draws = draws + 1
    check(limit >= 1, 'empty random range')
    return 1
end
local function rejected(category, count, occupied)
    local before = draws
    local items, err = core.generate_batch(category, count, first, occupied)
    check(not items and type(err) == 'string', 'invalid batch accepted')
    check(draws == before, 'invalid batch consumed randomness')
end
for _,bad in ipairs{false, '2', 0, -1, 1.5, math.huge, -math.huge, 0/0} do
    rejected('family', bad)
end
rejected('family', nil)
rejected('family', 1e300)
rejected('family', #assert(core.candidates('family'))+1)
rejected('unknown', 1)
rejected(false, 1)
check(not core.candidates(false), 'non-string candidate category accepted')
check(not core.generate_batch('family', 1, nil), 'missing RNG accepted')

local capacities = {}
for _,category in ipairs(core.categories()) do
    local candidates = assert(core.candidates(category))
    capacities[category] = #candidates
    local count = math.min(100, #candidates)
    local batch = assert(core.generate_batch(category, count, function(n) return n end))
    check(#batch == count, 'wrong batch size: '..category)
    local seen, allowed = {}, {}
    for _,item in ipairs(candidates) do allowed[core.normalize(item.name)] = true end
    for _,item in ipairs(batch) do
        local key = core.normalize(item.name)
        check(allowed[key] and not seen[key], 'invalid or repeated batch name: '..category)
        seen[key] = true
    end
    -- Candidate storage must survive sampling, including data-backed type packs.
    check(#assert(core.candidates(category)) == #candidates, 'sampling changed the catalog')
    if count == #candidates then rejected(category, 1, seen) end
end
local family = assert(core.candidates('family'))
local occupied = {[family[1].name:upper():gsub(' ', '-')]=true, [family[2].name]=false}
local occupied_before = json.encode(occupied)
local remaining = assert(core.generate_batch('family', #family-1, first, occupied))
check(#remaining == #family-1, 'wrong remaining capacity')
local included_second = false
for _,item in ipairs(remaining) do
    check(core.normalize(item.name) ~= core.normalize(family[1].name), 'normalized collision')
    if item.name == family[2].name then included_second = true end
end
check(included_second and json.encode(occupied) == occupied_before, 'occupied set changed or false entry blocked')
rejected('family', #family, occupied)
local calls = 0
local partial, rng_err = core.generate_batch('family', 2, function()
    calls = calls+1
    return calls == 1 and 1 or 0
end)
check(not partial and calls == 2 and rng_err:find('invalid index'), 'partial batch escaped failed RNG')

-- Every two-draw index path has equal probability. Exhausting a small actual
-- category must therefore yield every ordered pair exactly once.
local small = assert(core.candidates('hospital'))
local pairs_seen, pair_count = {}, 0
for a=1,#small do
    for b=1,#small-1 do
        local step = 0
        local pair = assert(core.generate_batch('hospital', 2, function(limit)
            step = step+1
            check(limit == #small-step+1, 'sampling range did not shrink')
            return step == 1 and a or b
        end))
        local key = pair[1].name .. '/' .. pair[2].name
        check(pair[1].name ~= pair[2].name and not pairs_seen[key], 'biased or repeated ordered pair')
        pairs_seen[key] = true; pair_count = pair_count+1
    end
end
check(pair_count == #small*(#small-1), 'missing ordered pairs')
local full = assert(core.generate_batch('person-female', capacities['person-female'], function(n) return math.ceil(n/2) end))
local full_seen = {}
for _,item in ipairs(full) do
    check(not full_seen[item.name], 'full personal batch repeated a name')
    full_seen[item.name] = true
end
check(#full == capacities['person-female'], 'full personal batch incomplete')

-- Capture the command's own print binding, restoring it even on assertion errors.
local previous_print, previous_random = rawget(command, 'print'), random.index
local output = {}
local function invoke(args, rng)
    output = {}
    command.print = function(text) output[#output+1] = text end
    random.index = rng or first
    return pcall(command.main, args)
end
local command_cases = 0
local ok, err = xpcall(function()
    for _,count in ipairs{'abc', '', '2cats', '0', '-1', '1.5', '101', '1e309'} do
        local passed, failure = invoke({'family', count})
        check(not passed and tostring(failure):find('integer count'), 'bad CLI count accepted: '..count)
        check(#output == 0, 'bad CLI count printed names')
        command_cases = command_cases+1
    end
    for _,args in ipairs{{'hospital',tostring(capacities.hospital+1)}, {'unknown','1'}, {'family','1','extra'}} do
        check(not invoke(args), 'invalid CLI arguments accepted')
        check(#output == 0, 'failed CLI batch printed names')
        command_cases = command_cases+1
    end
    calls = 0
    local passed, failure = invoke({'family','2'}, function()
        calls = calls+1
        return calls == 1 and 1 or 0
    end)
    check(not passed and tostring(failure):find('invalid index') and #output == 0, 'CLI printed partial RNG result')
    command_cases = command_cases+1
    for _,args in ipairs{{}, {'help'}, {'--help'}, {'-h'}} do
        check(invoke(args) and #output == 3, 'help failed')
        for _,category in ipairs(core.categories()) do
            check(output[2]:find(category, 1, true), 'help missing category')
        end
        command_cases = command_cases+1
    end
    for _,args in ipairs{{'family'}, {'family',tostring(math.min(100,capacities.family))}, {'person-female','100'}} do
        check(invoke(args), 'valid command failed')
        local count = args[2] and tonumber(args[2]) or 1
        check(#output == count, 'wrong printed count')
        local seen = {}
        for _,text in ipairs(output) do
            local name = text:match('^(.-) %-%- ')
            check(name and not seen[name] and text:find('Sources:', 1, true), 'duplicate or unsourced output')
            seen[name] = true
        end
        command_cases = command_cases+1
    end
end, debug.traceback)
command.print, random.index = previous_print, previous_random
assert(ok, err)
local started = os.clock()
local batch = assert(core.generate_batch('person-female', 100, random.index))
local report = {result='PASS', assertions=assertions, command_cases=command_cases,
    capacity=capacities, unique_person_batch=#batch, batch_cpu_seconds=os.clock()-started,
    equally_reachable_ordered_pairs=pair_count, full_person_batch=#full}
local f = assert(io.open(os.getenv('FORTHAMMER_PROBE_LAB')..'/results/names-batch.json', 'w'))
f:write(json.encode(report)); f:close()
print(json.encode(report))
