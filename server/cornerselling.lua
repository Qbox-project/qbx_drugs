local config = require 'config.server'

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

lib.callback.register('qb-drugs:server:getAvailableDrugs', function(source)
    return getAvailableDrugs(source)
end)

RegisterNetEvent('qb-drugs:server:giveStealItems', function(drugType, amount)
    local availableDrugs = getAvailableDrugs(source)
    local player = exports.qbx_core:GetPlayer(source)

    if not availableDrugs or not player then return end

    exports.ox_inventory:AddItem(source, availableDrugs[drugType].item, amount)
end)

RegisterNetEvent('qb-drugs:server:sellCornerDrugs', function(drugType, amount, price)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    local availableDrugs = getAvailableDrugs(src)

    if not availableDrugs or not player then return end

    local item = availableDrugs[drugType].item

    local hasItem = player.Functions.GetItemByName(item)
    if hasItem.amount >= amount then
        exports.qbx_core:Notify(src, locale('success.offer_accepted'), 'success')
        exports.ox_inventory:RemoveItem(src, item, amount)
        player.Functions.AddMoney('cash', price, 'sold-cornerdrugs')
        TriggerClientEvent('qb-drugs:client:refreshAvailableDrugs', src, getAvailableDrugs(src))
    else
        TriggerClientEvent('qb-drugs:client:cornerselling', src)
    end
end)

RegisterNetEvent('qb-drugs:server:robCornerDrugs', function(drugType, amount)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    local availableDrugs = getAvailableDrugs(src)

    if not availableDrugs or not player then return end

    local item = availableDrugs[drugType].item

    exports.ox_inventory:RemoveItem(src, item, amount)
    TriggerClientEvent('qb-drugs:client:refreshAvailableDrugs', src, getAvailableDrugs(src))
end)