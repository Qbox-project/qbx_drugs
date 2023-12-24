local config = require 'config.server'
local sharedConfig = require 'config.shared'

-- Functions
exports('GetDealers', function()
    return sharedConfig.dealers
end)

-- Callbacks
lib.callback.register('qb-drugs:server:RequestConfig', function()
    return sharedConfig.dealers
end)

-- Events
RegisterNetEvent('qb-drugs:server:updateDealerItems', function(itemData, amount, dealer)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)

    if not Player then return end

    if sharedConfig.dealers[dealer].products[itemData.slot].amount - 1 >= 0 then
        sharedConfig.dealers[dealer].products[itemData.slot].amount -= amount
        TriggerClientEvent('qb-drugs:client:setDealerItems', -1, itemData, amount, dealer)
    else
        exports.ox_inventory:RemoveItem(src, itemData.name, amount)
        Player.Functions.AddMoney('cash', amount * sharedConfig.dealers[dealer].products[itemData.slot].price)
        exports.qbx_core:Notify(src, Lang:t("error.item_unavailable"), "error")
    end
end)

RegisterNetEvent('qb-drugs:server:giveDeliveryItems', function(deliveryData)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)

    if not Player then return end

    local item = sharedConfig.deliveryItems[deliveryData.item].item

    if not item then return end

    exports.ox_inventory:AddItem(src, item, deliveryData.amount)
end)

RegisterNetEvent('qb-drugs:server:successDelivery', function(deliveryData, inTime)
    local src = source
    local Player = exports.qbx_core:GetPlayer(src)

    if not Player then return end

    local item = sharedConfig.deliveryItems[deliveryData.item].item
    local itemAmount = deliveryData.amount
    local payout = deliveryData.itemData.payout * itemAmount
    local copsOnline = exports.qbx_core:GetDutyCountType('leo')
    local curRep = Player.PlayerData.metadata.dealerrep
    local invItem = exports.ox_inventory:Search(src, 'count', item)
    if inTime then
        if invItem and invItem.amount >= itemAmount then -- on time correct amount
            exports.ox_inventory:RemoveItem(src, item, itemAmount)
            if copsOnline > 0 then
                local copModifier = copsOnline * config.policeDeliveryModifier
                if config.useMarkedBills then
                    local worth = math.floor(payout * copModifier)
                    local metadata = { worth = worth, description = "Value: " .. worth }
                    exports.ox_inventory:AddItem(src, 'markedbills', 1, metadata)
                else
                    Player.Functions.AddMoney('cash', math.floor(payout * copModifier), 'drug-delivery')
                end
            else
                if config.useMarkedBills then
                    local metadata = { worth = payout, description = "Value: " .. payout }
                    exports.ox_inventory:AddItem(src, 'markedbills', 1, metadata)
                else
                    Player.Functions.AddMoney('cash', payout, 'drug-delivery')
                end
            end
            exports.qbx_core:Notify(src, Lang:t("success.order_delivered"), 'success')
            SetTimeout(math.random(5000, 10000), function()
                TriggerClientEvent('qb-drugs:client:sendDeliveryMail', src, 'perfect', deliveryData)
                Player.Functions.SetMetaData('dealerrep', (curRep + config.deliveryRepGain))
            end)
        else
            exports.qbx_core:Notify(src, Lang:t("error.order_not_right"), 'error')-- on time incorrect amount
            if invItem then
                local newItemAmount = invItem.amount
                local modifiedPayout = deliveryData.itemData.payout * newItemAmount
                exports.ox_inventory:RemoveItem(src, item, newItemAmount)
                Player.Functions.AddMoney('cash', math.floor(modifiedPayout / config.wrongAmountFee))
            end
            SetTimeout(math.random(5000, 10000), function()
                TriggerClientEvent('qb-drugs:client:sendDeliveryMail', src, 'bad', deliveryData)
                if curRep - 1 > 0 then
                    Player.Functions.SetMetaData('dealerrep', (curRep - config.deliveryRepLoss))
                else
                    Player.Functions.SetMetaData('dealerrep', 0)
                end
            end)
        end
    else
        if invItem and invItem.amount >= itemAmount then -- late correct amount
            exports.qbx_core:Notify(src, Lang:t("error.too_late"), 'error')
            exports.ox_inventory:RemoveItem(src, item, itemAmount)
            Player.Functions.AddMoney('cash', math.floor(payout / config.overdueDeliveryFee), "delivery-drugs-too-late")
            SetTimeout(math.random(5000, 10000), function()
                TriggerClientEvent('qb-drugs:client:sendDeliveryMail', src, 'late', deliveryData)
                if curRep - 1 > 0 then
                    Player.Functions.SetMetaData('dealerrep', (curRep - config.deliveryRepLoss))
                else
                    Player.Functions.SetMetaData('dealerrep', 0)
                end
            end)
        else
            if invItem then -- late incorrect amount
                local newItemAmount = invItem.amount
                local modifiedPayout = deliveryData.itemData.payout * newItemAmount
                exports.qbx_core:Notify(src, Lang:t("error.too_late"), 'error')
                exports.ox_inventory:RemoveItem(src, item, itemAmount)
                Player.Functions.AddMoney('cash', math.floor(modifiedPayout / config.overdueDeliveryFee), "delivery-drugs-too-late")
                SetTimeout(math.random(5000, 10000), function()
                    TriggerClientEvent('qb-drugs:client:sendDeliveryMail', src, 'late', deliveryData)
                    if curRep - 1 > 0 then
                        Player.Functions.SetMetaData('dealerrep', (curRep - config.deliveryRepLoss))
                    else
                        Player.Functions.SetMetaData('dealerrep', 0)
                    end
                end)
            end
        end
    end
end)


lib.addCommand("newdealer", {
    help = Lang:t("info.newdealer_command_desc"),
    params = {
        {
            name = 'name',
            type = 'string',
            help = Lang:t("info.newdealer_command_help1_help"),
            optional = false
        },
        {
            name = 'min',
            type = 'number',
            help = Lang:t("info.newdealer_command_help2_help"),
            optional = false
        },
        {
            name = 'max',
            type = 'number',
            help = Lang:t("info.newdealer_command_help3_help"),
            optional = false
        }
    },
    restricted = 'group.admin'
}, function(source, args)
    local ped = GetPlayerPed(source)
    local coords = GetEntityCoords(ped)
    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then return end
    local dealerName = args.name
    local minTime = args.min
    local maxTime = args.max
    local time = json.encode({min = minTime, max = maxTime})
    local pos = json.encode({x = coords.x, y = coords.y, z = coords.z})
    local result = MySQL.scalar.await('SELECT name FROM dealers WHERE name = ?', {dealerName})
    if result then return exports.qbx_core:Notify(source, Lang:t("error.dealer_already_exists"), "error") end
    MySQL.insert('INSERT INTO dealers (name, coords, time, createdby) VALUES (?, ?, ?, ?)', {dealerName, pos, time, Player.PlayerData.citizenid}, function()
        sharedConfig.dealers[dealerName] = {
            name = dealerName,
            coords = vec3(coords.x, coords.y, coords.z),
            time = { min = minTime, max = maxTime },
            products = config.products
        }
        TriggerClientEvent('qb-drugs:client:RefreshDealers', -1, sharedConfig.dealers)
    end)
end)

lib.addCommand("deletedealer", {
    help = Lang:t("info.newdealer_command_desc"),
    params = {
        {
            name = 'name',
            type = 'string',
            help = Lang:t("info.deletedealer_command_help1_help"),
            optional = false
        },
    },
    restricted = 'group.admin'
}, function(source, args)
    local dealerName = args.name
    local result = MySQL.scalar.await('SELECT * FROM dealers WHERE name = ?', {dealerName})
    if result then
        MySQL.query('DELETE FROM dealers WHERE name = ?', {dealerName})
        sharedConfig.dealers[dealerName] = nil
        TriggerClientEvent('qb-drugs:client:RefreshDealers', -1, sharedConfig.dealers)
        exports.qbx_core:Notify(source, Lang:t("success.dealer_deleted", {dealerName = dealerName}), "success")
    else
        exports.qbx_core:Notify(source, Lang:t("error.dealer_not_exists_command", {dealerName = dealerName}), "error")
    end
end)

lib.addCommand("dealers", {
    help = "To see the list of dealers",

    restricted = 'group.admin'
}, function(source)
    local DealersText = ""
    if sharedConfig.dealers ~= nil and next(sharedConfig.dealers) ~= nil then
        for _, v in pairs(sharedConfig.dealers) do
            DealersText = DealersText .. Lang:t("info.list_dealers_name_prefix") .. v.name .. "<br>"
        end
        TriggerClientEvent('chat:addMessage', source, {
            color = { 0, 0, 255 },
            template = '<div class="chat-message advert"><div class="chat-message-body"><strong>' .. Lang:t("info.list_dealers_title") .. '</strong><br><br> ' .. DealersText .. '</div></div>',
            args = {}
        })
    else
        exports.qbx_core:Notify(source, Lang:t("error.no_dealers"), 'error')
    end
end)

lib.addCommand("dealergoto", {
    help = "To teleport to dealer",
    params = {
        {
            name = 'name',
            type = 'string',
            help = Lang:t("info.dealergoto_command_help1_help"),
            optional = false
        },
    },
    restricted = 'group.admin'
}, function(source, args)
    local DealerName = args.name
    if sharedConfig.dealers[DealerName] then
        local ped = GetPlayerPed(source)
        SetEntityCoords(ped, sharedConfig.dealers[DealerName].coords.x, sharedConfig.dealers[DealerName].coords.y, sharedConfig.dealers[DealerName].coords.z, false, false, false, false)
        exports.qbx_core:Notify(source, Lang:t("success.teleported_to_dealer", {dealerName = DealerName}), 'success')
    else
        exports.qbx_core:Notify(source, Lang:t("error.dealer_not_exists"), 'error')
    end
end)


CreateThread(function()
    Wait(500)
    local dealers = MySQL.query.await('SELECT * FROM dealers')
    if dealers and #dealers ~= 0 then
        for i = 1, #dealers do
            local data = dealers[i]
            local coords = json.decode(data.coords)
            local time = json.decode(data.time)

            sharedConfig.dealers[data.name] = {
                name = data.name,
                coords = vec3(coords.x, coords.y, coords.z),
                time = { min = time.min, max = time.max },
                products = config.products
            }
        end
    end
    TriggerClientEvent('qb-drugs:client:RefreshDealers', -1, sharedConfig.dealers)
end)