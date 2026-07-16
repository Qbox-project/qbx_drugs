local config = require 'config.server'
local sharedConfig = require 'config.shared'
local activeDeliveries = {}
local policeAlertCooldowns = {}

---@param source number
---@param coords vector3
---@param maxDistance number
---@return boolean
local function isPlayerNear(source, coords, maxDistance)
    local ped = GetPlayerPed(source)
    if ped == 0 then return false end

    return #(GetEntityCoords(ped) - coords) <= maxDistance
end

---@param source number
---@param dealer string
---@return boolean
local function isNearDealer(source, dealer)
    local dealerData = type(dealer) == 'string' and sharedConfig.dealers[dealer]
    return dealerData ~= nil and isPlayerNear(source, dealerData.coords, 4.0)
end

exports('GetDealers', function()
    return sharedConfig.dealers
end)

lib.callback.register('qb-drugs:server:RequestConfig', function()
    return sharedConfig.dealers
end)

RegisterNetEvent('qb-drugs:server:randomPoliceAlert', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    local delivery = activeDeliveries[src]
    if not player or not delivery or not isPlayerNear(src, delivery.data.coords, 5.0) then return end

    local currentTime = GetGameTimer()
    if policeAlertCooldowns[src] and currentTime - policeAlertCooldowns[src] < 30000 then return end
    policeAlertCooldowns[src] = currentTime

    if config.policeCallChance >= math.random(1, 100) then
        TriggerEvent('police:server:policeAlert', locale('info.possible_drug_dealing'), nil, player.PlayerData.source)
    end
end)

RegisterNetEvent('qb-drugs:server:updateDealerItems', function(itemData, amount, dealer)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player or type(itemData) ~= 'table' or type(itemData.slot) ~= 'number'
        or itemData.slot % 1 ~= 0 or type(amount) ~= 'number' or amount % 1 ~= 0
        or amount < 1 or amount > 100 or not isNearDealer(src, dealer) then return end

    local dealerData = sharedConfig.dealers[dealer]
    local product = dealerData.products[itemData.slot]
    if not product or itemData.name ~= product.name or player.PlayerData.metadata.dealerrep < product.minrep
        or product.amount < amount then
        return exports.qbx_core:Notify(src, locale('error.item_unavailable'), 'error')
    end

    product.amount = product.amount - amount
    TriggerClientEvent('qb-drugs:client:setDealerItems', -1, {name = product.name, slot = itemData.slot}, amount, dealer)
end)

lib.callback.register('qb-drugs:server:requestDelivery', function(source, dealer)
    local player = exports.qbx_core:GetPlayer(source)
    if not player or not isNearDealer(source, dealer) then return false end
    if activeDeliveries[source] then return activeDeliveries[source].data end

    local stored = player.PlayerData.metadata.drugdelivery
    if type(stored) == 'table' then
        local storedItem = sharedConfig.deliveryItems[stored.item]
        local storedLocation = sharedConfig.deliveryLocations[stored.location]
        if storedItem and storedLocation and type(stored.amount) == 'number'
            and stored.amount % 1 == 0 and stored.amount >= 1 and stored.amount <= 3
            and type(stored.dealer) == 'string' and sharedConfig.dealers[stored.dealer]
            and type(stored.startedAt) == 'number' then
            local delivery = {
                coords = storedLocation.coords,
                locationLabel = storedLocation.label,
                amount = stored.amount,
                dealer = stored.dealer,
                itemData = storedItem,
                item = stored.item,
            }
            activeDeliveries[source] = {data = delivery, startedAt = stored.startedAt}
            return delivery
        end

        player.Functions.SetMetaData('drugdelivery', nil)
    end

    local availableItems = {}
    for i = 1, #sharedConfig.deliveryItems do
        if sharedConfig.deliveryItems[i].minrep <= player.PlayerData.metadata.dealerrep then
            availableItems[#availableItems + 1] = i
        end
    end
    if #availableItems == 0 then return false end

    local itemIndex = availableItems[math.random(1, #availableItems)]
    local itemData = sharedConfig.deliveryItems[itemIndex]
    local locationIndex = math.random(1, #sharedConfig.deliveryLocations)
    local location = sharedConfig.deliveryLocations[locationIndex]
    local amount = math.random(1, 3)
    local delivery = {
        coords = location.coords,
        locationLabel = location.label,
        amount = amount,
        dealer = dealer,
        itemData = itemData,
        item = itemIndex,
    }

    if not exports.ox_inventory:AddItem(source, itemData.item, amount) then return false end

    activeDeliveries[source] = {
        data = delivery,
        startedAt = os.time(),
    }
    player.Functions.SetMetaData('drugdelivery', {
        item = itemIndex,
        location = locationIndex,
        amount = amount,
        dealer = dealer,
        startedAt = activeDeliveries[source].startedAt,
    })
    return delivery
end)

RegisterNetEvent('qb-drugs:server:successDelivery', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    local delivery = activeDeliveries[src]
    if not player or not delivery or not isPlayerNear(src, delivery.data.coords, 4.0) then return end

    activeDeliveries[src] = nil
    player.Functions.SetMetaData('drugdelivery', nil)
    local itemData = sharedConfig.deliveryItems[delivery.data.item]
    if not itemData or itemData.item ~= delivery.data.itemData.item then return end

    local expectedAmount = delivery.data.amount
    local inventoryAmount = exports.ox_inventory:GetItemCount(src, itemData.item)
    local deliveredAmount = math.min(expectedAmount, inventoryAmount)
    local onTime = os.time() - delivery.startedAt <= 300
    local complete = deliveredAmount == expectedAmount
    if deliveredAmount < 1 or not exports.ox_inventory:RemoveItem(src, itemData.item, deliveredAmount) then
        exports.qbx_core:Notify(src, locale('error.order_not_right'), 'error')
        return
    end

    local payout = itemData.payout * deliveredAmount
    if onTime and complete then
        local copsOnline = exports.qbx_core:GetDutyCountType('leo')
        if copsOnline > 0 then payout = payout * copsOnline * config.policeDeliveryModifier end
    elseif onTime then
        payout = payout / config.wrongAmountFee
    else
        payout = payout / config.overdueDeliveryFee
    end
    payout = math.floor(payout)

    if config.useMarkedBills then
        exports.ox_inventory:AddItem(src, 'markedbills', 1, {
            worth = payout,
            description = 'Value: ' .. payout,
        })
    else
        player.Functions.AddMoney('cash', payout, onTime and 'drug-delivery' or 'delivery-drugs-too-late')
    end

    local currentRep = player.PlayerData.metadata.dealerrep
    local mailType
    if onTime and complete then
        mailType = 'perfect'
        player.Functions.SetMetaData('dealerrep', currentRep + config.deliveryRepGain)
        exports.qbx_core:Notify(src, locale('success.order_delivered'), 'success')
    else
        mailType = onTime and 'bad' or 'late'
        player.Functions.SetMetaData('dealerrep', math.max(0, currentRep - config.deliveryRepLoss))
        exports.qbx_core:Notify(src, onTime and locale('error.order_not_right') or locale('error.too_late'), 'error')
    end

    TriggerClientEvent('qb-drugs:client:sendDeliveryMail', src, mailType, delivery.data)
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

AddEventHandler('playerDropped', function()
    activeDeliveries[source] = nil
    policeAlertCooldowns[source] = nil
end)
