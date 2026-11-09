-- Complete identities must not depend on DF's nickname display preference.
--@ module = true
function full_name(name)
    -- onlyLastPart omits both first name and nickname in native translateName.
    -- Match its capitalization and spacing without allocating a native copy or
    -- temporarily changing the live name/display settings.
    local first = name.first_name
    local last = dfhack.translation.translateName(name, false, true)
    if first == '' then return last end
    first = first:sub(1,1):upper() .. first:sub(2)
    return first .. (last == '' and '' or ' ' .. last)
end
