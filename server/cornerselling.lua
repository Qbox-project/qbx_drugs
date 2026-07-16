local config = require 'config.server'
local cornerOffers = {}
local stolenItems = {}
local cornerLocks = {}

local function getAvailableDrugs(source)
    local availableDrugs = {}
    local player = exports.qbx_core:GetPlayer(source)

    if not player then return nil end

    for i = 1, #config.cornerSellingDrugsList do
        local itemName = config.cornerSellingDrugsList[i]
        local itemCount = exports.ox_inventory:Search(source, 'count', itemName)
        if itemCount > 0 then
            availableDrugs[#availableDrugs + 1] = {
                item = itemName,
                amount = itemCount,
                label = exports.ox_inventory:Items()[itemName].label
            }
        end
    end
    return table.type(availableDrugs) ~= 'empty' and availableDrugs or nil
end

lib.callback.register('qb-drugs:server:getDrugOffer', function(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return nil end
    local availableDrugs = getAvailableDrugs(player.PlayerData.source)
    if availableDrugs == nil then return nil end

    local randomDrug = math.random(1, #availableDrugs)
    local chosenDrug = availableDrugs[randomDrug]
    local offeredAmount = math.random(1, chosenDrug.amount > 15 and 15 or chosenDrug.amount)
    local basePrice = math.random(config.cornerSellingDrugsPrice[chosenDrug.item].min, config.cornerSellingDrugsPrice[chosenDrug.item].max)
    local totalPrice = config.scamChance >= math.random(1, 100) and basePrice * offeredAmount or math.random(3, 10) * offeredAmount

    cornerOffers[source] = {
        item = chosenDrug.item,
        amount = offeredAmount,
        total = totalPrice,
        expiresAt = os.time() + 60,
    }

    return { chosen = chosenDrug, idx = randomDrug, amount = offeredAmount, total = totalPrice }
end)

RegisterNetEvent('qb-drugs:server:giveStealItems', function()
    local src = source
    local stolen = stolenItems[src]
    stolenItems[src] = nil
    if not stolen or stolen.expiresAt < os.time() then return end

    exports.ox_inventory:AddItem(src, stolen.item, stolen.amount)
end)

RegisterNetEvent('qb-drugs:server:sellCornerDrugs', function()
    local src = source
    if cornerLocks[src] then return end
    cornerLocks[src] = true

    local player = exports.qbx_core:GetPlayer(src)
    local offer = cornerOffers[src]
    cornerOffers[src] = nil
    if player and offer and offer.expiresAt >= os.time()
        and exports.ox_inventory:GetItemCount(src, offer.item) >= offer.amount
        and exports.ox_inventory:RemoveItem(src, offer.item, offer.amount) then
        exports.qbx_core:Notify(src, locale('success.offer_accepted'), 'success')
        player.Functions.AddMoney('cash', offer.total, 'sold-cornerdrugs')
        if config.policeCallChance >= math.random(1, 100) then
            TriggerEvent('police:server:policeAlert', locale('info.possible_drug_dealing'), nil, src)
        end
    elseif player then
        TriggerClientEvent('qb-drugs:client:cornerselling', src)
    end

    cornerLocks[src] = nil
end)

RegisterNetEvent('qb-drugs:server:robCornerDrugs', function()
    local src = source
    if cornerLocks[src] then return end
    cornerLocks[src] = true

    local player = exports.qbx_core:GetPlayer(src)
    local offer = cornerOffers[src]
    cornerOffers[src] = nil
    if player and offer and offer.expiresAt >= os.time()
        and exports.ox_inventory:RemoveItem(src, offer.item, offer.amount) then
        stolenItems[src] = {
            item = offer.item,
            amount = offer.amount,
            expiresAt = os.time() + 600,
        }
    end

    cornerLocks[src] = nil
end)

AddEventHandler('playerDropped', function()
    cornerOffers[source] = nil
    stolenItems[source] = nil
    cornerLocks[source] = nil
end)
