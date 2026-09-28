local _typeof = typeof
local _type = type
local _tostring = tostring
local _tonumber = tonumber
local _pairs = pairs
local _ipairs = ipairs
local _pcall = pcall
local _xpcall = xpcall
local _select = select
local _unpack = table.unpack
local _insert = table.insert
local _concat = table.concat
local _find = table.find
local _clock = os.clock
local _time = os.time
local _random = math.random
local _floor = math.floor
local _max = math.max
local _min = math.min
local _format = string.format
local _sub = string.sub
local _gsub = string.gsub
local _match = string.match
local _lower = string.lower

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")


local ENV_ROOTS = {}

local function addEnvRoot(name, value)
    if _type(value) ~= "table" then
        return
    end
    for _, entry in _ipairs(ENV_ROOTS) do
        if entry.value == value then
            return
        end
    end
    _insert(ENV_ROOTS, {name = name, value = value})
end

do
    local okFenv, fenv = _pcall(function()
        return getfenv(0)
    end)
    if okFenv then
        addEnvRoot("getfenv(0)", fenv)
    end

    local okGenv, genv = _pcall(function()
        return getgenv()
    end)
    if okGenv then
        addEnvRoot("getgenv()", genv)
    end

    addEnvRoot("_G", _G)
end

local ROOT_ENV = (#ENV_ROOTS > 0 and ENV_ROOTS[1].value) or _G

local DEFAULT_CONFIG = {
    Network = true,
    FileSystem = true,
    Drawing = true,
    Debug = true,
    ScriptIntrospection = true,
    Metatable = true,
    Cache = true,
    Actors = true,
    Experimental = true,
    Invasive = false,
    SaveReport = true,
    Timeout = 7,
    VerboseSurface = false,
    RandomizeOrder = true,
}

local CONFIG = {}
for k, v in _pairs(DEFAULT_CONFIG) do
    CONFIG[k] = v
end

do
    local supplied
    for _, entry in _ipairs(ENV_ROOTS) do
        local candidate = rawget(entry.value, "uUNC_Config")
        if _type(candidate) == "table" then
            supplied = candidate
            break
        end
    end

    if _type(supplied) == "table" then
        for k, v in _pairs(supplied) do
            if DEFAULT_CONFIG[k] ~= nil then
                CONFIG[k] = v
            end
        end
    end
end

CONFIG.Timeout = _max(1, _tonumber(CONFIG.Timeout) or 7)

local function guid()
    local ok, value = _pcall(function()
        return HttpService:GenerateGUID(false)
    end)
    if ok and _type(value) == "string" then
        return value
    end
    return _format("%x-%x-%x", _floor(_clock() * 1e6), _random(1, 0x7fffffff), _time())
end

local RUN_ID = guid()
local NONCE = "uUNC-" .. guid() .. "-" .. _tostring(_random(100000, 999999))
local STARTED = _clock()

local function indexSafe(container, key)
    local ok, value = _pcall(function()
        return container[key]
    end)
    if ok then
        return value
    end
    return nil
end

local function resolveFrom(root, path)
    if _type(path) ~= "string" or path == "" then
        return nil
    end

    local current = root
    for key in string.gmatch(path, "[^.]+") do
        if current == nil then
            return nil
        end
        current = indexSafe(current, key)
    end
    return current
end

local function resolve(path)
    for _, entry in _ipairs(ENV_ROOTS) do
        local value = resolveFrom(entry.value, path)
        if value ~= nil then
            return value, entry.name
        end
    end
    return nil, nil
end

local function resolveAny(names)
    for _, name in _ipairs(names) do
        local value, envName = resolve(name)
        if value ~= nil then
            return value, name, envName
        end
    end
    return nil, nil, nil
end

local function callable(value)
    return _type(value) == "function"
end

local function assertf(condition, message, ...)
    if not condition then
        error(_format(message, ...), 2)
    end
    return condition
end

local function safeJson(value)
    local ok, encoded = _pcall(function()
        return HttpService:JSONEncode(value)
    end)
    return ok and encoded or nil
end

local function arrContainsIdentity(list, needle)
    for _, value in _ipairs(list) do
        if value == needle then
            return true
        end
    end
    return false
end

local function shallowArrayOfInstances(value, classA, classB)
    if _type(value) ~= "table" then
        return false, "return was not a table"
    end
    if #value == 0 then
        return true, "empty table (accepted, weak evidence)"
    end

    local sample = value[1]
    if _typeof(sample) ~= "Instance" then
        return false, "first entry was not an Instance"
    end

    if classA and not sample:IsA(classA) and (not classB or not sample:IsA(classB)) then
        return false, "unexpected instance type: " .. sample.ClassName
    end
    return true
end

local function sanitizeFileName(s)
    s = _tostring(s or "unknown")
    s = _gsub(s, "[^%w%._%-]", "_")
    return _sub(s, 1, 80)
end

local function echoedHeaderEquals(body, headerName, expected)
    if _type(body) ~= "string" then
        return false
    end
    local ok, data = _pcall(function()
        return HttpService:JSONDecode(body)
    end)
    if not ok or _type(data) ~= "table" or _type(data.headers) ~= "table" then
        return false
    end
    local wanted = _lower(headerName)
    for key, value in _pairs(data.headers) do
        if _type(key) == "string" and _lower(key) == wanted and _tostring(value) == expected then
            return true
        end
    end
    return false
end

local function echoRequest(requestFn, method, token, requestBody, contentType)
    local endpoints
    if method == "GET" then
        endpoints = {
            "https://httpbin.org/anything?uunc=" .. HttpService:UrlEncode(token),
            "https://postman-echo.com/get?uunc=" .. HttpService:UrlEncode(token),
        }
    else
        endpoints = {
            "https://httpbin.org/anything",
            "https://postman-echo.com/post",
        }
    end

    local errors = {}
    for _, url in _ipairs(endpoints) do
        local ok, response = _pcall(function()
            local headers = {
                ["X-uUNC-Challenge"] = token,
            }
            if contentType then
                headers["Content-Type"] = contentType
            end

            local options = {
                Url = url,
                Method = method,
                Headers = headers,
            }
            if requestBody ~= nil then
                options.Body = requestBody
            end
            return requestFn(options)
        end)

        if ok and _type(response) == "table" then
            local status = response.StatusCode or response.Status
            local body = response.Body or response.body
            local statusOK = _type(status) == "number" and status >= 200 and status < 300
            local bodyOK = _type(body) == "string" and string.find(body, token, 1, true) ~= nil
            local headerOK = bodyOK and echoedHeaderEquals(body, "X-uUNC-Challenge", token)
            if statusOK and bodyOK and headerOK then
                return response, url
            end
            _insert(errors, url .. " status/body/header verification failed")
        else
            _insert(errors, url .. " -> " .. _tostring(response))
        end
    end

    error("all public echo endpoints failed: " .. _concat(errors, " | "))
end

local function runTimed(callback, timeoutSeconds)
    local finished = false
    local ok = false
    local packed = nil

    local thread = task.spawn(function()
        local result = table.pack(_pcall(callback))
        ok = result[1] == true
        packed = result
        finished = true
    end)

    local deadline = _clock() + (timeoutSeconds or CONFIG.Timeout)
    while not finished and _clock() < deadline do
        task.wait()
    end

    if not finished then
        _pcall(function()
            task.cancel(thread)
        end)
        return false, "__UUNC_TIMEOUT__"
    end

    if not ok then
        return false, packed and packed[2] or "unknown error"
    end

    if not packed then
        return true
    end

    return true, _unpack(packed, 2, packed.n)
end


local CATALOG = {}

local function surface(category, canonical, aliases, tier)
    _insert(CATALOG, {
        category = category,
        canonical = canonical,
        aliases = aliases or {},
        tier = tier or "core",
    })
end

-- cache
surface("Cache", "cache.invalidate")
surface("Cache", "cache.iscached")
surface("Cache", "cache.replace")
surface("Cache", "cloneref")
surface("Cache", "compareinstances")

-- closures
surface("Closures", "checkcaller")
surface("Closures", "clonefunction")
surface("Closures", "getcallingscript")
surface("Closures", "getscriptclosure", {"getscriptfunction"})
surface("Closures", "hookfunction", {"replaceclosure"})
surface("Closures", "iscclosure")
surface("Closures", "islclosure")
surface("Closures", "isexecutorclosure", {"checkclosure", "isourclosure"})
surface("Closures", "loadstring")
surface("Closures", "newcclosure")


surface("Console", "rconsoleclear", {"consoleclear"}, "extended")
surface("Console", "rconsolecreate", {"consolecreate"}, "extended")
surface("Console", "rconsoledestroy", {"consoledestroy"}, "extended")
surface("Console", "rconsoleinput", {"consoleinput"}, "extended")
surface("Console", "rconsolename", {"consolename", "rconsolesettitle"}, "extended")
surface("Console", "rconsoleprint", {"consoleprint"}, "extended")
surface("Console", "rconsoleinfo", {"consoleinfo"}, "extended")
surface("Console", "rconsolewarn", {"consolewarn"}, "extended")
surface("Console", "rconsoleerr", {"consoleerr"}, "extended")


surface("Crypt", "crypt.base64encode", {"crypt.base64.encode", "crypt.base64_encode", "base64.encode", "base64_encode", "base64encode"}, "extended")
surface("Crypt", "crypt.base64decode", {"crypt.base64.decode", "crypt.base64_decode", "base64.decode", "base64_decode", "base64decode"}, "extended")
surface("Crypt", "crypt.encrypt", {}, "extended")
surface("Crypt", "crypt.decrypt", {}, "extended")
surface("Crypt", "crypt.generatebytes", {}, "extended")
surface("Crypt", "crypt.generatekey", {}, "extended")
surface("Crypt", "crypt.hash", {}, "extended")
surface("Compression", "lz4compress", {"crypt.lz4compress"}, "extended")
surface("Compression", "lz4decompress", {"crypt.lz4decompress"}, "extended")
surface("Compression", "zstdcompress", {"crypt.zstdcompress", "crypt.zstd.compress"}, "experimental")
surface("Compression", "zstddecompress", {"crypt.zstddecompress", "crypt.zstd.decompress"}, "experimental")

surface("Debug", "debug.getconstant")
surface("Debug", "debug.getconstants")
surface("Debug", "debug.getinfo", {"getinfo"})
surface("Debug", "debug.getproto")
surface("Debug", "debug.getprotos")
surface("Debug", "debug.getstack")
surface("Debug", "debug.getupvalue")
surface("Debug", "debug.getupvalues")
surface("Debug", "debug.setconstant")
surface("Debug", "debug.setstack")
surface("Debug", "debug.setupvalue")
surface("Debug", "setstackhidden", {}, "experimental")

surface("Filesystem", "appendfile")
surface("Filesystem", "delfile")
surface("Filesystem", "delfolder")
surface("Filesystem", "isfile")
surface("Filesystem", "isfolder")
surface("Filesystem", "listfiles")
surface("Filesystem", "loadfile")
surface("Filesystem", "makefolder")
surface("Filesystem", "readfile")
surface("Filesystem", "writefile")

surface("Input", "isrbxactive", {"isgameactive"}, "extended")
surface("Input", "keypress", {}, "extended")
surface("Input", "keyrelease", {}, "extended")
surface("Input", "mouse1click", {}, "extended")
surface("Input", "mouse1press", {}, "extended")
surface("Input", "mouse1release", {}, "extended")
surface("Input", "mouse2click", {}, "extended")
surface("Input", "mouse2press", {}, "extended")
surface("Input", "mouse2release", {}, "extended")
surface("Input", "mousemoveabs", {}, "extended")
surface("Input", "mousemoverel", {}, "extended")
surface("Input", "mousescroll", {}, "extended")

-- instance
surface("Instances", "fireclickdetector", {}, "extended")
surface("Instances", "fireproximityprompt", {}, "extended")
surface("Instances", "firetouchinterest", {}, "extended")
surface("Instances", "firesignal", {}, "extended")
surface("Instances", "getconnections")
surface("Instances", "getcustomasset", {"getsynasset"})
surface("Instances", "gethiddenproperty")
surface("Instances", "sethiddenproperty")
surface("Instances", "gethui")
surface("Instances", "getinstances")
surface("Instances", "getnilinstances")
surface("Instances", "isscriptable")
surface("Instances", "setscriptable")
surface("Instances", "setrbxclipboard", {}, "extended")

--
surface("Metatable", "getrawmetatable")
surface("Metatable", "hookmetamethod")
surface("Metatable", "getnamecallmethod")
surface("Metatable", "isreadonly")
surface("Metatable", "setrawmetatable")
surface("Metatable", "setreadonly")

-- netwrk
surface("Misc", "identifyexecutor", {"getexecutorname"})
surface("Misc", "messagebox", {}, "extended")
surface("Misc", "queue_on_teleport", {"queueonteleport"}, "extended")
surface("Network", "request", {"http.request", "http_request", "syn.request"})
surface("Misc", "setclipboard", {"toclipboard"}, "extended")
surface("Misc", "setfpscap", {}, "extended")
surface("Misc", "getfpscap", {}, "extended")
surface("Misc", "getfflag", {}, "extended")
surface("Misc", "setfflag", {"setfastflag"}, "extended")

-- script
surface("Scripts", "getgc")
surface("Scripts", "getgenv")
surface("Scripts", "getloadedmodules")
surface("Scripts", "getrenv")
surface("Scripts", "getrunningscripts")
surface("Scripts", "getscriptbytecode", {"dumpstring"})
surface("Scripts", "getscripthash")
surface("Scripts", "getscripts")
surface("Scripts", "getsenv")
surface("Scripts", "getthreadidentity", {"getidentity", "getthreadcontext"})
surface("Scripts", "setthreadidentity", {"setidentity", "setthreadcontext"})
surface("Scripts", "getfunctionbytecode", {}, "experimental")
surface("Scripts", "decompile", {}, "extended")
surface("Scripts", "saveinstance", {}, "extended")

-- drawin
surface("Drawing", "Drawing.new", {}, "extended")
surface("Drawing", "Drawing.Fonts", {}, "extended")
surface("Drawing", "isrenderobj", {}, "extended")
surface("Drawing", "getrenderproperty", {}, "extended")
surface("Drawing", "setrenderproperty", {}, "extended")
surface("Drawing", "cleardrawcache", {}, "extended")

surface("WebSocket", "WebSocket.connect", {"websocket.connect"}, "legacy")

surface("Actors", "getactors", {}, "extended")
surface("Actors", "run_on_actor", {"runonactor"}, "extended")
surface("Actors", "get_comm_channel", {}, "extended")
surface("Actors", "create_comm_channel", {}, "extended")
surface("Actors", "isparallel", {}, "extended")
surface("Actors", "getactorthreads", {}, "extended")
surface("Actors", "run_on_thread", {}, "extended")

local SURFACE_RESULTS = {}
local SURFACE_COUNTS = {
    core = {present = 0, total = 0},
    extended = {present = 0, total = 0},
    experimental = {present = 0, total = 0},
    legacy = {present = 0, total = 0},
}

for _, item in _ipairs(CATALOG) do
    local names = {item.canonical}
    for _, alias in _ipairs(item.aliases) do
        _insert(names, alias)
    end

    local value, resolvedName = resolveAny(names)
    local present = value ~= nil
    local valueType = present and _typeof(value) or "nil"

    SURFACE_COUNTS[item.tier] = SURFACE_COUNTS[item.tier] or {present = 0, total = 0}
    SURFACE_COUNTS[item.tier].total += 1
    if present then
        SURFACE_COUNTS[item.tier].present += 1
    end

    _insert(SURFACE_RESULTS, {
        category = item.category,
        canonical = item.canonical,
        resolved = resolvedName,
        present = present,
        type = valueType,
        tier = item.tier,
    })
end


local TESTS = {}
local RESULTS = {}
local INTEGRITY_FLAGS = {}

local function test(name, category, tier, dependencies, callback, options)
    _insert(TESTS, {
        name = name,
        category = category,
        tier = tier or "core",
        dependencies = dependencies or {},
        callback = callback,
        options = options or {},
    })
end

local function flag(kind, message, evidence)
    _insert(INTEGRITY_FLAGS, {
        kind = kind,
        message = message,
        evidence = evidence,
    })
end

local function dependencyState(dep)
    local names = {}
    if _type(dep) == "table" then
        for _, name in _ipairs(dep) do
            _insert(names, name)
        end
    else
        names[1] = dep
    end

    local value, resolvedName = resolveAny(names)
    return value, resolvedName, names
end

local function configEnabled(key)
    if not key then
        return true
    end
    return CONFIG[key] ~= false
end

local function record(testDef, status, detail, duration, resolvedDeps)
    _insert(RESULTS, {
        name = testDef.name,
        category = testDef.category,
        tier = testDef.tier,
        status = status,
        detail = detail,
        durationMs = _floor((duration or 0) * 1000 + 0.5),
        dependencies = resolvedDeps or {},
    })
end


test("identifyexecutor.semantic", "Misc", "core", {{"identifyexecutor", "getexecutorname"}}, function(deps)
    local f = deps[1]
    assertf(callable(f), "identifyexecutor/getexecutorname is not callable")
    local name, version = f()
    assertf(_type(name) == "string" and #name > 0, "executor name must be a non-empty string")
    if version ~= nil then
        assertf(_type(version) == "string" or _type(version) == "number", "version has invalid type: %s", _type(version))
    end
    return "executor=" .. name .. (version ~= nil and (" version=" .. _tostring(version)) or "")
end)

test("getgenv.roundtrip", "Scripts", "core", {{"getgenv"}}, function(deps)
    local f = deps[1]
    local a = f()
    local b = f()
    assertf(_type(a) == "table" and _type(b) == "table", "getgenv must return tables")
    local key = "__uUNC_" .. _gsub(RUN_ID, "%-", "")
    a[key] = NONCE
    assertf(b[key] == NONCE, "getgenv did not preserve shared mutation")
    a[key] = nil
    return "shared environment mutation verified"
end)

test("getrenv.semantic", "Scripts", "core", {{"getrenv"}}, function(deps)
    local env = deps[1]()
    assertf(_type(env) == "table", "getrenv must return a table")
    assertf(env.game == game, "getrenv().game is not the live DataModel reference")
    assertf(env._G ~= nil, "getrenv() is missing _G")
    return "Roblox environment reference verified"
end)

test("loadstring.execute", "Closures", "core", {{"loadstring"}}, function(deps)
    local loader = deps[1]
    local fn, compileError = loader("return function(x) return x .. ':ok' end")
    assertf(callable(fn), "loadstring failed to compile: %s", _tostring(compileError))
    local inner = fn()
    assertf(callable(inner), "compiled chunk did not return a function")
    assertf(inner(NONCE) == NONCE .. ":ok", "compiled code returned incorrect result")
    return "randomized execution verified"
end)

test("checkcaller.semantic", "Closures", "core", {{"checkcaller"}}, function(deps)
    local value = deps[1]()
    assertf(_type(value) == "boolean", "checkcaller must return boolean")
    assertf(value == true, "executor-originated uUNC thread should report checkcaller()==true")
    return "executor caller recognized"
end)

test("clonefunction.semantic", "Closures", "core", {{"clonefunction"}}, function(deps)
    local clonefunction_ = deps[1]
    local salt = _random(1000, 999999)
    local function original(x)
        return x + salt
    end
    local clone = clonefunction_(original)
    assertf(callable(clone), "clonefunction did not return a function")
    assertf(clone ~= original, "clonefunction returned the original function object")
    assertf(clone(17) == original(17), "clone result differs from original")
    return "distinct callable clone verified"
end)

test("closure.classifiers", "Closures", "core", {{"iscclosure"}, {"islclosure"}}, function(deps)
    local isc, isl = deps[1], deps[2]
    local function luaClosure() return NONCE end
    assertf(isc(print) == true, "iscclosure(print) should be true")
    assertf(isl(print) == false, "islclosure(print) should be false")
    assertf(isl(luaClosure) == true, "islclosure(Luau closure) should be true")
    assertf(isc(luaClosure) == false, "iscclosure(Luau closure) should be false")
    return "C/L closure split verified"
end)

test("newcclosure.semantic", "Closures", "core", {{"newcclosure"}, {"iscclosure"}}, function(deps)
    local newc, isc = deps[1], deps[2]
    local wrapped = newc(function(x)
        return x == NONCE and NONCE or "bad"
    end)
    assertf(callable(wrapped), "newcclosure did not return function")
    assertf(wrapped(NONCE) == NONCE, "newcclosure changed callable behavior")
    assertf(isc(wrapped) == true, "newcclosure result was not classified as C closure")
    return "call + closure classification verified"
end)

test("isexecutorclosure.semantic", "Closures", "core", {{"isexecutorclosure", "checkclosure", "isourclosure"}}, function(deps)
    local f = deps[1]
    local function ours() return NONCE end
    local ourResult = f(ours)
    local robloxResult = f(print)
    assertf(_type(ourResult) == "boolean" and _type(robloxResult) == "boolean", "classifier must return booleans")
    assertf(ourResult == true, "executor-created Luau closure was not recognized")
    assertf(robloxResult == false, "Roblox C closure 'print' was incorrectly classified as executor closure")
    return "positive and negative classification verified"
end)

test("hookfunction.local", "Closures", "core", {{"hookfunction", "replaceclosure"}}, function(deps)
    local hook = deps[1]
    local function target(x)
        return "original:" .. x
    end
    local original = hook(target, function(x)
        return "hooked:" .. x
    end)
    assertf(callable(original), "hookfunction did not return original callable")
    assertf(target(NONCE) == "hooked:" .. NONCE, "target behavior was not replaced")
    assertf(original(NONCE) == "original:" .. NONCE, "returned original callable is incorrect")
    return "local closure hook + original reference verified"
end) 

test("cloneref.compareinstances", "Cache", "core", {{"cloneref"}, {"compareinstances"}}, function(deps)
    local cloneRef, compare = deps[1], deps[2]
    local object = Instance.new("Folder")
    object.Name = "uUNC_" .. RUN_ID

    local clone = cloneRef(object)
    assertf(clone ~= nil, "cloneref returned nil")
    assertf(clone ~= object, "cloneref returned identical wrapper/reference")
    assertf(compare(object, clone) == true, "compareinstances did not recognize the same underlying Instance")

    clone.Name = "uUNC_mut_" .. _tostring(_random(1000, 9999))
    assertf(object.Name == clone.Name, "cloneref wrapper did not reference same underlying object")
    object:Destroy()
    return "reference identity + shared backing Instance verified"
end)

test("cache.invalidate", "Cache", "core", {{"cache.invalidate"}}, function(deps)
    local invalidate = deps[1]
    local container = Instance.new("Folder")
    local part = Instance.new("Part")
    part.Parent = container

    local before = container:FindFirstChild("Part")
    assertf(before ~= nil, "control reference was nil")
    invalidate(before)
    local after = container:FindFirstChild("Part")

    assertf(after ~= nil, "Instance disappeared after cache.invalidate")
    assertf(before ~= after, "reference was not invalidated")

    container:Destroy()
    return "historical UNC-style invalidation verified"
end, {config = "Cache"})

test("cache.replace", "Cache", "core", {{"cache.replace"}}, function(deps)
    local replace = deps[1]
    local part = Instance.new("Part")
    local fire = Instance.new("Fire")

    replace(part, fire)

    part:Destroy()
    fire:Destroy()
    return "cache.replace executed without error"
end, {config = "Cache"})



test("getrawmetatable.locked", "Metatable", "core", {{"getrawmetatable"}}, function(deps)
    local getraw = deps[1]
    local mt = {__metatable = "LOCKED_" .. NONCE, marker = NONCE}
    local object = setmetatable({}, mt)
    assertf(getmetatable(object) == "LOCKED_" .. NONCE, "control: Lua metatable lock did not apply")
    local raw = getraw(object)
    assertf(_type(raw) == "table", "getrawmetatable did not bypass __metatable lock")
    assertf(raw.marker == NONCE, "raw metatable content mismatch")
    return "__metatable lock bypass verified"
end, {config = "Metatable"})

test("readonly.roundtrip", "Metatable", "core", {{"isreadonly"}, {"setreadonly"}}, function(deps)
    local isro, setro = deps[1], deps[2]
    local t = {value = NONCE}
    setro(t, true)
    assertf(isro(t) == true, "table did not become readonly")
    local writeOk = _pcall(function()
        t.value = "mutated"
    end)

    
    assertf(writeOk == false, "readonly table still accepted mutation")
    setro(t, false)
    assertf(isro(t) == false, "table did not become writable")
    t.value = NONCE .. ":rw"
    assertf(t.value == NONCE .. ":rw", "writable table mutation failed")
    return "readonly -> write reject -> writable round-trip verified"
end, {config = "Metatable"})

test("setrawmetatable.semantic", "Metatable", "core", {{"setrawmetatable"}}, function(deps)
    local setraw = deps[1]
    local object = setmetatable({}, {__index = function() return "old" end, __metatable = "locked"})
    local returned = setraw(object, {__index = function(_, k) return k == "probe" and NONCE or nil end})
    assertf(object.probe == NONCE, "setrawmetatable did not alter lookup semantics")
    if returned ~= nil then
        assertf(returned == object, "non-nil return should be original object")
    end
    return "metatable semantics changed"
end, {config = "Metatable"})

test("hookmetamethod.local", "Metatable", "core", {{"hookmetamethod"}}, function(deps)
    local hook = deps[1]
    local object = setmetatable({}, {
        __index = function(_, key)
            return "original:" .. _tostring(key)
        end,
        __metatable = "locked",
    })

    local original = hook(object, "__index", function(_, key)
        return "hooked:" .. _tostring(key)
    end)

    assertf(callable(original), "hookmetamethod did not return original metamethod")
    assertf(object[NONCE] == "hooked:" .. NONCE, "hooked metamethod did not execute")
    assertf(original(object, NONCE) == "original:" .. NONCE, "original metamethod reference incorrect")
    return "local metamethod hook verified"
end, {config = "Metatable"})



test("debug.constants", "Debug", "core", {{"debug.getconstants"}, {"debug.setconstant"}}, function(deps)
    local getconstants_, setconstant_ = deps[1], deps[2]
    local MARKER = "uUNC_CONST_" .. NONCE
    local function target()
        return MARKER
    end

    local constants = getconstants_(target)
    assertf(_type(constants) == "table", "debug.getconstants must return table")

    local index
    for i, value in _ipairs(constants) do
        if value == MARKER then
            index = i
            break
        end
    end
    assertf(index ~= nil, "unique string constant was not found")

    local replacement = MARKER .. "_CHANGED"
    setconstant_(target, index, replacement)
    assertf(target() == replacement, "debug.setconstant did not affect function behavior")
    setconstant_(target, index, MARKER)
    assertf(target() == MARKER, "failed to restore original constant")
    return "constant read/write/restore verified"
end, {config = "Debug"})

test("debug.upvalues", "Debug", "core", {{"debug.getupvalues"}, {"debug.setupvalue"}}, function(deps)
    local getupvalues_, setupvalue_ = deps[1], deps[2]
    local secret = "uUNC_UP_" .. NONCE
    local function target()
        return secret
    end

    local values = getupvalues_(target)
    assertf(_type(values) == "table", "debug.getupvalues must return table")

    local index
    for i, value in _pairs(values) do
        if value == secret then
            index = i
            break
        end
    end
    assertf(index ~= nil, "unique upvalue not found")

    local replacement = secret .. "_CHANGED"
    setupvalue_(target, index, replacement)
    assertf(target() == replacement, "debug.setupvalue did not mutate upvalue")
    setupvalue_(target, index, secret)
    assertf(target() == secret, "failed to restore upvalue")
    return "upvalue read/write/restore verified"
end, {config = "Debug"})

test("debug.protos", "Debug", "core", {{"debug.getprotos"}}, function(deps)
    local getprotos_ = deps[1]
    local function outer()
        local function alpha() return "A_" .. NONCE end
        local function beta() return "B_" .. NONCE end
        return alpha, beta
    end

    local protos = getprotos_(outer)
    assertf(_type(protos) == "table", "debug.getprotos must return table")
    assertf(#protos >= 2, "expected at least two nested prototypes, got %d", #protos)
    for _, proto in _ipairs(protos) do
        assertf(callable(proto), "prototype entry is not callable/function-like")
    end
    return "nested prototype enumeration verified"
end, {config = "Debug"})

test("debug.getinfo", "Debug", "core", {{"debug.getinfo", "getinfo"}}, function(deps)
    local getinfo_ = deps[1]
    local function namedProbe(a, b)
        return a, b
    end
    local info = getinfo_(namedProbe)
    assertf(_type(info) == "table", "getinfo must return table")
    local hasUsefulField = info.numparams ~= nil or info.nparams ~= nil or info.source ~= nil or info.short_src ~= nil or info.name ~= nil
    assertf(hasUsefulField, "getinfo returned a table with no recognizable metadata")
    return "function metadata returned"
end, {config = "Debug"})




test("filesystem.roundtrip", "Filesystem", "core",
    {{"makefolder"}, {"writefile"}, {"readfile"}, {"appendfile"}, {"isfile"}, {"isfolder"}, {"listfiles"}, {"delfile"}, {"delfolder"}},
    function(deps)
        local makefolder_, writefile_, readfile_, appendfile_, isfile_, isfolder_, listfiles_, delfile_, delfolder_ =
            deps[1], deps[2], deps[3], deps[4], deps[5], deps[6], deps[7], deps[8], deps[9]

        local root = "uUNC_" .. sanitizeFileName(RUN_ID)
        local file = root .. "/roundtrip_" .. _tostring(_random(100000, 999999)) .. ".txt"
        local first = NONCE .. "::A"
        local second = "::" .. NONCE .. "::B"

        _pcall(function() delfolder_(root) end)
        makefolder_(root)
        assertf(isfolder_(root) == true, "makefolder/isfolder round-trip failed")

        writefile_(file, first)
        assertf(isfile_(file) == true, "writefile did not create a file")
        assertf(readfile_(file) == first, "readfile content mismatch after writefile")

        appendfile_(file, second)
        local joined = readfile_(file)
        assertf(joined == first .. second, "appendfile did not append exact bytes")

        local list = listfiles_(root)
        assertf(_type(list) == "table", "listfiles did not return table")
        local found = false
        for _, path in _ipairs(list) do
            if _type(path) == "string" and (_match(path, "roundtrip_") or path == file) then
                found = true
                break
            end
        end
        assertf(found, "listfiles did not enumerate the created file")

        delfile_(file)
        assertf(isfile_(file) == false, "delfile did not remove file")
        delfolder_(root)
        assertf(isfolder_(root) == false, "delfolder did not remove folder")
        return "create/write/read/append/list/delete round-trip verified"
    end,
    {config = "FileSystem"}
)

test("loadfile.execute", "Filesystem", "extended", {{"writefile"}, {"loadfile"}, {"delfile"}}, function(deps)
    local writefile_, loadfile_, delfile_ = deps[1], deps[2], deps[3]
    local path = "uUNC_loadfile_" .. sanitizeFileName(RUN_ID) .. ".lua"
    writefile_(path, "return " .. string.format("%q", NONCE))
    local chunk, err = loadfile_(path)
    assertf(callable(chunk), "loadfile did not return callable: %s", _tostring(err))
    assertf(chunk() == NONCE, "loadfile executed incorrect content")
    delfile_(path)
    return "file compilation/execution verified"
end, {config = "FileSystem"})
------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------
------------------------------------------------------------
test("getinstances.contains", "Instances", "core", {{"getinstances"}}, function(deps)
    local getinstances_ = deps[1]
    local marker = Instance.new("Folder")
    marker.Name = "uUNC_INSTANCE_" .. RUN_ID
    marker.Parent = workspace

    local list = getinstances_()
    assertf(_type(list) == "table", "getinstances must return table")
    assertf(arrContainsIdentity(list, marker), "getinstances did not include a live unique Instance")

    marker:Destroy()
    return "live unique Instance found"
end)

test("getnilinstances.semantic", "Instances", "core", {{"getnilinstances"}}, function(deps)
    local list = deps[1]()
    assertf(_type(list) == "table", "getnilinstances must return table")

    if #list == 0 then
        return "__UUNC_SKIP__:empty list; no safe sample to validate"
    end

    assertf(_typeof(list[1]) == "Instance", "first entry is not an Instance")
    assertf(list[1].Parent == nil, "first entry is not parented to nil")
    return "historical UNC-style nil Instance validation passed"
end)

test("getconnections.observable", "Instances", "core", {{"getconnections"}}, function(deps)
    local getconnections_ = deps[1]
    local bindable = Instance.new("BindableEvent")
    local connection = bindable.Event:Connect(function() end)

    local connections = getconnections_(bindable.Event)
    assertf(_type(connections) == "table", "getconnections must return table")
    assertf(#connections >= 1, "connected signal returned zero connections")

    local usable = false
    for _, c in _ipairs(connections) do
        if c ~= nil then
            local enabled = indexSafe(c, "Enabled")
            local disable = indexSafe(c, "Disable")
            local disconnect = indexSafe(c, "Disconnect")
            if enabled ~= nil or callable(disable) or callable(disconnect) then
                usable = true
                break
            end
        end
    end
    assertf(usable, "connection entries expose no recognizable connection semantics")
    connection:Disconnect()
    bindable:Destroy()
    return "real connected signal enumerated"
end)

test("firesignal.observable", "Instances", "extended", {{"firesignal"}}, function(deps)
    local firesignal_ = deps[1]
    local bindable = Instance.new("BindableEvent")
    local seen = nil
    local connection = bindable.Event:Connect(function(value)
        seen = value
    end)

    firesignal_(bindable.Event, NONCE)
    task.wait()
    assertf(seen == NONCE, "firesignal did not deliver randomized argument to live connection")

    connection:Disconnect()
    bindable:Destroy()
    return "signal delivery verified"
end)

test("gethui.semantic", "Instances", "core", {{"gethui"}}, function(deps)
    local hui = deps[1]()
    assertf(_typeof(hui) == "Instance", "gethui must return an Instance")
    assertf(hui:IsA("BasePlayerGui") or hui:IsA("Folder") or hui:IsA("ScreenGui") or hui:IsA("PlayerGui") or hui == game:GetService("CoreGui"),
        "gethui returned unexpected class: %s", hui.ClassName)
    return "container=" .. hui:GetFullName()
end)

test("getgc.semantic", "Scripts", "core", {{"getgc"}}, function(deps)
    local getgc_ = deps[1]
    local values = getgc_(true)
    assertf(_type(values) == "table", "getgc must return table")
    assertf(#values > 0, "getgc returned empty table")
    local sawFunction = false
    for i = 1, _min(#values, 5000) do
        if _type(values[i]) == "function" then
            sawFunction = true
            break
        end
    end
    assertf(sawFunction, "getgc sample contained no functions")
    return "non-empty GC set with functions"
end, {config = "ScriptIntrospection"})

test("getloadedmodules.semantic", "Scripts", "core", {{"getloadedmodules"}}, function(deps)
    local values = deps[1]()
    local ok, reason = shallowArrayOfInstances(values, "ModuleScript")
    assertf(ok, reason)
    return "ModuleScript list shape verified"
end, {config = "ScriptIntrospection"})

test("getscripts.semantic", "Scripts", "core", {{"getscripts"}}, function(deps)
    local values = deps[1]()
    local ok, reason = shallowArrayOfInstances(values, "LocalScript", "ModuleScript")
    assertf(ok, reason)
    return "script list shape verified"
end, {config = "ScriptIntrospection"})

test("getrunningscripts.semantic", "Scripts", "core", {{"getrunningscripts"}}, function(deps)
    local values = deps[1]()
    local ok, reason = shallowArrayOfInstances(values, "LocalScript", "ModuleScript")
    assertf(ok, reason)
    return "running script list shape verified"
end, {config = "ScriptIntrospection"})

local function findScriptTarget(requireModule)
    local candidates = {}

    local getrunning = resolve("getrunningscripts")
    if callable(getrunning) then
        local ok, values = _pcall(getrunning)
        if ok and _type(values) == "table" then
            for _, item in _ipairs(values) do
                if _typeof(item) == "Instance" then
                    if requireModule and item:IsA("ModuleScript") then
                        _insert(candidates, item)
                    elseif not requireModule and (item:IsA("LocalScript") or item:IsA("ModuleScript")) then
                        _insert(candidates, item)
                    end
                end
            end
        end
    end

    local player = Players.LocalPlayer
    if player and player.Character then
        local animate = player.Character:FindFirstChild("Animate")
        if animate and animate:IsA("LocalScript") and not requireModule then
            _insert(candidates, 1, animate)
        end
    end

    return candidates[1]
end

test("getscriptbytecode.semantic", "Scripts", "core", {{"getscriptbytecode", "dumpstring"}}, function(deps)
    local target = findScriptTarget(false)
    if not target then
        return "__UUNC_SKIP__:no LocalScript/ModuleScript target available"
    end
    local bytes = deps[1](target)
    assertf(_type(bytes) == "string", "getscriptbytecode must return string")
    assertf(#bytes > 8, "bytecode result is implausibly short")
    return "bytecode bytes=" .. #bytes .. " target=" .. target.ClassName
end, {config = "ScriptIntrospection"})

test("getscripthash.stability", "Scripts", "core", {{"getscripthash"}}, function(deps)
    local target = findScriptTarget(false)
    if not target then
        return "__UUNC_SKIP__:no script target available"
    end
    local a = deps[1](target)
    local b = deps[1](target)
    assertf(_type(a) == "string" and #a >= 8, "getscripthash returned invalid hash")
    assertf(a == b, "same unchanged script produced unstable hashes")
    return "stable hash len=" .. #a
end, {config = "ScriptIntrospection"})

test("getsenv.semantic", "Scripts", "core", {{"getsenv"}}, function(deps)
    local target = findScriptTarget(false)
    if not target or not target:IsA("LocalScript") then
        return "__UUNC_SKIP__:no LocalScript target available"
    end
    local env = deps[1](target)
    assertf(_type(env) == "table", "getsenv must return table")
    if env.script ~= nil then
        assertf(env.script == target, "getsenv().script does not match target")
    end
    return "script environment table returned"
end, {config = "ScriptIntrospection"})

test("getscriptclosure.semantic", "Scripts", "core", {{"getscriptclosure", "getscriptfunction"}}, function(deps)
    local target = findScriptTarget(true)
    if not target then
        return "__UUNC_SKIP__:no ModuleScript target available"
    end
    local closure = deps[1](target)
    assertf(callable(closure), "getscriptclosure did not return function")
    return "closure generated for " .. target:GetFullName()
end, {config = "ScriptIntrospection"})

test("threadidentity.roundtrip", "Scripts", "extended",
    {{"getthreadidentity", "getidentity", "getthreadcontext"}, {"setthreadidentity", "setidentity", "setthreadcontext"}},
    function(deps)
        local getid, setid = deps[1], deps[2]
        local original = getid()
        assertf(_type(original) == "number", "getthreadidentity must return number")

        local target = original == 3 and 2 or 3
        local okSet, err = _pcall(function() setid(target) end)
        if not okSet then
            error("setthreadidentity errored: " .. _tostring(err))
        end

        local observed = getid()
        local restoreOk, restoreErr = _pcall(function() setid(original) end)
        assertf(restoreOk, "CRITICAL: failed to restore thread identity: %s", _tostring(restoreErr))
        assertf(observed == target, "identity setter did not produce requested value; expected %s got %s", _tostring(target), _tostring(observed))
        assertf(getid() == original, "identity did not restore to original value")
        return _format("%s -> %s -> %s", original, target, original)
    end,
    {config = "ScriptIntrospection"}
)


test("request.GET.echo", "Network", "core", {{"request", "http.request", "http_request", "syn.request"}}, function(deps)
    local request_ = deps[1]
    local token = NONCE .. "-GET-" .. _tostring(_random(100000, 999999))
    local _, endpoint = echoRequest(request_, "GET", token, nil, nil)
    return "GET echo + custom header verified via " .. endpoint
end, {config = "Network", external = true})

test("request.POST.echo", "Network", "core", {{"request", "http.request", "http_request", "syn.request"}}, function(deps)
    local request_ = deps[1]
    local token = NONCE .. "-POST-" .. _tostring(_random(100000, 999999))
    local payload = safeJson({uunc = token, run = RUN_ID})
    assertf(payload ~= nil, "failed to encode randomized POST body")

    local _, endpoint = echoRequest(request_, "POST", token, payload, "application/json")
    return "POST body + custom header echo verified via " .. endpoint
end, {config = "Network", external = true})

test("request.POST.large-body", "Network", "experimental", {{"request", "http.request", "http_request", "syn.request"}}, function(deps)
    if CONFIG.Experimental == false then
        return "__UUNC_SKIP__:experimental tests disabled"
    end

    local request_ = deps[1]
    local tail = NONCE .. "-TAIL-" .. _tostring(_random(100000, 999999))
    local bodyData = string.rep("uUNC0123456789abcdef", 2048) .. tail -- ~36 KiB + unique tail

    local _, endpoint = echoRequest(request_, "POST", tail, bodyData, "text/plain")
    return "large POST body tail + header verified via " .. endpoint
end, {config = "Network", external = true, timeout = 12})

test("HttpGet.second-argument-shape", "Network", "experimental", {}, function()
    if CONFIG.Experimental == false then
        return "__UUNC_SKIP__:experimental tests disabled"
    end

    local token = NONCE .. "-HTTPGET-" .. _tostring(_random(100000, 999999))
    local urls = {
        "https://httpbin.org/anything?uunc=" .. HttpService:UrlEncode(token),
        "https://postman-echo.com/get?uunc=" .. HttpService:UrlEncode(token),
    }

    local lastError
    for _, url in _ipairs(urls) do
        local ok, body = _pcall(function()
            return game:HttpGet(url, true)
        end)
        if ok and _type(body) == "string" and string.find(body, token, 1, true) ~= nil then
            return "second argument accepted via " .. url .. "; cache semantics not claimed"
        end
        lastError = body
    end

    error("game:HttpGet(url, true) failed on both public echo endpoints: " .. _tostring(lastError))
end, {config = "Network", external = true})

test("base64.roundtrip", "Crypt", "extended",
    {{"crypt.base64encode", "crypt.base64.encode", "crypt.base64_encode", "base64.encode", "base64_encode", "base64encode"},
     {"crypt.base64decode", "crypt.base64.decode", "crypt.base64_decode", "base64.decode", "base64_decode", "base64decode"}},
    function(deps)
        local enc, dec = deps[1], deps[2]
        local raw = NONCE .. "\0\x01\x02" .. NONCE
        local encoded = enc(raw)
        assertf(_type(encoded) == "string" and encoded ~= raw and #encoded > 0, "base64 encoder returned invalid output")
        local decoded = dec(encoded)
        assertf(decoded == raw, "base64 decode(encode(x)) != x")
        return "binary-safe base64 round-trip verified"
    end
)

test("crypt.hash.sha256", "Crypt", "extended", {{"crypt.hash"}}, function(deps)
    local hash = deps[1]
    local expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    local attempts = {
        function() return hash("abc", "sha256") end,
        function() return hash("abc", "sha-256") end,
        function() return hash("abc", "SHA256") end,
    }

    local last
    for _, attempt in _ipairs(attempts) do
        local ok, value = _pcall(attempt)
        if ok and _type(value) == "string" then
            last = _lower(value)
            if last == expected then
                return "known SHA-256 vector verified"
            end
        end
    end

    error("crypt.hash exists but no tested SHA-256 spelling matched known vector; last=" .. _tostring(last))
end)

test("lz4.roundtrip", "Compression", "extended",
    {{"lz4compress", "crypt.lz4compress"}, {"lz4decompress", "crypt.lz4decompress"}},
    function(deps)
        local compress, decompress = deps[1], deps[2]
        local raw = string.rep(NONCE .. "|", 16)
        local packed = compress(raw)
        assertf(_type(packed) == "string" and #packed > 0, "lz4compress returned invalid data")

        local ok1, restored = _pcall(function()
            return decompress(packed, #raw)
        end)
        if not ok1 then
            local ok2, restored2 = _pcall(function()
                return decompress(packed)
            end)
            assertf(ok2, "lz4decompress failed both supported signatures")
            restored = restored2
        end

        assertf(restored == raw, "LZ4 round-trip mismatch")
        return "LZ4 round-trip verified"
    end
)

test("zstd.roundtrip", "Compression", "experimental",
    {{"zstdcompress", "crypt.zstdcompress", "crypt.zstd.compress"}, {"zstddecompress", "crypt.zstddecompress", "crypt.zstd.decompress"}},
    function(deps)
        if CONFIG.Experimental == false then
            return "__UUNC_SKIP__:experimental tests disabled"
        end
        local raw = string.rep(NONCE .. "|", 16)
        local packed = deps[1](raw)
        assertf(_type(packed) == "string" and #packed > 0, "zstdcompress returned invalid data")
        local restored = deps[2](packed)
        assertf(restored == raw, "Zstandard round-trip mismatch")
        return "Zstandard round-trip verified"
    end
)

-- ddrawing

test("Drawing.new.semantic", "Drawing", "extended", {{"Drawing.new"}}, function(deps)
    local drawingNew = deps[1]
    local before = #game:GetService("CoreGui"):GetDescendants()

    local square = drawingNew("Square")
    assertf(square ~= nil, "Drawing.new returned nil")

    square.Visible = false
    square.Position = Vector2.new(17, 29)
    square.Size = Vector2.new(31, 37)

    assertf(square.Visible == false, "Drawing.Visible property did not round-trip")
    assertf(square.Position == Vector2.new(17, 29), "Drawing.Position did not round-trip")
    assertf(square.Size == Vector2.new(31, 37), "Drawing.Size did not round-trip")

    local destroy = indexSafe(square, "Destroy")
    local remove = indexSafe(square, "Remove")
    if callable(destroy) then
        destroy(square)
    elseif callable(remove) then
        remove(square)
    else
        error("Drawing object has neither Destroy nor Remove")
    end

    task.wait()
    local after = #game:GetService("CoreGui"):GetDescendants()
    if after > before + 2 then
        flag("drawing-overlay", "Drawing.new coincided with new CoreGui descendants; possible Lua/UI overlay implementation", {
            before = before,
            after = after,
        })
    end

    return "property round-trip + destruction verified"
end, {config = "Drawing"})

-- fps stuff

test("fpscap.roundtrip", "Misc", "extended", {{"setfpscap"}, {"getfpscap"}}, function(deps)
    local setcap, getcap = deps[1], deps[2]
    local original = getcap()
    assertf(_type(original) == "number", "getfpscap must return number")

    local target = original == 61 and 73 or 61
    setcap(target)
    task.wait()
    local observed = getcap()
    setcap(original)
    assertf(_type(observed) == "number", "getfpscap after set returned non-number")
    assertf(math.abs(observed - target) <= 1, "setfpscap/getfpscap mismatch: requested %s observed %s", target, observed)
    return _format("%s -> %s -> %s", original, observed, original)
end)
---- 

test("actors.getactors.shape", "Actors", "extended", {{"getactors"}}, function(deps)
    local actors = deps[1]()
    assertf(_type(actors) == "table", "getactors must return table")
    for i = 1, _min(#actors, 50) do
        local actor = actors[i]
        assertf(_typeof(actor) == "Instance" and actor:IsA("Actor"), "getactors entry %d is not Actor", i)
    end
    return "Actor list shape verified; count=" .. #actors
end, {config = "Actors"})

test("actors.isparallel.shape", "Actors", "extended", {{"isparallel"}}, function(deps)
    local value = deps[1]()
    assertf(_type(value) == "boolean", "isparallel must return boolean")
    return "isparallel=" .. _tostring(value)
end, {config = "Actors"})

test("getfunctionbytecode.semantic", "Scripts", "experimental", {{"getfunctionbytecode"}}, function(deps)
    if CONFIG.Experimental == false then
        return "__UUNC_SKIP__:experimental tests disabled"
    end
    local function probe()
        return "uUNC_FUNCTION_BYTECODE_" .. NONCE
    end
    local bytes = deps[1](probe)
    assertf(_type(bytes) == "string", "getfunctionbytecode must return string")
    assertf(#bytes > 8, "function bytecode result is implausibly short")
    return "function bytecode bytes=" .. #bytes
end, {config = "ScriptIntrospection"})

local SYMBOL = {
    PASS = "✅",
    FAIL = "⛔",
    MISSING = "❌",
    UNVERIFIED = "⚪",
    SKIP = "⏭️",
    SPOOF = "🚩",
}

print("\n")
print("============================================================")
print("uUNC — Ultra Unified Naming Convention")
--print("  " .. RUN_ID)
print("============================================================")
print("✅ PASS  ⛔ FAIL  ❌ MISSING  ⚪ UNVERIFIED  ⏭️ SKIP  🚩 SPOOF?")
print("Random challenge: " .. NONCE)
print("")

local executorName = "Unknown"
local executorVersion = nil
do
    local f = resolveAny({"identifyexecutor", "getexecutorname"})
    if callable(f) then
        local ok, name, version = _pcall(f)
        if ok and _type(name) == "string" then
            executorName = name
            executorVersion = version
        end
    end
end

print("Executor: " .. executorName .. (executorVersion ~= nil and (" | " .. _tostring(executorVersion)) or ""))
do
    local roots = {}
    for _, entry in _ipairs(ENV_ROOTS) do
        _insert(roots, entry.name)
    end
    print("Environment roots: " .. _concat(roots, " -> "))
end
print("")

if CONFIG.RandomizeOrder ~= false then
    for i = #TESTS, 2, -1 do
        local j = _random(1, i)
        TESTS[i], TESTS[j] = TESTS[j], TESTS[i]
    end
    print("Test order: randomized for this run")
    print("")
end

for _, t in _ipairs(TESTS) do
    local optionConfig = t.options and t.options.config
    if optionConfig and not configEnabled(optionConfig) then
        record(t, "SKIP", "disabled by config: " .. optionConfig, 0, {})
        print(SYMBOL.SKIP .. " [" .. t.category .. "] " .. t.name .. " • disabled")
        continue
    end

    if t.tier == "experimental" and CONFIG.Experimental == false then
        record(t, "SKIP", "experimental disabled", 0, {})
        print(SYMBOL.SKIP .. " [" .. t.category .. "] " .. t.name .. " • experimental disabled")
        continue
    end

    local deps = {}
    local depNames = {}
    local missing = {}

    for _, dep in _ipairs(t.dependencies) do
        local value, resolvedName, candidateNames = dependencyState(dep)
        _insert(deps, value)
        _insert(depNames, resolvedName or _concat(candidateNames, "|"))
        if value == nil then
            _insert(missing, _concat(candidateNames, "|"))
        elseif not callable(value) then
            _insert(missing, (resolvedName or candidateNames[1]) .. " (not callable: " .. _typeof(value) .. ")")
        end
    end

    if #missing > 0 then
        local detail = "missing dependency: " .. _concat(missing, ", ")
        record(t, "MISSING", detail, 0, depNames)
        print(SYMBOL.MISSING .. " [" .. t.category .. "] " .. t.name .. " • " .. detail)
        continue
    end

    local t0 = _clock()
    local ok, value = runTimed(function()
        return t.callback(deps)
    end, t.options and t.options.timeout or CONFIG.Timeout)
    local elapsed = _clock() - t0

    if not ok then
        local message = _tostring(value)
        if message == "__UUNC_TIMEOUT__" then
            flag("timeout", t.name .. " timed out while its dependencies were present", {test = t.name})
            record(t, "FAIL", "timeout after " .. CONFIG.Timeout .. "s", elapsed, depNames)
            print(SYMBOL.FAIL .. " [" .. t.category .. "] " .. t.name .. " • TIMEOUT")
        else
            flag("behavior-failure", t.name .. " exists but failed behavioral verification", {
                test = t.name,
                error = message,
            })
            record(t, "FAIL", message, elapsed, depNames)
            print(SYMBOL.FAIL .. " [" .. t.category .. "] " .. t.name .. " • " .. message)
        end
    else
        local detail = value ~= nil and _tostring(value) or "verified"
        if string.sub(detail, 1, 14) == "__UUNC_SKIP__:" then
            detail = string.sub(detail, 15)
            record(t, "SKIP", detail, elapsed, depNames)
            print(SYMBOL.SKIP .. " [" .. t.category .. "] " .. t.name .. " • " .. detail)
        else
            record(t, "PASS", detail, elapsed, depNames)
            print(SYMBOL.PASS .. " [" .. t.category .. "] " .. t.name .. " • " .. detail)
        end
    end
end

-- scan for faked functions
do
    local buckets = {}
    for _, item in _ipairs(CATALOG) do
        local names = {item.canonical}
        for _, alias in _ipairs(item.aliases) do
            _insert(names, alias)
        end
        local value, resolvedName = resolveAny(names)
        if callable(value) then
            local bucket = buckets[value]
            if not bucket then
                bucket = {}
                buckets[value] = bucket
            end
            _insert(bucket, resolvedName or item.canonical)
        end
    end

    for _, names in _pairs(buckets) do
        if #names >= 4 then
            flag("shared-stub", "same function object backs 4+ unrelated exported APIs", names)
        end
    end
end

do
    local pass, fail = 0, 0
    for _, r in _ipairs(RESULTS) do
        if r.status == "PASS" then
            pass += 1
        elseif r.status == "FAIL" then
            fail += 1
        end
    end

    if fail >= 4 and fail >= pass * 0.25 then
        flag("systemic-failure", "many declared capabilities failed semantic checks", {
            pass = pass,
            fail = fail,
        })
    end
end

local function pct(a, b)
    if b <= 0 then
        return 0
    end
    return _floor((a / b) * 1000 + 0.5) / 10
end

local behavior = {
    PASS = 0,
    FAIL = 0,
    MISSING = 0,
    SKIP = 0,
}
local coreBehavior = {
    PASS = 0,
    FAIL = 0,
    MISSING = 0,
    SKIP = 0,
}
local byCategory = {}

for _, r in _ipairs(RESULTS) do
    behavior[r.status] = (behavior[r.status] or 0) + 1

    byCategory[r.category] = byCategory[r.category] or {PASS = 0, FAIL = 0, MISSING = 0, SKIP = 0}
    byCategory[r.category][r.status] = (byCategory[r.category][r.status] or 0) + 1

    if r.tier == "core" then
        coreBehavior[r.status] = (coreBehavior[r.status] or 0) + 1
    end
end

local coreBehaviorDenom = coreBehavior.PASS + coreBehavior.FAIL + coreBehavior.MISSING
local attemptedPresent = behavior.PASS + behavior.FAIL

local coreSurface = SURFACE_COUNTS.core or {present = 0, total = 0}
local extendedSurface = SURFACE_COUNTS.extended or {present = 0, total = 0}
local experimentalSurface = SURFACE_COUNTS.experimental or {present = 0, total = 0}

local verifiedCoverage = pct(coreBehavior.PASS, coreBehaviorDenom)
local reliability = pct(behavior.PASS, attemptedPresent)
local coreSurfaceCoverage = pct(coreSurface.present, coreSurface.total)
local extendedSurfaceCoverage = pct(extendedSurface.present, extendedSurface.total)

local suspicion
if #INTEGRITY_FLAGS == 0 then
    suspicion = "NO FLAGS"
elseif #INTEGRITY_FLAGS <= 2 then
    suspicion = "LOW"
elseif #INTEGRITY_FLAGS <= 5 then
    suspicion = "MEDIUM"
else
    suspicion = "HIGH"
end

print("\n============================================================")
print("                     uUNC SUMMARY")
print("============================================================")
print(_format("Core surface coverage:   %5.1f%%  (%d/%d API groups found)", coreSurfaceCoverage, coreSurface.present, coreSurface.total))
print(_format("Extended surface:        %5.1f%%  (%d/%d API groups found)", extendedSurfaceCoverage, extendedSurface.present, extendedSurface.total))
print(_format("Experimental surface:             (%d/%d API groups found; NOT core-scored)", experimentalSurface.present, experimentalSurface.total))
print(_format("Core verified coverage: %5.1f%%  (%d PASS / %d scored behavioral tests)", verifiedCoverage, coreBehavior.PASS, coreBehaviorDenom))
print(_format("Behavior reliability:   %5.1f%%  (%d PASS / %d attempted-present tests)", reliability, behavior.PASS, attemptedPresent))
print(_format("Behavior failures:                %d", behavior.FAIL))
print(_format("Behavior missing:                 %d", behavior.MISSING))
print(_format("Skipped/inconclusive:             %d", behavior.SKIP))
print(_format("Integrity flags:                  %d (%s)", #INTEGRITY_FLAGS, suspicion))

if #INTEGRITY_FLAGS > 0 then
    print("\nIntegrity / spoof-resistance flags:")
    for i, item in _ipairs(INTEGRITY_FLAGS) do
        print(_format("🚩 %02d. [%s] %s", i, item.kind, item.message))
    end
end

if CONFIG.VerboseSurface then
    print("\nSurface details:")
    for _, s in _ipairs(SURFACE_RESULTS) do
        local mark = s.present and "•" or "-"
        print(_format("%s [%s/%s] %-28s -> %-22s (%s)",
            mark,
            s.tier,
            s.category,
            s.canonical,
            s.resolved or "MISSING",
            s.type
        ))
    end
end

local REPORT = {
    schema = 1,
    benchmark = "uUNC",
    benchmarkLongName = "Ultra Unified Naming Convention",
    --version = "2026.09.26-r2",
    runId = RUN_ID,
    nonce = NONCE,
    executor = {
        name = executorName,
        version = executorVersion ~= nil and _tostring(executorVersion) or nil,
    },
    config = CONFIG,
    durationMs = _floor((_clock() - STARTED) * 1000 + 0.5),
    scores = {
        coreSurfaceCoverage = coreSurfaceCoverage,
        extendedSurfaceCoverage = extendedSurfaceCoverage,
        coreVerifiedCoverage = verifiedCoverage,
        behaviorReliability = reliability,
        integritySuspicion = suspicion,
    },
    counts = {
        surface = SURFACE_COUNTS,
        behavior = behavior,
        coreBehavior = coreBehavior,
        integrityFlags = #INTEGRITY_FLAGS,
    },
    surface = SURFACE_RESULTS,
    tests = RESULTS,
    integrity = INTEGRITY_FLAGS,
}

local reportJson = safeJson(REPORT)
local savedPath = nil

if CONFIG.SaveReport and reportJson and callable(resolve("writefile")) then
    local filename = "uUNC-report-" .. sanitizeFileName(executorName) .. "-" .. sanitizeFileName(_tostring(_time())) .. ".json"
    local ok, err = _pcall(function()
        resolve("writefile")(filename, reportJson)
    end)
    if ok then
        savedPath = filename
        print("\nReport saved: " .. filename)
    else
        print("\n⚠️ Report JSON generated but could not be saved: " .. _tostring(err))
    end
end

REPORT.savedPath = savedPath

print(_format("Finished in %.2fs", _clock() - STARTED))
print("============================================================")
print("")

for _, entry in _ipairs(ENV_ROOTS) do
    _pcall(function()
        entry.value.uUNC_LastReport = REPORT
    end)
end

return REPORT
