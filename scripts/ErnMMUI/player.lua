--[[
ErnMMUI for OpenMW.
Copyright (C) 2026 Erin Pentecost

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
]]
local ui          = require('openmw.ui')
local util        = require('openmw.util')
local pself       = require('openmw.self')
local statsHud    = require('scripts.ErnMMUI.render.statshud')

local healthStat  = pself.type.stats.dynamic.health(pself)
local fatigueStat = pself.type.stats.dynamic.fatigue(pself)
local magickaStat = pself.type.stats.dynamic.magicka(pself)

local hud         = statsHud.New(
    healthStat.current, healthStat.base + healthStat.modifier,
    fatigueStat.current, fatigueStat.base + fatigueStat.modifier,
    magickaStat.current, magickaStat.base + magickaStat.modifier)


local root = ui.create {
    name = "root",
    layer = 'HUD',
    type = ui.TYPE.Widget,
    props = {
        relativePosition = util.vector2(0, 0),
        relativeSize = util.vector2(1, 1),
        anchor = util.vector2(0, 0),
    },
    content = ui.content {
        hud:getElement()
    }
}

local function onUpdate(dt)
    hud:onUpdate(dt,
        healthStat.current, healthStat.base + healthStat.modifier,
        fatigueStat.current, fatigueStat.base + fatigueStat.modifier,
        magickaStat.current, magickaStat.base + magickaStat.modifier)
    root:update()
end

return {
    engineHandlers = {
        onUpdate = onUpdate,
    }
}
