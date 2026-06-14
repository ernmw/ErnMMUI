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

local ui               = require('openmw.ui')
local util             = require('openmw.util')
local async            = require('openmw.async')
local Heart            = require('scripts.ErnMMUI.render.heart')
local settings         = require("scripts.ErnMMUI.settings.settings")

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local HEARTS_PER_ROW   = 10
local MIN_HP_PER_HEART = 8  -- a heart must represent at least this many HP
local HEART_SIZE       = 32 -- display size of each heart icon in pixels

-- ---------------------------------------------------------------------------
-- Helper: compute heart count and HP-per-heart from max health X.
--
--   Formula:  numHearts = X / (4 * floor(X^(1/4)))
--   Clamped:  healthPerHeart >= MIN_HP_PER_HEART
--             numHearts >= 1
-- ---------------------------------------------------------------------------
local function computeHeartScaling(maxHealth)
    maxHealth        = math.max(maxHealth, 1)

    local fourth     = math.max(math.floor(maxHealth ^ 0.25), 1)
    local heartCount = math.max(math.ceil(maxHealth / (4 * fourth)), 1)
    local hpPerHeart = maxHealth / heartCount

    if hpPerHeart < MIN_HP_PER_HEART then
        heartCount = math.max(math.floor(maxHealth / MIN_HP_PER_HEART), 1)
        hpPerHeart = maxHealth / heartCount
    end

    return heartCount, hpPerHeart
end

-- ---------------------------------------------------------------------------
-- Helper: map current HP to a per-heart AMOUNT table.
-- ---------------------------------------------------------------------------
local function computeHeartAmounts(currentHP, heartCount, hpPerHeart)
    local amounts = {}
    for i = 1, heartCount do
        local fill = (currentHP - (i - 1) * hpPerHeart) / hpPerHeart
        if fill <= 0 then
            amounts[i] = Heart.AMOUNT.EMPTY
        elseif fill < 0.375 then
            amounts[i] = Heart.AMOUNT.QUARTER
        elseif fill < 0.625 then
            amounts[i] = Heart.AMOUNT.HALF
        elseif fill < 0.875 then
            amounts[i] = Heart.AMOUNT.THREE_QUARTER
        else
            amounts[i] = Heart.AMOUNT.FULL
        end
    end
    return amounts
end

-- ---------------------------------------------------------------------------
-- Internal: grow or shrink the HeartComponent pool to newCount.
-- Existing components are reused so their beat/flash timers are preserved.
-- ---------------------------------------------------------------------------
local function resizeHeartComponents(components, newCount, all)
    local start = all and 1 or #components + 1
    for i = start, newCount do
        components[i] = Heart.NewHeartComponent({
            size = util.vector2(HEART_SIZE * settings.ui.scaling, HEART_SIZE * settings.ui.scaling),
        })
    end
    while #components > newCount do
        components[#components] = nil
    end
end

-- ---------------------------------------------------------------------------
-- Internal: build the heart-row vertical-flex layout from the current state.
-- ---------------------------------------------------------------------------

local paddingLayout = {
    name = 'padWidget',
    props = { size = util.vector2(math.max(1, math.ceil(settings.ui.scaling)), math.max(1, math.ceil(settings.ui.scaling))) },
    external = { grow = 1 }
}

-- flashSet (optional): table keyed by heart index; truthy values trigger a flash.
-- dt (optional): elapsed seconds passed through to GetLayout; defaults to 0.
local function buildLayout(heartComponents, heartAmounts, heartCount, flashSet, dt)
    flashSet         = flashSet or {}
    dt               = dt or 0

    local rowLayouts = {}
    local heartIdx   = 1

    while heartIdx <= heartCount do
        local rowChildren = {}
        for _ = 1, HEARTS_PER_ROW do
            if heartIdx > heartCount then break end
            local hc                      = heartComponents[heartIdx]
            local amount                  = heartAmounts[heartIdx]
            local flash                   = flashSet[heartIdx] or false
            rowChildren[#rowChildren + 1] = hc:GetLayout(amount, flash, dt)
            heartIdx                      = heartIdx + 1

            rowChildren[#rowChildren + 1] = paddingLayout
        end

        rowLayouts[#rowLayouts + 1] = {
            type    = ui.TYPE.Flex,
            props   = {
                horizontal = true,
                arrange    = ui.ALIGNMENT.Start,
                align      = ui.ALIGNMENT.Start,
                autoSize   = true,
            },
            content = ui.content(rowChildren),
        }
    end

    return {
        type    = ui.TYPE.Flex,
        name    = 'heartHealthRoot',
        props   = {
            horizontal = false,
            arrange    = ui.ALIGNMENT.Start,
            align      = ui.ALIGNMENT.Start,
            autoSize   = true,
        },
        content = ui.content(rowLayouts),
    }
end

-- ---------------------------------------------------------------------------
-- HeartHealth
-- ---------------------------------------------------------------------------

---@class HeartHealth
---@field _heartComponents  table   array of HeartComponent objects
---@field _heartAmounts     table   last-known per-heart AMOUNT values
---@field _heartCount       number
---@field _hpPerHeart       number
---@field _maxHealth        number
---@field _currentHealth    number
---@field _elem             table   root ui element

local HeartHealthMethods   = {}
HeartHealthMethods.__index = HeartHealthMethods

--- Create a new HeartHealth meter.
---@param maxHealth     number  initial maximum health
---@param currentHealth number  initial current health
---@return HeartHealth
local function NewHeartHealth(maxHealth, currentHealth)
    local self = {
        _heartComponents = {},
        _heartAmounts    = {},
        _heartCount      = 0,
        _hpPerHeart      = MIN_HP_PER_HEART,
        _maxHealth       = maxHealth,
        _currentHealth   = currentHealth,
        _elem            = nil,
    }
    setmetatable(self, HeartHealthMethods)

    local heartCount, hpPerHeart = computeHeartScaling(maxHealth)
    self._heartCount = heartCount
    self._hpPerHeart = hpPerHeart

    resizeHeartComponents(self._heartComponents, heartCount)
    self._heartAmounts = computeHeartAmounts(currentHealth, heartCount, hpPerHeart)

    self._elem = ui.create(
        buildLayout(self._heartComponents, self._heartAmounts, self._heartCount))

    -- invalidate the element when settings change
    settings.ui.subscribe(async:callback(function(section, key)
        if settings.ui.hearts then
            resizeHeartComponents(self._heartComponents, heartCount, true)
            self._elem:update()
        end
    end))

    return self
end

--- Update the heart meter each frame.
---@param self          HeartHealth
---@param dt            number   elapsed seconds
---@param currentHealth number   current HP
---@param maxHealth     number   max HP (change triggers a rescale)
function HeartHealthMethods:onUpdate(dt, currentHealth, maxHealth)
    -- Detect max-health change and rescale if needed.
    local rescale = (maxHealth ~= self._maxHealth)
    if rescale then
        self._maxHealth = maxHealth
        local newCount, newHPH = computeHeartScaling(maxHealth)
        if newCount ~= self._heartCount or newHPH ~= self._hpPerHeart then
            self._heartCount = newCount
            self._hpPerHeart = newHPH
            resizeHeartComponents(self._heartComponents, newCount)
        end
    end

    -- Compute new per-heart fill amounts.
    local oldAmounts = self._heartAmounts
    local newAmounts = computeHeartAmounts(
        currentHealth, self._heartCount, self._hpPerHeart)

    -- Flash hearts that lost fill this frame.
    local flashSet = {}
    if currentHealth < self._currentHealth or rescale then
        -- Find the rightmost heart that has any fill at the new health value.
        -- This heart absorbs the damage even if its sprite didn't step down.
        local rightmostFilledHeart = 0
        for i = 1, self._heartCount do
            if newAmounts[i] ~= Heart.AMOUNT.EMPTY then
                rightmostFilledHeart = i
            end
        end

        for i = 1, self._heartCount do
            local oldA = oldAmounts[i] or Heart.AMOUNT.EMPTY
            local newA = newAmounts[i] or Heart.AMOUNT.EMPTY
            if newA < oldA or i == rightmostFilledHeart then
                flashSet[i] = true
            end
        end
    end

    self._heartAmounts        = newAmounts
    self._currentHealth       = currentHealth

    -- Rebuild and push the updated layout.
    local newLayout           = buildLayout(
        self._heartComponents, newAmounts, self._heartCount, flashSet, dt)
    self._elem.layout.content = newLayout.content
    self._elem:update()
end

--- Destroy the UI element.
function HeartHealthMethods:destroy()
    if self._elem then
        self._elem:destroy()
        self._elem = nil
    end
end

--- Return the root UI element for embedding in a parent layout.
---@return table
function HeartHealthMethods:getElement()
    return self._elem
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
return {
    New = NewHeartHealth,
}
