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

local ui            = require('openmw.ui')
local util          = require('openmw.util')

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local FADE_DURATION = 0.2 -- seconds for a removed icon to fade to invisible
local ICON_PADDING  = 2   -- px gap between icons
local ICONS_PER_ROW = 10  -- wrap after this many icons

-- ---------------------------------------------------------------------------
-- Atlas helpers
-- ---------------------------------------------------------------------------

local function buildAtlasTextures(atlasPath, atlasResolution, cols, rows)
    local frameW   = atlasResolution.x / cols
    local frameH   = atlasResolution.y / rows
    local textures = {}
    for i = 0, cols * rows - 1 do
        local col = i % cols
        local row = math.floor(i / cols)
        textures[i + 1] = ui.texture {
            path   = atlasPath,
            offset = util.vector2(col * frameW, row * frameH),
            size   = util.vector2(frameW, frameH),
        }
    end
    return textures
end

local function randomTextureIdx(textureCount)
    return math.random(1, textureCount)
end

-- ---------------------------------------------------------------------------
-- Layout builder
--
-- _slots is a single flat array covering every visible position left-to-right:
--
--   index 1 .. liveCount          : live icons   (alpha 1)
--   index liveCount+1 .. #_slots  : fading icons (alpha 1→0)
--
-- Live icons always occupy the leftmost positions; fading icons trail on the
-- right — exactly where they were when they were live.  This means:
--   • removing the rightmost icon starts a fade at the rightmost position  ✓
--   • live icons never change texture when the count changes               ✓
--   • new icons are appended to the right of the live block                ✓
--
-- We never touch textureIdx of an existing slot during normal operation.
-- randomTextureIdx is only called when a slot is first created or revived.
-- ---------------------------------------------------------------------------

local paddingLayout = {
    name  = 'padWidget',
    props = { size = util.vector2(ICON_PADDING, ICON_PADDING) },
}

local function buildLayout(slots, textures, iconSize, color)
    local rowLayouts = {}
    local idx        = 1
    local total      = #slots

    while idx <= total do
        local rowChildren = {}
        for _ = 1, ICONS_PER_ROW do
            if idx > total then break end
            local slot                    = slots[idx]
            local alpha                   = slot.fading
                and math.max(0, slot.fadeTimer / FADE_DURATION)
                or 1

            rowChildren[#rowChildren + 1] = {
                type  = ui.TYPE.Image,
                props = {
                    size     = iconSize,
                    resource = textures[slot.textureIdx],
                    alpha    = alpha,
                    color    = color
                },
            }
            rowChildren[#rowChildren + 1] = paddingLayout
            idx                           = idx + 1
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
        name    = 'iconStackRoot',
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
-- IconStack
--
-- _slots : flat array of { textureIdx, fading, fadeTimer }
--   indices 1.._liveCount        = live
--   indices _liveCount+1..#slots = fading (in the order they were removed)
--
-- _liveCount tracks the boundary.  Only fading slots are pruned; live slots
-- are never removed mid-array, so their indices (and thus textures) are stable.
-- ---------------------------------------------------------------------------

---@class IconStack
local IconStackMethods   = {}
IconStackMethods.__index = IconStackMethods

local function NewIconStack(opts)
    assert(opts.atlasPath, 'IconStack: atlasPath is required')
    assert(opts.atlasResolution, 'IconStack: atlasResolution is required')

    local cols         = opts.gridCols or 1
    local rows         = opts.gridRows or 1

    local textures     = buildAtlasTextures(opts.atlasPath, opts.atlasResolution, cols, rows)
    local textureCount = cols * rows

    local cellW        = opts.atlasResolution.x / cols
    local cellH        = opts.atlasResolution.y / rows
    local iconSize     = opts.iconSize or util.vector2(cellW, cellH)

    local slots        = {}
    local initCount    = opts.initialCount or 0
    for _ = 1, initCount do
        slots[#slots + 1] = {
            textureIdx = randomTextureIdx(textureCount),
            fading     = false,
            fadeTimer  = 0,
        }
    end

    local self = {
        _slots        = slots,
        _liveCount    = initCount,
        _textures     = textures,
        _textureCount = textureCount,
        _iconSize     = iconSize,
        _elem         = nil,
        _color        = opts.color
    }
    setmetatable(self, IconStackMethods)

    self._elem = ui.create(buildLayout(self._slots, self._textures, self._iconSize, self._color))
    return self
end

function IconStackMethods:onUpdate(dt, iconCount)
    iconCount       = math.max(0, iconCount)

    local slots     = self._slots
    local liveCount = self._liveCount
    local tcCount   = self._textureCount

    -- -----------------------------------------------------------------------
    -- 1. Reconcile live count.
    -- -----------------------------------------------------------------------
    if iconCount > liveCount then
        local needed = iconCount - liveCount

        -- First: reclaim fading slots that directly follow the live block.
        -- Iterate forward through the fading region so we reclaim oldest first
        -- (they're closest to the live block, i.e. lowest visual index).
        local i = liveCount + 1
        while i <= #slots and needed > 0 do
            local slot      = slots[i]
            -- Revive in place: pick a new random texture, mark as live.
            slot.textureIdx = randomTextureIdx(tcCount)
            slot.fading     = false
            slot.fadeTimer  = 0
            -- Swap into the live block (move it to liveCount+1 position).
            -- Since we're iterating forward and liveCount is about to grow,
            -- the slot is already at the right position — just bump liveCount.
            liveCount       = liveCount + 1
            i               = i + 1
            needed          = needed - 1
        end

        -- Still short: append brand-new slots after all existing entries.
        while needed > 0 do
            slots[#slots + 1] = {
                textureIdx = randomTextureIdx(tcCount),
                fading     = false,
                fadeTimer  = 0,
            }
            liveCount         = liveCount + 1
            needed            = needed - 1
        end

        self._liveCount = liveCount
    elseif iconCount < liveCount then
        -- Demote live slots from the right end of the live block to fading.
        -- We move them rather than mark-in-place so fading slots always live
        -- at indices > liveCount and never disrupt live slot indices.
        local excess = liveCount - iconCount
        for _ = 1, excess do
            -- The rightmost live slot.
            local slot     = slots[liveCount]
            -- Only start a new fade if it isn't already fading
            -- (shouldn't happen here, but defensive).
            slot.fading    = true
            slot.fadeTimer = FADE_DURATION
            -- Move it to just after the new live block end by swapping with
            -- the first fading slot position (liveCount stays at old value
            -- until we finish, so this is safe).
            -- Actually: slots[liveCount] is already at index liveCount.
            -- After decrementing liveCount it will be at liveCount+1, which
            -- is exactly the fading region.  No swap needed.
            liveCount      = liveCount - 1
        end
        self._liveCount = liveCount
    end

    -- -----------------------------------------------------------------------
    -- 2. Tick fade timers; prune expired fading slots (backwards).
    -- -----------------------------------------------------------------------
    for i = #slots, self._liveCount + 1, -1 do
        local slot = slots[i]
        slot.fadeTimer = slot.fadeTimer - dt
        if slot.fadeTimer <= 0 then
            table.remove(slots, i)
            -- liveCount is unaffected because we're only touching indices > liveCount.
        end
    end

    -- -----------------------------------------------------------------------
    -- 3. Rebuild and push updated layout.
    -- -----------------------------------------------------------------------
    local newLayout           = buildLayout(slots, self._textures, self._iconSize, self._color)
    self._elem.layout.content = newLayout.content
    self._elem:update()
end

function IconStackMethods:destroy()
    if self._elem then
        self._elem:destroy()
        self._elem = nil
    end
end

function IconStackMethods:getElement()
    return self._elem
end

return {
    New = NewIconStack,
}
