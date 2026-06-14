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
local HeartHealth = require('scripts.ErnMMUI.render.hearthealth')
local Bar         = require('scripts.ErnMMUI.render.bar')
local core        = require("openmw.core")
local settings    = require("scripts.ErnMMUI.settings.settings")
local pself       = require('openmw.self')

-- from PCP-OpenMW
-- Get a usable color value from a fallback in openmw.cfg
local function configColor(setting)
    local v = core.getGMST('FontColor_color_' .. setting)
    local values = {}
    for i in v:gmatch('([^,]+)') do table.insert(values, tonumber(i)) end
    local color = util.color.rgb(values[1] / 255, values[2] / 255, values[3] / 255)
    return color
end

local function lerpColor(a, b, t)
    return util.color.rgba(
        a.r + (b.r - a.r) * t,
        a.g + (b.g - a.g) * t,
        a.b + (b.b - a.b) * t,
        a.a + (b.a - a.a) * t
    )
end

local healthStat    = pself.type.stats.dynamic.health(pself)
local fatigueStat   = pself.type.stats.dynamic.fatigue(pself)
local magickaStat   = pself.type.stats.dynamic.magicka(pself)

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local COLOR_FATIGUE = configColor("fatigue")
local COLOR_MAGICKA = configColor("magic")
local COLOR_CHARGES = configColor("magic_fill")
local FLASH_FATIGUE = lerpColor(COLOR_FATIGUE, util.color.rgba(0.9, 0.9, 0.9, 1), 0.7)
local FLASH_MAGICKA = lerpColor(COLOR_MAGICKA, util.color.rgba(0.9, 0.9, 0.9, 1), 0.7)
local FLASH_CHARGES = lerpColor(COLOR_CHARGES, util.color.rgba(0.9, 0.9, 0.9, 1), 0.7)

-- ---------------------------------------------------------------------------
-- StatsHUD
-- ---------------------------------------------------------------------------

local function barSize(max)
    return util.vector2(20 * math.sqrt(max) * settings.ui.scaling, 24)
end

---@class StatsHUD
---@field _heartHealth   HeartHealth
---@field _fatigueBar    table   Bar object
---@field _magickaBar    table   Bar object
---@field _chargesBar    table   Bar object
---@field _elem          table   root ui element

local StatsHUDMethods   = {}
StatsHUDMethods.__index = StatsHUDMethods

--- Create a new StatsHUD.
---@return StatsHUD
local function NewStatsHUD()
    local self = {
        _heartHealth = nil,
        _fatigueBar  = nil,
        _magickaBar  = nil,
        _elem        = nil,
    }
    setmetatable(self, StatsHUDMethods)

    -- Build child components.
    self._heartHealth = HeartHealth.New(healthStat.base + healthStat.modifier, healthStat.current)

    self._fatigueBar = Bar.New(
        fatigueStat.current / math.max(fatigueStat.base + fatigueStat.modifier, 1),
        COLOR_FATIGUE, FLASH_FATIGUE, barSize(fatigueStat.base + fatigueStat.modifier))

    self._magickaBar = Bar.New(
        magickaStat.current / math.max(magickaStat.base + magickaStat.modifier, 1),
        COLOR_MAGICKA, FLASH_MAGICKA, barSize(magickaStat.base + magickaStat.modifier))

    -- Root vertical flex: heart rows on top, then fatigue, then magicka.
    self._elem = ui.create({
        type    = ui.TYPE.Flex,
        name    = 'statsHUDRoot',
        props   = {
            horizontal = false,
            arrange    = ui.ALIGNMENT.Start,
            align      = ui.ALIGNMENT.Start,
            autoSize   = true,
        },
        content = ui.content {
            self._heartHealth:getElement().layout,
            self._fatigueBar.elem.layout,
            self._magickaBar.elem.layout,
        },
    })

    return self
end

--- Update every frame from your player_hud script.
---@param self           StatsHUD
---@param dt             number   elapsed seconds

function StatsHUDMethods:onUpdate(dt)
    -- Update the heart health meter (handles its own layout patching internally).
    self._heartHealth:onUpdate(dt, healthStat.current, healthStat.base + healthStat.modifier)

    -- Patch the first child of our root layout to mirror whatever the heart
    -- meter just rebuilt, then update the stat bars.
    self._elem.layout.content[1] = self._heartHealth:getElement().layout

    self._fatigueBar:onUpdate(dt, fatigueStat.current / math.max(fatigueStat.base + fatigueStat.modifier, 1),
        barSize(fatigueStat.base + fatigueStat.modifier))
    self._magickaBar:onUpdate(dt, magickaStat.current / math.max(magickaStat.base + magickaStat.modifier, 1),
        barSize(magickaStat.base + magickaStat.modifier))

    -- The bar elements call elem:update() themselves; we just need to refresh
    -- the root if the heart layout changed (heart meter calls its own update
    -- internally, but the root content slot[1] reference may have changed).
    self._elem:update()
end

--- Destroy all child UI elements.
function StatsHUDMethods:destroy()
    if self._heartHealth then
        self._heartHealth:destroy()
        self._heartHealth = nil
    end
    if self._elem then
        self._elem:destroy()
        self._elem = nil
    end
    -- Bar elements are children of _elem; destroying _elem covers them.
end

--- Return the root UI element for positioning in your HUD layer.
---@return table
function StatsHUDMethods:getElement()
    return self._elem
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
return {
    New = NewStatsHUD,
}
