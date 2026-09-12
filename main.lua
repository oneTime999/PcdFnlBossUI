--[[
    Pcd Fnl Boss Hub UI Library
    Original UI framework inspired by common Roblox UI-library ergonomics.

    Focus:
      - Window / Tab / Section / Controls architecture
      - Mobile + desktop input
      - Theme system
      - Notifications
      - Flags + config persistence
      - Executor API adapter (HTTP, clipboard, filesystem, executor info)

    This file intentionally does not include anti-cheat bypasses, stealth hooks,
    credential collection, or automatic data exfiltration.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local PcdHub = {
    Version = "0.3.0",
    Flags = {},
    Theme = "Midnight",
    _themeBindings = {},
    _flagHandlers = {},
    _connections = {},
    _screenGui = nil,
}

PcdHub.Themes = {
    Midnight = {
        Background = Color3.fromRGB(14, 16, 22),
        Surface = Color3.fromRGB(20, 23, 31),
        SurfaceAlt = Color3.fromRGB(26, 30, 40),
        Sidebar = Color3.fromRGB(17, 19, 26),
        Accent = Color3.fromRGB(121, 83, 255),
        AccentSoft = Color3.fromRGB(82, 61, 159),
        Text = Color3.fromRGB(242, 244, 250),
        MutedText = Color3.fromRGB(151, 158, 177),
        Border = Color3.fromRGB(46, 51, 65),
        Danger = Color3.fromRGB(235, 80, 90),
        Success = Color3.fromRGB(70, 204, 137),
    },
    Ocean = {
        Background = Color3.fromRGB(8, 18, 31),
        Surface = Color3.fromRGB(12, 27, 45),
        SurfaceAlt = Color3.fromRGB(16, 36, 58),
        Sidebar = Color3.fromRGB(9, 22, 37),
        Accent = Color3.fromRGB(30, 144, 255),
        AccentSoft = Color3.fromRGB(24, 93, 154),
        Text = Color3.fromRGB(236, 247, 255),
        MutedText = Color3.fromRGB(142, 174, 199),
        Border = Color3.fromRGB(34, 70, 96),
        Danger = Color3.fromRGB(255, 95, 103),
        Success = Color3.fromRGB(55, 210, 159),
    },
    Crimson = {
        Background = Color3.fromRGB(22, 12, 15),
        Surface = Color3.fromRGB(31, 17, 21),
        SurfaceAlt = Color3.fromRGB(43, 23, 29),
        Sidebar = Color3.fromRGB(25, 13, 17),
        Accent = Color3.fromRGB(235, 66, 91),
        AccentSoft = Color3.fromRGB(137, 44, 59),
        Text = Color3.fromRGB(255, 241, 244),
        MutedText = Color3.fromRGB(190, 150, 159),
        Border = Color3.fromRGB(76, 42, 50),
        Danger = Color3.fromRGB(255, 79, 79),
        Success = Color3.fromRGB(69, 210, 139),
    },
    Light = {
        Background = Color3.fromRGB(235, 239, 246),
        Surface = Color3.fromRGB(250, 251, 253),
        SurfaceAlt = Color3.fromRGB(240, 243, 248),
        Sidebar = Color3.fromRGB(244, 247, 251),
        Accent = Color3.fromRGB(100, 70, 230),
        AccentSoft = Color3.fromRGB(187, 177, 235),
        Text = Color3.fromRGB(31, 35, 45),
        MutedText = Color3.fromRGB(105, 112, 130),
        Border = Color3.fromRGB(212, 217, 227),
        Danger = Color3.fromRGB(219, 68, 78),
        Success = Color3.fromRGB(35, 159, 101),
    },
}

local function theme()
    return PcdHub.Themes[PcdHub.Theme] or PcdHub.Themes.Midnight
end

local function safeCall(callback, ...)
    if typeof(callback) ~= "function" then
        return true
    end

    local ok, result = pcall(callback, ...)
    if not ok then
        warn("[PcdHub] Callback error:", result)
    end
    return ok, result
end

local function new(className, properties)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    return object
end

local function corner(parent, radius)
    return new("UICorner", {
        CornerRadius = UDim.new(0, radius or 10),
        Parent = parent,
    })
end

local function stroke(parent, colorKey, transparency, thickness)
    local item = new("UIStroke", {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = theme()[colorKey or "Border"],
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        Parent = parent,
    })
    PcdHub:_BindTheme(item, "Color", colorKey or "Border")
    return item
end

local function padding(parent, l, r, t, b)
    return new("UIPadding", {
        PaddingLeft = UDim.new(0, l or 0),
        PaddingRight = UDim.new(0, r or 0),
        PaddingTop = UDim.new(0, t or 0),
        PaddingBottom = UDim.new(0, b or 0),
        Parent = parent,
    })
end

local function tween(object, time, properties, style, direction)
    local info = TweenInfo.new(
        time or 0.18,
        style or Enum.EasingStyle.Quint,
        direction or Enum.EasingDirection.Out
    )
    local t = TweenService:Create(object, info, properties)
    t:Play()
    return t
end

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(PcdHub._connections, connection)
    return connection
end

local function getRootParent()
    local ok, hui = pcall(function()
        if typeof(gethui) == "function" then
            return gethui()
        end
    end)
    if ok and hui then
        return hui
    end

    local okCore = pcall(function()
        return CoreGui.Name
    end)
    if okCore then
        return CoreGui
    end

    return LocalPlayer:WaitForChild("PlayerGui")
end

local function makeDraggable(handle, target, clampToViewport)
    local dragging = false
    local dragStart
    local startPosition
    local dragInput

    local function clampPosition(position)
        if clampToViewport == false then
            return position
        end

        local camera = workspace.CurrentCamera
        if not camera then
            return position
        end

        local viewport = camera.ViewportSize
        local targetSize = target.AbsoluteSize
        local anchor = target.AnchorPoint

        local x = position.X.Offset + viewport.X * position.X.Scale
        local y = position.Y.Offset + viewport.Y * position.Y.Scale

        local minX = targetSize.X * anchor.X + 6
        local maxX = viewport.X - targetSize.X * (1 - anchor.X) - 6
        local minY = targetSize.Y * anchor.Y + 6
        local maxY = viewport.Y - targetSize.Y * (1 - anchor.Y) - 6

        if maxX < minX then
            minX, maxX = viewport.X * 0.5, viewport.X * 0.5
        end
        if maxY < minY then
            minY, maxY = viewport.Y * 0.5, viewport.Y * 0.5
        end

        x = math.clamp(x, minX, maxX)
        y = math.clamp(y, minY, maxY)
        return UDim2.fromOffset(x, y)
    end

    connect(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = target.AbsolutePosition
            dragInput = input
        end
    end)

    connect(UserInputService.InputChanged, function(input)
        if not dragging then
            return
        end

        local valid = input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch
        if not valid then
            return
        end

        local delta = input.Position - dragStart
        local targetAbsolute = startPosition + Vector2.new(delta.X, delta.Y)
        local anchorOffset = Vector2.new(
            target.AbsoluteSize.X * target.AnchorPoint.X,
            target.AbsoluteSize.Y * target.AnchorPoint.Y
        )
        local desired = targetAbsolute + anchorOffset
        target.Position = clampPosition(UDim2.fromOffset(desired.X, desired.Y))
    end)

    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            dragInput = nil
        end
    end)
end

function PcdHub:_BindTheme(instance, property, colorKey)
    table.insert(self._themeBindings, {
        Instance = instance,
        Property = property,
        Key = colorKey,
    })
end

function PcdHub:SetTheme(themeName)
    if not self.Themes[themeName] then
        warn("[PcdHub] Unknown theme:", themeName)
        return false
    end

    self.Theme = themeName
    local current = theme()

    for _, binding in ipairs(self._themeBindings) do
        local object = binding.Instance
        if object and object.Parent and current[binding.Key] ~= nil then
            pcall(function()
                tween(object, 0.22, {
                    [binding.Property] = current[binding.Key],
                })
            end)
        end
    end

    return true
end

function PcdHub:RegisterTheme(name, data)
    assert(type(name) == "string", "Theme name must be a string")
    assert(type(data) == "table", "Theme data must be a table")

    local base = self.Themes.Midnight
    local merged = {}
    for key, value in pairs(base) do
        merged[key] = value
    end
    for key, value in pairs(data) do
        merged[key] = value
    end

    self.Themes[name] = merged
    return merged
end

-- Executor/API Adapter ---------------------------------------------------------
PcdHub.API = {}

function PcdHub.API.GetExecutor()
    local candidates = {
        function()
            if typeof(identifyexecutor) == "function" then
                return identifyexecutor()
            end
        end,
        function()
            if typeof(getexecutorname) == "function" then
                return getexecutorname()
            end
        end,
    }

    for _, resolver in ipairs(candidates) do
        local ok, a, b = pcall(resolver)
        if ok and a then
            return tostring(a), b and tostring(b) or nil
        end
    end

    return "Unknown", nil
end

function PcdHub.API.Capabilities()
    return {
        HttpRequest = typeof(request) == "function"
            or typeof(http_request) == "function"
            or (syn and typeof(syn.request) == "function")
            or false,
        Clipboard = typeof(setclipboard) == "function"
            or typeof(toclipboard) == "function",
        Filesystem = typeof(writefile) == "function"
            and typeof(readfile) == "function"
            and typeof(isfile) == "function",
        Folders = typeof(makefolder) == "function"
            and typeof(isfolder) == "function",
        GetHui = typeof(gethui) == "function",
    }
end

function PcdHub.API.Copy(text)
    text = tostring(text or "")

    local fn = nil
    if typeof(setclipboard) == "function" then
        fn = setclipboard
    elseif typeof(toclipboard) == "function" then
        fn = toclipboard
    end

    if not fn then
        return false, "Clipboard API unavailable"
    end

    local ok, err = pcall(fn, text)
    return ok, err
end

function PcdHub.API.Request(options)
    assert(type(options) == "table", "Request options must be a table")

    local requestFn = nil
    if typeof(request) == "function" then
        requestFn = request
    elseif typeof(http_request) == "function" then
        requestFn = http_request
    elseif syn and typeof(syn.request) == "function" then
        requestFn = syn.request
    end

    local method = string.upper(options.Method or options.method or "GET")
    local url = options.Url or options.URL or options.url
    assert(type(url) == "string", "Request URL is required")

    if requestFn then
        local ok, response = pcall(requestFn, {
            Url = url,
            Method = method,
            Headers = options.Headers or {},
            Body = options.Body,
        })

        if not ok then
            return nil, response
        end

        return response
    end

    if method == "GET" then
        local ok, body = pcall(function()
            return game:HttpGet(url)
        end)
        if ok then
            return {
                Success = true,
                StatusCode = 200,
                Body = body,
                Headers = {},
            }
        end
        return nil, body
    end

    return nil, "HTTP request API unavailable for non-GET requests"
end

-- Config ----------------------------------------------------------------------
local function normalizeConfigPath(folder, fileName)
    folder = folder or "PcdFnlBossHub"
    fileName = fileName or "config.json"
    if not string.match(fileName, "%.json$") then
        fileName = fileName .. ".json"
    end
    return folder, folder .. "/" .. fileName
end

function PcdHub:SaveConfig(folder, fileName)
    local caps = self.API.Capabilities()
    if not caps.Filesystem then
        return false, "Filesystem API unavailable"
    end

    local folderName, path = normalizeConfigPath(folder, fileName)

    if typeof(isfolder) == "function" and typeof(makefolder) == "function" then
        if not isfolder(folderName) then
            pcall(makefolder, folderName)
        end
    end

    local okEncode, encoded = pcall(HttpService.JSONEncode, HttpService, self.Flags)
    if not okEncode then
        return false, encoded
    end

    local okWrite, err = pcall(writefile, path, encoded)
    return okWrite, err or path
end

function PcdHub:LoadConfig(folder, fileName)
    local caps = self.API.Capabilities()
    if not caps.Filesystem then
        return false, "Filesystem API unavailable"
    end

    local _, path = normalizeConfigPath(folder, fileName)
    if not isfile(path) then
        return false, "Config file not found"
    end

    local okRead, raw = pcall(readfile, path)
    if not okRead then
        return false, raw
    end

    local okDecode, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
    if not okDecode or type(decoded) ~= "table" then
        return false, decoded
    end

    for flag, value in pairs(decoded) do
        self.Flags[flag] = value
        local setter = self._flagHandlers[flag]
        if setter then
            safeCall(setter, value, true)
        end
    end

    return true, decoded
end

function PcdHub:GetFlag(flag)
    return self.Flags[flag]
end

function PcdHub:SetFlag(flag, value)
    self.Flags[flag] = value
    local setter = self._flagHandlers[flag]
    if setter then
        safeCall(setter, value, false)
    end
end

function PcdHub:Destroy()
    for _, connection in ipairs(self._connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(self._connections)
    table.clear(self._themeBindings)
    table.clear(self._flagHandlers)

    if self._screenGui then
        pcall(function()
            self._screenGui:Destroy()
        end)
        self._screenGui = nil
    end
    self._notificationHolder = nil
end

-- Notifications ---------------------------------------------------------------
function PcdHub:Notify(options)
    options = options or {}
    if not self._screenGui then
        return nil
    end

    local titleText = tostring(options.Title or options.Name or "Pcd Fnl Boss Hub")
    local contentText = tostring(options.Content or options.Description or "Notification")
    local duration = math.max(1, tonumber(options.Duration) or 4)
    local actions = options.Actions or {}

    local camera = workspace.CurrentCamera
    local viewportX = camera and camera.ViewportSize.X or 1280
    local width = math.clamp(viewportX - 28, 240, 330)

    local holder = self._notificationHolder
    if not holder or not holder.Parent then
        holder = new("Frame", {
            Name = "Notifications",
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -10, 1, -10),
            Size = UDim2.new(0, width, 1, -20),
            BackgroundTransparency = 1,
            Parent = self._screenGui,
        })
        new("UIListLayout", {
            Padding = UDim.new(0, 8),
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = holder,
        })
        self._notificationHolder = holder
    else
        holder.Size = UDim2.new(0, width, 1, -20)
    end

    local hasActions = #actions > 0
    local cardHeight = hasActions and 112 or 78
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, cardHeight),
        BackgroundColor3 = theme().Surface,
        BorderSizePixel = 0,
        Parent = holder,
    })
    corner(card, 13)
    stroke(card, "Border", 0.15, 1)
    self:_BindTheme(card, "BackgroundColor3", "Surface")

    local accent = new("Frame", {
        Position = UDim2.new(0, 0, 0, 12),
        Size = UDim2.new(0, 3, 1, -24),
        BackgroundColor3 = theme().Accent,
        BorderSizePixel = 0,
        Parent = card,
    })
    corner(accent, 4)
    self:_BindTheme(accent, "BackgroundColor3", "Accent")

    local titleLabel = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 14, 0, 10),
        Size = UDim2.new(1, -42, 0, 20),
        Font = Enum.Font.GothamSemibold,
        Text = titleText,
        TextColor3 = theme().Text,
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })
    self:_BindTheme(titleLabel, "TextColor3", "Text")

    local closeButton = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 7),
        Size = UDim2.new(0, 24, 0, 24),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = "×",
        TextColor3 = theme().MutedText,
        TextSize = 16,
        AutoButtonColor = false,
        Parent = card,
    })
    self:_BindTheme(closeButton, "TextColor3", "MutedText")

    local bodyLabel = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 14, 0, 31),
        Size = UDim2.new(1, -28, 0, hasActions and 38 or 36),
        Font = Enum.Font.Gotham,
        Text = contentText,
        TextWrapped = true,
        TextColor3 = theme().MutedText,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = card,
    })
    self:_BindTheme(bodyLabel, "TextColor3", "MutedText")

    local dismissed = false
    local function dismiss()
        if dismissed or not card.Parent then
            return
        end
        dismissed = true
        tween(card, 0.18, {
            Position = UDim2.new(0, 24, 0, 0),
            BackgroundTransparency = 1,
        })
        task.delay(0.2, function()
            if card and card.Parent then
                card:Destroy()
            end
        end)
    end

    connect(closeButton.Activated, dismiss)

    if hasActions then
        local actionHolder = new("Frame", {
            Position = UDim2.new(0, 12, 1, -36),
            Size = UDim2.new(1, -24, 0, 28),
            BackgroundTransparency = 1,
            Parent = card,
        })
        local layout = new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            Padding = UDim.new(0, 6),
            Parent = actionHolder,
        })
        for i, actionData in ipairs(actions) do
            if i > 2 then break end
            local actionButton = new("TextButton", {
                Size = UDim2.new(0, 86, 1, 0),
                BackgroundColor3 = i == 1 and theme().Accent or theme().SurfaceAlt,
                BorderSizePixel = 0,
                Font = Enum.Font.GothamSemibold,
                Text = tostring(actionData.Name or actionData.Title or ("Action " .. i)),
                TextColor3 = theme().Text,
                TextSize = 10,
                AutoButtonColor = false,
                Parent = actionHolder,
            })
            corner(actionButton, 8)
            if i == 1 then
                self:_BindTheme(actionButton, "BackgroundColor3", "Accent")
            else
                self:_BindTheme(actionButton, "BackgroundColor3", "SurfaceAlt")
            end
            self:_BindTheme(actionButton, "TextColor3", "Text")
            connect(actionButton.Activated, function()
                safeCall(actionData.Callback)
                if actionData.Close ~= false then
                    dismiss()
                end
            end)
        end
    end

    card.Position = UDim2.new(0, 22, 0, 0)
    card.BackgroundTransparency = 1
    tween(card, 0.2, {Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 0})

    task.delay(duration, dismiss)

    return {
        Close = dismiss,
        Frame = card,
    }
end

-- UI Components ---------------------------------------------------------------
local function createElementShell(parent, height)
    local frame = new("Frame", {
        Size = UDim2.new(1, 0, 0, height or 48),
        BackgroundColor3 = theme().SurfaceAlt,
        BorderSizePixel = 0,
        Parent = parent,
    })
    corner(frame, 10)
    stroke(frame, "Border", 0.2, 1)
    PcdHub:_BindTheme(frame, "BackgroundColor3", "SurfaceAlt")
    frame:SetAttribute("PcdElement", true)
    return frame
end

local function createLabel(parent, text, size, bold)
    local label = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Font = bold and Enum.Font.GothamSemibold or Enum.Font.Gotham,
        Text = text or "Label",
        TextColor3 = theme().Text,
        TextSize = size or 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = parent,
    })
    PcdHub:_BindTheme(label, "TextColor3", "Text")
    return label
end

local function addDescription(frame, name, description)
    local title = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 14, 0, description and 7 or 0),
        Size = UDim2.new(1, -28, description and 0 or 1, description and 20 or 0),
        Font = Enum.Font.GothamSemibold,
        Text = name or "Element",
        TextColor3 = theme().Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })
    PcdHub:_BindTheme(title, "TextColor3", "Text")

    frame:SetAttribute("PcdSearchText", string.lower(tostring(name or "") .. " " .. tostring(description or "")))

    local subtitle
    if description then
        subtitle = new("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 14, 0, 27),
            Size = UDim2.new(1, -28, 0, 16),
            Font = Enum.Font.Gotham,
            Text = description,
            TextColor3 = theme().MutedText,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = frame,
        })
        PcdHub:_BindTheme(subtitle, "TextColor3", "MutedText")
    end

    return title, subtitle
end

local function resolveFlag(options)
    return options.Flag or options.flag or options.Name or options.name
end

local function registerFlag(flag, defaultValue, setter)
    if flag then
        if PcdHub.Flags[flag] == nil then
            PcdHub.Flags[flag] = defaultValue
        end
        PcdHub._flagHandlers[flag] = setter
    end
end

local SectionMethods = {}
SectionMethods.__index = SectionMethods

function SectionMethods:CreateButton(options)
    options = options or {}
    local frame = createElementShell(self.Container, options.Description and 56 or 46)
    local title = addDescription(frame, options.Name or "Button", options.Description)
    title.Size = UDim2.new(1, -60, title.Size.Y.Scale, title.Size.Y.Offset)

    local action = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0, 34, 0, 28),
        BackgroundColor3 = theme().Accent,
        Text = "›",
        Font = Enum.Font.GothamBold,
        TextSize = 20,
        TextColor3 = Color3.new(1, 1, 1),
        AutoButtonColor = false,
        Parent = frame,
    })
    corner(action, 8)
    PcdHub:_BindTheme(action, "BackgroundColor3", "Accent")

    connect(action.Activated, function()
        tween(action, 0.08, {Size = UDim2.new(0, 31, 0, 25)})
        task.delay(0.08, function()
            if action.Parent then
                tween(action, 0.12, {Size = UDim2.new(0, 34, 0, 28)})
            end
        end)
        safeCall(options.Callback)
    end)

    local handle = {}
    function handle:Set(text)
        title.Text = tostring(text)
    end
    return handle
end

function SectionMethods:CreateToggle(options)
    options = options or {}
    local flag = resolveFlag(options)
    local current = options.CurrentValue
    if current == nil then current = options.Default end
    if current == nil then current = false end

    local frame = createElementShell(self.Container, options.Description and 56 or 46)
    local title = addDescription(frame, options.Name or "Toggle", options.Description)
    title.Size = UDim2.new(1, -72, title.Size.Y.Scale, title.Size.Y.Offset)

    local switch = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.new(0, 42, 0, 24),
        BackgroundColor3 = current and theme().Accent or theme().Border,
        Text = "",
        AutoButtonColor = false,
        Parent = frame,
    })
    corner(switch, 20)

    local knob = new("Frame", {
        Position = current and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
        Size = UDim2.new(0, 18, 0, 18),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
        Parent = switch,
    })
    corner(knob, 20)

    local function render(value)
        tween(switch, 0.16, {
            BackgroundColor3 = value and theme().Accent or theme().Border,
        })
        tween(knob, 0.16, {
            Position = value and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
        })
    end

    local function set(value, fromConfig)
        current = value == true
        if flag then
            PcdHub.Flags[flag] = current
        end
        render(current)
        if not fromConfig or options.FireOnLoad == true then
            safeCall(options.Callback, current)
        end
    end

    registerFlag(flag, current, set)
    render(current)

    connect(switch.Activated, function()
        set(not current, false)
    end)

    local handle = {}
    function handle:Set(value)
        set(value, false)
    end
    function handle:Get()
        return current
    end
    return handle
end

function SectionMethods:CreateSlider(options)
    options = options or {}
    local range = options.Range or {0, 100}
    local minimum = tonumber(options.Min or range[1]) or 0
    local maximum = tonumber(options.Max or range[2]) or 100
    local increment = tonumber(options.Increment) or 1
    local suffix = options.Suffix or ""
    local current = tonumber(options.CurrentValue or options.Default) or minimum
    current = math.clamp(current, minimum, maximum)
    local flag = resolveFlag(options)

    local frame = createElementShell(self.Container, 68)
    local title = addDescription(frame, options.Name or "Slider", options.Description)
    title.Size = UDim2.new(1, -80, 0, 22)

    local valueLabel = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 8),
        Size = UDim2.new(0, 72, 0, 18),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamSemibold,
        Text = tostring(current) .. suffix,
        TextColor3 = theme().Accent,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = frame,
    })
    PcdHub:_BindTheme(valueLabel, "TextColor3", "Accent")

    local bar = new("Frame", {
        Position = UDim2.new(0, 14, 1, -20),
        Size = UDim2.new(1, -28, 0, 6),
        BackgroundColor3 = theme().Border,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(bar, 10)
    PcdHub:_BindTheme(bar, "BackgroundColor3", "Border")

    local fill = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = theme().Accent,
        BorderSizePixel = 0,
        Parent = bar,
    })
    corner(fill, 10)
    PcdHub:_BindTheme(fill, "BackgroundColor3", "Accent")

    local hitbox = new("TextButton", {
        Position = UDim2.new(0, 0, 0.5, -10),
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = "",
        Parent = bar,
    })

    local dragging = false

    local function quantize(value)
        local rounded = math.floor((value / increment) + 0.5) * increment
        local decimals = tostring(increment):match("%.(%d+)")
        if decimals then
            local places = #decimals
            local mult = 10 ^ places
            rounded = math.floor(rounded * mult + 0.5) / mult
        end
        return math.clamp(rounded, minimum, maximum)
    end

    local function set(value, fromConfig)
        value = quantize(tonumber(value) or minimum)
        current = value
        if flag then
            PcdHub.Flags[flag] = current
        end

        local alpha = (current - minimum) / math.max(maximum - minimum, 0.0001)
        tween(fill, 0.08, {Size = UDim2.new(alpha, 0, 1, 0)})
        valueLabel.Text = tostring(current) .. suffix

        if not fromConfig or options.FireOnLoad == true then
            safeCall(options.Callback, current)
        end
    end

    local function setFromInput(input)
        local relative = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        set(minimum + (maximum - minimum) * relative, false)
    end

    connect(hitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromInput(input)
        end
    end)

    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            setFromInput(input)
        end
    end)

    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    registerFlag(flag, current, set)
    set(current, true)

    local handle = {}
    function handle:Set(value)
        set(value, false)
    end
    function handle:Get()
        return current
    end
    return handle
end

function SectionMethods:CreateInput(options)
    options = options or {}
    local current = tostring(options.CurrentValue or options.Default or "")
    local flag = resolveFlag(options)

    local frame = createElementShell(self.Container, options.Description and 72 or 62)
    local title = addDescription(frame, options.Name or "Input", options.Description)
    title.Size = UDim2.new(1, -28, 0, 20)

    local input = new("TextBox", {
        Position = UDim2.new(0, 14, 1, -32),
        Size = UDim2.new(1, -28, 0, 24),
        BackgroundColor3 = theme().Background,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        PlaceholderText = options.PlaceholderText or options.Placeholder or "Type here...",
        PlaceholderColor3 = theme().MutedText,
        Text = current,
        TextColor3 = theme().Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })
    corner(input, 7)
    padding(input, 8, 8, 0, 0)
    PcdHub:_BindTheme(input, "BackgroundColor3", "Background")
    PcdHub:_BindTheme(input, "TextColor3", "Text")
    PcdHub:_BindTheme(input, "PlaceholderColor3", "MutedText")

    local function set(value, fromConfig)
        current = tostring(value or "")
        input.Text = current
        if flag then
            PcdHub.Flags[flag] = current
        end
        if not fromConfig or options.FireOnLoad == true then
            safeCall(options.Callback, current)
        end
    end

    registerFlag(flag, current, set)

    connect(input.FocusLost, function(enterPressed)
        set(input.Text, false)
        if options.RemoveTextAfterFocusLost then
            input.Text = ""
        end
        if options.OnEnter and enterPressed then
            safeCall(options.OnEnter, current)
        end
    end)

    local handle = {}
    function handle:Set(value)
        set(value, false)
    end
    function handle:Get()
        return current
    end
    return handle
end

function SectionMethods:CreateColorPicker(options)
    options = options or {}
    local flag = resolveFlag(options)
    local current = options.Color or options.CurrentColor or options.Default or Color3.fromRGB(121, 83, 255)
    if typeof(current) ~= "Color3" then
        current = Color3.fromRGB(121, 83, 255)
    end

    local frame = createElementShell(self.Container, 48)
    local title = addDescription(frame, options.Name or "Color Picker", options.Description)
    title.Size = UDim2.new(1, -76, title.Size.Y.Scale, title.Size.Y.Offset)

    local preview = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0, 46, 0, 26),
        BackgroundColor3 = current,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = frame,
    })
    corner(preview, 8)
    stroke(preview, "Border", 0.15, 1)

    local panel = new("Frame", {
        Position = UDim2.new(0, 0, 1, 7),
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = theme().Surface,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Visible = false,
        ZIndex = 30,
        Parent = frame,
    })
    corner(panel, 10)
    stroke(panel, "Border", 0.1, 1)
    PcdHub:_BindTheme(panel, "BackgroundColor3", "Surface")

    local sv = new("ImageButton", {
        Position = UDim2.new(0, 10, 0, 10),
        Size = UDim2.new(1, -48, 0, 105),
        BackgroundColor3 = Color3.fromHSV(0, 1, 1),
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Image = "rbxassetid://4155801252",
        ZIndex = 31,
        Parent = panel,
    })
    corner(sv, 8)

    local hue = new("ImageButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 10),
        Size = UDim2.new(0, 24, 0, 105),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Image = "rbxassetid://3641079629",
        ZIndex = 31,
        Parent = panel,
    })
    corner(hue, 8)

    local valueText = new("TextLabel", {
        Position = UDim2.new(0, 10, 1, -30),
        Size = UDim2.new(1, -20, 0, 20),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextColor3 = theme().MutedText,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 31,
        Parent = panel,
    })
    PcdHub:_BindTheme(valueText, "TextColor3", "MutedText")

    local h, s, v = current:ToHSV()
    local open = false
    local svDragging = false
    local hueDragging = false
    local setOpen

    local function serialize(color)
        return {
            R = math.floor(color.R * 255 + 0.5),
            G = math.floor(color.G * 255 + 0.5),
            B = math.floor(color.B * 255 + 0.5),
        }
    end

    local function deserialize(value)
        if typeof(value) == "Color3" then
            return value
        end
        if type(value) == "table" then
            local r = tonumber(value.R or value[1])
            local g = tonumber(value.G or value[2])
            local b = tonumber(value.B or value[3])
            if r and g and b then
                return Color3.fromRGB(math.clamp(r, 0, 255), math.clamp(g, 0, 255), math.clamp(b, 0, 255))
            end
        end
        return current
    end

    local function render()
        current = Color3.fromHSV(h, s, v)
        preview.BackgroundColor3 = current
        sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        local rgb = serialize(current)
        valueText.Text = string.format("RGB  %d, %d, %d", rgb.R, rgb.G, rgb.B)
    end

    local function set(value, fromConfig)
        current = deserialize(value)
        h, s, v = current:ToHSV()
        render()
        if flag then
            PcdHub.Flags[flag] = serialize(current)
        end
        if not fromConfig or options.FireOnLoad == true then
            safeCall(options.Callback, current)
        end
    end

    local function updateSV(input)
        local x = math.clamp((input.Position.X - sv.AbsolutePosition.X) / math.max(sv.AbsoluteSize.X, 1), 0, 1)
        local y = math.clamp((input.Position.Y - sv.AbsolutePosition.Y) / math.max(sv.AbsoluteSize.Y, 1), 0, 1)
        s = x
        v = 1 - y
        set(Color3.fromHSV(h, s, v), false)
    end

    local function updateHue(input)
        local y = math.clamp((input.Position.Y - hue.AbsolutePosition.Y) / math.max(hue.AbsoluteSize.Y, 1), 0, 1)
        h = y
        set(Color3.fromHSV(h, s, v), false)
    end

    setOpen = function(state)
        open = state == true
        panel.Visible = true
        frame.ZIndex = open and 25 or 1
        tween(panel, 0.16, {Size = UDim2.new(1, 0, 0, open and 148 or 0)})
        tween(frame, 0.16, {Size = UDim2.new(1, 0, 0, open and 203 or 48)})
        if not open then
            task.delay(0.17, function()
                if panel.Parent and not open then
                    panel.Visible = false
                end
            end)
        end
    end

    connect(preview.Activated, function()
        setOpen(not open)
    end)

    connect(sv.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            svDragging = true
            updateSV(input)
        end
    end)
    connect(hue.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            hueDragging = true
            updateHue(input)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            if svDragging then updateSV(input) end
            if hueDragging then updateHue(input) end
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            svDragging = false
            hueDragging = false
        end
    end)

    registerFlag(flag, serialize(current), set)
    render()

    local handle = {}
    function handle:Set(value)
        set(value, false)
    end
    function handle:Get()
        return current
    end
    function handle:SetOpen(state)
        if state == nil then state = not open end
        if state ~= open then
            setOpen(state)
        end
    end
    return handle
end

function SectionMethods:CreateDropdown(options)
    options = options or {}
    local items = options.Options or options.Values or {}
    local multi = options.MultipleOptions == true or options.Multi == true
    local initial = options.CurrentOption or options.Default
    local flag = resolveFlag(options)
    local selected = multi and {} or nil

    if multi then
        if type(initial) == "table" then
            for _, v in ipairs(initial) do
                selected[tostring(v)] = true
            end
        end
    else
        if type(initial) == "table" then
            selected = initial[1]
        else
            selected = initial
        end
    end

    local frame = createElementShell(self.Container, 48)
    local title = addDescription(frame, options.Name or "Dropdown", nil)
    title.Size = UDim2.new(0.45, 0, 1, 0)

    local dropdownButton = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0.52, 0, 0, 30),
        BackgroundColor3 = theme().Background,
        BorderSizePixel = 0,
        Font = Enum.Font.Gotham,
        Text = "Select",
        TextColor3 = theme().MutedText,
        TextSize = 11,
        AutoButtonColor = false,
        Parent = frame,
    })
    corner(dropdownButton, 8)
    padding(dropdownButton, 8, 8, 0, 0)
    PcdHub:_BindTheme(dropdownButton, "BackgroundColor3", "Background")
    PcdHub:_BindTheme(dropdownButton, "TextColor3", "MutedText")

    local list = new("Frame", {
        Position = UDim2.new(0, 0, 1, 8),
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = theme().Surface,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Visible = false,
        ZIndex = 20,
        Parent = frame,
    })
    corner(list, 9)
    stroke(list, "Border", 0, 1)
    PcdHub:_BindTheme(list, "BackgroundColor3", "Surface")

    local listLayout = new("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = list,
    })
    padding(list, 6, 6, 6, 6)

    local open = false
    local optionButtons = {}
    local setOpen

    local function currentText()
        if multi then
            local values = {}
            for _, item in ipairs(items) do
                if selected[tostring(item)] then
                    table.insert(values, tostring(item))
                end
            end
            if #values == 0 then return "Select" end
            return table.concat(values, ", ")
        end
        return selected ~= nil and tostring(selected) or "Select"
    end

    local function serializeSelection()
        if multi then
            local values = {}
            for _, item in ipairs(items) do
                if selected[tostring(item)] then
                    table.insert(values, item)
                end
            end
            return values
        end
        return selected
    end

    local function refreshVisual()
        dropdownButton.Text = currentText()
        for value, button in pairs(optionButtons) do
            local active = multi and selected[value] or tostring(selected) == value
            button.BackgroundColor3 = active and theme().AccentSoft or theme().Background
            button.TextColor3 = active and theme().Text or theme().MutedText
        end
    end

    local function set(value, fromConfig)
        if multi then
            selected = {}
            if type(value) == "table" then
                for _, v in ipairs(value) do
                    selected[tostring(v)] = true
                end
            elseif value ~= nil then
                selected[tostring(value)] = true
            end
        else
            if type(value) == "table" then
                selected = value[1]
            else
                selected = value
            end
        end

        local serialized = serializeSelection()
        if flag then
            PcdHub.Flags[flag] = serialized
        end
        refreshVisual()
        if not fromConfig or options.FireOnLoad == true then
            safeCall(options.Callback, serialized)
        end
    end

    local function rebuild()
        for _, child in ipairs(list:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end
        table.clear(optionButtons)

        for _, item in ipairs(items) do
            local value = tostring(item)
            local button = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 30),
                BackgroundColor3 = theme().Background,
                BorderSizePixel = 0,
                Font = Enum.Font.Gotham,
                Text = value,
                TextColor3 = theme().MutedText,
                TextSize = 11,
                AutoButtonColor = false,
                ZIndex = 21,
                Parent = list,
            })
            corner(button, 7)
            optionButtons[value] = button

            connect(button.Activated, function()
                if multi then
                    selected[value] = not selected[value] or nil
                else
                    selected = item
                    setOpen(false)
                end

                local serialized = serializeSelection()
                if flag then
                    PcdHub.Flags[flag] = serialized
                end
                refreshVisual()
                safeCall(options.Callback, serialized)
            end)
        end

        refreshVisual()
    end

    setOpen = function(state)
        open = state == true
        list.Visible = true
        local wanted = math.min(#items * 34 + 12, 180)
        tween(list, 0.16, {Size = UDim2.new(1, 0, 0, open and wanted or 0)})
        tween(frame, 0.16, {Size = UDim2.new(1, 0, 0, open and (56 + wanted) or 48)})
        if not open then
            task.delay(0.17, function()
                if not open and list.Parent then
                    list.Visible = false
                end
            end)
        end
    end

    connect(dropdownButton.Activated, function()
        setOpen(not open)
    end)

    registerFlag(flag, serializeSelection(), set)
    rebuild()

    local handle = {}
    function handle:Set(value)
        set(value, false)
    end
    function handle:Get()
        return serializeSelection()
    end
    function handle:Refresh(newOptions, keepSelection)
        items = newOptions or {}
        if not keepSelection then
            selected = multi and {} or nil
        end
        rebuild()
    end
    return handle
end

function SectionMethods:CreateKeybind(options)
    options = options or {}
    local current = options.CurrentKeybind or options.Default or Enum.KeyCode.RightShift
    if type(current) == "string" then
        current = Enum.KeyCode[current] or Enum.KeyCode.RightShift
    end
    local flag = resolveFlag(options)

    local frame = createElementShell(self.Container, 46)
    local title = addDescription(frame, options.Name or "Keybind", nil)
    title.Size = UDim2.new(1, -110, 1, 0)

    local button = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0, 92, 0, 28),
        BackgroundColor3 = theme().Background,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamSemibold,
        Text = current.Name,
        TextColor3 = theme().MutedText,
        TextSize = 11,
        AutoButtonColor = false,
        Parent = frame,
    })
    corner(button, 8)
    PcdHub:_BindTheme(button, "BackgroundColor3", "Background")
    PcdHub:_BindTheme(button, "TextColor3", "MutedText")

    local listening = false

    local function set(value, fromConfig)
        if type(value) == "string" then
            value = Enum.KeyCode[value]
        end
        if typeof(value) ~= "EnumItem" then
            return
        end
        current = value
        button.Text = current.Name
        if flag then
            PcdHub.Flags[flag] = current.Name
        end
        if not fromConfig or options.FireOnLoad == true then
            safeCall(options.Changed, current)
        end
    end

    registerFlag(flag, current.Name, set)

    connect(button.Activated, function()
        listening = true
        button.Text = "..."
    end)

    connect(UserInputService.InputBegan, function(input, processed)
        if input.UserInputType ~= Enum.UserInputType.Keyboard then
            return
        end

        if listening then
            listening = false
            set(input.KeyCode, false)
            return
        end

        if input.KeyCode == current and (not processed or options.IgnoreProcessed == true) then
            safeCall(options.Callback, current)
        end
    end)

    local handle = {}
    function handle:Set(value)
        set(value, false)
    end
    function handle:Get()
        return current
    end
    return handle
end

function SectionMethods:CreateLabel(text)
    local frame = createElementShell(self.Container, 38)
    frame:SetAttribute("PcdSearchText", string.lower(tostring(text or "Label")))
    local label = createLabel(frame, tostring(text or "Label"), 12, false)
    padding(label, 14, 14, 0, 0)

    local handle = {}
    function handle:Set(value)
        label.Text = tostring(value)
    end
    return handle
end

function SectionMethods:CreateParagraph(options)
    options = options or {}
    local frame = createElementShell(self.Container, 72)
    frame:SetAttribute("PcdSearchText", string.lower(tostring(options.Title or "Information") .. " " .. tostring(options.Content or "")))
    local title = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 14, 0, 10),
        Size = UDim2.new(1, -28, 0, 18),
        Font = Enum.Font.GothamSemibold,
        Text = options.Title or "Information",
        TextColor3 = theme().Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })
    local content = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 14, 0, 31),
        Size = UDim2.new(1, -28, 0, 31),
        Font = Enum.Font.Gotham,
        Text = options.Content or "",
        TextWrapped = true,
        TextColor3 = theme().MutedText,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = frame,
    })
    PcdHub:_BindTheme(title, "TextColor3", "Text")
    PcdHub:_BindTheme(content, "TextColor3", "MutedText")

    local handle = {}
    function handle:Set(newTitle, newContent)
        if newContent == nil then
            content.Text = tostring(newTitle)
        else
            title.Text = tostring(newTitle)
            content.Text = tostring(newContent)
        end
    end
    return handle
end

function SectionMethods:CreateDivider()
    local line = new("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = theme().Border,
        BorderSizePixel = 0,
        Parent = self.Container,
    })
    PcdHub:_BindTheme(line, "BackgroundColor3", "Border")
    return line
end

local TabMethods = {}
TabMethods.__index = TabMethods

function TabMethods:_GetDefaultSection()
    if self._defaultSection then
        return self._defaultSection
    end
    self._defaultSection = self:CreateSection(nil, true)
    return self._defaultSection
end

function TabMethods:CreateSection(name, hiddenTitle)
    local sectionRoot = new("Frame", {
        Size = UDim2.new(1, -4, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = self.Page,
    })

    local layout = new("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = sectionRoot,
    })

    if name and not hiddenTitle then
        local header = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamSemibold,
            Text = string.upper(name),
            TextColor3 = theme().MutedText,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = sectionRoot,
        })
        PcdHub:_BindTheme(header, "TextColor3", "MutedText")
    end

    local section = setmetatable({
        Container = sectionRoot,
        Layout = layout,
        Name = name,
    }, SectionMethods)

    return section
end

for _, methodName in ipairs({
    "CreateButton",
    "CreateToggle",
    "CreateSlider",
    "CreateInput",
    "CreateColorPicker",
    "CreateDropdown",
    "CreateKeybind",
    "CreateLabel",
    "CreateParagraph",
    "CreateDivider",
}) do
    local delegatedMethod = methodName
    TabMethods[delegatedMethod] = function(self, ...)
        local section = self:_GetDefaultSection()
        return section[delegatedMethod](section, ...)
    end
end

-- Window ----------------------------------------------------------------------
function PcdHub:CreateWindow(options)
    options = options or {}

    if self._screenGui then
        self:Destroy()
    end

    if options.Theme and self.Themes[options.Theme] then
        self.Theme = options.Theme
    end

    local screenGui = new("ScreenGui", {
        Name = options.GuiName or "PcdFnlBossHub",
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = tonumber(options.DisplayOrder) or 999,
        Parent = getRootParent(),
    })
    self._screenGui = screenGui

    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local requestedWidth = tonumber(options.Width) or 560
    local requestedHeight = tonumber(options.Height) or 350
    local width = math.clamp(requestedWidth, 330, math.max(330, viewport.X - 18))
    local height = math.clamp(requestedHeight, 270, math.max(270, viewport.Y - 30))
    local compactBreakpoint = 560
    local compact = viewport.X <= compactBreakpoint
    local sidebarExpandedWidth = compact and 116 or 138
    local sidebarCollapsedWidth = 54
    local sidebarCollapsed = options.SidebarCollapsed == true or (compact and options.AutoCollapseSidebar ~= false)
    local sidebarWidth = sidebarCollapsed and sidebarCollapsedWidth or sidebarExpandedWidth

    local overlay = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 90,
        Parent = screenGui,
    })

    local main = new("Frame", {
        Name = "Main",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = theme().Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = screenGui,
    })
    corner(main, 16)
    stroke(main, "Border", 0.05, 1)
    self:_BindTheme(main, "BackgroundColor3", "Background")

    local headerHeight = 46
    local header = new("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, headerHeight),
        BackgroundColor3 = theme().Surface,
        BorderSizePixel = 0,
        Parent = main,
    })
    self:_BindTheme(header, "BackgroundColor3", "Surface")

    local menuButton = new("TextButton", {
        Position = UDim2.new(0, 8, 0.5, -14),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = theme().SurfaceAlt,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "≡",
        TextColor3 = theme().MutedText,
        TextSize = 16,
        AutoButtonColor = false,
        Parent = header,
    })
    corner(menuButton, 8)
    self:_BindTheme(menuButton, "BackgroundColor3", "SurfaceAlt")
    self:_BindTheme(menuButton, "TextColor3", "MutedText")

    local title = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 44, 0, 6),
        Size = UDim2.new(1, -126, 0, 18),
        Font = Enum.Font.GothamSemibold,
        Text = options.Name or options.Title or "Pcd Fnl Boss Hub",
        TextColor3 = theme().Text,
        TextSize = 14,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header,
    })
    self:_BindTheme(title, "TextColor3", "Text")

    local subtitle = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 44, 0, 24),
        Size = UDim2.new(1, -126, 0, 14),
        Font = Enum.Font.Gotham,
        Text = options.Subtitle or ("Pcd UI • " .. self.Version),
        TextColor3 = theme().MutedText,
        TextSize = 9,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header,
    })
    self:_BindTheme(subtitle, "TextColor3", "MutedText")

    local minimize = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -40, 0.5, 0),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = theme().SurfaceAlt,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "–",
        TextColor3 = theme().MutedText,
        TextSize = 16,
        AutoButtonColor = false,
        Parent = header,
    })
    corner(minimize, 8)
    self:_BindTheme(minimize, "BackgroundColor3", "SurfaceAlt")
    self:_BindTheme(minimize, "TextColor3", "MutedText")

    local close = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = theme().SurfaceAlt,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "×",
        TextColor3 = theme().MutedText,
        TextSize = 16,
        AutoButtonColor = false,
        Parent = header,
    })
    corner(close, 8)
    self:_BindTheme(close, "BackgroundColor3", "SurfaceAlt")
    self:_BindTheme(close, "TextColor3", "MutedText")

    local sidebar = new("Frame", {
        Name = "Sidebar",
        Position = UDim2.new(0, 0, 0, headerHeight),
        Size = UDim2.new(0, sidebarWidth, 1, -headerHeight),
        BackgroundColor3 = theme().Sidebar,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = main,
    })
    self:_BindTheme(sidebar, "BackgroundColor3", "Sidebar")

    local searchBox = new("TextBox", {
        Position = UDim2.new(0, 8, 0, 8),
        Size = UDim2.new(1, -16, 0, 30),
        BackgroundColor3 = theme().SurfaceAlt,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        PlaceholderText = "Search",
        PlaceholderColor3 = theme().MutedText,
        Text = "",
        TextColor3 = theme().Text,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Visible = not sidebarCollapsed,
        Parent = sidebar,
    })
    corner(searchBox, 9)
    padding(searchBox, 9, 9, 0, 0)
    self:_BindTheme(searchBox, "BackgroundColor3", "SurfaceAlt")
    self:_BindTheme(searchBox, "PlaceholderColor3", "MutedText")
    self:_BindTheme(searchBox, "TextColor3", "Text")

    local tabHolder = new("ScrollingFrame", {
        Position = UDim2.new(0, 7, 0, sidebarCollapsed and 8 or 46),
        Size = UDim2.new(1, -14, 1, sidebarCollapsed and -16 or -54),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = theme().Accent,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Parent = sidebar,
    })
    self:_BindTheme(tabHolder, "ScrollBarImageColor3", "Accent")
    new("UIListLayout", {
        Padding = UDim.new(0, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = tabHolder,
    })

    local content = new("Frame", {
        Name = "Content",
        Position = UDim2.new(0, sidebarWidth, 0, headerHeight),
        Size = UDim2.new(1, -sidebarWidth, 1, -headerHeight),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = main,
    })

    local mobileOpen = new("TextButton", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -12, 1, -12),
        Size = UDim2.fromOffset(46, 46),
        BackgroundColor3 = theme().Accent,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = "PFB",
        TextColor3 = Color3.new(1, 1, 1),
        TextSize = 10,
        Visible = false,
        AutoButtonColor = false,
        Parent = screenGui,
    })
    corner(mobileOpen, 14)
    stroke(mobileOpen, "Border", 0.15, 1)
    self:_BindTheme(mobileOpen, "BackgroundColor3", "Accent")

    makeDraggable(header, main, true)
    makeDraggable(mobileOpen, mobileOpen, true)

    local tabs = {}
    local activeTab = nil
    local visible = true

    local function setVisible(state)
        visible = state == true
        main.Visible = visible
        mobileOpen.Visible = not visible
    end

    local function getSidebarWidth()
        return sidebarCollapsed and sidebarCollapsedWidth or sidebarExpandedWidth
    end

    local function renderSidebar(animated)
        sidebarWidth = getSidebarWidth()
        local sideSize = UDim2.new(0, sidebarWidth, 1, -headerHeight)
        local contentPos = UDim2.new(0, sidebarWidth, 0, headerHeight)
        local contentSize = UDim2.new(1, -sidebarWidth, 1, -headerHeight)
        if animated then
            tween(sidebar, 0.16, {Size = sideSize})
            tween(content, 0.16, {Position = contentPos, Size = contentSize})
        else
            sidebar.Size = sideSize
            content.Position = contentPos
            content.Size = contentSize
        end
        searchBox.Visible = not sidebarCollapsed
        tabHolder.Position = UDim2.new(0, 7, 0, sidebarCollapsed and 8 or 46)
        tabHolder.Size = UDim2.new(1, -14, 1, sidebarCollapsed and -16 or -54)

        for _, tab in ipairs(tabs) do
            if tab.Label then
                tab.Label.Visible = not sidebarCollapsed
            end
            if tab.IconLabel then
                tab.IconLabel.Position = sidebarCollapsed and UDim2.new(0.5, -9, 0.5, -9) or UDim2.new(0, 9, 0.5, -9)
            end
        end
    end

    local function applySearch(query)
        query = string.lower(tostring(query or ""))
        if not activeTab then return end
        for _, section in ipairs(activeTab.Page:GetChildren()) do
            if section:IsA("Frame") then
                local visibleChildren = 0
                for _, child in ipairs(section:GetChildren()) do
                    if child:IsA("GuiObject") and child:GetAttribute("PcdElement") then
                        local text = tostring(child:GetAttribute("PcdSearchText") or "")
                        local show = query == "" or string.find(text, query, 1, true) ~= nil
                        child.Visible = show
                        if show then visibleChildren += 1 end
                    end
                end
                section.Visible = query == "" or visibleChildren > 0
            end
        end
    end

    local function selectTab(tab)
        if activeTab == tab then
            return
        end
        for _, item in ipairs(tabs) do
            local selected = item == tab
            item.Page.Visible = selected
            tween(item.Button, 0.14, {
                BackgroundColor3 = selected and theme().AccentSoft or theme().SurfaceAlt,
            })
            tween(item.Indicator, 0.14, {
                BackgroundTransparency = selected and 0 or 1,
            })
            if item.Label then
                tween(item.Label, 0.14, {
                    TextColor3 = selected and theme().Text or theme().MutedText,
                })
            end
        end
        activeTab = tab
        searchBox.Text = ""
        applySearch("")
    end

    local window = {
        Main = main,
        ScreenGui = screenGui,
        Tabs = tabs,
        IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
    }

    function window:CreateTab(name, icon)
        if type(name) == "table" then
            icon = name.Icon or name.icon
            name = name.Name or name.name or "Tab"
        end
        name = tostring(name or "Tab")

        local button = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 36),
            BackgroundColor3 = theme().SurfaceAlt,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            Parent = tabHolder,
        })
        corner(button, 9)
        PcdHub:_BindTheme(button, "BackgroundColor3", "SurfaceAlt")

        local indicator = new("Frame", {
            Position = UDim2.new(0, 3, 0.5, -8),
            Size = UDim2.fromOffset(3, 16),
            BackgroundColor3 = theme().Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = button,
        })
        corner(indicator, 4)
        PcdHub:_BindTheme(indicator, "BackgroundColor3", "Accent")

        local iconLabel
        if icon then
            iconLabel = new("ImageLabel", {
                Position = sidebarCollapsed and UDim2.new(0.5, -9, 0.5, -9) or UDim2.new(0, 9, 0.5, -9),
                Size = UDim2.fromOffset(18, 18),
                BackgroundTransparency = 1,
                Image = tostring(icon):find("rbxassetid://") and tostring(icon) or ("rbxassetid://" .. tostring(icon)),
                ImageColor3 = theme().MutedText,
                Parent = button,
            })
            PcdHub:_BindTheme(iconLabel, "ImageColor3", "MutedText")
        else
            local initials = string.sub(name, 1, 1)
            iconLabel = new("TextLabel", {
                Position = sidebarCollapsed and UDim2.new(0.5, -9, 0.5, -9) or UDim2.new(0, 9, 0.5, -9),
                Size = UDim2.fromOffset(18, 18),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                Text = string.upper(initials),
                TextColor3 = theme().MutedText,
                TextSize = 11,
                Parent = button,
            })
            PcdHub:_BindTheme(iconLabel, "TextColor3", "MutedText")
        end

        local label = new("TextLabel", {
            Position = UDim2.new(0, 34, 0, 0),
            Size = UDim2.new(1, -40, 1, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamSemibold,
            Text = name,
            TextColor3 = theme().MutedText,
            TextSize = 10,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
            Visible = not sidebarCollapsed,
            Parent = button,
        })
        PcdHub:_BindTheme(label, "TextColor3", "MutedText")

        local page = new("ScrollingFrame", {
            Position = UDim2.new(0, 10, 0, 8),
            Size = UDim2.new(1, -20, 1, -16),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = theme().Accent,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            Visible = false,
            Parent = content,
        })
        PcdHub:_BindTheme(page, "ScrollBarImageColor3", "Accent")
        padding(page, 1, 4, 2, 8)
        new("UIListLayout", {
            Padding = UDim.new(0, 10),
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = page,
        })

        local tab = setmetatable({
            Name = name,
            Icon = icon,
            Button = button,
            Indicator = indicator,
            IconLabel = iconLabel,
            Label = label,
            Page = page,
        }, TabMethods)

        table.insert(tabs, tab)
        connect(button.Activated, function()
            selectTab(tab)
            if compact and not sidebarCollapsed then
                sidebarCollapsed = true
                renderSidebar(true)
            end
        end)

        if #tabs == 1 then
            selectTab(tab)
        end
        return tab
    end

    function window:SelectTab(tabOrName)
        if type(tabOrName) == "table" then
            selectTab(tabOrName)
            return true
        end
        for _, tab in ipairs(tabs) do
            if tab.Name == tabOrName then
                selectTab(tab)
                return true
            end
        end
        return false
    end

    function window:SetTitle(value)
        title.Text = tostring(value)
    end

    function window:SetSubtitle(value)
        subtitle.Text = tostring(value)
    end

    function window:SetTheme(value)
        return PcdHub:SetTheme(value)
    end

    function window:SetSidebarCollapsed(state)
        sidebarCollapsed = state == true
        renderSidebar(true)
    end

    function window:IsSidebarCollapsed()
        return sidebarCollapsed
    end

    function window:SetVisible(state)
        setVisible(state)
    end

    function window:IsVisible()
        return visible
    end

    function window:Toggle()
        setVisible(not visible)
    end

    function window:SetSize(newWidth, newHeight)
        local currentViewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or viewport
        width = math.clamp(tonumber(newWidth) or width, 330, math.max(330, currentViewport.X - 18))
        height = math.clamp(tonumber(newHeight) or height, 270, math.max(270, currentViewport.Y - 30))
        tween(main, 0.18, {Size = UDim2.fromOffset(width, height)})
    end

    function window:GetSize()
        return Vector2.new(width, height)
    end

    function window:Notify(data)
        return PcdHub:Notify(data)
    end

    function window:Dialog(data)
        data = data or {}
        overlay.Visible = true
        overlay.BackgroundTransparency = 1
        tween(overlay, 0.15, {BackgroundTransparency = 0.48})

        local dialog = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.fromOffset(math.min(330, math.max(250, main.AbsoluteSize.X - 40)), 150),
            BackgroundColor3 = theme().Surface,
            BorderSizePixel = 0,
            ZIndex = 91,
            Parent = overlay,
        })
        corner(dialog, 14)
        stroke(dialog, "Border", 0.08, 1)
        PcdHub:_BindTheme(dialog, "BackgroundColor3", "Surface")

        local dTitle = new("TextLabel", {
            Position = UDim2.new(0, 14, 0, 12),
            Size = UDim2.new(1, -28, 0, 20),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamSemibold,
            Text = tostring(data.Title or "Confirm"),
            TextColor3 = theme().Text,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 92,
            Parent = dialog,
        })
        PcdHub:_BindTheme(dTitle, "TextColor3", "Text")

        local dContent = new("TextLabel", {
            Position = UDim2.new(0, 14, 0, 38),
            Size = UDim2.new(1, -28, 0, 58),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            Text = tostring(data.Content or data.Description or "Are you sure?"),
            TextColor3 = theme().MutedText,
            TextSize = 11,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 92,
            Parent = dialog,
        })
        PcdHub:_BindTheme(dContent, "TextColor3", "MutedText")

        local buttons = new("Frame", {
            Position = UDim2.new(0, 14, 1, -42),
            Size = UDim2.new(1, -28, 0, 30),
            BackgroundTransparency = 1,
            ZIndex = 92,
            Parent = dialog,
        })
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            Padding = UDim.new(0, 7),
            Parent = buttons,
        })

        local function closeDialog(result)
            if not overlay.Visible then return end
            safeCall(data.Callback, result)
            tween(overlay, 0.12, {BackgroundTransparency = 1})
            task.delay(0.13, function()
                if dialog.Parent then dialog:Destroy() end
                overlay.Visible = false
            end)
        end

        local cancel = new("TextButton", {
            Size = UDim2.fromOffset(84, 30),
            BackgroundColor3 = theme().SurfaceAlt,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamSemibold,
            Text = tostring(data.CancelText or "Cancel"),
            TextColor3 = theme().MutedText,
            TextSize = 10,
            AutoButtonColor = false,
            ZIndex = 93,
            Parent = buttons,
        })
        corner(cancel, 8)
        PcdHub:_BindTheme(cancel, "BackgroundColor3", "SurfaceAlt")
        PcdHub:_BindTheme(cancel, "TextColor3", "MutedText")

        local confirm = new("TextButton", {
            Size = UDim2.fromOffset(84, 30),
            BackgroundColor3 = theme().Accent,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamSemibold,
            Text = tostring(data.ConfirmText or "Confirm"),
            TextColor3 = theme().Text,
            TextSize = 10,
            AutoButtonColor = false,
            ZIndex = 93,
            Parent = buttons,
        })
        corner(confirm, 8)
        PcdHub:_BindTheme(confirm, "BackgroundColor3", "Accent")
        PcdHub:_BindTheme(confirm, "TextColor3", "Text")

        connect(cancel.Activated, function() closeDialog(false) end)
        connect(confirm.Activated, function() closeDialog(true) end)

        return {Close = closeDialog, Frame = dialog}
    end

    function window:Destroy()
        PcdHub:Destroy()
    end

    connect(menuButton.Activated, function()
        sidebarCollapsed = not sidebarCollapsed
        renderSidebar(true)
    end)
    connect(minimize.Activated, function() setVisible(false) end)
    connect(mobileOpen.Activated, function() setVisible(true) end)
    connect(close.Activated, function()
        if options.CloseCallback then safeCall(options.CloseCallback) end
        PcdHub:Destroy()
    end)
    connect(searchBox:GetPropertyChangedSignal("Text"), function()
        applySearch(searchBox.Text)
    end)

    local toggleKey = options.ToggleUIKeybind or Enum.KeyCode.RightShift
    if type(toggleKey) == "string" then
        toggleKey = Enum.KeyCode[toggleKey] or Enum.KeyCode.RightShift
    end
    connect(UserInputService.InputBegan, function(input, processed)
        if input.KeyCode == toggleKey and (not processed or options.IgnoreProcessedToggle == true) then
            setVisible(not visible)
        end
    end)

    if camera then
        connect(camera:GetPropertyChangedSignal("ViewportSize"), function()
            local v = camera.ViewportSize
            compact = v.X <= compactBreakpoint
            local maxWidth = math.max(330, v.X - 18)
            local maxHeight = math.max(270, v.Y - 30)
            width = math.min(width, maxWidth)
            height = math.min(height, maxHeight)
            main.Size = UDim2.fromOffset(width, height)
            sidebarExpandedWidth = compact and 116 or 138
            if compact and options.AutoCollapseSidebar ~= false then
                sidebarCollapsed = true
            end
            renderSidebar(false)
        end)
    end

    renderSidebar(false)

    local config = options.ConfigurationSaving or options.Configuration
    if type(config) == "table" and config.Enabled then
        local folder = config.FolderName or "PcdFnlBossHub"
        local file = config.FileName or "config"
        window.Config = {Folder = folder, File = file}
        function window:SaveConfiguration()
            return PcdHub:SaveConfig(folder, file)
        end
        function window:LoadConfiguration()
            return PcdHub:LoadConfig(folder, file)
        end
        if config.AutoLoad ~= false then
            task.defer(function()
                PcdHub:LoadConfig(folder, file)
            end)
        end
    else
        function window:SaveConfiguration()
            return false, "Configuration saving is disabled"
        end
        function window:LoadConfiguration()
            return false, "Configuration saving is disabled"
        end
    end

    return window
end

return PcdHub
