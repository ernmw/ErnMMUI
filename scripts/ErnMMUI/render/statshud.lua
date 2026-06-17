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

local ui          = require('openmw.ui')
local util        = require('openmw.util')
local HeartHealth = require('scripts.ErnMMUI.render.hearthealth')
local iconstack   = require('scripts.ErnMMUI.render.iconstack')
local Bar         = require('scripts.ErnMMUI.render.bar')
local core        = require("openmw.core")
local settings    = require("scripts.ErnMMUI.settings.settings")
local enchantUtil = require("scripts.ErnMMUI.enchantutil")
local spellUtil   = require("scripts.ErnMMUI.spellutil")
local pself       = require('openmw.self')
local types       = require('openmw.types')
local async       = require('openmw.async')
local const       = require('scripts.ErnMMUI.render.const')

local function lerpColor(a, b, t)
    return util.color.rgba(
        a.r + (b.r - a.r) * t,
        a.g + (b.g - a.g) * t,
        a.b + (b.b - a.b) * t,
        a.a + (b.a - a.a) * t
    )
end

local healthStat  = pself.type.stats.dynamic.health(pself)
local fatigueStat = pself.type.stats.dynamic.fatigue(pself)
local magickaStat = pself.type.stats.dynamic.magicka(pself)


local FLASH_HEALTH
local FLASH_FATIGUE
local FLASH_MAGICKA
local FLASH_CHARGES

local function updateFlashColors()
    FLASH_HEALTH  = lerpColor(settings.ui.colorHealth, util.color.rgba(0.9, 0.9, 0.9, 1), 0.7)
    FLASH_FATIGUE = lerpColor(settings.ui.colorFatigue, util.color.rgba(0.9, 0.9, 0.9, 1), 0.7)
    FLASH_MAGICKA = lerpColor(settings.ui.colorMagicka, util.color.rgba(0.9, 0.9, 0.9, 1), 0.7)
    FLASH_CHARGES = lerpColor(settings.ui.colorCharges, util.color.rgba(0.9, 0.9, 0.9, 1), 0.7)
end
updateFlashColors()

-- ---------------------------------------------------------------------------
-- StatsHUD
-- ---------------------------------------------------------------------------


local WHITE = util.color.rgba(1, 1, 1, 1)

local function shimmerFn(baseColor, spreadIcons)
    baseColor   = baseColor or WHITE
    spreadIcons = spreadIcons or 4

    return function(index, elapsed)
        -- Phase for this icon: offset each icon by (1/spreadIcons) of the
        -- cycle so the crest sweeps left-to-right.
        -- elapsed drives the global wave; subtracting the icon offset makes
        -- the peak travel rightward as time increases.
        local phase = elapsed - (index - 1) / spreadIcons

        -- sin oscillates -1..1; map to 0..1 so t=0 is baseColor, t=1 is white.
        local t = (math.sin(phase * 2 * math.pi) + 1) * 0.5

        return { color = lerpColor(baseColor, FLASH_MAGICKA, t) }
    end
end


local function uniformBarLength()
    return (const.HEART_SIZE + const.HEART_PADDING) * const.HEARTS_PER_ROW * settings.ui.scaling
end

local function barSize(max)
    if settings.ui.uniformBarLength then
        return util.vector2(uniformBarLength(), const.BAR_HEIGHT * settings.ui.scaling)
    else
        return util.vector2(const.BAR_LENGTH_FACTOR * math.sqrt(max) * settings.ui.scaling,
            const.BAR_HEIGHT * settings.ui.scaling)
    end
end

---@class StatsHUD
---@field _heartHealth   HeartHealth
---@field _healthBar     table   Bar object (used when settings.ui.hearts is false)
---@field _magickaRunesStack table
---@field _magickaPipsStack table
---@field _chargesStack table
---@field _fatigueBar    table   Bar object
---@field _magickaBar    table   Bar object
---@field _chargesBar    table   Bar object
---@field _elem          table   root ui element
---@field _showMagickaBar boolean
---@field _showChargesBar boolean
local StatsHUDMethods   = {}
StatsHUDMethods.__index = StatsHUDMethods

local paddingLayout     = {
    name = 'padWidget',
    props = { size = util.vector2(math.max(1, 4 * math.ceil(settings.ui.scaling)), math.max(1, 4 * math.ceil(settings.ui.scaling))) },
}

--- Build the root content table from current visibility state.
--- Called both on first creation and whenever visibility flags change.
---@param self StatsHUD
local function rebuildContent(self)
    local items = {}

    -- Health: heart widget or bar depending on the setting.
    if settings.ui.healthType == "hearts" then
        items[#items + 1] = self._heartHealth:getElement().layout
    else
        items[#items + 1] = self._healthBar.elem.layout
    end

    items[#items + 1] = paddingLayout
    items[#items + 1] = self._fatigueBar.elem.layout
    items[#items + 1] = paddingLayout

    if self._showMagickaBar then
        if settings.ui.magickaType == "runes" then
            items[#items + 1] = self._magickaRunesStack:getElement()
            items[#items + 1] = paddingLayout
        elseif settings.ui.magickaType == "pips" then
            items[#items + 1] = self._magickaPipsStack:getElement()
            items[#items + 1] = paddingLayout
        else
            items[#items + 1] = self._magickaBar.elem.layout
            items[#items + 1] = paddingLayout
        end
    end
    if self._showChargesBar then
        if settings.ui.chargesType == "pips" then
            items[#items + 1] = self._chargesStack:getElement()
        else
            items[#items + 1] = self._chargesBar.elem.layout
        end
    end

    self._elem.layout.content = ui.content(items)
end

--- Create a new StatsHUD.
---@return StatsHUD
local function NewStatsHUD()
    local self = {
        _heartHealth       = nil,
        _healthBar         = nil,
        _magickaRunesStack = nil,
        _magickaPipsStack  = nil,
        _chargesStack      = nil,
        _fatigueBar        = nil,
        _magickaBar        = nil,
        _chargesBar        = nil,
        _elem              = nil,
        _showMagickaBar    = false,
        _showChargesBar    = false,
    }
    setmetatable(self, StatsHUDMethods)

    -- Build child components.
    self._heartHealth = HeartHealth.New(healthStat.base + healthStat.modifier, healthStat.current)

    self._magickaRunesStack = iconstack.New({
        atlasPath       = 'Textures/ErnMMUI/daedric.dds',
        atlasResolution = util.vector2(128, 128),
        gridCols        = 4,
        gridRows        = 4,
        iconSize        = util.vector2(32, 32),
        initialCount    = 0,
        color           = settings.ui.colorMagicka,
        iconUpdateFn    = shimmerFn(settings.ui.colorMagicka, 10),
    })
    self._magickaPipsStack = iconstack.New({
        atlasPath       = 'Textures/ErnMMUI/magicka.png',
        atlasResolution = util.vector2(16, 16),
        gridCols        = 1,
        gridRows        = 1,
        iconSize        = util.vector2(16, 16),
        initialCount    = 0,
    })

    self._chargesStack = iconstack.New({
        atlasPath       = 'Textures/ErnMMUI/charges.png',
        atlasResolution = util.vector2(16, 16),
        gridCols        = 1,
        gridRows        = 1,
        iconSize        = util.vector2(16, 16),
        initialCount    = 0,
    })

    local makeBars = function()
        updateFlashColors()
        self._healthBar = Bar.New(
            healthStat.current / math.max(healthStat.base + healthStat.modifier, 1),
            settings.ui.colorHealth, FLASH_HEALTH, barSize(healthStat.base + healthStat.modifier))

        self._fatigueBar = Bar.New(
            fatigueStat.current / math.max(fatigueStat.base + fatigueStat.modifier, 1),
            settings.ui.colorFatigue, FLASH_FATIGUE, barSize(fatigueStat.base + fatigueStat.modifier))

        self._magickaBar = Bar.New(
            magickaStat.current / math.max(magickaStat.base + magickaStat.modifier, 1),
            settings.ui.colorMagicka, FLASH_MAGICKA, barSize(magickaStat.base + magickaStat.modifier))

        self._chargesBar = Bar.New(
            magickaStat.current / math.max(magickaStat.base + magickaStat.modifier, 1),
            settings.ui.colorCharges, FLASH_CHARGES, barSize(magickaStat.base + magickaStat.modifier))
    end
    makeBars()

    -- Root vertical flex: health on top, then fatigue, then magicka/charges.
    -- Content is populated by rebuildContent; start with a minimal placeholder
    -- so ui.create has something to work with.
    self._elem = ui.create({
        type    = ui.TYPE.Flex,
        name    = 'statsHUDRoot',
        props   = {
            horizontal = false,
            arrange    = ui.ALIGNMENT.Start,
            align      = ui.ALIGNMENT.Start,
            autoSize   = true,
        },
        content = ui.content {},
    })

    rebuildContent(self)
    self._elem:update()

    -- Watch for the hearts setting being toggled.
    settings.ui.subscribe(async:callback(function(section, key)
        makeBars()
        rebuildContent(self)
        self._elem:update()
    end))

    return self
end

local function itemChargeInfo(item)
    if not item or not item:isValid() then
        return nil
    end
    local record = item.type.record(item)
    if record.enchant == nil then
        return nil
    end

    local enchantRecord = core.magic.enchantments.records[record.enchant]
    if enchantRecord.type == core.magic.ENCHANTMENT_TYPE.CastOnce or enchantRecord.type == core.magic.ENCHANTMENT_TYPE.ConstantEffect then
        return nil
    end

    local capacity = enchantUtil.getMaxEnchantmentCharge(enchantRecord)
    if capacity < 1 then
        return nil
    end

    local data = types.Item.itemData(item)

    return {
        current = data and data.enchantmentCharge or capacity,
        max = capacity,
        castCost = enchantUtil.getCastCost(enchantRecord)
    }
end

--- Update every frame from your player_hud script.
---@param self           StatsHUD
---@param dt             number   elapsed seconds
function StatsHUDMethods:onUpdate(dt)
    -- Update whichever health widget is currently active.
    if settings.ui.healthType == "hearts" then
        self._heartHealth:onUpdate(dt, healthStat.current, healthStat.base + healthStat.modifier)
    else
        self._healthBar:onUpdate(dt,
            healthStat.current / math.max(healthStat.base + healthStat.modifier, 1),
            barSize(healthStat.base + healthStat.modifier))
    end

    self._fatigueBar:onUpdate(dt, fatigueStat.current / math.max(fatigueStat.base + fatigueStat.modifier, 1),
        barSize(fatigueStat.base + fatigueStat.modifier))

    local spellStance = types.Actor.getStance(pself) == types.Actor.STANCE.Spell
    local currentSpell = types.Actor.getSelectedSpell(pself)
    local showMagickaBar = (settings.ui.alwaysShowMagicka and settings.ui.magickaType == "bar") or
        (spellStance and currentSpell and currentSpell.type == core.magic.SPELL_TYPE.Spell)

    -- Only call onUpdate for bars that will be shown.
    if showMagickaBar then
        if settings.ui.magickaType == "bar" then
            self._magickaBar:onUpdate(dt, magickaStat.current / math.max(magickaStat.base + magickaStat.modifier, 1),
                barSize(magickaStat.base + magickaStat.modifier))
        elseif settings.ui.magickaType == "runes" then
            local cost = spellUtil.calculateSpellCost(currentSpell)
            self._magickaRunesStack:onUpdate(dt,
                math.floor(math.floor(magickaStat.current) / math.floor(math.max(1, cost))))
        elseif settings.ui.magickaType == "pips" then
            local cost = spellUtil.calculateSpellCost(currentSpell)
            self._magickaPipsStack:onUpdate(dt,
                math.floor(math.floor(magickaStat.current) / math.floor(math.max(1, cost))))
        else

        end
    end

    local chargeInfo
    if types.Actor.getStance(pself) == types.Actor.STANCE.Weapon then
        local rightHand = pself.type.getEquipment(pself, types.Actor.EQUIPMENT_SLOT.CarriedRight)
        chargeInfo = itemChargeInfo(rightHand)
    else
        chargeInfo = itemChargeInfo(types.Actor.getSelectedEnchantedItem(pself))
    end

    local showChargesBar = chargeInfo ~= nil

    if chargeInfo ~= nil then
        if settings.ui.chargesType == "pips" then
            self._chargesStack:onUpdate(dt,
                math.floor(math.floor(chargeInfo.current) / math.floor(math.max(1, chargeInfo.castCost))))
        else
            self._chargesBar:onUpdate(dt, chargeInfo.current / chargeInfo.max,
                barSize(chargeInfo.max))
        end
    end

    -- Rebuild root content only when visibility has changed.
    if showMagickaBar ~= self._showMagickaBar or showChargesBar ~= self._showChargesBar then
        self._showMagickaBar = showMagickaBar
        self._showChargesBar = showChargesBar
        rebuildContent(self)
    end

    self._elem:update()
end

--- Destroy all child UI elements.
function StatsHUDMethods:destroy()
    if self._heartHealth then
        self._heartHealth:destroy()
        self._heartHealth = nil
    end
    if self._elem then
        self._elem:destroy()
        self._elem = nil
    end
    -- Bar elements are children of _elem; destroying _elem covers them.
end

--- Return the root UI element for positioning in your HUD layer.
---@return table
function StatsHUDMethods:getElement()
    return self._elem
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
return {
    New = NewStatsHUD,
}
