return {
    useTarget = GetConvar('UseTarget', 'false') == 'true',
    policeCallChance = 15,
    successChance = 50,
    scamChance = 25,
    robberyChance = 25,
    minimumDrugSalePolice = 0,
    drugsPrice = {
        ['weed_white-widow'] = {
            min = 15,
            max = 24,
        },
        ['weed_og-kush'] = {
            min = 15,
            max = 28,
        },
        ['weed_skunk'] = {
            min = 15,
            max = 31,
        },
        ['weed_amnesia'] = {
            min = 18,
            max = 34,
        },
        ['weed_purple-haze'] = {
            min = 18,
            max = 37,
        },
        ['weed_ak47'] = {
            min = 18,
            max = 40,
        },
        ['crack_baggy'] = {
            min = 18,
            max = 34,
        },
        ['cokebaggy'] = {
            min = 18,
            max = 37,
        },
        ['meth'] = {
            min = 18,
            max = 40,
        },
    },
    deliveryLocations = {
        {
            label = 'Strip Club',
            coords = vec3(106.24, -1280.32, 29.24),
        },
        {
            label = 'Vinewood Video',
            coords = vec3(223.98, 121.53, 102.76),
        },
        {
            label = 'Taxi',
            coords = vec3(882.67, -160.26, 77.11),
        },
        {
            label = 'Resort',
            coords = vec3(-1245.63, 376.21, 75.34),
        },
        {
            label = 'Bahama Mamas',
            coords = vec3(-1383.1, -639.99, 28.67),
        },
    }
}