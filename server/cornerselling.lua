local config = require 'config.server'

local function getAvailableDrugs(source)
    local AvailableDrugs = {}
    local Player = exports.qbx_core:GetPlayer(source)

    if not Player then return nil end

    for i = 1, #config.cornerSellingDrugsList do
        ---@todo Check to see if this works
        local item = exports.ox_inventory:Search(source, 'count', config.cornerSellingDrugsList[i])

        if item then
            AvailableDrugs[#AvailableDrugs + 1] = {
                item = item.name,
                amount = item.amount,
                label = exports.ox_inventory:Items()[item.name].label
            }
        end
    end
    return table.type(AvailableDrugs) ~= "empty" and AvailableDrugs or nil
end

lib.callback.register('qb-drugs:server:getAvailableDrugs', function(source)
    return getAvailableDrugs(source)
end)

RegisterNetEvent('qb-drugs:server:giveStealItems', function(drugType, amount)
    local availableDrugs = getAvailableDrugs(source)
    local Player = exports.qbx_core:GetPlayer(source)

    if not availableDrugs or not Player then return end

    exports.ox_inventory:AddItem(source, availableDrugs[drugType].item, amount)
end)

RegisterNetEvent('qb-drugs:server:sellCornerDrugs', function(drugType, amount, price)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    local availableDrugs = getAvailableDrugs(src)

    if not availableDrugs or not Player then return end

    local item = availableDrugs[drugType].item

    local hasItem = Player.Functions.GetItemByName(item)
    if hasItem.amount >= amount then
        TriggerClientEvent('QBCore:Notify', src, Lang:t("success.offer_accepted"), 'success')
        exports.ox_inventory:RemoveItem(src, item, amount)
        Player.Functions.AddMoney('cash', price, "sold-cornerdrugs")
        TriggerClientEvent('qb-drugs:client:refreshAvailableDrugs', src, getAvailableDrugs(src))
    else
        TriggerClientEvent('qb-drugs:client:cornerselling', src)
    end
end)

RegisterNetEvent('qb-drugs:server:robCornerDrugs', function(drugType, amount)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)
    local availableDrugs = getAvailableDrugs(src)

    if not availableDrugs or not Player then return end

    local item = availableDrugs[drugType].item

    exports.ox_inventory:RemoveItem(src, item, amount)
    TriggerClientEvent('qb-drugs:client:refreshAvailableDrugs', src, getAvailableDrugs(src))
end)