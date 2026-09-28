-- Every file the device runs parses and uses only what the device's Lua
-- has; every module except the device glue stays free of picocalc, so the
-- host tests can run it.
local T = require("tests.t")

-- The modules that talk to picocalc; every other src module must not.
local DEVICE = { render = true, hud = true, controls = true, game = true }
local FORBIDDEN = { "io%.", "os%.", "package%.", "debug%.", "dofile", "loadfile", "loadstring", "setfenv" }

local function ls(pattern)
    local out = {}
    local p = assert(io.popen("ls " .. pattern .. " 2>/dev/null"))
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    return out
end

local function device_files()
    local files = { "main.lua" }
    for _, f in ipairs(ls("src/*.lua data/*.lua")) do files[#files + 1] = f end
    return files
end

local function code_of(path)
    local f = assert(io.open(path))
    local text = f:read("a")
    f:close()
    return (text:gsub("%-%-[^\n]*", "")) -- drop comments
end

return {
    device_files_parse = function()
        for _, path in ipairs(device_files()) do
            local fn, err = loadfile(path)
            T.ok(fn, err)
        end
    end,
    device_files_avoid_missing_libraries = function()
        for _, path in ipairs(device_files()) do
            local code = code_of(path)
            for _, pat in ipairs(FORBIDDEN) do
                T.ok(not code:find("%f[%w_]" .. pat), path .. " uses " .. pat)
            end
        end
    end,
    pure_modules_do_not_touch_picocalc = function()
        for _, path in ipairs(ls("src/*.lua")) do
            local name = path:match("src/(.-)%.lua$")
            if not DEVICE[name] then
                T.ok(not code_of(path):find("picocalc", 1, true), name .. " uses picocalc")
            end
        end
    end,
}
