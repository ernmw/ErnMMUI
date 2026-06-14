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

local ui   = require('openmw.ui')
local util = require('openmw.util')



--- from pcp myui
local function padWidget(sizeH, sizeV)
    local padLayout = {
        name = 'padWidget',
        props = { size = util.vector2(sizeH, sizeV) }
    }
    return padLayout
end


local function addMarginLayout(inner, padding)
    return {
        type = ui.TYPE.Flex,
        props = {
            horizontal = false,
        },
        external = {
            grow = 1,
        },
        content = ui.content {

            -- top padding
            padWidget(0, padding),

            -- middle row
            {
                type = ui.TYPE.Flex,
                props = {
                    horizontal = true,
                },
                external = {
                    grow = 1,
                },
                content = ui.content {

                    -- left padding
                    padWidget(padding, 0),

                    -- actual content
                    {
                        type = ui.TYPE.Container,
                        external = {
                            grow = 1,
                        },
                        content = ui.content {
                            inner
                        }
                    },

                    -- right padding
                    padWidget(padding, 0),
                }
            },

            -- bottom padding
            padWidget(0, padding),
        }
    }
end
