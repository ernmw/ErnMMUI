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
local ui                      = require('openmw.ui')
local util                    = require('openmw.util')
local core                    = require('openmw.core')
local pself                   = require('openmw.self')
local types                   = require('openmw.types')
local async                   = require('openmw.async')
local margin                  = require("scripts.ErnMMUI.render.margin")
local statsHud                = require('scripts.ErnMMUI.render.statshud')
local enemylist               = require('scripts.ErnMMUI.render.enemylist')
local const                   = require('scripts.ErnMMUI.render.const')
local settings                = require("scripts.ErnMMUI.settings.settings")

-- An enemy that falls out of the closest-N set must stay outside it for this
-- many seconds before it's actually dropped from the visible list. This
-- avoids flicker when two enemies are near-equidistant and jockeying for
-- the last visible slot.
local BUMP_STICKINESS_SECONDS = 1.0

local combatTracker           = {}
-- id -> seconds remaining before a bumped-but-still-in-combat enemy is
-- actually dropped from the visible list. Only holds entries for enemies
-- that are currently visible but no longer rank in the true closest-N set.
local bumpTimers              = {}


local hud = statsHud.New()
local enemyList = enemylist.New()


local topCenter = util.vector2(0.5, 0)
local bottomCenter = util.vector2(0.5, 1)

local function enemyBarLocation()
    if settings.ui.enemyHealthAnchor == "top" then
        return topCenter
    else
        return bottomCenter
    end
end

local function getPaddedEnemyList()
    local padded = margin.addMarginLayout(enemyList:getElement(), 5, {
        relativePosition = enemyBarLocation(),
        anchor = enemyBarLocation(),
    })
    padded.name = "enemy"
    return padded
end

local root = ui.create {
    name = "root",
    layer = 'HUD',
    type = ui.TYPE.Widget,
    props = {
        relativePosition = util.vector2(0, 0),
        relativeSize = util.vector2(1, 1),
        anchor = util.vector2(0, 0),
    },
    content = ui.content {}
}

local function buildRootContent()
    local items = {}
    items[#items + 1] = margin.addMarginLayout(hud:getElement(), 5)
    items[#items + 1] = getPaddedEnemyList()
    root.layout.content = ui.content(items)
end
buildRootContent()

-- invalidate the element when settings change
settings.ui.subscribe(async:callback(function(section, key)
    buildRootContent()
    root:update()
end))

-- The set of enemies actually shown last frame (array of GameObjects).
local currentlyVisible = {}

--- Returns all valid, living combat-tracked enemies, nearest-to-the-player
--- first. Prunes combatTracker of any entry that's no longer valid (e.g.
--- died without a clean OMWMusicCombatTargetsChanged removal, or unloaded).
local function rankEnemiesByDistance()
    local playerPos = pself.position
    local candidates = {}

    for id, enemy in pairs(combatTracker) do
        if enemy and enemy:isValid() and not types.Actor.isDead(enemy) then
            candidates[#candidates + 1] = enemy
        else
            combatTracker[id] = nil
        end
    end

    table.sort(candidates, function(a, b)
        return (a.position - playerPos):length2() < (b.position - playerPos):length2()
    end)

    return candidates
end

--- Picks which enemies should be visible this frame, applying a stickiness
--- buffer: an enemy already on screen keeps its spot for
--- BUMP_STICKINESS_SECONDS after it falls out of the true closest-N set
--- before it's actually dropped. This avoids flicker when enemies are
--- near-equidistant and swapping rank from frame to frame.
---
--- The visible set is still capped at MAX_VISIBLE_ENEMIES overall: a sticky
--- enemy occupies one of the slots (rather than being added on top of a
--- full true-closest set), so newly-promoted enemies only actually appear
--- once they out-rank enough non-sticky, non-true-closest contenders to
--- earn a slot.
---@param dt number elapsed seconds
local function getClosestEnemies(dt)
    local ranked = rankEnemiesByDistance()
    local rankOf = {}
    for i, enemy in ipairs(ranked) do
        rankOf[enemy.id] = i
    end

    local trueClosest = {}
    for i = 1, math.min(const.MAX_ENEMY_SLOTS, #ranked) do
        trueClosest[ranked[i].id] = true
    end

    -- Carry over any previously-visible enemy that's still a valid combat
    -- target, ticking down its bump timer if it's fallen out of the true
    -- closest set. Enemies that left combat or died are dropped immediately
    -- (handled implicitly: they're absent from combatTracker/ranked).
    local kept = {}
    for _, enemy in ipairs(currentlyVisible) do
        if rankOf[enemy.id] then -- still a valid, in-combat candidate
            if trueClosest[enemy.id] then
                bumpTimers[enemy.id] = nil
                kept[#kept + 1] = enemy
            else
                local remaining = (bumpTimers[enemy.id] or BUMP_STICKINESS_SECONDS) - dt
                if remaining > 0 then
                    bumpTimers[enemy.id] = remaining
                    kept[#kept + 1] = enemy
                else
                    bumpTimers[enemy.id] = nil
                end
            end
        else
            bumpTimers[enemy.id] = nil
        end
    end

    -- Fill any remaining slots with the highest-ranked candidates not
    -- already kept, in distance order.
    local keptIds = {}
    for _, enemy in ipairs(kept) do
        keptIds[enemy.id] = true
    end

    local visible = { table.unpack(kept) }
    for _, enemy in ipairs(ranked) do
        if #visible >= const.MAX_ENEMY_SLOTS then break end
        if not keptIds[enemy.id] then
            visible[#visible + 1] = enemy
            keptIds[enemy.id] = true

            settings.debugPrint("combat! " .. tostring(enemy.type.record(enemy).name))
        end
    end

    currentlyVisible = visible
    return visible
end

local function onUpdate(dt)
    hud:onUpdate(dt)

    if settings.ui.showEnemyHealth then
        if not core.isWorldPaused() then
            enemyList:setEnemies(getClosestEnemies(dt))
        end
    else
        enemyList:setEnemies({})
    end

    enemyList:onUpdate(dt)

    root:update()
end



return {
    eventHandlers = {
        OMWMusicCombatTargetsChanged = function(incomingTargetData)
            if next(incomingTargetData.targets) == nil then
                settings.debugPrint("combat ended with " .. tostring(incomingTargetData.actor.id))
                combatTracker[incomingTargetData.actor.id] = nil
            else
                settings.debugPrint("combat started with " .. tostring(incomingTargetData.actor.id))
                combatTracker[incomingTargetData.actor.id] = incomingTargetData.actor
            end
        end,
        HUDTransparencyChange = function(data)
            if root then
                root.layout.props.alpha = data.alpha
            end
        end,
    },
    engineHandlers = {
        onUpdate = onUpdate,
    }
}
