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

local FADE_DURATION = 0.2   -- seconds for a removed icon to fade to invisible
local ICON_PADDING  = 2     -- px gap between icons in the stack
local ICONS_PER_ROW = 10    -- wrap after this many icons

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function deepCopy(orig)
    local t = type(orig)
    if t ~= 'table' then return orig end
    local copy = {}
    for k, v in next, orig, nil do
        copy[deepCopy(k)] = deepCopy(v)
    end
    setmetatable(copy, deepCopy(getmetatable(orig)))
    return copy
end

--- Build all ui.texture objects from the atlas once at construction time.
---
---@param atlasPath       string    VFS path to the atlas image
---@param atlasResolution Vector2   full pixel size of the atlas
---@param cols            number    number of columns in the grid (1 for single image)
---@param rows            number    number of rows    in the grid (1 for single image)
---@return table  array[cols*rows] of ui.texture handles
local function buildAtlasTextures(atlasPath, atlasResolution, cols, rows)
    local frameW   = atlasResolution.x / cols
    local frameH   = atlasResolution.y / rows
    local count    = cols * rows
    local textures = {}
    for i = 0, count - 1 do
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

-- ---------------------------------------------------------------------------
-- Slot  (one icon position in the stack)
--
-- A slot is always present for every index up to the current visible count,
-- plus any slots still fading out above that count.
--
-- Fields:
--   textureIdx  number   which atlas frame this slot locked in on (1-based)
--   fadeTimer   number   seconds of fade remaining; 0 means fully opaque / live
--   fading      boolean  true while this slot is playing the removal fade
-- ---------------------------------------------------------------------------

local function newSlot(textureCount)
    return {
        textureIdx = math.random(1, textureCount),
        fadeTimer  = 0,
        fading     = false,
    }
end

-- ---------------------------------------------------------------------------
-- Layout builder
-- ---------------------------------------------------------------------------

local paddingLayout = {
    name  = 'padWidget',
    props = { size = util.vector2(ICON_PADDING, ICON_PADDING) },
}

--- Build the full flex layout from the current slot list.
---
---@param slots       table   array of slot objects
---@param textures    table   array of ui.texture handles
---@param iconSize    Vector2
---@return table  root layout table
local function buildLayout(slots, textures, iconSize)
    local rowLayouts = {}
    local slotIdx    = 1
    local total      = #slots

    while slotIdx <= total do
        local rowChildren = {}
        for _ = 1, ICONS_PER_ROW do
            if slotIdx > total then break end
            local slot = slots[slotIdx]

            -- Compute alpha: fading slots go from 1 → 0 over FADE_DURATION.
            local alpha = 1
            if slot.fading then
                alpha = math.max(0, slot.fadeTimer / FADE_DURATION)
            end

            rowChildren[#rowChildren + 1] = {
                type  = ui.TYPE.Image,
                props = {
                    size     = iconSize,
                    resource = textures[slot.textureIdx],
                    color    = util.color.rgba(1, 1, 1, alpha),
                },
            }
            rowChildren[#rowChildren + 1] = paddingLayout
            slotIdx = slotIdx + 1
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
-- ---------------------------------------------------------------------------

---@class IconStack
---@field _slots        table     array of slot objects (live + fading)
---@field _liveCount    number    number of slots that are currently "on"
---@field _textures     table     atlas texture handles
---@field _textureCount number    total frames in the atlas
---@field _iconSize     Vector2
---@field _elem         table     root ui element

local IconStackMethods   = {}
IconStackMethods.__index = IconStackMethods

--- Create a new IconStack.
---
---@param opts table {
---   atlasPath       string    VFS path to the DDS/PNG atlas
---   atlasResolution Vector2   full pixel dimensions of the atlas image
---   gridCols        number    columns in the sprite grid (1 for a single image)
---   gridRows        number    rows    in the sprite grid (1 for a single image)
---   iconSize        Vector2?  display size of each icon (default: one atlas cell)
---   initialCount    number?   how many icons to show immediately (default: 0)
--- }
---@return IconStack
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

    local initialCount = opts.initialCount or 0

    local self         = {
        _slots        = {},
        _liveCount    = 0,
        _textures     = textures,
        _textureCount = textureCount,
        _iconSize     = iconSize,
        _elem         = nil,
    }
    setmetatable(self, IconStackMethods)

    -- Pre-populate slots for the initial count.
    for _ = 1, initialCount do
        self._slots[#self._slots + 1] = newSlot(textureCount)
    end
    self._liveCount = initialCount

    self._elem = ui.create(buildLayout(self._slots, self._textures, self._iconSize))
    return self
end

--- Called every frame.
---
---@param self       IconStack
---@param dt         number   elapsed seconds
---@param iconCount  number   desired number of visible icons
function IconStackMethods:onUpdate(dt, iconCount)
    iconCount          = math.max(0, iconCount)

    local textureCount = self._textureCount
    local slots        = self._slots
    local liveCount    = self._liveCount

    -- -----------------------------------------------------------------------
    -- 1. Handle count increase
    --    If iconCount rose, cancel any in-progress fades for slots we're
    --    reclaiming, then add brand-new slots on top if we still need more.
    -- -----------------------------------------------------------------------
    if iconCount > liveCount then
        -- First, cancel fades on trailing slots (highest indices first) so
        -- they snap back to visible before we potentially add more on top.
        local reclaimed = 0
        for i = #slots, liveCount + 1, -1 do
            if slots[i].fading and reclaimed < (iconCount - liveCount) then
                slots[i].fading     = false
                slots[i].fadeTimer  = 0
                -- Pick a fresh random texture so it doesn't look stale.
                slots[i].textureIdx = math.random(1, textureCount)
                reclaimed           = reclaimed + 1
            end
        end
        liveCount = liveCount + reclaimed

        -- Add brand-new slots for any remaining deficit.
        while liveCount < iconCount do
            slots[#slots + 1] = newSlot(textureCount)
            liveCount = liveCount + 1
        end

        self._liveCount = liveCount
    end

    -- -----------------------------------------------------------------------
    -- 2. Handle count decrease
    --    Begin fading any live slots above the new target that aren't already
    --    fading.
    -- -----------------------------------------------------------------------
    if iconCount < liveCount then
        for i = iconCount + 1, liveCount do
            if not slots[i].fading then
                slots[i].fading    = true
                slots[i].fadeTimer = FADE_DURATION
            end
        end
        self._liveCount = iconCount
    end

    -- -----------------------------------------------------------------------
    -- 3. Advance fade timers and prune fully-faded slots.
    -- -----------------------------------------------------------------------
    local i = 1
    while i <= #slots do
        local slot = slots[i]
        if slot.fading then
            slot.fadeTimer = slot.fadeTimer - dt
            if slot.fadeTimer <= 0 then
                -- Fully faded: remove the slot entirely.
                table.remove(slots, i)
                -- Don't increment i; the next slot has slid into this index.
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end

    -- -----------------------------------------------------------------------
    -- 4. Rebuild and push updated layout.
    -- -----------------------------------------------------------------------
    local newLayout           = buildLayout(slots, self._textures, self._iconSize)
    self._elem.layout.content = newLayout.content
    self._elem:update()
end

--- Destroy the UI element.
function IconStackMethods:destroy()
    if self._elem then
        self._elem:destroy()
        self._elem = nil
    end
end

--- Return the root UI element for embedding in a parent layout.
---@return table
function IconStackMethods:getElement()
    return self._elem
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
return {
    New = NewIconStack,
}
