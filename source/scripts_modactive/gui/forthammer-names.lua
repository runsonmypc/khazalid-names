-- Preview Khazalid suggestions or explicitly change a name.
local dialogs = require('gui.dialogs')
local core = reqscript('internal/forthammer-names/core')
local random = reqscript('internal/forthammer-names/random')
local adapter = reqscript('internal/forthammer-names/adapter')
local targets = reqscript('internal/forthammer-names/targets')
local data = reqscript('internal/forthammer-names/data').data
local variety = reqscript('internal/forthammer-names/variety')

local function wrapped(text)
    local width = dfhack.screen.getWindowSize()
    return text:wrap(math.max(20, math.min(88, width - 10)))
end

local function message(text)
    dialogs.showMessage('Khazalid names', wrapped(text), COLOR_WHITE)
end

local function confirm(proposal, on_cancel)
    local kind = proposal.kind
    local item = proposal.item
    local confirmation
    confirmation = dialogs.showYesNoPrompt('Accept name change?',
        wrapped('Current: '..proposal.old_text..'\nProposed: '..proposal.new_text..'\n\n'
        ..(proposal.fit_text and (proposal.fit_text..'\n\n') or '')
        ..core.describe(item,kind == 'artifact')..'\n\n'
        ..(kind == 'unit' and ('Only the forename changes; family name and nickname stay as they are.\n'
            ..(proposal.before[1].nickname ~= '' and ('Nickname (unchanged): '..proposal.before[1].nickname..'\n') or '')) or '')
        ..'Enter applies this change. Escape '..(on_cancel and 'returns to the choices' or 'cancels')..' without changing the name.'), COLOR_WHITE,
        function()
            -- Restore the prior pause state before constructing another modal.
            confirmation:dismiss()
            local ok, failure = adapter.accept(proposal)
            message(ok and ('Name changed to '..proposal.new_text..'. Save normally to keep it.') or failure)
        end,on_cancel and function()
            confirmation:dismiss()
            on_cancel()
        end)
    -- DialogWindow also dismisses after invoking the callback. A second native
    -- dismissal would restore this screen's pause state over the new modal.
    local dismiss = confirmation.dismiss
    local dismissed = false
    confirmation.dismiss = function(self)
        if dismissed then return end
        dismissed = true
        dismiss(self)
    end
end

local function propose(kind, id, category, namespace)
    if kind == 'artifact' then
        local list,err = adapter.artifact_options(id,random.index,namespace)
        if not list then message(err); return end
        local choices = {}
        for index,option in ipairs(list.options) do
            choices[#choices+1] = {text=option.tier..': '..option.item.name,index=index}
        end
        local function show_choices(selected)
            dialogs.ListBox{frame_title='Names for this item',
                text=wrapped('Choose a title to review its meaning and fit. All compatible alternatives are listed. Escape closes without changes.'),
                text_pen=COLOR_WHITE,choices=choices,selected=selected,
                on_select=function(_,choice)
                    local proposal,failure = adapter.preview_option(list,choice.index)
                    if not proposal then message(failure); return end
                    confirm(proposal,function() show_choices(choice.index % #choices + 1) end)
                end}:show()
        end
        show_choices(1)
        return
    end
    local proposal,err = adapter.suggest(kind,id,category,random.index,namespace)
    if not proposal then message(err); return end
    confirm(proposal)
end

local function suggestions()
    dialogs.showListPrompt('Name suggestions',
        'Choose a category. These suggestions do not change the world.', COLOR_WHITE,
        core.categories(), function(_, choice)
            local category = choice.text
            local items, err
            if category:match('^person%-') or category:match('^forename%-') then
                items,err = core.generate_batch(category,8,random.index)
            else
                items,err = variety.interleave(assert(core.candidates(category)),random.index)
            end
            if not items then message(err); return end
            local choices = {}
            for index,item in ipairs(items) do
                if index > 8 then break end
                choices[#choices+1] = {text=item.name, item=item}
            end
            dialogs.showListPrompt('Suggested names',
                'Select a name for meaning and sources. No history or geography is asserted.', COLOR_WHITE,
                choices, function(_, choice) message(core.describe(choice.item)) end)
        end)
end

-- Capture selection before opening a modal that changes UI focus.
local selected = dfhack.gui.getSelectedUnit(true)
local selected_id = selected and selected.id
local sex = selected and selected.sex
local selected_item = dfhack.gui.getSelectedItem(true)
local selected_artifact = selected_item and dfhack.items.getGeneralRef(selected_item,df.general_ref_type.IS_ARTIFACT)
local selected_artifact_id = selected_artifact and selected_artifact.artifact_id
local ctx = adapter.eligibility()
local choices = {{text='Browse suggestions (no changes)', action=suggestions}}
if ctx then
    if selected_artifact_id and targets.resolve('artifact',selected_artifact_id,ctx) then
        choices[#choices+1] = {text='Propose a fitted name for the selected item',
            action=function() propose('artifact',selected_artifact_id,'artifact') end}
    end
    choices[#choices+1] = {text='Propose a name for this fortress',
        action=function() propose('site',ctx.site,'hold') end}
    choices[#choices+1] = {text='Propose a name for a squad, institution, item or construction', action=function()
        local categories = {}
        for _,category in ipairs(core.categories()) do
            if data.types[category] then categories[#categories+1] = category end
        end
        dialogs.showListPrompt('Choose target type','Only eligible existing targets are listed.',COLOR_WHITE,categories,function(_,choice)
            local category = choice.text
            local current,err = adapter.eligibility()
            if not current then message(err); return end
            local available = targets.list(category,current)
            if #available == 0 then message('No eligible '..category..' targets. Browse suggestions to inspect the sourced names.'); return end
            dialogs.showListPrompt('Choose '..category,'Select the actual target to preview a name.',COLOR_WHITE,available,function(_,target)
                propose(category,target.id,category,target.namespace)
            end,nil,nil,true)
        end)
    end}
    if selected_id and (sex == 0 or sex == 1) then
        choices[#choices+1] = {text='Propose a forename for the selected Dwarf',
            action=function() propose('unit',selected_id,sex == 0 and 'forename-female' or 'forename-male') end}
    end
end

dialogs.showListPrompt('Khazalid names',
    'Attested roots; adapted compounds. No automatic renaming or earned epithets.\n'
    ..'Select a Dwarf for a forename or a named item for a fitted title.', COLOR_WHITE,
    choices, function(_, choice) choice.action() end)
