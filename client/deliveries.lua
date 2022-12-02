QBCore = exports['qb-core']:GetCoreObject()
local currentDealer = nil
local dealerIsHome = false
local waitingDelivery = nil
local activeDelivery = nil
local deliveryTimeout = 0
local waitingKeyPress = false
local drugDeliveryZone = nil
local inDeliveryZone = false
local dealerPoly = {}

-- Handlers
AddStateBagChangeHandler('isLoggedIn', nil, function(_, _, value, _, _)
    if value then
        QBCore.Functions.TriggerCallback('qb-drugs:server:RequestConfig', function(DealerConfig)
            Config.Dealers = DealerConfig
        end)

        Wait(1000)

        InitZones()
    else
        if not Config.UseTarget then
            for k, _ in pairs(Config.Dealers) do
                dealerPoly[k]:remove()
            end
        end
    end
end)

-- Functions
local function GetClosestDealer()
    local pCoords = GetEntityCoords(cache.ped)

    for k, v in pairs(Config.Dealers) do
        local dealerCoords = vec3(v.coords.x, v.coords.y, v.coords.z)

        if #(pCoords - dealerCoords) < 2 then
            currentDealer = k
            break
        end
    end
end

local function OpenDealerShop()
    GetClosestDealer()

    local repItems = {}

    repItems.label = Config.Dealers[currentDealer]["name"]
    repItems.items = {}
    repItems.slots = 30

    for k, _ in pairs(Config.Dealers[currentDealer]["products"]) do
        if QBCore.Functions.GetPlayerData().metadata["dealerrep"] >= Config.Dealers[currentDealer]["products"][k].minrep then
            repItems.items[k] = Config.Dealers[currentDealer]["products"][k]
        end
    end

    TriggerServerEvent("inventory:server:OpenInventory", "shop", "Dealer_" .. Config.Dealers[currentDealer]["name"], repItems)
end

local function KnockDoorAnim(home)
    local knockAnimLib = "timetable@jimmy@doorknock@"
    local knockAnim = "knockdoor_idle"
    local myData = QBCore.Functions.GetPlayerData()

    if home then
        TriggerServerEvent("InteractSound_SV:PlayOnSource", "knock_door", 0.2)

        Wait(100)

        lib.requestAnimDict(knockAnimLib)

        TaskPlayAnim(cache.ped, knockAnimLib, knockAnim, 3.0, 3.0, -1, 1, 0, false, false, false)

        Wait(3500)

        TaskPlayAnim(cache.ped, knockAnimLib, "exit", 3.0, 3.0, -1, 1, 0, false, false, false)
        RemoveAnimDict(knockAnimLib)

        Wait(1000)

        dealerIsHome = true

        lib.notify({
            title = Lang:t("info.dealer_name", {
                dealerName = Config.Dealers[currentDealer].name
            }),
            description = Lang:t("info.fred_knock_message", {
                firstName = myData.charinfo.firstname
            }),
            type = 'error'
        })
        lib.showTextUI(Lang:t("info.other_dealers_button"))

        AwaitingInput()
    else
        TriggerServerEvent("InteractSound_SV:PlayOnSource", "knock_door", 0.2)

        Wait(100)

        lib.requestAnimDict(knockAnimLib)

        TaskPlayAnim(cache.ped, knockAnimLib, knockAnim, 3.0, 3.0, -1, 1, 0, false, false, false)

        Wait(3500)

        TaskPlayAnim(cache.ped, knockAnimLib, "exit", 3.0, 3.0, -1, 1, 0, false, false, false)
        RemoveAnimDict(knockAnimLib)

        Wait(1000)

        lib.notify({
            description = Lang:t("info.no_one_home"),
            type = 'error'
        })
    end
end

local function KnockDealerDoor()
    GetClosestDealer()

    local hours = GetClockHours()
    local min = Config.Dealers[currentDealer].time.min
    local max = Config.Dealers[currentDealer].time.max

    if max < min then
        if hours <= max then
            KnockDoorAnim(true)
        elseif hours >= min then
            KnockDoorAnim(true)
        else
            KnockDoorAnim(false)
        end
    else
        if hours >= min and hours <= max then
            KnockDoorAnim(true)
        else
            KnockDoorAnim(false)
        end
    end
end

local function RandomDeliveryItemOnRep()
    local myRep = QBCore.Functions.GetPlayerData().metadata.dealerrep
    local availableItems = {}

    for k, _ in pairs(Config.DeliveryItems) do
        if Config.DeliveryItems[k].minrep <= myRep then
            availableItems[#availableItems + 1] = k
        end
    end

    return availableItems[math.random(1, #availableItems)]
end

local function RequestDelivery()
    if not waitingDelivery then
        GetClosestDealer()

        local location = math.random(1, #Config.DeliveryLocations)
        local amount = math.random(1, 3)
        local item = RandomDeliveryItemOnRep()

        waitingDelivery = {
            coords = Config.DeliveryLocations[location].coords,
            locationLabel = Config.DeliveryLocations[location].label,
            amount = amount,
            dealer = currentDealer,
            itemData = Config.DeliveryItems[item],
            item = item
        }

        lib.notify({
            description = Lang:t("info.sending_delivery_email"),
            type = 'success'
        })

        TriggerServerEvent('qb-drugs:server:giveDeliveryItems', waitingDelivery)

        SetTimeout(2000, function()
            TriggerServerEvent('qb-phone:server:sendNewMail', {
                sender = Config.Dealers[currentDealer]["name"],
                subject = "Delivery Location",
                message = Lang:t("info.delivery_info_email", {itemAmount = amount, itemLabel = QBCore.Shared.Items[waitingDelivery["itemData"]["item"]]["label"]}),
                button = {
                    enabled = true,
                    buttonEvent = "qb-drugs:client:setLocation",
                    buttonData = waitingDelivery
                }
            })
        end)
    else
        lib.notify({
            description = Lang:t("error.pending_delivery"),
            type = 'error'
        })
    end
end

local function DeliveryTimer()
    CreateThread(function()
        while deliveryTimeout - 1 > 0 do
            deliveryTimeout -= 1

            Wait(1000)
        end

        deliveryTimeout = 0
    end)
end

local function PoliceCall()
    if Config.PoliceCallChance <= math.random(1, 100) then
        TriggerServerEvent('police:server:policeAlert', 'Suspicous activity')
    end
end

local function DeliverStuff()
    if deliveryTimeout > 0 then
        Wait(500)

        TriggerEvent('animations:client:EmoteCommandStart', {"bumbin"})

        PoliceCall()

        if lib.progressBar({
            duration = 3500,
            label = Lang:t("info.delivering_products"),
            useWhileDead = false,
            canCancel = true,
            disable = {
                move = true,
                car = true,
                combat = true
            }
        }) then
            TriggerServerEvent('qb-drugs:server:successDelivery', activeDelivery, true)

            activeDelivery = nil

            if Config.UseTarget then
                exports.ox_target:removeZone(drugDeliveryZone)
            else
                drugDeliveryZone:remove()
            end
        else
            ClearPedTasks(cache.ped)
        end
    else
        TriggerServerEvent('qb-drugs:server:successDelivery', activeDelivery, false)
    end

    deliveryTimeout = 0
end

local function SetMapBlip(x, y)
    SetNewWaypoint(x, y)

    lib.notify({
        description = Lang:t("success.route_has_been_set"),
        type = 'success'
    })
end

-- Zone specific functions
function AwaitingInput()
    CreateThread(function()
        waitingKeyPress = true

        while waitingKeyPress do
            if not dealerIsHome then
                if IsControlPressed(0, 38) then
                    KnockDealerDoor()
                end
            elseif dealerIsHome then
                if IsControlJustPressed(0, 38) then
                    OpenDealerShop()

                    waitingKeyPress = false
                end

                if IsControlJustPressed(0, 47) then
                    if waitingDelivery then
                        waitingKeyPress = false
                    end

                    RequestDelivery()

                    dealerIsHome = false
                    waitingKeyPress = false
                end
            end

            Wait(0)
        end
    end)
end

function InitZones()
    if Config.UseTarget then
        for k,v in pairs(Config.Dealers) do
            exports["qb-target"]:AddBoxZone("dealer_"..k, vec3(v.coords.x, v.coords.y, v.coords.z), 1.5, 1.5, {
                name = "dealer_" .. k,
                heading = v.heading,
                minZ = v.coords.z - 1,
                maxZ = v.coords.z + 1
            }, {
                options = {
                    {
                        icon = 'fas fa-user-secret',
                        label = Lang:t("info.target_request"),
                        action = function()
                            RequestDelivery()
                        end,
                        canInteract = function()
                            GetClosestDealer()
                            local hours = GetClockHours()
                            local min = Config.Dealers[currentDealer]["time"]["min"]
                            local max = Config.Dealers[currentDealer]["time"]["max"]

                            if max < min then
                                if hours <= max then
                                    if not waitingDelivery then
                                        return true
                                    end
                                elseif hours >= min then
                                    if not waitingDelivery then
                                        return true
                                    end
                                end
                            else
                                if hours >= min and hours <= max then
                                    if not waitingDelivery then
                                        return true
                                    end
                                end
                            end
                        end
                    },
                    {
                        icon = 'fas fa-user-secret',
                        label = Lang:t("info.target_openshop"),
                        action = function()
                            OpenDealerShop()
                        end,
                        canInteract = function()
                            GetClosestDealer()
                            local hours = GetClockHours()
                            local min = Config.Dealers[currentDealer]["time"]["min"]
                            local max = Config.Dealers[currentDealer]["time"]["max"]

                            if max < min then
                                if hours <= max then
                                    return true
                                elseif hours >= min then
                                    return true
                                end
                            else
                                if hours >= min and hours <= max then
                                    return true
                                end
                            end
                        end
                    }
                },
                distance = 1.5
            })
        end
    else
        for k, v in pairs(Config.Dealers) do
            dealerPoly[k] = lib.zones.box({
                coords = v.coords,
                size = vec3(1.5, 1.5, 1.5),
                rotation = -20,
                onEnter = function(_)
                    if not dealerIsHome then
                        lib.showTextUI(Lang:t("info.knock_button"))

                        AwaitingInput()
                    elseif dealerIsHome then
                        lib.showTextUI(Lang:t("info.other_dealers_button"))

                        AwaitingInput()
                    end
                end,
                onExit = function(_)
                    if not dealerIsHome then
                        lib.showTextUI(Lang:t("info.knock_button"))

                        AwaitingInput()
                    elseif dealerIsHome then
                        waitingKeyPress = false

                        lib.hideTextUI()
                    end
                end
            })
        end
    end
end

-- Events
RegisterNetEvent('qb-drugs:client:RefreshDealers', function(DealerData)
    if not Config.UseTarget then
        for k, _ in pairs(Config.Dealers) do
            dealerPoly[k]:remove()
        end
    end

    Config.Dealers = DealerData

    Wait(1000)

    InitZones()
end)

RegisterNetEvent('qb-drugs:client:updateDealerItems', function(itemData, amount)
    TriggerServerEvent('qb-drugs:server:updateDealerItems', itemData, amount, currentDealer)
end)

RegisterNetEvent('qb-drugs:client:setDealerItems', function(itemData, amount, dealer)
    Config.Dealers[dealer]["products"][itemData.slot].amount = Config.Dealers[dealer]["products"][itemData.slot].amount - amount
end)

RegisterNetEvent('qb-drugs:client:setLocation', function(locationData)
    if activeDelivery then
        SetMapBlip(activeDelivery.coords.x, activeDelivery.coords.y)

        lib.notify({
            description = Lang:t("error.pending_delivery"),
            type = 'error'
        })
        return
    end

    activeDelivery = locationData
    deliveryTimeout = 300

    DeliveryTimer()
    SetMapBlip(activeDelivery.coords.x, activeDelivery.coords.y)

    if Config.UseTarget then
        exports["qb-target"]:AddBoxZone('drugDeliveryZone', vec3(activeDelivery["coords"].x, activeDelivery["coords"].y, activeDelivery["coords"].z), 1.5, 1.5, {
            name = 'drugDeliveryZone',
            heading = 0,
            minZ = activeDelivery["coords"].z - 1,
            maxZ = activeDelivery["coords"].z + 1
        }, {
            options = {
                {
                    icon = "fa-solid fa-user-secret",
                    label = Lang:t("info.target_deliver"),
                    action = function()
                        DeliverStuff()
                        waitingDelivery = nil
                    end,
                    canInteract = function()
                        if waitingDelivery then
                            return true
                        end
                    end
                }
            },
            distance = 1.5
        })
    else
        drugDeliveryZone = lib.zones.box({
            coords = activeDelivery.coords,
            size = vec3(1.5, 1.5, 1.5),
            rotation = 0.0,
            onEnter = function(_)
                inDeliveryZone = true

                lib.showTextUI(Lang:t("info.deliver_items_button", {itemAmount = activeDelivery["amount"], itemLabel = QBCore.Shared.Items[activeDelivery["itemData"]["item"]]["label"]}))

                CreateThread(function()
                    while inDeliveryZone do
                        if IsControlJustPressed(0, 38) then
                            DeliverStuff()

                            waitingDelivery = nil
                            break
                        end

                        Wait(0)
                    end
                end)
            end,
            onExit = function(_)
                inDeliveryZone = false

                lib.hideTextUI()
            end
        })
    end
end)

RegisterNetEvent('qb-drugs:client:sendDeliveryMail', function(type, deliveryData)
    if type == 'perfect' then
        TriggerServerEvent('qb-phone:server:sendNewMail', {
            sender = Config.Dealers[deliveryData["dealer"]]["name"],
            subject = "Delivery",
            message = Lang:t("info.perfect_delivery", {dealerName = Config.Dealers[deliveryData["dealer"]]["name"]})
        })
    elseif type == 'bad' then
        TriggerServerEvent('qb-phone:server:sendNewMail', {
            sender = Config.Dealers[deliveryData["dealer"]]["name"],
            subject = "Delivery",
            message = Lang:t("info.bad_delivery")
        })
    elseif type == 'late' then
        TriggerServerEvent('qb-phone:server:sendNewMail', {
            sender = Config.Dealers[deliveryData["dealer"]]["name"],
            subject = "Delivery",
            message = Lang:t("info.late_delivery")
        })
    end
end)