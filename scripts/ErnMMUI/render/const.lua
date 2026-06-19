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

local util = require("openmw.util")

return {
    HEARTS_PER_ROW      = 10,
    -- a heart must represent at least this many HP
    MIN_HP_PER_HEART    = 8,
    -- display size of each heart icon in pixels
    HEART_SIZE          = 32,
    HEART_PADDING       = 2,
    -- How long a flash border stays visible after a flash-start trigger (seconds).
    FLASH_DURATION      = 0.5,
    -- How fast the "beat" animation cycles between frame-A and frame-B (seconds per frame).
    BEAT_FRAME_DURATION = 0.2,
    BAR_LENGTH_FACTOR   = 20,
    BAR_HEIGHT          = 24,

    ENEMY_BAR_LENGTH    = 140,
    MAX_ENEMY_SLOTS     = 3,

    FLASH_GRAY          = util.color.rgba(0.9, 0.9, 0.9, 1),
    ENEMY_TEXT          = util.color.rgba(0.9, 0.9, 0.9, 1),
    ENEMY_TEXT_SHADOW   = util.color.rgba(0.1, 0.1, 0.1, 1)
}
