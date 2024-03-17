local config = require 'config.server'
local sharedConfig = require 'config.shared'

exports('GetDealers', function()
    return sharedConfig.dealers
end)

lib.callback.register('qb-drugs:server:RequestConfig', function()
    return sharedConfig.dealers
end)

RegisterNetEvent('qb-drugs:server:randomPoliceAlert', function()
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return end
    if config.policeCallChance >= math.random(1, 100) then
        TriggerEvent('police:server:policeAlert', locale('info.possible_drug_dealing'), nil, player.PlayerData.source)
    end
end)

RegisterNetEvent('qb-drugs:server:updateDealerItems', function(itemData, amount, dealer)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)

    if not player then return end

    if sharedConfig.dealers[dealer].products[itemData.slot].amount - 1 >= 0 then
        sharedConfig.dealers[dealer].products[itemData.slot].amount -= amount
        TriggerClientEvent('qb-drugs:client:setDealerItems', -1, itemData, amount, dealer)
    else
        exports.ox_inventory:RemoveItem(src, itemData.name, amount)
        player.Functions.AddMoney('cash', amount * sharedConfig.dealers[dealer].products[itemData.slot].price)
        exports.qbx_core:Notify(src, locale('error.item_unavailable'), 'error')
    end
end)

RegisterNetEvent('qb-drugs:server:giveDeliveryItems', function(deliveryData)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)

    if not player then return end

    local item = sharedConfig.deliveryItems[deliveryData.item].item

    if not item then return end

    exports.ox_inventory:AddItem(src, item, deliveryData.amount)
end)

RegisterNetEvent('qb-drugs:server:successDelivery', function(deliveryData, inTime)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)

    if not player then return end

    local item = sharedConfig.deliveryItems[deliveryData.item].item
    local itemAmount = deliveryData.amount
    local payout = deliveryData.itemData.payout * itemAmount
    local copsOnline = exports.qbx_core:GetDutyCountType('leo')
    local curRep = player.PlayerData.metadata.dealerrep
    local invItem = exports.ox_inventory:Search(src, 'count', item)
    if inTime then
        if invItem and invItem.amount >= itemAmount then -- on time correct amount
            exports.ox_inventory:RemoveItem(src, item, itemAmount)
            if copsOnline > 0 then
                local copModifier = copsOnline * config.policeDeliveryModifier
                if config.useMarkedBills then
                    local worth = math.floor(payout * copModifier)
                    local metadata = { worth = worth, description = 'Value: ' .. worth }
                    exports.ox_inventory:AddItem(src, 'markedbills', 1, metadata)
                else
                    player.Functions.AddMoney('cash', math.floor(payout * copModifier), 'drug-delivery')
                end
            else
                if config.useMarkedBills then
                    local metadata = { worth = payout, description = 'Value: ' .. payout }
                    exports.ox_inventory:AddItem(src, 'markedbills', 1, metadata)
                else
                    player.Functions.AddMoney('cash', payout, 'drug-delivery')
                end
            end
            exports.qbx_core:Notify(src, locale('success.order_delivered'), 'success')
            SetTimeout(math.random(5000, 10000), function()
                TriggerClientEvent('qb-drugs:client:sendDeliveryMail', src, 'perfect', deliveryData)
                player.Functions.SetMetaData('dealerrep', (curRep + config.deliveryRepGain))
            end)
        else
            exports.qbx_core:Notify(src, locale('error.order_not_right'), 'error')-- on time incorrect amount
            if invItem then
                local newItemAmount = invItem.amount
                local modifiedPayout = deliveryData.itemData.payout * newItemAmount
                exports.ox_inventory:RemoveItem(src, item, newItemAmount)
                player.Functions.AddMoney('cash', math.floor(modifiedPayout / config.wrongAmountFee))
            end
            SetTimeout(math.random(5000, 10000), function()
                TriggerClientEvent('qb-drugs:client:sendDeliveryMail', src, 'bad', deliveryData)
                if curRep - 1 > 0 then
                    player.Functions.SetMetaData('dealerrep', (curRep - config.deliveryRepLoss))
                else
                    player.Functions.SetMetaData('dealerrep', 0)
                end
            end)
        end
    else
        if invItem and invItem.amount >= itemAmount then -- late correct amount
            exports.qbx_core:Notify(src, locale('error.too_late'), 'error')
            exports.ox_inventory:RemoveItem(src, item, itemAmount)
            player.Functions.AddMoney('cash', math.floor(payout / config.overdueDeliveryFee), 'delivery-drugs-too-late')
            SetTimeout(math.random(5000, 10000), function()
                TriggerClientEvent('qb-drugs:client:sendDeliveryMail', src, 'late', deliveryData)
                if curRep - 1 > 0 then
                    player.Functions.SetMetaData('dealerrep', (curRep - config.deliveryRepLoss))
                else
                    player.Functions.SetMetaData('dealerrep', 0)
                end
            end)
        else
            if invItem then -- late incorrect amount
                local newItemAmount = invItem.amount
                local modifiedPayout = deliveryData.itemData.payout * newItemAmount
                exports.qbx_core:Notify(src, locale('error.too_late'), 'error')
                exports.ox_inventory:RemoveItem(src, item, itemAmount)
                player.Functions.AddMoney('cash', math.floor(modifiedPayout / config.overdueDeliveryFee), 'delivery-drugs-too-late')
                SetTimeout(math.random(5000, 10000), function()
                    TriggerClientEvent('qb-drugs:client:sendDeliveryMail', src, 'late', deliveryData)
                    if curRep - 1 > 0 then
                        player.Functions.SetMetaData('dealerrep', (curRep - config.deliveryRepLoss))
                    else
                        player.Functions.SetMetaData('dealerrep', 0)
                    end
                end)
            end
        end
    end
end)


lib.addCommand('newdealer', {
    help = locale('info.newdealer_command_desc'),
    params = {
        {
            name = 'name',
            type = 'string',
            help = locale('info.newdealer_command_help1_help'),
            optional = false
        },
        {
            name = 'min',
            type = 'number',
            help = locale('info.newdealer_command_help2_help'),
            optional = false
        },
        {
            name = 'max',
            type = 'number',
            help = locale('info.newdealer_command_help3_help'),
            optional = false
        }
    },
    restricted = 'group.admin'
}, function(source, args)
    local ped = GetPlayerPed(source)
    local coords = GetEntityCoords(ped)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return end
    local dealerName = args.name
    local minTime = args.min
    local maxTime = args.max
    local time = json.encode({min = minTime, max = maxTime})
    local pos = json.encode({x = coords.x, y = coords.y, z = coords.z})
    local result = MySQL.scalar.await('SELECT name FROM dealers WHERE name = ?', {dealerName})
    if result then return exports.qbx_core:Notify(source, locale('error.dealer_already_exists'), 'error') end
    MySQL.insert('INSERT INTO dealers (name, coords, time, createdby) VALUES (?, ?, ?, ?)', {dealerName, pos, time, player.PlayerData.citizenid}, function()
        sharedConfig.dealers[dealerName] = {
            name = dealerName,
            coords = vec3(coords.x, coords.y, coords.z),
            time = { min = minTime, max = maxTime },
            products = config.products
        }
        TriggerClientEvent('qb-drugs:client:RefreshDealers', -1, sharedConfig.dealers)
    end)
end)

lib.addCommand('deletedealer', {
    help = locale('info.newdealer_command_desc'),
    params = {
        {
            name = 'name',
            type = 'string',
            help = locale('info.deletedealer_command_help1_help'),
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
        exports.qbx_core:Notify(source, locale('success.dealer_deleted', dealerName), 'success')
    else
        exports.qbx_core:Notify(source, locale('error.dealer_not_exists_command', dealerName), 'error')
    end
end)

lib.addCommand('dealers', {
    help = 'To see the list of dealers',
    restricted = 'group.admin'
}, function(source)
    local dealersText = ''
    if sharedConfig.dealers ~= nil and next(sharedConfig.dealers) ~= nil then
        for _, v in pairs(sharedConfig.dealers) do
            dealersText = dealersText .. locale('info.list_dealers_name_prefix') .. v.name .. '<br>'
        end
        TriggerClientEvent('chat:addMessage', source, {
            color = { 0, 0, 255 },
            template = "<div class='chat-message advert'><div class='chat-message-body'><strong>' .. locale('info.list_dealers_title') .. '</strong><br><br> ' .. dealersText .. '</div></div>",
            args = {}
        })
    else
        exports.qbx_core:Notify(source, locale('error.no_dealers'), 'error')
    end
end)

lib.addCommand('dealergoto', {
    help = 'To teleport to dealer',
    params = {
        {
            name = 'name',
            type = 'string',
            help = locale('info.dealergoto_command_help1_help'),
            optional = false
        },
    },
    restricted = 'group.admin'
}, function(source, args)
    local dealerName = args.name
    if sharedConfig.dealers[dealerName] then
        local ped = GetPlayerPed(source)
        SetEntityCoords(ped, sharedConfig.dealers[dealerName].coords.x, sharedConfig.dealers[dealerName].coords.y, sharedConfig.dealers[dealerName].coords.z, false, false, false, false)
        exports.qbx_core:Notify(source, locale('success.teleported_to_dealer', dealerName), 'success')
    else
        exports.qbx_core:Notify(source, locale('error.dealer_not_exists'), 'error')
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