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

local ui                  = require("openmw.ui")
local util                = require("openmw.util")

-- ---------------------------------------------------------------------------
-- Atlas layout (4×4 grid, 16 frames, left→right then top→bottom)
--
-- Index  Description
--   1    empty (0)
--   2    empty (0) + flash border
--   3    1/4  beat-A
--   4    1/4  beat-B
--   5    1/4  beat-A + flash border
--   6    1/4  beat-B + flash border
--   7    1/2  beat-A
--   8    1/2  beat-B
--   9    1/2  beat-A + flash border
--  10    1/2  beat-B + flash border
--  11    3/4  beat-A
--  12    3/4  beat-B
--  13    3/4  beat-A + flash border
--  14    3/4  beat-B + flash border
--  15    full (1)
--  16    full (1) + flash border
-- ---------------------------------------------------------------------------

-- Amount enum values — use these as the `amount` parameter.
local AMOUNT              = {
    EMPTY         = 0,
    QUARTER       = 0.25,
    HALF          = 0.5,
    THREE_QUARTER = 0.75,
    FULL          = 1,
}

-- How long a flash border stays visible after a flash-start trigger (seconds).
local FLASH_DURATION      = 0.5

-- How fast the "beat" animation cycles between frame-A and frame-B (seconds per frame).
local BEAT_FRAME_DURATION = 0.2

-- ---------------------------------------------------------------------------
-- Frame index lookup table.
-- Keys are amount values; values are { plain = {A, B}, flash = {A, B} }.
-- For EMPTY and FULL there is only one visual frame (A == B).
-- ---------------------------------------------------------------------------
local FRAME_MAP           = {
    [0]    = { plain = { 1, 1 }, flash = { 2, 2 } },
    [0.25] = { plain = { 3, 4 }, flash = { 5, 6 } },
    [0.5]  = { plain = { 7, 8 }, flash = { 9, 10 } },
    [0.75] = { plain = { 11, 12 }, flash = { 13, 14 } },
    [1]    = { plain = { 15, 15 }, flash = { 16, 16 } },
}

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function deepCopy(orig)
    local t = type(orig)
    if t ~= "table" then return orig end
    local copy = {}
    for k, v in next, orig, nil do
        copy[deepCopy(k)] = deepCopy(v)
    end
    setmetatable(copy, deepCopy(getmetatable(orig)))
    return copy
end

--- Build the 16 ui.texture objects from the atlas once, at construction time.
---@param atlasPath string
---@param atlasResolution Vector2  full pixel size of the atlas image
---@return table  array[16] of ui.texture handles
local function buildAtlasTextures(atlasPath, atlasResolution)
    local COLS = 4
    local ROWS = 4
    local frameW = atlasResolution.x / COLS
    local frameH = atlasResolution.y / ROWS

    local textures = {}
    for i = 0, 15 do
        local col = i % COLS
        local row = math.floor(i / COLS)
        textures[i + 1] = ui.texture {
            path   = atlasPath,
            offset = util.vector2(col * frameW, row * frameH),
            size   = util.vector2(frameW, frameH),
        }
    end
    return textures
end

local atlas                   = buildAtlasTextures('Textures/ErnMMUI/heart.dds', util.vector2(256, 256))

-- ---------------------------------------------------------------------------
-- HeartComponent
-- ---------------------------------------------------------------------------

---@class HeartComponent
---@field _props          table      base props forwarded to the Image widget
---@field _beatTime       number     accumulated time within the current beat cycle
---@field _flashTimer     number     seconds of flash remaining (0 = no flash)

---@class HeartComponentMethods
local HeartComponentMethods   = {}
HeartComponentMethods.__index = HeartComponentMethods

--- Create a new HeartComponent.
---
---@param props           table?   optional extra props passed to ui.TYPE.Image
---@return HeartComponent
local function NewHeartComponent(props)
    local self = {
        _props      = props or {},
        _beatTime   = 0,
        _flashTimer = 0,
    }
    setmetatable(self, HeartComponentMethods)
    return self
end

--- Return the ui layout table for the current frame.
---
---@param self        HeartComponent
---@param amount      number   one of the AMOUNT enum values (0, 0.25, 0.5, 0.75, 1)
---@param flashStart  boolean  true → reset/extend the flash timer to FLASH_DURATION
---@param dt          number   elapsed seconds since the last call
---@return table  a ui layout table ready to pass to ui.create / content
function HeartComponentMethods:GetLayout(amount, flashStart, dt)
    dt = dt or 0

    -- Update flash timer.
    if flashStart then
        -- Reset to full duration whenever the caller signals a new flash.
        self._flashTimer = FLASH_DURATION
    else
        -- Only count down; a false flag never cancels an in-progress flash.
        self._flashTimer = math.max(0, self._flashTimer - dt)
    end

    -- Advance beat animation timer.
    self._beatTime = self._beatTime + dt
    -- Keep it in [0, 2 * BEAT_FRAME_DURATION) so it never grows unbounded.
    local cycleDuration = BEAT_FRAME_DURATION * 2
    self._beatTime = self._beatTime % cycleDuration

    -- Determine beat frame slot: 1 (first half of cycle) or 2 (second half).
    local beatSlot = (self._beatTime < BEAT_FRAME_DURATION) and 1 or 2

    -- Resolve frame map entry.
    local entry = FRAME_MAP[amount]
    if not entry then
        error("unknown amount: " .. tostring(amount))
        -- Fallback to empty if an unrecognised amount is supplied.
        entry = FRAME_MAP[0]
    end

    local frameSet = (self._flashTimer > 0) and entry.flash or entry.plain
    local frameIdx = frameSet[beatSlot]

    -- Build and return the layout table.
    local layout = {
        type  = ui.TYPE.Image,
        props = deepCopy(self._props),
    }
    layout.props.resource = atlas[frameIdx]
    return layout
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
return {
    NewHeartComponent = NewHeartComponent,
    AMOUNT            = AMOUNT,
}
