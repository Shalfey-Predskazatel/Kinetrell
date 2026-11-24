local mp = require "mp"
local utils = require "mp.utils"

-- The launcher sets the working directory to the portable folder. Relative
-- paths here let the Lua runtime use only ASCII file names on Windows.
local request = "portable_config/.launcher-open.json"
local processing = "portable_config/.launcher-processing.json"

local function open_requested_files()
    if not os.rename(request, processing) then
        return
    end
    local file = io.open(processing, "rb")
    if file then
        local paths = utils.parse_json(file:read("*a"))
        file:close()
        if type(paths) == "table" then
            for i, path in ipairs(paths) do
                if type(path) == "string" then
                    mp.commandv("loadfile", path, i == 1 and "replace" or "append")
                end
            end
            mp.set_property_native("pause", false)
        end
    end
    os.remove(processing)
end

mp.add_periodic_timer(0.12, open_requested_files)
