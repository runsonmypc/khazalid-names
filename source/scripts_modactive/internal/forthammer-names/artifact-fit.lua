-- Pure fit policy: a title remains symbolic; only these matching facts are stated.
--@ module = true
local core = reqscript('internal/forthammer-names/core')
local type_roots = {az=true,grund=true,grong=true,klad=true,makaz=true,thrund=true,klinka=true,khrum=true,agrul=true,zunthrum=true}
local material_roots = {azul=true,duraz=true,uzkul=true,angaz=true,agril=true,izor=true,mizpal=true}

function assess(candidate, profile)
    local facts = profile.facts
    local evidence, scores = {}, {type=0,material=0,image=0}
    for _,root in ipairs(candidate.roots) do
        -- Fitted titles cannot name a different tool/body material. In the
        -- general catalog those same words are explicitly symbolic imagery.
        if type_roots[root] and not facts.type[root] and not facts.image[root] then return 0, {}, false end
        if material_roots[root] and not facts.material[root] and not facts.image[root] then return 0, {}, false end
        for _,kind in ipairs{'type','material','image'} do
            local text = facts[kind][root]
            if text then
                evidence[#evidence+1] = text
                local weight = kind == 'type' and (root == 'makaz' and 2 or 4)
                    or kind == 'image' and 3 or 2
                scores[kind] = math.max(scores[kind],weight)
            end
        end
    end
    return scores.type + scores.material + scores.image, evidence, true
end

function explain(candidate, profile)
    local score, evidence, compatible = assess(candidate,profile)
    if not compatible then
        return 'This title does not match the item: its concrete type or material is unsupported by the observed facts.'
    end
    if score == 0 then
        return 'General symbolic suggestion; no supported item-specific match. The title does not describe physical properties.'
    end
    return 'Fits this item: '..table.concat(evidence,'; ')..'. Other imagery in the title is symbolic.'
end

-- One finite pass; uniformly sample the strongest unused matching tier. Once
-- occupied names exhaust that tier, the next compatible tier becomes available.
-- Zero-scoring neutral imagery is a fallback; incompatible concrete types or
-- materials never become fallback suggestions, even after every match is used.
function choose(candidates, profile, random_index, occupied)
    if type(random_index) ~= 'function' then return nil, 'A random-index function is required.' end
    local blocked = {}
    for name,present in pairs(occupied or {}) do
        if present then blocked[core.normalize(name)] = true end
    end
    local best, score = {}, -1
    for _,candidate in ipairs(candidates) do
        if not blocked[core.normalize(candidate.name)] then
            local value, _, compatible = assess(candidate,profile)
            if compatible then
                if value > score then best = {}; score = value end
                if value == score then best[#best+1] = candidate end
            end
        end
    end
    if #best == 0 then return nil, 'No unused compatible names remain for this item.' end
    local index = random_index(#best)
    if type(index) ~= 'number' or index % 1 ~= 0 or index < 1 or index > #best then
        return nil, 'Random source returned an invalid index.'
    end
    return best[index]
end

-- Expose every compatible unused option, including weaker matches and neutral
-- imagery. One assessment per candidate; full native preview happens on choice.
function alternatives(candidates, profile, random_index, occupied)
    local variety = reqscript('internal/forthammer-names/variety')
    if type(random_index) ~= 'function' then return nil,'A random-index function is required.' end
    local blocked, tiers, scores = {}, {}, {}
    for name,present in pairs(occupied or {}) do
        if present then blocked[core.normalize(name)] = true end
    end
    for _,candidate in ipairs(candidates) do
        if not blocked[core.normalize(candidate.name)] then
            local score,_,compatible = assess(candidate,profile)
            if compatible then
                if not tiers[score] then tiers[score] = {}; scores[#scores+1] = score end
                tiers[score][#tiers[score]+1] = candidate
            end
        end
    end
    if #scores == 0 then return nil,'No unused compatible names remain for this item.' end
    table.sort(scores,function(a,b) return a > b end)
    local result = {}
    for _,score in ipairs(scores) do
        local ordered,err = variety.interleave(tiers[score],random_index)
        if not ordered then return nil,err end
        for _,item in ipairs(ordered) do
            result[#result+1] = {item=item,score=score,
                tier=score == 0 and 'Symbolic' or score == scores[1] and 'Best fit' or 'Other fit'}
        end
    end
    return result
end
