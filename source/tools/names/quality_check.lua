-- Offline Lua regression harness. Run from the repository root with
-- python3 tools/checks/run_lua.py tools/names/quality_check.lua (Lua 5.4).
-- Models test policy and UI callback routing, not native DF compatibility.
local modules = {}
function reqscript(path)
    if modules[path] then return modules[path] end
    local env = setmetatable({}, {__index=_G})
    modules[path] = env
    assert(loadfile('scripts_modactive/'..path..'.lua','t',env))()
    return env
end
local count = 0
local function check(value,why) assert(value,why); count=count+1 end
local core = reqscript('internal/forthammer-names/core')
local fit = reqscript('internal/forthammer-names/artifact-fit')
local variety = reqscript('internal/forthammer-names/variety')
local function candidate(name,...) return {name=name,roots={...}} end
local one = candidate('One','grund','drakk','azul')
local two = candidate('Two','grund','drakk')
local red = candidate('Red','zan','dok')
local black = candidate('Black','kol','dok')
local sun = candidate('Sun','zon','karaz')
local wrong = candidate('Wrong','az','duraz')
local profile = {facts={type={grund='hammer'},material={azul='metal'},image={drakk='dragon'}}}
local input = {red,black,sun,two,wrong,one}
local rows = assert(fit.alternatives(input,profile,function(n) return n end))
check(#rows == 5,'complete compatible list')
check(rows[1].item == one and rows[1].tier == 'Best fit','best match first')
check(rows[2].item == two and rows[2].tier == 'Other fit','weaker fit accessible immediately')
check(rows[3].tier == 'Symbolic','neutral tier explicit')
check(variety.key(rows[3].item) ~= variety.key(rows[4].item),'different motifs before colour variants')
check(rows[5].item == black,'remaining colour variant still accessible')
check(input[1] == red and input[6] == one,'input ordering preserved')
local blocked = {ONE=true,WRONG=true}
local filtered = assert(fit.alternatives(input,profile,function(n) return n end,blocked))
check(#filtered == 4 and filtered[1].item == two,'occupied best does not hide weaker names')
local empty,err = fit.alternatives({wrong},profile,function() error('unexpected RNG') end)
check(not empty and err:find('No unused compatible',1,true),'mismatched-only exhaustion')
for _,bad in ipairs{false,0,-1,1.5,math.huge,0/0,'1'} do
    local result,why = fit.alternatives(input,profile,function() return bad end)
    check(not result and why:find('invalid index',1,true),'invalid RNG rejected')
end
local unknown = {facts={type={},material={},image={}}}
local all = core.candidates('artifact')
local exposed = assert(fit.alternatives(all,unknown,function(n) return n end))
local seen = {}
for _,row in ipairs(exposed) do
    local score,_,compatible = fit.assess(row.item,unknown)
    check(compatible and score == 0 and row.tier == 'Symbolic','unknown only neutral')
    check(not seen[row.item.name],'no duplicate option');seen[row.item.name]=true
end
for _,item in ipairs(all) do
    local _,_,compatible = fit.assess(item,unknown)
    check(not not seen[item.name] == compatible,'every compatible option reachable')
end
-- Adapter snapshots: isolate native reads and exercise actual list/preview code.
local reads,scans,previews = 0,0,0
local context = {world={},site=2,civ=3,group=4,epoch=1}
local name = {first_name='',nickname='',language=0,type=1,has_name=true,words={},parts_of_speech={}}
for i=0,6 do name.words[i]=-1; name.parts_of_speech[i]=0 end
local target = {name=name,namespace='fixture',object={item={}}}
modules['internal/forthammer-names/targets'] = {
    resolve=function() return target end,
    occupied=function() scans=scans+1;return {} end,
}
modules['internal/forthammer-names/native'] = {}
modules['internal/forthammer-names/artifact-facts'] = {
    read=function() reads=reads+1;return {facts=profile.facts,signature='original'} end,
}
dfhack = {onStateChange={},translation={translateName=function() return 'Existing' end}}
SC_MAP_UNLOADED=1;SC_WORLD_UNLOADED=2
local adapter = reqscript('internal/forthammer-names/adapter')
adapter.eligibility=function() return context end
local list = assert(adapter.artifact_options(42,function(n) return n end))
check(reads == 1 and scans == 1,'listing must scan facts/occupancy once')
local fresh = {before={name},artifact_signature='original'}
adapter.preview=function(kind,id,item,namespace)
    previews=previews+1
    check(kind == 'artifact' and id == 42 and namespace == 'fixture','preview re-resolves exact target')
    return fresh
end
check(adapter.preview_option(list,1) == fresh and previews == 1,'selected option previewed once')
name.nickname='changed'
check(not adapter.preview_option(list,1),'stale name rejected')
name.nickname=''
fresh.artifact_signature='changed'
check(not adapter.preview_option(list,1),'stale item facts rejected')
fresh.artifact_signature='original'
for _,field in ipairs{'world','site','civ','group','epoch'} do
    local saved=context[field]
    -- eligibility returns a fresh native context; don't mutate the list snapshot.
    local changed={};for k,v in pairs(context) do changed[k]=v end
    changed[field]={}
    adapter.eligibility=function() return changed end
    local n=previews
    check(not adapter.preview_option(list,1) and previews == n,'stale '..field..' rejected before preview')
end
adapter.eligibility=function() return context end
adapter.preview=function() return nil,'collision' end
check(not adapter.preview_option(list,1),'new collision rechecked')
check(not adapter.preview_option(list,999999),'invalid option rejected')
-- Exercise the shipping GUI's callback graph with inert dialog/native stubs.
local dialog, commits, selection_reads = nil,0,0
local dialogs = {}
function dialogs.showListPrompt(title,text,color,choices,on_select)
    dialog={title=title,choices=choices,on_select=on_select}
end
function dialogs.ListBox(info)
    function info:show() dialog=self end
    return info
end
function dialogs.showYesNoPrompt(title,text,color,on_accept,on_cancel)
    dialog={title=title,text=text,on_accept=on_accept,on_cancel=on_cancel,
        dismiss=function(self) self.dismissed=true;self.dismissals=(self.dismissals or 0)+1 end}
    return dialog
end
function dialogs.showMessage(title,text) dialog={title=title,text=text} end
package.loaded['gui.dialogs']=dialogs
modules['internal/forthammer-names/random']={index=function(n) return n end}
modules['internal/forthammer-names/targets'].resolve=function() return target end
adapter.artifact_options=function() return list end
adapter.preview_option=function(_,index)
    selection_reads=selection_reads+1
    return {kind='artifact',old_text='Existing',new_text=list.options[index].item.name,
        item=list.options[index].item,fit_text='Fixture fit'}
end
adapter.accept=function() commits=commits+1;return true end
dfhack.gui={getSelectedUnit=function() end,getSelectedItem=function() return {} end}
dfhack.items={getGeneralRef=function() return {artifact_id=42} end}
dfhack.screen={getWindowSize=function() return 100,60 end}
df={general_ref_type={IS_ARTIFACT=1}}
COLOR_WHITE=7
string.wrap=function(text) return text end
assert(loadfile('scripts_modactive/gui/forthammer-names.lua'))()
local selected_action
for _,choice in ipairs(dialog.choices) do
    if choice.text == 'Propose a fitted name for the selected item' then selected_action=choice.action end
end
check(selected_action ~= nil,'selected-item GUI path present')
selected_action()
local picker=dialog
check(#picker.choices == #list.options and picker.selected == 1,'GUI exposes complete list')
picker.on_select(1,picker.choices[1])
check(dialog.on_cancel and commits == 0 and selection_reads == 1,'review does not apply')
local confirmation=dialog
dialog.on_cancel()
check(confirmation.dismissed,'confirmation dismissed before next dialog')
check(dialog.selected == 2 and commits == 0,'decline returns with next option selected')
check(dialog.on_cancel == nil,'closing list has no mutation callback')
local weaker
for index,option in ipairs(list.options) do
    if option.tier ~= 'Best fit' then weaker=index;break end
end
check(weaker ~= nil,'fixture has accessible lower tier')
dialog.on_select(weaker,dialog.choices[weaker])
check(commits == 0,'lower tier preview does not apply')
confirmation=dialog
dialog.on_accept()
confirmation:dismiss() -- native DialogWindow repeats dismissal after callback
check(confirmation.dismissals == 1,'native dismissal executes only once')
check(confirmation.dismissed,'confirmation dismissed before result modal')
check(commits == 1,'explicit lower tier acceptance applies once')
print('PASS: '..count..' offline quality assertions; native runtime remains a separate gate.')
