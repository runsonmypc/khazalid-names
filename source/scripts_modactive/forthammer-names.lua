-- Source-grounded Khazalid suggestions; never renames anything automatically.
--@ module = true
--[====[
forthammer-names
===============
Generate name suggestions with meanings and source references.
Usage: forthammer-names <category> [count]
Use `forthammer-names help` for categories, or `gui/forthammer-names` for
suggestions and explicit previewed changes in an eligible Dwarf fortress.
]====]
local core = reqscript('internal/forthammer-names/core')
local random = reqscript('internal/forthammer-names/random')

function main(args)
    if not args[1] or args[1] == 'help' or args[1] == '--help' or args[1] == '-h' then
        print('forthammer-names <category> [count: 1-100]')
        print(table.concat(core.categories(), ', '))
        print('Suggestions only. No patronymics, earned epithets or biography are invented.')
        return
    end
    local count = 1
    if args[2] ~= nil then count = tonumber(args[2]) end
    if not count or count % 1 ~= 0 or count < 1 or count > 100 or args[3] then
        qerror('Expected a category and optional integer count from 1 to 100.')
    end
    local items, err = core.generate_batch(args[1], count, random.index)
    if not items then qerror(err) end
    for _,item in ipairs(items) do
        print(core.describe(item))
    end
end

if not dfhack_flags.module then main({...}) end
