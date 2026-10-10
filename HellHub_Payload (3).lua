--[[
    HELL HUB — Payload + Key System
    .gg/hellhub

    • Рандомные ключи
    • 1 ключ = 1 устройство (HWID)
    • Без валидного ключа скрипт не грузится
]]

if _G.HellHubLoading or _G.HellHubLoaded then
    warn("[HELL] Already loaded")
    return
end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
if not player then
    repeat task.wait() until Players.LocalPlayer
    player = Players.LocalPlayer
end

-- =========================================================
-- ШИФР КЛЮЧЕЙ (в файле ключи НЕ в открытом виде)
-- =========================================================
local _K = "HellHub@2026!Key"

local function _bxor(a, b)
    local r, p = 0, 1
    for _ = 1, 8 do
        local abit, bbit = a % 2, b % 2
        if abit ~= bbit then r = r + p end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        p = p * 2
    end
    return r
end

local function _xd(hex)
    if type(hex) ~= "string" or #hex < 2 or (#hex % 2) ~= 0 then return "" end
    local bytes = {}
    for i = 1, #hex, 2 do
        local b = tonumber(hex:sub(i, i + 1), 16)
        if not b then return "" end
        bytes[#bytes + 1] = b
    end
    local out = {}
    for i, b in ipairs(bytes) do
        local c = string.byte(_K, ((i - 1) % #_K) + 1)
        out[i] = string.char(_bxor(b, c))
    end
    return table.concat(out)
end

-- зашифрованные ключи (XOR+HEX). Открытым текстом их нет.
local KEY_ENC = {
    "06332729652C2976731D6570141D482A005D2B417C212973",
    "0D3D383965333B08741D637513004829095C2A41033E2E17",
    "0021293E653F510C711D7F71781C483C7B2B28410933510A",
    "0D573E58652D30786A1D7978707D48340D28274103263274",
    "7B5D3D5E653D3018731D0664130F483C00575E417C245119",
}

local KEY_DATABASE = {}
for _, enc in ipairs(KEY_ENC) do
    local plain = _xd(enc)
    if plain ~= "" then
        KEY_DATABASE[plain] = true
        KEY_DATABASE[plain:gsub("%-", "")] = true
    end
end

-- файл, где хранится привязка ключ -> HWID
local BIND_FILE = "HellHub_KeyBinds.json"
local SAVE_FILE = "HellHub_KeySave.json"

-- =========================================================
-- HWID
-- =========================================================
local function getHWID()
    local parts = {}

    pcall(function()
        if type(gethwid) == "function" then
            local h = gethwid()
            if h and tostring(h) ~= "" then
                table.insert(parts, "hw:" .. tostring(h))
            end
        end
    end)

    pcall(function()
        local ok, id = pcall(function()
            return game:GetService("RbxAnalyticsService"):GetClientId()
        end)
        if ok and id and tostring(id) ~= "" then
            table.insert(parts, "cid:" .. tostring(id))
        end
    end)

    pcall(function()
        if type(identifyexecutor) == "function" then
            local n = identifyexecutor()
            if n then table.insert(parts, "ex:" .. tostring(n)) end
        elseif type(getexecutorname) == "function" then
            local n = getexecutorname()
            if n then table.insert(parts, "ex:" .. tostring(n)) end
        end
    end)

    table.insert(parts, "uid:" .. tostring(player.UserId))

    if #parts == 0 then
        return "fallback-" .. tostring(player.UserId)
    end
    return table.concat(parts, "|")
end

local function normalizeKey(k)
    if type(k) ~= "string" then return "" end
    k = k:upper():gsub("%s+", "")
    return k
end

local function loadJson(path)
    if not (isfile and readfile) then return {} end
    local ok, data = pcall(function()
        if isfile(path) then
            return HttpService:JSONDecode(readfile(path))
        end
    end)
    if ok and type(data) == "table" then return data end
    return {}
end

local function saveJson(path, tbl)
    if not writefile then return false end
    local ok = pcall(function()
        writefile(path, HttpService:JSONEncode(tbl))
    end)
    return ok == true
end

local function isKeyValid(key)
    key = normalizeKey(key)
    if key == "" then return false end
    if KEY_DATABASE[key] == true then return true end
    local compact = key:gsub("%-", "")
    if KEY_DATABASE[compact] == true then return true end
    return false
end

local function checkKeyHWID(key)
    key = normalizeKey(key)
    local hwid = getHWID()
    local binds = loadJson(BIND_FILE)

    local bound = binds[key]
    if not bound then
        -- первая активация — привязываем к этому устройству
        binds[key] = hwid
        saveJson(BIND_FILE, binds)
        return true, "activated"
    end

    if bound == hwid then
        return true, "ok"
    end

    return false, "hwid_mismatch"
end

-- =========================================================
-- GUI (key prompt)
-- =========================================================
local function getGuiParent()
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    local ok = pcall(function()
        local t = Instance.new("Folder")
        t.Parent = CoreGui
        t:Destroy()
    end)
    if ok then return CoreGui end
    return player:WaitForChild("PlayerGui")
end

local function destroyOld()
    pcall(function()
        local p = getGuiParent()
        local old = p:FindFirstChild("HellHub_KeyUI")
        if old then old:Destroy() end
    end)
end

destroyOld()

local ACCENT = Color3.fromRGB(255, 45, 45)
local BG = Color3.fromRGB(14, 14, 16)
local CARD = Color3.fromRGB(22, 22, 26)
local TEXT = Color3.fromRGB(240, 240, 245)

local gui = Instance.new("ScreenGui")
gui.Name = "HellHub_KeyUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
gui.DisplayOrder = 999
gui.Parent = getGuiParent()

local overlay = Instance.new("Frame")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.35
overlay.BorderSizePixel = 0
overlay.Parent = gui

local box = Instance.new("Frame")
box.Size = UDim2.new(0, 340, 0, 210)
box.Position = UDim2.new(0.5, -170, 0.5, -105)
box.BackgroundColor3 = BG
box.BorderSizePixel = 0
box.Parent = overlay
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 14)

local stroke = Instance.new("UIStroke", box)
stroke.Thickness = 1.6
stroke.Color = ACCENT
stroke.Transparency = 0.15

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 34)
title.Position = UDim2.new(0, 10, 0, 12)
title.BackgroundTransparency = 1
title.Text = "HELL HUB  ·  KEY"
title.Font = Enum.Font.GothamBlack
title.TextSize = 18
title.TextColor3 = TEXT
title.Parent = box

local sub = Instance.new("TextLabel")
sub.Size = UDim2.new(1, -24, 0, 20)
sub.Position = UDim2.new(0, 12, 0, 44)
sub.BackgroundTransparency = 1
sub.Text = "1 key = 1 device"
sub.Font = Enum.Font.Gotham
sub.TextSize = 12
sub.TextColor3 = Color3.fromRGB(160, 160, 170)
sub.TextXAlignment = Enum.TextXAlignment.Left
sub.Parent = box

local input = Instance.new("TextBox")
input.Size = UDim2.new(1, -24, 0, 36)
input.Position = UDim2.new(0, 12, 0, 78)
input.BackgroundColor3 = CARD
input.BorderSizePixel = 0
input.PlaceholderText = "XXXX-XXXX-XXXX-XXXX-XXXX"
input.Text = ""
input.Font = Enum.Font.GothamBold
input.TextSize = 14
input.TextColor3 = TEXT
input.ClearTextOnFocus = false
input.Parent = box
Instance.new("UICorner", input).CornerRadius = UDim.new(0, 8)

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -24, 0, 18)
status.Position = UDim2.new(0, 12, 0, 120)
status.BackgroundTransparency = 1
status.Text = ""
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(255, 90, 90)
status.TextXAlignment = Enum.TextXAlignment.Left
status.Parent = box

local unlockBtn = Instance.new("TextButton")
unlockBtn.Size = UDim2.new(1, -24, 0, 36)
unlockBtn.Position = UDim2.new(0, 12, 0, 150)
unlockBtn.BackgroundColor3 = ACCENT
unlockBtn.BorderSizePixel = 0
unlockBtn.Text = "UNLOCK"
unlockBtn.Font = Enum.Font.GothamBlack
unlockBtn.TextSize = 14
unlockBtn.TextColor3 = Color3.fromRGB(20, 10, 10)
unlockBtn.Parent = box
Instance.new("UICorner", unlockBtn).CornerRadius = UDim.new(0, 8)

unlockBtn.MouseEnter:Connect(function()
    TweenService:Create(unlockBtn, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(255, 70, 70)}):Play()
end)
unlockBtn.MouseLeave:Connect(function()
    TweenService:Create(unlockBtn, TweenInfo.new(0.12), {BackgroundColor3 = ACCENT}):Play()
end)

-- =========================================================
-- LOAD MAIN SCRIPT (зашифрованный файл, сурс не в открытую)
-- Залей на GitHub файл HellHub.enc (только шифр)
-- =========================================================
local MAIN_URL = "https://raw.githubusercontent.com/CAEC-W36A-EAH7-7EPR-DTHT/Hell/main/HellHub.enc"

local function httpGet(url)
    local ok, res = pcall(function()
        return game:HttpGet(url)
    end)
    if ok and type(res) == "string" and #res > 50 then
        return res
    end
    ok, res = pcall(function()
        return game:HttpGetAsync(url)
    end)
    if ok and type(res) == "string" and #res > 50 then
        return res
    end
    return nil
end

local function decryptSource(hex)
    if type(hex) ~= "string" then return nil end
    hex = hex:gsub("%s+", "")
    if #hex < 20 or (#hex % 2) ~= 0 then return nil end
    local out = {}
    local ki = 0
    local klen = #_K
    for i = 1, #hex, 2 do
        local b = tonumber(hex:sub(i, i + 1), 16)
        if not b then return nil end
        ki = ki + 1
        local c = string.byte(_K, ((ki - 1) % klen) + 1)
        out[#out + 1] = string.char(_bxor(b, c))
    end
    return table.concat(out)
end

local function runMain()
    status.Text = "Loading..."
    status.TextColor3 = Color3.fromRGB(200, 200, 120)

    task.spawn(function()
        local enc = httpGet(MAIN_URL)
        if not enc then
            status.Text = "Failed to download script"
            status.TextColor3 = Color3.fromRGB(255, 90, 90)
            warn("[HELL] HttpGet failed:", MAIN_URL)
            return
        end

        local src = decryptSource(enc)
        if not src or #src < 50 then
            status.Text = "Decrypt failed"
            status.TextColor3 = Color3.fromRGB(255, 90, 90)
            warn("[HELL] decrypt failed")
            return
        end

        local fn, err = loadstring(src)
        if not fn then
            status.Text = "Load error"
            status.TextColor3 = Color3.fromRGB(255, 90, 90)
            warn("[HELL] loadstring failed:", err)
            return
        end

        pcall(function() gui:Destroy() end)
        local ok, e = xpcall(fn, function(e)
            return tostring(e) .. "\n" .. tostring(debug.traceback())
        end)
        if not ok then
            warn("[HELL] Runtime error:", e)
        end
    end)
end

local function tryUnlock(key)
    key = normalizeKey(key)
    if not isKeyValid(key) then
        status.Text = "Invalid key"
        status.TextColor3 = Color3.fromRGB(255, 90, 90)
        return
    end

    local ok, reason = checkKeyHWID(key)
    if not ok then
        if reason == "hwid_mismatch" then
            status.Text = "Key already used on another device"
        else
            status.Text = "Access denied"
        end
        status.TextColor3 = Color3.fromRGB(255, 90, 90)
        return
    end

    -- save last good key (auto login next time on same device)
    saveJson(SAVE_FILE, { key = key, hwid = getHWID() })

    status.Text = reason == "activated" and "Key activated on this device" or "Welcome back"
    status.TextColor3 = Color3.fromRGB(80, 255, 140)

    task.delay(0.35, runMain)
end

unlockBtn.MouseButton1Click:Connect(function()
    tryUnlock(input.Text)
end)

input.FocusLost:Connect(function(enter)
    if enter then tryUnlock(input.Text) end
end)

-- auto-login if same device + saved key
task.spawn(function()
    local saved = loadJson(SAVE_FILE)
    if type(saved) == "table" and saved.key and saved.hwid == getHWID() then
        if isKeyValid(saved.key) then
            local ok = checkKeyHWID(saved.key)
            if ok then
                status.Text = "Auto login..."
                status.TextColor3 = Color3.fromRGB(80, 255, 140)
                input.Text = saved.key
                task.wait(0.25)
                runMain()
                return
            end
        end
    end
end)

print("[HELL] Payload + Key System ready")
