local core = require('openmw.core')

--- Calculate the cost for a single effect
-- @param effect The effect with parameters (MagicEffectWithParams)
-- @return The base cost for this effect (float)
local function calculateEffectCost(effect)
    if not effect then
        return 0
    end

    -- Get magic effect record to access baseCost
    local magicEffect = core.magic.effects.records[effect.id]
    if not magicEffect then
        return 0
    end

    local baseCost = magicEffect.baseCost or 0

    -- Get effect magnitude range, ensure minimum of 1
    local minMagnitude = math.max(1, effect.magnitudeMin or 0)
    local maxMagnitude = math.max(1, effect.magnitudeMax or 0)

    -- Get effect duration
    local duration = math.max(1, effect.duration or 0)

    -- Get area of effect
    local area = effect.area or 0

    -- fEffectCostMult is typically 1.0 in Morrowind
    local fEffectCostMult = core.getGMST('fEffectCostMult') or 1.0

    -- Calculate cost using Morrowind formula (for GameSpell, durationOffset = 0):
    -- cost = 0.5 * (minMag + maxMag) * 0.1 * baseCost * duration + 0.05 * area * baseCost
    -- cost *= fEffectCostMult

    local x = 0.5 * (minMagnitude + maxMagnitude)
    x = x * 0.1 * baseCost
    x = x * duration
    x = x + 0.05 * math.max(0, area) * baseCost

    return x * fEffectCostMult
end


local cache = {}

--- Calculate the actual cost to cast a spell
-- @param spell The spell object containing effects and cost information
-- @return The magicka cost to cast the spell (integer)
local function calculateSpellCost(spell)
    if not spell then
        return 0
    end

    -- If autocalc flag is not set, return the stored cost directly
    if not spell.isAutocalc and not spell.autocalcFlag then
        return spell.cost or 0
    end

    if cache[spell.id] then
        return cache[spell.id]
    end

    -- Otherwise, calculate the cost based on effects
    local totalCost = 0.0

    if not spell.effects then
        cache[spell.id] = 0
        return cache[spell.id]
    end

    for _, effect in ipairs(spell.effects) do
        local effectCost = calculateEffectCost(effect)

        -- Apply range multiplier for target range spells
        if effect.range == core.magic.RANGE.Target then
            effectCost = effectCost * 1.5
        end

        totalCost = totalCost + math.max(0, effectCost)
    end

    -- Round to nearest integer
    cache[spell.id] = math.floor(totalCost + 0.5)
    return cache[spell.id]
end


return {
    calculateSpellCost = calculateSpellCost,
    calculateEffectCost = calculateEffectCost
}
