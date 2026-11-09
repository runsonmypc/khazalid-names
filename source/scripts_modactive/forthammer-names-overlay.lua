-- Correct the shared personal/group selector only during native squad creation.
--@ module = true
local gui = require('gui')
local overlay = require('plugins.overlay')
local pools = reqscript('internal/forthammer-names/pools')
local adapter = reqscript('internal/forthammer-names/adapter')
local creation = reqscript('internal/forthammer-names/creation')
local random = reqscript('internal/forthammer-names/random')

SquadNaming = defclass(SquadNaming, overlay.OverlayWidget)
SquadNaming.ATTRS {
    desc='Use Khazalid squad vocabulary during new Dwarf squad creation.',
    default_enabled=true,
    viewscreens='dwarfmode',
    fullscreen=true,
}
function SquadNaming:onInput(keys)
    if self.simulating then return false end
    local uniform = df.global.game.main_interface.assign_uniform
    if not uniform.open or uniform.context ~= df.assign_uniform_context_type.CREATE_SQUAD_FROM_SQUAD_MENU
            or not adapter.eligibility() then return false end
    if not pools.resolve('squad') then return false end -- old caches remain unchanged
    self.simulating = true
    local ok, err = pools.with_type('squad',function()
        gui.simulateInput(dfhack.gui.getDFViewscreen(true),keys)
    end)
    self.simulating = false
    if not ok then dfhack.printerr('Khazalid squad naming failed: '..tostring(err)) end
    return true -- forwarded exactly once; never replay a failed creation input
end

LocationNaming = defclass(LocationNaming, overlay.OverlayWidget)
LocationNaming.ATTRS {
    desc='Give newly created Dwarf taverns, libraries, hospitals and guildhalls reviewed Khazalid names.',
    default_enabled=true,
    viewscreens='dwarfmode/LocationSelector',
    fullscreen=true,
}
function LocationNaming:onInput(keys)
    if self.simulating or not (keys._MOUSE_L or keys.SELECT) then return false end
    local selector = df.global.game.main_interface.location_selector
    if not selector.open or selector.context ~= df.location_selector_context_type.ZONE_MEETING_AREA_ASSIGNMENT
            or selector.choosing_temple_religious_practice then return false end
    local before = creation.snapshot()
    if not before then return false end
    self.simulating = true
    local ok,err = xpcall(function()
        -- simulateInput re-enters the native feed/overlay chain. Only this
        -- widget declines recursion; search and other overlays still run.
        gui.simulateInput(dfhack.gui.getDFViewscreen(true),keys)
        local initialized,result = creation.finish(before,random.index)
        if not initialized then error(result) end
    end,debug.traceback)
    self.simulating = false
    if not ok then dfhack.printerr('Khazalid location creation: '..tostring(err)) end
    return true -- input was forwarded once; never replay a failed native action
end
OVERLAY_WIDGETS = {squad=SquadNaming,location=LocationNaming}
