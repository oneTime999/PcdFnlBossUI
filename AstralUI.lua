--[[
    AstraUI
    Modern Luau UI framework for Roblox experiences.

    Goals:
    - Original visual language (not a Rayfield clone)
    - Window / tabs / sections
    - Buttons, toggles, sliders, inputs, dropdowns, multi-dropdowns, keybinds
    - Search
    - Notifications
    - Local key-gate with optional custom validator
    - Flag/config system with JSON import/export
    - Mobile-friendly dragging + responsive layout
    - Theme switching
    - Clean unload lifecycle

    NOTE ABOUT KEY SYSTEMS:
    A key checked only on the client is never truly secure. For a real production
    experience, use KeySystem.Validate to ask your own server to validate access.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Executor-friendly GUI parent resolution.
-- Priority: explicit Parent -> gethui() -> PlayerGui -> CoreGui.
-- No executor-specific protection/evasion API is required.
local function resolveGuiParent(explicitParent)
    if explicitParent and typeof(explicitParent) == "Instance" then
        return explicitParent
    end

    local globalGetHui = gethui
    if type(globalGetHui) == "function" then
        local ok, result = pcall(globalGetHui)
        if ok and typeof(result) == "Instance" then
            return result
        end
    end

    LocalPlayer = Players.LocalPlayer or LocalPlayer
    if LocalPlayer then
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            or LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then
            local ok, result = pcall(function()
                return LocalPlayer:WaitForChild("PlayerGui", 8)
            end)
            if ok then
                playerGui = result
            end
        end
        if playerGui then
            return playerGui
        end
    end

    local ok, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)
    if ok and coreGui then
        return coreGui
    end

    error("[AstraUI] Unable to resolve a GUI parent. Pass CreateWindow({Parent = ...}).")
end

local AstraUI = {}
AstraUI.__index = AstraUI
AstraUI.Version = "3.0.0-executor"

local DEFAULT_THEME = {
    Background = Color3.fromRGB(12, 14, 19),
    Surface = Color3.fromRGB(19, 22, 29),
    Surface2 = Color3.fromRGB(25, 29, 38),
    Surface3 = Color3.fromRGB(31, 36, 47),
    Accent = Color3.fromRGB(108, 92, 231),
    Accent2 = Color3.fromRGB(93, 173, 226),
    Text = Color3.fromRGB(244, 246, 250),
    Muted = Color3.fromRGB(153, 161, 176),
    Border = Color3.fromRGB(52, 58, 72),
    Success = Color3.fromRGB(70, 201, 126),
    Warning = Color3.fromRGB(245, 180, 66),
    Danger = Color3.fromRGB(240, 86, 93),
}

local LIGHT_THEME = {
    Background = Color3.fromRGB(239, 242, 247),
    Surface = Color3.fromRGB(255, 255, 255),
    Surface2 = Color3.fromRGB(247, 249, 252),
    Surface3 = Color3.fromRGB(235, 239, 246),
    Accent = Color3.fromRGB(91, 76, 224),
    Accent2 = Color3.fromRGB(48, 137, 214),
    Text = Color3.fromRGB(27, 31, 39),
    Muted = Color3.fromRGB(100, 109, 125),
    Border = Color3.fromRGB(207, 214, 224),
    Success = Color3.fromRGB(44, 168, 99),
    Warning = Color3.fromRGB(218, 147, 35),
    Danger = Color3.fromRGB(215, 66, 75),
}

local function merge(base, patch)
    local result = {}
    for k, v in pairs(base) do
        result[k] = v
    end
    for k, v in pairs(patch or {}) do
        result[k] = v
    end
    return result
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return true
    end

    local ok, err = pcall(fn, ...)
    if not ok then
        warn("[AstraUI] Callback error:", err)
    end
    return ok
end

local function tween(obj, duration, props, style, direction)
    local info = TweenInfo.new(
        duration or 0.16,
        style or Enum.EasingStyle.Quart,
        direction or Enum.EasingDirection.Out
    )
    local tw = TweenService:Create(obj, info, props)
    tw:Play()
    return tw
end

local function create(className, properties, children)
    local instance = Instance.new(className)

    for property, value in pairs(properties or {}) do
        if property ~= "Parent" then
            instance[property] = value
        end
    end

    for _, child in ipairs(children or {}) do
        child.Parent = instance
    end

    if properties and properties.Parent then
        instance.Parent = properties.Parent
    end

    return instance
end

local function corner(radius)
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius or 10)
    })
end

local function stroke(color, transparency, thickness)
    return create("UIStroke", {
        Color = color or Color3.new(1,1,1),
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    })
end

local function padding(l, r, t, b)
    return create("UIPadding", {
        PaddingLeft = UDim.new(0, l or 0),
        PaddingRight = UDim.new(0, r or l or 0),
        PaddingTop = UDim.new(0, t or l or 0),
        PaddingBottom = UDim.new(0, b or t or l or 0),
    })
end

local function listLayout(parent, gap, alignment)
    return create("UIListLayout", {
        Parent = parent,
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = alignment or Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, gap or 8),
    })
end

local function textLabel(parent, text, size, color, bold)
    return create("TextLabel", {
        Parent = parent,
        BackgroundTransparency = 1,
        Text = text or "",
        TextSize = size or 14,
        TextColor3 = color or Color3.new(1,1,1),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        AutomaticSize = Enum.AutomaticSize.Y,
        Size = UDim2.new(1, 0, 0, 20),
        TextWrapped = true,
    })
end

local function button(parent, text, size, color)
    return create("TextButton", {
        Parent = parent,
        AutoButtonColor = false,
        BackgroundColor3 = color,
        Size = size,
        Text = text or "",
        TextColor3 = Color3.new(1,1,1),
        TextSize = 14,
        Font = Enum.Font.GothamMedium,
        BorderSizePixel = 0,
    }, {
        corner(10)
    })
end

local function isTouchDevice()
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function normalizeKeyCode(value)
    if typeof(value) == "EnumItem" and value.EnumType == Enum.KeyCode then
        return value
    end

    if type(value) == "string" then
        local ok, result = pcall(function()
            return Enum.KeyCode[value]
        end)
        if ok then
            return result
        end
    end

    return Enum.KeyCode.RightShift
end

function AstraUI.new()
    local self = setmetatable({}, AstraUI)
    self._connections = {}
    self._windows = {}
    self._destroyed = false
    return self
end

function AstraUI:_track(connection)
    table.insert(self._connections, connection)
    return connection
end

function AstraUI:Destroy()
    if self._destroyed then
        return
    end

    self._destroyed = true

    for _, connection in ipairs(self._connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    for _, window in ipairs(self._windows) do
        pcall(function()
            window:Destroy()
        end)
    end

    table.clear(self._connections)
    table.clear(self._windows)
end

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

function AstraUI:CreateWindow(options)
    options = options or {}

    local parent = resolveGuiParent(options.Parent)

    local screenName = options.Name or "AstraUI"
    if options.ReplaceExisting == true then
        local existing = parent:FindFirstChild(screenName)
        if existing and existing:IsA("ScreenGui") then
            existing:Destroy()
        end
    end

    local theme = merge(DEFAULT_THEME, options.Theme)
    local window = setmetatable({}, Window)

    window.Library = self
    window.Options = options
    window.Theme = theme
    window.Flags = {}
    window.FlagObjects = {}
    window.Tabs = {}
    window.CurrentTab = nil
    window.Destroyed = false
    window.Minimized = false
    window.KeyUnlocked = not (options.KeySystem and options.KeySystem.Enabled)
    window._themeBindings = {}
    window._connections = {}
    window._searchItems = {}
    window._themeListeners = {}
    window._dialogs = {}
    window._darkTheme = merge({}, theme)

    local screen = create("ScreenGui", {
        Name = screenName,
        ResetOnSpawn = false,
        IgnoreGuiInset = options.IgnoreGuiInset == true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = options.DisplayOrder or 10,
        Parent = parent,
    })

    pcall(function()
        screen:SetAttribute("AstraUI", true)
        screen:SetAttribute("AstraUIVersion", AstraUI.Version)
    end)

    local root = create("Frame", {
        Name = "Root",
        Parent = screen,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = options.Size or UDim2.fromOffset(760, 500),
        BackgroundColor3 = theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, {
        corner(18),
        stroke(theme.Border, 0.2, 1),
    })

    local scale = create("UIScale", {
        Parent = root,
        Scale = 1
    })

    local shadow = create("ImageLabel", {
        Name = "Shadow",
        Parent = root,
        BackgroundTransparency = 1,
        Image = "rbxassetid://1316045217",
        ImageColor3 = Color3.new(0,0,0),
        ImageTransparency = 0.55,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(10,10,118,118),
        Size = UDim2.new(1, 46, 1, 46),
        Position = UDim2.fromOffset(-23,-23),
        ZIndex = 0,
    })

    root.ZIndex = 2

    local sidebar = create("Frame", {
        Name = "Sidebar",
        Parent = root,
        BackgroundColor3 = theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 210, 1, 0),
        ZIndex = 3,
    })

    local sidebarDivider = create("Frame", {
        Parent = sidebar,
        AnchorPoint = Vector2.new(1,0),
        Position = UDim2.new(1,0,0,0),
        Size = UDim2.new(0,1,1,0),
        BackgroundColor3 = theme.Border,
        BackgroundTransparency = 0.25,
        BorderSizePixel = 0,
    })

    local brand = create("Frame", {
        Parent = sidebar,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(16,16),
        Size = UDim2.new(1,-32,0,54),
    })

    local brandIcon = create("Frame", {
        Parent = brand,
        Size = UDim2.fromOffset(38,38),
        BackgroundColor3 = theme.Accent,
        BorderSizePixel = 0,
    }, {
        corner(12),
    })

    local iconText = create("TextLabel", {
        Parent = brandIcon,
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1,1),
        Text = options.IconText or "A",
        TextColor3 = Color3.new(1,1,1),
        TextSize = 17,
        Font = Enum.Font.GothamBold,
    })

    local title = create("TextLabel", {
        Parent = brand,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(50, 0),
        Size = UDim2.new(1,-50,0,22),
        Text = options.Title or "Astra",
        TextColor3 = theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold,
        TextSize = 16,
    })

    local subtitle = create("TextLabel", {
        Parent = brand,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(50, 24),
        Size = UDim2.new(1,-50,0,18),
        Text = options.Subtitle or "Modern interface",
        TextColor3 = theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.Gotham,
        TextSize = 11,
    })

    local searchHolder = create("Frame", {
        Parent = sidebar,
        Position = UDim2.fromOffset(14,78),
        Size = UDim2.new(1,-28,0,38),
        BackgroundColor3 = theme.Surface2,
        BorderSizePixel = 0,
    }, {
        corner(10),
        stroke(theme.Border, 0.4, 1),
    })

    local searchIcon = create("TextLabel", {
        Parent = searchHolder,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(11,0),
        Size = UDim2.fromOffset(20,38),
        Text = "⌕",
        TextColor3 = theme.Muted,
        TextSize = 18,
        Font = Enum.Font.GothamBold,
    })

    local searchBox = create("TextBox", {
        Parent = searchHolder,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(34,0),
        Size = UDim2.new(1,-42,1,0),
        PlaceholderText = "Search",
        PlaceholderColor3 = theme.Muted,
        Text = "",
        TextColor3 = theme.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
    })

    local tabList = create("ScrollingFrame", {
        Parent = sidebar,
        Position = UDim2.fromOffset(10,126),
        Size = UDim2.new(1,-20,1,-180),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
    })
    listLayout(tabList, 6)

    local footer = create("Frame", {
        Parent = sidebar,
        AnchorPoint = Vector2.new(0,1),
        Position = UDim2.new(0,12,1,-12),
        Size = UDim2.new(1,-24,0,42),
        BackgroundColor3 = theme.Surface2,
        BorderSizePixel = 0,
    }, {
        corner(10),
    })

    local footerDot = create("Frame", {
        Parent = footer,
        Position = UDim2.fromOffset(11,15),
        Size = UDim2.fromOffset(10,10),
        BackgroundColor3 = theme.Success,
        BorderSizePixel = 0,
    }, {
        corner(999)
    })

    local footerText = create("TextLabel", {
        Parent = footer,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(30,0),
        Size = UDim2.new(1,-40,1,0),
        Text = options.Footer or ("AstraUI v" .. AstraUI.Version),
        TextColor3 = theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextSize = 11,
        Font = Enum.Font.Gotham,
    })

    local main = create("Frame", {
        Name = "Main",
        Parent = root,
        BackgroundColor3 = theme.Background,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(210,0),
        Size = UDim2.new(1,-210,1,0),
        ZIndex = 3,
    })

    local topbar = create("Frame", {
        Name = "Topbar",
        Parent = main,
        BackgroundTransparency = 1,
        Size = UDim2.new(1,0,0,66),
    })

    local pageTitle = create("TextLabel", {
        Parent = topbar,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(20,12),
        Size = UDim2.new(1,-160,0,24),
        Text = "Dashboard",
        TextColor3 = theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold,
        TextSize = 18,
    })

    local pageDesc = create("TextLabel", {
        Parent = topbar,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(20,36),
        Size = UDim2.new(1,-160,0,18),
        Text = "Select a section",
        TextColor3 = theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.Gotham,
        TextSize = 11,
    })

    local topActions = create("Frame", {
        Parent = topbar,
        AnchorPoint = Vector2.new(1,0),
        Position = UDim2.new(1,-14,0,14),
        Size = UDim2.fromOffset(92,36),
        BackgroundTransparency = 1,
    })

    local themeButton = button(topActions, "◐", UDim2.fromOffset(36,36), theme.Surface2)
    themeButton.Position = UDim2.fromOffset(0,0)
    themeButton.TextColor3 = theme.Muted
    themeButton.TextSize = 16

    local minimizeButton = button(topActions, "—", UDim2.fromOffset(36,36), theme.Surface2)
    minimizeButton.Position = UDim2.fromOffset(44,0)
    minimizeButton.TextColor3 = theme.Muted
    minimizeButton.TextSize = 16

    local pages = create("Frame", {
        Name = "Pages",
        Parent = main,
        Position = UDim2.fromOffset(0,66),
        Size = UDim2.new(1,0,1,-66),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
    })

    local notificationHost = create("Frame", {
        Name = "Notifications",
        Parent = screen,
        AnchorPoint = Vector2.new(1,0),
        Position = UDim2.new(1,-16,0,16),
        Size = UDim2.fromOffset(330, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex = 100,
    })
    listLayout(notificationHost, 8, Enum.HorizontalAlignment.Right)

    local mobileOpen = button(screen, "A", UDim2.fromOffset(52,52), theme.Accent)
    mobileOpen.Name = "MobileOpen"
    mobileOpen.Visible = false
    mobileOpen.AnchorPoint = Vector2.new(1,1)
    mobileOpen.Position = UDim2.new(1,-18,1,-24)
    mobileOpen.ZIndex = 99
    mobileOpen.TextSize = 18

    window.ScreenGui = screen
    window.Root = root
    window.Scale = scale
    window.Sidebar = sidebar
    window.TabList = tabList
    window.Main = main
    window.Pages = pages
    window.PageTitle = pageTitle
    window.PageDesc = pageDesc
    window.SearchBox = searchBox
    window.NotificationHost = notificationHost
    window.MobileOpen = mobileOpen
    window.BrandTitle = title
    window.BrandSubtitle = subtitle
    window.Footer = footer
    window.FooterText = footerText
    window.Topbar = topbar
    window.ThemeButton = themeButton
    window.MinimizeButton = minimizeButton

    local function bindTheme(instance, property, key)
        table.insert(window._themeBindings, {
            Instance = instance,
            Property = property,
            Key = key,
        })
    end

    window._bindTheme = bindTheme

    bindTheme(root, "BackgroundColor3", "Background")
    bindTheme(sidebar, "BackgroundColor3", "Surface")
    bindTheme(sidebarDivider, "BackgroundColor3", "Border")
    bindTheme(brandIcon, "BackgroundColor3", "Accent")
    bindTheme(title, "TextColor3", "Text")
    bindTheme(subtitle, "TextColor3", "Muted")
    bindTheme(searchHolder, "BackgroundColor3", "Surface2")
    bindTheme(searchIcon, "TextColor3", "Muted")
    bindTheme(searchBox, "TextColor3", "Text")
    bindTheme(searchBox, "PlaceholderColor3", "Muted")
    bindTheme(footer, "BackgroundColor3", "Surface2")
    bindTheme(footerDot, "BackgroundColor3", "Success")
    bindTheme(footerText, "TextColor3", "Muted")
    bindTheme(main, "BackgroundColor3", "Background")
    bindTheme(pageTitle, "TextColor3", "Text")
    bindTheme(pageDesc, "TextColor3", "Muted")
    bindTheme(themeButton, "BackgroundColor3", "Surface2")
    bindTheme(themeButton, "TextColor3", "Muted")
    bindTheme(minimizeButton, "BackgroundColor3", "Surface2")
    bindTheme(minimizeButton, "TextColor3", "Muted")
    bindTheme(mobileOpen, "BackgroundColor3", "Accent")

    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("UIStroke") then
            -- root / search holder stroke updates are handled by direct mapping where needed.
        end
    end

    function window:_connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(self._connections, connection)
        return connection
    end

    local dragging = false
    local dragStart
    local startPos
    local dragInput

    window:_connect(topbar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = root.Position

            window:_connect(input.Changed, function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    window:_connect(topbar.InputChanged, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    window:_connect(UserInputService.InputChanged, function(input)
        if dragging and input == dragInput and not window.DragLocked then
            local delta = input.Position - dragStart
            local camera = workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize or Vector2.new(1920,1080)
            local nextX = startPos.X.Offset + delta.X
            local nextY = startPos.Y.Offset + delta.Y

            -- Keep a useful portion of the top bar reachable so the window
            -- cannot be dragged completely off-screen.
            local horizontalLimit = math.max(80, viewport.X * 0.5 - 80)
            local verticalLimit = math.max(40, viewport.Y * 0.5 - 34)
            nextX = math.clamp(nextX, -horizontalLimit, horizontalLimit)
            nextY = math.clamp(nextY, -verticalLimit, verticalLimit)

            root.Position = UDim2.new(
                startPos.X.Scale,
                nextX,
                startPos.Y.Scale,
                nextY
            )
        end
    end)

    local function updateResponsive()
        local camera = workspace.CurrentCamera
        if not camera then return end

        local viewport = camera.ViewportSize
        local isSmall = viewport.X < 760 or isTouchDevice()
        local targetScale = 1

        if isSmall then
            targetScale = math.clamp((viewport.X - 24) / 760, 0.48, 0.95)
            if viewport.Y < 600 then
                targetScale = math.min(targetScale, math.clamp((viewport.Y - 24) / 500, 0.48, 0.95))
            end
        end

        window.ResponsiveScale = targetScale
        if not window.Minimized then
            scale.Scale = targetScale
        end
    end

    updateResponsive()

    if workspace.CurrentCamera then
        window:_connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), updateResponsive)
    end

    window:_connect(minimizeButton.MouseButton1Click, function()
        window:SetMinimized(not window.Minimized)
    end)

    window:_connect(mobileOpen.MouseButton1Click, function()
        window:SetMinimized(false)
    end)

    local usingLight = false
    window:_connect(themeButton.MouseButton1Click, function()
        usingLight = not usingLight
        window:SetTheme(usingLight and LIGHT_THEME or window._darkTheme)
    end)

    window:_connect(searchBox:GetPropertyChangedSignal("Text"), function()
        window:_applySearch(searchBox.Text)
    end)

    local toggleKey = normalizeKeyCode(options.ToggleKey or Enum.KeyCode.RightShift)
    window:_connect(UserInputService.InputBegan, function(input, processed)
        if processed then return end
        if input.KeyCode == toggleKey then
            window:SetMinimized(not window.Minimized)
        end
    end)

    table.insert(self._windows, window)

    if options.KeySystem and options.KeySystem.Enabled then
        task.defer(function()
            window:_showKeyGate(options.KeySystem)
        end)
    end

    return window
end

function Window:SetTheme(themePatch)
    if self.Destroyed then
        return
    end

    self.Theme = merge(self.Theme, themePatch)

    for _, binding in ipairs(self._themeBindings) do
        local instance = binding.Instance
        if instance and instance.Parent and self.Theme[binding.Key] ~= nil then
            pcall(function()
                tween(instance, 0.18, {
                    [binding.Property] = self.Theme[binding.Key]
                })
            end)
        end
    end
end

function Window:SetMinimized(state)
    if self.Destroyed then return end

    self.Minimized = state and true or false

    if self.Minimized then
        tween(self.Scale, 0.16, {Scale = math.max(0.62, (self.ResponsiveScale or self.Scale.Scale) * 0.96)})
        tween(self.Root, 0.16, {BackgroundTransparency = 1})

        task.delay(0.14, function()
            if self.Destroyed or not self.Minimized then return end
            self.Root.Visible = false
            self.MobileOpen.Visible = true
        end)
    else
        self.MobileOpen.Visible = false
        self.Root.Visible = true
        self.Root.BackgroundTransparency = 0
        tween(self.Scale, 0.18, {Scale = self.ResponsiveScale or 1})
    end
end

function Window:Notify(options)
    options = options or {}

    local theme = self.Theme
    local kind = string.lower(options.Type or "info")

    local accent = theme.Accent
    if kind == "success" then accent = theme.Success end
    if kind == "warning" then accent = theme.Warning end
    if kind == "error" or kind == "danger" then accent = theme.Danger end

    local card = create("Frame", {
        Parent = self.NotificationHost,
        Size = UDim2.new(1,0,0,0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = theme.Surface,
        BorderSizePixel = 0,
        ZIndex = 101,
    }, {
        corner(12),
        stroke(theme.Border, 0.25, 1),
        padding(12, 12, 10, 10)
    })

    local layout = listLayout(card, 4)

    local top = create("Frame", {
        Parent = card,
        BackgroundTransparency = 1,
        Size = UDim2.new(1,0,0,18),
    })

    local dot = create("Frame", {
        Parent = top,
        Size = UDim2.fromOffset(8,8),
        Position = UDim2.fromOffset(0,5),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
    }, {
        corner(999)
    })

    local nTitle = create("TextLabel", {
        Parent = top,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(16,0),
        Size = UDim2.new(1,-42,1,0),
        Text = options.Title or "Notification",
        TextColor3 = theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
    })

    local close = create("TextButton", {
        Parent = top,
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(1,0),
        Position = UDim2.new(1,0,0,0),
        Size = UDim2.fromOffset(18,18),
        BackgroundTransparency = 1,
        Text = "×",
        TextColor3 = theme.Muted,
        TextSize = 17,
        Font = Enum.Font.Gotham,
    })

    local body = textLabel(card, options.Content or options.Text or "", 11, theme.Muted, false)
    body.LayoutOrder = 2

    local progress = create("Frame", {
        Parent = card,
        LayoutOrder = 3,
        Size = UDim2.new(1,0,0,2),
        BackgroundColor3 = theme.Surface2,
        BorderSizePixel = 0,
    }, {
        corner(999)
    })

    local fill = create("Frame", {
        Parent = progress,
        Size = UDim2.fromScale(1,1),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
    }, {
        corner(999)
    })

    local removed = false
    local function remove()
        if removed then return end
        removed = true
        tween(card, 0.16, {BackgroundTransparency = 1})
        task.delay(0.17, function()
            if card then
                card:Destroy()
            end
        end)
    end

    self:_connect(close.MouseButton1Click, remove)

    local duration = options.Duration or 4
    tween(fill, duration, {Size = UDim2.fromScale(0,1)}, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
    task.delay(duration, remove)

    return {
        Close = remove
    }
end

function Window:_showKeyGate(config)
    local overlay = create("Frame", {
        Parent = self.Root,
        Size = UDim2.fromScale(1,1),
        BackgroundColor3 = self.Theme.Background,
        BackgroundTransparency = 0.04,
        BorderSizePixel = 0,
        ZIndex = 80,
    })

    local modal = create("Frame", {
        Parent = overlay,
        AnchorPoint = Vector2.new(0.5,0.5),
        Position = UDim2.fromScale(0.5,0.5),
        Size = UDim2.fromOffset(390, 250),
        BackgroundColor3 = self.Theme.Surface,
        BorderSizePixel = 0,
        ZIndex = 81,
    }, {
        corner(16),
        stroke(self.Theme.Border, 0.18, 1),
        padding(18,18,18,18),
    })

    listLayout(modal, 10)

    local badge = create("TextLabel", {
        Parent = modal,
        Size = UDim2.fromOffset(92,26),
        BackgroundColor3 = self.Theme.Surface2,
        Text = config.Badge or "ACCESS KEY",
        TextColor3 = self.Theme.Accent2,
        TextSize = 10,
        Font = Enum.Font.GothamBold,
        BorderSizePixel = 0,
    }, {
        corner(999)
    })

    local keyTitle = textLabel(modal, config.Title or "Unlock interface", 20, self.Theme.Text, true)
    keyTitle.LayoutOrder = 2

    local keyDesc = textLabel(
        modal,
        config.Description or "Enter your access key to continue.",
        11,
        self.Theme.Muted,
        false
    )
    keyDesc.LayoutOrder = 3

    local inputHolder = create("Frame", {
        Parent = modal,
        LayoutOrder = 4,
        Size = UDim2.new(1,0,0,42),
        BackgroundColor3 = self.Theme.Surface2,
        BorderSizePixel = 0,
    }, {
        corner(10),
        stroke(self.Theme.Border, 0.3, 1),
    })

    local keyInput = create("TextBox", {
        Parent = inputHolder,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12,0),
        Size = UDim2.new(1,-24,1,0),
        PlaceholderText = config.Placeholder or "Enter key...",
        PlaceholderColor3 = self.Theme.Muted,
        Text = "",
        TextColor3 = self.Theme.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
    })

    local status = textLabel(modal, "", 10, self.Theme.Muted, false)
    status.LayoutOrder = 5

    local unlock = button(modal, config.ButtonText or "Unlock", UDim2.new(1,0,0,40), self.Theme.Accent)
    unlock.LayoutOrder = 6

    local tries = 0
    local maxTries = config.MaxAttempts or 8
    local locked = false

    local function localValidate(value)
        if type(config.Keys) == "table" then
            for _, validKey in ipairs(config.Keys) do
                if tostring(validKey) == tostring(value) then
                    return true
                end
            end
        elseif config.Key ~= nil then
            return tostring(config.Key) == tostring(value)
        end
        return false
    end

    local function validate()
        if locked then return end

        local value = keyInput.Text
        if value == "" then
            status.Text = "Enter a key first."
            status.TextColor3 = self.Theme.Warning
            return
        end

        locked = true
        unlock.Text = "Checking..."

        local valid = false
        local message

        if type(config.Validate) == "function" then
            local ok, result, extra = pcall(config.Validate, value)
            valid = ok and result == true
            message = extra
            if not ok then
                message = "Validator failed."
            end
        else
            valid = localValidate(value)
        end

        task.wait(config.ValidationDelay or 0.15)

        if valid then
            self.KeyUnlocked = true
            status.Text = message or "Access granted."
            status.TextColor3 = self.Theme.Success
            unlock.Text = "Unlocked"

            safeCall(config.OnSuccess, value)

            tween(overlay, 0.18, {BackgroundTransparency = 1})
            tween(modal, 0.18, {BackgroundTransparency = 1})

            task.delay(0.2, function()
                overlay:Destroy()
            end)
        else
            tries += 1
            status.Text = message or ("Invalid key. Attempt " .. tries .. "/" .. maxTries)
            status.TextColor3 = self.Theme.Danger
            unlock.Text = config.ButtonText or "Unlock"
            keyInput.Text = ""

            safeCall(config.OnFailure, tries)

            if tries >= maxTries then
                status.Text = "Too many attempts. Try again later."
                unlock.Text = "Locked"
                unlock.Active = false
                unlock.BackgroundColor3 = self.Theme.Surface3

                task.delay(config.LockSeconds or 20, function()
                    if self.Destroyed or not unlock.Parent then return end
                    tries = 0
                    unlock.Active = true
                    unlock.BackgroundColor3 = self.Theme.Accent
                    unlock.Text = config.ButtonText or "Unlock"
                    status.Text = ""
                end)
            end
        end

        locked = false
    end

    self:_connect(unlock.MouseButton1Click, validate)
    self:_connect(keyInput.FocusLost, function(enterPressed)
        if enterPressed then
            validate()
        end
    end)
end

function Window:_applySearch(query)
    query = string.lower(query or "")

    for _, item in ipairs(self._searchItems) do
        if item.Instance and item.Instance.Parent then
            if query == "" then
                item.Instance.Visible = true
            else
                item.Instance.Visible = string.find(string.lower(item.SearchText), query, 1, true) ~= nil
            end
        end
    end
end

function Window:_registerSearch(instance, text)
    table.insert(self._searchItems, {
        Instance = instance,
        SearchText = tostring(text or ""),
    })
end

function Window:_setFlag(flag, value, silent)
    if not flag then
        return
    end

    self.Flags[flag] = value

    local object = self.FlagObjects[flag]
    if object and object._sync and not silent then
        object:_sync(value)
    end
end

function Window:GetFlag(flag)
    return self.Flags[flag]
end

function Window:SetFlag(flag, value)
    self:_setFlag(flag, value, false)
end

function Window:GetConfig()
    local output = {}

    for flag, value in pairs(self.Flags) do
        if typeof(value) == "EnumItem" then
            output[flag] = {
                __type = "EnumItem",
                enum = tostring(value.EnumType),
                name = value.Name,
            }
        elseif typeof(value) == "Color3" then
            output[flag] = {
                __type = "Color3",
                r = math.floor(value.R * 255),
                g = math.floor(value.G * 255),
                b = math.floor(value.B * 255),
            }
        else
            output[flag] = value
        end
    end

    return output
end

function Window:ExportConfig()
    return HttpService:JSONEncode(self:GetConfig())
end

function Window:LoadConfig(config)
    if type(config) == "string" then
        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, config)
        if not ok then
            return false, decoded
        end
        config = decoded
    end

    if type(config) ~= "table" then
        return false, "Config must be a table or JSON string"
    end

    for flag, value in pairs(config) do
        if type(value) == "table" and value.__type == "Color3" then
            value = Color3.fromRGB(value.r or 255, value.g or 255, value.b or 255)
        elseif type(value) == "table" and value.__type == "EnumItem" then
            local enumName = string.match(value.enum or "", "Enum%.(.+)")
            if enumName and Enum[enumName] then
                value = Enum[enumName][value.name]
            end
        end

        self:SetFlag(flag, value)
    end

    return true
end

function Window:CreateTab(options)
    if type(options) == "string" then
        options = {Name = options}
    end
    options = options or {}

    local tab = setmetatable({}, Tab)
    tab.Window = self
    tab.Name = options.Name or "Tab"
    tab.Description = options.Description or ""
    tab._elements = {}

    local tabButton = create("TextButton", {
        Parent = self.TabList,
        AutoButtonColor = false,
        Size = UDim2.new(1,0,0,38),
        BackgroundColor3 = self.Theme.Surface,
        BackgroundTransparency = 1,
        Text = "",
        BorderSizePixel = 0,
    }, {
        corner(10)
    })

    local indicator = create("Frame", {
        Parent = tabButton,
        Position = UDim2.fromOffset(4,10),
        Size = UDim2.fromOffset(3,18),
        BackgroundColor3 = self.Theme.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, {
        corner(999)
    })

    local tabText = create("TextLabel", {
        Parent = tabButton,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14,0),
        Size = UDim2.new(1,-20,1,0),
        Text = tab.Name,
        TextColor3 = self.Theme.Muted,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
    })

    local page = create("ScrollingFrame", {
        Parent = self.Pages,
        Size = UDim2.fromScale(1,1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = self.Theme.Surface3,
        Visible = false,
    }, {
        padding(20,20,4,20)
    })

    local pageLayout = listLayout(page, 12)

    tab.Button = tabButton
    tab.Indicator = indicator
    tab.ButtonText = tabText
    tab.Page = page
    tab.Layout = pageLayout

    self:_registerSearch(tabButton, tab.Name .. " " .. tab.Description)

    self._bindTheme(tabText, "TextColor3", "Muted")
    self._bindTheme(indicator, "BackgroundColor3", "Accent")
    self._bindTheme(page, "ScrollBarImageColor3", "Surface3")

    function tab:_setSelected(selected)
        page.Visible = selected

        if selected then
            tween(tabButton, 0.15, {
                BackgroundTransparency = 0,
                BackgroundColor3 = self.Window.Theme.Surface2
            })
            tween(tabText, 0.15, {TextColor3 = self.Window.Theme.Text})
            tween(indicator, 0.15, {BackgroundTransparency = 0})

            self.Window.PageTitle.Text = self.Name
            self.Window.PageDesc.Text = self.Description ~= "" and self.Description or "Manage " .. self.Name
        else
            tween(tabButton, 0.15, {
                BackgroundTransparency = 1,
                BackgroundColor3 = self.Window.Theme.Surface
            })
            tween(tabText, 0.15, {TextColor3 = self.Window.Theme.Muted})
            tween(indicator, 0.15, {BackgroundTransparency = 1})
        end
    end

    self:_connect(tabButton.MouseButton1Click, function()
        self:SelectTab(tab)
    end)

    table.insert(self.Tabs, tab)

    if #self.Tabs == 1 then
        self:SelectTab(tab)
    end

    return tab
end

function Window:SelectTab(tab)
    if self.CurrentTab == tab then
        return
    end

    for _, other in ipairs(self.Tabs) do
        other:_setSelected(other == tab)
    end

    self.CurrentTab = tab
end

function Window:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true

    for _, connection in ipairs(self._connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    if self.ScreenGui then
        self.ScreenGui:Destroy()
    end

    table.clear(self._connections)
    table.clear(self.Tabs)
    table.clear(self._searchItems)
end

function Tab:_sectionFrame(title, description)
    local section = create("Frame", {
        Parent = self.Page,
        Size = UDim2.new(1,0,0,0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = self.Window.Theme.Surface,
        BorderSizePixel = 0,
    }, {
        corner(14),
        stroke(self.Window.Theme.Border, 0.28, 1),
        padding(14,14,12,14)
    })

    local layout = listLayout(section, 8)

    if title and title ~= "" then
        local label = textLabel(section, title, 13, self.Window.Theme.Text, true)
        label.LayoutOrder = 1
        self.Window._bindTheme(label, "TextColor3", "Text")
    end

    if description and description ~= "" then
        local desc = textLabel(section, description, 10, self.Window.Theme.Muted, false)
        desc.LayoutOrder = 2
        self.Window._bindTheme(desc, "TextColor3", "Muted")
    end

    self.Window._bindTheme(section, "BackgroundColor3", "Surface")
    self.Window:_registerSearch(section, (title or "") .. " " .. (description or ""))

    return section, layout
end

function Tab:CreateSection(options)
    if type(options) == "string" then
        options = {Name = options}
    end
    options = options or {}

    local section, layout = self:_sectionFrame(options.Name or "Section", options.Description)

    local object = {
        Tab = self,
        Window = self.Window,
        Frame = section,
        Layout = layout,
    }

    local methods = {}

    function methods:AddButton(data)
        return self.Tab:_addButton(self.Frame, data)
    end

    function methods:AddToggle(data)
        return self.Tab:_addToggle(self.Frame, data)
    end

    function methods:AddSlider(data)
        return self.Tab:_addSlider(self.Frame, data)
    end

    function methods:AddInput(data)
        return self.Tab:_addInput(self.Frame, data)
    end

    function methods:AddDropdown(data)
        return self.Tab:_addDropdown(self.Frame, data)
    end

    function methods:AddKeybind(data)
        return self.Tab:_addKeybind(self.Frame, data)
    end

    function methods:AddLabel(data)
        return self.Tab:_addLabel(self.Frame, data)
    end

    return setmetatable(object, {__index = methods})
end

function Tab:AddButton(data) return self:_addButton(self.Page, data) end
function Tab:AddToggle(data) return self:_addToggle(self.Page, data) end
function Tab:AddSlider(data) return self:_addSlider(self.Page, data) end
function Tab:AddInput(data) return self:_addInput(self.Page, data) end
function Tab:AddDropdown(data) return self:_addDropdown(self.Page, data) end
function Tab:AddKeybind(data) return self:_addKeybind(self.Page, data) end
function Tab:AddLabel(data) return self:_addLabel(self.Page, data) end

function Tab:_row(parent, height)
    local row = create("Frame", {
        Parent = parent,
        Size = UDim2.new(1,0,0,height or 54),
        BackgroundColor3 = self.Window.Theme.Surface2,
        BorderSizePixel = 0,
    }, {
        corner(11),
        stroke(self.Window.Theme.Border, 0.45, 1),
    })

    self.Window._bindTheme(row, "BackgroundColor3", "Surface2")
    return row
end

function Tab:_titleBlock(row, data, rightWidth)
    local title = create("TextLabel", {
        Parent = row,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12,7),
        Size = UDim2.new(1,-(rightWidth or 90)-24,0,18),
        Text = data.Name or data.Title or "Option",
        TextColor3 = self.Window.Theme.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
    })

    local desc = create("TextLabel", {
        Parent = row,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12,26),
        Size = UDim2.new(1,-(rightWidth or 90)-24,0,16),
        Text = data.Description or "",
        TextColor3 = self.Window.Theme.Muted,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.Gotham,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Visible = (data.Description or "") ~= "",
    })

    self.Window._bindTheme(title, "TextColor3", "Text")
    self.Window._bindTheme(desc, "TextColor3", "Muted")

    self.Window:_registerSearch(row, (data.Name or data.Title or "") .. " " .. (data.Description or ""))

    return title, desc
end

function Tab:_addButton(parent, data)
    data = data or {}

    local row = self:_row(parent, 54)
    self:_titleBlock(row, data, 104)

    local action = button(row, data.ButtonText or "Run", UDim2.fromOffset(86,32), self.Window.Theme.Accent)
    action.AnchorPoint = Vector2.new(1,0.5)
    action.Position = UDim2.new(1,-11,0.5,0)
    action.TextSize = 11

    self.Window._bindTheme(action, "BackgroundColor3", "Accent")

    self.Window:_connect(action.MouseButton1Click, function()
        tween(action, 0.08, {Size = UDim2.fromOffset(82,30)})
        task.delay(0.08, function()
            if action.Parent then
                tween(action, 0.08, {Size = UDim2.fromOffset(86,32)})
            end
        end)

        safeCall(data.Callback)
    end)

    return {
        Instance = row,
        Fire = function()
            safeCall(data.Callback)
        end,
        SetText = function(_, text)
            action.Text = text
        end,
    }
end

function Tab:_addToggle(parent, data)
    data = data or {}

    local flag = data.Flag
    local value = data.Default == true
    if flag and self.Window.Flags[flag] ~= nil then
        value = self.Window.Flags[flag]
    end

    local row = self:_row(parent, 54)
    self:_titleBlock(row, data, 70)

    local switch = create("TextButton", {
        Parent = row,
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(1,0.5),
        Position = UDim2.new(1,-12,0.5,0),
        Size = UDim2.fromOffset(46,26),
        BackgroundColor3 = value and self.Window.Theme.Accent or self.Window.Theme.Surface3,
        Text = "",
        BorderSizePixel = 0,
    }, {
        corner(999)
    })

    local knob = create("Frame", {
        Parent = switch,
        AnchorPoint = Vector2.new(0.5,0.5),
        Position = value and UDim2.new(1,-13,0.5,0) or UDim2.fromOffset(13,13),
        Size = UDim2.fromOffset(18,18),
        BackgroundColor3 = Color3.new(1,1,1),
        BorderSizePixel = 0,
    }, {
        corner(999)
    })

    local object = {}

    local function set(newValue, fire)
        value = newValue == true

        tween(switch, 0.14, {
            BackgroundColor3 = value and self.Window.Theme.Accent or self.Window.Theme.Surface3
        })

        tween(knob, 0.14, {
            Position = value and UDim2.new(1,-13,0.5,0) or UDim2.fromOffset(13,13)
        })

        if flag then
            self.Window.Flags[flag] = value
        end

        if fire ~= false then
            safeCall(data.Callback, value)
        end
    end

    function object:Set(newValue, fireCallback)
        set(newValue, fireCallback ~= false)
    end

    function object:Get()
        return value
    end

    function object:GetDefault()
        return data.Default == true
    end

    function object:_sync(newValue)
        set(newValue, true)
    end

    self.Window:_connect(switch.MouseButton1Click, function()
        set(not value, true)
    end)

    if flag then
        self.Window.Flags[flag] = value
        self.Window.FlagObjects[flag] = object
    end

    return object
end

function Tab:_addSlider(parent, data)
    data = data or {}

    local min = tonumber(data.Min) or 0
    local max = tonumber(data.Max) or 100
    local step = tonumber(data.Increment or data.Step) or 1

    if max <= min then
        max = min + 1
    end

    local flag = data.Flag
    local value = tonumber(data.Default) or min
    if flag and tonumber(self.Window.Flags[flag]) then
        value = tonumber(self.Window.Flags[flag])
    end

    value = math.clamp(value, min, max)

    local row = self:_row(parent, 76)
    self:_titleBlock(row, data, 88)

    local valueText = create("TextLabel", {
        Parent = row,
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1,0),
        Position = UDim2.new(1,-12,0,8),
        Size = UDim2.fromOffset(74,18),
        Text = tostring(value) .. (data.Suffix or ""),
        TextColor3 = self.Window.Theme.Accent2,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextSize = 11,
        Font = Enum.Font.GothamBold,
    })

    local bar = create("TextButton", {
        Parent = row,
        AutoButtonColor = false,
        Position = UDim2.new(0,12,1,-20),
        Size = UDim2.new(1,-24,0,7),
        BackgroundColor3 = self.Window.Theme.Surface3,
        BorderSizePixel = 0,
        Text = "",
    }, {
        corner(999)
    })

    local fill = create("Frame", {
        Parent = bar,
        Size = UDim2.fromScale((value-min)/(max-min), 1),
        BackgroundColor3 = self.Window.Theme.Accent,
        BorderSizePixel = 0,
    }, {
        corner(999)
    })

    local knob = create("Frame", {
        Parent = bar,
        AnchorPoint = Vector2.new(0.5,0.5),
        Position = UDim2.new((value-min)/(max-min),0,0.5,0),
        Size = UDim2.fromOffset(14,14),
        BackgroundColor3 = Color3.new(1,1,1),
        BorderSizePixel = 0,
    }, {
        corner(999),
        stroke(self.Window.Theme.Accent, 0, 2)
    })

    self.Window._bindTheme(valueText, "TextColor3", "Accent2")
    self.Window._bindTheme(bar, "BackgroundColor3", "Surface3")
    self.Window._bindTheme(fill, "BackgroundColor3", "Accent")

    local dragging = false
    local object = {}

    local function roundToStep(number)
        return math.floor((number / step) + 0.5) * step
    end

    local function set(newValue, fire)
        newValue = math.clamp(tonumber(newValue) or min, min, max)
        newValue = roundToStep(newValue)
        newValue = math.clamp(newValue, min, max)

        value = newValue
        local alpha = (value - min) / (max - min)

        tween(fill, 0.08, {Size = UDim2.fromScale(alpha,1)})
        tween(knob, 0.08, {Position = UDim2.new(alpha,0,0.5,0)})

        local displayValue = value
        if step < 1 then
            displayValue = math.floor(value * 1000 + 0.5) / 1000
        end

        valueText.Text = tostring(displayValue) .. (data.Suffix or "")

        if flag then
            self.Window.Flags[flag] = value
        end

        if fire ~= false then
            safeCall(data.Callback, value)
        end
    end

    local function setFromInput(input)
        local x = input.Position.X
        local alpha = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        set(min + (max - min) * alpha, true)
    end

    self.Window:_connect(bar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromInput(input)
        end
    end)

    self.Window:_connect(bar.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    self.Window:_connect(UserInputService.InputChanged, function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            setFromInput(input)
        end
    end)

    function object:Set(newValue, fireCallback)
        set(newValue, fireCallback ~= false)
    end

    function object:Get()
        return value
    end

    function object:GetDefault()
        return tonumber(data.Default) or min
    end

    function object:_sync(newValue)
        set(newValue, true)
    end

    if flag then
        self.Window.Flags[flag] = value
        self.Window.FlagObjects[flag] = object
    end

    return object
end

function Tab:_addInput(parent, data)
    data = data or {}

    local flag = data.Flag
    local value = tostring(data.Default or "")
    if flag and self.Window.Flags[flag] ~= nil then
        value = tostring(self.Window.Flags[flag])
    end

    local row = self:_row(parent, 66)
    self:_titleBlock(row, data, 210)

    local holder = create("Frame", {
        Parent = row,
        AnchorPoint = Vector2.new(1,0.5),
        Position = UDim2.new(1,-12,0.5,0),
        Size = UDim2.fromOffset(190,36),
        BackgroundColor3 = self.Window.Theme.Surface3,
        BorderSizePixel = 0,
    }, {
        corner(9),
        stroke(self.Window.Theme.Border, 0.35, 1)
    })

    local input = create("TextBox", {
        Parent = holder,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10,0),
        Size = UDim2.new(1,-20,1,0),
        Text = value,
        PlaceholderText = data.Placeholder or "Type here...",
        PlaceholderColor3 = self.Window.Theme.Muted,
        TextColor3 = self.Window.Theme.Text,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
    })

    self.Window._bindTheme(holder, "BackgroundColor3", "Surface3")
    self.Window._bindTheme(input, "TextColor3", "Text")
    self.Window._bindTheme(input, "PlaceholderColor3", "Muted")

    local object = {}

    local function commit(text, fire)
        value = tostring(text or "")

        if data.Numeric then
            local number = tonumber(value)
            if number == nil then
                value = tostring(data.Default or "0")
                input.Text = value
                return
            end
        end

        if flag then
            self.Window.Flags[flag] = data.Numeric and tonumber(value) or value
        end

        if fire ~= false then
            safeCall(data.Callback, data.Numeric and tonumber(value) or value)
        end
    end

    self.Window:_connect(input.FocusLost, function(enterPressed)
        if data.CallbackOnEnter and not enterPressed then
            return
        end
        commit(input.Text, true)
    end)

    function object:Set(newValue, fireCallback)
        input.Text = tostring(newValue or "")
        commit(input.Text, fireCallback ~= false)
    end

    function object:Get()
        return data.Numeric and tonumber(input.Text) or input.Text
    end

    function object:GetDefault()
        return data.Numeric and tonumber(data.Default or 0) or tostring(data.Default or "")
    end

    function object:_sync(newValue)
        input.Text = tostring(newValue or "")
        commit(input.Text, true)
    end

    if flag then
        self.Window.Flags[flag] = data.Numeric and tonumber(value) or value
        self.Window.FlagObjects[flag] = object
    end

    return object
end

function Tab:_addDropdown(parent, data)
    data = data or {}

    local values = data.Options or data.Values or {}
    local multi = data.Multi == true
    local flag = data.Flag

    local selected
    if multi then
        selected = {}
        if type(data.Default) == "table" then
            for _, value in ipairs(data.Default) do
                selected[tostring(value)] = true
            end
        end
    else
        selected = data.Default
    end

    if flag and self.Window.Flags[flag] ~= nil then
        selected = self.Window.Flags[flag]
    end

    local holder = create("Frame", {
        Parent = parent,
        Size = UDim2.new(1,0,0,58),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = self.Window.Theme.Surface2,
        BorderSizePixel = 0,
    }, {
        corner(11),
        stroke(self.Window.Theme.Border, 0.45, 1)
    })

    self.Window._bindTheme(holder, "BackgroundColor3", "Surface2")
    self.Window:_registerSearch(holder, (data.Name or "Dropdown") .. " " .. (data.Description or ""))

    local header = create("TextButton", {
        Parent = holder,
        AutoButtonColor = false,
        Size = UDim2.new(1,0,0,58),
        BackgroundTransparency = 1,
        Text = "",
    })

    local title = create("TextLabel", {
        Parent = header,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12,7),
        Size = UDim2.new(1,-220,0,18),
        Text = data.Name or "Dropdown",
        TextColor3 = self.Window.Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
    })

    local desc = create("TextLabel", {
        Parent = header,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12,26),
        Size = UDim2.new(1,-220,0,16),
        Text = data.Description or "",
        TextColor3 = self.Window.Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextSize = 10,
        Font = Enum.Font.Gotham,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Visible = (data.Description or "") ~= "",
    })

    local display = create("TextLabel", {
        Parent = header,
        AnchorPoint = Vector2.new(1,0.5),
        Position = UDim2.new(1,-38,0.5,0),
        Size = UDim2.fromOffset(150,30),
        BackgroundColor3 = self.Window.Theme.Surface3,
        Text = "",
        TextColor3 = self.Window.Theme.Muted,
        TextSize = 10,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Font = Enum.Font.Gotham,
        BorderSizePixel = 0,
    }, {
        corner(8)
    })

    local arrow = create("TextLabel", {
        Parent = header,
        AnchorPoint = Vector2.new(1,0.5),
        Position = UDim2.new(1,-12,0.5,0),
        Size = UDim2.fromOffset(18,18),
        BackgroundTransparency = 1,
        Text = "⌄",
        TextColor3 = self.Window.Theme.Muted,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
    })

    local optionsFrame = create("Frame", {
        Parent = holder,
        Position = UDim2.fromOffset(8,58),
        Size = UDim2.new(1,-16,0,0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Visible = false,
    })
    local optionLayout = listLayout(optionsFrame, 5)
    local optionPadding = padding(0,0,0,8)
    optionPadding.Parent = optionsFrame

    self.Window._bindTheme(title, "TextColor3", "Text")
    self.Window._bindTheme(desc, "TextColor3", "Muted")
    self.Window._bindTheme(display, "BackgroundColor3", "Surface3")
    self.Window._bindTheme(display, "TextColor3", "Muted")
    self.Window._bindTheme(arrow, "TextColor3", "Muted")

    local open = false
    local optionButtons = {}

    local function selectionText()
        if multi then
            local chosen = {}
            for _, option in ipairs(values) do
                if selected[tostring(option)] then
                    table.insert(chosen, tostring(option))
                end
            end

            if #chosen == 0 then
                return data.Placeholder or "None"
            end

            return table.concat(chosen, ", ")
        else
            return selected ~= nil and tostring(selected) or (data.Placeholder or "Select")
        end
    end

    local function fire()
        if flag then
            self.Window.Flags[flag] = selected
        end
        safeCall(data.Callback, selected)
    end

    local function refresh()
        display.Text = selectionText()

        for value, refs in pairs(optionButtons) do
            local active
            if multi then
                active = selected[tostring(value)] == true
            else
                active = tostring(selected) == tostring(value)
            end

            refs.Check.Text = active and "✓" or ""
            refs.Button.BackgroundColor3 = active and self.Window.Theme.Surface3 or self.Window.Theme.Surface
            refs.Label.TextColor3 = active and self.Window.Theme.Text or self.Window.Theme.Muted
        end
    end

    local function rebuild()
        for _, child in ipairs(optionsFrame:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end
        table.clear(optionButtons)

        for _, option in ipairs(values) do
            local value = tostring(option)

            local item = create("TextButton", {
                Parent = optionsFrame,
                AutoButtonColor = false,
                Size = UDim2.new(1,0,0,34),
                BackgroundColor3 = self.Window.Theme.Surface,
                Text = "",
                BorderSizePixel = 0,
            }, {
                corner(8)
            })

            local label = create("TextLabel", {
                Parent = item,
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(10,0),
                Size = UDim2.new(1,-44,1,0),
                Text = value,
                TextColor3 = self.Window.Theme.Muted,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextSize = 11,
                Font = Enum.Font.Gotham,
            })

            local check = create("TextLabel", {
                Parent = item,
                AnchorPoint = Vector2.new(1,0.5),
                Position = UDim2.new(1,-10,0.5,0),
                Size = UDim2.fromOffset(20,20),
                BackgroundTransparency = 1,
                Text = "",
                TextColor3 = self.Window.Theme.Accent2,
                TextSize = 13,
                Font = Enum.Font.GothamBold,
            })

            optionButtons[value] = {
                Button = item,
                Label = label,
                Check = check,
            }

            self.Window:_connect(item.MouseButton1Click, function()
                if multi then
                    selected[value] = not selected[value]
                else
                    selected = value
                    open = false
                    optionsFrame.Visible = false
                    arrow.Text = "⌄"
                end

                refresh()
                fire()
            end)
        end

        refresh()
    end

    self.Window:_connect(header.MouseButton1Click, function()
        open = not open
        optionsFrame.Visible = open
        arrow.Text = open and "⌃" or "⌄"
    end)

    rebuild()

    function object:Set(newValue)
        if multi then
            selected = {}
            if type(newValue) == "table" then
                if #newValue > 0 then
                    for _, item in ipairs(newValue) do
                        selected[tostring(item)] = true
                    end
                else
                    for item, enabled in pairs(newValue) do
                        if enabled then
                            selected[tostring(item)] = true
                        end
                    end
                end
            end
        else
            selected = newValue
        end

        refresh()
        fire()
    end

    function object:Get()
        return selected
    end

    function object:GetDefault()
        return data.Default
    end

    function object:Refresh(newValues)
        values = newValues or {}
        rebuild()
    end

    function object:_sync(newValue)
        self:Set(newValue)
    end

    if flag then
        self.Window.Flags[flag] = selected
        self.Window.FlagObjects[flag] = object
    end

    return object
end

function Tab:_addKeybind(parent, data)
    data = data or {}

    local flag = data.Flag
    local current = normalizeKeyCode(data.Default or Enum.KeyCode.RightShift)
    if flag and self.Window.Flags[flag] ~= nil then
        current = normalizeKeyCode(self.Window.Flags[flag])
    end

    local row = self:_row(parent, 54)
    self:_titleBlock(row, data, 116)

    local keyButton = button(row, current.Name, UDim2.fromOffset(96,32), self.Window.Theme.Surface3)
    keyButton.AnchorPoint = Vector2.new(1,0.5)
    keyButton.Position = UDim2.new(1,-12,0.5,0)
    keyButton.TextColor3 = self.Window.Theme.Muted
    keyButton.TextSize = 10

    self.Window._bindTheme(keyButton, "BackgroundColor3", "Surface3")
    self.Window._bindTheme(keyButton, "TextColor3", "Muted")

    local listening = false
    local object = {}

    self.Window:_connect(keyButton.MouseButton1Click, function()
        listening = true
        keyButton.Text = "Press a key..."
    end)

    self.Window:_connect(UserInputService.InputBegan, function(input, processed)
        if listening then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                current = input.KeyCode
                listening = false
                keyButton.Text = current.Name

                if flag then
                    self.Window.Flags[flag] = current
                end

                safeCall(data.Changed, current)
            end
            return
        end

        if processed then return end
        if input.KeyCode == current then
            safeCall(data.Callback, current)
        end
    end)

    function object:Set(newKey, fireCallback)
        current = normalizeKeyCode(newKey)
        keyButton.Text = current.Name

        if flag then
            self.Window.Flags[flag] = current
        end

        if fireCallback ~= false then
            safeCall(data.Changed, current)
        end
    end

    function object:Get()
        return current
    end

    function object:GetDefault()
        return normalizeKeyCode(data.Default or Enum.KeyCode.RightShift)
    end

    function object:_sync(newValue)
        self:Set(newValue)
    end

    if flag then
        self.Window.Flags[flag] = current
        self.Window.FlagObjects[flag] = object
    end

    return object
end

function Tab:_addLabel(parent, data)
    if type(data) == "string" then
        data = {Text = data}
    end
    data = data or {}

    local frame = create("Frame", {
        Parent = parent,
        Size = UDim2.new(1,0,0,0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = self.Window.Theme.Surface2,
        BorderSizePixel = 0,
    }, {
        corner(11),
        padding(12,12,10,10)
    })

    local label = textLabel(
        frame,
        data.Text or data.Name or "Label",
        data.TextSize or 11,
        data.Color or self.Window.Theme.Muted,
        data.Bold == true
    )

    self.Window._bindTheme(frame, "BackgroundColor3", "Surface2")
    if not data.Color then
        self.Window._bindTheme(label, "TextColor3", "Muted")
    end

    self.Window:_registerSearch(frame, data.Text or data.Name or "")

    local object = {}

    function object:Set(text)
        label.Text = tostring(text or "")
    end

    function object:Get()
        return label.Text
    end

    return object
end


--[[
    ========================================================================
    AstraUI 2.0 enhancements
    ------------------------------------------------------------------------
    This block intentionally extends the 1.x API instead of breaking it.
    Existing scripts using CreateWindow/CreateTab/CreateSection and the
    original controls continue to work, while new controls and runtime APIs
    are added below.
    ========================================================================
]]

local OCEAN_THEME = merge(DEFAULT_THEME, {
    Background = Color3.fromRGB(8, 13, 22),
    Surface = Color3.fromRGB(12, 19, 31),
    Surface2 = Color3.fromRGB(18, 27, 43),
    Surface3 = Color3.fromRGB(25, 37, 57),
    Accent = Color3.fromRGB(65, 124, 255),
    Accent2 = Color3.fromRGB(72, 187, 255),
    Border = Color3.fromRGB(42, 57, 82),
})

local ROSE_THEME = merge(DEFAULT_THEME, {
    Background = Color3.fromRGB(18, 10, 17),
    Surface = Color3.fromRGB(27, 15, 25),
    Surface2 = Color3.fromRGB(38, 21, 35),
    Surface3 = Color3.fromRGB(49, 28, 46),
    Accent = Color3.fromRGB(226, 89, 161),
    Accent2 = Color3.fromRGB(255, 131, 194),
    Border = Color3.fromRGB(69, 42, 63),
})

local GRAPHITE_THEME = merge(DEFAULT_THEME, {
    Background = Color3.fromRGB(10, 11, 14),
    Surface = Color3.fromRGB(16, 18, 22),
    Surface2 = Color3.fromRGB(23, 25, 31),
    Surface3 = Color3.fromRGB(31, 34, 41),
    Accent = Color3.fromRGB(125, 104, 255),
    Accent2 = Color3.fromRGB(169, 155, 255),
    Border = Color3.fromRGB(48, 51, 61),
})

AstraUI.Themes = {
    Dark = DEFAULT_THEME,
    Light = LIGHT_THEME,
    Ocean = OCEAN_THEME,
    Rose = ROSE_THEME,
    Graphite = GRAPHITE_THEME,
}

local function copyTableShallow(source)
    local output = {}
    for key, value in pairs(source or {}) do
        output[key] = value
    end
    return output
end

local function colorToHex(color)
    local r = math.clamp(math.floor(color.R * 255 + 0.5), 0, 255)
    local g = math.clamp(math.floor(color.G * 255 + 0.5), 0, 255)
    local b = math.clamp(math.floor(color.B * 255 + 0.5), 0, 255)
    return string.format("#%02X%02X%02X", r, g, b)
end

local function getPointerPosition(input)
    if input and input.Position then
        return Vector2.new(input.Position.X, input.Position.Y)
    end
    local mouse = UserInputService:GetMouseLocation()
    return Vector2.new(mouse.X, mouse.Y)
end

local function pointInside(guiObject, point)
    if not guiObject or not guiObject.Parent then
        return false
    end
    local p = guiObject.AbsolutePosition
    local s = guiObject.AbsoluteSize
    return point.X >= p.X and point.X <= p.X + s.X
       and point.Y >= p.Y and point.Y <= p.Y + s.Y
end

local function addHover(window, guiObject, normalColorKey, hoverColorKey, amount)
    if not guiObject or not guiObject:IsA("GuiObject") then
        return
    end
    guiObject.Active = true
    local hovering = false
    local function resolveColor()
        local theme = window.Theme
        local base = theme[normalColorKey] or theme.Surface2
        local target = theme[hoverColorKey] or theme.Surface3
        if amount and amount > 0 and not hoverColorKey then
            return base:Lerp(theme.Text, amount)
        end
        return target
    end
    window:_connect(guiObject.MouseEnter, function()
        hovering = true
        tween(guiObject, 0.12, {BackgroundColor3 = resolveColor()})
    end)
    window:_connect(guiObject.MouseLeave, function()
        hovering = false
        local theme = window.Theme
        tween(guiObject, 0.12, {BackgroundColor3 = theme[normalColorKey] or theme.Surface2})
    end)
    return function()
        if hovering then
            guiObject.BackgroundColor3 = resolveColor()
        else
            guiObject.BackgroundColor3 = window.Theme[normalColorKey] or window.Theme.Surface2
        end
    end
end

-- Runtime/window helpers ----------------------------------------------------

function Window:IsVisible()
    return not self.Minimized and self.Root and self.Root.Visible
end

function Window:SetVisible(state)
    if self.Destroyed then return end
    if state then
        self:SetMinimized(false)
    else
        self:SetMinimized(true)
    end
end

function Window:Toggle()
    self:SetMinimized(not self.Minimized)
end

function Window:SetScale(value)
    if self.Destroyed then return end
    value = math.clamp(tonumber(value) or 1, 0.55, 1.35)
    self.ResponsiveScale = value
    if not self.Minimized then
        tween(self.Scale, 0.18, {Scale = value})
    end
end

function Window:Center()
    if self.Destroyed then return end
    tween(self.Root, 0.18, {Position = UDim2.fromScale(0.5, 0.5)})
end

function Window:SetTitle(newTitle, newSubtitle)
    if self.Destroyed then return end
    if self.BrandTitle then
        self.BrandTitle.Text = tostring(newTitle or self.BrandTitle.Text)
    end
    if newSubtitle ~= nil and self.BrandSubtitle then
        self.BrandSubtitle.Text = tostring(newSubtitle)
    end
end

function Window:SetFooter(text, statusColor)
    if self.Destroyed then return end
    if self.FooterText then
        self.FooterText.Text = tostring(text or "")
    end
    if statusColor and self.Footer then
        local dot = self.Footer:FindFirstChildWhichIsA("Frame")
        if dot then
            dot.BackgroundColor3 = statusColor
        end
    end
end

function Window:GetTheme()
    return copyTableShallow(self.Theme)
end

function Window:OnThemeChanged(callback)
    if type(callback) ~= "function" then
        return {Disconnect = function() end}
    end
    local listener = {Callback = callback, Connected = true}
    table.insert(self._themeListeners, listener)
    return {
        Disconnect = function()
            listener.Connected = false
        end
    }
end

-- Override theme switching so old and new controls both repaint cleanly.
function Window:SetTheme(themePatch)
    if self.Destroyed then return end
    self.Theme = merge(self.Theme, themePatch)

    for _, binding in ipairs(self._themeBindings) do
        local instance = binding.Instance
        if instance and instance.Parent and self.Theme[binding.Key] ~= nil then
            pcall(function()
                tween(instance, 0.18, {
                    [binding.Property] = self.Theme[binding.Key]
                })
            end)
        end
    end

    if self.ScreenGui then
        for _, descendant in ipairs(self.ScreenGui:GetDescendants()) do
            if descendant:IsA("UIStroke") then
                if descendant.Thickness >= 1.8 then
                    tween(descendant, 0.18, {Color = self.Theme.Accent})
                else
                    tween(descendant, 0.18, {Color = self.Theme.Border})
                end
            end
        end
    end

    for _, listener in ipairs(self._themeListeners or {}) do
        if listener.Connected then
            safeCall(listener.Callback, self.Theme)
        end
    end
end

function Window:SetThemePreset(name)
    local presetName = tostring(name or "")
    local preset = AstraUI.Themes[presetName]
    if not preset then
        return false, "Unknown theme preset"
    end
    if presetName ~= "Light" then
        self._darkTheme = merge({}, preset)
    end
    self:SetTheme(preset)
    return true
end

function Window:ResetConfig(fireCallbacks)
    for flag, object in pairs(self.FlagObjects) do
        if object and object.GetDefault and object.Set then
            object:Set(object:GetDefault(), fireCallbacks ~= false)
        end
    end
end

-- Modal dialog -------------------------------------------------------------

function Window:Dialog(options)
    options = options or {}
    if self.Destroyed then return nil end

    local overlay = create("TextButton", {
        Parent = self.ScreenGui,
        AutoButtonColor = false,
        Size = UDim2.fromScale(1,1),
        BackgroundColor3 = Color3.new(0,0,0),
        BackgroundTransparency = 0.38,
        Text = "",
        ZIndex = 200,
    })

    local card = create("Frame", {
        Parent = overlay,
        AnchorPoint = Vector2.new(0.5,0.5),
        Position = UDim2.fromScale(0.5,0.5),
        Size = UDim2.fromOffset(options.Width or 420, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = self.Theme.Surface,
        BorderSizePixel = 0,
        ZIndex = 201,
    }, {
        corner(16),
        stroke(self.Theme.Border, 0.12, 1),
        padding(18,18,16,16),
    })
    listLayout(card, 10)

    local title = textLabel(card, options.Title or "Confirm action", 17, self.Theme.Text, true)
    title.LayoutOrder = 1
    local content = textLabel(card, options.Content or options.Text or "", 11, self.Theme.Muted, false)
    content.LayoutOrder = 2

    local buttonsHolder = create("Frame", {
        Parent = card,
        LayoutOrder = 3,
        Size = UDim2.new(1,0,0,38),
        BackgroundTransparency = 1,
        ZIndex = 202,
    })
    local buttonLayout = create("UIListLayout", {
        Parent = buttonsHolder,
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0,8),
    })

    local closed = false
    local handle = {}
    function handle:Close()
        if closed then return end
        closed = true
        tween(overlay, 0.14, {BackgroundTransparency = 1})
        tween(card, 0.14, {BackgroundTransparency = 1})
        task.delay(0.15, function()
            if overlay then overlay:Destroy() end
        end)
    end

    local buttons = options.Buttons
    if type(buttons) ~= "table" or #buttons == 0 then
        buttons = {
            {Text = "Cancel", Style = "neutral"},
            {Text = "Confirm", Style = "accent", Callback = options.Callback},
        }
    end

    for index, data in ipairs(buttons) do
        local style = string.lower(data.Style or (index == #buttons and "accent" or "neutral"))
        local color = self.Theme.Surface3
        if style == "accent" or style == "primary" then color = self.Theme.Accent end
        if style == "danger" then color = self.Theme.Danger end
        if style == "success" then color = self.Theme.Success end

        local btn = button(buttonsHolder, data.Text or "OK", UDim2.fromOffset(data.Width or 96, 36), color)
        btn.LayoutOrder = index
        btn.ZIndex = 203
        self:_connect(btn.MouseButton1Click, function()
            safeCall(data.Callback, handle)
            if data.Close ~= false then
                handle:Close()
            end
        end)
    end

    self:_connect(overlay.MouseButton1Click, function()
        if options.CloseOnBackdrop == false then return end
        handle:Close()
    end)
    -- Prevent clicks on the card from being treated as backdrop intent.
    card.Active = true

    table.insert(self._dialogs, handle)
    return handle
end

-- Better base row/title styling -------------------------------------------

function Tab:_row(parent, height)
    local row = create("Frame", {
        Parent = parent,
        Size = UDim2.new(1,0,0,height or 56),
        BackgroundColor3 = self.Window.Theme.Surface2,
        BorderSizePixel = 0,
        Active = true,
    }, {
        corner(12),
        stroke(self.Window.Theme.Border, 0.48, 1),
    })

    self.Window._bindTheme(row, "BackgroundColor3", "Surface2")
    addHover(self.Window, row, "Surface2", "Surface3")
    return row
end

function Tab:_titleBlock(row, data, rightWidth)
    data = data or {}
    local hasDescription = (data.Description or "") ~= ""
    local titleY = hasDescription and 7 or 0

    local title = create("TextLabel", {
        Parent = row,
        BackgroundTransparency = 1,
        Position = hasDescription and UDim2.fromOffset(13,7) or UDim2.new(0,13,0.5,-9),
        Size = UDim2.new(1,-(rightWidth or 90)-26,0,18),
        Text = data.Name or data.Title or "Option",
        TextColor3 = self.Window.Theme.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
    })

    local desc = create("TextLabel", {
        Parent = row,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(13,27),
        Size = UDim2.new(1,-(rightWidth or 90)-26,0,16),
        Text = data.Description or "",
        TextColor3 = self.Window.Theme.Muted,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.Gotham,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Visible = hasDescription,
    })

    self.Window._bindTheme(title, "TextColor3", "Text")
    self.Window._bindTheme(desc, "TextColor3", "Muted")
    self.Window:_registerSearch(row, (data.Name or data.Title or "") .. " " .. (data.Description or ""))
    return title, desc
end

-- Collapsible modern sections + all controls -------------------------------

function Tab:CreateSection(options)
    if type(options) == "string" then
        options = {Name = options}
    end
    options = options or {}

    local wrapper = create("Frame", {
        Parent = self.Page,
        Size = UDim2.new(1,0,0,0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = self.Window.Theme.Surface,
        BorderSizePixel = 0,
    }, {
        corner(14),
        stroke(self.Window.Theme.Border, 0.28, 1),
        padding(13,13,12,13),
    })
    local wrapperLayout = listLayout(wrapper, 9)

    local header = create("TextButton", {
        Parent = wrapper,
        AutoButtonColor = false,
        LayoutOrder = 1,
        Size = UDim2.new(1,0,0, options.Description and 42 or 26),
        BackgroundTransparency = 1,
        Text = "",
        Active = options.Collapsible == true,
    })

    local title = create("TextLabel", {
        Parent = header,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0,0),
        Size = UDim2.new(1,-34,0,20),
        Text = options.Name or "Section",
        TextColor3 = self.Window.Theme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold,
    })

    local description = create("TextLabel", {
        Parent = header,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0,21),
        Size = UDim2.new(1,-34,0,16),
        Text = options.Description or "",
        TextColor3 = self.Window.Theme.Muted,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.Gotham,
        Visible = (options.Description or "") ~= "",
    })

    local arrow = create("TextLabel", {
        Parent = header,
        AnchorPoint = Vector2.new(1,0.5),
        Position = UDim2.new(1,0,0.5,0),
        Size = UDim2.fromOffset(24,24),
        BackgroundTransparency = 1,
        Text = options.Collapsible and "⌃" or "",
        TextColor3 = self.Window.Theme.Muted,
        TextSize = 15,
        Font = Enum.Font.GothamBold,
    })

    local content = create("Frame", {
        Parent = wrapper,
        LayoutOrder = 2,
        Size = UDim2.new(1,0,0,0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Visible = not (options.Collapsible and options.Collapsed),
    })
    local contentLayout = listLayout(content, 8)

    self.Window._bindTheme(wrapper, "BackgroundColor3", "Surface")
    self.Window._bindTheme(title, "TextColor3", "Text")
    self.Window._bindTheme(description, "TextColor3", "Muted")
    self.Window._bindTheme(arrow, "TextColor3", "Muted")
    self.Window:_registerSearch(wrapper, (options.Name or "") .. " " .. (options.Description or ""))

    local collapsed = options.Collapsible and options.Collapsed == true or false
    local object = {
        Tab = self,
        Window = self.Window,
        Frame = wrapper,
        Content = content,
        Header = header,
        Layout = contentLayout,
    }

    function object:SetCollapsed(state)
        if not options.Collapsible then return end
        collapsed = state == true
        content.Visible = not collapsed
        arrow.Text = collapsed and "⌄" or "⌃"
    end

    function object:Toggle()
        self:SetCollapsed(not collapsed)
    end

    function object:SetTitle(value)
        title.Text = tostring(value or "")
    end

    function object:SetDescription(value)
        description.Text = tostring(value or "")
        description.Visible = description.Text ~= ""
    end

    function object:AddButton(data) return self.Tab:_addButton(self.Content, data) end
    function object:AddToggle(data) return self.Tab:_addToggle(self.Content, data) end
    function object:AddSlider(data) return self.Tab:_addSlider(self.Content, data) end
    function object:AddInput(data) return self.Tab:_addInput(self.Content, data) end
    function object:AddDropdown(data) return self.Tab:_addDropdown(self.Content, data) end
    function object:AddKeybind(data) return self.Tab:_addKeybind(self.Content, data) end
    function object:AddLabel(data) return self.Tab:_addLabel(self.Content, data) end
    function object:AddParagraph(data) return self.Tab:_addParagraph(self.Content, data) end
    function object:AddDivider(data) return self.Tab:_addDivider(self.Content, data) end
    function object:AddProgressBar(data) return self.Tab:_addProgressBar(self.Content, data) end
    function object:AddColorPicker(data) return self.Tab:_addColorPicker(self.Content, data) end

    if options.Collapsible then
        self.Window:_connect(header.MouseButton1Click, function()
            object:Toggle()
        end)
    end

    return object
end

-- Enhanced dropdown --------------------------------------------------------

function Tab:_addDropdown(parent, data)
    data = data or {}
    local values = data.Options or data.Values or {}
    local multi = data.Multi == true
    local flag = data.Flag
    local selected

    if multi then
        selected = {}
        local default = data.Default
        if type(default) == "table" then
            if #default > 0 then
                for _, item in ipairs(default) do selected[tostring(item)] = true end
            else
                for item, enabled in pairs(default) do if enabled then selected[tostring(item)] = true end end
            end
        end
    else
        selected = data.Default
    end
    if flag and self.Window.Flags[flag] ~= nil then
        selected = self.Window.Flags[flag]
    end

    local holder = create("Frame", {
        Parent = parent,
        Size = UDim2.new(1,0,0,0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = self.Window.Theme.Surface2,
        BorderSizePixel = 0,
        Active = true,
    }, {
        corner(12),
        stroke(self.Window.Theme.Border, 0.45, 1),
    })
    local layout = listLayout(holder, 0)

    local header = create("TextButton", {
        Parent = holder,
        AutoButtonColor = false,
        LayoutOrder = 1,
        Size = UDim2.new(1,0,0,58),
        BackgroundTransparency = 1,
        Text = "",
    })
    self:_titleBlock(header, data, 230)

    local display = create("TextLabel", {
        Parent = header,
        AnchorPoint = Vector2.new(1,0.5),
        Position = UDim2.new(1,-40,0.5,0),
        Size = UDim2.fromOffset(166,32),
        BackgroundColor3 = self.Window.Theme.Surface3,
        Text = "",
        TextColor3 = self.Window.Theme.Muted,
        TextSize = 10,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Font = Enum.Font.Gotham,
        BorderSizePixel = 0,
    }, {corner(9)})

    local arrow = create("TextLabel", {
        Parent = header,
        AnchorPoint = Vector2.new(1,0.5),
        Position = UDim2.new(1,-12,0.5,0),
        Size = UDim2.fromOffset(18,18),
        BackgroundTransparency = 1,
        Text = "⌄",
        TextColor3 = self.Window.Theme.Muted,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
    })

    local panel = create("Frame", {
        Parent = holder,
        LayoutOrder = 2,
        Size = UDim2.new(1,0,0,0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Visible = false,
    })

    local panelInner = create("Frame", {
        Parent = panel,
        Position = UDim2.fromOffset(8,0),
        Size = UDim2.new(1,-16,1,-8),
        BackgroundTransparency = 1,
    })

    local object = {}
    local searchable = data.Searchable ~= false and #values >= (data.SearchThreshold or 6)
    local searchHeight = searchable and 36 or 0
    local actionsHeight = multi and 32 or 0
    local topOffset = searchHeight + actionsHeight + ((searchable and multi) and 8 or 0)

    local searchBox
    if searchable then
        local searchHolder = create("Frame", {
            Parent = panelInner,
            Size = UDim2.new(1,0,0,32),
            BackgroundColor3 = self.Window.Theme.Surface3,
            BorderSizePixel = 0,
        }, {corner(8)})
        searchBox = create("TextBox", {
            Parent = searchHolder,
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(10,0),
            Size = UDim2.new(1,-20,1,0),
            PlaceholderText = data.SearchPlaceholder or "Search options...",
            PlaceholderColor3 = self.Window.Theme.Muted,
            Text = "",
            TextColor3 = self.Window.Theme.Text,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClearTextOnFocus = false,
            Font = Enum.Font.Gotham,
        })
        self.Window._bindTheme(searchHolder, "BackgroundColor3", "Surface3")
        self.Window._bindTheme(searchBox, "TextColor3", "Text")
        self.Window._bindTheme(searchBox, "PlaceholderColor3", "Muted")
    end

    if multi then
        local actions = create("Frame", {
            Parent = panelInner,
            Position = UDim2.fromOffset(0, searchHeight + (searchable and 4 or 0)),
            Size = UDim2.new(1,0,0,28),
            BackgroundTransparency = 1,
        })
        local clearButton = button(actions, data.ClearText or "Clear", UDim2.fromOffset(72,28), self.Window.Theme.Surface3)
        clearButton.AnchorPoint = Vector2.new(1,0)
        clearButton.Position = UDim2.new(1,0,0,0)
        clearButton.TextSize = 9
        local allButton = button(actions, data.SelectAllText or "Select all", UDim2.fromOffset(84,28), self.Window.Theme.Surface3)
        allButton.AnchorPoint = Vector2.new(1,0)
        allButton.Position = UDim2.new(1,-80,0,0)
        allButton.TextSize = 9
        self.Window:_connect(clearButton.MouseButton1Click, function()
            table.clear(selected)
            if object and object._refresh then object:_refresh(true) end
        end)
        self.Window:_connect(allButton.MouseButton1Click, function()
            table.clear(selected)
            for _, option in ipairs(values) do selected[tostring(option)] = true end
            if object and object._refresh then object:_refresh(true) end
        end)
    end

    local scroller = create("ScrollingFrame", {
        Parent = panelInner,
        Position = UDim2.fromOffset(0, topOffset),
        Size = UDim2.new(1,0,1,-topOffset),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = self.Window.Theme.Surface3,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
    })
    listLayout(scroller, 5)

    self.Window._bindTheme(holder, "BackgroundColor3", "Surface2")
    self.Window._bindTheme(display, "BackgroundColor3", "Surface3")
    self.Window._bindTheme(display, "TextColor3", "Muted")
    self.Window._bindTheme(arrow, "TextColor3", "Muted")
    self.Window._bindTheme(scroller, "ScrollBarImageColor3", "Surface3")
    self.Window:_registerSearch(holder, (data.Name or "Dropdown") .. " " .. (data.Description or ""))

    local open = false
    local object = {}
    local optionButtons = {}
    local maxVisible = math.max(3, tonumber(data.MaxVisible) or 5)

    local function chosenCount()
        local count = 0
        if multi then
            for _, option in ipairs(values) do
                if selected[tostring(option)] then count += 1 end
            end
        end
        return count
    end

    local function selectionText()
        if multi then
            local chosen = {}
            for _, option in ipairs(values) do
                if selected[tostring(option)] then table.insert(chosen, tostring(option)) end
            end
            if #chosen == 0 then return data.Placeholder or "None selected" end
            if #chosen <= 2 then return table.concat(chosen, ", ") end
            return tostring(#chosen) .. " selected"
        end
        return selected ~= nil and tostring(selected) or (data.Placeholder or "Select")
    end

    local function fire()
        if flag then self.Window.Flags[flag] = selected end
        safeCall(data.Callback, selected)
    end

    local function refresh(fireCallback)
        display.Text = selectionText()
        for value, refs in pairs(optionButtons) do
            local active = multi and selected[tostring(value)] == true or tostring(selected) == tostring(value)
            refs.Check.Text = active and "✓" or ""
            refs.Button.BackgroundColor3 = active and self.Window.Theme.Surface3 or self.Window.Theme.Surface
            refs.Label.TextColor3 = active and self.Window.Theme.Text or self.Window.Theme.Muted
        end
        if fireCallback then fire() end
    end
    object._refresh = refresh

    local function applyFilter(query)
        query = string.lower(query or "")
        for value, refs in pairs(optionButtons) do
            refs.Button.Visible = query == "" or string.find(string.lower(value), query, 1, true) ~= nil
        end
    end

    local function rebuild()
        for _, child in ipairs(scroller:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end
        table.clear(optionButtons)

        for _, option in ipairs(values) do
            local value = tostring(option)
            local item = create("TextButton", {
                Parent = scroller,
                AutoButtonColor = false,
                Size = UDim2.new(1,0,0,34),
                BackgroundColor3 = self.Window.Theme.Surface,
                Text = "",
                BorderSizePixel = 0,
                Active = true,
            }, {corner(8)})
            local label = create("TextLabel", {
                Parent = item,
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(10,0),
                Size = UDim2.new(1,-44,1,0),
                Text = value,
                TextColor3 = self.Window.Theme.Muted,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextSize = 11,
                Font = Enum.Font.Gotham,
            })
            local check = create("TextLabel", {
                Parent = item,
                AnchorPoint = Vector2.new(1,0.5),
                Position = UDim2.new(1,-10,0.5,0),
                Size = UDim2.fromOffset(20,20),
                BackgroundTransparency = 1,
                Text = "",
                TextColor3 = self.Window.Theme.Accent2,
                TextSize = 13,
                Font = Enum.Font.GothamBold,
            })
            optionButtons[value] = {Button=item, Label=label, Check=check}
            self.Window:_connect(item.MouseButton1Click, function()
                if multi then
                    selected[value] = not selected[value]
                else
                    selected = value
                    open = false
                    panel.Visible = false
                    panel.Size = UDim2.new(1,0,0,0)
                    arrow.Text = "⌄"
                end
                refresh(true)
            end)
        end
        refresh(false)
        if searchBox then applyFilter(searchBox.Text) end
    end

    local function setOpen(state)
        open = state == true
        arrow.Text = open and "⌃" or "⌄"
        if open then
            panel.Visible = true
            local visibleRows = math.min(#values, maxVisible)
            local listHeight = math.max(38, visibleRows * 39)
            local desired = topOffset + listHeight + 8
            panel.Size = UDim2.new(1,0,0,0)
            tween(panel, 0.16, {Size = UDim2.new(1,0,0,desired)})
        else
            tween(panel, 0.14, {Size = UDim2.new(1,0,0,0)})
            task.delay(0.14, function()
                if panel.Parent and not open then panel.Visible = false end
            end)
        end
    end

    self.Window:_connect(header.MouseButton1Click, function()
        setOpen(not open)
    end)
    if searchBox then
        self.Window:_connect(searchBox:GetPropertyChangedSignal("Text"), function()
            applyFilter(searchBox.Text)
        end)
    end

    rebuild()

    function object:Set(newValue, fireCallback)
        if multi then
            selected = {}
            if type(newValue) == "table" then
                if #newValue > 0 then
                    for _, item in ipairs(newValue) do selected[tostring(item)] = true end
                else
                    for item, enabled in pairs(newValue) do if enabled then selected[tostring(item)] = true end end
                end
            end
        else
            selected = newValue
        end
        refresh(fireCallback ~= false)
    end

    function object:Get() return selected end
    function object:GetDefault() return data.Default end
    function object:Open() setOpen(true) end
    function object:Close() setOpen(false) end
    function object:Refresh(newValues, preserveSelection)
        values = newValues or {}
        if not preserveSelection then
            if multi then selected = {} else selected = nil end
        end
        rebuild()
        if open then setOpen(true) end
    end
    function object:_sync(newValue) self:Set(newValue, true) end

    if flag then
        self.Window.Flags[flag] = selected
        self.Window.FlagObjects[flag] = object
    end
    return object
end

-- Paragraph ---------------------------------------------------------------

function Tab:_addParagraph(parent, data)
    if type(data) == "string" then data = {Text = data} end
    data = data or {}
    local frame = create("Frame", {
        Parent = parent,
        Size = UDim2.new(1,0,0,0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = self.Window.Theme.Surface2,
        BorderSizePixel = 0,
    }, {
        corner(11),
        padding(13,13,11,11),
    })
    listLayout(frame, 4)

    local title
    if data.Title or data.Name then
        title = textLabel(frame, data.Title or data.Name, 12, self.Window.Theme.Text, true)
        title.LayoutOrder = 1
        self.Window._bindTheme(title, "TextColor3", "Text")
    end
    local body = textLabel(frame, data.Text or data.Content or "", data.TextSize or 10, self.Window.Theme.Muted, false)
    body.LayoutOrder = 2

    self.Window._bindTheme(frame, "BackgroundColor3", "Surface2")
    if not data.Color then self.Window._bindTheme(body, "TextColor3", "Muted") end
    if data.Color then body.TextColor3 = data.Color end
    self.Window:_registerSearch(frame, (data.Title or data.Name or "") .. " " .. (data.Text or data.Content or ""))

    local object = {}
    function object:Set(text) body.Text = tostring(text or "") end
    function object:SetTitle(text) if title then title.Text = tostring(text or "") end end
    function object:Get() return body.Text end
    return object
end

function Tab:_addDivider(parent, data)
    data = type(data) == "string" and {Text=data} or (data or {})
    local holder = create("Frame", {
        Parent = parent,
        Size = UDim2.new(1,0,0, data.Text and 24 or 12),
        BackgroundTransparency = 1,
    })
    local line = create("Frame", {
        Parent = holder,
        AnchorPoint = Vector2.new(0,0.5),
        Position = UDim2.new(0,0,0.5,0),
        Size = UDim2.new(1,0,0,1),
        BackgroundColor3 = self.Window.Theme.Border,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
    })
    self.Window._bindTheme(line, "BackgroundColor3", "Border")
    if data.Text then
        local label = create("TextLabel", {
            Parent = holder,
            AnchorPoint = Vector2.new(0.5,0.5),
            Position = UDim2.fromScale(0.5,0.5),
            Size = UDim2.fromOffset(math.max(80, #tostring(data.Text)*7 + 20), 20),
            BackgroundColor3 = self.Window.Theme.Surface,
            Text = tostring(data.Text),
            TextColor3 = self.Window.Theme.Muted,
            TextSize = 9,
            Font = Enum.Font.GothamMedium,
            BorderSizePixel = 0,
        })
        self.Window._bindTheme(label, "BackgroundColor3", "Surface")
        self.Window._bindTheme(label, "TextColor3", "Muted")
    end
    return {Instance = holder}
end

-- Progress bar -------------------------------------------------------------

function Tab:_addProgressBar(parent, data)
    data = data or {}
    local min = tonumber(data.Min) or 0
    local max = tonumber(data.Max) or 100
    if max <= min then max = min + 1 end
    local value = math.clamp(tonumber(data.Default) or min, min, max)
    local flag = data.Flag

    local row = self:_row(parent, 72)
    self:_titleBlock(row, data, 92)

    local valueText = create("TextLabel", {
        Parent = row,
        AnchorPoint = Vector2.new(1,0),
        Position = UDim2.new(1,-13,0,8),
        Size = UDim2.fromOffset(80,18),
        BackgroundTransparency = 1,
        TextColor3 = self.Window.Theme.Accent2,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextSize = 10,
        Font = Enum.Font.GothamBold,
    })
    local bar = create("Frame", {
        Parent = row,
        Position = UDim2.new(0,13,1,-19),
        Size = UDim2.new(1,-26,0,7),
        BackgroundColor3 = self.Window.Theme.Surface3,
        BorderSizePixel = 0,
    }, {corner(999)})
    local fill = create("Frame", {
        Parent = bar,
        Size = UDim2.fromScale((value-min)/(max-min),1),
        BackgroundColor3 = data.Color or self.Window.Theme.Accent,
        BorderSizePixel = 0,
    }, {corner(999)})

    self.Window._bindTheme(valueText, "TextColor3", "Accent2")
    self.Window._bindTheme(bar, "BackgroundColor3", "Surface3")
    if not data.Color then self.Window._bindTheme(fill, "BackgroundColor3", "Accent") end

    local object = {}
    local function set(newValue, fire)
        value = math.clamp(tonumber(newValue) or min, min, max)
        local alpha = (value-min)/(max-min)
        tween(fill, 0.16, {Size = UDim2.fromScale(alpha,1)})
        local formatted = data.Format and data.Format(value, min, max) or (tostring(math.floor(value*100+0.5)/100) .. (data.Suffix or ""))
        valueText.Text = tostring(formatted)
        if flag then self.Window.Flags[flag] = value end
        if fire ~= false then safeCall(data.Callback, value) end
    end
    function object:Set(v, fire) set(v, fire) end
    function object:Get() return value end
    function object:GetDefault() return tonumber(data.Default) or min end
    function object:_sync(v) set(v, true) end
    set(value, false)
    if flag then self.Window.Flags[flag]=value; self.Window.FlagObjects[flag]=object end
    return object
end

-- HSV color picker ---------------------------------------------------------

function Tab:_addColorPicker(parent, data)
    data = data or {}
    local flag = data.Flag
    local initial = data.Default
    if typeof(initial) ~= "Color3" then initial = self.Window.Theme.Accent end
    if flag and typeof(self.Window.Flags[flag]) == "Color3" then initial = self.Window.Flags[flag] end

    local h, s, v = Color3.toHSV(initial)
    local value = initial
    local open = data.Open == true

    local holder = create("Frame", {
        Parent = parent,
        Size = UDim2.new(1,0,0,0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = self.Window.Theme.Surface2,
        BorderSizePixel = 0,
    }, {corner(12), stroke(self.Window.Theme.Border,0.45,1)})
    listLayout(holder,0)

    local header = create("TextButton", {
        Parent = holder,
        AutoButtonColor = false,
        LayoutOrder = 1,
        Size = UDim2.new(1,0,0,58),
        BackgroundTransparency = 1,
        Text = "",
    })
    self:_titleBlock(header, data, 150)

    local preview = create("Frame", {
        Parent = header,
        AnchorPoint = Vector2.new(1,0.5),
        Position = UDim2.new(1,-38,0.5,0),
        Size = UDim2.fromOffset(94,30),
        BackgroundColor3 = value,
        BorderSizePixel = 0,
    }, {corner(8), stroke(self.Window.Theme.Border,0.2,1)})
    local hex = create("TextLabel", {
        Parent = preview,
        Size = UDim2.fromScale(1,1),
        BackgroundTransparency = 1,
        Text = colorToHex(value),
        TextColor3 = Color3.new(1,1,1),
        TextStrokeTransparency = 0.55,
        TextSize = 9,
        Font = Enum.Font.GothamBold,
    })
    local arrow = create("TextLabel", {
        Parent = header,
        AnchorPoint = Vector2.new(1,0.5),
        Position = UDim2.new(1,-12,0.5,0),
        Size = UDim2.fromOffset(18,18),
        BackgroundTransparency = 1,
        Text = open and "⌃" or "⌄",
        TextColor3 = self.Window.Theme.Muted,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
    })

    local panel = create("Frame", {
        Parent = holder,
        LayoutOrder = 2,
        Size = UDim2.new(1,0,0, open and 154 or 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Visible = open,
    })

    local sv = create("TextButton", {
        Parent = panel,
        AutoButtonColor = false,
        Position = UDim2.fromOffset(10,4),
        Size = UDim2.new(1,-72,0,112),
        BackgroundColor3 = Color3.fromHSV(h,1,1),
        Text = "",
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, {corner(8)})
    local whiteOverlay = create("Frame", {
        Parent = sv,
        Size = UDim2.fromScale(1,1),
        BackgroundColor3 = Color3.new(1,1,1),
        BorderSizePixel = 0,
    })
    create("UIGradient", {
        Parent = whiteOverlay,
        Color = ColorSequence.new(Color3.new(1,1,1), Color3.new(1,1,1)),
        Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,0), NumberSequenceKeypoint.new(1,1)}),
    })
    local blackOverlay = create("Frame", {
        Parent = sv,
        Size = UDim2.fromScale(1,1),
        BackgroundColor3 = Color3.new(0,0,0),
        BorderSizePixel = 0,
    })
    create("UIGradient", {
        Parent = blackOverlay,
        Rotation = 90,
        Color = ColorSequence.new(Color3.new(0,0,0), Color3.new(0,0,0)),
        Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0,1), NumberSequenceKeypoint.new(1,0)}),
    })
    local svCursor = create("Frame", {
        Parent = sv,
        AnchorPoint = Vector2.new(0.5,0.5),
        Position = UDim2.fromScale(s,1-v),
        Size = UDim2.fromOffset(12,12),
        BackgroundColor3 = value,
        BorderSizePixel = 0,
        ZIndex = 4,
    }, {corner(999), stroke(Color3.new(1,1,1),0,2)})

    local hue = create("TextButton", {
        Parent = panel,
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(1,0),
        Position = UDim2.new(1,-10,0,4),
        Size = UDim2.fromOffset(42,112),
        BackgroundColor3 = Color3.new(1,1,1),
        Text = "",
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, {corner(8)})
    create("UIGradient", {
        Parent = hue,
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromHSV(0.00,1,1)),
            ColorSequenceKeypoint.new(0.17, Color3.fromHSV(0.17,1,1)),
            ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33,1,1)),
            ColorSequenceKeypoint.new(0.50, Color3.fromHSV(0.50,1,1)),
            ColorSequenceKeypoint.new(0.67, Color3.fromHSV(0.67,1,1)),
            ColorSequenceKeypoint.new(0.83, Color3.fromHSV(0.83,1,1)),
            ColorSequenceKeypoint.new(1.00, Color3.fromHSV(1.00,1,1)),
        })
    })
    local hueCursor = create("Frame", {
        Parent = hue,
        AnchorPoint = Vector2.new(0.5,0.5),
        Position = UDim2.new(0.5,0,h,0),
        Size = UDim2.new(1,-6,0,4),
        BackgroundColor3 = Color3.new(1,1,1),
        BorderSizePixel = 0,
        ZIndex = 4,
    }, {corner(999)})

    local readout = create("TextLabel", {
        Parent = panel,
        Position = UDim2.fromOffset(10,123),
        Size = UDim2.new(1,-20,0,22),
        BackgroundColor3 = self.Window.Theme.Surface3,
        Text = colorToHex(value),
        TextColor3 = self.Window.Theme.Muted,
        TextSize = 9,
        Font = Enum.Font.GothamMedium,
        BorderSizePixel = 0,
    }, {corner(7)})

    self.Window._bindTheme(holder, "BackgroundColor3", "Surface2")
    self.Window._bindTheme(arrow, "TextColor3", "Muted")
    self.Window._bindTheme(readout, "BackgroundColor3", "Surface3")
    self.Window._bindTheme(readout, "TextColor3", "Muted")
    self.Window:_registerSearch(holder, (data.Name or "Color") .. " " .. (data.Description or ""))

    local object = {}
    local draggingSV = false
    local draggingHue = false

    local function fire()
        value = Color3.fromHSV(h,s,v)
        preview.BackgroundColor3 = value
        svCursor.BackgroundColor3 = value
        hex.Text = colorToHex(value)
        readout.Text = string.format("%s   RGB %d, %d, %d", colorToHex(value), math.floor(value.R*255+0.5), math.floor(value.G*255+0.5), math.floor(value.B*255+0.5))
        sv.BackgroundColor3 = Color3.fromHSV(h,1,1)
        svCursor.Position = UDim2.fromScale(s,1-v)
        hueCursor.Position = UDim2.new(0.5,0,h,0)
        if flag then self.Window.Flags[flag] = value end
        safeCall(data.Callback, value)
    end

    local function updateSV(point)
        local x = math.clamp((point.X - sv.AbsolutePosition.X) / math.max(1,sv.AbsoluteSize.X),0,1)
        local y = math.clamp((point.Y - sv.AbsolutePosition.Y) / math.max(1,sv.AbsoluteSize.Y),0,1)
        s = x
        v = 1-y
        fire()
    end
    local function updateHue(point)
        h = math.clamp((point.Y - hue.AbsolutePosition.Y) / math.max(1,hue.AbsoluteSize.Y),0,1)
        fire()
    end
    local function setOpen(state)
        open = state == true
        arrow.Text = open and "⌃" or "⌄"
        if open then
            panel.Visible = true
            tween(panel,0.16,{Size=UDim2.new(1,0,0,154)})
        else
            tween(panel,0.14,{Size=UDim2.new(1,0,0,0)})
            task.delay(0.14,function() if panel.Parent and not open then panel.Visible=false end end)
        end
    end

    self.Window:_connect(header.MouseButton1Click,function() setOpen(not open) end)
    self.Window:_connect(sv.InputBegan,function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSV=true; updateSV(getPointerPosition(input))
        end
    end)
    self.Window:_connect(hue.InputBegan,function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingHue=true; updateHue(getPointerPosition(input))
        end
    end)
    self.Window:_connect(UserInputService.InputEnded,function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSV=false; draggingHue=false
        end
    end)
    self.Window:_connect(UserInputService.InputChanged,function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            local point = getPointerPosition(input)
            if draggingSV then updateSV(point) end
            if draggingHue then updateHue(point) end
        end
    end)

    function object:Set(newValue, fireCallback)
        if typeof(newValue) ~= "Color3" then return end
        h,s,v = Color3.toHSV(newValue)
        value = newValue
        if fireCallback == false then
            preview.BackgroundColor3=value; svCursor.BackgroundColor3=value; hex.Text=colorToHex(value); readout.Text=colorToHex(value)
            sv.BackgroundColor3=Color3.fromHSV(h,1,1); svCursor.Position=UDim2.fromScale(s,1-v); hueCursor.Position=UDim2.new(0.5,0,h,0)
            if flag then self.Window.Flags[flag]=value end
        else
            fire()
        end
    end
    function object:Get() return value end
    function object:GetDefault() return initial end
    function object:Open() setOpen(true) end
    function object:Close() setOpen(false) end
    function object:_sync(newValue) self:Set(newValue,true) end

    if flag then self.Window.Flags[flag]=value; self.Window.FlagObjects[flag]=object end
    if open then panel.Visible=true end
    object:Set(value,false)
    return object
end

-- Direct tab-level access for new controls ---------------------------------
function Tab:AddParagraph(data) return self:_addParagraph(self.Page, data) end
function Tab:AddDivider(data) return self:_addDivider(self.Page, data) end
function Tab:AddProgressBar(data) return self:_addProgressBar(self.Page, data) end
function Tab:AddColorPicker(data) return self:_addColorPicker(self.Page, data) end

-- Quality-of-life compatibility helpers for existing controls -------------
-- The original API returns control objects. These wrappers are intentionally
-- optional; existing control behavior is unchanged.
function Window:GetFlags()
    return copyTableShallow(self.Flags)
end

function Window:HasFlag(flag)
    return self.Flags[flag] ~= nil
end


function AstraUI:GetEnvironment()
    local hasGetHui = type(gethui) == "function"
    return {
        Executor = hasGetHui,
        GetHui = hasGetHui,
        Touch = UserInputService.TouchEnabled,
        Keyboard = UserInputService.KeyboardEnabled,
        Studio = RunService:IsStudio(),
    }
end

--[[
    ========================================================================
    AstraUI 3.0 - Executor Edition
    ------------------------------------------------------------------------
    Executor-first runtime upgrades layered on top of AstraUI 2.x without
    breaking the existing API. The focus here is lifecycle safety, repeat
    execution, mobile ergonomics, executor capabilities, config persistence,
    better notifications and richer controls.
    ========================================================================
]]

local V3_REGISTRY_KEY = "__ASTRA_UI_V3_REGISTRY__"

local MIDNIGHT_THEME = merge(DEFAULT_THEME, {
    Background = Color3.fromRGB(7, 9, 14),
    Surface = Color3.fromRGB(12, 15, 22),
    Surface2 = Color3.fromRGB(18, 22, 31),
    Surface3 = Color3.fromRGB(26, 31, 43),
    Accent = Color3.fromRGB(118, 92, 255),
    Accent2 = Color3.fromRGB(92, 190, 255),
    Border = Color3.fromRGB(44, 50, 65),
})

local EMERALD_THEME = merge(DEFAULT_THEME, {
    Background = Color3.fromRGB(8, 14, 13),
    Surface = Color3.fromRGB(13, 23, 21),
    Surface2 = Color3.fromRGB(19, 32, 29),
    Surface3 = Color3.fromRGB(26, 43, 38),
    Accent = Color3.fromRGB(57, 199, 146),
    Accent2 = Color3.fromRGB(94, 225, 177),
    Border = Color3.fromRGB(43, 67, 60),
})

AstraUI.Themes.Midnight = MIDNIGHT_THEME
AstraUI.Themes.Emerald = EMERALD_THEME

local function getExecutorGlobal(name)
    local value
    pcall(function()
        value = _G[name]
    end)
    if value ~= nil then
        return value
    end

    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then
            return env[name]
        end
    end

    return nil
end

local function getSharedEnvironment()
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then
            return env
        end
    end
    return _G
end

local function ensureRegistry()
    local env = getSharedEnvironment()
    if type(env[V3_REGISTRY_KEY]) ~= "table" then
        env[V3_REGISTRY_KEY] = {}
    end
    return env[V3_REGISTRY_KEY]
end

local function clampString(text, maxLength)
    text = tostring(text or "")
    maxLength = tonumber(maxLength)
    if maxLength and maxLength > 0 and #text > maxLength then
        return string.sub(text, 1, maxLength)
    end
    return text
end

local function colorDistance(a, b)
    if typeof(a) ~= "Color3" or typeof(b) ~= "Color3" then
        return math.huge
    end
    local dr = a.R - b.R
    local dg = a.G - b.G
    local db = a.B - b.B
    return math.sqrt(dr * dr + dg * dg + db * db)
end

local function enumName(value)
    if typeof(value) == "EnumItem" then
        return value.Name
    end
    return tostring(value)
end

local function sanitizeConfigPath(path)
    path = tostring(path or "AstraUI/config.json")
    path = path:gsub("\\", "/")
    path = path:gsub("%.%./", "")
    path = path:gsub("^/+", "")
    if path == "" then
        path = "AstraUI/config.json"
    end
    if not path:lower():match("%.json$") then
        path ..= ".json"
    end
    return path
end

local function ensureFolderForPath(path)
    local makeFolder = getExecutorGlobal("makefolder")
    local isFolder = getExecutorGlobal("isfolder")
    if type(makeFolder) ~= "function" then
        return
    end

    local current = ""
    local parts = string.split(path, "/")
    for i = 1, math.max(0, #parts - 1) do
        local piece = parts[i]
        if piece ~= "" then
            current = current == "" and piece or (current .. "/" .. piece)
            local exists = false
            if type(isFolder) == "function" then
                local ok, result = pcall(isFolder, current)
                exists = ok and result == true
            end
            if not exists then
                pcall(makeFolder, current)
            end
        end
    end
end

function AstraUI:GetCapabilities()
    local identify = getExecutorGlobal("identifyexecutor") or getExecutorGlobal("getexecutorname")
    local executorName = "Unknown"
    if type(identify) == "function" then
        local ok, result = pcall(identify)
        if ok and result then
            executorName = tostring(result)
        end
    end

    local writeFile = getExecutorGlobal("writefile")
    local readFile = getExecutorGlobal("readfile")
    local isFile = getExecutorGlobal("isfile")
    local deleteFile = getExecutorGlobal("delfile")
    local setClipboard = getExecutorGlobal("setclipboard") or getExecutorGlobal("toclipboard")

    return {
        Executor = type(getExecutorGlobal("gethui")) == "function" or type(getExecutorGlobal("getgenv")) == "function",
        ExecutorName = executorName,
        GetHui = type(getExecutorGlobal("gethui")) == "function",
        FileSystem = type(writeFile) == "function" and type(readFile) == "function",
        IsFile = type(isFile) == "function",
        DeleteFile = type(deleteFile) == "function",
        Clipboard = type(setClipboard) == "function",
        Touch = UserInputService.TouchEnabled,
        Keyboard = UserInputService.KeyboardEnabled,
        Mouse = UserInputService.MouseEnabled,
        Studio = RunService:IsStudio(),
    }
end

function AstraUI:GetEnvironment()
    return self:GetCapabilities()
end

function AstraUI:UnloadAll()
    local copy = {}
    for _, window in ipairs(self._windows) do
        table.insert(copy, window)
    end
    for _, window in ipairs(copy) do
        pcall(function()
            window:Destroy()
        end)
    end
end

-- More precise theme repainting. V2 recolored every thick UIStroke, which can
-- accidentally recolor white color-picker cursors. V3 only maps strokes that
-- actually match a prior theme semantic color.
function Window:SetTheme(themePatch)
    if self.Destroyed then return end

    local oldTheme = self.Theme
    local nextTheme = merge(self.Theme, themePatch)
    self.Theme = nextTheme

    for _, binding in ipairs(self._themeBindings) do
        local instance = binding.Instance
        if instance and instance.Parent and nextTheme[binding.Key] ~= nil then
            pcall(function()
                tween(instance, 0.18, {[binding.Property] = nextTheme[binding.Key]})
            end)
        end
    end

    if self.ScreenGui then
        local semanticKeys = {"Border", "Accent", "Accent2", "Success", "Warning", "Danger"}
        for _, descendant in ipairs(self.ScreenGui:GetDescendants()) do
            if descendant:IsA("UIStroke") then
                local key = descendant:GetAttribute("AstraThemeKey")
                if not key then
                    for _, candidate in ipairs(semanticKeys) do
                        if oldTheme[candidate] and colorDistance(descendant.Color, oldTheme[candidate]) < 0.025 then
                            key = candidate
                            descendant:SetAttribute("AstraThemeKey", candidate)
                            break
                        end
                    end
                end
                if key and nextTheme[key] then
                    tween(descendant, 0.18, {Color = nextTheme[key]})
                end
            end
        end
    end

    for _, listener in ipairs(self._themeListeners or {}) do
        if listener.Connected then
            safeCall(listener.Callback, self.Theme)
        end
    end
end

-- Minimize without forcing a minimum 0.62 scale. On small phones that caused
-- a visible jump right before the window disappeared.
function Window:SetMinimized(state)
    if self.Destroyed then return end
    self.Minimized = state == true

    if self.Minimized then
        local currentScale = self.ResponsiveScale or self.Scale.Scale or 1
        tween(self.Scale, 0.14, {Scale = math.max(0.35, currentScale * 0.96)})
        tween(self.Root, 0.14, {BackgroundTransparency = 1})
        task.delay(0.12, function()
            if self.Destroyed or not self.Minimized then return end
            self.Root.Visible = false
            self.MobileOpen.Visible = true
        end)
    else
        self.MobileOpen.Visible = false
        self.Root.Visible = true
        self.Root.BackgroundTransparency = 0
        tween(self.Scale, 0.17, {Scale = self.ResponsiveScale or 1})
    end
end

function Window:SetDragLocked(state)
    self.DragLocked = state == true
end

function Window:IsDragLocked()
    return self.DragLocked == true
end

function Window:SetSidebarCollapsed(state, instant)
    if self.Destroyed then return end
    state = state == true
    if self.SidebarCollapsed == state then return end
    self.SidebarCollapsed = state

    local sidebarWidth = state and 72 or 210
    local searchHolder = self.SearchBox and self.SearchBox.Parent

    if searchHolder then
        searchHolder.Visible = not state
    end
    if self.BrandTitle then self.BrandTitle.Visible = not state end
    if self.BrandSubtitle then self.BrandSubtitle.Visible = not state end
    if self.FooterText then self.FooterText.Visible = not state end

    if state then
        self.TabList.Position = UDim2.fromOffset(8, 78)
        self.TabList.Size = UDim2.new(1, -16, 1, -132)
    else
        self.TabList.Position = UDim2.fromOffset(10, 126)
        self.TabList.Size = UDim2.new(1, -20, 1, -180)
    end

    for _, tab in ipairs(self.Tabs) do
        if tab.ButtonText then
            tab.ButtonText.TextXAlignment = state and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
            tab.ButtonText.Position = state and UDim2.fromOffset(0,0) or UDim2.fromOffset(14,0)
            tab.ButtonText.Size = state and UDim2.fromScale(1,1) or UDim2.new(1,-20,1,0)
            if state then
                tab.ButtonText.Text = tab.Icon or string.sub(tab.Name or "?", 1, 1)
                tab.ButtonText.TextSize = 15
            else
                tab.ButtonText.Text = tab.Icon and (tab.Icon .. "   " .. tab.Name) or tab.Name
                tab.ButtonText.TextSize = 12
            end
        end
    end

    local duration = instant and 0 or 0.16
    if duration == 0 then
        self.Sidebar.Size = UDim2.new(0, sidebarWidth, 1, 0)
        self.Main.Position = UDim2.fromOffset(sidebarWidth, 0)
        self.Main.Size = UDim2.new(1, -sidebarWidth, 1, 0)
    else
        tween(self.Sidebar, duration, {Size = UDim2.new(0, sidebarWidth, 1, 0)})
        tween(self.Main, duration, {
            Position = UDim2.fromOffset(sidebarWidth, 0),
            Size = UDim2.new(1, -sidebarWidth, 1, 0),
        })
    end
end

function Window:ToggleSidebar()
    self:SetSidebarCollapsed(not self.SidebarCollapsed)
end

function Window:FocusSearch()
    if self.Destroyed or not self.SearchBox then return end
    if self.SidebarCollapsed then
        self:SetSidebarCollapsed(false)
    end
    self.SearchBox:CaptureFocus()
end

function Window:ClearSearch()
    if self.SearchBox then
        self.SearchBox.Text = ""
    end
end

function Window:GetStats()
    local notifications = 0
    for _, item in ipairs(self._activeNotifications or {}) do
        if item and item.Card and item.Card.Parent then
            notifications += 1
        end
    end
    return {
        Version = AstraUI.Version,
        Tabs = #self.Tabs,
        Flags = self:GetFlags(),
        FlagCount = (function()
            local n = 0
            for _ in pairs(self.Flags) do n += 1 end
            return n
        end)(),
        Connections = #self._connections,
        ThemeBindings = #self._themeBindings,
        Notifications = notifications,
        Minimized = self.Minimized,
        SidebarCollapsed = self.SidebarCollapsed == true,
        Parent = self.ScreenGui and self.ScreenGui.Parent and self.ScreenGui.Parent:GetFullName() or "None",
    }
end

function Window:OnUnload(callback)
    if type(callback) ~= "function" then
        return {Disconnect = function() end}
    end
    self._unloadCallbacks = self._unloadCallbacks or {}
    local entry = {Connected = true, Callback = callback}
    table.insert(self._unloadCallbacks, entry)
    return {
        Disconnect = function()
            entry.Connected = false
        end,
    }
end

function Window:CopyConfig()
    local setClipboard = getExecutorGlobal("setclipboard") or getExecutorGlobal("toclipboard")
    if type(setClipboard) ~= "function" then
        return false, "Clipboard API is unavailable in this executor"
    end
    local json = self:ExportConfig()
    local ok, err = pcall(setClipboard, json)
    return ok, ok and json or tostring(err)
end

function Window:SaveConfigFile(path)
    local writeFile = getExecutorGlobal("writefile")
    if type(writeFile) ~= "function" then
        return false, "writefile is unavailable in this executor"
    end
    path = sanitizeConfigPath(path or self.Options.ConfigPath)
    ensureFolderForPath(path)
    local json = self:ExportConfig()
    local ok, err = pcall(writeFile, path, json)
    if ok then
        return true, path
    end
    return false, tostring(err)
end

function Window:LoadConfigFile(path)
    local readFile = getExecutorGlobal("readfile")
    local isFile = getExecutorGlobal("isfile")
    if type(readFile) ~= "function" then
        return false, "readfile is unavailable in this executor"
    end
    path = sanitizeConfigPath(path or self.Options.ConfigPath)
    if type(isFile) == "function" then
        local ok, exists = pcall(isFile, path)
        if ok and not exists then
            return false, "Config file does not exist: " .. path
        end
    end
    local ok, content = pcall(readFile, path)
    if not ok then
        return false, tostring(content)
    end
    local loaded, err = self:LoadConfig(content)
    if not loaded then
        return false, tostring(err)
    end
    return true, path
end

function Window:DeleteConfigFile(path)
    local deleteFile = getExecutorGlobal("delfile")
    local isFile = getExecutorGlobal("isfile")
    if type(deleteFile) ~= "function" then
        return false, "delfile is unavailable in this executor"
    end
    path = sanitizeConfigPath(path or self.Options.ConfigPath)
    if type(isFile) == "function" then
        local ok, exists = pcall(isFile, path)
        if ok and not exists then
            return true, path
        end
    end
    local ok, err = pcall(deleteFile, path)
    return ok, ok and path or tostring(err)
end

-- Notification system ------------------------------------------------------

function Window:ClearNotifications()
    for _, item in ipairs(self._activeNotifications or {}) do
        if item and item.Close then
            pcall(item.Close)
        end
    end
    self._activeNotifications = {}
end

function Window:Notify(options)
    options = options or {}
    if self.Destroyed then return nil end

    self._activeNotifications = self._activeNotifications or {}
    local theme = self.Theme
    local kind = string.lower(tostring(options.Type or "info"))
    local accent = theme.Accent
    if kind == "success" then accent = theme.Success end
    if kind == "warning" then accent = theme.Warning end
    if kind == "error" or kind == "danger" then accent = theme.Danger end

    local card = create("Frame", {
        Parent = self.NotificationHost,
        Size = UDim2.new(1,0,0,0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 101,
    }, {
        corner(13),
        stroke(theme.Border, 0.2, 1),
        padding(12,12,10,10),
    })
    local layout = listLayout(card, 5)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

    local top = create("Frame", {
        Parent = card,
        LayoutOrder = 1,
        Size = UDim2.new(1,0,0,20),
        BackgroundTransparency = 1,
        ZIndex = 102,
    })
    local dot = create("Frame", {
        Parent = top,
        Position = UDim2.fromOffset(0,6),
        Size = UDim2.fromOffset(8,8),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        ZIndex = 103,
    }, {corner(999)})
    local title = create("TextLabel", {
        Parent = top,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(16,0),
        Size = UDim2.new(1,-42,1,0),
        Text = tostring(options.Title or "Notification"),
        TextColor3 = theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        ZIndex = 103,
    })
    local close = create("TextButton", {
        Parent = top,
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(1,0),
        Position = UDim2.new(1,0,0,0),
        Size = UDim2.fromOffset(20,20),
        BackgroundTransparency = 1,
        Text = "×",
        TextColor3 = theme.Muted,
        TextSize = 17,
        Font = Enum.Font.Gotham,
        ZIndex = 103,
    })
    local body = textLabel(card, options.Content or options.Text or "", 11, theme.Muted, false)
    body.LayoutOrder = 2
    body.ZIndex = 102

    local actionHolder
    if type(options.Actions) == "table" and #options.Actions > 0 then
        actionHolder = create("Frame", {
            Parent = card,
            LayoutOrder = 3,
            Size = UDim2.new(1,0,0,30),
            BackgroundTransparency = 1,
            ZIndex = 102,
        })
        create("UIListLayout", {
            Parent = actionHolder,
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0,6),
        })
    end

    local progress = create("Frame", {
        Parent = card,
        LayoutOrder = 4,
        Size = UDim2.new(1,0,0,2),
        BackgroundColor3 = theme.Surface2,
        BorderSizePixel = 0,
        ZIndex = 102,
    }, {corner(999)})
    local fill = create("Frame", {
        Parent = progress,
        Size = UDim2.fromScale(1,1),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        ZIndex = 103,
    }, {corner(999)})

    local closed = false
    local handle = {Card = card}
    local function removeFromList()
        for i = #self._activeNotifications, 1, -1 do
            if self._activeNotifications[i] == handle then
                table.remove(self._activeNotifications, i)
                break
            end
        end
    end
    local function closeNotification()
        if closed then return end
        closed = true
        removeFromList()
        tween(card, 0.14, {BackgroundTransparency = 1})
        task.delay(0.15, function()
            if card and card.Parent then card:Destroy() end
        end)
    end
    handle.Close = closeNotification
    function handle:Update(data)
        data = data or {}
        if data.Title ~= nil then title.Text = tostring(data.Title) end
        if data.Content ~= nil or data.Text ~= nil then body.Text = tostring(data.Content or data.Text or "") end
    end

    self:_connect(close.MouseButton1Click, closeNotification)

    if actionHolder then
        for _, action in ipairs(options.Actions) do
            local actionButton = button(actionHolder, action.Text or "Action", UDim2.fromOffset(action.Width or 74, 28), action.Primary and accent or theme.Surface3)
            actionButton.TextSize = 10
            actionButton.ZIndex = 103
            self:_connect(actionButton.MouseButton1Click, function()
                safeCall(action.Callback, handle)
                if action.Close ~= false then
                    closeNotification()
                end
            end)
        end
    end

    table.insert(self._activeNotifications, handle)
    local maxNotifications = tonumber(self.Options.MaxNotifications) or 5
    while #self._activeNotifications > maxNotifications do
        local oldest = self._activeNotifications[1]
        if oldest and oldest.Close then oldest.Close() else table.remove(self._activeNotifications, 1) end
    end

    tween(card, 0.16, {BackgroundTransparency = 0})
    local duration = tonumber(options.Duration)
    if duration == nil then duration = 4 end
    if duration > 0 then
        tween(fill, duration, {Size = UDim2.fromScale(0,1)}, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
        task.delay(duration, closeNotification)
    else
        fill.Visible = false
    end

    return handle
end

-- Richer tab metadata ------------------------------------------------------

local _CreateTabV2 = Window.CreateTab
function Window:CreateTab(options)
    local rawOptions = type(options) == "table" and options or {Name = tostring(options)}
    local tab = _CreateTabV2(self, options)
    tab.Icon = rawOptions.Icon and tostring(rawOptions.Icon) or nil

    if tab.Icon and tab.ButtonText then
        tab.ButtonText.Text = tab.Icon .. "   " .. tab.Name
    end

    function tab:SetBadge(text, tone)
        if self._badge and self._badge.Parent then
            self._badge:Destroy()
            self._badge = nil
        end
        if text == nil or tostring(text) == "" then return end

        local color = self.Window.Theme.Accent
        tone = string.lower(tostring(tone or "accent"))
        if tone == "success" then color = self.Window.Theme.Success end
        if tone == "warning" then color = self.Window.Theme.Warning end
        if tone == "danger" or tone == "error" then color = self.Window.Theme.Danger end

        local badge = create("TextLabel", {
            Parent = self.Button,
            AnchorPoint = Vector2.new(1,0.5),
            Position = UDim2.new(1,-10,0.5,0),
            Size = UDim2.fromOffset(28,18),
            BackgroundColor3 = color,
            Text = tostring(text),
            TextColor3 = Color3.new(1,1,1),
            TextSize = 9,
            Font = Enum.Font.GothamBold,
            BorderSizePixel = 0,
        }, {corner(999)})
        self._badge = badge
    end

    if self.SidebarCollapsed and tab.ButtonText then
        tab.ButtonText.Text = tab.Icon or string.sub(tab.Name or "?",1,1)
        tab.ButtonText.TextXAlignment = Enum.TextXAlignment.Center
        tab.ButtonText.Position = UDim2.fromOffset(0,0)
        tab.ButtonText.Size = UDim2.fromScale(1,1)
    end

    return tab
end

-- Modern button with disabled/loading/confirm support ---------------------

function Tab:_addButton(parent, data)
    data = data or {}
    local row = self:_row(parent, 56)
    self:_titleBlock(row, data, 122)

    local normalText = tostring(data.ButtonText or "Run")
    local action = button(row, normalText, UDim2.fromOffset(96,34), self.Window.Theme.Accent)
    action.AnchorPoint = Vector2.new(1,0.5)
    action.Position = UDim2.new(1,-11,0.5,0)
    action.TextSize = 11
    self.Window._bindTheme(action, "BackgroundColor3", "Accent")

    local object = {}
    local disabled = data.Disabled == true
    local loading = false

    local function repaint()
        action.Active = not disabled and not loading
        action.TextTransparency = disabled and 0.35 or 0
        if disabled then
            action.BackgroundColor3 = self.Window.Theme.Surface3
        else
            action.BackgroundColor3 = self.Window.Theme.Accent
        end
    end

    local function runCallback()
        if disabled or loading then return end

        local function execute()
            if data.Async == true then
                loading = true
                action.Text = tostring(data.LoadingText or "Working...")
                repaint()
                task.spawn(function()
                    local ok, err = pcall(data.Callback)
                    loading = false
                    if action and action.Parent then
                        action.Text = normalText
                        repaint()
                    end
                    if not ok then
                        warn("[AstraUI] Async button callback error:", err)
                        if self.Window and not self.Window.Destroyed then
                            self.Window:Notify({Title = "Action failed", Content = tostring(err), Type = "error", Duration = 5})
                        end
                    end
                end)
            else
                safeCall(data.Callback)
            end
        end

        if data.Confirm then
            local confirmData = type(data.Confirm) == "table" and data.Confirm or {}
            self.Window:Dialog({
                Title = confirmData.Title or "Confirm action",
                Content = confirmData.Content or confirmData.Text or "Are you sure you want to continue?",
                Buttons = {
                    {Text = confirmData.CancelText or "Cancel", Style = "neutral"},
                    {Text = confirmData.ConfirmText or "Continue", Style = confirmData.Style or "accent", Callback = execute},
                },
            })
        else
            execute()
        end
    end

    self.Window:_connect(action.MouseButton1Click, function()
        if disabled or loading then return end
        tween(action, 0.07, {Size = UDim2.fromOffset(92,32)})
        task.delay(0.07, function()
            if action and action.Parent then tween(action, 0.08, {Size = UDim2.fromOffset(96,34)}) end
        end)
        runCallback()
    end)

    function object:Fire() runCallback() end
    function object:SetText(text)
        normalText = tostring(text or "")
        if not loading then action.Text = normalText end
    end
    function object:SetDisabled(state)
        disabled = state == true
        repaint()
    end
    function object:IsDisabled() return disabled end
    function object:SetLoading(state, text)
        loading = state == true
        action.Text = loading and tostring(text or data.LoadingText or "Working...") or normalText
        repaint()
    end
    function object:IsLoading() return loading end
    function object:GetDefault() return data.Disabled == true end
    object.Instance = row

    repaint()
    return object
end

-- Status card --------------------------------------------------------------

function Tab:_addStatus(parent, data)
    if type(data) == "string" then data = {Name = data} end
    data = data or {}

    local row = self:_row(parent, 54)
    self:_titleBlock(row, data, 150)

    local pill = create("TextLabel", {
        Parent = row,
        AnchorPoint = Vector2.new(1,0.5),
        Position = UDim2.new(1,-12,0.5,0),
        Size = UDim2.fromOffset(128,28),
        BackgroundColor3 = self.Window.Theme.Surface3,
        Text = tostring(data.Value or data.Text or "Ready"),
        TextColor3 = self.Window.Theme.Muted,
        TextSize = 10,
        Font = Enum.Font.GothamBold,
        BorderSizePixel = 0,
    }, {corner(999)})
    self.Window._bindTheme(pill, "BackgroundColor3", "Surface3")

    local object = {}
    local tone = data.Tone or "muted"
    local value = tostring(data.Value or data.Text or "Ready")

    local function applyTone(newTone)
        tone = string.lower(tostring(newTone or "muted"))
        local color = self.Window.Theme.Muted
        if tone == "accent" then color = self.Window.Theme.Accent2 end
        if tone == "success" then color = self.Window.Theme.Success end
        if tone == "warning" then color = self.Window.Theme.Warning end
        if tone == "danger" or tone == "error" then color = self.Window.Theme.Danger end
        pill.TextColor3 = color
    end

    function object:Set(newValue, newTone)
        value = tostring(newValue or "")
        pill.Text = value
        if newTone ~= nil then applyTone(newTone) end
    end
    function object:Get() return value end
    function object:SetTone(newTone) applyTone(newTone) end
    function object:GetTone() return tone end

    applyTone(tone)
    return object
end

-- Text area ---------------------------------------------------------------

function Tab:_addTextArea(parent, data)
    data = data or {}
    local flag = data.Flag
    local initial = clampString(data.Default or "", data.MaxLength)
    if flag and self.Window.Flags[flag] ~= nil then
        initial = clampString(self.Window.Flags[flag], data.MaxLength)
    end
    local value = initial

    local holder = create("Frame", {
        Parent = parent,
        Size = UDim2.new(1,0,0,126),
        BackgroundColor3 = self.Window.Theme.Surface2,
        BorderSizePixel = 0,
    }, {corner(11), stroke(self.Window.Theme.Border,0.45,1)})
    self.Window._bindTheme(holder,"BackgroundColor3","Surface2")

    local title = create("TextLabel", {
        Parent = holder,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12,7),
        Size = UDim2.new(1,-24,0,18),
        Text = data.Name or data.Title or "Text area",
        TextColor3 = self.Window.Theme.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamMedium,
    })
    local desc = create("TextLabel", {
        Parent = holder,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12,26),
        Size = UDim2.new(1,-24,0,16),
        Text = data.Description or "",
        TextColor3 = self.Window.Theme.Muted,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.Gotham,
        Visible = (data.Description or "") ~= "",
    })
    self.Window._bindTheme(title,"TextColor3","Text")
    self.Window._bindTheme(desc,"TextColor3","Muted")

    local inputHolder = create("Frame", {
        Parent = holder,
        Position = UDim2.fromOffset(10,48),
        Size = UDim2.new(1,-20,0,66),
        BackgroundColor3 = self.Window.Theme.Surface3,
        BorderSizePixel = 0,
    }, {corner(9), stroke(self.Window.Theme.Border,0.35,1)})
    self.Window._bindTheme(inputHolder,"BackgroundColor3","Surface3")

    local input = create("TextBox", {
        Parent = inputHolder,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10,7),
        Size = UDim2.new(1,-20,1,-14),
        Text = value,
        PlaceholderText = data.Placeholder or "Type here...",
        PlaceholderColor3 = self.Window.Theme.Muted,
        TextColor3 = self.Window.Theme.Text,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        MultiLine = true,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
    })
    self.Window._bindTheme(input,"TextColor3","Text")
    self.Window._bindTheme(input,"PlaceholderColor3","Muted")
    self.Window:_registerSearch(holder,(data.Name or data.Title or "") .. " " .. (data.Description or ""))

    local object = {}
    local function commit(fireCallback)
        local nextValue = clampString(input.Text, data.MaxLength)
        if nextValue ~= input.Text then input.Text = nextValue end
        value = nextValue
        if flag then self.Window.Flags[flag] = value end
        if fireCallback ~= false then safeCall(data.Callback, value) end
    end

    self.Window:_connect(input:GetPropertyChangedSignal("Text"), function()
        if data.Live == true then commit(true) end
    end)
    self.Window:_connect(input.FocusLost, function()
        if data.Live ~= true then commit(true) end
    end)

    function object:Set(newValue, fireCallback)
        input.Text = clampString(newValue, data.MaxLength)
        commit(fireCallback ~= false)
    end
    function object:Get() return value end
    function object:GetDefault() return initial end
    function object:Focus() input:CaptureFocus() end
    function object:_sync(newValue) self:Set(newValue,true) end

    if flag then
        self.Window.Flags[flag] = value
        self.Window.FlagObjects[flag] = object
    end
    return object
end

-- Attach V3 controls to both tabs and sections -----------------------------

local _CreateSectionV2 = Tab.CreateSection
function Tab:CreateSection(options)
    local section = _CreateSectionV2(self, options)
    function section:AddStatus(data)
        return self.Tab:_addStatus(self.Content or self.Frame, data)
    end
    function section:AddTextArea(data)
        return self.Tab:_addTextArea(self.Content or self.Frame, data)
    end
    return section
end

function Tab:AddStatus(data) return self:_addStatus(self.Page, data) end
function Tab:AddTextArea(data) return self:_addTextArea(self.Page, data) end

-- Executor-first window bootstrap -----------------------------------------

local _CreateWindowV2 = AstraUI.CreateWindow
function AstraUI:CreateWindow(options)
    options = options or {}

    if options.ReplaceExisting == nil then options.ReplaceExisting = true end
    if options.DisplayOrder == nil then options.DisplayOrder = 1000 end
    if options.IgnoreGuiInset == nil then options.IgnoreGuiInset = true end
    if options.AutoCollapseSidebar == nil then options.AutoCollapseSidebar = true end
    if options.MaxNotifications == nil then options.MaxNotifications = 5 end
    if options.ConfigPath == nil then options.ConfigPath = "AstraUI/" .. tostring(options.Name or "AstraUI") .. ".json" end

    local registry = ensureRegistry()
    local registryKey = tostring(options.RegistryKey or options.Name or "AstraUI")
    local previous = registry[registryKey]
    if options.ReplaceExisting ~= false and previous and previous.Destroy and not previous.Destroyed then
        pcall(function() previous:Destroy() end)
    end

    local window = _CreateWindowV2(self, options)
    window._registryKey = registryKey
    window._unloadCallbacks = {}
    window._activeNotifications = {}
    window.SidebarCollapsed = false
    window.DragLocked = false
    registry[registryKey] = window

    if window.ScreenGui then
        window.ScreenGui.IgnoreGuiInset = options.IgnoreGuiInset ~= false
        window.ScreenGui.DisplayOrder = options.DisplayOrder or 1000
    end

    -- Make the floating reopen button feel like an executor launcher.
    if window.MobileOpen then
        window.MobileOpen.Size = UDim2.fromOffset(56,56)
        window.MobileOpen.Text = options.IconText or "A"
        window.MobileOpen.Font = Enum.Font.GothamBold
        window.MobileOpen.TextSize = 18
    end

    -- Sidebar button in the top bar.
    local sidebarButton = button(window.Topbar, "☰", UDim2.fromOffset(36,36), window.Theme.Surface2)
    sidebarButton.AnchorPoint = Vector2.new(1,0)
    sidebarButton.Position = UDim2.new(1,-112,0,14)
    sidebarButton.TextColor3 = window.Theme.Muted
    sidebarButton.TextSize = 14
    window._bindTheme(sidebarButton,"BackgroundColor3","Surface2")
    window._bindTheme(sidebarButton,"TextColor3","Muted")
    window.SidebarButton = sidebarButton
    window:_connect(sidebarButton.MouseButton1Click, function()
        window:ToggleSidebar()
    end)

    -- Optional hard close button. Re-running the script recreates the window.
    if options.ShowCloseButton ~= false then
        local closeButton = button(window.Topbar, "×", UDim2.fromOffset(36,36), window.Theme.Surface2)
        closeButton.AnchorPoint = Vector2.new(1,0)
        closeButton.Position = UDim2.new(1,-156,0,14)
        closeButton.TextColor3 = window.Theme.Muted
        closeButton.TextSize = 18
        window._bindTheme(closeButton,"BackgroundColor3","Surface2")
        window._bindTheme(closeButton,"TextColor3","Muted")
        window.CloseButton = closeButton
        window:_connect(closeButton.MouseButton1Click, function()
            if options.ConfirmClose == true then
                window:Dialog({
                    Title = "Unload AstraUI?",
                    Content = "This closes the interface and disconnects its tracked input connections.",
                    Buttons = {
                        {Text = "Cancel", Style = "neutral"},
                        {Text = "Unload", Style = "danger", Callback = function() window:Destroy() end},
                    },
                })
            else
                window:Destroy()
            end
        end)
    end

    if window.PageTitle then
        window.PageTitle.Size = UDim2.new(1,-250,0,24)
    end
    if window.PageDesc then
        window.PageDesc.Size = UDim2.new(1,-250,0,18)
    end

    -- Ctrl+K or Ctrl+F opens Astra search. Escape clears search focus.
    window:_connect(UserInputService.InputBegan, function(input, processed)
        if processed or window.Destroyed then return end
        local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
        if ctrl and (input.KeyCode == Enum.KeyCode.K or input.KeyCode == Enum.KeyCode.F) then
            window:FocusSearch()
        elseif input.KeyCode == Enum.KeyCode.Escape and window.SearchBox and window.SearchBox:IsFocused() then
            window.SearchBox:ReleaseFocus()
            window:ClearSearch()
        end
    end)

    -- Auto-collapse on narrow viewports, while keeping user control on larger
    -- screens. The original V2 scale system still handles overall fit.
    local function updateV3Responsive()
        if window.Destroyed then return end
        local camera = workspace.CurrentCamera
        if not camera then return end
        local viewport = camera.ViewportSize
        if options.AutoCollapseSidebar ~= false then
            window:SetSidebarCollapsed(viewport.X < 620, true)
        end
    end

    local cameraViewportConnection
    local function bindCamera()
        if cameraViewportConnection then
            pcall(function() cameraViewportConnection:Disconnect() end)
            cameraViewportConnection = nil
        end
        local camera = workspace.CurrentCamera
        if camera then
            cameraViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateV3Responsive)
            table.insert(window._connections, cameraViewportConnection)
        end
        updateV3Responsive()
    end
    bindCamera()
    window:_connect(workspace:GetPropertyChangedSignal("CurrentCamera"), bindCamera)

    -- Draggable floating launcher. A tiny movement does not suppress click;
    -- this is intentionally simple and touch-friendly.
    if window.MobileOpen then
        local launcherDragging = false
        local launcherStart
        local launcherPosition
        local launcherInput
        window:_connect(window.MobileOpen.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                launcherDragging = true
                launcherStart = input.Position
                launcherPosition = window.MobileOpen.Position
            end
        end)
        window:_connect(window.MobileOpen.InputChanged, function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                launcherInput = input
            end
        end)
        window:_connect(UserInputService.InputChanged, function(input)
            if not launcherDragging or input ~= launcherInput then return end
            local delta = input.Position - launcherStart
            window.MobileOpen.Position = UDim2.new(
                launcherPosition.X.Scale,
                launcherPosition.X.Offset + delta.X,
                launcherPosition.Y.Scale,
                launcherPosition.Y.Offset + delta.Y
            )
        end)
        window:_connect(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                launcherDragging = false
            end
        end)
    end

    return window
end

-- Respect V3 drag lock by filtering the root's movement after V2 has already
-- wired drag input. We keep this guard lightweight: when locked, snap back to
-- the last known allowed position if movement occurs.
local _CenterV2 = Window.Center
function Window:Center()
    if self.Destroyed then return end
    _CenterV2(self)
end

-- Cleanup registry and user unload callbacks.
local _DestroyWindowV2 = Window.Destroy
function Window:Destroy()
    if self.Destroyed then return end

    for _, entry in ipairs(self._unloadCallbacks or {}) do
        if entry.Connected then
            safeCall(entry.Callback, self)
        end
    end

    local registry = ensureRegistry()
    if self._registryKey and registry[self._registryKey] == self then
        registry[self._registryKey] = nil
    end

    _DestroyWindowV2(self)
end

-- Version is assigned last so anything querying the module after load sees V3.
AstraUI.Version = "3.0.0-executor"

-- ============================================================================
-- AstraUI V3.1 visual polish layer
-- Focus: reliable icons, denser layout, cleaner controls and topbar UX.
-- This layer intentionally preserves the V3 public API.
-- ============================================================================

local V31_VERSION = "3.1.0-executor"

local function v31IsAssetIcon(value)
    if type(value) == "number" then
        return "rbxassetid://" .. tostring(value)
    end
    if type(value) ~= "string" then return nil end
    if string.match(value, "^rbxassetid://%d+$") then return value end
    if string.match(value, "^%d+$") then return "rbxassetid://" .. value end
    return nil
end

local function v31IsAsciiShort(value)
    if type(value) ~= "string" or #value == 0 or #value > 3 then return false end
    return string.match(value, "^[%w%p%s]+$") ~= nil
end

local function v31Line(parent, position, size, color, rotation, zindex)
    local line = create("Frame", {
        Parent = parent,
        Position = position,
        Size = size,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Rotation = rotation or 0,
        ZIndex = zindex or ((parent.ZIndex or 1) + 1),
    }, {corner(999)})
    return line
end

local function v31IconHost(parent, position, size, zindex)
    return create("Frame", {
        Name = "AstraV31Icon",
        Parent = parent,
        Position = position,
        Size = size or UDim2.fromOffset(18,18),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = zindex or ((parent.ZIndex or 1) + 1),
    })
end

local function v31ClearIcon(parent)
    if not parent then return end
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == "AstraV31Icon" then
            child:Destroy()
        end
    end
end

local function v31DrawButtonIcon(window, target, kind)
    if not target then return end
    target.Text = ""
    target.TextTransparency = 1
    v31ClearIcon(target)

    local host = v31IconHost(target, UDim2.new(0.5,-9,0.5,-9), UDim2.fromOffset(18,18), target.ZIndex + 2)
    local muted = window.Theme.Muted

    if kind == "menu" then
        for _, y in ipairs({4, 8.5, 13}) do
            local line = v31Line(host, UDim2.fromOffset(2,y), UDim2.fromOffset(14,1.5), muted, 0, host.ZIndex + 1)
            window._bindTheme(line, "BackgroundColor3", "Muted")
        end
    elseif kind == "minimize" then
        local line = v31Line(host, UDim2.fromOffset(3,8.5), UDim2.fromOffset(12,1.5), muted, 0, host.ZIndex + 1)
        window._bindTheme(line, "BackgroundColor3", "Muted")
    elseif kind == "close" then
        local a = v31Line(host, UDim2.fromOffset(3,8.25), UDim2.fromOffset(12,1.5), muted, 45, host.ZIndex + 1)
        local b = v31Line(host, UDim2.fromOffset(3,8.25), UDim2.fromOffset(12,1.5), muted, -45, host.ZIndex + 1)
        window._bindTheme(a, "BackgroundColor3", "Muted")
        window._bindTheme(b, "BackgroundColor3", "Muted")
    elseif kind == "theme" then
        local ring = create("Frame", {
            Parent = host,
            Position = UDim2.fromOffset(2,2),
            Size = UDim2.fromOffset(14,14),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = host.ZIndex + 1,
        }, {corner(999)})
        local ringStroke = stroke(muted, 0, 1.5)
        ringStroke.Parent = ring
        window._bindTheme(ringStroke, "Color", "Muted")

        local half = create("Frame", {
            Parent = host,
            Position = UDim2.fromOffset(3.5,3.5),
            Size = UDim2.fromOffset(5.5,11),
            BackgroundColor3 = muted,
            BorderSizePixel = 0,
            ZIndex = host.ZIndex + 2,
        }, {corner(999)})
        window._bindTheme(half, "BackgroundColor3", "Muted")
    end

    if not target:GetAttribute("AstraV31Hover") then
        target:SetAttribute("AstraV31Hover", true)
        window:_connect(target.MouseEnter, function()
            if window.Destroyed then return end
            tween(target, 0.12, {BackgroundColor3 = window.Theme.Surface3})
        end)
        window:_connect(target.MouseLeave, function()
            if window.Destroyed then return end
            tween(target, 0.12, {BackgroundColor3 = window.Theme.Surface2})
        end)
    end
end

local function v31DrawSearchIcon(window)
    if not window.SearchBox or not window.SearchBox.Parent then return end
    local holder = window.SearchBox.Parent

    for _, child in ipairs(holder:GetChildren()) do
        if child:IsA("TextLabel") and child ~= window.SearchBox then
            if child.Text == "⌕" or child.Name == "SearchIcon" then
                child.Text = ""
                child.Visible = false
            end
        end
    end

    local old = holder:FindFirstChild("AstraV31SearchIcon")
    if old then old:Destroy() end

    local host = create("Frame", {
        Name = "AstraV31SearchIcon",
        Parent = holder,
        Position = UDim2.fromOffset(12,11),
        Size = UDim2.fromOffset(16,16),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = holder.ZIndex + 2,
    })
    local circle = create("Frame", {
        Parent = host,
        Position = UDim2.fromOffset(1,1),
        Size = UDim2.fromOffset(9,9),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = host.ZIndex + 1,
    }, {corner(999)})
    local s = stroke(window.Theme.Muted, 0, 1.4)
    s.Parent = circle
    window._bindTheme(s, "Color", "Muted")
    local handle = v31Line(host, UDim2.fromOffset(9,10), UDim2.fromOffset(6,1.4), window.Theme.Muted, 45, host.ZIndex + 1)
    window._bindTheme(handle, "BackgroundColor3", "Muted")

    window.SearchBox.Position = UDim2.fromOffset(36,0)
    window.SearchBox.Size = UDim2.new(1,-46,1,0)
end

local function v31DrawTabVector(window, host, alias)
    alias = string.lower(tostring(alias or ""))
    local muted = window.Theme.Muted
    local z = host.ZIndex + 1

    local function bind(frame)
        window._bindTheme(frame, "BackgroundColor3", "Muted")
        return frame
    end

    if alias == "home" then
        bind(v31Line(host, UDim2.fromOffset(3,6), UDim2.fromOffset(8,1.5), muted, -40, z))
        bind(v31Line(host, UDim2.fromOffset(8,6), UDim2.fromOffset(8,1.5), muted, 40, z))
        local body = create("Frame", {Parent=host, Position=UDim2.fromOffset(5,8), Size=UDim2.fromOffset(9,7), BackgroundTransparency=1, BorderSizePixel=0, ZIndex=z})
        local st = stroke(muted,0,1.3); st.Parent=body; window._bindTheme(st,"Color","Muted")
        return true
    elseif alias == "automation" or alias == "controls" or alias == "settings" then
        for i, y in ipairs({4,9,14}) do
            bind(v31Line(host, UDim2.fromOffset(2,y), UDim2.fromOffset(14,1.2), muted, 0, z))
            local x = (i == 1 and 5) or (i == 2 and 11) or 7
            local dot = create("Frame", {Parent=host, Position=UDim2.fromOffset(x,y-2), Size=UDim2.fromOffset(4,4), BackgroundColor3=muted, BorderSizePixel=0, ZIndex=z+1}, {corner(999)})
            window._bindTheme(dot,"BackgroundColor3","Muted")
        end
        return true
    elseif alias == "visuals" or alias == "visual" then
        local eye = create("Frame", {Parent=host, Position=UDim2.fromOffset(2,5), Size=UDim2.fromOffset(14,8), BackgroundTransparency=1, BorderSizePixel=0, ZIndex=z}, {corner(999)})
        local st = stroke(muted,0,1.3); st.Parent=eye; window._bindTheme(st,"Color","Muted")
        local pupil = create("Frame", {Parent=host, Position=UDim2.fromOffset(7,7), Size=UDim2.fromOffset(4,4), BackgroundColor3=muted, BorderSizePixel=0, ZIndex=z+1}, {corner(999)})
        window._bindTheme(pupil,"BackgroundColor3","Muted")
        return true
    elseif alias == "info" then
        local ring = create("Frame", {Parent=host, Position=UDim2.fromOffset(2,2), Size=UDim2.fromOffset(14,14), BackgroundTransparency=1, BorderSizePixel=0, ZIndex=z}, {corner(999)})
        local st = stroke(muted,0,1.3); st.Parent=ring; window._bindTheme(st,"Color","Muted")
        local text = create("TextLabel", {Parent=host, Size=UDim2.fromScale(1,1), BackgroundTransparency=1, Text="i", TextColor3=muted, TextSize=12, Font=Enum.Font.GothamBold, ZIndex=z+1})
        window._bindTheme(text,"TextColor3","Muted")
        return true
    elseif alias == "config" then
        local doc = create("Frame", {Parent=host, Position=UDim2.fromOffset(3,2), Size=UDim2.fromOffset(12,14), BackgroundTransparency=1, BorderSizePixel=0, ZIndex=z}, {corner(3)})
        local st = stroke(muted,0,1.2); st.Parent=doc; window._bindTheme(st,"Color","Muted")
        for _, y in ipairs({6,9,12}) do bind(v31Line(host,UDim2.fromOffset(6,y),UDim2.fromOffset(6,1),muted,0,z+1)) end
        return true
    elseif alias == "runtime" then
        bind(v31Line(host, UDim2.fromOffset(2,9), UDim2.fromOffset(4,1.3), muted, 0, z))
        bind(v31Line(host, UDim2.fromOffset(5,8), UDim2.fromOffset(5,1.3), muted, -55, z))
        bind(v31Line(host, UDim2.fromOffset(8,7), UDim2.fromOffset(5,1.3), muted, 55, z))
        bind(v31Line(host, UDim2.fromOffset(12,9), UDim2.fromOffset(4,1.3), muted, 0, z))
        return true
    end
    return false
end

local function v31BuildTabIcon(window, tab, iconSpec)
    if not tab.Button then return end
    if tab._v31IconFrame and tab._v31IconFrame.Parent then tab._v31IconFrame:Destroy() end

    local host = v31IconHost(tab.Button, UDim2.fromOffset(13,10), UDim2.fromOffset(18,18), tab.Button.ZIndex + 2)
    tab._v31IconFrame = host
    local asset = v31IsAssetIcon(iconSpec)

    if asset then
        local img = create("ImageLabel", {
            Parent = host,
            Size = UDim2.fromScale(1,1),
            BackgroundTransparency = 1,
            Image = asset,
            ImageColor3 = window.Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = host.ZIndex + 1,
        })
        window._bindTheme(img,"ImageColor3","Muted")
    elseif not v31DrawTabVector(window, host, iconSpec) then
        local fallback = v31IsAsciiShort(iconSpec) and tostring(iconSpec) or string.sub(tab.Name or "?",1,1)
        local txt = create("TextLabel", {
            Parent = host,
            Size = UDim2.fromScale(1,1),
            BackgroundTransparency = 1,
            Text = fallback,
            TextColor3 = window.Theme.Muted,
            TextSize = 11,
            Font = Enum.Font.GothamBold,
            ZIndex = host.ZIndex + 1,
        })
        window._bindTheme(txt,"TextColor3","Muted")
    end
end

-- Less boxed-in rows. The surface distinction does most of the separation.
function Tab:_row(parent, height)
    local border = stroke(self.Window.Theme.Border, 0.64, 1)
    self.Window._bindTheme(border, "Color", "Border")
    local row = create("Frame", {
        Parent = parent,
        Size = UDim2.new(1,0,0,height or 54),
        BackgroundColor3 = self.Window.Theme.Surface2,
        BorderSizePixel = 0,
        Active = true,
    }, {corner(11), border})
    self.Window._bindTheme(row, "BackgroundColor3", "Surface2")
    addHover(self.Window, row, "Surface2", "Surface3")
    return row
end

-- Premium compact toggle with subtle active ring.
function Tab:_addToggle(parent, data)
    data = data or {}
    local flag = data.Flag
    local value = data.Default == true
    if flag and self.Window.Flags[flag] ~= nil then value = self.Window.Flags[flag] == true end

    local row = self:_row(parent, 52)
    self:_titleBlock(row, data, 66)

    local switchStroke = stroke(self.Window.Theme.Accent, value and 0.40 or 1, 1)
    local switch = create("TextButton", {
        Parent = row,
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(1,0.5),
        Position = UDim2.new(1,-12,0.5,0),
        Size = UDim2.fromOffset(42,24),
        BackgroundColor3 = value and self.Window.Theme.Accent or self.Window.Theme.Surface3,
        Text = "",
        BorderSizePixel = 0,
    }, {corner(999), switchStroke})

    local knob = create("Frame", {
        Parent = switch,
        AnchorPoint = Vector2.new(0.5,0.5),
        Position = value and UDim2.new(1,-12,0.5,0) or UDim2.fromOffset(12,12),
        Size = UDim2.fromOffset(16,16),
        BackgroundColor3 = Color3.new(1,1,1),
        BorderSizePixel = 0,
    }, {corner(999)})

    self.Window._bindTheme(switchStroke,"Color","Accent")
    local object = {}
    local disabled = data.Disabled == true

    local function paint(animated)
        local duration = animated and 0.15 or 0
        local bg = value and self.Window.Theme.Accent or self.Window.Theme.Surface3
        if duration > 0 then
            tween(switch,duration,{BackgroundColor3=bg})
            tween(knob,duration,{Position=value and UDim2.new(1,-12,0.5,0) or UDim2.fromOffset(12,12)})
            tween(switchStroke,duration,{Transparency=value and 0.40 or 1})
        else
            switch.BackgroundColor3 = bg
            knob.Position = value and UDim2.new(1,-12,0.5,0) or UDim2.fromOffset(12,12)
            switchStroke.Transparency = value and 0.40 or 1
        end
        switch.Active = not disabled
        switch.BackgroundTransparency = disabled and 0.35 or 0
        knob.BackgroundTransparency = disabled and 0.35 or 0
    end

    local function set(newValue, fireCallback)
        value = newValue == true
        paint(true)
        if flag then self.Window.Flags[flag] = value end
        if fireCallback ~= false then safeCall(data.Callback,value) end
    end

    self.Window:_connect(switch.MouseButton1Click,function()
        if disabled then return end
        set(not value,true)
    end)
    self.Window:_connect(switch.MouseEnter,function()
        if disabled then return end
        tween(knob,0.10,{Size=UDim2.fromOffset(17,17)})
    end)
    self.Window:_connect(switch.MouseLeave,function()
        tween(knob,0.10,{Size=UDim2.fromOffset(16,16)})
    end)

    function object:Set(newValue, fireCallback) set(newValue,fireCallback ~= false) end
    function object:Get() return value end
    function object:GetDefault() return data.Default == true end
    function object:SetDisabled(state) disabled = state == true; paint(false) end
    function object:IsDisabled() return disabled end
    function object:_sync(newValue) set(newValue,true) end
    object.Instance = row

    if flag then self.Window.Flags[flag]=value; self.Window.FlagObjects[flag]=object end
    paint(false)
    return object
end

-- Denser slider: smaller thumb, cleaner value and touch-safe interaction.
function Tab:_addSlider(parent, data)
    data = data or {}
    local min = tonumber(data.Min) or 0
    local max = tonumber(data.Max) or 100
    local step = tonumber(data.Increment or data.Step) or 1
    if max <= min then max = min + 1 end

    local flag = data.Flag
    local defaultValue = tonumber(data.Default) or min
    local value = defaultValue
    if flag and tonumber(self.Window.Flags[flag]) then value = tonumber(self.Window.Flags[flag]) end
    value = math.clamp(value,min,max)

    local row = self:_row(parent, 70)
    self:_titleBlock(row,data,92)

    local valueText = create("TextLabel", {
        Parent=row,
        BackgroundTransparency=1,
        AnchorPoint=Vector2.new(1,0),
        Position=UDim2.new(1,-13,0,8),
        Size=UDim2.fromOffset(76,18),
        Text="",
        TextColor3=self.Window.Theme.Accent2,
        TextXAlignment=Enum.TextXAlignment.Right,
        TextSize=10,
        Font=Enum.Font.GothamBold,
    })
    self.Window._bindTheme(valueText,"TextColor3","Accent2")

    local bar = create("TextButton", {
        Parent=row,
        AutoButtonColor=false,
        Position=UDim2.new(0,13,1,-17),
        Size=UDim2.new(1,-26,0,6),
        BackgroundColor3=self.Window.Theme.Surface3,
        BorderSizePixel=0,
        Text="",
    }, {corner(999)})
    self.Window._bindTheme(bar,"BackgroundColor3","Surface3")

    local fill = create("Frame", {Parent=bar, Size=UDim2.fromScale(0,1), BackgroundColor3=self.Window.Theme.Accent, BorderSizePixel=0}, {corner(999)})
    self.Window._bindTheme(fill,"BackgroundColor3","Accent")
    local knobStroke = stroke(self.Window.Theme.Accent,0.10,1.5)
    local knob = create("Frame", {
        Parent=bar,
        AnchorPoint=Vector2.new(0.5,0.5),
        Position=UDim2.fromScale(0,0.5),
        Size=UDim2.fromOffset(12,12),
        BackgroundColor3=Color3.new(1,1,1),
        BorderSizePixel=0,
    }, {corner(999),knobStroke})
    self.Window._bindTheme(knobStroke,"Color","Accent")

    local object = {Instance=row}
    local dragging=false
    local disabled=data.Disabled == true

    local function roundToStep(number)
        return math.floor((number / step) + 0.5) * step
    end
    local function display(number)
        if step < 1 then number = math.floor(number*1000+0.5)/1000 end
        return tostring(number) .. tostring(data.Suffix or "")
    end
    local function paint(animated)
        local alpha=(value-min)/(max-min)
        valueText.Text=display(value)
        if animated then
            tween(fill,0.07,{Size=UDim2.fromScale(alpha,1)})
            tween(knob,0.07,{Position=UDim2.new(alpha,0,0.5,0)})
        else
            fill.Size=UDim2.fromScale(alpha,1)
            knob.Position=UDim2.new(alpha,0,0.5,0)
        end
        bar.Active=not disabled
        row.BackgroundTransparency=disabled and 0.25 or 0
    end
    local function set(newValue, fireCallback)
        newValue=math.clamp(tonumber(newValue) or min,min,max)
        newValue=math.clamp(roundToStep(newValue),min,max)
        value=newValue
        paint(true)
        if flag then self.Window.Flags[flag]=value end
        if fireCallback ~= false then safeCall(data.Callback,value) end
    end
    local function fromInput(input)
        if disabled or bar.AbsoluteSize.X <= 0 then return end
        local alpha=math.clamp((input.Position.X-bar.AbsolutePosition.X)/bar.AbsoluteSize.X,0,1)
        set(min+(max-min)*alpha,true)
    end

    self.Window:_connect(bar.InputBegan,function(input)
        if disabled then return end
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true
            tween(knob,0.08,{Size=UDim2.fromOffset(14,14)})
            fromInput(input)
        end
    end)
    self.Window:_connect(bar.InputEnded,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=false
            tween(knob,0.08,{Size=UDim2.fromOffset(12,12)})
        end
    end)
    self.Window:_connect(UserInputService.InputChanged,function(input)
        if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then fromInput(input) end
    end)

    function object:Set(newValue,fireCallback) set(newValue,fireCallback ~= false) end
    function object:Get() return value end
    function object:GetDefault() return defaultValue end
    function object:SetDisabled(state) disabled=state==true; if disabled then dragging=false end; paint(false) end
    function object:IsDisabled() return disabled end
    function object:_sync(newValue) set(newValue,true) end

    if flag then self.Window.Flags[flag]=value; self.Window.FlagObjects[flag]=object end
    paint(false)
    return object
end

-- Adaptive action buttons: short labels no longer create oversized purple blocks.
function Tab:_addButton(parent, data)
    data = data or {}
    local normalText = tostring(data.ButtonText or "Run")
    local measured = math.clamp(42 + (#normalText * 6.2), 72, 116)
    local actionWidth = tonumber(data.ButtonWidth) or measured

    local row = self:_row(parent, 54)
    self:_titleBlock(row,data,actionWidth + 26)
    local action = button(row,normalText,UDim2.fromOffset(actionWidth,32),self.Window.Theme.Accent)
    action.AnchorPoint=Vector2.new(1,0.5)
    action.Position=UDim2.new(1,-11,0.5,0)
    action.TextSize=10
    self.Window._bindTheme(action,"BackgroundColor3","Accent")

    local object={Instance=row}
    local disabled=data.Disabled==true
    local loading=false

    local function repaint()
        action.Active=not disabled and not loading
        action.TextTransparency=disabled and 0.45 or 0
        action.BackgroundColor3=disabled and self.Window.Theme.Surface3 or self.Window.Theme.Accent
    end
    local function execute()
        if disabled or loading then return end
        if data.Async==true then
            loading=true; action.Text=tostring(data.LoadingText or "Working..."); repaint()
            task.spawn(function()
                local ok,err=pcall(data.Callback)
                loading=false
                if action and action.Parent then action.Text=normalText; repaint() end
                if not ok and self.Window and not self.Window.Destroyed then
                    warn("[AstraUI] Async button callback error:",err)
                    self.Window:Notify({Title="Action failed",Content=tostring(err),Type="error",Duration=5})
                end
            end)
        else
            safeCall(data.Callback)
        end
    end
    local function run()
        if disabled or loading then return end
        if data.Confirm then
            local confirmData=type(data.Confirm)=="table" and data.Confirm or {}
            self.Window:Dialog({
                Title=confirmData.Title or "Confirm action",
                Content=confirmData.Content or confirmData.Text or "Are you sure you want to continue?",
                Buttons={
                    {Text=confirmData.CancelText or "Cancel",Style="neutral"},
                    {Text=confirmData.ConfirmText or "Continue",Style=confirmData.Style or "accent",Callback=execute},
                },
            })
        else execute() end
    end

    self.Window:_connect(action.MouseButton1Click,function()
        if disabled or loading then return end
        tween(action,0.06,{Size=UDim2.fromOffset(math.max(64,actionWidth-4),30)})
        task.delay(0.06,function() if action and action.Parent then tween(action,0.08,{Size=UDim2.fromOffset(actionWidth,32)}) end end)
        run()
    end)
    self.Window:_connect(action.MouseEnter,function()
        if not disabled and not loading then tween(action,0.10,{Size=UDim2.fromOffset(actionWidth+2,33)}) end
    end)
    self.Window:_connect(action.MouseLeave,function()
        if action and action.Parent and not loading then tween(action,0.10,{Size=UDim2.fromOffset(actionWidth,32)}) end
    end)

    function object:Fire() run() end
    function object:SetText(text)
        normalText=tostring(text or "")
        if not loading then action.Text=normalText end
    end
    function object:SetDisabled(state) disabled=state==true; repaint() end
    function object:IsDisabled() return disabled end
    function object:SetLoading(state,text) loading=state==true; action.Text=loading and tostring(text or data.LoadingText or "Working...") or normalText; repaint() end
    function object:IsLoading() return loading end
    function object:GetDefault() return data.Disabled==true end
    repaint()
    return object
end

-- Section polish without changing section API.
local _AstraV31CreateSection = Tab.CreateSection
function Tab:CreateSection(options)
    local section = _AstraV31CreateSection(self, options)
    if section and section.Frame then
        for _, child in ipairs(section.Frame:GetChildren()) do
            if child:IsA("UIPadding") then
                child.PaddingLeft = UDim.new(0,11)
                child.PaddingRight = UDim.new(0,11)
                child.PaddingTop = UDim.new(0,10)
                child.PaddingBottom = UDim.new(0,11)
            elseif child:IsA("UIStroke") then
                child.Transparency = 0.52
            end
        end
    end
    if section and section.Layout then section.Layout.Padding = UDim.new(0,6) end
    if section and section.Header then
        local hasDescription = false
        if type(options)=="table" then hasDescription=(options.Description or "")~="" end
        section.Header.Size = UDim2.new(1,0,0,hasDescription and 38 or 24)
    end
    return section
end

-- Icon-safe tab wrapper. Use aliases such as "home", "automation", "visuals",
-- "settings", "info", "config", "runtime", or a Roblox image asset id.
local _AstraV31CreateTab = Window.CreateTab
function Window:CreateTab(options)
    local raw = type(options)=="table" and options or {Name=tostring(options)}
    local forwarded = {}
    for key,value in pairs(raw) do forwarded[key]=value end
    local iconSpec = forwarded.Icon
    forwarded.Icon = nil -- prevent unsupported unicode glyphs from becoming tofu squares

    local tab = _AstraV31CreateTab(self,forwarded)
    tab.Icon = iconSpec
    v31BuildTabIcon(self,tab,iconSpec)

    local oldSetBadge = tab.SetBadge
    if oldSetBadge then
        function tab:SetBadge(text,tone)
            oldSetBadge(self,text,tone)
            if self._badge then self._badge.Visible = not self.Window.SidebarCollapsed end
        end
    end

    function tab:_v31ApplyLayout(collapsed)
        if not self.ButtonText then return end
        if collapsed then
            self.ButtonText.Text = ""
            self.ButtonText.Position = UDim2.fromOffset(0,0)
            self.ButtonText.Size = UDim2.fromScale(1,1)
            if self._v31IconFrame then self._v31IconFrame.Position = UDim2.new(0.5,-9,0,10) end
            if self._badge then self._badge.Visible=false end
        else
            self.ButtonText.Text = self.Name
            self.ButtonText.TextXAlignment = Enum.TextXAlignment.Left
            self.ButtonText.Position = UDim2.fromOffset(42,0)
            self.ButtonText.Size = UDim2.new(1,-54,1,0)
            if self._v31IconFrame then self._v31IconFrame.Position = UDim2.fromOffset(14,10) end
            if self._badge then self._badge.Visible=true end
        end
    end
    tab:_v31ApplyLayout(self.SidebarCollapsed)
    return tab
end

local _AstraV31SetSidebarCollapsed = Window.SetSidebarCollapsed
function Window:SetSidebarCollapsed(state, instant)
    _AstraV31SetSidebarCollapsed(self,state,instant)
    for _, tab in ipairs(self.Tabs or {}) do
        if tab._v31ApplyLayout then tab:_v31ApplyLayout(self.SidebarCollapsed) end
    end
end

-- Executor window polish. Defaults to three topbar actions; hard close remains opt-in.
local _AstraV31CreateWindow = AstraUI.CreateWindow
function AstraUI:CreateWindow(options)
    options = options or {}
    if options.ShowCloseButton == nil then options.ShowCloseButton = false end

    local window = _AstraV31CreateWindow(self,options)

    if window.ThemeButton and window.ThemeButton.Parent then
        local topActions = window.ThemeButton.Parent
        topActions.Size = UDim2.fromOffset(76,34)
        topActions.Position = UDim2.new(1,-14,0,14)
        window.ThemeButton.Size = UDim2.fromOffset(34,34)
        window.ThemeButton.Position = UDim2.fromOffset(0,0)
        window.MinimizeButton.Size = UDim2.fromOffset(34,34)
        window.MinimizeButton.Position = UDim2.fromOffset(42,0)
    end
    if window.SidebarButton then
        window.SidebarButton.Size = UDim2.fromOffset(34,34)
        window.SidebarButton.Position = UDim2.new(1,-100,0,14)
    end
    if window.CloseButton then
        window.CloseButton.Size = UDim2.fromOffset(34,34)
        window.CloseButton.Position = UDim2.new(1,-142,0,14)
    end

    v31DrawButtonIcon(window,window.SidebarButton,"menu")
    v31DrawButtonIcon(window,window.ThemeButton,"theme")
    v31DrawButtonIcon(window,window.MinimizeButton,"minimize")
    v31DrawButtonIcon(window,window.CloseButton,"close")
    v31DrawSearchIcon(window)

    if window.PageTitle then window.PageTitle.Size=UDim2.new(1,-170,0,24) end
    if window.PageDesc then window.PageDesc.Size=UDim2.new(1,-170,0,18) end

    return window
end

AstraUI.Version = V31_VERSION


-- ============================================================================
-- AstraUI V3.2 responsive/design refinement layer
-- Focus only: visual hierarchy, mobile ergonomics, responsive window behavior,
-- glyph reliability and touch presentation. No new public component types.
-- ============================================================================

local V32_VERSION = "3.2.0-executor"

-- Rose keeps the pink identity but moves most of the chrome back toward neutral
-- charcoal. Accent should attract the eye; every container should not compete.
AstraUI.Themes.Rose = merge(DEFAULT_THEME, {
    Background = Color3.fromRGB(12, 10, 13),
    Surface = Color3.fromRGB(18, 15, 19),
    Surface2 = Color3.fromRGB(26, 21, 27),
    Surface3 = Color3.fromRGB(35, 29, 37),
    Accent = Color3.fromRGB(231, 87, 164),
    Accent2 = Color3.fromRGB(255, 136, 199),
    Border = Color3.fromRGB(53, 43, 56),
})

local function v32GetViewport()
    local camera = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function v32GetOffsetSize(size, fallbackX, fallbackY)
    if typeof(size) == "UDim2" and size.X.Scale == 0 and size.Y.Scale == 0 then
        return math.max(1, size.X.Offset), math.max(1, size.Y.Offset)
    end
    return fallbackX, fallbackY
end

local function v32SetCorner(instance, radius)
    if not instance then return end
    local c = instance:FindFirstChildOfClass("UICorner")
    if c then c.CornerRadius = UDim.new(0, radius) end
end

local function v32SetPagePadding(page, left, right, top, bottom)
    if not page then return end
    local p = page:FindFirstChildOfClass("UIPadding")
    if p then
        p.PaddingLeft = UDim.new(0, left)
        p.PaddingRight = UDim.new(0, right)
        p.PaddingTop = UDim.new(0, top)
        p.PaddingBottom = UDim.new(0, bottom)
    end
end

local function v32RegisterResponsive(window, callback)
    window._v32ResponsiveCallbacks = window._v32ResponsiveCallbacks or {}
    table.insert(window._v32ResponsiveCallbacks, callback)
end

local function v32RunResponsiveCallbacks(window)
    for _, callback in ipairs(window._v32ResponsiveCallbacks or {}) do
        safeCall(callback, window._v32Narrow == true, window._v32TouchLayout == true)
    end
end

local function v32Chevron(window, parent, size)
    local host = create("Frame", {
        Name = "AstraV32Chevron",
        Parent = parent,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size or 14, size or 14),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = (parent.ZIndex or 1) + 2,
    })
    local color = window.Theme.Muted
    local a = v31Line(host, UDim2.new(0.5, -5, 0.5, -1), UDim2.fromOffset(7, 1.4), color, 40, host.ZIndex + 1)
    local b = v31Line(host, UDim2.new(0.5, 0, 0.5, -1), UDim2.fromOffset(7, 1.4), color, -40, host.ZIndex + 1)
    window._bindTheme(a, "BackgroundColor3", "Muted")
    window._bindTheme(b, "BackgroundColor3", "Muted")
    return host
end

local function v32DecorateChevronGlyph(window, glyph)
    if not glyph or glyph:GetAttribute("AstraV32ChevronGlyph") then return end
    local text = tostring(glyph.Text or "")
    if text ~= "⌄" and text ~= "⌃" then return end
    glyph:SetAttribute("AstraV32ChevronGlyph", true)
    glyph.TextTransparency = 1
    local host = v32Chevron(window, glyph, 14)
    local function sync()
        local value = tostring(glyph.Text or "")
        host.Visible = value == "⌄" or value == "⌃"
        local rotation = value == "⌃" and 180 or 0
        tween(host, 0.12, {Rotation = rotation})
    end
    window:_connect(glyph:GetPropertyChangedSignal("Text"), sync)
    sync()
end

local function v32DecorateCheckGlyph(window, glyph)
    if not glyph or glyph:GetAttribute("AstraV32CheckGlyph") then return end
    if not glyph:IsA("TextLabel") then return end
    if glyph.AnchorPoint.X < 0.9 then return end
    if glyph.Size.X.Offset ~= 20 or glyph.Size.Y.Offset ~= 20 then return end

    glyph:SetAttribute("AstraV32CheckGlyph", true)
    glyph.TextTransparency = 1
    local host = create("Frame", {
        Name = "AstraV32Check",
        Parent = glyph,
        AnchorPoint = Vector2.new(0.5,0.5),
        Position = UDim2.fromScale(0.5,0.5),
        Size = UDim2.fromOffset(14,14),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = glyph.ZIndex + 2,
    })
    local a = v31Line(host, UDim2.fromOffset(1.5,7.5), UDim2.fromOffset(5.5,1.5), window.Theme.Accent2, 42, host.ZIndex + 1)
    local b = v31Line(host, UDim2.fromOffset(5.2,6.4), UDim2.fromOffset(8,1.5), window.Theme.Accent2, -43, host.ZIndex + 1)
    window._bindTheme(a,"BackgroundColor3","Accent2")
    window._bindTheme(b,"BackgroundColor3","Accent2")
    local function sync()
        host.Visible = tostring(glyph.Text or "") ~= ""
    end
    window:_connect(glyph:GetPropertyChangedSignal("Text"), sync)
    sync()
end

local function v32DecorateGlyphs(window, root)
    if not root then return end
    for _, item in ipairs(root:GetDescendants()) do
        if item:IsA("TextLabel") or item:IsA("TextButton") then
            v32DecorateChevronGlyph(window, item)
        end
        if item:IsA("TextLabel") then
            v32DecorateCheckGlyph(window, item)
        end
    end
end

-- Reduce visual nesting another step. Borders become supporting detail instead
-- of the dominant separator between every single control.
local _AstraV32Row = Tab._row
function Tab:_row(parent, height)
    local row = _AstraV32Row(self, parent, height)
    for _, child in ipairs(row:GetChildren()) do
        if child:IsA("UIStroke") then child.Transparency = 0.76 end
    end
    v32SetCorner(row, 10)
    return row
end

-- Keep the existing dropdown API/behavior, but replace unsupported unicode UI
-- glyphs and make the right-hand value field adapt on narrow phones.
local _AstraV32AddDropdown = Tab._addDropdown
function Tab:_addDropdown(parent, data)
    local existing = {}
    for _, child in ipairs(parent:GetChildren()) do existing[child] = true end

    local object = _AstraV32AddDropdown(self, parent, data)
    local holder
    for _, child in ipairs(parent:GetChildren()) do
        if not existing[child] and child:IsA("Frame") then
            holder = child
            break
        end
    end

    if holder then
        holder.Name = "AstraDropdown"
        object.Instance = holder
        for _, child in ipairs(holder:GetChildren()) do
            if child:IsA("UIStroke") then child.Transparency = 0.74 end
        end
        v32DecorateGlyphs(self.Window, holder)

        self.Window:_connect(holder.DescendantAdded, function(descendant)
            task.defer(function()
                if self.Window.Destroyed or not descendant.Parent then return end
                if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
                    v32DecorateChevronGlyph(self.Window, descendant)
                end
                if descendant:IsA("TextLabel") then
                    v32DecorateCheckGlyph(self.Window, descendant)
                end
            end)
        end)

        local header
        for _, child in ipairs(holder:GetChildren()) do
            if child:IsA("TextButton") then header = child break end
        end
        if header then
            local display
            local titleLabels = {}
            for _, child in ipairs(header:GetChildren()) do
                if child:IsA("TextLabel") then
                    if child.BackgroundTransparency < 1 and child.AnchorPoint.X > 0.9 then
                        display = child
                    elseif not child:GetAttribute("AstraV32ChevronGlyph") then
                        table.insert(titleLabels, child)
                    end
                end
            end
            v32RegisterResponsive(self.Window, function(narrow)
                if not header.Parent then return end
                header.Size = UDim2.new(1,0,0,narrow and 56 or 58)
                if display then
                    display.Size = UDim2.fromOffset(narrow and 112 or 166, narrow and 30 or 32)
                    display.Position = UDim2.new(1, narrow and -36 or -40, 0.5, 0)
                end
                if narrow then
                    for _, label in ipairs(titleLabels) do
                        label.Size = UDim2.new(1,-162,label.Size.Y.Scale,label.Size.Y.Offset)
                    end
                end
            end)
        end
    end

    return object
end

-- Section frame remains the same component, just quieter and more efficient on
-- small screens.
local _AstraV32CreateSection = Tab.CreateSection
function Tab:CreateSection(options)
    local section = _AstraV32CreateSection(self, options)
    if section and section.Frame then
        for _, child in ipairs(section.Frame:GetChildren()) do
            if child:IsA("UIStroke") then child.Transparency = 0.66 end
        end
        v32SetCorner(section.Frame, 13)
        v32DecorateGlyphs(self.Window, section.Frame)
    end
    v32RegisterResponsive(self.Window, function(narrow)
        if not section or not section.Frame or not section.Frame.Parent then return end
        for _, child in ipairs(section.Frame:GetChildren()) do
            if child:IsA("UIPadding") then
                local side = narrow and 9 or 11
                child.PaddingLeft = UDim.new(0,side)
                child.PaddingRight = UDim.new(0,side)
                child.PaddingTop = UDim.new(0,narrow and 8 or 10)
                child.PaddingBottom = UDim.new(0,narrow and 9 or 11)
            end
        end
        if section.Layout then section.Layout.Padding = UDim.new(0,narrow and 5 or 6) end
    end)
    return section
end

local function v32SetTabIconColor(tab, color)
    local host = tab and tab._v31IconFrame
    if not host then return end
    for _, item in ipairs(host:GetDescendants()) do
        if item:IsA("UIStroke") then
            tween(item, 0.14, {Color = color})
        elseif item:IsA("ImageLabel") then
            tween(item, 0.14, {ImageColor3 = color})
        elseif item:IsA("TextLabel") then
            tween(item, 0.14, {TextColor3 = color})
        elseif item:IsA("Frame") and item.BackgroundTransparency < 1 then
            tween(item, 0.14, {BackgroundColor3 = color})
        end
    end
end

local function v32ApplyTabVisuals(window)
    for _, tab in ipairs(window.Tabs or {}) do
        local selected = tab == window.CurrentTab
        if tab.Button then
            if selected then
                tween(tab.Button, 0.14, {BackgroundTransparency = 0.08})
            end
        end
        v32SetTabIconColor(tab, selected and window.Theme.Accent2 or window.Theme.Muted)
    end
end

local _AstraV32CreateTab = Window.CreateTab
function Window:CreateTab(options)
    local tab = _AstraV32CreateTab(self, options)
    if tab.Page then
        tab.Page.ScrollBarThickness = UserInputService.TouchEnabled and 0 or 2
        tab.Page.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
        tab.Page.ScrollingDirection = Enum.ScrollingDirection.Y
        v32RegisterResponsive(self, function(narrow, touch)
            if not tab.Page.Parent then return end
            v32SetPagePadding(tab.Page, narrow and 10 or 18, narrow and 10 or 18, narrow and 2 or 4, narrow and 12 or 18)
            tab.Page.ScrollBarThickness = touch and 0 or 2
        end)
    end
    v32ApplyTabVisuals(self)
    return tab
end

local _AstraV32SelectTab = Window.SelectTab
function Window:SelectTab(tab)
    _AstraV32SelectTab(self, tab)
    v32ApplyTabVisuals(self)
    if tab and tab.Page and tab.Page.Visible then
        tab.Page.Position = UDim2.fromOffset(0, 4)
        tween(tab.Page, 0.15, {Position = UDim2.fromOffset(0,0)})
    end
    if self._v32Narrow and self._v32DrawerOpen then
        self:SetSidebarCollapsed(true)
    end
end

local _AstraV32SetTheme = Window.SetTheme
function Window:SetTheme(themePatch)
    _AstraV32SetTheme(self, themePatch)
    task.defer(function()
        if not self.Destroyed then v32ApplyTabVisuals(self) end
    end)
end

local _AstraV32SetSidebarCollapsed = Window.SetSidebarCollapsed
local _AstraV32ToggleSidebar = Window.ToggleSidebar

local function v32SetDrawer(window, open, instant)
    if not window._v32Narrow then return end
    open = open == true
    window._v32DrawerOpen = open
    window.SidebarCollapsed = not open

    local width = window._v32DrawerWidth or 228
    local target = open and UDim2.fromOffset(0,0) or UDim2.fromOffset(-width - 8,0)
    if instant then
        window.Sidebar.Position = target
    else
        tween(window.Sidebar, 0.18, {Position = target}, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    end

    if window._v32Scrim then
        if open then
            window._v32Scrim.Visible = true
            window._v32Scrim.BackgroundTransparency = 1
            tween(window._v32Scrim, 0.16, {BackgroundTransparency = 0.46})
        else
            tween(window._v32Scrim, 0.14, {BackgroundTransparency = 1})
            task.delay(0.14, function()
                if window.Destroyed or not window._v32Scrim then return end
                if not window._v32DrawerOpen then window._v32Scrim.Visible = false end
            end)
        end
    end

    local searchHolder = window.SearchBox and window.SearchBox.Parent
    if searchHolder then searchHolder.Visible = true end
    if window.BrandTitle then window.BrandTitle.Visible = true end
    if window.BrandSubtitle then window.BrandSubtitle.Visible = true end
    if window.FooterText then window.FooterText.Visible = true end
    if window.TabList then
        window.TabList.Position = UDim2.fromOffset(10,126)
        window.TabList.Size = UDim2.new(1,-20,1,-180)
    end
    for _, tab in ipairs(window.Tabs or {}) do
        if tab._v31ApplyLayout then tab:_v31ApplyLayout(false) end
    end
end

function Window:SetSidebarCollapsed(state, instant)
    if self._v32Narrow then
        v32SetDrawer(self, not (state == true), instant)
        return
    end
    _AstraV32SetSidebarCollapsed(self, state, instant)
    v32ApplyTabVisuals(self)
end

function Window:ToggleSidebar()
    if self._v32Narrow then
        v32SetDrawer(self, not self._v32DrawerOpen, false)
        return
    end
    _AstraV32ToggleSidebar(self)
end

local function v32ApplyWindowResponsive(window, options, instant)
    if window.Destroyed then return end
    local viewport = v32GetViewport()
    local touch = UserInputService.TouchEnabled
    local baseW, baseH = v32GetOffsetSize(window._v32BaseSize, 840, 550)
    local narrow = viewport.X < 600 or (touch and viewport.X < 680 and viewport.Y >= viewport.X)
    local touchLayout = touch == true
    local wasNarrow = window._v32Narrow == true
    local wasDrawerOpen = window._v32DrawerOpen == true

    window._v32Narrow = narrow
    window._v32TouchLayout = touchLayout

    local shadow = window.Root and window.Root:FindFirstChild("Shadow")

    if narrow then
        local margin = 6
        window.ResponsiveScale = 1
        window.Scale.Scale = 1
        window.Root.Position = UDim2.fromScale(0.5,0.5)
        window.Root.Size = UDim2.new(1,-margin*2,1,-margin*2)
        v32SetCorner(window.Root, 14)
        if shadow then shadow.Visible = false end

        local drawerWidth = math.clamp(math.floor(viewport.X * 0.74), 208, 252)
        window._v32DrawerWidth = drawerWidth
        window.Sidebar.Size = UDim2.new(0,drawerWidth,1,0)
        window.Sidebar.ZIndex = 30
        window.Main.Position = UDim2.fromOffset(0,0)
        window.Main.Size = UDim2.fromScale(1,1)

        window.Topbar.Size = UDim2.new(1,0,0,58)
        window.Pages.Position = UDim2.fromOffset(0,58)
        window.Pages.Size = UDim2.new(1,0,1,-58)

        if window.SidebarButton then
            window.SidebarButton.AnchorPoint = Vector2.new(0,0)
            window.SidebarButton.Position = UDim2.fromOffset(12,12)
            window.SidebarButton.Size = UDim2.fromOffset(32,32)
        end
        if window.PageTitle then
            window.PageTitle.Position = UDim2.fromOffset(56,8)
            window.PageTitle.Size = UDim2.new(1,-164,0,22)
            window.PageTitle.TextSize = 17
        end
        if window.PageDesc then
            window.PageDesc.Position = UDim2.fromOffset(56,31)
            window.PageDesc.Size = UDim2.new(1,-164,0,17)
            window.PageDesc.TextSize = 10
        end
        if window.ThemeButton and window.ThemeButton.Parent then
            local actions = window.ThemeButton.Parent
            actions.Size = UDim2.fromOffset(70,32)
            actions.Position = UDim2.new(1,-10,0,12)
            window.ThemeButton.Size = UDim2.fromOffset(32,32)
            window.ThemeButton.Position = UDim2.fromOffset(0,0)
            window.MinimizeButton.Size = UDim2.fromOffset(32,32)
            window.MinimizeButton.Position = UDim2.fromOffset(38,0)
        end
        if window.CloseButton then window.CloseButton.Visible = false end

        if window.NotificationHost then
            window.NotificationHost.Position = UDim2.new(1,-10,0,10)
            window.NotificationHost.Size = UDim2.fromOffset(math.clamp(viewport.X - 20, 250, 330),0)
        end
        if window.MobileOpen then
            window.MobileOpen.Size = UDim2.fromOffset(50,50)
            window.MobileOpen.AnchorPoint = Vector2.new(1,1)
            if not window.MobileOpen:GetAttribute("AstraV32UserMovedLauncher") then
                window.MobileOpen.Position = UDim2.new(1,-14,1,-14)
            end
        end

        -- Drawer starts closed when entering phone layout, but an already open
        -- drawer stays open through small viewport-height changes (keyboard etc.).
        v32SetDrawer(window, wasNarrow and wasDrawerOpen or false, instant ~= false)
    else
        if window._v32Scrim then
            window._v32Scrim.Visible = false
            window._v32Scrim.BackgroundTransparency = 1
        end
        window._v32DrawerOpen = false
        window.Sidebar.Position = UDim2.fromOffset(0,0)
        window.Sidebar.ZIndex = 3
        window.Root.Size = window._v32BaseSize
        window.Root.Position = UDim2.fromScale(0.5,0.5)
        v32SetCorner(window.Root, 18)
        if shadow then shadow.Visible = true end

        local fitScale = math.min((viewport.X - 18) / baseW, (viewport.Y - 18) / baseH, 1)
        fitScale = math.clamp(fitScale, touch and 0.52 or 0.72, 1)
        window.ResponsiveScale = fitScale
        if not window.Minimized then window.Scale.Scale = fitScale end

        window.Topbar.Size = UDim2.new(1,0,0,66)
        window.Pages.Position = UDim2.fromOffset(0,66)
        window.Pages.Size = UDim2.new(1,0,1,-66)

        if window.SidebarButton then
            window.SidebarButton.AnchorPoint = Vector2.new(1,0)
            window.SidebarButton.Position = UDim2.new(1,-100,0,14)
            window.SidebarButton.Size = UDim2.fromOffset(34,34)
        end
        if window.PageTitle then
            window.PageTitle.Position = UDim2.fromOffset(20,12)
            window.PageTitle.Size = UDim2.new(1,-170,0,24)
            window.PageTitle.TextSize = 18
        end
        if window.PageDesc then
            window.PageDesc.Position = UDim2.fromOffset(20,36)
            window.PageDesc.Size = UDim2.new(1,-170,0,18)
            window.PageDesc.TextSize = 11
        end
        if window.ThemeButton and window.ThemeButton.Parent then
            local actions = window.ThemeButton.Parent
            actions.Size = UDim2.fromOffset(76,34)
            actions.Position = UDim2.new(1,-14,0,14)
            window.ThemeButton.Size = UDim2.fromOffset(34,34)
            window.ThemeButton.Position = UDim2.fromOffset(0,0)
            window.MinimizeButton.Size = UDim2.fromOffset(34,34)
            window.MinimizeButton.Position = UDim2.fromOffset(42,0)
        end
        if window.CloseButton then window.CloseButton.Visible = options.ShowCloseButton == true end
        if window.NotificationHost then
            window.NotificationHost.Position = UDim2.new(1,-16,0,16)
            window.NotificationHost.Size = UDim2.fromOffset(330,0)
        end
        if window.MobileOpen then
            window.MobileOpen.Size = UDim2.fromOffset(56,56)
        end

        if options.AutoCollapseSidebar ~= false then
            local targetCollapsed = touch or viewport.X < 700
            -- Narrow drawer mode also uses SidebarCollapsed as its open/closed
            -- state. Force one transition when leaving that mode so the rail
            -- geometry is actually restored even when the boolean matches.
            if wasNarrow then window.SidebarCollapsed = not targetCollapsed end
            window:SetSidebarCollapsed(targetCollapsed, true)
        elseif wasNarrow then
            window.SidebarCollapsed = true
            window:SetSidebarCollapsed(false, true)
        end
    end

    if window.TabList then
        local layout = window.TabList:FindFirstChildOfClass("UIListLayout")
        if layout then layout.Padding = UDim.new(0,narrow and 4 or 5) end
    end

    v32RunResponsiveCallbacks(window)
    v32ApplyTabVisuals(window)
end

local _AstraV32CreateWindow = AstraUI.CreateWindow
function AstraUI:CreateWindow(options)
    options = options or {}
    local window = _AstraV32CreateWindow(self, options)
    window._v32BaseSize = options.Size or UDim2.fromOffset(840,550)
    window._v32ResponsiveCallbacks = window._v32ResponsiveCallbacks or {}
    window._v32Narrow = false
    window._v32DrawerOpen = false

    -- Dimmer belongs to the existing navigation structure; it only appears when
    -- the sidebar becomes a mobile drawer.
    local scrim = create("TextButton", {
        Name = "MobileSidebarScrim",
        Parent = window.Root,
        Size = UDim2.fromScale(1,1),
        BackgroundColor3 = Color3.new(0,0,0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Visible = false,
        ZIndex = 20,
    })
    window._v32Scrim = scrim
    window:_connect(scrim.MouseButton1Click, function()
        if window._v32Narrow then window:SetSidebarCollapsed(true) end
    end)

    -- Remove every remaining arrow/check unicode dependency in existing UI.
    v32DecorateGlyphs(window, window.Root)

    local cameraConnection
    local function bindViewport()
        if cameraConnection then
            pcall(function() cameraConnection:Disconnect() end)
            cameraConnection = nil
        end
        local camera = workspace.CurrentCamera
        if camera then
            cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                task.defer(function()
                    if not window.Destroyed then v32ApplyWindowResponsive(window, options, true) end
                end)
            end)
            table.insert(window._connections, cameraConnection)
        end
        task.defer(function()
            if not window.Destroyed then v32ApplyWindowResponsive(window, options, true) end
        end)
    end
    bindViewport()
    window:_connect(workspace:GetPropertyChangedSignal("CurrentCamera"), bindViewport)

    -- Keep the launcher inside a reachable mobile-safe region after dragging.
    if window.MobileOpen then
        window:_connect(UserInputService.InputEnded, function(input)
            if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            task.defer(function()
                if window.Destroyed or not window.MobileOpen or not window.MobileOpen.Parent then return end
                local viewport = v32GetViewport()
                local pos = window.MobileOpen.AbsolutePosition
                local size = window.MobileOpen.AbsoluteSize
                local x = math.clamp(pos.X, 8, math.max(8,viewport.X-size.X-8))
                local y = math.clamp(pos.Y, 8, math.max(8,viewport.Y-size.Y-8))
                window.MobileOpen:SetAttribute("AstraV32UserMovedLauncher", true)
                window.MobileOpen.AnchorPoint = Vector2.new(1,1)
                window.MobileOpen.Position = UDim2.fromOffset(x + size.X, y + size.Y)
            end)
        end)
    end

    return window
end


-- ============================================================================
-- AstraUI V3.3 visual refinement layer
-- No new component types: this pass only improves density, hierarchy and
-- touch-landscape presentation based on real mobile screenshots.
-- ============================================================================

local V33_VERSION = "3.3.0-executor"

local function v33IsTouchLandscape()
    local viewport = v32GetViewport()
    return UserInputService.TouchEnabled and viewport.X > viewport.Y and not (viewport.X < 600)
end

local function v33FindBrandParts(window)
    if window._v33BrandFrame and window._v33BrandFrame.Parent then
        return window._v33BrandFrame, window._v33BrandIcon
    end
    if not window.Sidebar then return nil,nil end
    for _, child in ipairs(window.Sidebar:GetChildren()) do
        if child:IsA("Frame") and child.BackgroundTransparency == 1 then
            for _, nested in ipairs(child:GetChildren()) do
                if nested:IsA("Frame") and nested.Size.X.Offset >= 34 and nested.Size.X.Offset <= 44 then
                    local label = nested:FindFirstChildOfClass("TextLabel")
                    if label then
                        window._v33BrandFrame = child
                        window._v33BrandIcon = nested
                        return child,nested
                    end
                end
            end
        end
    end
    return nil,nil
end

local function v33DrawThemeIcon(window)
    local target = window.ThemeButton
    if not target then return end
    v31ClearIcon(target)
    target.Text = ""
    target.TextTransparency = 1

    local host = v31IconHost(target, UDim2.new(0.5,-9,0.5,-9), UDim2.fromOffset(18,18), target.ZIndex + 2)
    host.Name = "AstraV31Icon"
    local color = window.Theme.Muted

    local center = create("Frame", {
        Parent = host,
        AnchorPoint = Vector2.new(0.5,0.5),
        Position = UDim2.fromScale(0.5,0.5),
        Size = UDim2.fromOffset(6,6),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        ZIndex = host.ZIndex + 2,
    }, {corner(999)})
    window._bindTheme(center,"BackgroundColor3","Muted")

    for _, data in ipairs({
        {UDim2.fromOffset(8.4,0.5), UDim2.fromOffset(1.2,4), 0},
        {UDim2.fromOffset(8.4,13.5), UDim2.fromOffset(1.2,4), 0},
        {UDim2.fromOffset(0.5,8.4), UDim2.fromOffset(4,1.2), 0},
        {UDim2.fromOffset(13.5,8.4), UDim2.fromOffset(4,1.2), 0},
        {UDim2.fromOffset(2.8,2.8), UDim2.fromOffset(4,1.1), 45},
        {UDim2.fromOffset(11.2,2.8), UDim2.fromOffset(4,1.1), -45},
        {UDim2.fromOffset(2.8,11.2), UDim2.fromOffset(4,1.1), -45},
        {UDim2.fromOffset(11.2,11.2), UDim2.fromOffset(4,1.1), 45},
    }) do
        local ray = v31Line(host, data[1], data[2], color, data[3], host.ZIndex + 1)
        window._bindTheme(ray,"BackgroundColor3","Muted")
    end
end

-- Rows keep their normal desktop size, but become denser in touch landscape.
-- This preserves comfortable portrait touch targets while fitting considerably
-- more information on the common mobile landscape viewport used by Roblox.
local _AstraV33Row = Tab._row
function Tab:_row(parent, height)
    local baseHeight = height or 54
    local row = _AstraV33Row(self,parent,height)
    v32RegisterResponsive(self.Window,function(narrow,touch)
        if not row.Parent then return end
        local dense = touch and not narrow and v33IsTouchLandscape()
        local target = baseHeight
        if dense then
            if baseHeight >= 72 then
                target = baseHeight - 10
            elseif baseHeight >= 60 then
                target = baseHeight - 7
            else
                target = math.max(48,baseHeight - 4)
            end
        end
        row.Size = UDim2.new(1,0,0,target)
    end)
    return row
end

-- Sections lose a little more padding only in landscape-touch mode. The goal is
-- not to make them tiny; it is to remove the "card inside card" heaviness.
local _AstraV33CreateSection = Tab.CreateSection
function Tab:CreateSection(options)
    local section = _AstraV33CreateSection(self,options)
    v32RegisterResponsive(self.Window,function(narrow,touch)
        if not section or not section.Frame or not section.Frame.Parent then return end
        local dense = touch and not narrow and v33IsTouchLandscape()
        if dense then
            for _, child in ipairs(section.Frame:GetChildren()) do
                if child:IsA("UIPadding") then
                    child.PaddingLeft = UDim.new(0,9)
                    child.PaddingRight = UDim.new(0,9)
                    child.PaddingTop = UDim.new(0,8)
                    child.PaddingBottom = UDim.new(0,9)
                elseif child:IsA("UIStroke") then
                    child.Transparency = 0.72
                end
            end
            if section.Layout then section.Layout.Padding = UDim.new(0,5) end
        end
    end)
    return section
end

-- Dropdown value boxes were still visually heavier than the other controls on
-- mobile landscape. Keep the same behavior but tighten the field and row.
local _AstraV33Dropdown = Tab._addDropdown
function Tab:_addDropdown(parent,data)
    local object = _AstraV33Dropdown(self,parent,data)
    local holder = object and object.Instance
    if holder then
        v32RegisterResponsive(self.Window,function(narrow,touch)
            if not holder.Parent then return end
            local dense = touch and not narrow and v33IsTouchLandscape()
            if dense then
                local header
                for _, child in ipairs(holder:GetChildren()) do
                    if child:IsA("TextButton") then header=child break end
                end
                if header then
                    header.Size = UDim2.new(1,0,0,54)
                    for _, child in ipairs(header:GetChildren()) do
                        if child:IsA("TextLabel") and child.BackgroundTransparency < 1 and child.AnchorPoint.X > 0.9 then
                            child.Size = UDim2.fromOffset(150,30)
                            child.Position = UDim2.new(1,-38,0.5,0)
                        end
                    end
                end
            end
        end)
    end
    return object
end

local _AstraV33CreateTab = Window.CreateTab
function Window:CreateTab(options)
    local tab = _AstraV33CreateTab(self,options)
    v32RegisterResponsive(self,function(narrow,touch)
        if not tab.Page or not tab.Page.Parent then return end
        local dense = touch and not narrow and v33IsTouchLandscape()
        if dense then
            v32SetPagePadding(tab.Page,14,14,2,14)
        end
    end)
    return tab
end

local function v33ApplySidebarGeometry(window)
    if window.Destroyed or window._v32Narrow then return end
    local viewport = v32GetViewport()
    local touchLandscape = UserInputService.TouchEnabled and viewport.X > viewport.Y
    if not touchLandscape then
        if window.Footer then window.Footer.Visible = true end
        return
    end

    local collapsed = window.SidebarCollapsed == true
    local sidebarWidth = collapsed and 62 or 194
    window.Sidebar.Size = UDim2.new(0,sidebarWidth,1,0)
    window.Main.Position = UDim2.fromOffset(sidebarWidth,0)
    window.Main.Size = UDim2.new(1,-sidebarWidth,1,0)

    local brand,brandIcon = v33FindBrandParts(window)
    if brand then
        brand.Position = collapsed and UDim2.fromOffset(12,12) or UDim2.fromOffset(14,14)
    end
    if brandIcon then
        brandIcon.Size = collapsed and UDim2.fromOffset(36,36) or UDim2.fromOffset(38,38)
    end

    if window.Footer then
        window.Footer.Visible = not collapsed
        if not collapsed then
            window.Footer.Position = UDim2.new(0,10,1,-10)
            window.Footer.Size = UDim2.new(1,-20,0,38)
            local dot
            for _, child in ipairs(window.Footer:GetChildren()) do
                if child:IsA("Frame") and child.Size.X.Offset <= 12 then dot=child break end
            end
            if dot then
                dot.Size = UDim2.fromOffset(8,8)
                dot.Position = UDim2.fromOffset(11,15)
            end
        end
    end

    if window.TabList then
        if collapsed then
            window.TabList.Position = UDim2.fromOffset(6,68)
            window.TabList.Size = UDim2.new(1,-12,1,-82)
        else
            window.TabList.Position = UDim2.fromOffset(8,118)
            window.TabList.Size = UDim2.new(1,-16,1,-168)
        end
    end

    local searchHolder = window.SearchBox and window.SearchBox.Parent
    if searchHolder and not collapsed then
        searchHolder.Position = UDim2.fromOffset(10,72)
        searchHolder.Size = UDim2.new(1,-20,0,36)
        v32SetCorner(searchHolder,9)
    end

    for _, tab in ipairs(window.Tabs or {}) do
        if tab.Button then
            tab.Button.Size = UDim2.new(1,0,0,collapsed and 38 or 40)
            v32SetCorner(tab.Button,9)
        end
        if tab._v31ApplyLayout then tab:_v31ApplyLayout(collapsed) end
    end
end

local function v33ApplyWindowPolish(window,options)
    if window.Destroyed then return end
    local viewport = v32GetViewport()
    local touch = UserInputService.TouchEnabled
    local landscapeTouch = touch and viewport.X > viewport.Y and not window._v32Narrow

    if landscapeTouch then
        local baseW,baseH = v32GetOffsetSize(window._v32BaseSize,840,550)
        local targetW = math.min(baseW,820)
        local targetH = math.min(baseH,500)
        window.Root.Size = UDim2.fromOffset(targetW,targetH)
        window.Root.Position = UDim2.fromScale(0.5,0.5)
        v32SetCorner(window.Root,16)

        local fitScale = math.min((viewport.X-24)/targetW,(viewport.Y-24)/targetH,1)
        fitScale = math.clamp(fitScale,0.72,1)
        window.ResponsiveScale = fitScale
        if not window.Minimized then window.Scale.Scale = fitScale end

        window.Topbar.Size = UDim2.new(1,0,0,60)
        window.Pages.Position = UDim2.fromOffset(0,60)
        window.Pages.Size = UDim2.new(1,0,1,-60)

        if window.PageTitle then
            window.PageTitle.Position = UDim2.fromOffset(18,9)
            window.PageTitle.Size = UDim2.new(1,-158,0,22)
            window.PageTitle.TextSize = 17
        end
        if window.PageDesc then
            window.PageDesc.Position = UDim2.fromOffset(18,31)
            window.PageDesc.Size = UDim2.new(1,-158,0,16)
            window.PageDesc.TextSize = 10
        end
        if window.SidebarButton then
            window.SidebarButton.Size = UDim2.fromOffset(32,32)
            window.SidebarButton.Position = UDim2.new(1,-94,0,12)
        end
        if window.ThemeButton and window.ThemeButton.Parent then
            local actions = window.ThemeButton.Parent
            actions.Size = UDim2.fromOffset(70,32)
            actions.Position = UDim2.new(1,-12,0,12)
            window.ThemeButton.Size = UDim2.fromOffset(32,32)
            window.MinimizeButton.Size = UDim2.fromOffset(32,32)
            window.MinimizeButton.Position = UDim2.fromOffset(38,0)
        end
        v33ApplySidebarGeometry(window)
    end
end

local _AstraV33SetSidebarCollapsed = Window.SetSidebarCollapsed
function Window:SetSidebarCollapsed(state,instant)
    _AstraV33SetSidebarCollapsed(self,state,instant)
    task.defer(function()
        if not self.Destroyed then
            v33ApplySidebarGeometry(self)
            v33ApplyWindowPolish(self,self.Options or {})
        end
    end)
end

local _AstraV33CreateWindow = AstraUI.CreateWindow
function AstraUI:CreateWindow(options)
    options = options or {}
    local window = _AstraV33CreateWindow(self,options)

    -- The old half-filled ring was visually heavy in screenshots. A simple sun
    -- is clearer at mobile scale and remains completely font-independent.
    v33DrawThemeIcon(window)

    local function applyLater()
        task.defer(function()
            if window.Destroyed then return end
            v33ApplyWindowPolish(window,options)
            v33ApplySidebarGeometry(window)
            v32RunResponsiveCallbacks(window)
            v32ApplyTabVisuals(window)
        end)
    end

    local cameraConnection
    local function bindV33Camera()
        if cameraConnection then
            pcall(function() cameraConnection:Disconnect() end)
            cameraConnection=nil
        end
        local camera=workspace.CurrentCamera
        if camera then
            cameraConnection=camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLater)
            table.insert(window._connections,cameraConnection)
        end
        applyLater()
    end
    bindV33Camera()
    window:_connect(workspace:GetPropertyChangedSignal("CurrentCamera"),bindV33Camera)

    return window
end


AstraUI.Version = V33_VERSION

-- ============================================================================
-- AstraUI V3.4 interaction + responsive polish layer
-- Focus: smoother mobile rail transitions, quieter hierarchy and larger
-- invisible touch targets without making the visual controls bulky.
-- No new public component types are introduced in this pass.
-- ============================================================================

local V34_VERSION = "3.4.0-executor"

local function v34TouchLandscape()
    local viewport = v32GetViewport()
    return UserInputService.TouchEnabled and viewport.X > viewport.Y and not (viewport.X < 600)
end

local function v34ApplyRail(window, collapsed, instant)
    if window.Destroyed or window._v32Narrow or not v34TouchLandscape() then
        return false
    end

    collapsed = collapsed == true
    window.SidebarCollapsed = collapsed

    -- A slightly slimmer rail gives the content more breathing room while the
    -- expanded sidebar stays wide enough for labels and search.
    local width = collapsed and 58 or 188
    local duration = instant and 0 or 0.18

    local sidebarProps = {Size = UDim2.new(0,width,1,0)}
    local mainProps = {
        Position = UDim2.fromOffset(width,0),
        Size = UDim2.new(1,-width,1,0),
    }

    if duration == 0 then
        window.Sidebar.Size = sidebarProps.Size
        window.Main.Position = mainProps.Position
        window.Main.Size = mainProps.Size
    else
        tween(window.Sidebar,duration,sidebarProps,Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
        tween(window.Main,duration,mainProps,Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
    end

    local brand,brandIcon = v33FindBrandParts(window)
    if brand then
        brand.Position = collapsed and UDim2.fromOffset(11,12) or UDim2.fromOffset(13,14)
    end
    if brandIcon then
        brandIcon.Size = collapsed and UDim2.fromOffset(34,34) or UDim2.fromOffset(38,38)
    end

    local searchHolder = window.SearchBox and window.SearchBox.Parent
    if searchHolder then
        searchHolder.Visible = not collapsed
        if not collapsed then
            searchHolder.Position = UDim2.fromOffset(10,72)
            searchHolder.Size = UDim2.new(1,-20,0,36)
            v32SetCorner(searchHolder,9)
        end
    end
    if window.BrandTitle then window.BrandTitle.Visible = not collapsed end
    if window.BrandSubtitle then window.BrandSubtitle.Visible = not collapsed end

    if window.Footer then
        window.Footer.Visible = not collapsed
        if not collapsed then
            window.Footer.Position = UDim2.new(0,10,1,-10)
            window.Footer.Size = UDim2.new(1,-20,0,38)
        end
    end

    if window.TabList then
        if collapsed then
            window.TabList.Position = UDim2.fromOffset(5,64)
            window.TabList.Size = UDim2.new(1,-10,1,-76)
        else
            window.TabList.Position = UDim2.fromOffset(8,118)
            window.TabList.Size = UDim2.new(1,-16,1,-168)
        end
        local layout = window.TabList:FindFirstChildOfClass("UIListLayout")
        if layout then layout.Padding = UDim.new(0,5) end
    end

    for _,tab in ipairs(window.Tabs or {}) do
        if tab.Button then
            tab.Button.Size = UDim2.new(1,0,0,collapsed and 38 or 40)
            v32SetCorner(tab.Button,9)
        end
        if tab._v31ApplyLayout then
            tab:_v31ApplyLayout(collapsed)
        end
    end
    v32ApplyTabVisuals(window)
    return true
end

-- V3.3 first animated to the V3.1 width and corrected the width on the next
-- task.defer. It looked fine in screenshots but produced a tiny "two-step"
-- movement in real use. V3.4 animates directly to the final mobile width.
local _AstraV34SetSidebarCollapsed = Window.SetSidebarCollapsed
function Window:SetSidebarCollapsed(state,instant)
    if v34ApplyRail(self,state,instant) then
        return
    end
    _AstraV34SetSidebarCollapsed(self,state,instant)
end

-- Give thin sliders a 36px invisible touch lane. The visible rail/thumb stay
-- compact; only the hit area becomes finger-friendly.
local _AstraV34Slider = Tab._addSlider
function Tab:_addSlider(parent,data)
    data = data or {}
    local before = {}
    for _,child in ipairs(parent:GetChildren()) do before[child]=true end
    local object = _AstraV34Slider(self,parent,data)

    if UserInputService.TouchEnabled then
        local row
        for _,child in ipairs(parent:GetChildren()) do
            if not before[child] and child:IsA("Frame") then row=child break end
        end
        if row then
            local bar
            for _,child in ipairs(row:GetChildren()) do
                if child:IsA("TextButton") and child.Size.Y.Offset <= 10 and child.Size.X.Scale > 0.5 then
                    bar=child
                    break
                end
            end
            if bar then
                local hit = create("TextButton",{
                    Name = "AstraSliderTouchLane",
                    Parent = row,
                    AutoButtonColor = false,
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Text = "",
                    Position = UDim2.new(bar.Position.X.Scale,bar.Position.X.Offset,bar.Position.Y.Scale,bar.Position.Y.Offset-14),
                    Size = UDim2.new(bar.Size.X.Scale,bar.Size.X.Offset,0,36),
                    ZIndex = math.max(bar.ZIndex + 5,8),
                })

                local min = tonumber(data.Min) or 0
                local max = tonumber(data.Max) or 100
                if max <= min then max=min+1 end
                local dragging=false
                local function setFrom(input)
                    if not hit.Parent or hit.AbsoluteSize.X <= 0 then return end
                    local x=input.Position.X
                    local alpha=math.clamp((x-hit.AbsolutePosition.X)/hit.AbsoluteSize.X,0,1)
                    object:Set(min+(max-min)*alpha)
                end
                self.Window:_connect(hit.InputBegan,function(input)
                    if input.UserInputType==Enum.UserInputType.Touch then
                        dragging=true
                        setFrom(input)
                    end
                end)
                self.Window:_connect(hit.InputEnded,function(input)
                    if input.UserInputType==Enum.UserInputType.Touch then dragging=false end
                end)
                self.Window:_connect(UserInputService.InputChanged,function(input)
                    if dragging and input.UserInputType==Enum.UserInputType.Touch then setFrom(input) end
                end)
            end
        end
    end
    return object
end

-- On touch devices the left side of a toggle row is also tappable. This makes
-- toggles feel native on phones without enlarging the visible switch.
local _AstraV34Toggle = Tab._addToggle
function Tab:_addToggle(parent,data)
    data=data or {}
    local before={}
    for _,child in ipairs(parent:GetChildren()) do before[child]=true end
    local object=_AstraV34Toggle(self,parent,data)
    if UserInputService.TouchEnabled then
        local row
        for _,child in ipairs(parent:GetChildren()) do
            if not before[child] and child:IsA("Frame") then row=child break end
        end
        if row then
            local hit=create("TextButton",{
                Name="AstraToggleTouchArea",
                Parent=row,
                AutoButtonColor=false,
                BackgroundTransparency=1,
                BorderSizePixel=0,
                Text="",
                Position=UDim2.fromOffset(0,0),
                Size=UDim2.new(1,-72,1,0),
                ZIndex=8,
            })
            self.Window:_connect(hit.MouseButton1Click,function()
                object:Set(not object:Get())
            end)
        end
    end
    return object
end

-- Quieter separators and slightly cleaner density on mobile landscape. This is
-- deliberately subtle: V3.3's proportions were already close to the target.
local _AstraV34Row = Tab._row
function Tab:_row(parent,height)
    local row=_AstraV34Row(self,parent,height)
    v32RegisterResponsive(self.Window,function(narrow,touch)
        if not row.Parent then return end
        local dense=touch and not narrow and v34TouchLandscape()
        for _,child in ipairs(row:GetChildren()) do
            if child:IsA("UIStroke") then
                child.Transparency=dense and 0.84 or 0.76
            end
        end
    end)
    return row
end

local _AstraV34CreateSection = Tab.CreateSection
function Tab:CreateSection(options)
    local section=_AstraV34CreateSection(self,options)
    v32RegisterResponsive(self.Window,function(narrow,touch)
        if not section or not section.Frame or not section.Frame.Parent then return end
        local dense=touch and not narrow and v34TouchLandscape()
        if dense then
            for _,child in ipairs(section.Frame:GetChildren()) do
                if child:IsA("UIStroke") then child.Transparency=0.82 end
            end
        end
    end)
    return section
end

local function v34ApplyWindow(window,options)
    if window.Destroyed then return end
    if v34TouchLandscape() and not window._v32Narrow then
        -- Keep the V3.3 footprint; users liked the size. Only refine internal
        -- spacing and the safe breathing room around the content.
        local viewport=v32GetViewport()
        local baseW,baseH=v32GetOffsetSize(window._v32BaseSize,840,550)
        local targetW=math.min(baseW,820)
        local targetH=math.min(baseH,500)
        window.Root.Size=UDim2.fromOffset(targetW,targetH)
        window.Root.Position=UDim2.fromScale(0.5,0.5)
        local fitScale=math.min((viewport.X-28)/targetW,(viewport.Y-28)/targetH,1)
        fitScale=math.clamp(fitScale,0.72,1)
        window.ResponsiveScale=fitScale
        if not window.Minimized then window.Scale.Scale=fitScale end

        window.Topbar.Size=UDim2.new(1,0,0,58)
        window.Pages.Position=UDim2.fromOffset(0,58)
        window.Pages.Size=UDim2.new(1,0,1,-58)
        if window.PageTitle then
            window.PageTitle.Position=UDim2.fromOffset(18,8)
        end
        if window.PageDesc then
            window.PageDesc.Position=UDim2.fromOffset(18,30)
        end
        if window.SidebarButton then
            window.SidebarButton.Position=UDim2.new(1,-94,0,11)
        end
        if window.ThemeButton and window.ThemeButton.Parent then
            local actions=window.ThemeButton.Parent
            actions.Position=UDim2.new(1,-12,0,11)
        end
        v34ApplyRail(window,window.SidebarCollapsed,true)
        v32RunResponsiveCallbacks(window)
    end
end

local _AstraV34CreateWindow = AstraUI.CreateWindow
function AstraUI:CreateWindow(options)
    options=options or {}
    local window=_AstraV34CreateWindow(self,options)

    local function apply()
        task.defer(function()
            if not window.Destroyed then
                v34ApplyWindow(window,options)
            end
        end)
    end
    local cameraConnection
    local function bindCamera()
        if cameraConnection then pcall(function() cameraConnection:Disconnect() end) end
        local camera=workspace.CurrentCamera
        if camera then
            cameraConnection=camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
            table.insert(window._connections,cameraConnection)
        end
        apply()
    end
    bindCamera()
    window:_connect(workspace:GetPropertyChangedSignal("CurrentCamera"),bindCamera)
    return window
end


-- ============================================================================
-- AstraUI V3.5 accessibility + state clarity refinement
-- Focus: contrast, toggle state communication, active navigation hierarchy,
-- touch breathing room and scroll affordance. No new component categories.
-- ============================================================================

local V35_VERSION = "3.5.0-executor"

local function v35Luma(color)
    return color.R * 0.2126 + color.G * 0.7152 + color.B * 0.0722
end

local function v35UpgradeTheme(theme)
    if type(theme) ~= "table" then return end
    local light = theme.Background and v35Luma(theme.Background) > 0.55
    -- Secondary copy needs to remain visually secondary while still readable.
    theme.Muted = light and Color3.fromRGB(88, 96, 110) or Color3.fromRGB(178, 182, 193)
end

for _, theme in pairs(AstraUI.Themes or {}) do
    v35UpgradeTheme(theme)
end
v35UpgradeTheme(DEFAULT_THEME)
v35UpgradeTheme(LIGHT_THEME)

local function v35ApplyTabState(window)
    for _, tab in ipairs(window.Tabs or {}) do
        local selected = tab == window.CurrentTab
        if tab.Button then
            tween(tab.Button, 0.14, {
                BackgroundTransparency = selected and 0.22 or 1,
            })
        end
        if tab.ButtonText then
            tween(tab.ButtonText, 0.14, {
                TextColor3 = selected and window.Theme.Text or window.Theme.Muted,
            })
        end
        v32SetTabIconColor(tab, selected and window.Theme.Accent or window.Theme.Muted)
    end
end

local _AstraV35CreateTab = Window.CreateTab
function Window:CreateTab(options)
    local tab = _AstraV35CreateTab(self, options)
    if tab.Page then
        tab.Page.ScrollBarThickness = UserInputService.TouchEnabled and 2 or 3
        tab.Page.ScrollBarImageColor3 = self.Theme.Muted
        tab.Page.ScrollBarImageTransparency = 0.35
        self._bindTheme(tab.Page, "ScrollBarImageColor3", "Muted")
        v32RegisterResponsive(self, function(_, touch)
            if not tab.Page.Parent then return end
            tab.Page.ScrollBarThickness = touch and 2 or 3
            tab.Page.ScrollBarImageTransparency = 0.35
        end)
    end
    task.defer(function()
        if not self.Destroyed then v35ApplyTabState(self) end
    end)
    return tab
end

local _AstraV35SelectTab = Window.SelectTab
function Window:SelectTab(tab)
    _AstraV35SelectTab(self, tab)
    v35ApplyTabState(self)
end

-- Dropdown selection text and chevron receive stronger contrast so the control
-- reads as interactive at a glance, especially on small screens.
local _AstraV35Dropdown = Tab._addDropdown
function Tab:_addDropdown(parent, data)
    local object = _AstraV35Dropdown(self, parent, data)
    local holder = object and object.Instance
    if holder then
        local header
        for _, child in ipairs(holder:GetChildren()) do
            if child:IsA("TextButton") then header = child break end
        end
        if header then
            for _, child in ipairs(header:GetChildren()) do
                if child:IsA("TextLabel") then
                    if child.BackgroundTransparency < 1 and child.AnchorPoint.X > 0.9 then
                        child.TextColor3 = self.Window.Theme.Text
                        self.Window._bindTheme(child, "TextColor3", "Text")
                    elseif child:GetAttribute("AstraV32ChevronGlyph") then
                        child.TextTransparency = 1
                    end
                end
            end
            for _, desc in ipairs(header:GetDescendants()) do
                if desc:IsA("Frame") and desc.Name ~= "AstraV31Icon" and desc.BackgroundTransparency < 1 then
                    local parentObj = desc.Parent
                    if parentObj and type(parentObj.GetAttribute) == "function" and parentObj:GetAttribute("AstraV32ChevronGlyph") then
                        desc.BackgroundColor3 = self.Window.Theme.Text
                    end
                end
            end
        end
    end
    return object
end

-- Stronger numeric affordance for sliders. Accent remains the state color,
-- but the value is bright enough to read without hunting for it.
local _AstraV35Slider = Tab._addSlider
function Tab:_addSlider(parent, data)
    local object = _AstraV35Slider(self, parent, data)
    local row = object and object.Instance
    if row then
        for _, child in ipairs(row:GetChildren()) do
            if child:IsA("TextLabel") and child.AnchorPoint.X > 0.9 then
                child.TextColor3 = self.Window.Theme.Accent2
                self.Window._bindTheme(child, "TextColor3", "Accent2")
                child.TextTransparency = 0
            end
        end
    end
    return object
end

-- Repaint the existing compact toggle to make OFF and ON unmistakable.
local _AstraV35Toggle = Tab._addToggle
function Tab:_addToggle(parent, data)
    local object = _AstraV35Toggle(self, parent, data)
    local row = object and object.Instance
    if not row then return object end

    local switch, knob
    for _, child in ipairs(row:GetChildren()) do
        if child:IsA("TextButton") and child.Size.X.Offset >= 38 and child.Size.X.Offset <= 48 then
            switch = child
            knob = child:FindFirstChildOfClass("Frame")
            break
        end
    end

    if switch and knob then
        local originalSet = object.Set
        local originalDisabled = object.SetDisabled
        local function repaint(animated)
            local on = object:Get() == true
            local disabled = object.IsDisabled and object:IsDisabled() or false
            local duration = animated and 0.14 or 0
            local switchColor = on and self.Window.Theme.Accent or self.Window.Theme.Surface3
            local knobColor = on and Color3.fromRGB(255,255,255) or self.Window.Theme.Muted
            local targetPos = on and UDim2.new(1,-12,0.5,0) or UDim2.fromOffset(12,12)
            if duration > 0 then
                tween(switch,duration,{BackgroundColor3=switchColor})
                tween(knob,duration,{BackgroundColor3=knobColor,Position=targetPos})
            else
                switch.BackgroundColor3=switchColor
                knob.BackgroundColor3=knobColor
                knob.Position=targetPos
            end
            switch.BackgroundTransparency = disabled and 0.35 or 0
            knob.BackgroundTransparency = disabled and 0.45 or (on and 0 or 0.12)
        end
        function object:Set(value, fireCallback)
            originalSet(self, value, fireCallback)
            repaint(true)
        end
        if originalDisabled then
            function object:SetDisabled(state)
                originalDisabled(self, state)
                repaint(false)
            end
        end
        self.Window:_connect(switch.MouseButton1Click,function()
            task.defer(function()
                if switch.Parent then repaint(true) end
            end)
        end)
        self.Window:OnThemeChanged(function()
            if switch.Parent then repaint(false) end
        end)
        repaint(false)
    end
    return object
end

-- Give rows a touch more breathing room in landscape without returning to the
-- oversized V3.2 proportions. Hit targets remain comfortably finger-sized.
local _AstraV35Row = Tab._row
function Tab:_row(parent, height)
    local row = _AstraV35Row(self, parent, height)
    local originalHeight = row.Size.Y.Offset
    v32RegisterResponsive(self.Window,function(narrow,touch)
        if not row.Parent then return end
        if touch and not narrow and v34TouchLandscape() then
            row.Size = UDim2.new(1,0,0,originalHeight + 2)
        end
    end)
    return row
end

local _AstraV35CreateSection = Tab.CreateSection
function Tab:CreateSection(options)
    local section = _AstraV35CreateSection(self, options)
    if section and section.Frame then
        for _, child in ipairs(section.Frame:GetChildren()) do
            if child:IsA("UIStroke") then child.Transparency = 0.88 end
        end
    end
    return section
end

local _AstraV35CreateWindow = AstraUI.CreateWindow
function AstraUI:CreateWindow(options)
    options = options or {}
    local window = _AstraV35CreateWindow(self, options)

    -- Custom themes passed directly through CreateWindow also receive the same
    -- readable secondary-text treatment unless the caller explicitly overrides
    -- Muted after creation.
    if window.Theme then
        v35UpgradeTheme(window.Theme)
        window:SetTheme({Muted = window.Theme.Muted})
    end

    window:OnThemeChanged(function()
        if window.Destroyed then return end
        v35ApplyTabState(window)
        for _, tab in ipairs(window.Tabs or {}) do
            if tab.Page then
                tab.Page.ScrollBarImageColor3 = window.Theme.Muted
            end
        end
    end)

    task.defer(function()
        if not window.Destroyed then v35ApplyTabState(window) end
    end)
    return window
end


AstraUI.Version = V35_VERSION

-- ============================================================================
-- AstraUI V3.6 mobile layout refinement
-- Focus: portrait composition, virtual-keyboard ergonomics, responsive right-
-- side controls and final spacing polish. Existing component API is preserved.
-- ============================================================================

local V36_VERSION = "3.6.0-executor"

local function v36Viewport()
    local camera = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(840, 550)
end

local function v36Portrait(window)
    local viewport = v36Viewport()
    return window and window._v32Narrow == true and viewport.Y > viewport.X
end

local function v36Remember(instance, key, value)
    if instance and instance:GetAttribute(key) == nil then
        instance:SetAttribute(key, value)
    end
end

local function v36TitleLabels(row)
    local result = {}
    for _, child in ipairs(row:GetChildren()) do
        if child:IsA("TextLabel") and child.BackgroundTransparency >= 0.99 and child.Position.X.Offset <= 16 then
            table.insert(result, child)
        end
    end
    return result
end

local function v36SetTitleWidth(row, narrow)
    for _, label in ipairs(v36TitleLabels(row)) do
        if label:GetAttribute("AstraV36BaseSizeXScale") == nil then
            label:SetAttribute("AstraV36BaseSizeXScale", label.Size.X.Scale)
            label:SetAttribute("AstraV36BaseSizeXOffset", label.Size.X.Offset)
        end
        if narrow then
            label.Size = UDim2.new(1, -24, label.Size.Y.Scale, label.Size.Y.Offset)
        else
            label.Size = UDim2.new(
                label:GetAttribute("AstraV36BaseSizeXScale") or 1,
                label:GetAttribute("AstraV36BaseSizeXOffset") or -120,
                label.Size.Y.Scale,
                label.Size.Y.Offset
            )
        end
    end
end

local function v36ResponsiveRightControl(window, row, control, config)
    if not (window and row and control) then return end
    config = config or {}

    local baseRowHeight = row.Size.Y.Offset
    local basePosition = control.Position
    local baseSize = control.Size
    local baseAnchor = control.AnchorPoint

    v32RegisterResponsive(window, function(narrow)
        if not row.Parent or not control.Parent then return end
        local portrait = narrow and v36Portrait(window)
        if portrait then
            row.Size = UDim2.new(1, 0, 0, config.RowHeight or 96)
            control.AnchorPoint = Vector2.new(0, 0)
            control.Position = UDim2.fromOffset(12, config.Top or 55)
            control.Size = UDim2.new(1, -24, 0, config.Height or 34)
            v36SetTitleWidth(row, true)
        else
            row.Size = UDim2.new(1, 0, 0, baseRowHeight)
            control.AnchorPoint = baseAnchor
            control.Position = basePosition
            control.Size = baseSize
            v36SetTitleWidth(row, false)
        end
    end)
end

-- Input fields use the full row width in portrait, preventing the label from
-- being squeezed beside a 190px text field on narrow phones.
local _AstraV36Input = Tab._addInput
function Tab:_addInput(parent, data)
    local object = _AstraV36Input(self, parent, data)
    local row = object and object.Instance
    if not row then
        -- Older input objects do not expose Instance. Find the last matching row.
        local children = parent:GetChildren()
        for i = #children, 1, -1 do
            local child = children[i]
            if child:IsA("Frame") and child.Size.Y.Offset >= 60 then row = child break end
        end
        if object and row then object.Instance = row end
    end
    if row then
        local holder
        for _, child in ipairs(row:GetChildren()) do
            if child:IsA("Frame") and child.AnchorPoint.X > 0.9 and child:FindFirstChildOfClass("TextBox") then
                holder = child
                break
            end
        end
        if holder then
            v36ResponsiveRightControl(self.Window, row, holder, {RowHeight = 104, Top = 56, Height = 36})
        end
    end
    return object
end

-- Keybinds become a comfortable full-width target in portrait while retaining
-- the compact desktop/landscape layout everywhere else.
local _AstraV36Keybind = Tab._addKeybind
function Tab:_addKeybind(parent, data)
    local object = _AstraV36Keybind(self, parent, data)
    local row = object and object.Instance
    if not row then
        local children = parent:GetChildren()
        for i = #children, 1, -1 do
            local child = children[i]
            if child:IsA("Frame") and child.Size.Y.Offset >= 50 then row = child break end
        end
        if object and row then object.Instance = row end
    end
    if row then
        local keyButton
        for _, child in ipairs(row:GetChildren()) do
            if child:IsA("TextButton") and child.AnchorPoint.X > 0.9 and child.Size.X.Offset >= 80 then
                keyButton = child
                break
            end
        end
        if keyButton then
            v36ResponsiveRightControl(self.Window, row, keyButton, {RowHeight = 94, Top = 52, Height = 34})
            keyButton.TextColor3 = self.Window.Theme.Text
            self.Window._bindTheme(keyButton, "TextColor3", "Text")
        end
    end
    return object
end

-- Action buttons stack below their labels on narrow portrait screens. This is
-- a layout refinement only; button behavior and API remain unchanged.
local _AstraV36Button = Tab._addButton
function Tab:_addButton(parent, data)
    local object = _AstraV36Button(self, parent, data)
    local row = object and object.Instance
    if row then
        local action
        for _, child in ipairs(row:GetChildren()) do
            if child:IsA("TextButton") and child.AnchorPoint.X > 0.9 then
                action = child
                break
            end
        end
        if action then
            local baseWidth = action.Size.X.Offset
            local baseSize = action.Size
            local basePos = action.Position
            local baseAnchor = action.AnchorPoint
            local baseHeight = row.Size.Y.Offset
            v32RegisterResponsive(self.Window, function(narrow)
                if not row.Parent or not action.Parent then return end
                local portrait = narrow and v36Portrait(self.Window)
                if portrait then
                    row.Size = UDim2.new(1,0,0,94)
                    action.AnchorPoint = Vector2.new(1,0)
                    action.Position = UDim2.new(1,-12,0,52)
                    action.Size = baseSize
                    v36SetTitleWidth(row,true)
                else
                    row.Size = UDim2.new(1,0,0,baseHeight)
                    action.AnchorPoint = baseAnchor
                    action.Position = basePos
                    action.Size = baseSize
                    v36SetTitleWidth(row,false)
                end
            end)
        end
    end
    return object
end

-- Dropdowns use a two-line portrait composition: label first, selection field
-- below. This avoids cramped titles and makes the whole selected value obvious.
local _AstraV36Dropdown = Tab._addDropdown
function Tab:_addDropdown(parent, data)
    local object = _AstraV36Dropdown(self, parent, data)
    local holder = object and object.Instance
    if not holder then return object end

    local header
    local optionsFrame
    for _, child in ipairs(holder:GetChildren()) do
        if child:IsA("TextButton") and not header then header = child end
        if child:IsA("Frame") and child.Position.Y.Offset >= 50 then optionsFrame = child end
    end
    if not header then return object end

    local display
    local chevronHost
    for _, child in ipairs(header:GetChildren()) do
        if child:IsA("TextLabel") and child.BackgroundTransparency < 1 and child.AnchorPoint.X > 0.9 then
            display = child
        elseif child:IsA("Frame") and child.AnchorPoint.X > 0.9 then
            chevronHost = child
        end
    end

    local baseHolderSize = holder.Size
    local baseHeaderSize = header.Size
    local baseDisplayPos = display and display.Position
    local baseDisplaySize = display and display.Size
    local baseDisplayAnchor = display and display.AnchorPoint
    local baseOptionsPos = optionsFrame and optionsFrame.Position

    v32RegisterResponsive(self.Window, function(narrow)
        if not holder.Parent or not header.Parent then return end
        local portrait = narrow and v36Portrait(self.Window)
        if portrait then
            holder.Size = UDim2.new(1,0,0,96)
            header.Size = UDim2.new(1,0,0,96)
            for _, label in ipairs(header:GetChildren()) do
                if label:IsA("TextLabel") and label ~= display and label.Position.X.Offset <= 16 then
                    label.Size = UDim2.new(1,-24,0,label.Size.Y.Offset)
                end
            end
            if display then
                display.AnchorPoint = Vector2.new(0,0)
                display.Position = UDim2.fromOffset(12,55)
                display.Size = UDim2.new(1,-52,0,32)
                display.TextXAlignment = Enum.TextXAlignment.Left
                local pad = display:FindFirstChildOfClass("UIPadding")
                if not pad then
                    pad = Instance.new("UIPadding")
                    pad.PaddingLeft = UDim.new(0,12)
                    pad.PaddingRight = UDim.new(0,12)
                    pad.Parent = display
                end
            end
            if chevronHost then
                chevronHost.Position = UDim2.new(1,-16,0,62)
            end
            if optionsFrame then optionsFrame.Position = UDim2.fromOffset(8,96) end
        else
            holder.Size = baseHolderSize
            header.Size = baseHeaderSize
            if display and baseDisplayPos and baseDisplaySize and baseDisplayAnchor then
                display.AnchorPoint = baseDisplayAnchor
                display.Position = baseDisplayPos
                display.Size = baseDisplaySize
                display.TextXAlignment = Enum.TextXAlignment.Center
            end
            if optionsFrame and baseOptionsPos then optionsFrame.Position = baseOptionsPos end
        end
    end)
    return object
end

local function v36FindContainingPage(window, instance)
    for _, tab in ipairs(window.Tabs or {}) do
        local page = tab.Page
        if page and instance:IsDescendantOf(page) then return page end
    end
end

local function v36ScrollFocusedIntoView(window, textBox)
    if not window._v32Narrow or not textBox or not textBox.Parent then return end
    local page = v36FindContainingPage(window, textBox)
    if not page then return end
    task.delay(0.08, function()
        if window.Destroyed or not textBox.Parent or not page.Parent then return end
        local relativeTop = textBox.AbsolutePosition.Y - page.AbsolutePosition.Y + page.CanvasPosition.Y
        local visibleTop = page.CanvasPosition.Y
        local visibleBottom = visibleTop + page.AbsoluteSize.Y
        local targetBottom = relativeTop + textBox.AbsoluteSize.Y + 22
        if relativeTop < visibleTop + 18 then
            page.CanvasPosition = Vector2.new(0, math.max(0, relativeTop - 18))
        elseif targetBottom > visibleBottom then
            page.CanvasPosition = Vector2.new(0, math.max(0, targetBottom - page.AbsoluteSize.Y))
        end
    end)
end

local function v36ApplyWindow(window)
    if window.Destroyed then return end
    local viewport = v36Viewport()
    local portrait = window._v32Narrow and viewport.Y > viewport.X

    if window._v32Narrow then
        local margin = viewport.X <= 390 and 4 or 6
        window.Root.Size = UDim2.new(1,-margin*2,1,-margin*2)
        if window.PageTitle then
            window.PageTitle.TextSize = viewport.X <= 390 and 16 or 17
        end
        if window.PageDesc then
            window.PageDesc.TextSize = 10
        end
        if window.NotificationHost then
            local notificationWidth = math.clamp(viewport.X - 20, 240, portrait and 310 or 330)
            window.NotificationHost.Size = UDim2.fromOffset(notificationWidth,0)
        end

        -- Slightly narrower drawer leaves enough context visible behind it.
        local drawerWidth = math.clamp(math.floor(viewport.X * 0.76), 214, 244)
        window._v32DrawerWidth = drawerWidth
        window.Sidebar.Size = UDim2.new(0,drawerWidth,1,0)
        if window._v32DrawerOpen then
            window.Sidebar.Position = UDim2.fromOffset(0,0)
        else
            window.Sidebar.Position = UDim2.fromOffset(-drawerWidth-8,0)
        end
    end

    v32RunResponsiveCallbacks(window)
end

local _AstraV36CreateWindow = AstraUI.CreateWindow
function AstraUI:CreateWindow(options)
    options = options or {}
    local window = _AstraV36CreateWindow(self, options)

    window:_connect(UserInputService.TextBoxFocused, function(textBox)
        if textBox and textBox:IsDescendantOf(window.ScreenGui) then
            v36ScrollFocusedIntoView(window, textBox)
        end
    end)

    local scheduled = false
    local function scheduleApply()
        if scheduled then return end
        scheduled = true
        task.defer(function()
            scheduled = false
            if not window.Destroyed then v36ApplyWindow(window) end
        end)
    end

    local cameraConnection
    local function bindCamera()
        if cameraConnection then pcall(function() cameraConnection:Disconnect() end) end
        local camera = workspace.CurrentCamera
        if camera then
            cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(scheduleApply)
            table.insert(window._connections,cameraConnection)
        end
        scheduleApply()
    end
    bindCamera()
    window:_connect(workspace:GetPropertyChangedSignal("CurrentCamera"),bindCamera)

    return window
end


-- ============================================================================
-- AstraUI V3.7.1 motion hotfix
-- Keeps V3.6/V3.5 visual language intact and adds motion that is visible on
-- touch devices without leaving hover/glow states stuck on mobile.
-- ============================================================================

local V371_VERSION = "3.7.1-executor"

local function v371EffectsEnabled(window)
    if not window or window.Destroyed then return false end
    local options = window.Options or {}
    return options.Effects ~= false and options.ReduceMotion ~= true
end

local function v371TouchLayout()
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function v371Connect(window, signal, callback)
    if window and window._connect then
        return window:_connect(signal, callback)
    end
    return signal:Connect(callback)
end

local function v371EnsureScale(gui, name)
    if not gui then return nil end
    name = name or "AstraV371Scale"
    local current = gui:FindFirstChild(name)
    if current and current:IsA("UIScale") then return current end
    local scale = Instance.new("UIScale")
    scale.Name = name
    scale.Scale = 1
    scale.Parent = gui
    return scale
end

local function v371EnsureStroke(gui, name, window, colorKey, thickness)
    if not gui then return nil end
    local current = gui:FindFirstChild(name)
    if current and current:IsA("UIStroke") then return current end
    local outline = Instance.new("UIStroke")
    outline.Name = name
    outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    outline.Color = (window.Theme and window.Theme[colorKey or "Accent"]) or Color3.new(1,1,1)
    outline.Transparency = 1
    outline.Thickness = thickness or 1
    outline:SetAttribute("AstraV371ColorKey", colorKey or "Accent")
    outline.Parent = gui
    return outline
end

local function v371CloneCorner(source, target)
    local c = source and source:FindFirstChildOfClass("UICorner")
    if c and target then
        local clone = c:Clone()
        clone.Parent = target
    elseif target then
        local fallback = Instance.new("UICorner")
        fallback.CornerRadius = UDim.new(0, 10)
        fallback.Parent = target
    end
end

local function v371EnsureOverlay(window, gui, name, colorKey)
    if not gui then return nil end
    local current = gui:FindFirstChild(name)
    if current and current:IsA("Frame") then return current end

    local overlay = Instance.new("Frame")
    overlay.Name = name
    overlay.BackgroundColor3 = window.Theme[colorKey or "Accent"] or window.Theme.Accent
    overlay.BackgroundTransparency = 1
    overlay.BorderSizePixel = 0
    overlay.Size = UDim2.fromScale(1,1)
    overlay.Position = UDim2.fromScale(0,0)
    overlay.Active = false
    overlay.ZIndex = math.max(gui.ZIndex + 1, 2)
    overlay.Parent = gui
    v371CloneCorner(gui, overlay)
    if window._bindTheme then
        window._bindTheme(overlay, "BackgroundColor3", colorKey or "Accent")
    end
    return overlay
end

local function v371TapFeedback(window, gui, options)
    if not gui or gui:GetAttribute("AstraV371TapFeedback") then return end
    gui:SetAttribute("AstraV371TapFeedback", true)
    options = options or {}

    local scale = v371EnsureScale(gui, options.ScaleName or "AstraV371TapScale")
    local overlay = v371EnsureOverlay(window, gui, options.OverlayName or "AstraV371TapOverlay", options.ColorKey or "Accent")
    local pressing = false
    local hovering = false

    local pressedScale = options.PressedScale or 0.975
    local hoverScale = options.HoverScale or 1.006
    local pressAlpha = options.PressTransparency or 0.935
    local hoverAlpha = options.HoverTransparency or 0.985

    local function paint()
        if not gui.Parent then return end
        if not v371EffectsEnabled(window) then
            scale.Scale = 1
            overlay.BackgroundTransparency = 1
            return
        end

        local targetScale = pressing and pressedScale or ((hovering and not v371TouchLayout()) and hoverScale or 1)
        local targetAlpha = pressing and pressAlpha or ((hovering and not v371TouchLayout()) and hoverAlpha or 1)
        tween(scale, pressing and 0.055 or 0.13, {Scale = targetScale}, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
        tween(overlay, pressing and 0.055 or 0.15, {BackgroundTransparency = targetAlpha}, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    end

    if not v371TouchLayout() then
        v371Connect(window, gui.MouseEnter, function()
            hovering = true
            paint()
        end)
        v371Connect(window, gui.MouseLeave, function()
            hovering = false
            pressing = false
            paint()
        end)
    end

    v371Connect(window, gui.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            pressing = true
            paint()
        end
    end)

    v371Connect(window, gui.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            pressing = false
            paint()
        end
    end)
end

local function v371AddShine(window, gui)
    if not gui or gui:GetAttribute("AstraV371Shine") then return end
    gui:SetAttribute("AstraV371Shine", true)
    gui.ClipsDescendants = true

    local shine = Instance.new("Frame")
    shine.Name = "AstraV371ShineSweep"
    shine.AnchorPoint = Vector2.new(0.5,0.5)
    shine.Position = UDim2.fromScale(-0.2,0.5)
    shine.Size = UDim2.new(0.14,0,1.75,0)
    shine.Rotation = 18
    shine.BackgroundColor3 = Color3.new(1,1,1)
    shine.BackgroundTransparency = 0.88
    shine.BorderSizePixel = 0
    shine.Active = false
    shine.ZIndex = math.max(gui.ZIndex + 3, 4)
    shine.Parent = gui

    local running = false
    local function sweep()
        if running or not v371EffectsEnabled(window) or not shine.Parent then return end
        running = true
        shine.Position = UDim2.fromScale(-0.2,0.5)
        tween(shine,0.30,{Position=UDim2.fromScale(1.2,0.5)},Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
        task.delay(0.32,function()
            if shine and shine.Parent then shine.Position=UDim2.fromScale(-0.2,0.5) end
            running=false
        end)
    end

    if gui:IsA("GuiButton") then
        v371Connect(window, gui.Activated, sweep)
    elseif not v371TouchLayout() then
        v371Connect(window, gui.MouseEnter, sweep)
    end
end

local function v371RefreshThemeEffects(window)
    if not window or window.Destroyed or not window.ScreenGui then return end
    for _, descendant in ipairs(window.ScreenGui:GetDescendants()) do
        if descendant:IsA("UIStroke") then
            local key = descendant:GetAttribute("AstraV371ColorKey")
            if key and window.Theme[key] then descendant.Color = window.Theme[key] end
        elseif descendant:IsA("Frame") then
            local key = descendant:GetAttribute("AstraV371FrameColorKey")
            if key and window.Theme[key] then descendant.BackgroundColor3 = window.Theme[key] end
        end
    end
end

local function v371DecorateRow(window, row)
    if not row or row:GetAttribute("AstraV371Row") then return end
    row:SetAttribute("AstraV371Row",true)
    -- Important: no permanent Accent stroke. On touch, MouseEnter can remain
    -- logically active and used to leave every row outlined after interaction.
    v371TapFeedback(window,row,{
        PressedScale=0.992,
        HoverScale=1.0015,
        PressTransparency=0.965,
        HoverTransparency=0.992,
        OverlayName="AstraV371RowPulse",
    })
end

local function v371DecorateSearch(window)
    local box = window.SearchBox
    local holder = box and box.Parent
    if not box or not holder or holder:GetAttribute("AstraV371Focus") then return end
    holder:SetAttribute("AstraV371Focus",true)
    local outline = v371EnsureStroke(holder,"AstraV371SearchFocus",window,"Accent",1)
    local scale = v371EnsureScale(holder,"AstraV371SearchScale")

    v371Connect(window,box.Focused,function()
        if not v371EffectsEnabled(window) then return end
        tween(outline,0.13,{Transparency=0.38})
        tween(scale,0.13,{Scale=1.008})
    end)
    v371Connect(window,box.FocusLost,function()
        tween(outline,0.13,{Transparency=1})
        tween(scale,0.13,{Scale=1})
    end)
end

local function v371DecorateTextInput(window, row)
    if not row or row:GetAttribute("AstraV371InputFocus") then return end
    local textBox = row:FindFirstChildWhichIsA("TextBox",true)
    if not textBox then return end
    local holder = textBox.Parent
    if not holder or not holder:IsA("GuiObject") then return end
    row:SetAttribute("AstraV371InputFocus",true)

    local outline = v371EnsureStroke(holder,"AstraV371InputStroke",window,"Accent",1)
    local scale = v371EnsureScale(holder,"AstraV371InputScale")
    v371Connect(window,textBox.Focused,function()
        if not v371EffectsEnabled(window) then return end
        tween(outline,0.13,{Transparency=0.34})
        tween(scale,0.13,{Scale=1.006})
    end)
    v371Connect(window,textBox.FocusLost,function()
        tween(outline,0.13,{Transparency=1})
        tween(scale,0.13,{Scale=1})
    end)
end

local function v371DecorateTopActions(window)
    for _, control in ipairs({window.SidebarButton,window.ThemeButton,window.MinimizeButton,window.CloseButton,window.MobileOpen}) do
        if control and control:IsA("GuiObject") then
            v371TapFeedback(window,control,{
                PressedScale=0.89,
                HoverScale=1.04,
                PressTransparency=0.91,
                HoverTransparency=0.98,
                OverlayName="AstraV371ActionPulse",
            })
        end
    end
end

local function v371Entrance(window)
    if not window.Root or not v371EffectsEnabled(window) then return end
    local scale = window.Scale or v371EnsureScale(window.Root,"AstraV371WindowScale")
    local finalScale = window.ResponsiveScale or scale.Scale or 1
    local finalPos = window.Root.Position
    scale.Scale = finalScale * 0.94
    window.Root.Position = UDim2.new(finalPos.X.Scale,finalPos.X.Offset,finalPos.Y.Scale,finalPos.Y.Offset + 7)
    task.defer(function()
        if window.Destroyed or not window.Root.Parent then return end
        tween(scale,0.25,{Scale=finalScale},Enum.EasingStyle.Back,Enum.EasingDirection.Out)
        tween(window.Root,0.22,{Position=finalPos},Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
    end)
end

local _AstraV371Row = Tab._row
function Tab:_row(parent,height)
    local row = _AstraV371Row(self,parent,height)
    v371DecorateRow(self.Window,row)
    return row
end

local _AstraV371Button = Tab._addButton
function Tab:_addButton(parent,data)
    local object = _AstraV371Button(self,parent,data)
    local row = object and object.Instance
    if row then
        for _, child in ipairs(row:GetChildren()) do
            if child:IsA("TextButton") and child.AnchorPoint.X > 0.9 then
                v371TapFeedback(self.Window,child,{
                    PressedScale=0.91,
                    HoverScale=1.025,
                    PressTransparency=0.96,
                    HoverTransparency=0.995,
                    OverlayName="AstraV371ButtonPulse",
                    ColorKey="Text",
                })
                v371AddShine(self.Window,child)
                break
            end
        end
    end
    return object
end

local _AstraV371Toggle = Tab._addToggle
function Tab:_addToggle(parent,data)
    local object = _AstraV371Toggle(self,parent,data)
    local row = object and object.Instance
    if not row then return object end

    local switch, knob
    for _, child in ipairs(row:GetChildren()) do
        if child:IsA("TextButton") and child.Size.X.Offset >= 38 and child.Size.X.Offset <= 60 then
            switch=child
            for _, sub in ipairs(child:GetChildren()) do
                if sub:IsA("Frame") and sub.AnchorPoint.X == 0.5 then knob=sub break end
            end
            break
        end
    end
    if not switch then return object end

    local flash = v371EnsureStroke(switch,"AstraV371ToggleFlash",self.Window,"Accent",1.35)
    local knobScale = knob and v371EnsureScale(knob,"AstraV371ToggleKnob")
    local function pulse()
        if not v371EffectsEnabled(self.Window) then return end
        flash.Transparency=0.18
        if knobScale then knobScale.Scale=0.82 end
        tween(flash,0.24,{Transparency=1},Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
        if knobScale then tween(knobScale,0.20,{Scale=1},Enum.EasingStyle.Back,Enum.EasingDirection.Out) end
    end
    v371Connect(self.Window,switch.MouseButton1Click,function() task.defer(pulse) end)
    return object
end

local _AstraV371Slider = Tab._addSlider
function Tab:_addSlider(parent,data)
    local object = _AstraV371Slider(self,parent,data)
    local row = object and object.Instance
    if not row then return object end

    local bar,knob
    for _,child in ipairs(row:GetChildren()) do
        if child:IsA("TextButton") and child.Size.X.Scale > 0.5 and child.Size.Y.Offset <= 18 then
            bar=child
            for _,sub in ipairs(child:GetChildren()) do
                if sub:IsA("Frame") and sub.AnchorPoint.X == 0.5 and sub.Size.X.Offset <= 22 then knob=sub break end
            end
            break
        end
    end
    if not bar or not knob then return object end

    local halo=v371EnsureStroke(knob,"AstraV371SliderHalo",self.Window,"Accent",2)
    local scale=v371EnsureScale(knob,"AstraV371SliderKnob")
    local function active(state)
        if not v371EffectsEnabled(self.Window) then halo.Transparency=1; scale.Scale=1; return end
        tween(halo,0.09,{Transparency=state and 0.08 or 1})
        tween(scale,0.09,{Scale=state and 1.15 or 1})
    end
    v371Connect(self.Window,bar.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then active(true) end
    end)
    v371Connect(self.Window,UserInputService.InputEnded,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then active(false) end
    end)
    if not v371TouchLayout() then
        v371Connect(self.Window,bar.MouseEnter,function() active(true) end)
        v371Connect(self.Window,bar.MouseLeave,function() active(false) end)
    end
    return object
end

local _AstraV371Dropdown = Tab._addDropdown
function Tab:_addDropdown(parent,data)
    local object = _AstraV371Dropdown(self,parent,data)
    local holder = object and object.Instance
    if not holder then return object end

    local header,optionsFrame
    for _,child in ipairs(holder:GetChildren()) do
        if child:IsA("TextButton") and not header then header=child end
        if child:IsA("Frame") and child.Position.Y.Offset >= 45 then optionsFrame=child end
    end
    if not header then return object end

    v371TapFeedback(self.Window,header,{
        PressedScale=0.995,
        HoverScale=1.001,
        PressTransparency=0.975,
        HoverTransparency=0.995,
        OverlayName="AstraV371DropdownPulse",
    })

    local chevronHost
    for _,child in ipairs(header:GetChildren()) do
        if child:IsA("Frame") and child.AnchorPoint.X > 0.9 then chevronHost=child end
    end

    local function refresh()
        if not optionsFrame then return end
        local open=optionsFrame.Visible
        if chevronHost then
            if v371EffectsEnabled(self.Window) then
                tween(chevronHost,0.18,{Rotation=open and 180 or 0},Enum.EasingStyle.Back,Enum.EasingDirection.Out)
            else
                chevronHost.Rotation=open and 180 or 0
            end
        end
    end
    if optionsFrame then
        v371Connect(self.Window,header.MouseButton1Click,function() task.defer(refresh) end)
        v371Connect(self.Window,optionsFrame:GetPropertyChangedSignal("Visible"),refresh)
        refresh()
    end
    return object
end

local _AstraV371Input = Tab._addInput
function Tab:_addInput(parent,data)
    local object = _AstraV371Input(self,parent,data)
    local row = object and object.Instance
    if row then v371DecorateTextInput(self.Window,row) end
    return object
end

local _AstraV371CreateTab = Window.CreateTab
function Window:CreateTab(options)
    local tab=_AstraV371CreateTab(self,options)
    if tab and tab.Button then
        v371TapFeedback(self,tab.Button,{
            PressedScale=0.94,
            HoverScale=1.01,
            PressTransparency=0.975,
            HoverTransparency=0.994,
            OverlayName="AstraV371TabPulse",
        })
    end
    return tab
end

local _AstraV371SelectTab = Window.SelectTab
function Window:SelectTab(tab)
    _AstraV371SelectTab(self,tab)
    if tab and tab.Button and v371EffectsEnabled(self) then
        local scale=v371EnsureScale(tab.Button,"AstraV371SelectedPulse")
        scale.Scale=0.955
        tween(scale,0.19,{Scale=1},Enum.EasingStyle.Back,Enum.EasingDirection.Out)
    end
    if tab and tab.Page and v371EffectsEnabled(self) then
        tab.Page.Position=UDim2.fromOffset(8,0)
        tween(tab.Page,0.20,{Position=UDim2.fromOffset(0,0)},Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
    end
end

local _AstraV371CreateSection = Tab.CreateSection
function Tab:CreateSection(options)
    local section=_AstraV371CreateSection(self,options)
    if section and section.Frame and v371EffectsEnabled(self.Window) then
        local scale=v371EnsureScale(section.Frame,"AstraV371SectionEntrance")
        scale.Scale=0.982
        task.defer(function()
            if scale.Parent and not self.Window.Destroyed then
                tween(scale,0.22,{Scale=1},Enum.EasingStyle.Back,Enum.EasingDirection.Out)
            end
        end)
    end
    return section
end

local _AstraV371Notify = Window.Notify
function Window:Notify(options)
    local before={}
    if self.NotificationHost then
        for _,child in ipairs(self.NotificationHost:GetChildren()) do before[child]=true end
    end
    local handle=_AstraV371Notify(self,options)
    if self.NotificationHost then
        task.defer(function()
            if self.Destroyed then return end
            for _,child in ipairs(self.NotificationHost:GetChildren()) do
                if child:IsA("Frame") and not before[child] then
                    local scale=v371EnsureScale(child,"AstraV371Notification")
                    if v371EffectsEnabled(self) then
                        scale.Scale=0.86
                        tween(scale,0.24,{Scale=1},Enum.EasingStyle.Back,Enum.EasingDirection.Out)
                    end
                    break
                end
            end
        end)
    end
    return handle
end

local _AstraV371Dialog = Window.Dialog
function Window:Dialog(options)
    local before={}
    if self.ScreenGui then for _,child in ipairs(self.ScreenGui:GetChildren()) do before[child]=true end end
    local handle=_AstraV371Dialog(self,options)
    task.defer(function()
        if self.Destroyed or not self.ScreenGui then return end
        for _,child in ipairs(self.ScreenGui:GetChildren()) do
            if not before[child] and child:IsA("TextButton") and child.ZIndex >= 190 then
                local card=child:FindFirstChildOfClass("Frame")
                if card and v371EffectsEnabled(self) then
                    local scale=v371EnsureScale(card,"AstraV371Dialog")
                    local targetTransparency=child.BackgroundTransparency
                    child.BackgroundTransparency=0.72
                    scale.Scale=0.90
                    tween(child,0.18,{BackgroundTransparency=targetTransparency},Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
                    tween(scale,0.23,{Scale=1},Enum.EasingStyle.Back,Enum.EasingDirection.Out)
                end
                break
            end
        end
    end)
    return handle
end

local _AstraV371SetTheme = Window.SetTheme
function Window:SetTheme(themePatch)
    _AstraV371SetTheme(self,themePatch)
    task.defer(function()
        if not self.Destroyed then v371RefreshThemeEffects(self) end
    end)
end

local _AstraV371CreateWindow = AstraUI.CreateWindow
function AstraUI:CreateWindow(options)
    options=options or {}
    local window=_AstraV371CreateWindow(self,options)
    v371DecorateSearch(window)
    v371DecorateTopActions(window)
    v371Entrance(window)
    v371RefreshThemeEffects(window)
    return window
end

AstraUI.Version = V371_VERSION
return AstraUI.new()
