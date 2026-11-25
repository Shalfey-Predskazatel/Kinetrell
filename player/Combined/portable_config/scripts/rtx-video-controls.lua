local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

local path = mp.command_native({"expand-path", "~~/i18n/locale.lua"})
local locale = assert(loadstring(assert(require("mp.utils").read_local_file(path, 4096)), "@" .. path))()
local tr = locale.text


msg.info("VFG, RIFE and RTX Video controls loaded")

local targets = {
    {id = "display", label = "экран", english = "display"},
    {id = "1080", width = 1920, height = 1080, label = "1080p"},
    {id = "1440", width = 2560, height = 1440, label = "1440p"},
    {id = "2160", width = 3840, height = 2160, label = "4K"},
}

local quality_modes = {
    rife = {
        {id = "4171", label = "RIFE 4.17 Lite", button_label = "4.17 Lite"},
        {id = "44", label = "RIFE 4.4", button_label = "4.4"},
        {id = "46", label = "RIFE 4.6", button_label = "4.6"},
    },
    vfg = {
        {id = "low", label = "Низкое", english = "Low"},
        {id = "medium", label = "Среднее", english = "Medium"},
        {id = "high", label = "Высокое", english = "High"},
    },
}

local multipliers = {0, 2, 3, 4, 5, 6}
local multiplier_labels = {"Выкл.", "2×", "3×", "4×", "5×", "6×"}
local multiplier_indices = {}
for index, value in ipairs(multipliers) do
    multiplier_indices[value] = index
end

local plugins = os.getenv("VAPOURSYNTH_PLUGIN_PATH")
local has_tensorrt = plugins and utils.file_info(plugins .. "/vstrt.dll")
    and utils.file_info(plugins .. "/vsmlrt-cuda/nvinfer_10.dll")
local profiles = {
    vfg = {multiplier = 2, quality = 1},
    rife = {multiplier = 2, quality = has_tensorrt and 1 or 2},
}
local state = {
    auto = false,
    backend = "rife",
    multiplier = profiles.rife.multiplier,
    quality = profiles.rife.quality,
    sr_enabled = true,
    sr_target = "display",
    hdr_enabled = true,
}

local player_options = {
    volume = "number",
    mute = "boolean",
    fullscreen = "boolean",
    ["window-maximized"] = "boolean",
}
local player_settings = {}
local state_path = mp.command_native({"expand-path", "~~home/combined-video-state.json"})
local save_timer
local settings_dirty = false
local last_applied_filter_chain = nil

local function valid_player_setting(name, value)
    if type(value) ~= player_options[name] then
        return false
    end
    return name ~= "volume" or (value >= 0 and value <= 1000)
end

local function load_settings()
    local text = utils.read_local_file(state_path, 4096)
    if not text then
        return
    end
    local saved = utils.parse_json(text)
    if type(saved) ~= "table" or saved.version ~= 1 or
       type(saved.rtx) ~= "table" or type(saved.player) ~= "table" then
        msg.warn(tr("Некорректный файл настроек RTX Video. Используются начальные настройки.", "Invalid RTX Video settings file. Loading defaults."))
        return
    end

    local rtx = saved.rtx
    for backend, profile in pairs(profiles) do
        local stored = type(rtx.profiles) == "table" and rtx.profiles[backend]
        if type(stored) == "table" then
            if multiplier_indices[stored.multiplier] and stored.multiplier > 0 then
                profile.multiplier = stored.multiplier
            end
            for index, mode in ipairs(quality_modes[backend]) do
                if stored.quality == mode.id then
                    profile.quality = index
                    break
                end
            end
        end
    end
    if rtx.backend == "off" or profiles[rtx.backend] then
        state.backend = rtx.backend
    end
    local active = profiles[state.backend]
    state.multiplier = active and active.multiplier or 0
    state.quality = active and active.quality or 1
    for _, target in ipairs(targets) do
        if rtx.sr_target == target.id then
            state.sr_target = target.id
            break
        end
    end
    for _, name in ipairs({"sr_enabled", "hdr_enabled", "auto"}) do
        if type(rtx[name]) == "boolean" then
            state[name] = rtx[name]
        end
    end
    for name in pairs(player_options) do
        if valid_player_setting(name, saved.player[name]) then
            player_settings[name] = saved.player[name]
        end
    end
end

local function save_settings()
    if save_timer then
        save_timer:kill()
        save_timer = nil
    end
    if not settings_dirty then
        return
    end

    local stored_profiles = {}
    for backend, profile in pairs(profiles) do
        stored_profiles[backend] = {
            multiplier = profile.multiplier,
            quality = quality_modes[backend][profile.quality].id,
        }
    end
    local text = utils.format_json({
        version = 1,
        rtx = {
            backend = state.backend,
            profiles = stored_profiles,
            auto = state.auto,
            sr_enabled = state.sr_enabled,
            sr_target = state.sr_target,
            hdr_enabled = state.hdr_enabled,
        },
        player = player_settings,
    }, true)
    if not text or not utils.atomic_write_file(state_path, text .. "\n") then
        msg.warn(tr("Не удалось сохранить настройки RTX Video. Проверь права на запись в папку плеера.", "Could not save RTX Video settings. Check write permissions for the player folder."))
        return
    end
    settings_dirty = false
end

local function queue_settings_save()
    settings_dirty = true
    if not save_timer then
        save_timer = mp.add_timeout(0.25, save_settings)
    end
end

local function restore_player_options()
    for name in pairs(player_options) do
        if not mp.get_property_bool("option-info/" .. name .. "/set-from-commandline") then
            if player_settings[name] ~= nil then
                mp.set_property_native(name, player_settings[name])
            end
            player_settings[name] = mp.get_property_native(name)
            mp.observe_property(name, "native", function(property, value)
                if valid_player_setting(property, value) and player_settings[property] ~= value then
                    player_settings[property] = value
                    queue_settings_save()
                end
            end)
        end
    end
end

local function copy_state()
    local copy = {}
    for key, value in pairs(state) do
        copy[key] = value
    end
    return copy
end

local function source_fps()
    local value = mp.get_property_number("video-params/fps")
    if not value or value <= 0 then
        value = mp.get_property_number("container-fps")
    end
    return value
end

-- Use the largest available integer multiplier that fits the display.
local function effective_multiplier(value)
    if not value.auto or value.backend == "off" then return value.multiplier end
    local fps = source_fps()
    local refresh = mp.get_property_number("display-fps")
    if not fps or fps <= 0 or not refresh or refresh <= 0 then return 0 end
    for index = #multipliers, 2, -1 do
        if fps * multipliers[index] <= refresh * 1.001 then return multipliers[index] end
    end
    return 0
end

local function effective_state(value)
    if not value.auto then return value end
    local active = {}
    for key, setting in pairs(value) do active[key] = setting end
    active.multiplier = effective_multiplier(value)
    if active.multiplier == 0 then active.backend = "off" end
    return active
end

local popup_callback
local popup_token = 0
local function select_popup(anchor, options)
    popup_token = popup_token + 1
    popup_callback = options.submit
    local menu = utils.format_json({
        anchor = anchor, token = popup_token, title = options.prompt,
        items = options.items, selected = options.default_item,
    })
    mp.commandv("script-message-to", "osc", "osc-rtx-popup", menu)
end

mp.register_script_message("rtx-popup-choice", function(token, index)
    if tonumber(token) ~= popup_token or not popup_callback then return end
    local callback = popup_callback
    popup_callback = nil
    callback(tonumber(index))
end)

local function source_dimensions()
    local width = mp.get_property_number("video-params/w")
    local height = mp.get_property_number("video-params/h")
    if width and width > 0 and height and height > 0 then
        return mp.get_property_number("video-params/dw", width),
               mp.get_property_number("video-params/dh", height)
    end
    return nil, nil
end

local function initial_dimensions()
    local track = mp.get_property_native("current-tracks/video")
    if not track then
        return nil, nil
    end
    local width, height = track["demux-w"], track["demux-h"]
    if not width or width <= 0 or not height or height <= 0 then
        return nil, nil
    end
    local par = track["demux-par"] or 1
    if par > 1 then
        width = math.floor(width * par + 0.5)
    elseif par > 0 and par < 1 then
        height = math.floor(height / par + 0.5)
    end
    return width, height
end

local function vpp_before_vfg(state_value)
    if state_value.backend ~= "vfg" or not (state_value.sr_enabled and state_value.hdr_enabled) then
        return false
    end
    return state_value.multiplier >= 4
        or (state_value.multiplier == 2 and quality_modes.vfg[state_value.quality].id == "high"
            and (state_value.sr_target == "display" or state_value.sr_target == "1080"))
end

local function limit_auto_sr(state_value)
    return state_value.backend == "rife" or vpp_before_vfg(state_value)
end

local function target_dimensions(target, state_value)
    if target.id ~= "display" then
        return target.width, target.height
    end

    -- Use the monitor rather than the window size so resizing, minimizing or
    -- changing fullscreen does not switch VSR to a 1:1 pass.
    local width = mp.get_property_number("display-width", 0)
    local height = mp.get_property_number("display-height", 0)
    -- Keep automatic upscaling at Full HD while RIFE runs.
    -- Explicit targets are handled above.
    local cap_width = limit_auto_sr(state_value) and 1920 or 3840
    local cap_height = limit_auto_sr(state_value) and 1080 or 2160
    -- Use a conservative fallback before mpv creates its first window.
    return math.min(width > 0 and width or 1920, cap_width),
           math.min(height > 0 and height or 1080, cap_height)
end

local function get_target(state_value)
    for _, target in ipairs(targets) do
        if target.id == state_value.sr_target then
            return target
        end
    end
    return targets[1]
end

local function sr_scale(state_value, width, height)
    if not width then
        return 1
    end
    local target_width, target_height = target_dimensions(get_target(state_value), state_value)
    return math.max(1, math.min(target_width / width, target_height / height))
end

local function format_scale(value)
    local formatted = string.format("%.3f", value)
    formatted = formatted:gsub("0+$", ""):gsub("%.$", "")
    return formatted
end

local function quality_label(mode)
    return tr(mode.label, mode.english or mode.label)
end

local function multiplier_label(index)
    if index == 1 then return tr("Выкл.", "Off") end
    return multiplier_labels[index]
end

local function update_buttons()
    local backend = state.backend
    local mode = quality_modes[backend] and quality_modes[backend][state.quality]
    local name = backend == "off" and tr("Ген. выкл.", "FG off") or backend:upper()
    local multiplier = effective_multiplier(state)
    local label = multiplier > 0 and multiplier_label(multiplier_indices[multiplier]) or "—"
    if state.auto then label = tr("Авто", "Auto") .. " " .. label end
    mp.commandv("script-message-to", "osc", "osc-custom-button", "1", name)
    mp.commandv("script-message-to", "osc", "osc-custom-button", "2", label)
    mp.commandv("script-message-to", "osc", "osc-custom-button", "3",
                mode and (mode.button_label or quality_label(mode)) or "—")
    mp.commandv("script-message-to", "osc", "osc-custom-button", "7", tr("Кадры", "Frames"))
    mp.commandv("script-message-to", "osc", "osc-custom-button", "5", tr("Размер", "Size"))
    mp.commandv("script-message-to", "osc", "osc-custom-button", "8", tr("RU", "EN"))
    mp.set_property("title", "$" .. "{media-title:" .. tr("Проигрыватель RTX Video", "RTX Video Player") .. "}")
end

local function build_filter_chain(state_value, width, height)
    local filters = {}

    if state_value.backend == "rife" then
        filters[#filters + 1] = string.format(
            "vapoursynth=file=~~/vs/rife.vpy:user-data=%d-%s:buffered-frames=8:concurrent-frames=12",
            state_value.multiplier,
            quality_modes.rife[state_value.quality].id
        )
    elseif state_value.backend == "vfg" then
        filters[#filters + 1] = string.format(
            "nvidia-vfg=mode=%s:multiplier=%d",
            quality_modes.vfg[state_value.quality].id,
            state_value.multiplier
        )
    end

    if state_value.sr_enabled or state_value.hdr_enabled then
        local vpp = string.format(
            "d3d11vpp=scale=%s:scaling-mode=%s:nvidia-true-hdr=%s",
            format_scale(state_value.sr_enabled and sr_scale(state_value, width, height) or 1),
            state_value.sr_enabled and "nvidia" or "standard",
            state_value.hdr_enabled and "yes" or "no"
        )
        table.insert(filters, vpp_before_vfg(state_value) and 1 or #filters + 1, vpp)
    end

    return table.concat(filters, ",")
end

local function apply_filter_chain(state_value, width, height)
    local filter_chain = build_filter_chain(effective_state(state_value), width, height)
    if filter_chain ~= last_applied_filter_chain then
        local ok, err = mp.commandv("vf", "set", filter_chain)
        if not ok then
            msg.error(tr("Не удалось изменить фильтры RTX Video: ", "Could not update RTX Video filters: ") .. tostring(err))
            mp.osd_message(tr("Не удалось изменить фильтры RTX Video", "Could not update RTX Video filters"), 4)
            return false
        end
        last_applied_filter_chain = filter_chain
        return true, true
    end
    return true, false
end

local function describe_generation(state_value)
    local backend = state_value.backend
    if backend == "off" then
        return tr("Генерация выкл.", "Frame generation off")
    end
    local mode = quality_modes[backend][state_value.quality]
    return string.format("%s %d× (%s)", backend:upper(), state_value.multiplier,
                         mode.button_label or quality_label(mode))
end

local function describe_state(state_value)
    state_value = effective_state(state_value)
    local sr_text

    if state_value.sr_enabled then
        local target = get_target(state_value)
        local label = tr(target.label, target.english or target.label)
        if target.id == "display" and limit_auto_sr(state_value) then
            label = label .. tr(" до 1080p", " up to 1080p")
        end
        local scale = sr_scale(state_value, source_dimensions())
        if scale <= 1 then
            sr_text = string.format(tr("Чёткость (%s), без увеличения", "Super resolution (%s), original size"), label)
        else
            sr_text = string.format(tr("Чёткость (%s, ×%s)", "Super resolution (%s, ×%s)"), label, format_scale(scale))
        end
    else
        sr_text = tr("Чёткость выкл.", "Super resolution off")
    end

    local hdr_text = state_value.hdr_enabled and tr("RTX Video HDR вкл.", "RTX Video HDR on") or tr("RTX Video HDR выкл.", "RTX Video HDR off")
    return table.concat({describe_generation(state_value), sr_text, hdr_text}, "  |  ")
end

local function update_sr_button(width, height)
    local label = "RTX SR"
    if not state.sr_enabled then
        label = tr("SR выкл.", "SR off")
    elseif width and format_scale(sr_scale(effective_state(state), width, height)) == "1" then
        label = "SR 1:1"
    end
    mp.commandv("script-message-to", "osc", "osc-custom-button", "4", label)
end
local function apply(next_state, show_status)
    local width, height = source_dimensions()
    if width then
        local position
        if (show_status or next_state.auto) and mp.get_property_bool("seekable") and not mp.get_property_bool("pause") then
            position = mp.get_property_number("time-pos")
        end
        local ok, changed = apply_filter_chain(next_state, width, height)
        if not ok then
            return false
        end
        -- mpv refreshes paused video itself. While playing, an exact seek
        -- discards old queued frames and re-syncs audio at the same position.
        if changed and position then
            mp.commandv("no-osd", "seek", position, "absolute+exact")
        end
    end

    local generation_changed = state.backend ~= next_state.backend
        or state.quality ~= next_state.quality or state.multiplier ~= next_state.multiplier
    state = next_state
    update_sr_button(width, height)
    if generation_changed then
        local profile = profiles[state.backend]
        if profile then
            profile.multiplier = state.multiplier
            profile.quality = state.quality
        end
    end
    if generation_changed or state.auto or show_status then update_buttons() end
    if show_status then
        queue_settings_save()
        local suffix = width and "" or tr(" (применится к видео)", " (applies when a video opens)")
        mp.osd_message(describe_state(state) .. suffix, 4)
    end
    return true
end

local function set_backend(backend)
    if not backend or backend == state.backend then return end
    local next_state = copy_state()
    local profile = profiles[backend]
    next_state.backend = backend
    if backend == "off" then next_state.auto = false end
    next_state.multiplier = profile and profile.multiplier or 0
    next_state.quality = profile and profile.quality or 1
    apply(next_state, true)
end

local function show_backend_menu()
    local backends = {"off", "vfg", "rife"}
    local selected = state.backend == "off" and 1 or state.backend == "vfg" and 2 or 3
    select_popup(1, {
        prompt = tr("Генератор кадров", "Frame generator"),
        items = {tr("Выкл.", "Off"), "VFG", "RIFE"},
        default_item = selected,
        submit = function(index) set_backend(backends[index]) end,
    })
end

local function set_multiplier(multiplier)
    if multiplier == 0 then
        set_backend("off")
    elseif profiles[state.backend] then
        local next_state = copy_state()
        next_state.auto = false
        next_state.multiplier = multiplier
        apply(next_state, true)
    end
end

local function enable_auto()
    if state.auto then return end
    local next_state = copy_state()
    next_state.auto = true
    if next_state.auto and next_state.backend == "off" then
        next_state.backend = "rife"
        next_state.multiplier = profiles.rife.multiplier
        next_state.quality = profiles.rife.quality
    end
    apply(next_state, true)
end

local function show_multiplier_menu()
    if state.backend == "off" then return show_backend_menu() end
    local items = {}
    for index in ipairs(multipliers) do items[index] = multiplier_label(index) end
    local auto_index = #items + 1
    items[auto_index] = tr("Авто", "Auto")
    select_popup(2, {
        prompt = tr("Множитель ", "Multiplier · ") .. state.backend:upper(),
        items = items,
        default_item = state.auto and auto_index or multiplier_indices[state.multiplier],
        submit = function(index)
            if index == auto_index then
                enable_auto()
            elseif multipliers[index] ~= nil then
                set_multiplier(multipliers[index])
            end
        end,
    })
end

local function set_vfg_quality(quality)
    if not quality then return end
    if state.backend == "off" or quality == state.quality then
        return
    end
    local next_state = copy_state()
    next_state.quality = quality
    apply(next_state, true)
end

local function show_vfg_quality_menu()
    if state.backend == "off" then return show_backend_menu() end
    local modes = quality_modes[state.backend]
    local items = {}
    for index, mode in ipairs(modes) do
        items[index] = quality_label(mode)
    end
    select_popup(3, {
        prompt = state.backend == "rife" and tr("Модель RIFE", "RIFE model")
            or tr("Качество VFG", "VFG quality"),
        items = items,
        default_item = state.quality,
        submit = set_vfg_quality,
    })
end

local function cycle_vfg_quality(direction)
    if state.backend == "off" then return show_backend_menu() end
    set_vfg_quality(((state.quality - 1 + direction) % #quality_modes[state.backend]) + 1)
end

local function toggle_sr()
    local next_state = copy_state()
    next_state.sr_enabled = not state.sr_enabled
    apply(next_state, true)
end

local function set_target(index)
    if not targets[index] then return end
    local next_state = copy_state()
    next_state.sr_target = targets[index].id
    next_state.sr_enabled = true
    apply(next_state, true)
end

local function target_index()
    for index, target in ipairs(targets) do
        if target.id == state.sr_target then return index end
    end
    return 1
end

local function show_target_menu()
    local items = {}
    for index, target in ipairs(targets) do
        items[index] = target.id == "display" and tr("Экран", "Display") or target.label
    end
    select_popup(5, {
        prompt = tr("Разрешение RTX SR", "RTX SR resolution"),
        items = items,
        default_item = target_index(),
        submit = set_target,
    })
end

local function change_target(direction)
    set_target((target_index() - 1 + direction) % #targets + 1)
end

local function toggle_hdr()
    local next_state = copy_state()
    next_state.hdr_enabled = not state.hdr_enabled
    apply(next_state, true)
end

local function property_text(name, format)
    local value = mp.get_property_number(name)
    if value == nil then
        return tr("н/д", "n/a")
    end
    return string.format(format, value)
end

local function fps_value(value)
    if not value or value <= 0 then
        return "—"
    end
    return string.format("%.0f", value)
end

local function show_fps_status()
    local avsync = mp.get_property_number("avsync")
    local avsync_text = avsync and string.format(tr("%+.0f мс", "%+.0f ms"), avsync * 1000) or tr("н/д", "n/a")
    local message = string.format(
        tr("%s\nСдвиг звука %s\nИсточник %s кадр/с → после фильтров ≈ %s кадр/с\nЭкран %s Гц  |  пропущено кадров %s", "%s\nA/V offset %s\nSource %s fps → filtered ≈ %s fps\nDisplay %s Hz  |  dropped frames %s"),
        describe_generation(effective_state(state)),
        avsync_text,
        fps_value(source_fps()),
        property_text("estimated-vf-fps", "%.0f"),
        property_text("display-fps", "%.0f"),
        property_text("frame-drop-count", "%.0f")
    )
    mp.osd_message(message, 6)
end

mp.register_script_message("rtx-video-controls", function(action)
    local multiplier = tonumber((action or ""):match("^vfg%-(%d+)$"))
    if action == "language-toggle" then
        local language = locale.current() == "ru" and "en" or "ru"
        if not locale.set(language) then
            mp.osd_message(tr("Не удалось сохранить язык", "Could not save language"), 3)
            return
        end
        update_buttons()
        update_sr_button(source_dimensions())
        mp.osd_message(tr("Русский · перезапустите для смены языка меню ☰",
                          "English · restart to switch the ☰ menu"), 4)
    elseif action == "generator-menu" then
        show_backend_menu()
    elseif action == "generator-vfg" then
        set_backend("vfg")
    elseif action == "generator-rife" then
        set_backend("rife")
    elseif action == "generator-off" or action == "vfg-off" then
        set_backend("off")
    elseif action == "vfg-multiplier-menu" then
        show_multiplier_menu()
    elseif multiplier and multiplier_indices[multiplier] then
        set_multiplier(multiplier)
    elseif action == "vfg-quality-menu" then
        show_vfg_quality_menu()
    elseif action == "vfg-quality-next" then
        cycle_vfg_quality(1)
    elseif action == "vfg-quality-previous" then
        cycle_vfg_quality(-1)
    elseif action == "sr-menu" then
        show_target_menu()
    elseif action == "sr-toggle" then
        toggle_sr()
    elseif action == "sr-next" then
        change_target(1)
    elseif action == "sr-previous" then
        change_target(-1)
    elseif action == "hdr-toggle" then
        toggle_hdr()
    elseif action == "fps-status" then
        show_fps_status()
    end
end)

mp.add_hook("on_loaded", 50, function()
    last_applied_filter_chain = nil
    -- Use demux metadata before the decoder and video output are initialized.
    local width, height = initial_dimensions()
    apply_filter_chain(state, width, height)
    update_sr_button(width, height)
    update_buttons()
end)

mp.add_hook("on_unload", 50, save_settings)
mp.register_event("shutdown", save_settings)

local reconfigure_timer
local function schedule_reconfigure()
    if reconfigure_timer then
        return
    end
    reconfigure_timer = mp.add_timeout(0.1, function()
        reconfigure_timer = nil
        apply(copy_state(), false)
    end)
end

mp.register_event("file-loaded", schedule_reconfigure)
mp.observe_property("display-fps", "number", schedule_reconfigure)
mp.observe_property("container-fps", "number", schedule_reconfigure)
mp.observe_property("video-params/fps", "number", schedule_reconfigure)
mp.observe_property("display-width", "number", schedule_reconfigure)
mp.observe_property("display-height", "number", schedule_reconfigure)
mp.observe_property("video-params/w", "number", schedule_reconfigure)
mp.observe_property("video-params/h", "number", schedule_reconfigure)
mp.observe_property("video-params/dw", "number", schedule_reconfigure)
mp.observe_property("video-params/dh", "number", schedule_reconfigure)

mp.set_property_native(locale.property, locale.saved())
load_settings()
restore_player_options()
update_buttons()
update_sr_button(source_dimensions())
