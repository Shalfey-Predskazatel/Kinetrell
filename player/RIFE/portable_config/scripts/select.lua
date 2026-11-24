local mp = require "mp"
local utils = require "mp.utils"
local directory = mp.command_native({"expand-path", "~~/i18n"})
local function load_script(name)
    local path = directory .. "/" .. name .. ".lua"
    local source = assert(utils.read_local_file(path, 256 * 1024))
    return assert(loadstring(source, "@" .. path))()
end
local locale = load_script("locale")
load_script("select-" .. locale.saved())
