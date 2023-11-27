fx_version 'cerulean'
game 'gta5'

description 'QBX_Drugs'
repository 'https://github.com/Qbox-project/qbx_drugs'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/shared/locale.lua',
    'locales/en.lua',
    'locales/*.lua',
}

client_scripts{
    '@qbx_core/modules/playerdata.lua',
    'client/deliveries.lua',
    'client/cornerselling.lua',
}

server_scripts{
    '@oxmysql/lib/MySQL.lua',
    'server/deliveries.lua',
    'server/cornerselling.lua',
}

files {
    'config/client.lua',
    'config/shared.lua'
}

lua54 'yes'
use_experimental_fxv2_oal 'yes'