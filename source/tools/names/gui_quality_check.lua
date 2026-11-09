-- Native widgets and production callbacks on a temporary artifact fixture.
-- Loaded only by artifact_adapter_check; no persistent fixture is created here.
return function(record, snapshot)
    assert(os.getenv('FORTHAMMER_PROBE_LAB'))
    local dialogs=require('gui.dialogs')
    local old_list,old_prompt,old_message=dialogs.ListBox,dialogs.showYesNoPrompt,dialogs.showMessage
    local view,opened=nil,{}
    local function capture(v) view=v;opened[#opened+1]=v;return v end
    dialogs.ListBox=setmetatable({}, {__index=old_list,
        __call=function(_,info)return capture(old_list(info))end})
    dialogs.showYesNoPrompt=function(...)return capture(old_prompt(...))end
    dialogs.showMessage=function(...)return capture(old_message(...))end
    local before=snapshot(record.name)
    local assertions=0
    local function check(value,why)assert(value,why);assertions=assertions+1 end
    local function pick(predicate)
        local list=assert(view.subviews.list,'expected list widget')
        for i,row in ipairs(list:getChoices()) do
            if predicate(row) then
                local selection=list.setSelected and list or list.list
                selection:setSelected(i);selection:onInput{SELECT=true};return i
            end
        end
        error('expected GUI choice missing')
    end
    local function text(expected)return function(row)return row.text==expected end end
    local ok,err=xpcall(function()
        for _,paused in ipairs{true,false} do
            df.global.pause_state=paused
            dfhack.run_script('gui/forthammer-names')
            pick(text('Propose a name for a squad, institution, item or construction'))
            pick(text('artifact'))
            pick(function(row)return row.id==record.id end)
            local first_picker=view
            local total=#view.subviews.list:getChoices()
            check(total>1,'complete picker unavailable')
            view.subviews.list:setSelected(total)
            view.subviews.list:onInput{SELECT=true}
            check(snapshot(record.name)==before,'preview wrote native name')
            check(df.global.pause_state,'confirmation failed to pause')
            view.subviews[1]:cancel()
            check(snapshot(record.name)==before,'decline wrote native name')
            check(view~=first_picker and view.subviews.list:getSelected()==1,'decline did not wrap to next alternative')
            check(df.global.pause_state==paused,'decline changed pause state')
            -- Closing the actual list requires no confirmation and writes nothing.
            view:onInput{LEAVESCREEN=true}
            check(snapshot(record.name)==before,'closing list wrote native name')
            check(df.global.pause_state==paused,'closing list changed pause state')
        end
        df.global.pause_state=false
        dfhack.run_script('gui/forthammer-names')
        pick(text('Propose a name for a squad, institution, item or construction'))
        pick(text('artifact'))
        pick(function(row)return row.id==record.id end)
        pick(function(row)return row.text:find('Symbolic:',1,true)==1 end)
        check(snapshot(record.name)==before,'symbolic review wrote native name')
        view.subviews[1]:accept()
        check(snapshot(record.name)~=before,'explicit lower-tier acceptance did not write')
        check(df.global.pause_state,'result modal not paused')
        view.subviews[1]:accept()
        check(not df.global.pause_state,'accept/result close left originally running fortress paused')
    end,debug.traceback)
    dialogs.ListBox,dialogs.showYesNoPrompt,dialogs.showMessage=old_list,old_prompt,old_message
    for i=#opened,1,-1 do pcall(function()opened[i]:dismiss()end)end
    df.global.pause_state=true
    assert(ok,err)
    return {result='PASS',assertions=assertions,decline_returns_next=true,
        closing_list_preserves_name=true,lower_tier_accepted=true,pause_true_and_false_preserved=true,
        method='Actual DFHack widgets and production callbacks; synthetic artifact fixture; no simulated elapsed frames.'}
end
