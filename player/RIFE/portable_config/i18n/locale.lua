local mp = require "mp"
local utils = require "mp.utils"

local locale = {}
locale.property = "user-data/rtx-video/language"
locale.path = mp.command_native({"expand-path", "~~/language.txt"})

function locale.saved()
    local text = utils.read_local_file(locale.path, 8)
    return text and text:match("^en%s*$") and "en" or "ru"
end

function locale.current()
    return mp.get_property_native(locale.property) or locale.saved()
end

function locale.text(ru, en)
    return locale.current() == "en" and en or ru
end

function locale.set(language)
    if not utils.atomic_write_file(locale.path, language .. "\n") then return false end
    mp.set_property_native(locale.property, language)
    return true
end

return locale
