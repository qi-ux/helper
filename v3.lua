_DEBUG = true
ui.sidebar("Helper v3", "code")

--
-- dependencies
--

local json = require "neverlose/better_json"
local clipboard = require "neverlose/clipboard"
local http = require "neverlose/http"
local weapons = require "neverlose/csgo_weapons"
local easing = require "neverlose/easing"
local pretty_json = require "neverlose/pretty_json"
local images = require "neverlose/images"
local table_gen = require "neverlose/table_gen"

local database = db
local table_clear = require "table.clear"

--
-- debug mode
--

local DEBUG
if _DEBUG then
    DEBUG = {
        inspect = require "neverlose/inspect"
    }

    local large_font = render.load_font("Segoe UI", 35, "abd")
    events.render:set(
        function()
            if large_font and DEBUG.debug_text ~= nil then
                render.text(large_font, vector() + 150, color(), "s", DEBUG.debug_text)
            end
        end
    )
end

--
-- constants
--

local SOURCE_TYPE_NAMES = {
    ["remote"] = "Remote",
    ["local"] = "Local",
    ["local_file"] = "Local file"
}

local LOCATION_TYPE_NAMES = {
    grenade = "Grenade",
    wallbang = "Wallbang",
    movement = "Movement"
}

local YAW_DIRECTION_OFFSETS = {
    Forward = 0,
    Back = 180,
    Left = 90,
    Right = -90
}

local MOVEMENT_BUTTONS_CHARS = {
    ["in_attack"] = "A",
    ["in_jump"] = "J",
    ["in_duck"] = "D",
    ["in_forward"] = "F",
    ["in_moveleft"] = "L",
    ["in_moveright"] = "R",
    ["in_back"] = "B",
    ["in_use"] = "U",
    ["in_attack2"] = "Z",
    ["in_speed"] = "S"
}

local GRENADE_WEAPON_NAMES =
    setmetatable(
    {
        [weapons.weapon_smokegrenade] = "Smoke",
        [weapons.weapon_flashbang] = "Flashbang",
        [weapons.weapon_hegrenade] = "HE",
        [weapons.weapon_molotov] = "Molotov"
    },
    {
        __index = function(tbl, key)
            if type(key) == "table" and key.name then
                tbl[key] = key.name
                return tbl[key]
            end
        end
    }
)

local GRENADE_WEAPON_NAMES_UI =
    setmetatable(
    {
        [weapons.weapon_smokegrenade] = "Smoke",
        [weapons.weapon_flashbang] = "Flashbang",
        [weapons.weapon_hegrenade] = "High Explosive",
        [weapons.weapon_molotov] = "Molotov"
    },
    {
        __index = GRENADE_WEAPON_NAMES
    }
)

local WEAPON_ICONS =
    setmetatable(
    {},
    {
        __index = function(tbl, key)
            if key == nil then
                return
            end

            tbl[key] = images.get_weapon_icon(key)
            return tbl[key]
        end
    }
)

local WEPAON_ICONS_OFFSETS =
    setmetatable(
    {
        [WEAPON_ICONS["weapon_smokegrenade"]] = {0.2, -0.1, 0.35, 0},
        [WEAPON_ICONS["weapon_hegrenade"]] = {0.1, -0.12, 0.2, 0},
        [WEAPON_ICONS["weapon_molotov"]] = {0, -0.04, 0, 0}
    },
    {
        __index = function(tbl, key)
            tbl[key] = {0, 0, 0, 0}
            return tbl[key]
        end
    }
)

local WEAPON_ALIASES = {
    [weapons["weapon_incgrenade"]] = weapons["weapon_molotov"],
    [weapons["weapon_firebomb"]] = weapons["weapon_molotov"],
    [weapons["weapon_frag_grenade"]] = weapons["weapon_hegrenade"]
}
for _, weapon in pairs(weapons) do
    if weapon.type == "knife" then
        WEAPON_ALIASES[weapon] = weapons["weapon_knife"]
    end
end

local vector_index_i, vector_index_lookup = 1, {}
local VECTOR_INDEX =
    setmetatable(
    {},
    {
        __index = function(self, key)
            local id = string.format("%.2f %.2f %.2f", key:unpack())
            local index = vector_index_lookup[id]

            -- first time we met this location
            if index == nil then
                index = vector_index_i
                vector_index_lookup[id] = index
                vector_index_i = index + 1
            end

            self[key] = index
            return index
        end,
        __mode = "k"
    }
)

local DEFAULTS = {
    visibility_offset = vector(0, 0, 24),
    fov = 0.7,
    fov_movement = 0.1,
    select_fov_legit = 8,
    select_fov_rage = 25,
    max_dist = 6,
    destroy_text = "Break the object",
    source_ttl = 5
}

local MAX_DIST_ICON = _DEBUG and 3000 or 1500
local MAX_DIST_ICON_SQR = MAX_DIST_ICON * MAX_DIST_ICON
local MAX_DIST_COMBINE_SQR = 20 * 20
local MAX_DIST_TEXT = _DEBUG and 1300 or 650
local MAX_DIST_CLOSE = _DEBUG and 56 or 28
local MAX_DIST_CLOSE_DRAW = _DEBUG and 30 or 15
local MAX_DIST_CORRECT = 0.1
local POSITION_WORLD_OFFSET = vector(0, 0, 8)
local POSITION_WORLD_TOP_SIZE = 6
local NULL_VECTOR = vector()
local FL_ONGROUND = 1
local GRENADE_PLAYBACK_PREPARE, GRENADE_PLAYBACK_RUN, GRENADE_PLAYBACK_THROW, GRENADE_PLAYBACK_THROWN, GRENADE_PLAYBACK_FINISHED = 1, 2, 3, 4, 5

-- local CLR_CIRCLE_GREEN = {20, 236, 0}
-- local CLR_CIRCLE_RED = {255, 10, 10}
-- local CLR_CIRCLE_WHITE = {140, 140, 140}
local CLR_TEXT_EDIT = color(255, 16, 16)

local approach_accurate_Z_OFFSET = 20
local approach_accurate_PLAYER_RADIUS = 16
local approach_accurate_OFFSETS_START = {
    vector(approach_accurate_PLAYER_RADIUS * 0.7, 0, approach_accurate_Z_OFFSET),
    vector(-approach_accurate_PLAYER_RADIUS * 0.7, 0, approach_accurate_Z_OFFSET),
    vector(0, approach_accurate_PLAYER_RADIUS * 0.7, approach_accurate_Z_OFFSET),
    vector(0, -approach_accurate_PLAYER_RADIUS * 0.7, approach_accurate_Z_OFFSET)
}
local approach_accurate_OFFSETS_END = {
    vector(approach_accurate_PLAYER_RADIUS * 2),
    vector(0, approach_accurate_PLAYER_RADIUS * 2),
    vector(-approach_accurate_PLAYER_RADIUS * 2),
    vector(0, -approach_accurate_PLAYER_RADIUS * 2)
}
-- local POSITION_INACCURATE_OFFSETS = {
--     vector(),
--     vector(8),
--     vector(-8),
--     vector(0, 8),
--     vector(0, -8)
-- }

--
-- debug
--

local benchmark = {
    start_times = {},
    measure = function(name, callback, ...)
        if not DEBUG then
            return
        end

        local start = common.get_timestamp()
        local values = {callback(...)}
        print(string.format("%s took %fms", name, common.get_timestamp() - start))

        return unpack(values)
    end,
    start = function(self, name)
        if not DEBUG then
            return
        end

        if self.start_times[name] ~= nil then
            print_raw("\a4B69FF[neverlose]\aFF4040\x20benchmark: " .. name .. " wasn't finished before starting again")
        end
        self.start_times[name] = common.get_timestamp()
    end,
    finish = function(self, name)
        if not DEBUG then
            return
        end

        if self.start_times[name] == nil then
            return
        end

        print(string.format("%s took %fms", name, common.get_timestamp() - self.start_times[name]))
        self.start_times[name] = nil
    end
}

--
-- builtin assets
--

local CUSTOM_ICONS = {}

-- bhop icon
CUSTOM_ICONS.bhop =
    images.load_svg [[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 158 200" height="200mm" width="158mm"><path d="M27.693 195.583c-2.003-2.003-2.363-5.637-1.252-12.65.516-3.26.938-6.157.938-6.438 0-.28-1.054-.689-2.343-.907-1.29-.218-2.344-.467-2.344-.555 0-.087.895-2.107 1.988-4.489 4.178-9.102 7.387-22.167 7.387-30.08v-3.571l-3.44-.654c-7.509-1.427-14.81-6.385-17.132-11.635-.617-1.395-1.665-5.26-2.33-8.587-.893-4.483-1.742-6.934-3.273-9.457-2.296-3.785-2.316-5.113-.15-10.165.632-1.476 2.428-7.86 3.99-14.185 2.365-9.578 3.487-12.902 6.715-19.887 5.154-11.15 5.358-11.988 3.937-16.119-1.318-3.831-1.056-5.345 1.698-9.821.989-1.608 2.12-4.13 2.515-5.604.687-2.569.636-2.83-1.246-6.276-1.64-3.006-2.044-4.51-2.462-9.162-.274-3.062-.508-6.885-.52-8.497l-.02-2.93 9.333.832 9.334.832.416 4.435c.229 2.44.232 9.482.008 15.65l-.407 11.213 3.401.388c1.871.213 4.456.53 5.745.701l2.344.314.02-4.585c.015-3.63.3-5.12 1.371-7.156 3.088-5.87 9.893-10.612 17.04-11.87 2.72-.48 4.16-.41 7.136.344 8.67 2.198 13.982 9.621 13.982 19.536 0 3.495-.14 3.9-1.992 5.752-1.244 1.244-2.564 1.993-3.515 1.993-1.498 0-1.524.07-1.524 4.154V50.6l8.936-.238c5.285-.14 11.17-.674 14.408-1.308l5.474-1.072-.383-2.552c-.371-2.477-.336-2.552 1.2-2.552.87 0 1.91-.45 2.312-.997.683-.935 1.274-.91 9.439.387 4.867.774 12.329 1.487 16.913 1.617 4.511.127 8.931.513 9.821.858 2.243.868 2.71 3.071 1.032 4.858-2.363 2.515-4.225 2.914-9.654 2.07-6.496-1.011-9.485-.609-12.891 1.735-1.52 1.045-3.782 2.037-5.027 2.204-2.128.286-2.245.405-1.932 1.967.544 2.721-.247 4.49-3.682 8.225-3.771 4.102-4.631 5.891-5.494 11.424-.95 6.089-1.574 7.525-5.323 12.242-5.485 6.903-11.865 11.373-16.271 11.402-2.966.02-5.442-1.427-10.646-6.22-6.093-5.61-11.51-9.587-13.06-9.587-.744 0-2.728 1.564-5.069 3.995-2.116 2.197-4.28 4.24-4.81 4.54-.873.497-.887.972-.155 5.165.443 2.54 1.213 5.24 1.71 5.998 1.235 1.884 4.465 3.43 10.25 4.908 11.895 3.037 24.228 12.17 28.7 21.256 3.277 6.657 3.757 14.905 1.066 18.326-2.005 2.549-4.717 3.3-13.73 3.8-12.025.666-11.433.3-25.192 15.601-3.54 3.936-4.947 5.026-9.098 7.036-6.03 2.92-8.128 5.182-9.759 10.524-1.407 4.607-3.89 7.936-7.163 9.606-3.066 1.565-5.55 1.484-7.27-.236zM99.119 71.202c3.73-4.725 6.662-8.708 6.518-8.853-.145-.144-2.778 1.572-5.852 3.814-4.389 3.2-6.566 4.363-10.14 5.413-2.504.735-4.685 1.46-4.846 1.61-.317.296 6.477 6.567 7.14 6.59.22.009 3.451-3.85 7.18-8.574z" fill="#fff"/></svg>]]

--
-- utility functions
--

local function deep_flatten(tbl, ignore_arr, out, prefix)
    if out == nil then
        out = {}
        prefix = ""
    end

    for key, value in pairs(tbl) do
        if type(value) == "table" and (not ignore_arr or #value == 0) then
            deep_flatten(value, ignore_arr, out, prefix .. key .. ".")
        else
            out[prefix .. key] = value
        end
    end

    return out
end

local function deep_compare(tbl1, tbl2)
    if tbl1 == tbl2 then
        return true
    elseif type(tbl1) == "table" and type(tbl2) == "table" then
        for key1, value1 in pairs(tbl1) do
            local value2 = tbl2[key1]

            if value2 == nil then
                -- avoid the type call for missing keys in tbl2 by directly comparing with nil
                return false
            elseif value1 ~= value2 then
                if type(value1) == "table" and type(value2) == "table" then
                    if not deep_compare(value1, value2) then
                        return false
                    end
                else
                    return false
                end
            end
        end

        -- check for missing keys in tbl1
        for key2, _ in pairs(tbl2) do
            if tbl1[key2] == nil then
                return false
            end
        end

        return true
    end

    return false
end

local function vector2_rotate(position, angle)
    local sin = math.sin(angle)
    local cos = math.cos(angle)

    return vector(position.x * cos - position.y * sin, position.x * sin + position.y * cos)
end

local function triangle_rotated(position, size, angle, color)
    position = vector2_rotate(-size / 2, angle) + position
    render.poly(color, position + vector2_rotate(vector(size.x / 2, 0), angle), position + vector2_rotate(vector(0, size.y), angle), position + vector2_rotate(size, angle))
end

local function randomid(size)
    local str = ""
    for _ = 1, (size or 32) do
        str = str .. string.char(utils.random_int(97, 122))
    end
    return str
end

local crc32_lt = {}
local function crc32(s, lt)
    -- return crc32 checksum of string as an integer
    -- use lookup table lt if provided or create one on the fly
    -- if lt is empty, it is initialized.
    lt = lt or crc32_lt
    local b, crc, mask
    if not lt[1] then -- setup table
        for i = 1, 256 do
            crc = i - 1
            for _ = 1, 8 do --eight times
                mask = -bit.band(crc, 1)
                crc = bit.bxor(bit.rshift(crc, 1), bit.band(0xedb88320, mask))
            end
            lt[i] = crc
        end
    end

    -- compute the crc
    crc = 0xffffffff
    for i = 1, #s do
        b = string.byte(s, i)
        crc = bit.bxor(bit.rshift(crc, 8), lt[bit.band(bit.bxor(crc, b), 0xFF) + 1])
    end
    return bit.band(bit.bnot(crc), 0xffffffff)
end

local function table_map(tbl, callback)
    local new = {}
    for key, value in pairs(tbl) do
        new[key] = callback(value)
    end
    return new
end

local function table_map_assoc(tbl, callback)
    local new = {}
    for key, value in pairs(tbl) do
        local new_key, new_value = callback(key, value)
        new[new_key] = new_value
    end
    return new
end

local function format_duration(secs, ignore_seconds, max_parts)
    local units, dur, part = {"day", "hour", "minute"}, "", 1
    max_parts = max_parts or 4

    for i, v in ipairs({86400, 3600, 60}) do
        if part > max_parts then
            break
        end

        if secs >= v then
            dur = dur .. math.floor(secs / v) .. " " .. units[i] .. (math.floor(secs / v) > 1 and "s" or "") .. ", "
            secs = secs % v
            part = part + 1
        end
    end

    if secs == 0 or ignore_seconds or part > max_parts then
        return dur:sub(1, -3)
    else
        secs = math.floor(secs)
        return dur .. secs .. (secs > 1 and " seconds" or " second")
    end
end

local function is_grenade_being_thrown(weapon, cmd)
    if weapon ~= nil then
        local pin_pulled = weapon["m_bPinPulled"]
        if pin_pulled == false or cmd.in_attack or cmd.in_attack2 then
            local throw_time = weapon["m_fThrowTime"]
            if throw_time > 0 and throw_time < globals.curtime + 1 then
                return true
            end
        end
    end
    return false
end

local function trace_line_skip(begin, endl, max)
    max = max or 10
    local fraction, ent_hit = 0, nil
    local hit = begin

    local i = 0
    while max >= i and fraction < 1 and (ent_hit ~= nil or i == 0) do
        local trace = utils.trace_line(hit, endl, ent_hit)
        fraction, ent_hit = trace.fraction, trace.hit_entity

        hit = hit:lerp(endl, fraction)
        i = i + 1
    end

    fraction = begin:dist(hit) / begin:dist(endl)
    return fraction, ent_hit, hit
end

local MOVEMENT_BUTTONS_CHARS_INV =
    table_map_assoc(
    MOVEMENT_BUTTONS_CHARS,
    function(k, v)
        return v, k
    end
)

local format_timestamp =
    setmetatable(
    {},
    {
        __index = function(tbl, ts)
            tbl[ts] = common.get_date("%m/%d/%Y %H:%M", ts)
            return tbl[ts]
        end
    }
)

local function format_unix_timestamp(timestamp, allow_future, ignore_seconds, max_parts)
    local secs = timestamp - common.get_unixtime()

    if secs < 0 or allow_future then
        local duration = format_duration(math.abs(secs), ignore_seconds, max_parts)
        return secs > 0 and ("In " .. duration) or (duration .. " ago")
    else
        return format_timestamp[timestamp]
    end
end

local function calculate_move(btn1, btn2)
    return btn1 and 450 or (btn2 and -450 or 0)
end

local function compress_usercmds(usercmds)
    local frames = {}

    local current = {
        viewangles = {pitch = usercmds[1].pitch, yaw = usercmds[1].yaw},
        buttons = {}
    }

    for key, _ in pairs(MOVEMENT_BUTTONS_CHARS) do
        current.buttons[key] = false
    end

    local empty_count = 0
    for i, cmd in ipairs(usercmds) do
        local buttons = ""

        for btn, value_prev in pairs(current.buttons) do
            if cmd[btn] and not value_prev then
                buttons = buttons .. MOVEMENT_BUTTONS_CHARS[btn]
            elseif not cmd[btn] and value_prev then
                buttons = buttons .. MOVEMENT_BUTTONS_CHARS[btn]:lower()
            end
            current.buttons[btn] = cmd[btn]
        end

        local frame = {cmd.pitch - current.viewangles.pitch, cmd.yaw - current.viewangles.yaw, buttons, cmd.forwardmove, cmd.sidemove}
        current.viewangles = {pitch = cmd.pitch, yaw = cmd.yaw}

        if frame[#frame] == calculate_move(cmd.in_moveright, cmd.in_moveleft) then
            frame[#frame] = nil

            if frame[#frame] == calculate_move(cmd.in_forward, cmd.in_back) then
                frame[#frame] = nil

                if frame[#frame] == "" then
                    frame[#frame] = nil

                    if frame[#frame] == 0 then
                        frame[#frame] = nil

                        if frame[#frame] == 0 then
                            frame[#frame] = nil
                        end
                    end
                end
            end
        end

        if #frame > 0 then
            if empty_count > 0 then
                table.insert(frames, empty_count)
                empty_count = 0
            end

            table.insert(frames, frame)
        else
            empty_count = empty_count + 1
        end
    end

    if empty_count > 0 then
        table.insert(frames, empty_count)
        empty_count = 0
    end

    return frames
end

local function get_map_pattern()
    local ent = entity.get(0)
    if ent == nil then
        return
    end

    local mins = ent["m_WorldMins"]
    local maxs = ent["m_WorldMaxs"]

    if mins ~= NULL_VECTOR or maxs ~= NULL_VECTOR then
        return crc32(("bomb_%.2f_%.2f_%.2f %.2f_%.2f_%.2f"):format(mins.x, mins.y, mins.z, maxs.x, maxs.y, maxs.z))
    end
end

local MAP_PATTERNS = {
    [-2011174878] = "de_train",
    [-1890957714] = "ar_shoots",
    [-1768287648] = "dz_blacksite",
    [-1752602089] = "de_inferno",
    [-1639993233] = "de_mirage",
    [-1621571143] = "de_dust",
    [-1541779215] = "de_sugarcane",
    [-1439577949] = "de_canals",
    [-1411074561] = "de_tulip",
    [-1348292803] = "cs_apollo",
    [-1218081885] = "de_guard",
    [-923663825] = "dz_frostbite",
    [-768791216] = "de_dust2",
    [-692592072] = "cs_italy",
    [-542128589] = "ar_monastery",
    [-222265935] = "ar_baggage",
    [-182586077] = "de_aztec",
    [371013699] = "de_stmarc",
    [405708653] = "de_overpass",
    [549370830] = "de_lake",
    [790893427] = "dz_sirocco",
    [792319475] = "de_ancient",
    [878725495] = "de_bank",
    [899765791] = "de_safehouse",
    [1014664118] = "cs_office",
    [1238495690] = "ar_dizzy",
    [1364328969] = "cs_militia",
    [1445192006] = "de_engage",
    [1463756432] = "cs_assault",
    [1476824995] = "de_vertigo",
    [1507960924] = "cs_agency",
    [1563115098] = "de_nuke",
    [1722587796] = "de_dust2_old",
    [1850283081] = "de_anubis",
    [1900771637] = "de_cache",
    [1964982021] = "de_elysion",
    [2041417734] = "de_cbble",
    [2056138930] = "gd_rialto"
}

local MAP_LOOKUP = {
    de_shortnuke = "de_nuke",
    de_shortdust = "de_shortnuke"
}

local mapname_cache = {}
local function get_mapname()
    local map_data = common.get_map_data()
    if map_data == nil then
        return
    end

    local mapname_raw = map_data["shortname"]
    if mapname_cache[mapname_raw] == nil then
        local mapname = mapname_raw:gsub("_scrimmagemap$", "")

        if MAP_LOOKUP[mapname] ~= nil then
            mapname = MAP_LOOKUP[mapname]
        else
            local is_first_party_map = false
            for _, value in pairs(MAP_PATTERNS) do
                if value == mapname then
                    is_first_party_map = true
                    break
                end
            end

            if not is_first_party_map then
                local pattern = get_map_pattern()

                if MAP_PATTERNS[pattern] ~= nil then
                    mapname = MAP_PATTERNS[pattern]
                end
            end
        end

        mapname_cache[mapname_raw] = mapname
    end

    return mapname_cache[mapname_raw]
end

ui.create("Main")
ui.create("Manage", "A")
ui.create("Manage", "B")
if DEBUG then
    ui.create("Manage", "A"):label("DEBUG"):create():button(
        "Create helper map patterns",
        function()
            local maps = {
                "de_cache",
                "de_mirage",
                "de_dust2",
                "de_inferno",
                "de_overpass",
                "de_canals",
                "de_train",
                "cs_office",
                "cs_agency",
                "de_vertigo",
                "de_lake",
                "de_nuke",
                "de_safehouse",
                "dz_blacksite",
                "cs_assault",
                "ar_monastery",
                "de_cbble",
                "cs_italy",
                "cs_militia",
                "de_stmarc",
                "ar_baggage",
                "ar_shoots",
                "de_sugarcane",
                "ar_dizzy",
                "de_dust",
                "de_bank",
                -- popular removed maps (old / operation)
                "de_tulip",
                "de_aztec",
                "gd_rialto",
                "de_dust2_old",
                -- shattered web or after
                "dz_sirocco",
                "de_anubis",
                -- operation broken fang maps
                "cs_apollo",
                "de_ancient",
                "de_elysion",
                "de_engage",
                "dz_frostbite",
                "de_guard"
            }

            MAP_PATTERNS = {}

            DEBUG.create_map_patterns_count = #maps
            DEBUG.create_map_patterns_next = {}
            DEBUG.create_map_patterns_index = {}
            DEBUG.create_map_patterns_failed = {}
            for i = 1, #maps do
                local map = maps[i]
                if DEBUG.create_map_patterns_next[map] ~= nil then
                    error("Duplicate map " .. map)
                end
                DEBUG.create_map_patterns_next[map] = maps[i + 1]
                DEBUG.create_map_patterns_index[map] = i
            end

            -- print_raw(DEBUG.inspect(DEBUG.create_map_patterns_next))

            DEBUG.create_map_patterns = true
            DEBUG.debug_text = "create_map_patterns progress: " .. 1 .. " / " .. DEBUG.create_map_patterns_count
            utils.execute_after(0.5, utils.console_exec, "map " .. maps[1])
        end,
        true
    )
end

--
-- database initialization
--

benchmark:start("db_read")
local db = database["helper"] or {}
db.sources = db.sources or {}
benchmark:finish("db_read")

-- setup default sources
local default_sources = {
    {
        name = "Built-in (Legit)",
        id = "builtin_legit",
        type = "remote",
        url = "https://raw.githubusercontent.com/sapphyrus/helper/master/locations/builtin_legit.json",
        description = "Built-in legit grenades",
        builtin = true
    },
    {
        name = "Built-in (HvH)",
        id = "builtin_hvh",
        type = "remote",
        url = "https://raw.githubusercontent.com/sapphyrus/helper/master/locations/builtin_hvh.json",
        description = "HvH mollys, nades and oneways",
        builtin = true
    },
    -- {
    --     name = "SoThatWeMayBeFree",
    --     id = "builtin_sothatwemaybefree",
    --     type = "remote",
    --     url = "https://raw.githubusercontent.com/sapphyrus/helper/master/locations/sothatwemaybefree.json",
    --     description = "Grenades from sothatwemaybefree",
    --     builtin = true
    -- },
    {
        name = "Built-in (Movement)",
        id = "builtin_movement",
        type = "remote",
        url = "https://raw.githubusercontent.com/sapphyrus/helper/master/locations/builtin_movement.json",
        description = "Movement locations for popular maps",
        builtin = true
    }
    -- {
    --     name = "sigma's HvH locations",
    --     id = "sigma_hvh",
    --     type = "remote",
    --     url = "https://pastebin.com/raw/ewHvQ2tD",
    --     description = "Revolutionizing spread HvH",
    --     builtin = true
    -- }
}

-- first remove all default sources and some old ones
local removed_sources = {
    builtin_local_file = true,
    builtin_hvh = true
}

-- add default sources to remove list
for i = 1, #default_sources do
    removed_sources[default_sources[i].id] = true
end

-- remove sources
for i = #db.sources, 1, -1 do
    local source = db.sources[i]

    if source ~= nil and removed_sources[source.id] then
        table.remove(db.sources, i)
    end
end

-- re-add default sources in correct order
for i = 1, #default_sources do
    if db.sources[i] == nil or db.sources[i].id ~= default_sources[i].id then
        table.insert(db.sources, i, default_sources[i])
    end
end

if DEBUG and files.read("nl\\helper_data.json") then
    table.insert(
        db.sources,
        {
            name = "helper_data.json",
            id = "builtin_local_file",
            type = "local_file",
            filename = "helper_data.json",
            description = "Local file for testing",
            builtin = true
        }
    )

    local store_db = (database["helper_store"] or {})
    store_db.locations = store_db.locations or {}
    store_db.locations["builtin_local_file"] = {}
end

-- table of: source -> map name -> locations
local sources_locations = {}

-- forward declare the ui update func
local update_sources_ui, edit_set_ui_values

-- forward declare runtime map locations
local map_locations, active_locations = {}, nil

local function flush_active_locations(reason)
    active_locations = nil
    table_clear(map_locations)
    -- print_raw("flush_active_locations(", reason, ")")
end

local tickrates_mt = {
    __index = function(tbl, key)
        if tbl.tickrate ~= nil then
            return key / tbl.tickrate
        end
    end
}

local location_mt = {
    __index = {
        get_type_string = function(self)
            if self.type == "grenade" then
                local names =
                    table_map(
                    self.weapons,
                    function(weapon)
                        return GRENADE_WEAPON_NAMES[weapon]
                    end
                )
                return table.concat(names, "/")
            else
                return LOCATION_TYPE_NAMES[self.type] or self.type
            end
        end,
        get_export_tbl = function(self)
            local tbl = {
                name = (self.name == self.full_name) and self.name or {self.full_name:match("^(.*) to (.*)$")},
                description = self.description,
                weapon = #self.weapons == 1 and self.weapons[1].console_name or
                    table_map(
                        self.weapons,
                        function(weapon)
                            return weapon.console_name
                        end
                    ),
                position = {self.position.x, self.position.y, self.position.z},
                viewangles = {self.viewangles.pitch, self.viewangles.yaw}
            }

            if getmetatable(self.tickrates) == tickrates_mt then
                if self.tickrates.tickrate_set then
                    tbl.tickrate = self.tickrates.tickrate
                end
            elseif self.tickrates.orig ~= nil then
                tbl.tickrate = self.tickrates.orig
            end

            if self.approach_accurate ~= nil then
                tbl.approach_accurate = self.approach_accurate
            end

            if self.duckamount ~= 0 then
                tbl.duck = self.duckamount == 1 and true or self.duckamount
            end

            if self.position_visibility_different then
                tbl.position_visibility = {
                    self.position_visibility.x - self.position.x,
                    self.position_visibility.y - self.position.y,
                    self.position_visibility.z - self.position.z
                }
            end

            if self.type == "grenade" then
                tbl.grenade = {
                    fov = self.fov ~= DEFAULTS.fov and self.fov or nil,
                    jump = self.jump and true or nil,
                    strength = self.throw_strength ~= 1 and self.throw_strength or nil,
                    run = self.run_duration ~= nil and self.run_duration or nil,
                    run_yaw = self.run_yaw ~= self.viewangles.yaw and self.run_yaw - self.viewangles.yaw or nil,
                    run_speed = self.run_speed ~= nil and self.run_speed or nil,
                    recovery_yaw = self.recovery_yaw ~= nil and self.recovery_yaw - self.run_yaw or nil,
                    recovery_jump = self.recovery_jump and true or nil,
                    delay = self.delay > 0 and self.delay or nil
                }

                if next(tbl.grenade) == nil then
                    tbl.grenade = nil
                end
            elseif self.type == "movement" then
                tbl.movement = {
                    frames = compress_usercmds(self.movement_commands)
                }
            end

            if self.destroy_text ~= nil then
                tbl.destroy = {
                    ["start"] = self.destroy_start and {self.destroy_start:unpack()} or nil,
                    ["end"] = {self.destroy_end:unpack()},
                    ["text"] = self.destroy_text ~= DEFAULTS.destroy_text and self.destroy_text or nil
                }
            end

            return tbl
        end,
        get_export = function(self, fancy)
            local tbl = self:get_export_tbl()
            local indent = "  "

            local json_str
            if fancy then
                local default_keys, default_fancy = {"name", "description", "weapon", "position", "viewangles", "position_visibility", "grenade"}, {["grenade"] = 1}
                local result = {}

                for i = 1, #default_keys do
                    local key = default_keys[i]
                    local value = tbl[key]
                    if value ~= nil then
                        local str = default_fancy[key] == 1 and pretty_json.stringify(value, "\n", indent) or json.stringify(value)

                        if type(value[1]) == "number" and type(value[2]) == "number" and (value[3] == nil or type(value[3]) == "number") then
                            str = str:gsub(",", ", ")
                        else
                            str = str:gsub('","', '", "')
                        end

                        table.insert(result, string.format('"%s": %s', key, str))
                        tbl[key] = nil
                    end
                end

                for key, _ in pairs(tbl) do
                    table.insert(result, string.format('"%s": %s', key, pretty_json.stringify(tbl[key], "\n", indent)))
                end

                json_str = "{\n" .. indent .. table.concat(result, ",\n"):gsub("\n", "\n" .. indent) .. "\n}"
            else
                json_str = json.stringify(tbl)
            end

            -- print_raw("json_str: ", json_str:sub(0, 500))

            return json_str
        end
    }
}

local function create_location(location_parsed)
    if type(location_parsed) ~= "table" then
        return "wrong type, expected table"
    end

    if getmetatable(location_parsed) == location_mt then
        return "trying to create an already created location"
    end

    local location = {}

    if type(location_parsed.name) == "string" and location_parsed.name:len() > 0 then
        location.name = location_parsed.name:gsub("[%c]", "")
        location.full_name = location.name
    elseif type(location_parsed.name) == "table" and #location_parsed.name == 2 then
        location.name = location_parsed.name[2]:gsub("[%c]", "")
        location.full_name = string.format("%s to %s", location_parsed.name[1], location_parsed.name[2]):gsub("[%c]", "")
    else
        -- print_raw(DEBUG.inspect(location.name))
        return "invalid name, expected string or table of length 2"
    end

    if type(location_parsed.description) == "string" and location_parsed.description:len() > 0 then
        location.description = location_parsed.description
    elseif location_parsed.description ~= nil then
        return "invalid description, expected nil or non-empty string"
    end

    if type(location_parsed.weapon) == "string" and weapons[location_parsed.weapon] ~= nil then
        location.weapons = {weapons[location_parsed.weapon]}
        location.weapons_assoc = {[weapons[location_parsed.weapon]] = true}
    elseif type(location_parsed.weapon) == "table" and #location_parsed.weapon > 0 then
        location.weapons = {}
        location.weapons_assoc = {}

        for i = 1, #location_parsed.weapon do
            local weapon = weapons[location_parsed.weapon[i]]
            if weapon ~= nil then
                if location.weapons_assoc[weapon] then
                    return "duplicate weapon: " .. location_parsed.weapon[i]
                else
                    location.weapons[i] = weapon
                    location.weapons_assoc[weapon] = true
                end
            else
                return "invalid weapon: " .. location_parsed.weapon[i]
            end
        end
    else
        return string.format("invalid weapon (%s)", tostring(location_parsed.weapon))
    end

    if type(location_parsed.position) == "table" and #location_parsed.position == 3 then
        local x, y, z = unpack(location_parsed.position)

        if type(x) == "number" and type(y) == "number" and type(z) == "number" then
            location.position = vector(x, y, z)
            location.position_visibility = location.position + DEFAULTS.visibility_offset
            location.position_id = VECTOR_INDEX[location.position]
        else
            return "invalid type in position"
        end
    else
        return "invalid position"
    end

    if type(location_parsed.position_visibility) == "table" and #location_parsed.position_visibility == 3 then
        local x, y, z = unpack(location_parsed.position_visibility)

        if type(x) == "number" and type(y) == "number" and type(z) == "number" then
            local origin = location.position
            location.position_visibility = vector(origin.x + x, origin.y + y, origin.z + z)
            location.position_visibility_different = true
        else
            return "invalid type in position_visibility"
        end
    elseif location_parsed.position_visibility ~= nil then
        return "invalid position_visibility"
    end

    if type(location_parsed.viewangles) == "table" and #location_parsed.viewangles == 2 then
        local pitch, yaw = unpack(location_parsed.viewangles)

        if type(pitch) == "number" and type(yaw) == "number" then
            location.viewangles = {
                pitch = pitch,
                yaw = yaw
            }

            location.viewangles_forward = vector():angles(pitch, yaw)
        else
            return "invalid type in viewangles"
        end
    else
        return "invalid viewangles"
    end

    if type(location_parsed.approach_accurate) == "boolean" then
        location.approach_accurate = location_parsed.approach_accurate
    elseif location_parsed.approach_accurate ~= nil then
        return "invalid approach_accurate"
    end

    if location_parsed.duck == nil or type(location_parsed.duck) == "boolean" then
        location.duckamount = location_parsed.duck and 1 or 0
    else
        return string.format("invalid duck value (%s)", tostring(location_parsed.duck))
    end
    location.eye_pos = location.position + vector(0, 0, 64 - location.duckamount * 18)

    -- tickrates key is the real tickrate and value is the multiplier for duration etc
    if (type(location_parsed.tickrate) == "number" and location_parsed.tickrate > 0) or location_parsed.tickrate == nil then
        location.tickrates =
            setmetatable(
            {
                tickrate = location_parsed.tickrate or 64,
                tickrate_set = location_parsed.tickrate ~= nil
            },
            tickrates_mt
        )
    elseif type(location_parsed.tickrate) == "table" and #location_parsed.tickrate > 0 then
        location.tickrates = {
            orig = location_parsed.tickrate
        }

        local orig_tickrate

        for i = 1, #location_parsed.tickrate do
            local tickrate = location_parsed.tickrate[i]
            if type(tickrate) == "number" and tickrate > 0 then
                if orig_tickrate == nil then
                    orig_tickrate = tickrate
                    location.tickrates[tickrate] = 1
                else
                    location.tickrates[tickrate] = orig_tickrate / tickrate
                end
            else
                return "invalid tickrate: " .. tostring(location_parsed.tickrate[i])
            end
        end
    else
        return string.format("invalid tickrate (%s)", tostring(location_parsed.tickrate))
    end

    if type(location_parsed.target) == "table" then
        local x, y, z = unpack(location_parsed.target)

        if type(x) == "number" and type(y) == "number" and type(z) == "number" then
            location.target = vector(x, y, z)
        else
            return "invalid type in target"
        end
    elseif location_parsed.target ~= nil then
        return "invalid target"
    end

    -- ensure they're all a grenade or none a grenade, then determine type
    local has_grenade, has_non_grenade
    for i = 1, #location.weapons do
        if location.weapons[i].type == "grenade" then
            has_grenade = true
        else
            has_non_grenade = true
        end
    end

    if has_grenade and has_non_grenade then
        return "can't have grenade and non-grenade in one location"
    end

    if location_parsed.movement ~= nil then
        location.type = "movement"
        location.fov = DEFAULTS.fov_movement
    elseif has_grenade then
        location.type = "grenade"
        location.throw_strength = 1
        location.fov = DEFAULTS.fov
        location.delay = 0
        location.jump = false
        location.run_yaw = location.viewangles.yaw
    elseif has_non_grenade then
        location.type = "wallbang"
    else
        return "invalid type"
    end

    if location.viewangles_forward ~= nil and location.eye_pos ~= nil then
        local viewangles_target = location.eye_pos + location.viewangles_forward * 700
        local fraction, _, vec_hit = trace_line_skip(location.eye_pos, viewangles_target, 2)
        location.viewangles_target = fraction > 0.05 and vec_hit or viewangles_target
    end

    if location.type == "grenade" and type(location_parsed.grenade) == "table" then
        local grenade = location_parsed.grenade
        -- location.throw_strength = 1
        -- location.fov = 0.3
        -- location.jump = false
        -- location.run = false
        -- location.run_yaw = 0

        if type(grenade.strength) == "number" and grenade.strength >= 0 and grenade.strength <= 1 then
            location.throw_strength = grenade.strength
        elseif grenade.strength ~= nil then
            return string.format("invalid grenade.strength (%s)", tostring(grenade.strength))
        end

        if type(grenade.delay) == "number" and grenade.delay > 0 then
            location.delay = grenade.delay
        elseif grenade.delay ~= nil then
            return string.format("invalid grenade.delay (%s)", tostring(grenade.delay))
        end

        if type(grenade.fov) == "number" and grenade.fov >= 0 and grenade.fov <= 180 then
            location.fov = grenade.fov
        elseif grenade.fov ~= nil then
            return string.format("invalid grenade.fov (%s)", tostring(grenade.fov))
        end

        if type(grenade.jump) == "boolean" then
            location.jump = grenade.jump
        elseif grenade.jump ~= nil then
            return string.format("invalid grenade.jump (%s)", tostring(grenade.jump))
        end

        if type(grenade.run) == "number" and grenade.run > 0 and grenade.run < 512 then
            location.run_duration = grenade.run
        elseif grenade.run ~= nil then
            return string.format("invalid grenade.run (%s)", tostring(grenade.run))
        end

        if type(grenade.run_yaw) == "number" and grenade.run_yaw >= -180 and grenade.run_yaw <= 180 then
            location.run_yaw = location.viewangles.yaw + grenade.run_yaw
        elseif grenade.run_yaw ~= nil then
            return string.format("invalid grenade.run_yaw (%s)", tostring(grenade.run_yaw))
        end

        if type(grenade.run_speed) == "boolean" then
            location.run_speed = grenade.run_speed
        elseif grenade.run_speed ~= nil then
            return "invalid grenade.run_speed"
        end

        if type(grenade.recovery_yaw) == "number" then
            location.recovery_yaw = location.run_yaw + grenade.recovery_yaw
        elseif grenade.recovery_yaw ~= nil then
            return "invalid grenade.recovery_yaw"
        end

        if type(grenade.recovery_jump) == "boolean" then
            location.recovery_jump = grenade.recovery_jump
        elseif grenade.recovery_jump ~= nil then
            return "invalid grenade.recovery_jump"
        end
    elseif location_parsed.grenade ~= nil then
        -- print_raw(DEBUG.inspect(location_parsed))
        return "invalid grenade"
    end

    if location.type == "movement" and type(location_parsed.movement) == "table" then
        local movement = location_parsed.movement

        if type(movement.fov) == "number" and movement.fov > 0 and movement.fov < 360 then
            location.fov = movement.fov
        end

        if type(movement.frames) == "table" then
            -- decompress frames
            local frames = {}

            -- step one, insert the empty frames for numbers
            for i, frame in ipairs(movement.frames) do
                if type(frame) == "number" then
                    if movement.frames[i] > 0 then
                        for _ = 1, frame do
                            table.insert(frames, {})
                        end
                    else
                        return "invalid frame " .. tostring(i)
                    end
                elseif type(frame) == "table" then
                    table.insert(frames, frame)
                end
            end

            -- step two, delta decompress frames into ready-made usercmds
            local current = {
                viewangles = {pitch = location.viewangles.pitch, yaw = location.viewangles.yaw},
                buttons = {}
            }

            -- initialize all buttons as false
            for key, _ in pairs(MOVEMENT_BUTTONS_CHARS) do
                current.buttons[key] = false
            end

            for i, value in ipairs(frames) do
                local pitch, yaw, buttons, forwardmove, sidemove = unpack(value)

                if pitch ~= nil and type(pitch) ~= "number" then
                    return string.format("invalid pitch in frame #%d", i)
                elseif yaw ~= nil and type(yaw) ~= "number" then
                    return string.format("invalid yaw in frame #%d", i)
                end

                -- update current viewangles with new delta data
                current.viewangles.pitch = current.viewangles.pitch + (pitch or 0)
                current.viewangles.yaw = current.viewangles.yaw + (yaw or 0)

                -- update buttons
                if type(buttons) == "string" then
                    local buttons_dn, buttons_up = {}, {}
                    for c in buttons:gmatch(".") do
                        if c:lower() == c then
                            table.insert(buttons_up, MOVEMENT_BUTTONS_CHARS_INV[c:upper()] or false)
                        else
                            table.insert(buttons_dn, MOVEMENT_BUTTONS_CHARS_INV[c] or false)
                        end
                    end

                    local buttons_seen = {}
                    for _, btn in ipairs(buttons_dn) do
                        if btn == false then
                            return string.format("invalid button in frame #%d", i)
                        elseif buttons_seen[btn] then
                            return string.format("invalid frame #%d: duplicate button %s", i, btn)
                        end
                        buttons_seen[btn] = true

                        -- button is down
                        current.buttons[btn] = true
                    end

                    for _, btn in ipairs(buttons_up) do
                        if btn == false then
                            return string.format("invalid button in frame #%d", i)
                        elseif buttons_seen[btn] then
                            return string.format("invalid frame #%d: duplicate button %s", i, btn)
                        end
                        buttons_seen[btn] = true

                        -- button is up
                        current.buttons[btn] = false
                    end
                elseif buttons ~= nil then
                    return string.format("invalid buttons in frame #%d", i)
                end

                -- either copy or reconstruct forwardmove and sidemove
                if type(forwardmove) == "number" and forwardmove >= -450 and forwardmove <= 450 then
                    current.forwardmove = forwardmove
                elseif forwardmove ~= nil then
                    return string.format("invalid forwardmove in frame #%d: %s", i, tostring(forwardmove))
                else
                    current.forwardmove = calculate_move(current.buttons.in_forward, current.buttons.in_back)
                end

                if type(sidemove) == "number" and sidemove >= -450 and sidemove <= 450 then
                    current.sidemove = sidemove
                elseif sidemove ~= nil then
                    return string.format("invalid sidemove in frame #%d: %s", i, tostring(sidemove))
                else
                    current.sidemove = calculate_move(current.buttons.in_moveright, current.buttons.in_moveleft)
                end

                -- copy data from current into the frame
                frames[i] = {
                    pitch = current.viewangles.pitch,
                    yaw = current.viewangles.yaw,
                    move_yaw = current.viewangles.yaw,
                    forwardmove = current.forwardmove,
                    sidemove = current.sidemove
                }

                -- copy over buttons
                for btn, val in pairs(current.buttons) do
                    frames[i][btn] = val
                end
            end

            location.movement_commands = frames
        else
            return "invalid movement.frames"
        end
    elseif location_parsed.movement ~= nil then
        return "invalid movement"
    end

    if type(location_parsed.destroy) == "table" then
        local destroy = location_parsed.destroy
        location.destroy_text = "Break the object"

        if type(destroy.start) == "table" then
            local x, y, z = unpack(destroy.start)

            if type(x) == "number" and type(y) == "number" and type(z) == "number" then
                location.destroy_start = vector(x, y, z)
            else
                return "invalid type in destroy.start"
            end
        elseif destroy.start ~= nil then
            return "invalid destroy.start"
        end

        if type(destroy["end"]) == "table" then
            local x, y, z = unpack(destroy["end"])

            if type(x) == "number" and type(y) == "number" and type(z) == "number" then
                location.destroy_end = vector(x, y, z)
            else
                return "invalid type in destroy.end"
            end
        else
            return "invalid destroy.end"
        end

        if type(destroy.text) == "string" and destroy.text:len() > 0 then
            location.destroy_text = destroy.text
        elseif destroy.text ~= nil then
            return "invalid destroy.text"
        end
    elseif location_parsed.destroy ~= nil then
        return "invalid destroy"
    end

    return setmetatable(location, location_mt)
end

local function parse_and_create_locations(table_or_json)
    local locations_parsed
    if type(table_or_json) == "string" then
        local success
        success, locations_parsed = pcall(json.parse, table_or_json)

        if not success then
            error(locations_parsed)
            return
        end
    elseif type(table_or_json) == "table" then
        locations_parsed = table_or_json
    else
        assert(false)
    end

    if type(locations_parsed) ~= "table" then
        error(string.format("invalid type %s, expected table", type(locations_parsed)))
        return
    end

    local locations = {}
    for i = 1, #locations_parsed do
        local location = create_location(locations_parsed[i])

        if type(location) == "table" then
            table.insert(locations, location)
        else
            error(location or "failed to parse")
            return
        end
    end

    return locations
end

local function export_locations(tbl, fancy)
    local indent = "  "
    local result = {}

    for i = 1, #tbl do
        local str = tbl[i]:get_export(fancy)
        if fancy then
            str = indent .. str:gsub("\n", "\n" .. indent)
        end
        table.insert(result, str)
    end

    return (fancy and "[\n" or "[") .. table.concat(result, fancy and ",\n" or ",") .. (fancy and "\n]" or "]")
end

local function source_get_index_data(url, callback)
    http.get(
        url,
        {absolute_timeout = 10, network_timeout = 5, params = {ts = common.get_unixtime()}},
        function(success, response)
            local data = {}

            if not success or response.status ~= 200 or response.body == "404: Not Found" then
                if response.body == "404: Not Found" then
                    callback("404 - Not Found")
                else
                    callback(string.format("%s - %s", response.status, response.status_message))
                end

                return
            end

            local valid_json, jso = pcall(json.parse, response.body)
            if not valid_json then
                callback("Invalid JSON: " .. jso)
                return
            end

            -- name is always required
            if type(jso.name) == "string" then
                data.name = jso.name
            else
                callback("Invalid name")
                return
            end

            -- description can be nil or string
            if jso.description == nil or type(jso.description) == "string" then
                data.description = jso.description
            else
                callback("Invalid description")
                return
            end

            -- update_timestamp can be nil or number
            if jso.update_timestamp == nil or type(jso.update_timestamp) == "number" then
                data.update_timestamp = jso.update_timestamp
            else
                callback("Invalid update_timestamp")
                return
            end

            if jso.url_format ~= nil then
                -- dealing with a split location
                if type(jso.url_format) ~= "string" or not jso.url_format:match("^https?://.+$") then
                    callback("Invalid url_format")
                    return
                end

                -- simple sanity check, make sure <map> is contained in the string
                if not jso.url_format:find("%%map%%") then
                    callback("Invalid url_format - %map% is required")
                    return
                end

                data.url_format = jso.url_format
            else
                data.url_format = nil
            end

            -- create a lookup table for location aliases, or clear it if no locations are set (only valid for split location, will be checked later)
            data.location_aliases = {}
            data.locations = {}
            if type(jso.locations) == "table" then
                for map, map_data in pairs(jso.locations) do
                    if type(map) ~= "string" then
                        callback("Invalid key in locations")
                        return
                    end

                    if type(map_data) == "string" then
                        -- this is an alias
                        data.location_aliases[map] = map_data
                    elseif type(map_data) == "table" then
                        data.locations[map] = map_data
                    elseif jso.url_format ~= nil then
                        -- not an alias and non-alias is forbidden for split locations
                        callback("Location data is forbidden for split locations")
                        return
                    end
                end
            elseif jso.locations ~= nil then
                callback("Invalid locations")
                return
            end

            if next(data.location_aliases) == nil then
                data.location_aliases = nil
            end

            if next(data.locations) == nil then
                data.locations = nil
            end

            -- save last_updated to location
            data.last_updated = common.get_unixtime()

            -- for a normal location, parse locations and update data in helper_store db
            -- if data.url_format == nil then
            -- 	-- data.locations is already checked above, so we can safely use it
            -- 	local new_locations = {}

            -- 	for map, map_data in pairs(data.locations) do
            -- 		if type(map_data) == "table" then
            -- 			print_raw("source_get_index_data calling parse_and_create_locations")
            -- 			print_raw(inspect(data.locations))
            -- 			print_raw(inspect(map_data))
            -- 			local success, locations = pcall(parse_and_create_locations, map_data, map)

            -- 			if not success then
            -- 				return callback(string.format("Invalid locations for %s: %s", map, locations))
            -- 			end

            -- 			data.locations[map] = locations
            -- 		end
            -- 	end
            -- end

            callback(nil, data)
        end
    )
end

local source_mt = {
    __index = {
        -- update all data for remote source (index for split sources, everything for combined ones)
        update_remote_data = function(self)
            if not self.type == "remote" or self.url == nil then
                return
            end

            self.remote_status = "Loading index data..."
            source_get_index_data(
                self.url,
                function(err, data)
                    if err ~= nil then
                        self.remote_status = string.format("Error: %s", err)
                        update_sources_ui()
                        return
                    end

                    self.last_updated = data.last_updated

                    if self.last_updated == nil then
                        self.remote_status = "Index data refreshed"
                        update_sources_ui()
                        self.remote_status = nil
                    else
                        self.remote_status = nil
                        update_sources_ui()
                    end

                    local keys = {"name", "description", "update_timestamp", "url_format"}
                    for i = 1, #keys do
                        -- print_raw(string.format("setting %s to %s", keys[i], data[keys[i]]))
                        self[keys[i]] = data[keys[i]]
                    end

                    -- new url
                    if data.url ~= nil and data.url ~= self.url then
                        self.url = data.url
                        self:update_remote_data()
                        return
                    end

                    local current_map_name = get_mapname()

                    -- todo: find a better way to do this
                    sources_locations[self] = nil
                    local store_db_locations = (database["helper_store"] or {})["locations"]
                    if store_db_locations ~= nil and type(store_db_locations[self.id]) == "table" then
                        store_db_locations[self.id] = {}
                    end
                    flush_active_locations("update_remote_data")

                    if data.locations ~= nil then
                        sources_locations[self] = {}
                        for map, locations_unparsed in pairs(data.locations) do
                            -- print_raw("parse_and_create_locations: ", inspect(locations_unparsed))
                            local success, locations = pcall(parse_and_create_locations, locations_unparsed, map)
                            if not success then
                                self.remote_status = string.format("Invalid map data: %s", locations)
                                print_raw(string.format("\a4B69FF[neverlose]\aFF4040\x20Failed to load map data for %s (%s): %s", self.name, map, locations))
                                update_sources_ui()
                                return
                            end

                            -- set in runtime cache
                            sources_locations[self][map] = locations

                            -- save runtime cache to db
                            self:store_write(map)

                            -- remove from runtime cache unless we're on that map
                            if map == current_map_name then
                                flush_active_locations("B")
                            else
                                sources_locations[self][map] = nil
                            end
                        end
                    end
                end
            )
        end,
        store_read = function(self, mapname)
            -- read data from store and parse it into sources_locations[self][mapname]
            if mapname == nil then
                local store_db_locations = (database["helper_store"] or {})["locations"]
                if store_db_locations ~= nil and type(store_db_locations[self.id]) == "table" then
                    for mapname, _ in pairs(store_db_locations[self.id]) do
                        self:store_read(mapname)
                    end
                end
                return
            end

            local store_db_locations = (database["helper_store"] or {})["locations"]
            if store_db_locations ~= nil and type(store_db_locations[self.id]) == "table" and type(store_db_locations[self.id][mapname]) == "string" then
                local success, locations = pcall(parse_and_create_locations, store_db_locations[self.id][mapname], mapname)

                if not success then
                    self.remote_status = string.format("Invalid map data for %s in database: %s", mapname, locations)
                    print_raw(string.format("\a4B69FF[neverlose]\aFF4040\x20Invalid map data for %s (%s) in database: %s", self.name, mapname, locations))
                    update_sources_ui()
                else
                    sources_locations[self][mapname] = locations
                end
            -- print_raw("read from db! ", inspect(sources_locations[self][mapname]))
            end
        end,
        store_write = function(self, mapname)
            -- write sources_locations[self][mapname] to store db
            if mapname == nil then
                if sources_locations[self] ~= nil then
                    for mapname, _ in pairs(sources_locations[self]) do
                        self:store_write(mapname)
                    end
                end
                return
            end

            -- print_raw("write for ", self.id, " ", mapname)

            local store_db = (database["helper_store"] or {})
            store_db.locations = store_db.locations or {}
            store_db.locations[self.id] = store_db.locations[self.id] or {}

            store_db.locations[self.id][mapname] = export_locations(sources_locations[self][mapname])

            -- print_raw(inspect(sources_locations[self]))
            -- print_raw(inspect(store_db))

            database["helper_store"] = store_db
        end,
        get_locations = function(self, mapname, allow_fetch)
            if sources_locations[self] == nil then
                sources_locations[self] = {}
            end

            if sources_locations[self][mapname] == nil then
                self:store_read(mapname)
                local locations = sources_locations[self][mapname]

                if self.type == "remote" and allow_fetch and (self.last_updated == nil or common.get_unixtime() - self.last_updated > (self.ttl or DEFAULTS.source_ttl)) then
                    -- we dont even have up-to-date index data for this source, fetch it first
                    -- print_raw("fetching index data for ", self.name, " (", tostring(self.last_updated), ")")
                    self:update_remote_data()
                end

                -- read and parse locations if required
                if self.type == "local_file" and mapname ~= nil then
                    -- simulate delay for the memes
                    utils.execute_after(
                        0.5,
                        function()
                            benchmark:start("readfile")
                            local contents_raw = files.read("nl\\" .. self.filename)
                            local contents = json.parse(contents_raw)

                            local current_map_name = get_mapname()

                            for mapname, map_locations in pairs(contents) do
                                local success, locations = pcall(parse_and_create_locations, map_locations, mapname)
                                if not success then
                                    self.remote_status = string.format("Invalid map data: %s", locations)
                                    print_raw(string.format("\a4B69FF[neverlose]\aFF4040\x20Failed to load map data for %s (%s): %s", self.name, mapname, locations))
                                    update_sources_ui()
                                    return
                                end

                                -- sanity check for get_export working properly
                                if DEBUG then
                                    local keys_to_remove = {"viewangles", "position"}

                                    for i = 1, #map_locations do
                                        local location = create_location(map_locations[i])
                                        if type(location) ~= "table" then
                                            -- print_raw(inspect(map_locations[i]))
                                            print("failed to create! ", location)
                                        else
                                            local export_tbl = location:get_export_tbl()

                                            for j = 1, #keys_to_remove do
                                                export_tbl[keys_to_remove[j]] = nil
                                                map_locations[i][keys_to_remove[j]] = nil
                                            end

                                            if export_tbl.destroy ~= nil then
                                                export_tbl.destroy["start"] = nil
                                                export_tbl.destroy["end"] = nil
                                            end
                                            if map_locations[i].destroy ~= nil then
                                                map_locations[i].destroy["start"] = nil
                                                map_locations[i].destroy["end"] = nil
                                            end

                                            local json_str_export = json.stringify(export_tbl)
                                            local json_str_orig = json.stringify(map_locations[i])

                                            if json_str_orig:len() ~= json_str_export:len() then
                                                print("  orig: ", json_str_orig)
                                                print("export: ", json_str_export)
                                            end
                                        end
                                    end
                                end

                                -- print("read locations: ", inspect(locations):sub(0, 500))

                                -- set in runtime cache
                                sources_locations[self][mapname] = locations

                                flush_active_locations()

                                -- save runtime cache to db
                                self:store_write(mapname)

                                -- print_raw("wrote successfully")

                                -- remove from runtime cache unless we're on that map
                                if mapname ~= current_map_name then
                                    sources_locations[self][mapname] = nil
                                end
                            end

                            benchmark:finish("readfile")
                        end
                    )
                elseif locations == nil and allow_fetch and self.type == "remote" and self.url_format ~= nil then
                    -- fetch data for this map
                    -- print_raw("Fetching missing data for ", self.name, " - ", mapname)

                    local url = self.url_format:gsub("%%map%%", mapname)

                    self.remote_status = string.format("Loading map data for %s...", mapname)
                    update_sources_ui()

                    http.get(
                        url,
                        {network_timeout = 10, absolute_timeout = 15, params = {ts = common.get_unixtime()}},
                        function(success, response)
                            if not success or response.status ~= 200 or response.body == "404: Not Found" then
                                if response.status == 404 or response.body == "404: Not Found" then
                                    self.remote_status = string.format("No locations found for %s.", mapname)
                                else
                                    self.remote_status = string.format("Failed to fetch %s: %s %s", mapname, response.status, response.status_message)
                                end
                                update_sources_ui()
                                return
                            end

                            local success, locations = pcall(parse_and_create_locations, response.body, mapname)
                            if not success then
                                self.remote_status = string.format("Invalid map data: %s", locations)
                                update_sources_ui()
                                print_raw(string.format("\a4B69FF[neverlose]\aFF4040\x20Failed to load map data for %s (%s): %s", self.name, mapname, locations))
                                return
                            end

                            -- set in runtime cache
                            sources_locations[self][mapname] = locations

                            -- save runtime cache to db
                            self:store_write(mapname)

                            self.remote_status = nil
                            update_sources_ui()
                            flush_active_locations("C")
                        end
                    )
                else
                    if locations == nil then
                    -- print_raw("failed to fetch locations for: ", inspect(self))
                    end
                end

                sources_locations[self][mapname] = locations or {}
            end

            return sources_locations[self][mapname]
        end,
        get_all_locations = function(self)
            local locations = {}

            local store_db_locations = (database["helper_store"] or {})["locations"]
            if store_db_locations ~= nil and type(store_db_locations[self.id]) == "table" then
                for mapname, _ in pairs(store_db_locations[self.id]) do
                    locations[mapname] = self:get_locations(mapname)
                end
            end

            return locations
        end,
        -- called before writing source to db, so remove all temporary stuff etc
        cleanup = function(self)
            self.remote_status = nil
            setmetatable(self, nil)
        end
    }
}

for i = 1, #db.sources do
    setmetatable(db.sources[i], source_mt)
end

--
-- dummy menu element for saving per-config settings
-- util functions: get_sources_config, set_sources_config
--

local sources_config_reference = ui.create("Manage", "A"):input("##Config", "{}")
sources_config_reference:visibility(false)

local function get_sources_config()
    local sources_config = json.parse(sources_config_reference:get() or "{}")

    -- fix up enabled sources
    local source_ids_assoc = {}
    sources_config.enabled = sources_config.enabled or {}
    for i = 1, #db.sources do
        local source = db.sources[i]
        source_ids_assoc[source.id] = true
        if sources_config.enabled[source.id] == nil then
            sources_config.enabled[source.id] = true
        end
    end

    -- remove nonexistent sources from config
    for id, _ in pairs(sources_config.enabled) do
        if source_ids_assoc[id] == nil then
            sources_config.enabled[id] = nil
        end
    end

    return sources_config
end

local function set_sources_config(sources_config)
    sources_config_reference:set(json.stringify(sources_config))
end

local function button_with_confirmation(group, name, callback, callback_visibility)
    local button_open, button_cancel, button_confirm
    local ts_open

    button_open =
        group:button(
        name,
        function()
            button_open:visibility(false)
            button_cancel:visibility(true)
            button_confirm:visibility(true)

            local realtime = globals.realtime
            ts_open = realtime

            utils.execute_after(
                5,
                function()
                    if ts_open == realtime then
                        button_open:visibility(true)
                        button_cancel:visibility(false)
                        button_confirm:visibility(false)

                        if callback_visibility ~= nil then
                            callback_visibility()
                        end
                    end
                end
            )
        end
    )

    button_cancel =
        group:button(
        name .. "\x20(CANCEL)",
        function()
            button_open:visibility(true)
            button_cancel:visibility(false)
            button_confirm:visibility(false)

            if callback_visibility ~= nil then
                callback_visibility()
            end

            ts_open = nil
        end
    )

    button_confirm =
        group:button(
        name .. "\x20(CONFIRM)",
        function()
            button_open:visibility(true)
            button_cancel:visibility(false)
            button_confirm:visibility(false)

            ts_open = nil
            callback()

            if callback_visibility ~= nil then
                callback_visibility()
            end
        end
    )

    return button_open, button_cancel, button_confirm
end

--
-- ui references to default items
--

local air_strafe_reference = ui.find("Miscellaneous", "Main", "Movement", "Air Strafe")
local air_duck_reference = ui.find("Miscellaneous", "Main", "Movement", "Air Duck")
local quick_stop_reference = ui.find("Miscellaneous", "Main", "Movement", "Quick Stop")
local strafe_assist_reference = ui.find("Miscellaneous", "Main", "Movement", "Strafe Assist")
local infinite_duck_reference = ui.find("Miscellaneous", "Main", "Movement", "Infinite Duck")

local antiaim_pitch_reference = ui.find("Aimbot", "Anti Aim", "Angles", "Pitch")
local antiaim_body_yaw_reference = ui.find("Aimbot", "Anti Aim", "Angles", "Body Yaw")

--
-- normal menu items
--

local enabled_reference = ui.create("Main"):switch("Enabled")
local select_reference = ui.create("Main"):selectable("##Select", {"Smoke", "Flashbang", "High Explosive", "Molotov", "Movement"})
local shader_reference = select_reference:color_picker(color(120, 120, 255))
local hotkey_reference = ui.create("Main"):hotkey("Hotkey")
local aimbot_reference =
    ui.create("Main"):combo(
    "Aim at locations",
    {
        "Off",
        "Legit",
        "Legit (Silent)",
        "Rage"
    }
)
local aimbot_fov_reference = aimbot_reference:create():slider("##FOV", 0, 200, 80, 0.1, "°")
local aimbot_speed_reference = aimbot_reference:create():slider("##Speed", 0, 100, 75, 1, "%")
local behind_walls_reference = ui.create("Main"):switch("Show locations behind walls")

--
-- source management menu items
--

local sources_list_ui = {
    title = ui.create("Manage", "A"):switch("Manage sources"),
    list = ui.create("Manage", "A"):list("##Sources"),
    source_label1 = ui.create("Manage", "A"):label("Source label 1"),
    enabled = ui.create("Manage", "A"):switch("Enabled"),
    source_label2 = ui.create("Manage", "A"):label("Source label 2"),
    source_label3 = ui.create("Manage", "A"):label("Source label 3"),
    name = ui.create("Manage", "A"):input("New source name")
}

--
-- source editing
--

-- forward declare button callbacks
local on_edit_save, on_edit_delete, on_edit_teleport, on_edit_set, on_edit_export

local edit_ui = {
    list = ui.create("Manage", "A"):list("##Selected source locations"),
    show_all = ui.create("Manage", "A"):switch("Show all maps"),
    sort_by = ui.create("Manage", "A"):combo("Sort by", {"Creation date", "Type", "Alphabetically"}),
    type_label = ui.create("Manage", "B"):label("Creating new location"),
    type = ui.create("Manage", "B"):combo("##Location type", {"Grenade", "Movement", "Location", "Area"}),
    from_label = ui.create("Manage", "B"):label("From"),
    from = ui.create("Manage", "B"):input("##From"),
    to_label = ui.create("Manage", "B"):label("To"),
    to = ui.create("Manage", "B"):input("##To"),
    description_label = ui.create("Manage", "B"):label("Description (Optional)"),
    description = ui.create("Manage", "B"):input("##Description (Optional)"),
    grenade_properties_label = ui.create("Manage", "B"):label("Grenade Properties"),
    grenade_properties = ui.create("Manage", "B"):selectable(
        "##Grenade Properties",
        {
            "Jump",
            "Run",
            "Walk (Shift)",
            "Throw strength",
            "Force-enable recovery",
            "Tickrate dependent",
            "Destroy breakable object",
            "Delayed throw"
        }
    ),
    throw_strength = ui.create("Manage", "B"):combo("Throw strength", {"Left Click", "Left / Right Click", "Right Click"}),
    run_direction_label = ui.create("Manage", "B"):label("Run duration / direction"),
    run_direction = ui.create("Manage", "B"):combo("##Run duration / direction", {"Forward", "Left", "Right", "Back", "Custom"}),
    run_direction_custom = ui.create("Manage", "B"):slider("##Custom run direction", -180, 180, 0, 1, "°"),
    run_duration = ui.create("Manage", "B"):slider("##Run duration", 1, 256, 20, 1, "t"),
    delay = ui.create("Manage", "B"):slider("Throw delay", 1, 40, 1, 1, "t"),
    recovery_direction_label = ui.create("Manage", "B"):label("Recovery (after throw) direction"),
    recovery_direction = ui.create("Manage", "B"):combo("##Recovery (after throw) direction", {"Back", "Forward", "Left", "Right", "Custom"}, 0),
    recovery_direction_custom = ui.create("Manage", "B"):slider("##Custom recovery direction", -180, 180, 0, 1, "°"),
    recovery_jump = ui.create("Manage", "B"):switch("Recovery bunny-hop"),
    set = ui.create("Manage", "B"):button(
        "Set location",
        function()
            on_edit_set()
        end
    ),
    teleport = ui.create("Manage", "B"):button(
        "Teleport",
        function()
            on_edit_teleport()
        end
    ),
    export = ui.create("Manage", "B"):button(
        "Export to clipboard",
        function()
            on_edit_export()
        end
    ),
    save = ui.create("Manage", "B"):button(
        "Save",
        function()
            on_edit_save()
        end
    )
}

edit_ui.delete, edit_ui.delete_cancel, edit_ui.delete_confirm =
    button_with_confirmation(
    ui.create("Manage", "B"),
    "Delete",
    function()
        on_edit_delete()
    end,
    update_sources_ui
)

local edit_list, edit_ignore_callbacks, edit_different_map_selected = {}, false, false
local edit_location_selected

--
-- buttons with dummy callbacks so the funcs can be defined later
--

-- forward declare delete, create and import functions
local on_source_edit, on_source_edit_back, on_source_update, on_source_delete, on_source_create, on_source_import, on_source_export

sources_list_ui.edit =
    ui.create("Manage", "A"):button(
    "Edit",
    function()
        on_source_edit()
    end
)

sources_list_ui.update =
    ui.create("Manage", "A"):button(
    "Update",
    function()
        on_source_update()
    end
)

sources_list_ui.delete, sources_list_ui.delete_cancel, sources_list_ui.delete_confirm =
    button_with_confirmation(
    ui.create("Manage", "A"),
    "Delete",
    function()
        on_source_delete()
    end,
    update_sources_ui
)

sources_list_ui.create =
    ui.create("Manage", "A"):button(
    "Create",
    function()
        on_source_create()
    end
)

sources_list_ui.import =
    ui.create("Manage", "A"):button(
    "Import from clipboard",
    function()
        on_source_import()
    end
)

sources_list_ui.export =
    ui.create("Manage", "A"):button(
    "Export all to clipboard",
    function()
        on_source_export()
    end
)

sources_list_ui.back =
    ui.create("Manage", "A"):button(
    "Back",
    function()
        on_source_edit_back()
    end
)

sources_list_ui.source_label4 = ui.create("Manage", "A"):label("Ready.")

local sources_list, sources_ignore_callback = {}, false
local source_editing, source_selected, source_remote_add_status = false, nil, nil
local source_editing_modified, source_editing_has_changed = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})

-- sets source
local function set_source_selected(source_selected_new)
    source_selected_new = source_selected_new or "add_local"

    -- prevent useless ui updates
    if source_selected_new == source_selected then
        return false
    end

    for i = 1, #sources_list do
        if sources_list[i] == source_selected_new then
            sources_list_ui.list:set(i)
            source_editing = false
            return true
        end
    end

    return false
end

local function add_source(name_or_source, typ)
    local source
    if type(name_or_source) == "string" then
        source = {
            name = name_or_source,
            type = typ,
            id = randomid(8)
        }
    elseif type(name_or_source) == "table" then
        source = name_or_source
        source.type = typ
    else
        assert(false)
    end
    setmetatable(source, source_mt)

    local existing_ids =
        table_map_assoc(
        db.sources,
        function(key, value)
            return value.id, true
        end
    )
    while existing_ids[source.id] do
        source.id = randomid(8)
    end

    -- add to db
    table.insert(db.sources, source)

    -- add to config - handled by get_sources_config() fixup
    set_sources_config(get_sources_config())

    return source
end

local function get_sorted_locations(locations, sorting)
    if sorting == "Creation date" then
        return locations
    elseif sorting == "Type" or sorting == "Alphabetically" then
        local new_tbl = {}

        -- shallow copy the table and return a new, sorted one
        for i = 1, #locations do
            table.insert(new_tbl, locations[i])
        end

        table.sort(
            new_tbl,
            function(a, b)
                if sorting == "Type" then
                    return a:get_type_string() < b:get_type_string()
                elseif sorting == "Alphabetically" then
                    return a.name < b.name
                else
                    return true
                end
            end
        )

        return new_tbl
    else
        return locations
    end
end

-- update source ui - stateless
function update_sources_ui()
    local ui_visibility = {}

    for name, reference in pairs(sources_list_ui) do
        if name ~= "title" then
            ui_visibility[reference] = false
        end
    end

    edit_different_map_selected = true

    for _, reference in pairs(edit_ui) do
        ui_visibility[reference] = false
    end

    if enabled_reference:get() and sources_list_ui.title:get() then
        if source_editing and source_selected ~= nil then
            -- end
            -- print_raw(inspect(source_selected))
            local mapname = get_mapname()
            local show_all = edit_ui.show_all:get()

            -- if we're not ingame show all locations
            if mapname == nil then
                show_all = true
            end

            ui_visibility[sources_list_ui.source_label1] = true
            ui_visibility[sources_list_ui.source_label2] = true
            sources_list_ui.source_label1:set(
                string.format(
                    "\a%sEditing %s source: \a%s%s",
                    ui.get_style("Active Text"):to_hex(),
                    (SOURCE_TYPE_NAMES[source_selected.type] or source_selected.type):lower(),
                    ui.get_style("Link Active"):to_hex(),
                    source_selected.name
                )
            )
            sources_list_ui.source_label2:set(
                show_all and string.format("\a%sLocations on all maps: ", ui.get_style("Active Text"):to_hex()) or
                    string.format("\a%sLocations on \a%s%s\a%s:", ui.get_style("Active Text"):to_hex(), ui.get_style("Link Active"):to_hex(), mapname, ui.get_style("Active Text"):to_hex())
            )
            ui_visibility[sources_list_ui.import] = true
            ui_visibility[sources_list_ui.export] = true
            ui_visibility[sources_list_ui.back] = true
            ui_visibility[edit_ui.list] = true
            ui_visibility[edit_ui.show_all] = true
            ui_visibility[edit_ui.sort_by] = true

            local edit_listbox, edit_maps = {}, {}
            table_clear(edit_list)

            local sorting = edit_ui.sort_by:get()

            -- collect all locations for this map (or all if show_all is true)
            if show_all then
                local all_locations = source_selected:get_all_locations()
                local j = 1

                for map, locations in pairs(all_locations) do
                    locations = get_sorted_locations(locations, sorting)
                    for i = 1, #locations do
                        local location = locations[i]
                        edit_list[j] = location

                        local type_str = location:get_type_string()
                        edit_listbox[j] = string.format("[%s] %s: %s", map, type_str, location.name)

                        edit_maps[j] = map

                        j = j + 1
                    end
                end
            else
                local locations = source_selected:get_locations(mapname)

                locations = get_sorted_locations(locations, sorting)

                for i = 1, #locations do
                    local location = locations[i]
                    edit_list[i] = location

                    local type_str = location:get_type_string()
                    edit_listbox[i] = string.format("%s: %s", type_str, location.full_name)

                    edit_maps[i] = mapname
                end
            end

            table.insert(edit_listbox, string.format("\a%s  Create new", ui.get_style("Link Active"):to_hex()))
            table.insert(edit_list, "create_new")

            edit_ui.list:update(edit_listbox)

            if edit_location_selected == nil then
                -- edit_location_selected = "create_new"
                -- print_raw("setting to ", tostring(edit_location_selected), " ", i-1)

                edit_location_selected = "create_new"
                edit_set_ui_values(true)

            -- print_raw("set to ", edit_location_selected)
            end

            if edit_location_selected == "create_new" then
                edit_different_map_selected = false
            end

            for i = 1, #edit_list do
                if edit_list[i] == edit_location_selected then
                    edit_ui.list:set(i)

                    if edit_maps[i] == mapname and mapname ~= nil then
                        edit_different_map_selected = false
                    end
                end
            end

            -- update right side
            -- if edit_location_selected ~= nil then
            ui_visibility[edit_ui.type_label] = true
            ui_visibility[edit_ui.type] = true
            ui_visibility[edit_ui.from_label] = true
            ui_visibility[edit_ui.from] = true
            ui_visibility[edit_ui.to_label] = true
            ui_visibility[edit_ui.to] = true
            ui_visibility[edit_ui.description_label] = true
            ui_visibility[edit_ui.description] = true
            ui_visibility[edit_ui.grenade_properties_label] = true
            ui_visibility[edit_ui.grenade_properties] = true
            ui_visibility[edit_ui.set] = true
            ui_visibility[edit_ui.teleport] = true
            ui_visibility[edit_ui.export] = true
            ui_visibility[edit_ui.save] = true

            local properties =
                table_map_assoc(
                edit_ui.grenade_properties:get(),
                function(_, property)
                    return property, true
                end
            )

            if properties["Run"] then
                ui_visibility[edit_ui.run_direction] = true
                ui_visibility[edit_ui.run_duration] = true

                if edit_ui.run_direction:get() == "Custom" then
                    ui_visibility[edit_ui.run_direction_custom] = true
                end
            end

            if properties["Jump"] or properties["Force-enable recovery"] then
                ui_visibility[edit_ui.recovery_direction] = true
                ui_visibility[edit_ui.recovery_jump] = true

                if edit_ui.recovery_direction:get() == "Custom" then
                    ui_visibility[edit_ui.recovery_direction_custom] = true
                end
            end

            if properties["Delayed throw"] then
                ui_visibility[edit_ui.delay] = true
            end

            if properties["Throw strength"] then
                ui_visibility[edit_ui.throw_strength] = true
            end

            if edit_location_selected ~= nil and edit_location_selected ~= "create_new" then
                ui_visibility[edit_ui.delete] = true
            end
        else
            local sources_config = get_sources_config()

            local sources_listbox, sources_listbox_i = {}, nil
            table_clear(sources_list)

            -- collect all sources (default and custom)
            for i = 1, #db.sources do
                local source = db.sources[i]
                sources_list[i] = source
                table.insert(
                    sources_listbox,
                    string.format(
                        "\a%s  %s: %s",
                        sources_config.enabled[source.id] and (ui.get_style("Active Text"):to_hex() .. "+") or "DEFAULT-",
                        SOURCE_TYPE_NAMES[source.type] or source.type,
                        source.name
                    )
                )

                if source == source_selected then
                    sources_listbox_i = i
                end
            end

            table.insert(sources_listbox, string.format("\a%s+  Add remote source", ui.get_style("Link Active"):to_hex()))
            table.insert(sources_list, "add_remote")
            if source_selected == "add_remote" then
                sources_listbox_i = #sources_list
            end

            table.insert(sources_listbox, string.format("\a%s+  Create local", ui.get_style("Link Active"):to_hex()))
            table.insert(sources_list, "add_local")
            if source_selected == "add_local" then
                sources_listbox_i = #sources_list
            end

            if sources_listbox_i == nil then
                source_selected = sources_list[1]
                sources_listbox_i = 1
            end

            sources_list_ui.list:update(sources_listbox)
            if sources_listbox_i ~= nil then
                sources_list_ui.list:set(sources_listbox_i)
            end

            ui_visibility[sources_list_ui.list] = true
            if source_selected ~= nil then
                ui_visibility[sources_list_ui.source_label1] = true

                if source_selected == "add_remote" then
                    sources_list_ui.source_label1:set("Add new remote source")
                    ui_visibility[sources_list_ui.import] = true

                    if source_remote_add_status ~= nil then
                        sources_list_ui.source_label4:set(source_remote_add_status)
                        ui_visibility[sources_list_ui.source_label4] = true
                    end
                elseif source_selected == "add_local" then
                    ui_visibility[sources_list_ui.source_label1] = false
                    ui_visibility[sources_list_ui.name] = true
                    ui_visibility[sources_list_ui.create] = true
                elseif source_selected ~= nil then
                    ui_visibility[sources_list_ui.enabled] = true
                    ui_visibility[sources_list_ui.edit] = source_selected.type == "local" and not source_selected.builtin
                    ui_visibility[sources_list_ui.update] = source_selected.type == "remote"
                    ui_visibility[sources_list_ui.delete] = not source_selected.builtin

                    sources_ignore_callback = true

                    sources_list_ui.source_label1:set(
                        string.format(
                            "\a%s%s source: \a%s%s",
                            ui.get_style("Active Text"):to_hex(),
                            SOURCE_TYPE_NAMES[source_selected.type] or source_selected.type,
                            ui.get_style("Link Active"):to_hex(),
                            source_selected.name
                        )
                    )

                    if source_selected.description ~= nil then
                        ui_visibility[sources_list_ui.source_label2] = true
                        sources_list_ui.source_label2:set(string.format("\a%s%s\n", ui.get_style("Active Text"):to_hex(), source_selected.description))
                    end

                    if source_selected.remote_status ~= nil then
                        ui_visibility[sources_list_ui.source_label3] = true
                        sources_list_ui.source_label3:set(source_selected.remote_status)
                    elseif source_selected.update_timestamp ~= nil then
                        ui_visibility[sources_list_ui.source_label3] = true
                        -- format_unix_timestamp(timestamp, allow_future, ignore_seconds, max_parts)
                        sources_list_ui.source_label3:set(
                            string.format(
                                "\a%sLast updated: \a%s%s",
                                ui.get_style("Active Text"):to_hex(),
                                ui.get_style("Link Active"):to_hex(),
                                format_unix_timestamp(source_selected.update_timestamp, false, false, 1)
                            )
                        )
                    end

                    sources_list_ui.enabled:set(sources_config.enabled[source_selected.id] == true)

                    sources_ignore_callback = false
                end
            end
        end
    end

    for reference, visible in pairs(ui_visibility) do
        reference:visibility(visible)
    end
end

sources_list_ui.title:set_callback(
    function()
        if not sources_list_ui.title:get() then
            source_editing = false
        end

        update_sources_ui()
    end
)

sources_list_ui.list:set_callback(
    function()
        local source_selected_prev = source_selected
        local i = sources_list_ui.list:get()

        if i ~= nil then
            source_selected = sources_list[i]

            if source_selected ~= source_selected_prev then
                source_editing = false
                source_remote_add_status = nil
                update_sources_ui()
            end
        -- else
        -- 	error("ui.get on listbox returned nil!")
        end
    end
)

sources_list_ui.enabled:set_callback(
    function()
        if type(source_selected) == "table" and not sources_ignore_callback then
            local sources_config = get_sources_config()
            sources_config.enabled[source_selected.id] = sources_list_ui.enabled:get()
            set_sources_config(sources_config)
            update_sources_ui()

            flush_active_locations("D")
        end
    end
)

select_reference:set_callback(flush_active_locations)

edit_ui.show_all:set_callback(
    function()
        update_sources_ui()
    end
)
edit_ui.sort_by:set_callback(
    function()
        update_sources_ui()
    end
)

local url_fixers = {
    -- transform pastebin to raw urls
    function(url)
        local match = url:match("^https://pastebin.com/(%w+)/?$")

        if match ~= nil then
            return string.format("https://pastebin.com/raw/%s", match)
        end
    end,
    -- transform github to raw urls
    function(url)
        local user, repo, branch, path = url:match("^https://github.com/(%w+)/(%w+)/blob/(%w+)/(.+)$")

        if user ~= nil then
            return string.format("https://github.com/%s/%s/raw/%s/%s", user, repo, branch, path)
        end
    end
}

function on_source_delete()
    if type(source_selected) == "table" and not source_selected.builtin then
        -- remove from db
        for i = 1, #db.sources do
            if db.sources[i] == source_selected then
                table.remove(db.sources, i)
                break
            end
        end

        -- remove from config - handled by get_sources_config() fixup
        set_sources_config(get_sources_config())

        -- update ingame
        flush_active_locations("source deleted")

        set_source_selected()
    end
end

function on_source_update()
    if type(source_selected) == "table" and source_selected.type == "remote" then
        source_selected:update_remote_data()
        update_sources_ui()
    end
end

function on_source_create()
    if source_selected == "add_local" then
        local name = sources_list_ui.name:get()

        if name:gsub(" ", "") == "" then
            return
        end

        -- append (1), (2) etc if local source with same name exists
        local existing_names =
            table_map_assoc(
            db.sources,
            function(_, source)
                return source.name, source.type == "local"
            end
        )
        local name_new, i = name, 2

        while existing_names[name_new] do
            name_new = string.format("%s (%d)", name, i)
            i = i + 1
        end

        name = name_new

        -- actually add source to db etc
        local source = add_source(name, "local")

        -- update ui to add it to listbox, then set it as selected source
        update_sources_ui()
        set_source_selected(source)
        sources_list_ui.name:set("")
    end
end

local function source_import_arr(tbl, mapname)
    local locations = {}
    for i = 1, #tbl do
        local location = create_location(tbl[i])
        if type(location) ~= "table" then
            local err = string.format("invalid location #%d: %s", i, location)
            print_raw("\a4B69FF[neverlose]\aFF4040\x20Failed to import " .. tostring(mapname) .. ", " .. err)
            source_remote_add_status = err
            update_sources_ui()
            return
        end
        locations[i] = location
    end

    if #locations == 0 then
        print_raw("\a4B69FF[neverlose]\aFF4040\x20Failed to import: No locations to import")
        source_remote_add_status = "No locations to import"
        update_sources_ui()
        return
    end

    local source_locations = source_selected:get_locations(mapname)
    if source_locations == nil then
        source_locations = {}
        sources_locations[source_selected][mapname] = source_locations
    end

    for i = 1, #locations do
        table.insert(source_locations, locations[i])
    end

    update_sources_ui()
    source_selected:store_write()
    flush_active_locations()
end

function on_source_import()
    if source_editing and type(source_selected) == "table" and source_selected.type == "local" then
        -- import data into source
        local text = clipboard.get()

        if text == nil then
            local err = "No text copied to clipboard"
            print_raw("\a4B69FF[neverlose]\aFF4040\x20Failed to import: " .. err)
            source_remote_add_status = err
            update_sources_ui()
            return
        end

        local success, tbl = pcall(json.parse, text)

        if success and text:sub(1, 1) ~= "[" and text:sub(1, 1) ~= "{" then
            success, tbl = false, "Expected object or array"
        end

        if not success then
            local err = string.format("Invalid JSON: %s", tbl)
            print_raw("\a4B69FF[neverlose]\aFF4040\x20Failed to import: " .. err)
            source_remote_add_status = err
            update_sources_ui()
            return
        end

        -- heuristics to determine if its a location or an array of locations
        local is_arr = text:sub(1, 1) == "["

        if not is_arr then
            -- heuristics to determine if its a table of mapname -> locations or a single location
            if tbl["name"] ~= nil or tbl["grenade"] ~= nil or tbl["location"] ~= nil then
                tbl = {tbl}
                is_arr = true
            end
        end

        if is_arr then
            local mapname = get_mapname()

            if mapname == nil then
                print_raw("\a4B69FF[neverlose]\aFF4040\x20Failed to import: You need to be in-game")
                source_remote_add_status = "You need to be in-game"
                update_sources_ui()
                return
            end

            source_import_arr(tbl, mapname)
        else
            for mapname, _ in pairs(tbl) do
                if type(mapname) ~= "string" or mapname:find(" ") then
                    print_raw("\a4B69FF[neverlose]\aFF4040\x20Failed to import: Invalid map name")
                    source_remote_add_status = "Invalid map name"
                    update_sources_ui()
                    return
                end
            end

            for mapname, locations in pairs(tbl) do
                source_import_arr(locations, mapname)
            end
        end
    elseif source_selected == "add_remote" then
        -- add new remote source
        local text = clipboard.get()
        if text == nil then
            print_raw("\a4B69FF[neverlose]\aFF4040\x20Failed to import: Clipboard is empty")
            source_remote_add_status = "Clipboard is empty"
            update_sources_ui()
            return
        end

        local url = text:gsub("[%c]", ""):gsub(" ", "")

        if not url:match("^https?://.+$") then
            print_raw("\a4B69FF[neverlose]\aFF4040\x20Failed to import: Invalid URL")
            source_remote_add_status = "Invalid URL"
            update_sources_ui()
            return
        end

        for i = 1, #url_fixers do
            url = url_fixers[i](url) or url
        end

        for i = 1, #db.sources do
            local source = db.sources[i]
            if source.type == "remote" and source.url == url then
                print_raw("\a4B69FF[neverlose]\aFF4040\x20Failed to import: A source with that URL already exists")
                source_remote_add_status = "A source with that URL already exists"
                update_sources_ui()
                return
            end
        end

        source_remote_add_status = "Loading index data..."
        update_sources_ui()
        source_get_index_data(
            url,
            function(err, data)
                if source_selected ~= "add_remote" then
                    return
                end

                if err ~= nil then
                    print_raw(string.format("\a4B69FF[neverlose]\aFF4040\x20Failed to import: %s", err))
                    source_remote_add_status = err
                    update_sources_ui()
                    return
                end
                local source = add_source(data.name, "remote")

                source.url = data.url or url
                source.url_format = data.url_format
                source.description = data.description
                source.update_timestamp = data.update_timestamp
                source.last_updated = data.last_updated

                source_remote_add_status = string.format("Successfully imported %s", source.name)
                update_sources_ui()

                source_selected = nil
                set_source_selected("add_remote")
                update_sources_ui()
            end
        )
    end
end

function on_source_export()
    if source_editing and type(source_selected) == "table" and source_selected.type == "local" then
        local indent = "  "
        local mapname = get_mapname()
        local show_all = edit_ui.show_all:get()

        -- if we're not ingame show all locations
        if mapname == nil then
            show_all = true
        end

        local export_str
        if show_all then
            local all_locations = source_selected:get_all_locations()

            local maps = {}
            for map, _ in pairs(all_locations) do
                table.insert(maps, map)
            end
            table.sort(maps)

            local tbl = {}
            for i = 1, #maps do
                local map = maps[i]
                local locations = all_locations[map]
                local tbl_map = {}
                for i = 1, #locations do
                    local str = locations[i]:get_export(true)
                    table.insert(tbl_map, indent .. (str:gsub("\n", "\n" .. indent .. indent)))
                end

                table.insert(tbl, json.stringify(map) .. ": [\n" .. indent .. table.concat(tbl_map, ",\n" .. indent) .. "\n" .. indent .. "]")
            end

            export_str = "{\n" .. indent .. table.concat(tbl, ",\n" .. indent) .. "\n}"
        else
            local locations = source_selected:get_locations(mapname)

            local tbl = {}
            for i = 1, #locations do
                tbl[i] = locations[i]:get_export(true):gsub("\n", "\n" .. indent)
            end

            export_str = "[\n" .. indent .. table.concat(tbl, ",\n" .. indent) .. "\n]"
        end

        if export_str ~= nil then
            clipboard.set(export_str)
            print("Exported location (Copied to clipboard):")
            pretty_json.print_highlighted(export_str)
        end
    end
end

local function edit_update_has_changed()
    if source_editing and edit_location_selected ~= nil and source_editing_modified[edit_location_selected] ~= nil then
        if type(edit_location_selected) == "table" then
            local old = edit_location_selected:get_export_tbl()
            source_editing_has_changed[edit_location_selected] = not deep_compare(old, source_editing_modified[edit_location_selected])
        else
            source_editing_has_changed[edit_location_selected] = true
        end
    end

    return source_editing_has_changed[edit_location_selected] == true
end

function edit_set_ui_values(force)
    local location_tbl = {}
    if source_editing and edit_location_selected ~= nil and source_editing_modified[edit_location_selected] ~= nil then
        location_tbl = source_editing_modified[edit_location_selected]
    end

    if edit_different_map_selected and not force then
        location_tbl = {}
    end

    local yaw_to_name =
        table_map_assoc(
        YAW_DIRECTION_OFFSETS,
        function(k, v)
            return v, k
        end
    )

    edit_ignore_callbacks = true
    edit_ui.from:set(location_tbl.name and location_tbl.name[1] or "")
    edit_ui.to:set(location_tbl.name and location_tbl.name[2] or "")
    edit_ui.grenade_properties:set({})

    edit_ui.description:set(location_tbl.description or "")

    if edit_different_map_selected then
        edit_ui.type_label:set(string.format("\a%sCan't edit location on a different map", ui.get_style("Active Text"):to_hex()))
    else
        edit_ui.type_label:set(
            edit_location_selected == "create_new" and "Creating new location" or
                string.format(
                    "\a%sEditing %s to %s",
                    ui.get_style("Active Text"):to_hex(),
                    location_tbl.name and location_tbl.name[1] or "Unnamed",
                    location_tbl.name and location_tbl.name[2] or "Unnamed"
                )
        )
    end

    if location_tbl.grenade ~= nil then
        edit_ui.type:set("Grenade")

        edit_ui.recovery_direction:set(yaw_to_name[180])
        edit_ui.recovery_direction_custom:set(0)
        edit_ui.recovery_jump:set(false)

        edit_ui.run_duration:set(20)
        edit_ui.run_direction:set(yaw_to_name[0])
        edit_ui.run_direction_custom:set(0)
        edit_ui.delay:set(1)

        local properties = {}
        if location_tbl.grenade.jump then
            table.insert(properties, "Jump")
        end

        if location_tbl.grenade.recovery_yaw ~= nil then
            if not location_tbl.grenade.jump then
                table.insert(properties, "Force-enable recovery")
            end

            if yaw_to_name[location_tbl.grenade.recovery_yaw] ~= nil then
                edit_ui.recovery_direction:set(yaw_to_name[location_tbl.grenade.recovery_yaw])
            else
                edit_ui.recovery_direction:set("Custom")
                edit_ui.recovery_direction_custom:set(location_tbl.grenade.recovery_yaw)
            end
        end

        if location_tbl.grenade.recovery_jump then
            edit_ui.recovery_jump:set(true)
        end

        if location_tbl.grenade.strength ~= nil and location_tbl.grenade.strength ~= 1 then
            table.insert(properties, "Throw strength")

            edit_ui.throw_strength:set(location_tbl.grenade.strength == 0.5 and "Left / Right Click" or "Left Click")
        end

        if location_tbl.grenade.delay ~= nil then
            table.insert(properties, "Delayed throw")
            edit_ui.delay:set(location_tbl.grenade.delay)
        end

        if location_tbl.grenade.run ~= nil then
            table.insert(properties, "Run")

            if location_tbl.grenade.run ~= 20 then
                edit_ui.run_duration:set(location_tbl.grenade.run)
            end

            if location_tbl.grenade.run_yaw ~= nil then
                if yaw_to_name[location_tbl.grenade.run_yaw] ~= nil then
                    edit_ui.run_direction:set(yaw_to_name[location_tbl.grenade.run_yaw])
                else
                    edit_ui.run_direction:set("Custom")
                    edit_ui.run_direction_custom:set(location_tbl.grenade.run_yaw)
                end
            end

            if location_tbl.grenade.run_speed then
                table.insert(properties, "Walk (Shift)")
            end
        end

        edit_ui.grenade_properties:set(properties)
    elseif location_tbl.movement ~= nil then
        edit_ui.type:set("Movement")
    else
        edit_ui.grenade_properties:set({})
    end

    edit_ignore_callbacks = false
end

local function edit_read_ui_values()
    if edit_ignore_callbacks or edit_different_map_selected then
        return
    end

    if source_editing and source_editing_modified[edit_location_selected] == nil then
        -- print_raw("is nil!")
        if edit_location_selected == "create_new" then
            -- creating new location
            -- source_editing_modified[edit_location_selected] = {}
            -- print_raw("created new!")
        elseif edit_location_selected ~= nil then
            -- editing existing location
            source_editing_modified[edit_location_selected] = edit_location_selected:get_export_tbl()
            edit_set_ui_values()

        -- print_raw("cloned!")
        end
    end

    if source_editing and edit_location_selected ~= nil and source_editing_modified[edit_location_selected] ~= nil then
        local location = source_editing_modified[edit_location_selected]

        -- todo: get location names here
        local from = edit_ui.from:get()
        if from:gsub(" ", "") == "" then
            from = "Unnamed"
        end

        local to = edit_ui.to:get()
        if to:gsub(" ", "") == "" then
            to = "Unnamed"
        end

        location.name = {from, to}

        local description = edit_ui.description:get()
        if description:gsub(" ", "") ~= "" then
            location.description = description:gsub("^%s+", ""):gsub("%s+$", "")
        else
            location.description = nil
        end

        location.grenade = location.grenade or {}
        local properties =
            table_map_assoc(
            edit_ui.grenade_properties:get(),
            function(_, property)
                return property, true
            end
        )

        if properties["Jump"] then
            location.grenade.jump = true
        else
            location.grenade.jump = nil
        end

        if properties["Jump"] or properties["Force-enable recovery"] then
            -- print("saved: ", location.grenade.recovery_yaw)
            -- figure out recovery_yaw
            local recovery_yaw_offset
            local recovery_yaw_option = edit_ui.recovery_direction:get()

            if recovery_yaw_option == "Custom" then
                recovery_yaw_offset = edit_ui.recovery_direction_custom:get()

                if recovery_yaw_offset == -180 then
                    recovery_yaw_offset = 180
                end
            else
                recovery_yaw_offset = YAW_DIRECTION_OFFSETS[recovery_yaw_option]
            end

            location.grenade.recovery_yaw = (recovery_yaw_offset ~= nil and recovery_yaw_offset ~= 180) and recovery_yaw_offset or (not properties["Jump"] and 180 or nil)
            location.grenade.recovery_jump = edit_ui.recovery_jump:get() and true or nil
        else
            location.grenade.recovery_yaw = nil
            location.grenade.recovery_jump = nil
        end

        if properties["Run"] then
            location.grenade.run = edit_ui.run_duration:get()

            -- figure out run_yaw_offset
            local run_yaw_offset
            local run_yaw_option = edit_ui.run_direction:get()
            if run_yaw_option == "Custom" then
                run_yaw_offset = edit_ui.run_direction_custom:get()
            else
                run_yaw_offset = YAW_DIRECTION_OFFSETS[run_yaw_option]
            end

            location.grenade.run_yaw = (run_yaw_offset ~= nil and run_yaw_offset ~= 0) and run_yaw_offset or nil

            if properties["Walk (Shift)"] then
                location.grenade.run_speed = true
            else
                location.grenade.run_speed = nil
            end
        else
            location.grenade.run = nil
            location.grenade.run_yaw = nil
            location.grenade.run_speed = nil
        end

        if properties["Delayed throw"] then
            location.grenade.delay = edit_ui.delay:get()
        else
            location.grenade.delay = nil
        end

        if properties["Throw strength"] then
            local strength = edit_ui.throw_strength:get()
            if strength == "Left / Right Click" then
                location.grenade.strength = 0.5
            elseif strength == "Right Click" then
                location.grenade.strength = 0
            else
                location.grenade.strength = nil
            end
        else
            location.grenade.strength = nil
        end

        if location.grenade ~= nil and next(location.grenade) == nil then
            location.grenade = nil
        end

        if edit_update_has_changed() then
            flush_active_locations("edit_update_has_changed")
        end
    end
    update_sources_ui()
end

edit_ui.grenade_properties:set_callback(edit_read_ui_values)
edit_ui.run_direction:set_callback(edit_read_ui_values)
edit_ui.run_direction_custom:set_callback(edit_read_ui_values)
edit_ui.run_duration:set_callback(edit_read_ui_values)
edit_ui.recovery_direction:set_callback(edit_read_ui_values)
edit_ui.recovery_direction_custom:set_callback(edit_read_ui_values)
edit_ui.recovery_jump:set_callback(edit_read_ui_values)
edit_ui.delay:set_callback(edit_read_ui_values)
edit_ui.throw_strength:set_callback(edit_read_ui_values)

utils.execute_after(0, update_sources_ui)

function on_source_edit()
    if type(source_selected) == "table" and source_selected.type == "local" and not source_selected.builtin then
        source_editing = true
        update_sources_ui()
        flush_active_locations("on_source_edit")
    end
end

function on_source_edit_back()
    source_editing = false
    edit_location_selected = nil

    table_clear(source_editing_modified)
    table_clear(source_editing_has_changed)

    flush_active_locations("on_source_edit_back")
    update_sources_ui()
end

function on_edit_teleport()
    if not edit_different_map_selected and edit_location_selected ~= nil and (edit_location_selected == "create_new" or source_editing_modified[edit_location_selected] ~= nil) then
        if cvar.sv_cheats:int() == 0 then
            return
        end

        local location = source_editing_modified[edit_location_selected]

        if location ~= nil then
            utils.console_exec(("use %s; setpos_exact %f %f %f"):format(location.weapon, unpack(location.position)))
            render.camera_angles(vector(unpack(location.viewangles)))

            utils.execute_after(
                0.1,
                function()
                    local local_player = entity.get_local_player()
                    if local_player ~= nil and local_player["m_MoveType"] == 8 then
                        local x, y, z = unpack(location.position)
                        utils.console_exec(("noclip off; setpos_exact %f %f %f"):format(x, y, z + 64))
                    end
                end
            )
        end
    end
end

function on_edit_set()
    if not edit_different_map_selected and edit_location_selected ~= nil then
        if source_editing_modified[edit_location_selected] == nil then
            source_editing_modified[edit_location_selected] = {}
            edit_read_ui_values()
        end

        local local_player = entity.get_local_player()
        local weapon_ent = local_player:get_player_weapon()
        local weapon = weapons[weapon_ent:get_weapon_index()]

        weapon = WEAPON_ALIASES[weapon] or weapon

        local location = source_editing_modified[edit_location_selected]

        location.position = {local_player:get_origin():unpack()}

        local camera = render.camera_angles()
        location.viewangles = {camera.x, camera.y}

        local duckamount = local_player["m_flDuckAmount"]
        if duckamount ~= 0 then
            location.duck = local_player["m_flDuckAmount"] == 1
        else
            location.duck = nil
        end
        location.weapon = weapon.console_name

        -- if weapon.type == "grenade" then
        -- 	local throw_strength = weapon_ent["m_flThrowStrength"]

        -- 	if throw_strength ~= 1 then
        -- 		location.grenade = location.grenade or {}

        -- 		if throw_strength == 0 then
        -- 			location.grenade.strength = 0
        -- 		else
        -- 			location.grenade.strength = 0.5
        -- 		end
        -- 	elseif location.grenade ~= nil then
        -- 		location.grenade.strength = nil
        -- 	end

        -- 	if location.grenade ~= nil and next(location.grenade) == nil then
        -- 		location.grenade = nil
        -- 	end
        -- end

        if edit_update_has_changed() then
            flush_active_locations("edit_update_has_changed")
        end
    end
end

function on_edit_save()
    if not edit_different_map_selected and edit_location_selected ~= nil and source_editing_modified[edit_location_selected] ~= nil then
        -- print("saving to ", edit_location_selected)

        local location = create_location(source_editing_modified[edit_location_selected])

        if type(location) ~= "table" then
            print_raw("\a4B69FF[neverlose]\aFF4040\x20Failed to save: " .. location)
            return
        end

        local mapname = get_mapname()

        if mapname == nil then
            return
        end

        local source_locations = sources_locations[source_selected][mapname]
        if source_locations == nil then
            source_locations = {}
            sources_locations[source_selected][mapname] = source_locations
        end
        if edit_location_selected == "create_new" then
            table.insert(source_locations, location)
            source_selected:store_write()
            flush_active_locations()

            edit_location_selected = location
            source_editing_modified[edit_location_selected] = source_editing_modified["create_new"]
            source_editing_modified["create_new"] = nil
        elseif type(edit_location_selected) == "table" then
            -- replace in sources_locations
            for i = 1, #source_locations do
                if source_locations[i] == edit_location_selected then
                    -- migrate changes to new location
                    source_editing_modified[location] = source_editing_modified[source_locations[i]]
                    source_editing_modified[source_locations[i]] = nil
                    edit_location_selected = location

                    -- replace location
                    source_locations[i] = location

                    source_selected:store_write()
                    flush_active_locations()
                    break
                end
            end
        end

        -- -- flush to disk rn to make sure we dont lose data on game crash
        -- database.flush()

        edit_set_ui_values()

        update_sources_ui()
        flush_active_locations()
    end
end

function on_edit_export()
    if type(edit_location_selected) == "table" or source_editing_modified[edit_location_selected] ~= nil then
        local location = create_location(source_editing_modified[edit_location_selected]) or edit_location_selected

        if type(location) == "table" then
            local export_str = location:get_export(true)

            clipboard.set(export_str)
            print("Exported location (Copied to clipboard):")
            pretty_json.print_highlighted(export_str)
        else
            print_raw("\a4B69FF[neverlose]\aFF4040\x20" .. location)
        end
    end
end

function on_edit_delete()
    if not edit_different_map_selected and edit_location_selected ~= nil and type(edit_location_selected) == "table" then
        local mapname = get_mapname()
        if mapname == nil then
            return
        end

        local source_locations = sources_locations[source_selected][mapname]

        for i = 1, #source_locations do
            if source_locations[i] == edit_location_selected then
                table.remove(source_locations, i)
                source_editing_modified[edit_location_selected] = nil
                edit_location_selected = nil
                update_sources_ui()
                source_selected:store_write()
                -- database.flush()
                flush_active_locations()
                break
            end
        end
    end
end

edit_ui.list:set_callback(
    function()
        local edit_location_selected_prev = edit_location_selected
        local i = edit_ui.list:get()

        if i ~= nil then
            edit_location_selected = edit_list[i]
        else
            -- error("ui.get on edit listbox returned nil!")
            edit_location_selected = "create_new"
        end

        -- print_raw("prev: ", tostring(edit_location_selected_prev))
        -- print_raw("cur: ", tostring(edit_location_selected))

        update_sources_ui()
        if edit_location_selected ~= edit_location_selected_prev and not edit_different_map_selected then
            -- print_raw("edit_location_selected changed to ", tostring(edit_location_selected))

            if type(edit_location_selected) == "table" and source_editing_modified[edit_location_selected] == nil then
                -- clone location
                source_editing_modified[edit_location_selected] = edit_location_selected:get_export_tbl()
            end

            edit_set_ui_values()
            update_sources_ui()
            flush_active_locations()
        elseif edit_location_selected ~= edit_location_selected_prev then
            edit_set_ui_values()
        end
    end
)

update_sources_ui()
utils.execute_after(0, update_sources_ui)

local last_vischeck, weapon_prev, active_locations_in_range = 0, nil, nil
local location_set_closest, location_selected, location_playback

local ICON_EDIT = images.get_panorama_image("icons/ui/edit.svg")
local ICON_WARNING = images.get_panorama_image("icons/ui/warning.svg")

local function on_paint_editing()
    local location = source_editing_modified[edit_location_selected]
    if location ~= nil then
        -- todo: get location names here
        local from = edit_ui.from:get()
        local to = edit_ui.to:get()

        if from:gsub(" ", "") == "" then
            from = "Unnamed"
        end

        if to:gsub(" ", "") == "" then
            to = "Unnamed"
        end

        if (from ~= location.name[1]) or (to ~= location.name[2]) then
            edit_read_ui_values()
        end

        local description = edit_ui.description:get()
        if description:gsub(" ", "") ~= "" then
            description = description:gsub("^%s+", ""):gsub("%s+$", "")
        else
            description = nil
        end

        if location.description ~= description then
            edit_read_ui_values()
        end

        local location_orig = type(edit_location_selected) == "table" and edit_location_selected:get_export_tbl() or {}
        local location_orig_flattened = deep_flatten(location_orig, true)

        local has_changes = source_editing_has_changed[edit_location_selected]
        local key_values = deep_flatten(location, true)
        local key_values_arr = {}
        for key, value in pairs(key_values) do
            local changed = false
            local val_new = json.stringify(value)

            if has_changes then
                local val_old = json.stringify(location_orig_flattened[key])

                changed = val_new ~= val_old
            end

            local val_new_fancy =
                pretty_json.highlight(
                val_new,
                changed and {244, 147, 134} or {221, 221, 221},
                changed and {223, 57, 35} or {218, 230, 30},
                changed and {209, 42, 62} or {180, 230, 30},
                changed and {209, 42, 62} or {96, 160, 220}
            )
            local text_new = ""
            for i = 1, #val_new_fancy do
                local r, g, b, text = unpack(val_new_fancy[i])
                text_new = text_new .. string.format("\a%02X%02X%02XFF%s", r, g, b, text)
            end

            table.insert(key_values_arr, {key, text_new, changed})
        end

        local lookup = {
            name = "\1",
            weapon = "\2",
            position = "\3",
            viewangles = "\4"
        }
        table.sort(
            key_values_arr,
            function(a, b)
                return (lookup[b[1]] or b[1]) > (lookup[a[1]] or a[1])
            end
        )

        local lines = {
            {{ICON_EDIT, 0, 0, 12, 12}, color(255, 220), "", " Editing Location:"}
        }

        for i = 1, #key_values_arr do
            local key, value, changed = unpack(key_values_arr[i])

            table.insert(lines, {color(255, 220), "", key, ": ", changed and "\aF21A3EFF" or "\aFFFFFFDC", value})
        end

        local size_prev = #lines
        if has_changes then
            table.insert(lines, {{ICON_WARNING, 0, 0, 12, 12, 255, 54, 0, 255}, color(234, 64, 18, 220), "", "You have unsaved changes! Make sure to click save."})
        end

        local weapon = weapons[location.weapon]

        if weapon.type == "grenade" then
            local select_enabled =
                table_map_assoc(
                select_reference:get(),
                function(_, typ)
                    return typ, true
                end
            )
            local weapon_name = GRENADE_WEAPON_NAMES_UI[weapon]
            if not select_enabled[weapon_name] then
                table.insert(lines, {{ICON_WARNING, 0, 0, 12, 12, 255, 54, 0, 255}, color(234, 64, 18, 220), "", 'Location not shown because type "' .. tostring(weapon_name) .. '" is not enabled.'})
            end
        end

        local sources_config = get_sources_config()

        if source_selected ~= nil and not sources_config.enabled[source_selected.id] then
            table.insert(
                lines,
                {
                    {ICON_WARNING, 0, 0, 12, 12, 255, 54, 0, 255},
                    color(234, 64, 18, 220),
                    "s",
                    'Location not shown because source "' .. tostring(source_selected.name) .. '" is not enabled.'
                }
            )
        end

        if #lines > size_prev then
            table.insert(lines, size_prev + 1, {color(255, 0), "", " "})
        end

        local line_size, line_y = vector(), {}
        for i = 1, #lines do
            local line = lines[i]
            local has_icon = type(line[1]) == "table"
            local w, h = render.measure_text(1, select(has_icon and 3 or 2, unpack(line))):unpack()

            if has_icon then
                w = w + line[1][4]
            end

            if w > line_size.x then
                line_size.x = w
            end

            line_y[i] = line_size.y
            line_size.y = line_size.y + h

            if i == 1 then
                line_size.y = line_size.y + 2
            end
        end

        local screen_size = render.screen_size()
        local begin = vector(screen_size.x / 2 - math.floor(line_size.x / 2) - 1, 140)
        local endl = begin + line_size + vector(1)

        -- draw background
        render.rect(begin - 3, endl + 3, color(16, 150 * 0.7))
        render.rect_outline(begin - 4, endl + 4, color(16, 170 * 0.7))
        render.rect_outline(begin - 5, endl + 5, color(16, 195 * 0.7))
        render.rect_outline(begin - 6, endl + 6, color(16, 40 * 0.7))

        ICON_EDIT:draw(begin.x, begin.y, 12, 12)
        render.rect(begin + vector(15), begin + vector(16, 12), color())

        for i = 1, #lines do
            local line = lines[i]
            local has_icon = type(line[1]) == "table"

            local icon, ix, iy, iw, ih, ir, ig, ib, ia
            if has_icon then
                icon, ix, iy, iw, ih, ir, ig, ib, ia = unpack(line[1])
                icon:draw(begin.x + ix, begin.y + iy + line_y[i], iw, ih, ir, ig, ib, ia)
            end

            render.text(1, begin + vector((iw or -3) + 3, line_y[i]), select(has_icon and 2 or 1, unpack(lines[i])))
        end
    end
end

local function populate_map_locations(local_player, weapon)
    map_locations[weapon] = {}
    active_locations = map_locations[weapon]

    local tickrate = 1 / globals.tickinterval
    local mapname = get_mapname()
    local sources_config = get_sources_config()

    local select_enabled =
        table_map_assoc(
        select_reference:get(),
        function(_, typ)
            return typ, true
        end
    )

    -- collect enabled sources
    for i = 1, #db.sources do
        local source = db.sources[i]
        if sources_config.enabled[source.id] then
            -- fetch sources if we dont have them
            local source_locations = source:get_locations(mapname, true)

            local editing_current_source = source_editing and source_selected == source

            -- are we editing this source?
            if editing_current_source then
                local source_locations_new = {}

                -- print("editing_current_source!")
                -- print(tostring(edit_location_selected))

                for i = 1, #source_locations do
                    if source_locations[i] == edit_location_selected and source_editing_modified[source_locations[i]] == nil then
                    -- print("source_editing_modified[source_locations[i]] is nil")
                    end

                    if source_locations[i] == edit_location_selected and source_editing_modified[source_locations[i]] ~= nil then
                        local location = create_location(source_editing_modified[source_locations[i]])

                        -- print("create!")

                        if type(location) == "table" then
                            location.editing = source_editing and source_editing_has_changed[source_locations[i]]
                            source_locations_new[i] = location
                        else
                            print_raw("\a4B69FF[neverlose]\aFF4040\x20Failed to initialize editing location: " .. tostring(location))
                        end
                    else
                        source_locations_new[i] = source_locations[i]
                    end
                end

                if edit_location_selected == "create_new" and source_editing_modified["create_new"] ~= nil then
                    local location = create_location(source_editing_modified[edit_location_selected])

                    if type(location) == "table" then
                        location.editing = source_editing and source_editing_has_changed[edit_location_selected]
                        table.insert(source_locations_new, location)
                    else
                        print_raw("\a4B69FF[neverlose]\aFF4040\x20Failed to initialize new editing location: " .. tostring(location))
                    end
                end

                source_locations = source_locations_new
            end

            -- first create table of position_id -> locations
            for i = 1, #source_locations do
                local location = source_locations[i]

                local include = false
                if location.type == "grenade" then
                    if location.tickrates[tickrate] ~= nil then
                        for i = 1, #location.weapons do
                            local weapon_name = GRENADE_WEAPON_NAMES_UI[location.weapons[i]]
                            if select_enabled[weapon_name] then
                                include = true
                            end
                        end
                    end
                elseif location.type == "movement" then
                    if select_enabled["Movement"] then
                        include = true
                    end
                else
                    error("not yet implemented: " .. location.type)
                end

                if include and location.weapons_assoc[weapon] then
                    local location_set = active_locations[location.position_id]
                    if location_set == nil then
                        location_set = {
                            position = location.position,
                            position_approach = location.position,
                            position_visibility = location.position_visibility,
                            visible_alpha = 0,
                            distance_alpha = 0,
                            distance_width_mp = 0,
                            in_range_draw_mp = 0,
                            position_world_bottom = location.position + POSITION_WORLD_OFFSET
                        }
                        active_locations[location.position_id] = location_set
                    end

                    location.in_fov_select_mp = 0
                    location.in_fov_mp = 0
                    location.on_screen_mp = 0
                    table.insert(location_set, location)

                    location.set = location_set

                    -- if this location has a custom position_visibility, it overrides the location set's one
                    if location.position_visibility_different then
                        location_set.position_visibility = location.position_visibility
                    end

                    if location.duckamount ~= 1 then
                        location_set.has_only_duck = false
                    elseif location.duckamount == 1 and location_set.has_only_duck == nil then
                        location_set.has_only_duck = true
                    end

                    -- if this location has approach_accurate set, set it for the whole location set
                    if location.approach_accurate ~= nil then
                        if location_set.approach_accurate == nil or location_set.approach_accurate == location.approach_accurate then
                            location_set.approach_accurate = location.approach_accurate
                        else
                            -- todo: better warning here
                            print_raw("\a4B69FF[neverlose]\aFF4040\x20approach_accurate conflict found")
                        end
                    end
                end
            end
        end
    end

    -- combines nearby positions
    local count = 0

    for key, _ in pairs(active_locations) do
        if key > count then
            count = key
        end
    end

    for position_id_1 = 1, count do
        local locations_1 = active_locations[position_id_1]

        -- can be nil if location was already merged
        if locations_1 ~= nil then
            local pos_1 = locations_1.position

            -- loop from current index to end, to avoid checking locations we already checked (just different order)
            for position_id_2 = position_id_1 + 1, count do
                local locations_2 = active_locations[position_id_2]

                -- can be nil if location was already merged
                if locations_2 ~= nil then
                    local pos_2 = locations_2.position

                    if pos_1:distsqr(pos_2) < MAX_DIST_COMBINE_SQR then
                        -- the position with more locations is seen as the main one
                        -- the other one is deleted and all locations are inserted into the main one
                        local main = #locations_2 > #locations_1 and position_id_2 or position_id_1
                        local other = main == position_id_1 and position_id_2 or position_id_1

                        -- copy over locations
                        local main_locations = active_locations[main]
                        local other_locations = active_locations[other]

                        if main_locations ~= nil and other_locations ~= nil then
                            local main_count = #main_locations
                            for i = 1, #other_locations do
                                local location = other_locations[i]
                                main_locations[main_count + i] = location

                                location.set = main_locations

                                if location.duckamount ~= 1 then
                                    main_locations.has_only_duck = false
                                elseif location.duckamount == 1 and main_locations.has_only_duck == nil then
                                    main_locations.has_only_duck = true
                                end
                            end

                            -- print("combining:")
                            -- print(inspect(main_locations))
                            -- print(inspect(other_locations))

                            -- recompute location.position from location.positions
                            local sum_x, sum_y, sum_z = 0, 0, 0
                            local new_len = #main_locations
                            for i = 1, new_len do
                                local position = main_locations[i].position
                                sum_x = sum_x + position.x
                                sum_y = sum_y + position.y
                                sum_z = sum_z + position.z
                            end
                            main_locations.position = vector(sum_x / new_len, sum_y / new_len, sum_z / new_len)
                            main_locations.position_world_bottom = main_locations.position + POSITION_WORLD_OFFSET

                            -- delete other
                            active_locations[other] = nil
                        end
                    end
                end
            end
        end
    end

    local sort_by_yaw_fn = function(a, b)
        return a.viewangles.yaw > b.viewangles.yaw
    end

    -- create dynamic per-position data
    for _, location_set in pairs(active_locations) do
        -- sort by yaw to make more right locations draw above
        if #location_set > 1 then
            table.sort(location_set, sort_by_yaw_fn)
        end

        -- figure out approach_accurate with a few traces
        if location_set.approach_accurate == nil then
            local count_accurate_move = 0

            -- go through all directions
            for i = 1, #approach_accurate_OFFSETS_END do
                if count_accurate_move > 1 then
                    break
                end

                -- set offset added to start for this direction
                local end_offset = approach_accurate_OFFSETS_END[i]

                -- loop through all start points
                for i = 1, #approach_accurate_OFFSETS_START do
                    local start = approach_accurate_OFFSETS_START[i] + location_set.position
                    local start_x, start_y, start_z = start:unpack()

                    local target = start + end_offset
                    local target_x, target_y, target_z = target:unpack()
                    -- client.draw_debug_text(start_x, start_y, start_z, 0, 5, 255, 255, 255, 255, "S", i)

                    local trace = utils.trace_line(start, target, local_player)
                    local fraction, entindex_hit = trace.fraction, trace.hit_entity == nil and -1 or trace.hit_entity:get_index()
                    local end_pos = start + end_offset
                    -- client.draw_debug_text(target_x, target_y, target_z, 0, 5, 255, 255, 255, 255, "E", i)

                    if entindex_hit == 0 and fraction > 0.45 and fraction < 0.6 then
                        count_accurate_move = count_accurate_move + 1
                        -- client.draw_debug_text(target_x, target_y, target_z, 1, 5, 0, 255, 0, 100, "HIT ", fraction)
                        break
                    end
                end
            end

            -- client.draw_debug_text(location.pos.x, location.pos.y, location.pos.z, 0, 5, 255, 255, 255, 255, "hit ", count_accurate_move, " times")
            location_set.approach_accurate = count_accurate_move > 1
        end
    end
end

-- playback variables
local playback_state, playback_begin, playback_sensitivity_set, playback_weapon
-- , playback_data.start_at, playback_weapon, playback_data.recovery_start_at, playback_data.throw_at, playback_data.thrown_at, playback_sensitivity_set
local playback_data = {}

-- restore disabled menu elements
local ui_restore = {}

local function restore_disabled()
    for key, value in pairs(ui_restore) do
        key:set(value)
    end

    if playback_sensitivity_set then
        cvar.sensitivity:float(tonumber(cvar.sensitivity:string()), true)
        playback_sensitivity_set = nil
    end

    table_clear(ui_restore)
end

local movetype_prev, waterlevel_prev
local function on_paint()
    if not entity.get_local_player() then
        return
    end

    -- these variables are set every paint, so if we ever early return here or something, make sure to reset them
    location_set_closest = nil
    location_selected = nil

    local local_player = entity.get_local_player()
    if local_player == nil then
        active_locations = nil

        if location_playback ~= nil then
            location_playback = nil
            restore_disabled()
        end

        return
    end

    local weapon_ent = local_player:get_player_weapon()
    if weapon_ent == nil then
        active_locations = nil

        if location_playback ~= nil then
            location_playback = nil
            restore_disabled()
        end

        return
    end

    local weapon = weapons[weapon_ent:get_weapon_index()]
    if weapon == nil then
        active_locations = nil

        if location_playback ~= nil then
            location_playback = nil
            restore_disabled()
        end

        return
    end

    if WEAPON_ALIASES[weapon] ~= nil then
        weapon = WEAPON_ALIASES[weapon]
    end

    local weapon_changed = weapon_prev ~= weapon
    if weapon_changed then
        active_locations = nil
        weapon_prev = weapon
    end

    local dpi_scale = render.get_scale(2)

    local hotkey = hotkey_reference:get()
    local aimbot = aimbot_reference:get()
    local aimbot_is_silent = aimbot == "Legit (Silent)" or aimbot == "Rage" or (aimbot == "Legit" and aimbot_speed_reference:get() == 0)

    local screen_size = render.screen_size()
    local min_height, max_height = math.floor(screen_size.y * 0.012) * dpi_scale, screen_size.y * 0.018 * dpi_scale
    local realtime = globals.realtime
    local frametime = globals.frametime

    local camera_angles = render.camera_angles()
    local camera_position = render.camera_position()
    local local_origin = local_player:get_origin()

    local position_world_top_offset = vector():angles(camera_angles.x - 90, camera_angles.y) * POSITION_WORLD_TOP_SIZE

    local shader_m = shader_reference:get()

    -- for i=0, 600 do
    -- 	local value = i/600

    -- 	local r, g, b = lerp_color(CIRCLE_RED_R, CIRCLE_RED_G, CIRCLE_RED_B, 0, CIRCLE_GREEN_R, CIRCLE_GREEN_G, CIRCLE_GREEN_B, 0, value)
    -- 	renderer.rectangle(screen_width/2-300+i, 1200, 1, 40, r, g, b, 255)
    -- end

    -- find all locations on current map, filter out wrong tickrate etc, combine origins, etc
    -- create a table of vector -> location(s)

    if location_playback ~= nil and (not hotkey or not local_player:is_alive() or local_player["m_MoveType"] == 8) then
        location_playback = nil
        restore_disabled()
    end

    if source_editing then
        on_paint_editing()
    end

    if active_locations == nil then
        benchmark:start("create active_locations")
        active_locations = {}
        active_locations_in_range = {}
        last_vischeck = 0

        -- create map_locations entry for this weapon
        if map_locations[weapon] == nil then
            populate_map_locations(local_player, weapon)
        else
            active_locations = map_locations[weapon]

            if weapon_changed then
                for _, location_set in pairs(active_locations) do
                    location_set.visible_alpha = 0
                    location_set.distance_alpha = 0
                    location_set.distance_width_mp = 0
                    location_set.in_range_draw_mp = 0

                    for i = 1, #location_set do
                        location_set[i].set = location_set
                    end
                end
            end
        end

        benchmark:finish("create active_locations")
    end

    if active_locations ~= nil then
        -- benchmark:start("[helper] frame")
        if realtime > last_vischeck + 0.07 then
            table_clear(active_locations_in_range)
            last_vischeck = realtime

            for _, location_set in pairs(active_locations) do
                location_set.distsqr = local_origin:distsqr(location_set.position)
                location_set.in_range = location_set.distsqr <= MAX_DIST_ICON_SQR
                if location_set.in_range then
                    location_set.distance = math.sqrt(location_set.distsqr)
                    location_set.visible = utils.trace_line(camera_position, location_set.position_visibility, local_player):is_visible()
                    location_set.in_range_text = location_set.distance <= MAX_DIST_TEXT

                    table.insert(active_locations_in_range, location_set)
                else
                    location_set.distance_alpha = 0
                    location_set.in_range_text = false
                    location_set.distance_width_mp = 0
                end
            end

            table.sort(
                active_locations_in_range,
                function(a, b)
                    return a.distsqr > b.distsqr
                end
            )
        end

        if #active_locations_in_range == 0 then
            return
        end

        -- find any location sets that we're on and store closest one
        for i = 1, #active_locations_in_range do
            local location_set = active_locations_in_range[i]

            if location_set_closest == nil or location_set.distance < location_set_closest.distance then
                location_set_closest = location_set
            end
        end

        -- override drawing if we're playing back a location
        local location_playback_set = location_playback ~= nil and location_playback.set or nil

        local closest_mp = 1
        if location_playback_set ~= nil then
            location_set_closest = location_playback_set
            closest_mp = 1
        elseif location_set_closest.distance < MAX_DIST_CLOSE then
            closest_mp = 0.4 + easing.quad_in_out(location_set_closest.distance, 0, 0.6, MAX_DIST_CLOSE)
        else
            location_set_closest = nil
        end

        local behind_walls = behind_walls_reference:get()

        local boxes_drawn_aabb = {}
        for i = 1, #active_locations_in_range do
            local location_set = active_locations_in_range[i]
            local is_closest = location_set == location_set_closest

            location_set.distance = local_origin:dist(location_set.position)
            location_set.distance_alpha = location_playback_set == location_set and 1 or easing.quart_out(1 - location_set.distance / MAX_DIST_ICON, 0, 1, 1)

            local display_full_width = location_set.in_range_text and (closest_mp > 0.5 or is_closest)
            if display_full_width and location_set.distance_width_mp < 1 then
                location_set.distance_width_mp = math.min(1, location_set.distance_width_mp + frametime * 7.5)
            elseif not display_full_width and location_set.distance_width_mp > 0 then
                location_set.distance_width_mp = math.max(0, location_set.distance_width_mp - frametime * 7.5)
            end
            local distance_width_mp = easing.quad_in_out(location_set.distance_width_mp, 0, 1, 1)

            local invisible_alpha = (behind_walls and location_set.distance_width_mp > 0) and 0.45 or 0
            local invisible_fade_mp = (behind_walls and location_set.distance_width_mp > 0 and not location_set.visible) and 0.33 or 1

            if (location_set.visible and location_set.visible_alpha < 1) or (location_set.visible_alpha < invisible_alpha) then
                location_set.visible_alpha = math.min(1, location_set.visible_alpha + frametime * 5.5 * invisible_fade_mp)
            elseif not location_set.visible and location_set.visible_alpha > invisible_alpha then
                location_set.visible_alpha = math.max(invisible_alpha, location_set.visible_alpha - frametime * 7.5 * invisible_fade_mp)
            end
            local visible_alpha = easing.sine_in_out(location_set.visible_alpha, 0, 1, 1) * (is_closest and 1 or closest_mp) * location_set.distance_alpha

            if not is_closest then
                location_set.in_range_draw_mp = 0
            end

            if visible_alpha > 0 then
                local position_bottom = location_set.position_world_bottom
                local ws_bot = position_bottom:to_screen()

                if ws_bot ~= nil then
                    local ws_top = (position_bottom + position_world_top_offset):to_screen()

                    if ws_top ~= nil then
                        local width_text, height_text = 0, 0
                        local lines = {}

                        -- get text and its size
                        for i = 1, #location_set do
                            local location = location_set[i]
                            local name = location.name

                            local shader = shader_m:clone()
                            if location.editing then
                                shader = CLR_TEXT_EDIT
                            end
                            shader.a = shader.a * visible_alpha

                            table.insert(lines, {shader, "s", name})
                        end

                        for i = 1, #lines do
                            local _, flags, text = unpack(lines[i])
                            local ls = render.measure_text(1, flags, text)
                            ls.y = ls.y - 1
                            if ls.x > width_text then
                                width_text = ls.x
                            end
                            lines[i].y_o = height_text - 1
                            height_text = height_text + ls.y
                            lines[i].width = ls.x
                            lines[i].height = ls.y
                        end

                        if location_set.distance_width_mp < 1 then
                            width_text = width_text * location_set.distance_width_mp
                            height_text = math.max(lines[1] and lines[1].height or 0, height_text * math.min(1, location_set.distance_width_mp * 1))

                            -- modify text and make it smaller
                            for i = 1, #lines do
                                local _, flags, text = unpack(lines[i])

                                for j = text:len(), 0, -1 do
                                    local text_modified = text:sub(1, j)
                                    local lw = render.measure_text(1, flags, text_modified).x

                                    if width_text >= lw then
                                        -- got new text, update shit
                                        lines[i][6] = text_modified
                                        lines[i].width = lw
                                        break
                                    end
                                end
                            end
                        end

                        if location_set.distance_width_mp > 0 then
                            width_text = width_text + 2
                        else
                            width_text = 0
                        end

                        -- get icon
                        local wx_icon, wy_icon, width_icon, height_icon, width_icon_orig, height_icon_orig
                        local icon

                        local location = location_set[1]
                        if location.type == "movement" and location.weapons[1].type ~= "grenade" then
                            icon = CUSTOM_ICONS.bhop
                        else
                            icon = WEAPON_ICONS[location_set[1].weapons[1]]
                        end

                        local ox, oy, ow, oh
                        if icon ~= nil then
                            ox, oy, ow, oh = unpack(WEPAON_ICONS_OFFSETS[icon])
                            local _height = math.floor(math.min(max_height, math.max(min_height, height_text + 2, math.abs(ws_bot.y - ws_top.y))))
                            width_icon_orig, height_icon_orig = icon:measure(nil, _height)
                            -- wx_icon, wy_icon = wx_bot-width_icon/2, wy_top+(wy_bot-wy_top)/2-_height/2

                            ox = ox * width_icon_orig
                            oy = oy * height_icon_orig
                            width_icon = width_icon_orig + ow * width_icon_orig
                            height_icon = height_icon_orig + oh * height_icon_orig
                        end

                        -- got all the width's, calculate our topleft position
                        local full_width, full_height = width_text, height_text
                        if width_icon ~= nil then
                            full_width = full_width + (location_set.distance_width_mp * 8 * dpi_scale) + width_icon
                            full_height = math.max(height_icon, height_text)
                        else
                            full_height = math.max(math.floor(15 * dpi_scale), height_text)
                        end

                        local wx_topleft, wy_topleft = math.floor(ws_top.x - full_width / 2), math.floor(ws_bot.y - full_height)

                        for i = 1, #boxes_drawn_aabb do
                            -- local x2, y2, w2, h2 = unpack(boxes_drawn_aabb[i])
                            -- while wx_topleft < x2+w2 and x2 < wx_bot and wy_topleft < y2+h2 and y2 < wy_bot do
                            -- 	wy_bot = wy_bot-1
                            -- 	wy_topleft = wy_topleft-1
                            -- end
                            -- if wx_topleft < x2+w2 and x2 < wx_bot and wy_topleft < y2+h2 and y2 < wy_bot then
                            -- 	visible_alpha = visible_alpha * 0.1
                            -- end
                        end

                        if width_icon ~= nil then
                            wx_icon = ws_bot.x - full_width / 2 + ox
                            wy_icon = ws_bot.y - full_height + oy

                            if height_text > height_icon then
                                wy_icon = wy_icon + (height_text - height_icon) / 2
                            end
                        end

                        -- actually draw stuff: background
                        local begin = vector(wx_topleft, wy_topleft)
                        local endl = begin + vector(full_width, full_height)
                        render.rect(begin - 2, endl + 2, color(16, 180 * visible_alpha))
                        render.rect_outline(begin - 3, endl + 3, color(16, 170 * visible_alpha))
                        render.rect_outline(begin - 4, endl + 4, color(16, 195 * visible_alpha))
                        render.rect_outline(begin - 5, endl + 5, color(16, 40 * visible_alpha))

                        local shader = shader_m:clone()
                        if location_set[1].editing and #location_set == 1 then
                            shader = CLR_TEXT_EDIT
                        end
                        shader.a = shader_m.a * visible_alpha

                        if location_set.distance_width_mp > 0 then
                            if width_icon ~= nil then
                                -- draw divider
                                local begin = vector(wx_topleft + width_icon + 3, wy_topleft + 2)
                                local endl = begin + vector(0, full_height - 3)
                                render.line(begin, endl, shader)
                            end

                            -- draw text lines vertically centered
                            local wx_text, wy_text = wx_topleft + (width_icon == nil and 0 or width_icon + 8 * dpi_scale), wy_topleft
                            if full_height > height_text then
                                wy_text = wy_text + math.floor((full_height - height_text) / 2)
                            end

                            for i = 1, #lines do
                                local sha, flags, text = unpack(lines[i])
                                local _x, _y = wx_text, wy_text + lines[i].y_o

                                if lines[i].y_o + lines[i].height - 4 > height_text then
                                    break
                                end

                                render.text(1, vector(_x, _y), sha, flags, text)
                            end
                        end

                        -- draw icon
                        if icon ~= nil then
                            local outline_size = math.min(2, full_height * 0.03)

                            local outline_a_mp = 1
                            if outline_size > 0.6 and outline_size < 1 then
                                outline_a_mp = (outline_size - 0.6) / 0.4
                                outline_size = 1
                            else
                                outline_size = math.floor(outline_size)
                            end

                            local outline_r, outline_g, outline_b, outline_a = 0, 0, 0, 80 * outline_a_mp * visible_alpha
                            if outline_size > 0 then
                                icon:draw(wx_icon - outline_size, wy_icon, width_icon_orig, height_icon_orig, outline_r, outline_g, outline_b, outline_a, true)
                                icon:draw(wx_icon + outline_size, wy_icon, width_icon_orig, height_icon_orig, outline_r, outline_g, outline_b, outline_a, true)
                                icon:draw(wx_icon, wy_icon - outline_size, width_icon_orig, height_icon_orig, outline_r, outline_g, outline_b, outline_a, true)
                                icon:draw(wx_icon, wy_icon + outline_size, width_icon_orig, height_icon_orig, outline_r, outline_g, outline_b, outline_a, true)
                            end

                            -- renderer.rectangle(wx_icon, wy_icon, width_icon, height_icon, 255, 0, 0, 180)
                            --render.texture(icon, vector(wx_icon, wy_icon), size, shader_m)
                            icon:draw(wx_icon, wy_icon, width_icon_orig, height_icon_orig, shader_m.r, shader_m.g, shader_m.b, shader_m.a * visible_alpha, true)
                        -- local o = client.random_int(-10, 10)
                        -- renderer.line(wx+o, wy, wx_top+o, wy_top, 255, 0, 0, 255)
                        end

                        -- renderer.line(wx_top, wy_top, wx_bot, wy_bot, 255, 0, 0, 255)
                        -- renderer.text(wx_top, wy_top-6, 255, 0, 0, 255, "c", 0, math.abs(wy_bot-wy_top))

                        table.insert(boxes_drawn_aabb, {wx_topleft - 10, wy_topleft - 10, full_width + 10, full_height + 10})
                    end
                end
            end
        end

        if location_set_closest ~= nil then
            if location_set_closest.distance == nil then
                location_set_closest.distance = local_origin:dist(location_set_closest.position)
            end
            local in_range_draw = location_set_closest.distance < MAX_DIST_CLOSE_DRAW

            if location_set_closest == location_playback_set then
                location_set_closest.in_range_draw_mp = 1
            elseif in_range_draw and location_set_closest.in_range_draw_mp < 1 then
                location_set_closest.in_range_draw_mp = math.min(1, location_set_closest.in_range_draw_mp + frametime * 8)
            elseif not in_range_draw and location_set_closest.in_range_draw_mp > 0 then
                location_set_closest.in_range_draw_mp = math.max(0, location_set_closest.in_range_draw_mp - frametime * 8)
            end

            if location_set_closest.in_range_draw_mp > 0 then
                -- find selected location (closest to crosshair and in fov)
                local location_closest
                for i = 1, #location_set_closest do
                    local location = location_set_closest[i]

                    if location.viewangles_target ~= nil then
                        local pitch, yaw = location.viewangles.pitch, location.viewangles.yaw
                        local dp, dy = camera_angles.x - pitch, math.normalize_yaw(camera_angles.y - yaw)
                        location.viewangles_dist = math.sqrt(dp * dp + dy * dy)

                        if location_closest == nil or location_closest.viewangles_dist > location.viewangles_dist then
                            location_closest = location
                        end

                        if aimbot == "Legit" or (aimbot == "Legit (Silent)" and location.type == "movement") then
                            location.is_in_fov_select = location.viewangles_dist <= aimbot_fov_reference:get() * 0.1
                        else
                            location.is_in_fov_select = location.viewangles_dist <= (location.fov_select or aimbot == "Rage" and DEFAULTS.select_fov_rage or DEFAULTS.select_fov_legit)
                        end

                        local dist = local_origin:dist(location.position)
                        local dist2d = local_origin:dist2d(location.position)
                        if dist2d < 1.5 then
                            dist = dist2d
                        end

                        -- if hotkey then
                        -- 	print(local_origin)
                        -- 	print(location.position)
                        -- 	print(dist)
                        -- 	print(dist2d)
                        -- end

                        location.is_position_correct = dist < MAX_DIST_CORRECT and local_player["m_flDuckAmount"] == location.duckamount

                        -- print(globals.realtime())
                        -- print(location.duckamount)
                        -- print(entity.get_prop(local_player, "m_flDuckAmount"))
                        -- print(location_set_closest.distance)
                        -- print(location_set_closest.distance < MAX_DIST_CORRECT)
                        -- print(entity.get_prop(local_player, "m_flDuckAmount") == location.duckamount)
                        -- print(location.is_position_correct)

                        if location.fov ~= nil then
                            location.is_in_fov =
                                location.is_in_fov_select and ((not (location.type == "movement" and aimbot == "Legit (Silent)") and aimbot_is_silent) or location.viewangles_dist <= location.fov)
                        end
                    end
                end

                -- local visible_alpha = easing.sine_in_out(location_set.visible_alpha, 0, 1, 1) * (is_closest and 1 or closest_mp)

                local in_range_draw_mp = easing.cubic_in(location_set_closest.in_range_draw_mp, 0, 1, 1)

                for i = 1, #location_set_closest do
                    local location = location_set_closest[i]

                    if location.viewangles_target ~= nil then
                        local is_closest = location == location_closest
                        local is_selected = is_closest and location.is_in_fov_select
                        local is_in_fov = is_selected and location.is_in_fov

                        -- determine distance based multiplier
                        local in_fov_select_mp = 1
                        if location.is_in_fov_select ~= nil then
                            if is_selected and location.in_fov_select_mp < 1 then
                                location.in_fov_select_mp = math.min(1, location.in_fov_select_mp + frametime * 2.5 * (is_in_fov and 2 or 1))
                            elseif not is_selected and location.in_fov_select_mp > 0 then
                                location.in_fov_select_mp = math.max(0, location.in_fov_select_mp - frametime * 4.5)
                            end

                            in_fov_select_mp = location.in_fov_select_mp
                        end

                        -- determine if we pass the fov check (for legit)
                        local in_fov_mp = 1
                        if location.is_in_fov ~= nil then
                            if is_in_fov and location.in_fov_mp < 1 then
                                location.in_fov_mp = math.min(1, location.in_fov_mp + frametime * 6.5)
                            elseif not is_in_fov and location.in_fov_mp > 0 then
                                location.in_fov_mp = math.max(0, location.in_fov_mp - frametime * 5.5)
                            end

                            in_fov_mp = (location.is_position_correct or location == location_playback) and location.in_fov_mp or location.in_fov_mp * 0.5
                        end

                        if is_selected then
                            location_selected = location
                        end

                        local position, _, is_out_of_fov = render.get_offscreen(location.viewangles_target, 0.9)

                        if position ~= nil then
                            position:init(math.floor(position.x + 0.5), math.floor(position.y + 0.5))

                            -- local _wx, _wy = wx, wy

                            if not is_out_of_fov and location.on_screen_mp < 1 then
                                location.on_screen_mp = math.min(1, location.on_screen_mp + frametime * 3.5)
                            elseif is_out_of_fov and location.on_screen_mp > 0 then
                                location.on_screen_mp = math.max(0, location.on_screen_mp - frametime * 4.5)
                            end

                            local visible_alpha = (0.5 + location.on_screen_mp * 0.5) * in_range_draw_mp

                            local name = "»" .. location.name
                            local description

                            local title = render.measure_text(1, "s", name)
                            local description_size = vector()

                            if location.description ~= nil then
                                description = location.description:upper():gsub(" ", "  ")
                                description_size = render.measure_text(2, "s", description .. " ")
                                description_size.x = description_size.x
                            end
                            local extra_target_width = math.floor(description_size.y / 2)
                            extra_target_width = extra_target_width - extra_target_width % 2

                            local full_width, full_height = math.max(title.x, description_size.x), title.y + description_size.y

                            local shader = shader_m:clone()

                            if location.editing then
                                shader = CLR_TEXT_EDIT
                            end

                            local circle_size = math.floor(title.y / 2 - 1) * 2
                            local target_size = 0
                            if location.on_screen_mp > 0 then
                                target_size = math.floor((circle_size + 8 * dpi_scale) * location.on_screen_mp) + extra_target_width

                                full_width = full_width + target_size
                            end

                            position:init(position.x - circle_size / 2 - extra_target_width / 2, position.y - full_height / 2)

                            -- adjust if offscreen to the right
                            local wx_topleft = math.min(position.x, screen_size.x - 40 - full_width)
                            local wy_topleft = position.y

                            -- draw background

                            local background_mp = easing.sine_out(visible_alpha, 0, 1, 1)

                            local begin = vector(wx_topleft, wy_topleft)
                            local endl = begin + vector(full_width, full_height)

                            render.rect(begin - 2, endl + 2, color(16, 150 * background_mp))
                            render.rect_outline(begin - 3, endl + 3, color(16, 170 * background_mp))
                            render.rect_outline(begin - 4, endl + 4, color(16, 195 * background_mp))
                            render.rect_outline(begin - 5, endl + 5, color(16, 40 * background_mp))

                            if is_out_of_fov then
                                local triangle_alpha = 1 - location.on_screen_mp

                                if triangle_alpha > 0 then
                                    local cpos = screen_size / 2

                                    local angle = math.atan2(wy_topleft + full_height / 2 - cpos.y, wx_topleft + full_width / 2 - cpos.x)
                                    local triangle_angle = angle + math.rad(90)
                                    local offset = vector2_rotate(vector(0, -screen_size.y / 2 + 100), triangle_angle)

                                    local tpos = cpos + offset

                                    local dist_triangle_text = tpos:dist(vector(wx_topleft + full_width / 2, wy_topleft + full_height / 2))
                                    local dist_center_triangle = tpos:dist(cpos)
                                    local dist_center_text = cpos:dist(vector(wx_topleft + full_width / 2, wy_topleft + full_height / 2))

                                    local a_mp_dist = 1
                                    if 40 > dist_triangle_text then
                                        a_mp_dist = (dist_triangle_text - 30) / 10
                                    end

                                    if dist_center_text > dist_center_triangle and a_mp_dist > 0 then
                                        local height = math.floor(title.y * 1.5)

                                        local realtime_alpha_mp = 0.2 + math.abs(math.sin(globals.realtime * math.pi * 0.8 + i * 0.1)) * 0.8

                                        triangle_rotated(
                                            tpos,
                                            vector(height * 1.66, height),
                                            triangle_angle,
                                            color(shader.r, shader.g, shader.b, shader.a * math.min(1, visible_alpha * 1.5) * triangle_alpha * a_mp_dist * realtime_alpha_mp)
                                        )
                                    -- renderer.text(screen_width/2+offset_x, screen_height/2+offset_y, 255, 255, 255, 255, "c", 0, triangle_alpha)
                                    end
                                end
                            end

                            if location.on_screen_mp > 0.5 and in_range_draw_mp > 0 then
                                -- in_fov_select_mp
                                -- CIRCLE_GREEN_R

                                local c_a = 255 * 1 * in_range_draw_mp * easing.expo_in(location.on_screen_mp, 0, 1, 1)
                                local red_r, red_g, red_b = 255, 10, 10
                                local green_r, green_g, green_b = 20, 236, 0
                                local white_r, white_g, white_b = 140, 140, 140

                                -- fade from red to green based on selection
                                local sel_r, sel_g, sel_b = color(red_r, red_g, red_b, 0):lerp(color(green_r, green_g, green_b, 0), in_fov_mp):unpack()

                                -- fade from white to red/green
                                local c_r, c_g, c_b = color(white_r, white_g, white_b, 0):lerp(color(sel_r, sel_g, sel_b, 0), in_fov_select_mp):unpack()

                                local c_pos = vector(position.x + circle_size / 2 + extra_target_width / 2, position.y + full_height / 2)
                                local c_radius = circle_size / 2

                                -- outline
                                render.circle_outline(c_pos, color(16, c_a * 0.6), c_radius + 1, 0, 1, 2)

                                -- circle
                                render.circle(c_pos, color(c_r, c_g, c_b, c_a), c_radius, 0, 1)

                                -- gradient (kind of)
                                render.circle_outline(c_pos, color(16, c_a * 0.3), c_radius + 1, 0, 1, 2)
                                render.circle_outline(c_pos, color(16, c_a * 0.2), c_radius, 0, 1, 2)
                                render.circle_outline(c_pos, color(16, c_a * 0.1), c_radius - 1, 0, 1, 2)

                            -- -- crosshair
                            -- renderer.rectangle(wx-1, wy-5, 2, 10, 0, 0, 0, 120*in_fov_select_mp)
                            -- renderer.rectangle(wx-5, wy-1, 4, 2, 0, 0, 0, 120*in_fov_select_mp)
                            -- renderer.rectangle(wx+1, wy-1, 4, 2, 0, 0, 0, 120*in_fov_select_mp)
                            end

                            -- divider
                            if target_size > 1 then
                                render.rect(
                                    vector(wx_topleft + target_size - 4 * dpi_scale, wy_topleft + 1),
                                    vector(wx_topleft + target_size - 4 * dpi_scale, wy_topleft + 1) + vector(1, full_height - 1),
                                    color(shader.r, shader.g, shader.b, shader_m.a * visible_alpha * location.on_screen_mp)
                                )
                            end

                            -- text
                            render.text(1, vector(wx_topleft + target_size, position.y), color(shader.r, shader.g, shader.b, shader_m.a * visible_alpha), "s", name)

                            if description ~= nil then
                                render.text(
                                    2,
                                    vector(wx_topleft + target_size, position.y + title.y),
                                    color(math.min(255, shader.r * 1.2), math.min(255, shader.g * 1.2), math.min(255, shader.b * 1.2), shader_m.a * visible_alpha * 0.92),
                                    "s",
                                    description
                                )
                            end

                        -- renderer.rectangle(_wx-2, _wy-2, 4, 4, 255, 255, 255, 255)
                        end
                    end
                end
            end
        end

        -- run smooth aimbot in paint
        if hotkey and location_selected ~= nil and ((location_selected.type == "movement" and aimbot ~= "Rage") or (location_selected.type ~= "movement" and aimbot == "Legit")) then
            if (not location_selected.is_in_fov or location_selected.viewangles_dist > 0.1) then
                local speed = aimbot_speed_reference:get() / 100

                if speed == 0 then
                    if location_selected.type == "grenade" and local_player:get_player_weapon()["m_bPinPulled"] then
                        -- local aim_pitch, aim_yaw = location_selected.viewangles.pitch, location_selected.viewangles.yaw
                        render.camera_angles(vector(unpack(location_selected.viewangles)))
                    end
                else
                    local aim_pitch, aim_yaw = location_selected.viewangles.pitch, location_selected.viewangles.yaw
                    local dp, dy = camera_angles.x - aim_pitch, math.normalize_yaw(camera_angles.y - aim_yaw)

                    local dist = location_selected.viewangles_dist
                    dp = dp / dist
                    dy = dy / dist

                    local mp = math.min(1, dist / 3) * 0.5
                    local delta_mp = (mp + math.abs(dist * (1 - mp))) * globals.frametime * 15 * speed

                    local pitch = camera_angles.x - dp * delta_mp * utils.random_float(0.7, 1.2)
                    local yaw = camera_angles.y - dy * delta_mp * utils.random_float(0.7, 1.2)

                    render.camera_angles(vector(pitch, yaw))
                end
            end
        end

    -- benchmark:finish("[helper] frame")
    end
end

local function cmd_remove_user_input(cmd)
    cmd.in_forward = false
    cmd.in_back = false
    cmd.in_moveleft = false
    cmd.in_moveright = false

    cmd.forwardmove = 0
    cmd.sidemove = 0

    cmd.in_jump = false
    cmd.in_speed = false
end

-- local i = 0
-- client.set_event_callback("setup_command", function(cmd)
-- 	if cmd.in_jump == 1 then
-- 		local origin = vector(entity.get_prop(entity.get_local_player(), "m_vecAbsOrigin"))
-- 		print(i, " ", origin.z)

-- 		i = i + 1
-- 	else
-- 		i = 0
-- 	end
-- end)

local function cmd_location_playback_grenade(cmd, local_player, weapon)
    local tickrate = 1 / globals.tickinterval
    local tickrate_mp = location_playback.tickrates[tickrate]

    if playback_state == nil then
        playback_state = GRENADE_PLAYBACK_PREPARE
        table_clear(playback_data)

        -- playback_data = {}
        -- playback_data.start_at = nil
        -- playback_data.recovery_start_at = nil
        -- playback_data.throw_at = nil
        -- playback_data.thrown_at = nil

        local aimbot = aimbot_reference:get()
        if aimbot == "Legit" or aimbot == "Off" then
            cvar.sensitivity:float(0, true)
            playback_sensitivity_set = true
        end

        local begin = playback_begin

        utils.execute_after(
            (location_playback.run_duration or 0) * tickrate_mp * 2 + 2,
            function()
                if location_playback ~= nil and playback_begin == begin then
                    print_raw("\a4B69FF[neverlose]\aFF4040\x20[helper] playback timed out")

                    location_playback = nil
                    restore_disabled()
                end
            end
        )
    end

    if weapon ~= playback_weapon and playback_state ~= GRENADE_PLAYBACK_FINISHED then
        location_playback = nil

        restore_disabled()

        return
    end

    if playback_state ~= GRENADE_PLAYBACK_FINISHED then
        cmd_remove_user_input(cmd)

        cmd.in_duck = location_playback.duckamount == 1
        cmd.move_yaw = location_playback.run_yaw
    elseif playback_sensitivity_set then
        cvar.sensitivity:float(tonumber(cvar.sensitivity:string()), true)
        playback_sensitivity_set = nil
    end

    -- prepare for the playback, here we make sure we have the right throwstrength etc
    if playback_state == GRENADE_PLAYBACK_PREPARE or playback_state == GRENADE_PLAYBACK_RUN or playback_state == GRENADE_PLAYBACK_THROWN then
        if location_playback.throw_strength == 1 then
            cmd.in_attack = true
            cmd.in_attack2 = false
        elseif location_playback.throw_strength == 0.5 then
            cmd.in_attack = true
            cmd.in_attack2 = true
        elseif location_playback.throw_strength == 0 then
            cmd.in_attack = false
            cmd.in_attack2 = true
        end
    end

    -- check if we have the right throwstrength and go to next state
    if playback_state == GRENADE_PLAYBACK_PREPARE and weapon["m_flThrowStrength"] == location_playback.throw_strength then
        playback_state = GRENADE_PLAYBACK_RUN
        playback_data.start_at = cmd.command_number
    end

    if playback_state == GRENADE_PLAYBACK_RUN or playback_state == GRENADE_PLAYBACK_THROW or playback_state == GRENADE_PLAYBACK_THROWN then
        local step = cmd.command_number - playback_data.start_at

        if location_playback.run_duration ~= nil and location_playback.run_duration * tickrate_mp > step then
        elseif playback_state == GRENADE_PLAYBACK_RUN then
            playback_state = GRENADE_PLAYBACK_THROW
        end

        if location_playback.run_duration ~= nil then
            cmd.forwardmove = 450
            cmd.in_forward = true
            cmd.in_speed = location_playback.run_speed

            if antiaim_pitch_reference:get() ~= "Disabled" then
                waterlevel_prev = local_player["m_nWaterLevel"]
                local_player["m_nWaterLevel"] = 2

                movetype_prev = local_player["m_MoveType"]
                local_player["m_MoveType"] = 1
            end
        end
    end

    if playback_state == GRENADE_PLAYBACK_THROW then
        if location_playback.jump then
            cmd.in_jump = true
        end

        playback_state = GRENADE_PLAYBACK_THROWN
        playback_data.throw_at = cmd.command_number
    end

    if playback_state == GRENADE_PLAYBACK_THROWN then
        -- local throw_time = weapon["m_fThrowTime"]

        -- print("time since start: ", cmd.command_number - playback_data.throw_at)
        -- print("throw_time: ", throw_time)
        if cmd.command_number - playback_data.throw_at >= location_playback.delay then
            cmd.in_attack = false
            cmd.in_attack2 = false
        end
    end

    if playback_state == GRENADE_PLAYBACK_FINISHED then
        if location_playback.jump then
            local onground = bit.band(local_player["m_fFlags"], FL_ONGROUND) == FL_ONGROUND

            if onground then
                -- print("was onground at ", globals.tickcount)
                playback_state = nil
                location_playback = nil

                restore_disabled()
            else
                local aimbot = aimbot_reference:get()

                -- recovery strafe after throw
                if aimbot == "Rage" and cmd.in_forward == false and cmd.in_back == false and cmd.in_moveleft == false and cmd.in_moveright == false and cmd.in_jump == false then
                    cmd_remove_user_input(cmd)

                    cmd.move_yaw = location_playback.recovery_yaw or location_playback.run_yaw - 180
                    cmd.forwardmove = 450
                    cmd.in_forward = true
                    cmd.in_jump = location_playback.recovery_jump
                end

                -- turn airstrafe back on
                if ui_restore[air_strafe_reference] then
                    ui_restore[air_strafe_reference] = nil

                    -- either enable it next frame or in a bit of time, depending on magic number
                    utils.execute_after(cvar.sv_airaccelerate:float() > 50 and 0 or 0.05, air_strafe_reference.set, air_strafe_reference, true)
                end
            end
        elseif location_playback.recovery_yaw ~= nil then
            local aimbot = aimbot_reference:get()
            if aimbot == "Rage" and cmd.in_forward == false and cmd.in_back == false and cmd.in_moveleft == false and cmd.in_moveright == false and cmd.in_jump == false then
                if playback_data.recovery_start_at == nil then
                    playback_data.recovery_start_at = cmd.command_number
                end

                local recovery_duration = math.min(32, location_playback.run_duration or 16) + 13 + (location_playback.recovery_jump and 10 or 0)

                if playback_data.recovery_start_at + recovery_duration >= cmd.command_number then
                    cmd.move_yaw = location_playback.recovery_yaw
                    cmd.forwardmove = 450
                    cmd.in_forward = true
                    cmd.in_jump = location_playback.recovery_jump
                end
            else
                location_playback = nil

                restore_disabled()
            end
        end
    end

    if playback_state == GRENADE_PLAYBACK_THROWN then
        if location_playback.jump and air_strafe_reference:get() then
            ui_restore[air_strafe_reference] = true
            air_strafe_reference:set(false)
        end

        if air_duck_reference:get() then
            ui_restore[air_duck_reference] = true
            air_duck_reference:set(false)
        end

        local aimbot = aimbot_reference:get()

        -- true if this is the last tick of the throw, here we can start resetting stuff
        if is_grenade_being_thrown(weapon, cmd) then
            playback_data.thrown_at = cmd.command_number
            if DEBUG then
                local origin = local_player:get_origin()
                local velocity = local_player["m_vecAbsVelocity"]

                print("throwing from ", origin)
                print("throw velocity: ", velocity:length())

                local dir = location_playback.position:to(origin)
                local angles = dir:angles()

                -- print_raw(location_playback.position)
                -- print_raw(origin)
                -- print_raw(dir)
                -- print_raw(dir:angles())

                if angles then
                    print("resulting move yaw: ", angles.y, " (offset: ", angles.y - location_playback.run_yaw, ")")
                end

                local weapon_ent = local_player:get_player_weapon()
                print("throw strength: ", weapon_ent["m_flThrowStrength"])
            end

            -- actually aim
            if aimbot == "Legit (Silent)" or aimbot == "Rage" then
                cmd.view_angles.x = location_playback.viewangles.pitch
                cmd.view_angles.y = location_playback.viewangles.yaw
                cmd.send_packet = false
            end

            -- just a little failsafe to make sure we turn stuff back on
            utils.execute_after(0.8, restore_disabled)
        elseif weapon["m_fThrowTime"] == 0 and playback_data.thrown_at ~= nil and playback_data.thrown_at > playback_data.throw_at then
            playback_state = GRENADE_PLAYBACK_FINISHED

            -- timeout incase user starts noclipping after throwing or something
            local begin = playback_begin
            utils.execute_after(
                0.6,
                function()
                    if playback_state == GRENADE_PLAYBACK_FINISHED and playback_begin == begin then
                        location_playback = nil

                        restore_disabled()
                    end
                end
            )
        end
    end
end

local function cmd_location_playback_movement(cmd, local_player, weapon)
    if playback_state == nil then
        playback_state = 1

        table_clear(playback_data)
        playback_data.start_at = cmd.command_number
        playback_data.last_offset_swap = 0
    end

    local is_grenade = location_playback.weapons[1].type == "grenade"
    local current_weapon = weapons[weapon:get_weapon_index()]

    if weapon ~= playback_weapon and not (is_grenade and current_weapon.type == "knife") then
        location_playback = nil
        restore_disabled()
        return
    end

    local index = cmd.command_number - playback_data.start_at + 1
    local command = location_playback.movement_commands[index]

    if command == nil then
        location_playback = nil
        restore_disabled()
        return
    end

    if air_strafe_reference:get() then
        ui_restore[air_strafe_reference] = true
        air_strafe_reference:set(false)
    end

    if quick_stop_reference:get() then
        ui_restore[quick_stop_reference] = true
        quick_stop_reference:set(false)
    end

    if strafe_assist_reference:get() then
        ui_restore[strafe_assist_reference] = true
        strafe_assist_reference:set(false)
    end

    if infinite_duck_reference:get() then
        ui_restore[infinite_duck_reference] = true
        infinite_duck_reference:set(false)
    end

    if air_duck_reference:get() then
        ui_restore[air_duck_reference] = true
        air_duck_reference:set(false)
    end

    if antiaim_body_yaw_reference:get() then
        ui_restore[antiaim_body_yaw_reference] = true
        antiaim_body_yaw_reference:set(false)
    end
    local aimbot = aimbot_reference:get()
    local ignore_pitch_yaw = aimbot == "Rage"
    local aa_enabled = antiaim_pitch_reference:get() ~= "Disabled"

    local onground = bit.band(local_player["m_fFlags"], FL_ONGROUND) == FL_ONGROUND

    local origin = local_player:get_origin()
    local velocity = local_player["m_vecAbsVelocity"]

    -- local prev_pitch, prev_yaw = cmd.pitch, cmd.yaw

    if aa_enabled then
        waterlevel_prev = local_player["m_nWaterLevel"]
        local_player["m_nWaterLevel"] = 2

        movetype_prev = local_player["m_MoveType"]
        local_player["m_MoveType"] = 1
    end

    for key, value in pairs(command) do
        local set_key = true

        if key == "view_angles" then
            set_key = false
        elseif key == "in_use" and value == false then
            set_key = false
        elseif key == "in_attack" or key == "in_attack2" then
            if is_grenade and current_weapon.type == "grenade" then
                set_key = true
            elseif value == false then
                set_key = false
            end
        end

        if set_key then
            cmd[key] = value
        end
    end

    -- compute_move(forwardmove, sidemove, real_pitch, real_yaw, wish_pitch, wish_yaw)
    -- local forwardmove, sidemove = movement_fix.compute_move(command.forwardmove, command.sidemove, prev_pitch, prev_yaw, prev_pitch, command.move_yaw)

    -- cmd.pitch = prev_pitch
    -- cmd.yaw = prev_yaw
    -- cmd.move_yaw = prev_yaw
    -- cmd.forwardmove, cmd.sidemove = forwardmove, sidemove

    -- debug: set yaw to move yaw, overriding the ignore_pitch_yaw check above
    -- cmd.yaw = cmd.move_yaw - 180

    if aimbot == "Rage" and aa_enabled and (is_grenade or (cmd.in_attack == false and cmd.in_attack2 == false)) and (not is_grenade or (is_grenade and playback_data.thrown_at == nil)) then
        if cmd.command_number - playback_data.last_offset_swap > 16 then
            local target_yaw = math.normalize_yaw(cmd.in_use and cmd.view_angles.y or cmd.view_angles.y - 180)
            playback_data.set_pitch = cmd.in_use == false

            local min_diff, new_offset = 90, nil
            -- find closest 90 deg offset of command.yaw to target_yaw
            for o = -180, 180, 90 do
                local command_yaw = math.normalize_yaw(command.yaw + o)
                local diff = math.abs(command_yaw - target_yaw)

                if min_diff > diff then
                    min_diff = diff
                    new_offset = o
                end
            end

            if new_offset ~= playback_data.last_offset then
                if DEBUG then
                    print_raw("offset switched from ", playback_data.last_offset, " to ", new_offset)
                end
                playback_data.last_offset = new_offset
                playback_data.last_offset_swap = cmd.command_number
            end
        end

        if playback_data.last_offset ~= nil then
            cmd.view_angles.y = command.yaw + playback_data.last_offset

            if playback_data.set_pitch then
                cmd.view_angles.x = 89
            end
        end
    end

    if not ignore_pitch_yaw then
        render.camera_angles(vector(command.pitch, command.yaw))

        if not aa_enabled then
            cmd.view_angles.x = command.pitch
            cmd.view_angles.y = command.yaw
        end

        cvar.sensitivity:float(0, true)
        playback_sensitivity_set = true
    elseif (is_grenade and current_weapon.type == "grenade") and aimbot == "Rage" and is_grenade_being_thrown(weapon, cmd) then
        -- render.camera_angles(vector(command.pitch, command.yaw))

        cmd.view_angles.x = command.pitch
        cmd.view_angles.y = command.yaw
        cmd.send_packet = false

        playback_data.thrown_at = cmd.command_number
    end

    if DEBUG then
        print_raw(string.format("cmd #%03d onground: %5s in_jump: %5s origin: %s velocity: %s", index, onground, cmd.in_jump, origin, velocity))
    end
end

local function cmd_location_playback(cmd, local_player, weapon)
    if location_playback.type == "grenade" then
        cmd_location_playback_grenade(cmd, local_player, weapon)
    elseif location_playback.type == "movement" then
        cmd_location_playback_movement(cmd, local_player, weapon)
    end
end

local function on_run_command()
    if movetype_prev ~= nil or waterlevel_prev ~= nil then
        local local_player = entity.get_local_player()

        if waterlevel_prev ~= nil then
            local_player["m_nWaterLevel"] = waterlevel_prev
            waterlevel_prev = nil
        end

        if movetype_prev ~= nil then
            local_player["m_MoveType"] = movetype_prev
            movetype_prev = nil
        end
    end
end

local function on_setup_command(cmd)
    local local_player = entity.get_local_player()
    local local_origin = local_player:get_origin()
    local hotkey = hotkey_reference:get()
    local weapon = local_player:get_player_weapon()

    if location_playback ~= nil then
        cmd_location_playback(cmd, local_player, weapon)
    elseif location_selected ~= nil and hotkey and location_selected.is_in_fov and location_selected.is_position_correct then
        -- if we're already aiming at the location properly, start executing it

        local speed = local_player["m_vecAbsVelocity"]:length()
        local pin_pulled = weapon["m_bPinPulled"]

        if location_selected.duckamount == 1 or location_set_closest.has_only_duck then
            cmd.in_duck = true
        end

        local is_grenade = location_selected.weapons[1].type == "grenade"
        local is_in_attack = cmd.in_attack or cmd.in_attack2

        if
            (location_selected.type == "movement" and speed < 2 and (not is_grenade or is_in_attack)) or
                (location_selected.type == "grenade" and pin_pulled and is_in_attack and speed < 2) and location_selected.duckamount == local_player["m_flDuckAmount"]
         then
            location_playback = location_selected
            playback_state = nil
            playback_weapon = weapon
            playback_begin = cmd.command_number

            cmd_location_playback(cmd, local_player, weapon)
        elseif not pin_pulled and (cmd.in_attack or cmd.in_attack2) then
            -- just started holding attack for the first cmd, here we still have the chance to instantly go to the right throwstrength
            if location_selected.throw_strength == 1 then
                cmd.in_attack = true
                cmd.in_attack2 = false
            elseif location_selected.throw_strength == 0.5 then
                cmd.in_attack = true
                cmd.in_attack2 = true
            elseif location_selected.throw_strength == 0 then
                cmd.in_attack = false
                cmd.in_attack2 = true
            end
        end
    elseif location_set_closest ~= nil and hotkey then
        -- move towards closest location set
        local target_position = (location_selected ~= nil and location_selected.is_in_fov) and location_selected.position or location_set_closest.position_approach
        local distance = local_origin:dist(target_position)
        local distance_2d = local_origin:dist2d(target_position)

        if (distance_2d < 0.5 and distance > 0.08 and distance < 5) or (location_set_closest.inaccurate_position and distance < 40) then
            distance = distance_2d
        end

        if ((location_selected ~= nil and location_selected.duckamount == 1) or location_set_closest.has_only_duck) and distance < 10 then
            cmd.in_duck = true
        end

        if cmd.forwardmove == 0 and cmd.sidemove == 0 and cmd.in_forward == false and cmd.in_back == false and cmd.in_moveleft == false and cmd.in_moveright == false then
            if distance < 32 and distance >= MAX_DIST_CORRECT * 0.5 then
                local fwd1 = target_position - local_origin

                local pos1 = target_position + fwd1:normalized() * 10

                local fwd = pos1 - local_origin
                local angles = fwd:angles()

                if angles == nil then
                    return
                end

                cmd.move_yaw = angles.y
                cmd.in_speed = false

                cmd.in_moveleft, cmd.in_moveright = false, false
                cmd.sidemove = 0

                if location_set_closest.approach_accurate then
                    cmd.in_forward, cmd.in_back = true, false
                    cmd.forwardmove = 450
                else
                    if distance > 14 then
                        cmd.forwardmove = 450
                    else
                        local wishspeed = math.min(450, math.max(1.1 + local_player["m_flDuckAmount"] * 10, distance * 9))
                        local vel = local_player["m_vecAbsVelocity"]:length2d()
                        if vel >= math.min(250, wishspeed) + 15 then
                            cmd.forwardmove = 0
                            cmd.in_forward = false
                        else
                            cmd.forwardmove = math.max(6, vel >= math.min(250, wishspeed) and wishspeed * 0.9 or wishspeed)
                            cmd.in_forward = true
                        end
                    end
                end
            end
        end
    end
end

local function on_console_input(text)
    -- if not source_editing then
    -- 	return
    -- end

    if text == "helper" or text:match("^helper .*$") then
        if not sources_list_ui.title:get() then
            return
        end

        local log_help = false
        if text:match("^helper map_pattern%s*") then
            local map_data = common.get_map_data()
            if map_data ~= nil then
                print("Raw map name: ", map_data.shortname)
                print("Resolved map name: ", get_mapname())
                print("Map pattern: ", get_map_pattern())
            else
                print_raw("\a4B69FF[neverlose]\aFF4040\x20You need to be in-game to use this command")
            end
        elseif text == "helper" or text:match("^helper %s*$") or text:match("^helper help%s*$") or text:match("^helper %?%s*$") then
            print("Helper console command system")
            log_help = true
        elseif text:match("^helper source stats%s*") then
            if type(source_selected) == "table" then
                local all_locations = source_selected:get_all_locations()
                local maps = {}
                for map, _ in pairs(all_locations) do
                    table.insert(maps, map)
                end
                table.sort(maps)

                local rows = {}
                local headings = {"MAP", "Smoke", "Flash", "Molotov", "HE Grenade", "Movement", "Location", "Area", " TOTAL "}
                local total_row = {"TOTAL", 0, 0, 0, 0, 0, 0, 0, 0}

                for i = 1, #maps do
                    local row = {maps[i], 0, 0, 0, 0, 0, 0, 0, 0}
                    local map_locations = all_locations[maps[i]]
                    for i = 1, #map_locations do
                        local location = map_locations[i]
                        local index = 7

                        if location.type == "grenade" then
                            for i = 1, #location.weapons do
                                local weapon = location.weapons[i]
                                if weapon.console_name == "weapon_smokegrenade" then
                                    index = 2
                                elseif weapon.console_name == "weapon_flashbang" then
                                    index = 3
                                elseif weapon.console_name == "weapon_molotov" then
                                    index = 4
                                elseif weapon.console_name == "weapon_hegrenade" then
                                    index = 5
                                end
                            end
                        elseif location.type == "movement" then
                            index = 6
                        elseif location.type == "location" then
                            index = 7
                        elseif location.type == "area" then
                            index = 8
                        end

                        row[index] = row[index] + 1
                        ---@diagnostic disable-next-line: assign-type-mismatch
                        total_row[index] = total_row[index] + 1
                        row[9] = row[9] + 1
                        total_row[9] = total_row[9] + 1
                    end

                    table.insert(rows, row)
                end

                table.insert(rows, {})
                table.insert(rows, total_row)

                -- remove empty columns
                for i = #total_row, 2, -1 do
                    if total_row[i] == 0 then
                        table.remove(headings, i)
                        for j = 1, #rows do
                            table.remove(rows[j], i)
                        end
                    end
                end

                local tbl_result = table_gen(rows, headings, {style = "Unicode"})
                -- print("Locations loaded:")
                -- for s in tbl_result:gmatch("[^\r\n]+") do
                --     print_raw("\aD7D7D7" .. s)
                -- end

                print("Statistics for ", source_selected.name, source_selected.description ~= nil and string.format(" - %s", source_selected.description) or "", ": \n", tbl_result, "\n")
            else
                print_raw("\a4B69FF[neverlose]\aFF4040\x20No source selected")
            end
        elseif text:match("^helper source export_repo%s*") then
            if type(source_selected) == "table" then
                if source_selected.type == "local" then
                    print_raw("\a4B69FF[neverlose]\aFF4040\x20Not yet implemented")
                else
                    print_raw("\a4B69FF[neverlose]\aFF4040\x20You can only export a local source")
                end
            else
                print_raw("\a4B69FF[neverlose]\aFF4040\x20No source selected")
            end
        elseif text:match("^helper source%s*$") then
            if type(source_selected) == "table" then
                print("Selected source: ", source_selected.name, " (", source_selected.type, ")")
                print("Description: ", tostring(source_selected.description))
                print(
                    "Last updated: ",
                    source_selected.update_timestamp and string.format("%s (unix ts: %s)", format_unix_timestamp(source_selected.update_timestamp, false, false, 1), source_selected.update_timestamp) or
                        "Not set"
                )
            else
                print_raw("\a4B69FF[neverlose]\aFF4040\x20No source selected")
            end
        else
            print_raw("\a4B69FF[neverlose]\aFF4040\x20Unknown helper command: " .. text:gsub("^helper ", ""))

            log_help = true
        end

        if log_help then
            local commands = {
                {"help", "Displays this help info"},
                {"map_pattern", "Displays map pattern debug info"},
                {"source", "Displays information about the current source"},
                {"source stats", "Displays statistics for the currently selected source"},
                {"source export_repo", "Exports a local source into a repository file structure"}
            }

            local text = "\tKnown commands:"
            for i = 1, #commands do
                local command, help = unpack(commands[i])
                text = text .. string.format("\n\thelper %s - %s", command, help)
            end

            print_raw("\aD7D7D7" .. text)
        end

        return false
    end
end

local function update_basic_ui()
    local enabled = enabled_reference:get()
    if enabled then
        events.render:set(on_paint)
        events.createmove:set(on_setup_command)
        events.createmove_run:set(on_run_command)
        events.console_input:set(on_console_input)
    else
        events.render:unset(on_paint)
        events.createmove:unset(on_setup_command)
        events.createmove_run:unset(on_run_command)
        events.console_input:unset(on_console_input)
    end

    select_reference:visibility(enabled)
    hotkey_reference:visibility(enabled)
    aimbot_reference:visibility(enabled)
    behind_walls_reference:visibility(enabled)
    sources_list_ui.title:visibility(enabled)

    update_sources_ui()

    local aimbot = enabled and aimbot_reference:get()
    aimbot_fov_reference:visibility(enabled and aimbot == "Legit")
    aimbot_speed_reference:visibility(enabled and aimbot == "Legit")
end

-- normal callbacks are linked to the ui element
enabled_reference:set_callback(update_basic_ui)
aimbot_reference:set_callback(update_basic_ui)
update_basic_ui()

events.level_init:set(
    function()
        source_selected = nil

        source_editing = false
        edit_location_selected = nil

        table_clear(source_editing_modified)
        table_clear(source_editing_has_changed)

        update_sources_ui()
        flush_active_locations()

        if DEBUG and DEBUG.create_map_patterns then
            local mapname = common.get_map_data()["shortname"]
            local pattern = get_map_pattern()

            DEBUG.debug_text = "create_map_patterns progress: " .. DEBUG.create_map_patterns_index[mapname] .. " / " .. DEBUG.create_map_patterns_count

            if pattern ~= nil then
                if MAP_PATTERNS[pattern] ~= nil then
                    local text = "collision: " .. mapname .. " has the same pattern as " .. MAP_PATTERNS[pattern]
                    DEBUG.debug_text = text
                    error(text)
                    return
                end

                print("created pattern for ", mapname, ": ", tostring(pattern))

                MAP_PATTERNS[pattern] = mapname

                -- if mapname == "de_aztec" then
                -- 	print("landed on aztec")
                -- 	print_raw(DEBUG.inspect(MAP_PATTERNS))
                -- 	return
                -- end

                if DEBUG.create_map_patterns_next[mapname] ~= nil then
                    print("If you can read this, the map ", DEBUG.create_map_patterns_next[mapname], " failed to load")
                    utils.execute_after(2, utils.console_exec, "map " .. DEBUG.create_map_patterns_next[mapname])
                else
                    DEBUG.debug_text = "DONE!"
                    print("Done!")
                    print(DEBUG.inspect(MAP_PATTERNS))
                    print("failed: ", DEBUG.inspect(DEBUG.create_map_patterns_failed))
                    DEBUG.create_map_patterns = false
                end
            else
                table.insert(DEBUG.create_map_patterns_failed, mapname)
                print_raw(table.concat({"\a4A69FF[neverlose]\x20", "\aFF3E3E", "failed to create pattern for ", mapname}))

                DEBUG.debug_text = "failed to create pattern for " .. mapname
            end
        end
    end
)

events.round_end:set(
    function()
        location_playback = nil
    end
)

events.shutdown:set(
    function()
        -- clear metatables
        for i = 1, #db.sources do
            if db.sources[i].cleanup ~= nil then
                db.sources[i]:cleanup()
            end
        end

        restore_disabled()

        benchmark:start("db_write")
        database["helper"] = db
        benchmark:finish("db_write")
    end
)
