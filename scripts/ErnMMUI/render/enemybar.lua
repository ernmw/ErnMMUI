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

local ui       = require("openmw.ui")
local util     = require("openmw.util")
local types    = require("openmw.types")
local settings = require("openmw.settings")
local const    = require('scripts.ErnMMUI.render.const')
local async    = require('openmw.async')
local colors   = require('scripts.ErnMMUI.render.colors')
local Bar      = require('scripts.ErnMMUI.render.bar')

local FLASH_ENEMYHEALTH

local function updateFlashColors()
    FLASH_ENEMYHEALTH = colors.lerpColor(settings.ui.colorEnemyHealth, const.FLASH_GRAY, 0.7)
end
updateFlashColors()

---@class EnemyBar
---@field _enemyObject table?
---@field _enemyName string?
---@field _enemyHealthStat table
---@field _enemyBar     table   Bar object
---@field _elem          table   root ui element
---@field _wasVisible    boolean whether the bar content was built (enemy valid+alive) last frame
---@field _settingsSub   table?  subscription handle, used to unsubscribe on destroy
local EnemyBarMethods   = {}
EnemyBarMethods.__index = EnemyBarMethods

local paddingLayout     = {
    name = 'padWidget',
    props = { size = util.vector2(math.max(1, 4 * math.ceil(settings.ui.scaling)), math.max(1, 4 * math.ceil(settings.ui.scaling))) },
}

---@param self EnemyBar
---@return boolean visible whether the enemy is currently valid and alive
local function isEnemyVisible(self)
    return self._enemyObject ~= nil
        and self._enemyObject:isValid()
        and not types.Actor.isDead(self._enemyObject)
end

---@param self EnemyBar
local function rebuildContent(self)
    local items = {}

    if isEnemyVisible(self) then
        -- we need to render the bar
        items[#items + 1] = {
            --template = interfaces.MWUI.templates.textHeader,
            type = ui.TYPE.Text,
            props = {
                text = self._enemyName,
                textColor = const.FLASH_GRAY,
                textAlignV = ui.ALIGNMENT.Center,
                textAlignH = ui.ALIGNMENT.Center,
                textSize = 12,
                --anchor = util.vector2(0.5, 0),
            }
        }
        items[#items + 1] = paddingLayout
        items[#items + 1] = self._enemyBar.elem
    end

    self._elem.layout.content = ui.content(items)
end

local function barSize(max)
    if settings.ui.uniformBarLength then
        return util.vector2(const.ENEMY_BAR_LENGTH * settings.ui.scaling, const.BAR_HEIGHT * settings.ui.scaling)
    else
        return util.vector2(const.BAR_LENGTH_FACTOR * math.sqrt(max) * settings.ui.scaling,
            const.BAR_HEIGHT * settings.ui.scaling)
    end
end

---@return EnemyBar
local function NewEnemyBar(enemy)
    local self = {
        _enemyObject = enemy,
        _enemyName = enemy.record.name,
        _enemyHealthStat = enemy.type.stats.dynamic.health(enemy),
        _enemyBar = nil,
        _elem = nil,
        _wasVisible = false,
        _settingsSub = nil,
    }
    setmetatable(self, EnemyBarMethods)

    local makeBars = function()
        updateFlashColors()
        self._enemyBar = Bar.New(
            self._enemyHealthStat.current / math.max(self._enemyHealthStat.base + self._enemyHealthStat.modifier, 1),
            settings.ui.colorEnemyHealth, FLASH_ENEMYHEALTH,
            barSize(self._enemyHealthStat.base + self._enemyHealthStat.modifier))
    end
    makeBars()

    self._elem = ui.create({
        type    = ui.TYPE.Flex,
        name    = 'enemybar',
        props   = {
            horizontal = false,
            arrange    = ui.ALIGNMENT.Start,
            align      = ui.ALIGNMENT.Start,
            autoSize   = true,
        },
        content = ui.content {},
    })

    self._wasVisible = isEnemyVisible(self)
    rebuildContent(self)
    self._elem:update()

    -- Watch for the hearts setting being toggled.
    self._settingsSub = settings.ui.subscribe(async:callback(function(section, key)
        makeBars()
        rebuildContent(self)
        self._elem:update()
    end))

    return self
end

--- Refresh health stat, animate the bar, and rebuild content if visibility changed.
---@param self EnemyBar
---@param dt number elapsed seconds
function EnemyBarMethods:onUpdate(dt)
    local visible = isEnemyVisible(self)

    if visible then
        self._enemyHealthStat = self._enemyObject.type.stats.dynamic.health(self._enemyObject)
        local max = math.max(self._enemyHealthStat.base + self._enemyHealthStat.modifier, 1)
        local ratio = self._enemyHealthStat.current / max
        self._enemyBar:onUpdate(dt, ratio, barSize(max))
    end

    if visible ~= self._wasVisible then
        self._wasVisible = visible
        rebuildContent(self)
        self._elem:update()
    end
end

--- Return the root UI element for embedding in a parent layout.
---@param self EnemyBar
---@return table
function EnemyBarMethods:getElement()
    return self._elem
end

--- Returns whether this bar currently has an enemy to track.
---@param self EnemyBar
---@return boolean
function EnemyBarMethods:isVisible()
    return isEnemyVisible(self)
end

--- Returns the tracked enemy game object, if any.
---@param self EnemyBar
---@return table?
function EnemyBarMethods:getEnemyObject()
    return self._enemyObject
end

--- Re-target this EnemyBar onto a different enemy, refreshing its bar state.
---@param self EnemyBar
---@param enemy table
function EnemyBarMethods:setEnemy(enemy)
    self._enemyObject = enemy
    self._enemyName = enemy.record.name
    self._enemyHealthStat = enemy.type.stats.dynamic.health(enemy)

    updateFlashColors()
    local max = math.max(self._enemyHealthStat.base + self._enemyHealthStat.modifier, 1)
    self._enemyBar:reset(self._enemyHealthStat.current / max)
    self._enemyBar.elem.layout.props.size = barSize(max)
    self._enemyBar.elem:update()

    self._wasVisible = isEnemyVisible(self)
    rebuildContent(self)
    self._elem:update()
end

--- Clear this slot so it renders nothing until setEnemy is called again.
---@param self EnemyBar
function EnemyBarMethods:clear()
    self._enemyObject = nil
    self._enemyName = nil
    self._wasVisible = false
    rebuildContent(self)
    self._elem:update()
end

--- Tear down the UI element and unsubscribe from settings changes.
---@param self EnemyBar
function EnemyBarMethods:destroy()
    if self._settingsSub then
        self._settingsSub:unsubscribe()
        self._settingsSub = nil
    end
    if self._elem then
        self._elem:destroy()
        self._elem = nil
    end
end

return {
    NewEnemyBar = NewEnemyBar
}
