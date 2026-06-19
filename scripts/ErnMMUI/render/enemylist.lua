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

--- this is a horizontal flex list of enemy bars.
--- each enemy bar occupies a slot in the flex list, and should not shift left or right
--- if a different enemy leaves combat or dies. they should be relatively sticky in this way.
