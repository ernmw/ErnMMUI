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
local ui         = require("openmw.ui")
local util       = require("openmw.util")
local interfaces = require('openmw.interfaces')

local function barLayout(value, color, flashColor, size)
    return {
        type = ui.TYPE.Widget,
        name = 'bar',
        template = interfaces.MWUI.templates.borders,
        props = {
            size = size,
        },
        content = ui.content {
            {
                type = ui.TYPE.Image,
                name = 'barContainer',
                props = {
                    resource = ui.texture { path = 'white' },
                    relativePosition = util.vector2(0, 0),
                    relativeSize = util.vector2(1, 1),
                    alpha = 0.5,
                    color = util.color.rgb(0.1, 0.1, 0.1),
                },
                events = {},
            },
            {
                name = 'barColor',
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                    arrange = ui.ALIGNMENT.Center,
                    align = ui.ALIGNMENT.Start,
                    anchor = util.vector2(0, 0),
                    relativePosition = util.vector2(0, 0),
                    relativeSize = util.vector2(1, 1),
                    autoSize = false,
                },
                content = ui.content {
                    {
                        type = ui.TYPE.Image,
                        name = 'barFill',
                        props = {
                            resource = ui.texture { path = 'Textures/ErnMMUI/horz_gradient.dds' },
                            relativeSize = util.vector2(value, 1),
                            --alpha = 0.7,
                            color = color,
                        },
                    },
                    {
                        type = ui.TYPE.Image,
                        name = 'barFlash',
                        props = {
                            resource = ui.texture { path = 'Textures/ErnMMUI/horz_gradient.dds' },
                            relativeSize = util.vector2(0, 1),
                            --alpha = 0.7,
                            color = flashColor,
                        },
                    },
                }
            },
        }
    }
end

local function setRatio(elem, ratio, flashRatio)
    elem.layout.content.barColor.content.barFill.props.relativeSize = util.vector2(ratio, 1)
    elem.layout.content.barColor.content.barFlash.props.relativeSize = util.vector2(flashRatio, 1)
end

local flashSpeed     = 0.1

local BarFunctions   = {}
BarFunctions.__index = BarFunctions

function NewBar(ratio, color, flashColor, size)
    local new = {
        ratio = ratio,
        flashRatio = 0,
        color = color,
        flashColor = flashColor,
        size = size,
        elem = ui.create(barLayout(ratio, color, flashColor, size))
    }
    setmetatable(new, BarFunctions)
    return new
end

function BarFunctions.reset(self, newRatio)
    self.ratio = newRatio or 0
    self.flashRatio = 0
    setRatio(self.elem, self.ratio, self.flashRatio)
    self.elem:update()
end

function BarFunctions.onUpdate(self, dt, newRatio, size)
    local changed = false
    if newRatio ~= self.ratio then
        if newRatio < self.ratio then
            self.flashRatio = util.clamp(self.flashRatio + self.ratio - newRatio, 0, 1 - newRatio)
        end
        self.ratio = newRatio
        changed = true
    end
    if self.flashRatio > 0 then
        self.flashRatio = util.clamp(self.flashRatio - flashSpeed * dt, 0, 1)
        changed = true
    end
    if size and not changed then
        if size ~= self.elem.layout.props.size then
            changed = true
        end
    end
    if changed then
        if size then self.elem.layout.props.size = size end
        setRatio(self.elem, self.ratio, self.flashRatio)
        self.elem:update()
    end
end

return {
    New = NewBar,
}
