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

local ui                 = require("openmw.ui")
local util               = require("openmw.util")
local EnemyBar           = require('scripts.ErnMMUI.render.enemybar')

local MAX_ENEMY_SLOTS    = 4

local paddingLayout      = {
    name = 'padWidget',
    props = { size = util.vector2(8, 8) },
}

-- ---------------------------------------------------------------------------
-- EnemyList
--
-- A horizontal row of MAX_ENEMY_SLOTS slots. Each slot is sticky: once an
-- enemy is assigned to a slot, that enemy keeps that slot (and therefore its
-- horizontal position) until it dies/leaves combat, regardless of how other
-- enemies come and go. When a slot's enemy disappears, the slot becomes free
-- and is reused, in order, by the next new enemy seen in a future
-- setEnemies() call.
-- ---------------------------------------------------------------------------

---@class EnemyList
---@field _slots table  array of size MAX_ENEMY_SLOTS; each entry is an EnemyBar? (false = never used)
---@field _elem  table  root ui element
local EnemyListMethods   = {}
EnemyListMethods.__index = EnemyListMethods

---@param self EnemyList
local function rebuildContent(self)
    local items = {}
    for i = 1, MAX_ENEMY_SLOTS do
        local slot = self._slots[i]
        if slot then
            if #items > 0 then
                items[#items + 1] = paddingLayout
            end
            items[#items + 1] = slot:getElement()
        end
    end
    self._elem.layout.content = ui.content(items)
end

---@return EnemyList
local function NewEnemyList()
    local self = {
        _slots = {},
        _elem = nil,
    }
    setmetatable(self, EnemyListMethods)

    for i = 1, MAX_ENEMY_SLOTS do
        self._slots[i] = false
    end

    self._elem = ui.create({
        type    = ui.TYPE.Flex,
        name    = 'enemylist',
        props   = {
            horizontal = true,
            arrange    = ui.ALIGNMENT.Start,
            align      = ui.ALIGNMENT.Start,
            autoSize   = true,
        },
        content = ui.content {},
    })

    rebuildContent(self)
    self._elem:update()

    return self
end

--- Assign enemies to slots.
---
--- Enemies already occupying a slot keep that slot as long as they're still
--- present in `enemyList` (matched by object equality). Enemies that have
--- left/died free their slot. Any new enemies (present in `enemyList` but not
--- already assigned to a slot) fill the lowest-numbered free slots, in the
--- order they appear in `enemyList`. At most MAX_ENEMY_SLOTS enemies are
--- shown; extras beyond that are ignored until a slot frees up.
---
---@param self      EnemyList
---@param enemyList table  array of enemy game objects currently relevant (e.g. in combat)
function EnemyListMethods:setEnemies(enemyList)
    -- Track which enemies are still present this call.
    local stillPresent = {}
    for _, enemy in ipairs(enemyList) do
        stillPresent[enemy] = true
    end

    -- Free slots whose enemy is no longer present.
    for i = 1, MAX_ENEMY_SLOTS do
        local slot = self._slots[i]
        if slot then
            local enemy = slot:getEnemyObject()
            if not enemy or not stillPresent[enemy] then
                slot:clear()
            end
        end
    end

    -- Figure out which enemies are already assigned to a slot, so we don't
    -- double-assign them.
    local alreadyAssigned = {}
    for i = 1, MAX_ENEMY_SLOTS do
        local slot = self._slots[i]
        if slot then
            local enemy = slot:getEnemyObject()
            if enemy then
                alreadyAssigned[enemy] = true
            end
        end
    end

    -- Fill free slots with new enemies, in the order given, lowest free slot first.
    local slotIdx = 1
    for _, enemy in ipairs(enemyList) do
        if not alreadyAssigned[enemy] then
            -- find the next free slot
            while slotIdx <= MAX_ENEMY_SLOTS and self._slots[slotIdx] and self._slots[slotIdx]:getEnemyObject() do
                slotIdx = slotIdx + 1
            end
            if slotIdx > MAX_ENEMY_SLOTS then
                break
            end

            if self._slots[slotIdx] then
                self._slots[slotIdx]:setEnemy(enemy)
            else
                self._slots[slotIdx] = EnemyBar.NewEnemyBar(enemy)
            end

            alreadyAssigned[enemy] = true
            slotIdx = slotIdx + 1
        end
    end

    rebuildContent(self)
    self._elem:update()
end

--- Update all occupied slots each frame (drives bar fill/flash animation).
---@param self EnemyList
---@param dt   number elapsed seconds
function EnemyListMethods:onUpdate(dt)
    for i = 1, MAX_ENEMY_SLOTS do
        local slot = self._slots[i]
        if slot then
            slot:onUpdate(dt)
        end
    end
end

--- Return the root UI element for embedding in a parent layout.
---@param self EnemyList
---@return table
function EnemyListMethods:getElement()
    return self._elem
end

--- Tear down all slots and the root UI element.
---@param self EnemyList
function EnemyListMethods:destroy()
    for i = 1, MAX_ENEMY_SLOTS do
        local slot = self._slots[i]
        if slot then
            slot:destroy()
        end
        self._slots[i] = false
    end
    if self._elem then
        self._elem:destroy()
        self._elem = nil
    end
end

return {
    New = NewEnemyList,
}
