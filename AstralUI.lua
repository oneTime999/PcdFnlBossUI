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


-- ============================================================================
-- AstraUI V3.8 Design System Refactor
-- Focus: semantic theme tokens, neutral chrome, accessibility, hierarchy,
-- responsive density, focus/scroll affordance and interaction consistency.
-- Public component API remains backwards compatible with V3.7.1.
-- ============================================================================

local V38_VERSION = "3.8.0-executor"
local GuiService = game:GetService("GuiService")

AstraUI.DesignSystem = {
    Spacing = {XS=4, SM=8, MD=12, LG=16, XL=20, XXL=24, XXXL=32},
    Radius = {SM=8, MD=10, LG=12, XL=16, Window=18, Pill=999},
    Motion = {Instant=0.08, Fast=0.12, Normal=0.18, Emphasis=0.24, Slow=0.32},
    Breakpoints = {Phone=480, Narrow=760, Tablet=980},
    TouchTarget = 44,
}

local function v38Copy(source)
    local out={}
    for k,v in pairs(source or {}) do out[k]=v end
    return out
end

local function v38Mix(a,b,t)
    t=math.clamp(tonumber(t) or 0,0,1)
    return Color3.new(
        a.R + (b.R-a.R)*t,
        a.G + (b.G-a.G)*t,
        a.B + (b.B-a.B)*t
    )
end

local function v38Linear(c)
    if c <= 0.04045 then return c/12.92 end
    return ((c+0.055)/1.055)^2.4
end

local function v38Luminance(c)
    return 0.2126*v38Linear(c.R)+0.7152*v38Linear(c.G)+0.0722*v38Linear(c.B)
end

local function v38Contrast(a,b)
    local la,lb=v38Luminance(a),v38Luminance(b)
    if la < lb then la,lb=lb,la end
    return (la+0.05)/(lb+0.05)
end

local function v38ReadableSecondary(background, preferred)
    local target = preferred or Color3.fromRGB(176,181,192)
    local light = v38Luminance(background) > 0.45
    local toward = light and Color3.fromRGB(38,43,52) or Color3.fromRGB(240,243,248)
    local i=0
    while v38Contrast(target,background) < 4.5 and i < 16 do
        target=v38Mix(target,toward,0.12)
        i+=1
    end
    return target
end

local function v38AccentText(accent)
    local white=Color3.fromRGB(255,255,255)
    local dark=Color3.fromRGB(15,17,22)
    return v38Contrast(white,accent) >= v38Contrast(dark,accent) and white or dark
end

local V38_DARK_NEUTRALS = {
    Background=Color3.fromRGB(8,10,14),
    Surface=Color3.fromRGB(12,15,20),
    Surface2=Color3.fromRGB(18,22,29),
    Surface3=Color3.fromRGB(25,30,39),
    Text=Color3.fromRGB(244,246,250),
    Muted=Color3.fromRGB(176,181,192),
    Border=Color3.fromRGB(48,54,66),
    Success=Color3.fromRGB(66,201,137),
    Warning=Color3.fromRGB(245,181,72),
    Danger=Color3.fromRGB(239,91,99),
}

local V38_LIGHT_NEUTRALS = {
    Background=Color3.fromRGB(239,242,247),
    Surface=Color3.fromRGB(255,255,255),
    Surface2=Color3.fromRGB(247,249,252),
    Surface3=Color3.fromRGB(235,239,246),
    Text=Color3.fromRGB(27,31,39),
    Muted=Color3.fromRGB(91,99,113),
    Border=Color3.fromRGB(204,211,221),
    Success=Color3.fromRGB(42,167,99),
    Warning=Color3.fromRGB(209,137,29),
    Danger=Color3.fromRGB(211,64,72),
}

local function v38Preset(neutrals,accent,accent2)
    local t=v38Copy(neutrals)
    t.Accent=accent
    t.Accent2=accent2 or v38Mix(accent,Color3.new(1,1,1),0.22)
    return t
end

-- Accent changes identity; structural surfaces stay neutral.
AstraUI.Themes.Midnight = v38Preset(V38_DARK_NEUTRALS,Color3.fromRGB(118,92,255),Color3.fromRGB(157,143,255))
AstraUI.Themes.Dark = v38Preset(V38_DARK_NEUTRALS,Color3.fromRGB(108,92,231),Color3.fromRGB(139,127,241))
AstraUI.Themes.Graphite = v38Preset(V38_DARK_NEUTRALS,Color3.fromRGB(142,126,255),Color3.fromRGB(176,165,255))
AstraUI.Themes.Ocean = v38Preset(V38_DARK_NEUTRALS,Color3.fromRGB(64,145,255),Color3.fromRGB(104,177,255))
AstraUI.Themes.Rose = v38Preset(V38_DARK_NEUTRALS,Color3.fromRGB(231,87,164),Color3.fromRGB(255,132,198))
AstraUI.Themes.Emerald = v38Preset(V38_DARK_NEUTRALS,Color3.fromRGB(57,199,146),Color3.fromRGB(94,225,177))
AstraUI.Themes.Light = v38Preset(V38_LIGHT_NEUTRALS,Color3.fromRGB(91,76,224),Color3.fromRGB(74,130,225))

local function v38NormalizeTheme(theme)
    local src=v38Copy(theme or AstraUI.Themes.Midnight)
    local base = (src.Background and v38Luminance(src.Background)>0.5) and V38_LIGHT_NEUTRALS or V38_DARK_NEUTRALS
    local t=v38Copy(base)
    for k,v in pairs(src) do t[k]=v end

    t.Muted=v38ReadableSecondary(t.Background,t.Muted)
    t.TextPrimary=t.Text
    t.TextSecondary=t.Muted
    t.SurfaceBase=t.Background
    t.SurfaceRaised=t.Surface
    t.SurfaceInteractive=t.Surface2
    t.SurfaceHover=t.Surface3
    t.BorderSubtle=v38Mix(t.Border,t.Background,0.30)
    t.AccentSoft=v38Mix(t.Surface2,t.Accent,0.13)
    t.AccentHover=v38Mix(t.Accent,Color3.new(1,1,1),0.08)
    t.AccentPressed=v38Mix(t.Accent,Color3.new(0,0,0),0.10)
    t.AccentText=v38AccentText(t.Accent)
    t.Focus=t.Accent2 or t.Accent
    t.DisabledText=v38Mix(t.Muted,t.Background,0.30)
    t.DisabledSurface=v38Mix(t.Surface2,t.Background,0.28)
    t.SuccessSoft=v38Mix(t.Surface2,t.Success,0.13)
    t.WarningSoft=v38Mix(t.Surface2,t.Warning,0.13)
    t.DangerSoft=v38Mix(t.Surface2,t.Danger,0.13)
    return t
end

for name,theme in pairs(AstraUI.Themes) do
    AstraUI.Themes[name]=v38NormalizeTheme(theme)
end

local function v38FindStroke(instance)
    if not instance then return nil end
    return instance:FindFirstChildOfClass("UIStroke")
end

local function v38SetStroke(instance,color,transparency,thickness)
    if not instance then return nil end
    local st=instance:FindFirstChild("AstraV38Border")
    if not st then
        for _,child in ipairs(instance:GetChildren()) do
            if child:IsA("UIStroke") and not string.find(child.Name,"AstraV37",1,true) and child.Name ~= "AstraV38Focus" then
                st=child
                st.Name="AstraV38Border"
                break
            end
        end
    end
    if not st then
        st=Instance.new("UIStroke")
        st.Name="AstraV38Border"
        st.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
        st.Parent=instance
    end
    if color then st.Color=color end
    if transparency~=nil then st.Transparency=transparency end
    if thickness then st.Thickness=thickness end
    return st
end

local function v38SetCorner(instance,radius)
    if not instance then return end
    local c=instance:FindFirstChildOfClass("UICorner")
    if not c then c=Instance.new("UICorner"); c.Parent=instance end
    c.CornerRadius=UDim.new(0,radius)
end

local function v38IsTouchPrimary()
    return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function v38RefreshChrome(window)
    if not window or window.Destroyed then return end
    local theme=window.Theme
    if window.Root then
        window.Root.BackgroundColor3=theme.Background
        v38SetStroke(window.Root,theme.BorderSubtle,0.50,1)
    end
    if window.Sidebar then
        window.Sidebar.BackgroundColor3=theme.Surface
    end
    if window.Main then window.Main.BackgroundColor3=theme.Background end
    if window.Footer then window.Footer.BackgroundColor3=theme.Surface2 end
    if window.FooterText then window.FooterText.TextColor3=theme.TextSecondary end
    if window.PageTitle then window.PageTitle.TextColor3=theme.TextPrimary end
    if window.PageDesc then window.PageDesc.TextColor3=theme.TextSecondary end
    if window.SearchBox then
        window.SearchBox.TextColor3=theme.TextPrimary
        window.SearchBox.PlaceholderColor3=theme.TextSecondary
        if window.SearchBox.Parent then
            window.SearchBox.Parent.BackgroundColor3=theme.Surface2
            v38SetStroke(window.SearchBox.Parent,theme.BorderSubtle,0.55,1)
        end
    end
    for _,control in ipairs({window.SidebarButton,window.ThemeButton,window.MinimizeButton,window.CloseButton}) do
        if control and control.Parent then
            control.BackgroundColor3=theme.Surface2
            control.TextColor3=theme.TextSecondary
            v38SetStroke(control,theme.BorderSubtle,0.78,1)
        end
    end
end

local function v38ApplyTabHierarchy(window)
    if not window or window.Destroyed then return end
    for _,tab in ipairs(window.Tabs or {}) do
        local selected=(tab==window.CurrentTab)
        if tab.Button then
            tab.Button.BackgroundColor3 = selected and window.Theme.AccentSoft or window.Theme.Surface
            tab.Button.BackgroundTransparency = selected and 0.06 or 1
            v38SetStroke(tab.Button,selected and window.Theme.Accent or window.Theme.BorderSubtle,selected and 0.72 or 1,1)
        end
        if tab.ButtonText then
            tab.ButtonText.TextColor3=selected and window.Theme.TextPrimary or window.Theme.TextSecondary
        end
        if tab.Indicator then
            tab.Indicator.BackgroundColor3=window.Theme.Accent
            tab.Indicator.BackgroundTransparency=selected and 0 or 1
        end
        pcall(function()
            v32SetTabIconColor(tab,selected and window.Theme.Accent or window.Theme.TextSecondary)
        end)
    end
end

-- Contextual scrollbars: hidden when there is nothing to scroll, visible while
-- scrolling, then fade back to a subtle affordance.
local function v38InstallScrollbar(window,page)
    if not page or page:GetAttribute("AstraV38Scrollbar") then return end
    page:SetAttribute("AstraV38Scrollbar",true)
    local serial=0
    local function overflow()
        local canvas=page.AbsoluteCanvasSize.Y
        local view=page.AbsoluteSize.Y
        return canvas > view + 3
    end
    local function update()
        if not page.Parent then return end
        local has=overflow()
        page.ScrollBarThickness=has and (v38IsTouchPrimary() and 2 or 3) or 0
        page.ScrollBarImageColor3=window.Theme.TextSecondary
        if has then page.ScrollBarImageTransparency=0.58 end
    end
    local function pulse()
        if not overflow() then update(); return end
        serial+=1
        local mine=serial
        page.ScrollBarImageTransparency=0.16
        task.delay(0.65,function()
            if mine==serial and page.Parent then
                tween(page,AstraUI.DesignSystem.Motion.Normal,{ScrollBarImageTransparency=0.58},Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
            end
        end)
    end
    window:_connect(page:GetPropertyChangedSignal("AbsoluteCanvasSize"),update)
    window:_connect(page:GetPropertyChangedSignal("AbsoluteSize"),update)
    window:_connect(page:GetPropertyChangedSignal("CanvasPosition"),pulse)
    update()
end

-- Central selection focus for keyboard/gamepad. Touch does not receive a fake
-- hover/focus ring. Rings are temporary and scoped to the current Astra window.
local function v38InstallFocusManager(window)
    if window._v38FocusInstalled then return end
    window._v38FocusInstalled=true
    local previous
    local function clear(obj)
        if obj and obj.Parent then
            local st=obj:FindFirstChild("AstraV38Focus")
            if st then st:Destroy() end
        end
    end
    local function apply(obj)
        clear(previous)
        previous=nil
        if not obj or not window.ScreenGui or not obj:IsDescendantOf(window.ScreenGui) then return end
        if v38IsTouchPrimary() then return end
        if not obj:IsA("GuiObject") then return end
        local st=Instance.new("UIStroke")
        st.Name="AstraV38Focus"
        st.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
        st.Color=window.Theme.Focus
        st.Thickness=2
        st.Transparency=0.12
        st.Parent=obj
        previous=obj
    end
    window:_connect(GuiService:GetPropertyChangedSignal("SelectedObject"),function()
        apply(GuiService.SelectedObject)
    end)
    window:OnUnload(function() clear(previous) end)
end

local function v38MarkSelectable(root)
    if not root then return end
    if (root:IsA("TextButton") or root:IsA("ImageButton")) and root.Visible and root.Active ~= false then
        root.Selectable=true
    end
    for _,obj in ipairs(root:GetDescendants()) do
        if obj:IsA("TextButton") or obj:IsA("ImageButton") then
            if obj.Visible and obj.Active ~= false then obj.Selectable=true end
        end
    end
end

-- V3.8 button hierarchy: existing scripts remain Primary by default.
-- Style can be "Primary", "Secondary", "Ghost" or "Danger".
local function v38StyleAction(window,button,style,disabled)
    if not button or not window then return end
    button:SetAttribute("AstraV38Role","Action")
    button:SetAttribute("AstraV38Style",tostring(style or "Primary"))
    button:SetAttribute("AstraV38Disabled",disabled == true)
    style=string.lower(tostring(style or "primary"))
    local theme=window.Theme
    local bg,textColor,strokeColor,strokeAlpha
    if disabled then
        bg=theme.DisabledSurface; textColor=theme.DisabledText; strokeColor=theme.BorderSubtle; strokeAlpha=0.82
    elseif style=="secondary" then
        bg=theme.Surface3; textColor=theme.TextPrimary; strokeColor=theme.BorderSubtle; strokeAlpha=0.52
    elseif style=="ghost" then
        bg=theme.Surface2; textColor=theme.TextSecondary; strokeColor=theme.BorderSubtle; strokeAlpha=0.82
    elseif style=="danger" then
        bg=theme.Danger; textColor=v38AccentText(theme.Danger); strokeColor=theme.Danger; strokeAlpha=0.68
    else
        bg=theme.Accent; textColor=theme.AccentText; strokeColor=theme.Accent; strokeAlpha=0.72
    end
    button.BackgroundColor3=bg
    button.TextColor3=textColor
    button.BackgroundTransparency=(style=="ghost" and not disabled) and 0.35 or 0
    v38SetStroke(button,strokeColor,strokeAlpha,1)
end

local function v38StyleRow(window,row)
    if not row or not window then return end
    row:SetAttribute("AstraV38Role","Row")
    row.BackgroundColor3=window.Theme.Surface2
    v38SetCorner(row,AstraUI.DesignSystem.Radius.LG)
    v38SetStroke(row,window.Theme.BorderSubtle,0.86,1)
    for _,child in ipairs(row:GetChildren()) do
        if child:IsA("TextLabel") then
            if child.Position.Y.Offset <= 12 then
                child.TextColor3=window.Theme.TextPrimary
            else
                child.TextColor3=window.Theme.TextSecondary
            end
        end
    end
end

local _AstraV38Row = Tab._row
function Tab:_row(parent,height)
    local row=_AstraV38Row(self,parent,height)
    v38StyleRow(self.Window,row)
    return row
end

local _AstraV38CreateSection = Tab.CreateSection
function Tab:CreateSection(options)
    local section=_AstraV38CreateSection(self,options)
    if section and section.Frame then
        section.Frame:SetAttribute("AstraV38Role","Section")
        section.Frame.BackgroundColor3=self.Window.Theme.Surface
        v38SetCorner(section.Frame,AstraUI.DesignSystem.Radius.XL)
        v38SetStroke(section.Frame,self.Window.Theme.BorderSubtle,0.92,1)
        local pad=section.Frame:FindFirstChildOfClass("UIPadding")
        if pad then
            pad.PaddingLeft=UDim.new(0,12)
            pad.PaddingRight=UDim.new(0,12)
            pad.PaddingTop=UDim.new(0,11)
            pad.PaddingBottom=UDim.new(0,11)
        end
    end
    return section
end

local _AstraV38Button = Tab._addButton
function Tab:_addButton(parent,data)
    data=data or {}
    local object=_AstraV38Button(self,parent,data)
    local row=object and object.Instance
    if not row then return object end
    local action
    for _,child in ipairs(row:GetChildren()) do
        if child:IsA("TextButton") and child.AnchorPoint.X > 0.9 then action=child; break end
    end
    if action then
        local window=self.Window
        local style=data.Style or (data.Danger and "Danger") or "Primary"
        local disabled=data.Disabled==true
        v38StyleAction(window,action,style,disabled)
        local oldSetDisabled=object.SetDisabled
        if oldSetDisabled then
            function object:SetDisabled(state)
                oldSetDisabled(self,state)
                disabled=state==true
                v38StyleAction(window,action,style,disabled)
            end
        end
        window:OnThemeChanged(function()
            if action.Parent then v38StyleAction(window,action,style,disabled) end
        end)
    end
    return object
end

-- Improve selected-value hierarchy without making the entire dropdown accent.
local _AstraV38Dropdown = Tab._addDropdown
function Tab:_addDropdown(parent,data)
    local object=_AstraV38Dropdown(self,parent,data)
    local holder=object and object.Instance
    if not holder then return object end
    local header
    for _,child in ipairs(holder:GetChildren()) do
        if child:IsA("TextButton") then header=child; break end
    end
    if header then
        for _,child in ipairs(header:GetChildren()) do
            if child:IsA("TextLabel") then
                if child.AnchorPoint.X > 0.9 and child.BackgroundTransparency < 1 then
                    child:SetAttribute("AstraV38Role","DropdownDisplay")
                    child.BackgroundColor3=self.Window.Theme.Surface3
                    child.TextColor3=self.Window.Theme.TextPrimary
                    v38SetStroke(child,self.Window.Theme.BorderSubtle,0.78,1)
                elseif child.Position.X.Offset <= 16 then
                    child.TextColor3=(child.Position.Y.Offset <= 12) and self.Window.Theme.TextPrimary or self.Window.Theme.TextSecondary
                end
            end
        end
    end
    return object
end


-- Floating dropdown/popover. It no longer expands the section when opened.
-- On narrow portrait screens it becomes a compact bottom sheet.
local function v38MakeCheck(parent, active, theme, multi)
    for _,child in ipairs(parent:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    if not active then return end
    if multi then
        local a=Instance.new("Frame")
        a.AnchorPoint=Vector2.new(0.5,0.5)
        a.Position=UDim2.fromScale(0.43,0.55)
        a.Size=UDim2.fromOffset(2,7)
        a.Rotation=-42
        a.BackgroundColor3=theme.AccentText
        a.BorderSizePixel=0
        a.ZIndex=parent.ZIndex+1
        a.Parent=parent
        local b=Instance.new("Frame")
        b.AnchorPoint=Vector2.new(0.5,0.5)
        b.Position=UDim2.fromScale(0.60,0.46)
        b.Size=UDim2.fromOffset(2,11)
        b.Rotation=43
        b.BackgroundColor3=theme.AccentText
        b.BorderSizePixel=0
        b.ZIndex=parent.ZIndex+1
        b.Parent=parent
    else
        local dot=Instance.new("Frame")
        dot.AnchorPoint=Vector2.new(0.5,0.5)
        dot.Position=UDim2.fromScale(0.5,0.5)
        dot.Size=UDim2.fromOffset(8,8)
        dot.BackgroundColor3=theme.AccentText
        dot.BorderSizePixel=0
        dot.ZIndex=parent.ZIndex+1
        v38SetCorner(dot,999)
        dot.Parent=parent
    end
end

local function v38NormalizeMulti(value)
    local out={}
    if type(value)~="table" then return out end
    if #value>0 then
        for _,item in ipairs(value) do out[tostring(item)]=true end
    else
        for item,enabled in pairs(value) do if enabled then out[tostring(item)]=true end end
    end
    return out
end

function Tab:_addDropdown(parent,data)
    data=data or {}
    local window=self.Window
    local values=data.Options or data.Values or {}
    local multi=data.Multi==true
    local flag=data.Flag
    local disabled=data.Disabled==true
    local defaultValue=data.Default
    local selected=multi and v38NormalizeMulti(defaultValue) or defaultValue
    if flag and window.Flags[flag]~=nil then
        selected=multi and v38NormalizeMulti(window.Flags[flag]) or window.Flags[flag]
    end

    local row=self:_row(parent,64)
    row:SetAttribute("AstraV38Dropdown",true)
    self:_titleBlock(row,data,250)

    local header=Instance.new("TextButton")
    header.Name="Header"
    header.Size=UDim2.fromScale(1,1)
    header.BackgroundTransparency=1
    header.Text=""
    header.AutoButtonColor=false
    header.Selectable=true
    header.ZIndex=4
    header.Parent=row

    local display=Instance.new("TextLabel")
    display.Name="SelectedValue"
    display.AnchorPoint=Vector2.new(1,0.5)
    display.Position=UDim2.new(1,-44,0.5,0)
    display.Size=UDim2.fromOffset(190,34)
    display.BackgroundColor3=window.Theme.Surface3
    display.BorderSizePixel=0
    display.TextColor3=window.Theme.TextPrimary
    display.TextSize=11
    display.TextXAlignment=Enum.TextXAlignment.Center
    display.Font=Enum.Font.Gotham
    display.TextTruncate=Enum.TextTruncate.AtEnd
    display.ZIndex=5
    display.Parent=header
    display:SetAttribute("AstraV38Role","DropdownDisplay")
    v38SetCorner(display,AstraUI.DesignSystem.Radius.MD)
    v38SetStroke(display,window.Theme.BorderSubtle,0.76,1)

    local chevron=Instance.new("Frame")
    chevron.Name="Chevron"
    chevron.AnchorPoint=Vector2.new(1,0.5)
    chevron.Position=UDim2.new(1,-14,0.5,0)
    chevron.Size=UDim2.fromOffset(18,18)
    chevron.BackgroundTransparency=1
    chevron.ZIndex=6
    chevron.Parent=header
    local c1=Instance.new("Frame")
    c1.AnchorPoint=Vector2.new(0.5,0.5)
    c1.Position=UDim2.fromOffset(6,8)
    c1.Size=UDim2.fromOffset(7,1)
    c1.Rotation=42
    c1.BackgroundColor3=window.Theme.TextSecondary
    c1.BorderSizePixel=0
    c1.ZIndex=7
    c1.Parent=chevron
    local c2=Instance.new("Frame")
    c2.AnchorPoint=Vector2.new(0.5,0.5)
    c2.Position=UDim2.fromOffset(11,8)
    c2.Size=UDim2.fromOffset(7,1)
    c2.Rotation=-42
    c2.BackgroundColor3=window.Theme.TextSecondary
    c2.BorderSizePixel=0
    c2.ZIndex=7
    c2.Parent=chevron

    local overlay=Instance.new("TextButton")
    overlay.Name="AstraV38DropdownOverlay"
    overlay.Size=UDim2.fromScale(1,1)
    overlay.Position=UDim2.fromScale(0,0)
    overlay.BackgroundColor3=Color3.new(0,0,0)
    overlay.BackgroundTransparency=1
    overlay.BorderSizePixel=0
    overlay.Text=""
    overlay.AutoButtonColor=false
    overlay.Visible=false
    overlay.ZIndex=160
    overlay.Parent=window.ScreenGui

    local popover=Instance.new("Frame")
    popover.Name="Popover"
    popover.BackgroundColor3=window.Theme.Surface
    popover.BorderSizePixel=0
    popover.ClipsDescendants=true
    popover.ZIndex=161
    popover.Parent=overlay
    v38SetCorner(popover,AstraUI.DesignSystem.Radius.XL)
    v38SetStroke(popover,window.Theme.BorderSubtle,0.35,1)

    local top=Instance.new("Frame")
    top.Name="Top"
    top.BackgroundTransparency=1
    top.Position=UDim2.fromOffset(10,10)
    top.Size=UDim2.new(1,-20,0,0)
    top.ZIndex=162
    top.Parent=popover

    local searchBox
    local searchable=data.Searchable==true or #values>=8
    if searchable then
        local searchHolder=Instance.new("Frame")
        searchHolder.Name="SearchHolder"
        searchHolder.Size=UDim2.new(1,0,0,36)
        searchHolder.BackgroundColor3=window.Theme.Surface2
        searchHolder.BorderSizePixel=0
        searchHolder.ZIndex=163
        searchHolder.Parent=top
        v38SetCorner(searchHolder,AstraUI.DesignSystem.Radius.MD)
        v38SetStroke(searchHolder,window.Theme.BorderSubtle,0.72,1)
        searchBox=Instance.new("TextBox")
        searchBox.BackgroundTransparency=1
        searchBox.Position=UDim2.fromOffset(11,0)
        searchBox.Size=UDim2.new(1,-22,1,0)
        searchBox.ClearTextOnFocus=false
        searchBox.PlaceholderText=data.SearchPlaceholder or "Search options..."
        searchBox.PlaceholderColor3=window.Theme.TextSecondary
        searchBox.Text=""
        searchBox.TextColor3=window.Theme.TextPrimary
        searchBox.TextSize=11
        searchBox.TextXAlignment=Enum.TextXAlignment.Left
        searchBox.Font=Enum.Font.Gotham
        searchBox.ZIndex=164
        searchBox.Parent=searchHolder
        top.Size=UDim2.new(1,-20,0,36)
    end

    local actions
    if multi then
        actions=Instance.new("Frame")
        actions.Name="Actions"
        actions.BackgroundTransparency=1
        actions.Position=UDim2.fromOffset(0,searchable and 44 or 0)
        actions.Size=UDim2.new(1,0,0,30)
        actions.ZIndex=163
        actions.Parent=top
        top.Size=UDim2.new(1,-20,0,(searchable and 44 or 0)+30)
    end

    local list=Instance.new("ScrollingFrame")
    list.Name="Options"
    list.BackgroundTransparency=1
    list.BorderSizePixel=0
    list.CanvasSize=UDim2.new()
    list.AutomaticCanvasSize=Enum.AutomaticSize.Y
    list.ScrollBarThickness=v38IsTouchPrimary() and 2 or 3
    list.ScrollBarImageColor3=window.Theme.TextSecondary
    list.ScrollBarImageTransparency=0.55
    list.ScrollingDirection=Enum.ScrollingDirection.Y
    list.ElasticBehavior=Enum.ElasticBehavior.WhenScrollable
    list.ZIndex=162
    list.Parent=popover
    local listLayout=Instance.new("UIListLayout")
    listLayout.Padding=UDim.new(0,6)
    listLayout.SortOrder=Enum.SortOrder.LayoutOrder
    listLayout.Parent=list

    local optionRows={}
    local open=false
    local query=""

    local function chosenCount()
        local n=0
        if multi then for _,enabled in pairs(selected) do if enabled then n+=1 end end end
        return n
    end

    local function selectionText()
        if not multi then
            return selected~=nil and tostring(selected) or (data.Placeholder or "Select")
        end
        local chosen={}
        for _,option in ipairs(values) do
            local key=tostring(option)
            if selected[key] then table.insert(chosen,key) end
        end
        if #chosen==0 then return data.Placeholder or "None selected" end
        if #chosen<=2 then return table.concat(chosen,", ") end
        return tostring(#chosen).." selected"
    end

    local function fire()
        if flag then window.Flags[flag]=selected end
        safeCall(data.Callback,selected)
    end

    local function refreshDisplay()
        display.Text=selectionText()
    end

    local function refreshTheme()
        row.BackgroundColor3=window.Theme.Surface2
        popover.BackgroundColor3=window.Theme.Surface
        display.BackgroundColor3=window.Theme.Surface3
        display.TextColor3=window.Theme.TextPrimary
        c1.BackgroundColor3=window.Theme.TextSecondary
        c2.BackgroundColor3=window.Theme.TextSecondary
        v38SetStroke(popover,window.Theme.BorderSubtle,0.35,1)
        v38SetStroke(display,window.Theme.BorderSubtle,0.76,1)
        if searchBox then
            searchBox.TextColor3=window.Theme.TextPrimary
            searchBox.PlaceholderColor3=window.Theme.TextSecondary
            searchBox.Parent.BackgroundColor3=window.Theme.Surface2
            v38SetStroke(searchBox.Parent,window.Theme.BorderSubtle,0.72,1)
        end
        for _,entry in pairs(optionRows) do
            if entry.Button and entry.Button.Parent then
                local active=multi and selected[entry.Value] or tostring(selected)==entry.Value
                entry.Button.BackgroundColor3=active and window.Theme.AccentSoft or window.Theme.Surface2
                entry.Label.TextColor3=active and window.Theme.TextPrimary or window.Theme.TextSecondary
                entry.Check.BackgroundColor3=active and window.Theme.Accent or window.Theme.Surface3
                v38SetStroke(entry.Check,active and window.Theme.Accent or window.Theme.BorderSubtle,active and 0.28 or 0.68,1)
                v38MakeCheck(entry.Check,active,window.Theme,multi)
            end
        end
    end

    local function rebuild()
        for _,child in ipairs(list:GetChildren()) do
            if child:IsA("TextButton") or child.Name=="AstraV38EmptyOption" then child:Destroy() end
        end
        optionRows={}
        local lower=string.lower(query)
        local visibleCount=0
        for _,option in ipairs(values) do
            local value=tostring(option)
            local show=lower=="" or string.find(string.lower(value),lower,1,true)~=nil
            if show then
                visibleCount+=1
                local item=Instance.new("TextButton")
                item.AutoButtonColor=false
                item.Selectable=true
                item.Size=UDim2.new(1,0,0,36)
                item.BackgroundColor3=window.Theme.Surface2
                item.BorderSizePixel=0
                item.Text=""
                item.ZIndex=163
                item.Parent=list
                v38SetCorner(item,AstraUI.DesignSystem.Radius.MD)

                local label=Instance.new("TextLabel")
                label.BackgroundTransparency=1
                label.Position=UDim2.fromOffset(11,0)
                label.Size=UDim2.new(1,-48,1,0)
                label.Text=value
                label.TextColor3=window.Theme.TextSecondary
                label.TextSize=11
                label.TextXAlignment=Enum.TextXAlignment.Left
                label.Font=Enum.Font.Gotham
                label.TextTruncate=Enum.TextTruncate.AtEnd
                label.ZIndex=164
                label.Parent=item

                local check=Instance.new("Frame")
                check.AnchorPoint=Vector2.new(1,0.5)
                check.Position=UDim2.new(1,-10,0.5,0)
                check.Size=UDim2.fromOffset(18,18)
                check.BackgroundColor3=window.Theme.Surface3
                check.BorderSizePixel=0
                check.ZIndex=164
                check.Parent=item
                v38SetCorner(check,multi and 5 or 999)
                v38SetStroke(check,window.Theme.BorderSubtle,0.68,1)

                optionRows[value]={Button=item,Label=label,Check=check,Value=value}
                window:_connect(item.MouseButton1Click,function()
                    if disabled then return end
                    if multi then
                        selected[value]=not selected[value]
                    else
                        selected=value
                    end
                    refreshDisplay()
                    refreshTheme()
                    fire()
                    if not multi then
                        open=false
                        overlay.Visible=false
                        if v371EffectsEnabled(window) then tween(chevron,AstraUI.DesignSystem.Motion.Normal,{Rotation=0}) else chevron.Rotation=0 end
                    end
                end)
            end
        end
        if visibleCount==0 then
            local empty=Instance.new("TextLabel")
            empty.Name="AstraV38EmptyOption"
            empty.BackgroundTransparency=1
            empty.Size=UDim2.new(1,0,0,44)
            empty.Text="No results"
            empty.TextColor3=window.Theme.TextSecondary
            empty.TextSize=11
            empty.Font=Enum.Font.Gotham
            empty.ZIndex=163
            empty.Parent=list
            task.delay(0,function()
                if empty.Parent and query~="" then return end
            end)
        end
        refreshTheme()
    end

    local function layoutPopover()
        if not workspace.CurrentCamera then return end
        local viewport=workspace.CurrentCamera.ViewportSize
        local portrait=viewport.X < AstraUI.DesignSystem.Breakpoints.Phone or viewport.X < viewport.Y*0.78
        local topHeight=top.Size.Y.Offset
        local count=0
        local lower=string.lower(query)
        for _,option in ipairs(values) do
            if lower=="" or string.find(string.lower(tostring(option)),lower,1,true) then count+=1 end
        end
        local listHeight=math.clamp(count*42,48,portrait and 260 or 230)
        local height=math.clamp(20+topHeight+8+listHeight,120,portrait and math.min(360,viewport.Y-20) or 330)
        local width
        local x,y
        if portrait then
            width=math.clamp(viewport.X-16,260,420)
            x=math.floor((viewport.X-width)/2)
            y=math.max(8,viewport.Y-height-8)
            overlay.BackgroundTransparency=0.62
        else
            width=math.clamp(math.max(260,header.AbsoluteSize.X*0.42),260,340)
            x=math.clamp(header.AbsolutePosition.X+header.AbsoluteSize.X-width,8,viewport.X-width-8)
            local below=header.AbsolutePosition.Y+header.AbsoluteSize.Y+6
            if below+height <= viewport.Y-8 then y=below else y=math.max(8,header.AbsolutePosition.Y-height-6) end
            overlay.BackgroundTransparency=1
        end
        popover.Position=UDim2.fromOffset(x,y)
        popover.Size=UDim2.fromOffset(width,height)
        list.Position=UDim2.fromOffset(10,10+topHeight+8)
        list.Size=UDim2.new(1,-20,1,-(20+topHeight+8))
    end

    local function close()
        if not open then return end
        open=false
        if v371EffectsEnabled(window) then
            tween(chevron,AstraUI.DesignSystem.Motion.Normal,{Rotation=0},Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
            local sc=popover:FindFirstChild("AstraV38PopoverScale")
            if sc then tween(sc,AstraUI.DesignSystem.Motion.Fast,{Scale=0.97}) end
            task.delay(AstraUI.DesignSystem.Motion.Fast,function()
                if not open and overlay.Parent then overlay.Visible=false end
            end)
        else
            chevron.Rotation=0
            overlay.Visible=false
        end
    end

    local function openDropdown()
        if disabled or open then return end
        open=true
        query=""
        if searchBox then searchBox.Text="" end
        rebuild()
        layoutPopover()
        overlay.Visible=true
        local sc=popover:FindFirstChild("AstraV38PopoverScale") or Instance.new("UIScale")
        sc.Name="AstraV38PopoverScale"
        sc.Parent=popover
        if v371EffectsEnabled(window) then
            sc.Scale=0.97
            tween(sc,AstraUI.DesignSystem.Motion.Normal,{Scale=1},Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
            tween(chevron,AstraUI.DesignSystem.Motion.Normal,{Rotation=180},Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
        else
            sc.Scale=1
            chevron.Rotation=180
        end
    end

    if actions then
        local selectAll=Instance.new("TextButton")
        selectAll.AutoButtonColor=false
        selectAll.Size=UDim2.fromOffset(88,30)
        selectAll.BackgroundColor3=window.Theme.Surface3
        selectAll.BorderSizePixel=0
        selectAll.Text="Select all"
        selectAll.TextColor3=window.Theme.TextPrimary
        selectAll.TextSize=10
        selectAll.Font=Enum.Font.GothamMedium
        selectAll.ZIndex=164
        selectAll.Parent=actions
        v38SetCorner(selectAll,AstraUI.DesignSystem.Radius.SM)
        local clear=selectAll:Clone()
        clear.Text="Clear"
        clear.AnchorPoint=Vector2.new(1,0)
        clear.Position=UDim2.new(1,0,0,0)
        clear.Parent=actions
        window:_connect(selectAll.MouseButton1Click,function()
            if disabled then return end
            for _,option in ipairs(values) do selected[tostring(option)]=true end
            refreshDisplay(); refreshTheme(); fire()
        end)
        window:_connect(clear.MouseButton1Click,function()
            if disabled then return end
            selected={}
            refreshDisplay(); refreshTheme(); fire()
        end)
    end

    window:_connect(header.MouseButton1Click,function()
        if open then close() else openDropdown() end
    end)
    window:_connect(overlay.MouseButton1Click,close)
    window:_connect(UserInputService.InputBegan,function(input,processed)
        if processed then return end
        if open and input.KeyCode==Enum.KeyCode.Escape then close() end
    end)
    if searchBox then
        window:_connect(searchBox:GetPropertyChangedSignal("Text"),function()
            query=searchBox.Text or ""
            rebuild(); layoutPopover()
        end)
    end
    if workspace.CurrentCamera then
        window:_connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"),function()
            if open then layoutPopover() end
        end)
    end

    v32RegisterResponsive(window,function(narrow)
        if not row.Parent then return end
        local portrait=narrow and v36Portrait(window)
        if portrait then
            row.Size=UDim2.new(1,0,0,96)
            display.AnchorPoint=Vector2.new(0,0)
            display.Position=UDim2.fromOffset(12,55)
            display.Size=UDim2.new(1,-52,0,32)
            display.TextXAlignment=Enum.TextXAlignment.Left
            local pad=display:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
            pad.PaddingLeft=UDim.new(0,12); pad.PaddingRight=UDim.new(0,12); pad.Parent=display
            chevron.Position=UDim2.new(1,-16,0,62)
            for _,label in ipairs(row:GetChildren()) do
                if label:IsA("TextLabel") and label~=display and label.Position.X.Offset<=16 then
                    label.Size=UDim2.new(1,-24,0,label.Size.Y.Offset)
                end
            end
        else
            row.Size=UDim2.new(1,0,0,64)
            display.AnchorPoint=Vector2.new(1,0.5)
            display.Position=UDim2.new(1,-44,0.5,0)
            display.Size=UDim2.fromOffset(190,34)
            display.TextXAlignment=Enum.TextXAlignment.Center
            chevron.Position=UDim2.new(1,-14,0.5,0)
        end
        if open then task.defer(layoutPopover) end
    end)

    local object={Instance=row}
    function object:Set(newValue,fireCallback)
        if multi then selected=v38NormalizeMulti(newValue) else selected=newValue end
        if flag then window.Flags[flag]=selected end
        refreshDisplay(); refreshTheme()
        if fireCallback~=false then safeCall(data.Callback,selected) end
    end
    function object:Get() return selected end
    function object:GetDefault() return defaultValue end
    function object:Refresh(newValues)
        values=newValues or {}
        rebuild(); refreshDisplay()
        if open then layoutPopover() end
    end
    function object:SetDisabled(state)
        disabled=state==true
        header.Active=not disabled
        row.BackgroundTransparency=disabled and 0.35 or 0
        display.TextTransparency=disabled and 0.42 or 0
        if disabled then close() end
    end
    function object:IsDisabled() return disabled end
    function object:_sync(newValue) self:Set(newValue,true) end
    function object:_close() close() end

    if flag then
        window.Flags[flag]=selected
        window.FlagObjects[flag]=object
    end
    window._v38Popovers=window._v38Popovers or {}
    table.insert(window._v38Popovers,object)
    window:OnThemeChanged(function()
        if row.Parent then refreshTheme() end
    end)
    refreshDisplay(); rebuild(); object:SetDisabled(disabled)
    return object
end

local _AstraV38Input = Tab._addInput
function Tab:_addInput(parent,data)
    local object=_AstraV38Input(self,parent,data)
    local row=object and object.Instance
    if row then
        local box=row:FindFirstChildWhichIsA("TextBox",true)
        if box then
            box.TextColor3=self.Window.Theme.TextPrimary
            box.PlaceholderColor3=self.Window.Theme.TextSecondary
            if box.Parent and box.Parent:IsA("GuiObject") then
                box.Parent:SetAttribute("AstraV38Role","InputHolder")
                box.Parent.BackgroundColor3=self.Window.Theme.Surface3
                v38SetStroke(box.Parent,self.Window.Theme.BorderSubtle,0.76,1)
            end
        end
    end
    return object
end

local _AstraV38Slider = Tab._addSlider
function Tab:_addSlider(parent,data)
    local object=_AstraV38Slider(self,parent,data)
    local row=object and object.Instance
    if row then
        for _,child in ipairs(row:GetChildren()) do
            if child:IsA("TextLabel") and child.AnchorPoint.X > 0.9 then
                child.TextColor3=self.Window.Theme.Accent2
            end
        end
    end
    return object
end

local function v38RefreshComponents(window)
    if not window or window.Destroyed or not window.ScreenGui then return end
    for _,obj in ipairs(window.ScreenGui:GetDescendants()) do
        if obj:IsA("GuiObject") then
            local role=obj:GetAttribute("AstraV38Role")
            if role=="Row" then
                v38StyleRow(window,obj)
            elseif role=="Section" then
                obj.BackgroundColor3=window.Theme.Surface
                v38SetStroke(obj,window.Theme.BorderSubtle,0.92,1)
            elseif role=="Action" and obj:IsA("TextButton") then
                v38StyleAction(window,obj,obj:GetAttribute("AstraV38Style"),obj:GetAttribute("AstraV38Disabled") == true)
            elseif role=="DropdownDisplay" and obj:IsA("TextLabel") then
                obj.BackgroundColor3=window.Theme.Surface3
                obj.TextColor3=window.Theme.TextPrimary
                v38SetStroke(obj,window.Theme.BorderSubtle,0.78,1)
            elseif role=="InputHolder" then
                obj.BackgroundColor3=window.Theme.Surface3
                v38SetStroke(obj,window.Theme.BorderSubtle,0.76,1)
                local box=obj:FindFirstChildWhichIsA("TextBox",true)
                if box then
                    box.TextColor3=window.Theme.TextPrimary
                    box.PlaceholderColor3=window.Theme.TextSecondary
                end
            end
        end
    end
end

local _AstraV38CreateTab = Window.CreateTab
function Window:CreateTab(options)
    local tab=_AstraV38CreateTab(self,options)
    if tab and tab.Page then
        v38InstallScrollbar(self,tab.Page)
    end
    task.defer(function()
        if not self.Destroyed then
            v38ApplyTabHierarchy(self)
            v38MarkSelectable(tab and tab.Button)
        end
    end)
    return tab
end

local _AstraV38SelectTab = Window.SelectTab
function Window:SelectTab(tab)
    for _,popover in ipairs(self._v38Popovers or {}) do
        if popover and popover._close then pcall(popover._close,popover) end
    end
    _AstraV38SelectTab(self,tab)
    v38ApplyTabHierarchy(self)
end

local _AstraV38SetTheme = Window.SetTheme
function Window:SetTheme(themePatch)
    local merged=v38Copy(self.Theme or AstraUI.Themes.Midnight)
    for k,v in pairs(themePatch or {}) do merged[k]=v end
    local normalized=v38NormalizeTheme(merged)
    _AstraV38SetTheme(self,normalized)
    self.Theme=normalized
    task.defer(function()
        if self.Destroyed then return end
        v38RefreshChrome(self)
        v38RefreshComponents(self)
        v38ApplyTabHierarchy(self)
    end)
end

function Window:SetThemePreset(name)
    local preset=AstraUI.Themes[tostring(name or "")]
    if not preset then return false,"Unknown theme preset" end
    self._darkTheme=v38Copy(preset)
    self:SetTheme(preset)
    return true
end

-- Density changes geometry, not theme. This avoids the old practice of scaling
-- the entire window down until text becomes hard to read.
function Window:SetDensity(mode)
    mode=string.lower(tostring(mode or "comfortable"))
    local compact=mode=="compact"
    self.Density=compact and "Compact" or "Comfortable"
    for _,tab in ipairs(self.Tabs or {}) do
        if tab.Page then
            local layout=tab.Page:FindFirstChildOfClass("UIListLayout")
            if layout then layout.Padding=UDim.new(0,compact and 8 or 12) end
            local pad=tab.Page:FindFirstChildOfClass("UIPadding")
            if pad then
                pad.PaddingLeft=UDim.new(0,compact and 14 or 18)
                pad.PaddingRight=UDim.new(0,compact and 14 or 18)
                pad.PaddingTop=UDim.new(0,compact and 10 or 14)
                pad.PaddingBottom=UDim.new(0,compact and 10 or 14)
            end
        end
    end
    return self.Density
end

function Window:GetDesignTokens()
    return AstraUI.DesignSystem
end

function Window:SetAccent(color, accent2)
    if typeof(color) ~= "Color3" then return false,"Accent must be a Color3" end
    self:SetTheme({
        Accent=color,
        Accent2=(typeof(accent2)=="Color3") and accent2 or v38Mix(color,Color3.new(1,1,1),0.22),
    })
    return true
end

function AstraUI:CreateTheme(options)
    options=options or {}
    local baseName=tostring(options.Base or "Midnight")
    local base=AstraUI.Themes[baseName] or AstraUI.Themes.Midnight
    local theme=v38Copy(base)
    if typeof(options.Accent)=="Color3" then
        theme.Accent=options.Accent
        theme.Accent2=(typeof(options.Accent2)=="Color3") and options.Accent2 or v38Mix(options.Accent,Color3.new(1,1,1),0.22)
    end
    for key,value in pairs(options.Override or {}) do theme[key]=value end
    return v38NormalizeTheme(theme)
end

function AstraUI:AuditTheme(theme)
    local t=v38NormalizeTheme(theme or AstraUI.Themes.Midnight)
    local textRatio=v38Contrast(t.TextPrimary,t.Background)
    local secondaryRatio=v38Contrast(t.TextSecondary,t.Background)
    local accentOnSurface=v38Contrast(t.Accent,t.Surface2)
    local accentTextRatio=v38Contrast(t.AccentText,t.Accent)
    return {
        TextContrast=textRatio,
        SecondaryContrast=secondaryRatio,
        AccentContrast=accentOnSurface,
        AccentTextContrast=accentTextRatio,
        TextPass=textRatio>=4.5,
        SecondaryPass=secondaryRatio>=4.5,
        ComponentPass=accentOnSurface>=3,
        AccentTextPass=accentTextRatio>=4.5,
    }
end

-- Notification width tracks the viewport instead of assuming desktop width.
local _AstraV38Notify = Window.Notify
function Window:Notify(options)
    if self.NotificationHost and workspace.CurrentCamera then
        local w=workspace.CurrentCamera.ViewportSize.X
        local target=math.clamp(math.floor(w-24),260,330)
        self.NotificationHost.Size=UDim2.fromOffset(target,0)
    end
    return _AstraV38Notify(self,options)
end

local _AstraV38CreateWindow = AstraUI.CreateWindow
function AstraUI:CreateWindow(options)
    options=options or {}
    local prepared={}
    for k,v in pairs(options) do prepared[k]=v end
    if prepared.Theme then
        local base=v38Copy(AstraUI.Themes.Midnight)
        for k,v in pairs(prepared.Theme) do base[k]=v end
        prepared.Theme=v38NormalizeTheme(base)
    else
        prepared.Theme=v38Copy(AstraUI.Themes.Midnight)
    end

    local window=_AstraV38CreateWindow(self,prepared)
    window.Theme=v38NormalizeTheme(window.Theme)
    v38RefreshChrome(window)
    v38RefreshComponents(window)
    v38ApplyTabHierarchy(window)
    v38InstallFocusManager(window)
    v38MarkSelectable(window.Root)

    if prepared.Density then
        task.defer(function()
            if not window.Destroyed then window:SetDensity(prepared.Density) end
        end)
    end

    local function refreshViewport()
        if window.Destroyed then return end
        if window.NotificationHost and workspace.CurrentCamera then
            local vw=workspace.CurrentCamera.ViewportSize.X
            window.NotificationHost.Size=UDim2.fromOffset(math.clamp(math.floor(vw-24),260,330),0)
        end
        for _,tab in ipairs(window.Tabs or {}) do
            if tab.Page then
                local has=tab.Page.AbsoluteCanvasSize.Y > tab.Page.AbsoluteSize.Y + 3
                tab.Page.ScrollBarThickness=has and (v38IsTouchPrimary() and 2 or 3) or 0
            end
        end
    end
    if workspace.CurrentCamera then
        window:_connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"),refreshViewport)
    end
    window:_connect(workspace:GetPropertyChangedSignal("CurrentCamera"),function()
        task.defer(refreshViewport)
    end)
    task.defer(refreshViewport)
    return window
end


;(function()
-- ============================================================================
-- AstraUI V3.9 Precision & Adaptive Polish
-- Focus: viewport-safe popovers, deterministic page scroll state, compact
-- navigation tooltips, refined action hierarchy, light-theme quality,
-- typography/padding rhythm and small-screen robustness.
-- ============================================================================

local V39_VERSION = "3.9.0-executor"

AstraUI.DesignSystem.Type = {
    PageTitle = 18,
    PageDescription = 11,
    SectionTitle = 13,
    ControlTitle = 12,
    Description = 10,
    Caption = 9,
}
AstraUI.DesignSystem.Elevation = {
    None = 0,
    Raised = 1,
    Popover = 2,
    Modal = 3,
}
AstraUI.DesignSystem.Layout = {
    PageBottomPadding = 24,
    PageSideDesktop = 18,
    PageSideTouch = 14,
    PageSidePhone = 12,
    PopoverMargin = 12,
    PopoverMaxWidth = 380,
    BottomSheetMaxWidth = 520,
}

local function v39MinContrast(color, backgrounds)
    local value = math.huge
    for _, bg in ipairs(backgrounds) do
        value = math.min(value, v38Contrast(color, bg))
    end
    return value
end

local function v39ReadableAcross(theme, preferred, targetRatio)
    targetRatio = tonumber(targetRatio) or 4.5
    local light = v38Luminance(theme.Background) > 0.45
    local toward = light and Color3.fromRGB(31, 36, 44) or Color3.fromRGB(245, 247, 251)
    local result = preferred
    local backgrounds = {theme.Background, theme.Surface, theme.Surface2, theme.Surface3}
    local i = 0
    while v39MinContrast(result, backgrounds) < targetRatio and i < 24 do
        result = v38Mix(result, toward, 0.10)
        i += 1
    end
    return result
end

local function v39NormalizeTheme(theme)
    local t = v38NormalizeTheme(theme)
    t.TextSecondary = v39ReadableAcross(t, t.TextSecondary or t.Muted, 4.5)
    t.Muted = t.TextSecondary
    t.TextTertiary = v38Mix(t.TextSecondary, t.Background, 0.18)

    t.SurfaceSunken = v38Mix(t.Background, t.Surface2, 0.42)
    t.SurfaceSelected = v38Mix(t.Surface2, t.Accent, 0.10)
    t.SurfacePressed = v38Mix(t.Surface3, t.Accent, 0.07)

    t.BorderSubtle = v38Mix(t.Border, t.Background, 0.38)
    t.BorderDefault = v38Mix(t.Border, t.TextSecondary, 0.08)
    t.BorderStrong = v38Mix(t.Border, t.TextPrimary, 0.18)

    t.AccentSoft = v38Mix(t.Surface2, t.Accent, 0.11)
    t.AccentHover = v38Mix(t.Accent, Color3.new(1,1,1), 0.07)
    t.AccentPressed = v38Mix(t.Accent, Color3.new(0,0,0), 0.12)
    t.AccentText = v38AccentText(t.Accent)

    t.Focus = t.Accent2 or t.Accent
    t.Scrollbar = v38Mix(t.TextSecondary, t.Background, 0.10)
    t.Shadow = Color3.fromRGB(0,0,0)

    t.DisabledText = v38Mix(t.TextSecondary, t.Background, 0.38)
    t.DisabledSurface = v38Mix(t.Surface2, t.Background, 0.34)

    t.SuccessSoft = v38Mix(t.Surface2, t.Success, 0.11)
    t.WarningSoft = v38Mix(t.Surface2, t.Warning, 0.11)
    t.DangerSoft = v38Mix(t.Surface2, t.Danger, 0.11)
    return t
end

-- Light is treated as its own visual system rather than a simple inversion.
AstraUI.Themes.Light = v39NormalizeTheme({
    Background = Color3.fromRGB(244, 246, 250),
    Surface = Color3.fromRGB(255, 255, 255),
    Surface2 = Color3.fromRGB(248, 250, 253),
    Surface3 = Color3.fromRGB(238, 242, 248),
    Accent = Color3.fromRGB(91, 76, 224),
    Accent2 = Color3.fromRGB(72, 119, 219),
    Text = Color3.fromRGB(24, 29, 38),
    Muted = Color3.fromRGB(88, 96, 110),
    Border = Color3.fromRGB(202, 210, 221),
    Success = Color3.fromRGB(42, 167, 99),
    Warning = Color3.fromRGB(202, 133, 27),
    Danger = Color3.fromRGB(208, 62, 71),
})

for name, theme in pairs(AstraUI.Themes or {}) do
    if name ~= "Light" then
        AstraUI.Themes[name] = v39NormalizeTheme(theme)
    end
end

local function v39ApplyPagePadding(window, page)
    if not page or not page.Parent then return end
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local portrait = viewport.X < AstraUI.DesignSystem.Breakpoints.Phone
        or viewport.X < viewport.Y * 0.78
    local touch = v38IsTouchPrimary()
    local density = string.lower(tostring(window.Density or "Comfortable"))
    local compact = density == "compact"

    local side
    if portrait then
        side = AstraUI.DesignSystem.Layout.PageSidePhone
    elseif touch then
        side = AstraUI.DesignSystem.Layout.PageSideTouch
    else
        side = AstraUI.DesignSystem.Layout.PageSideDesktop
    end
    if compact then side = math.max(10, side - 3) end

    local top = compact and 9 or 12
    local bottom = compact and 18 or AstraUI.DesignSystem.Layout.PageBottomPadding

    local pad = page:FindFirstChildOfClass("UIPadding")
    if not pad then
        pad = Instance.new("UIPadding")
        pad.Parent = page
    end
    pad.PaddingLeft = UDim.new(0, side)
    pad.PaddingRight = UDim.new(0, side)
    pad.PaddingTop = UDim.new(0, top)
    pad.PaddingBottom = UDim.new(0, bottom)

    local layout = page:FindFirstChildOfClass("UIListLayout")
    if layout then
        layout.Padding = UDim.new(0, compact and 8 or 10)
    end
end

local function v39ApplyTypography(window)
    if not window or window.Destroyed then return end
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local phone = viewport.X < 390
    if window.PageTitle then
        window.PageTitle.TextSize = phone and 17 or AstraUI.DesignSystem.Type.PageTitle
    end
    if window.PageDesc then
        window.PageDesc.TextSize = phone and 10 or AstraUI.DesignSystem.Type.PageDescription
        window.PageDesc.TextColor3 = window.Theme.TextSecondary
    end
end

local function v39RefreshSidebarDivider(window)
    if not window or not window.Sidebar then return end
    for _, child in ipairs(window.Sidebar:GetChildren()) do
        if child:IsA("Frame") and child.AnchorPoint.X > 0.9 and child.Size.X.Offset <= 2 then
            child.BackgroundColor3 = window.Theme.BorderSubtle
            child.BackgroundTransparency = 0.45
        end
    end
end

-- --------------------------------------------------------------------------
-- Compact navigation tooltips.
-- --------------------------------------------------------------------------

local function v39EnsureTooltip(window)
    if window._v39Tooltip and window._v39Tooltip.Parent then
        return window._v39Tooltip
    end
    local host = Instance.new("Frame")
    host.Name = "AstraV39Tooltip"
    host.AutomaticSize = Enum.AutomaticSize.XY
    host.BackgroundColor3 = window.Theme.Surface3
    host.BorderSizePixel = 0
    host.Visible = false
    host.ZIndex = 240
    host.Parent = window.ScreenGui
    v38SetCorner(host, 9)
    v38SetStroke(host, window.Theme.BorderDefault, 0.42, 1)

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.PaddingTop = UDim.new(0, 7)
    pad.PaddingBottom = UDim.new(0, 7)
    pad.Parent = host

    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.AutomaticSize = Enum.AutomaticSize.XY
    label.BackgroundTransparency = 1
    label.Text = ""
    label.TextColor3 = window.Theme.TextPrimary
    label.TextSize = 10
    label.Font = Enum.Font.GothamMedium
    label.ZIndex = 241
    label.Parent = host

    local scale = Instance.new("UIScale")
    scale.Name = "AstraV39TooltipScale"
    scale.Scale = 1
    scale.Parent = host

    window._v39Tooltip = host
    return host
end

local function v39HideTooltip(window)
    local host = window and window._v39Tooltip
    if not host or not host.Parent then return end
    window._v39TooltipSerial = (window._v39TooltipSerial or 0) + 1
    if v371EffectsEnabled(window) and host.Visible then
        local scale = host:FindFirstChild("AstraV39TooltipScale")
        if scale then tween(scale, 0.08, {Scale = 0.98}) end
        task.delay(0.08, function()
            if host.Parent then host.Visible = false end
        end)
    else
        host.Visible = false
    end
end

local function v39ShowTooltip(window, target, textValue)
    if not window or window.Destroyed or not target or not target.Parent then return end
    if not UserInputService.MouseEnabled or v38IsTouchPrimary() then return end

    local host = v39EnsureTooltip(window)
    local label = host:FindFirstChild("Label")
    if not label then return end
    label.Text = tostring(textValue or "")

    host.Visible = true
    host.BackgroundColor3 = window.Theme.Surface3
    label.TextColor3 = window.Theme.TextPrimary
    v38SetStroke(host, window.Theme.BorderDefault, 0.42, 1)

    task.defer(function()
        if not host.Visible or not target.Parent then return end
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1280,720)
        local pos = target.AbsolutePosition
        local size = target.AbsoluteSize
        local tipSize = host.AbsoluteSize

        local x = pos.X + size.X + 8
        local y = pos.Y + math.floor((size.Y - tipSize.Y) * 0.5)
        if x + tipSize.X > viewport.X - 8 then
            x = math.max(8, pos.X - tipSize.X - 8)
        end
        y = math.clamp(y, 8, math.max(8, viewport.Y - tipSize.Y - 8))
        host.Position = UDim2.fromOffset(math.floor(x), math.floor(y))

        local scale = host:FindFirstChild("AstraV39TooltipScale")
        if scale and v371EffectsEnabled(window) then
            scale.Scale = 0.97
            tween(scale, 0.12, {Scale = 1}, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
        elseif scale then
            scale.Scale = 1
        end
    end)
end

local function v39AttachTooltip(window, target, textValue, compactOnly)
    if not target or target:GetAttribute("AstraV39TooltipBound") then return end
    target:SetAttribute("AstraV39TooltipBound", true)
    local serial = 0
    window:_connect(target.MouseEnter, function()
        if compactOnly and not window.SidebarCollapsed then return end
        serial += 1
        local mine = serial
        window._v39TooltipSerial = (window._v39TooltipSerial or 0) + 1
        local globalMine = window._v39TooltipSerial
        task.delay(0.34, function()
            if mine ~= serial or globalMine ~= window._v39TooltipSerial then return end
            if compactOnly and not window.SidebarCollapsed then return end
            v39ShowTooltip(window, target, textValue)
        end)
    end)
    window:_connect(target.MouseLeave, function()
        serial += 1
        v39HideTooltip(window)
    end)
    window:_connect(target.MouseButton1Down, function()
        serial += 1
        v39HideTooltip(window)
    end)
end

-- --------------------------------------------------------------------------
-- Page scroll-state + deterministic tab entrance.
-- --------------------------------------------------------------------------

local function v39ClampCanvasY(page, y)
    local maxY = math.max(0, page.AbsoluteCanvasSize.Y - page.AbsoluteSize.Y)
    return math.clamp(tonumber(y) or 0, 0, maxY)
end

local function v39InstallPageState(window, tab)
    if not tab or not tab.Page or tab.Page:GetAttribute("AstraV39PageState") then return end
    local page = tab.Page
    page:SetAttribute("AstraV39PageState", true)
    tab._v39ScrollY = 0
    tab._v39Visited = false
    tab._v39Restoring = false

    v39ApplyPagePadding(window, page)

    window:_connect(page:GetPropertyChangedSignal("CanvasPosition"), function()
        if tab._v39Restoring or not page.Visible then return end
        tab._v39ScrollY = page.CanvasPosition.Y
    end)
end

local function v39RestorePage(window, tab)
    if not tab or not tab.Page then return end
    local page = tab.Page
    local preserve = not (window.Options and window.Options.PreserveTabScroll == false)
    local resetAlways = window.Options and window.Options.ResetTabScrollOnSelect == true
    local desired = 0
    if preserve and tab._v39Visited and not resetAlways then
        desired = tab._v39ScrollY or 0
    end

    tab._v39Restoring = true
    page.CanvasPosition = Vector2.new(0, v39ClampCanvasY(page, desired))
    page.Position = UDim2.fromOffset(0,0)
    tab._v39Visited = true

    task.defer(function()
        if page.Parent then
            page.CanvasPosition = Vector2.new(0, v39ClampCanvasY(page, desired))
            page.Position = UDim2.fromOffset(0,0)
        end
        tab._v39Restoring = false
    end)
end

-- --------------------------------------------------------------------------
-- Popover precision layer. This works on top of V3.8 dropdowns and keeps the
-- API intact while making every popup fit the real viewport.
-- --------------------------------------------------------------------------

local function v39FindNewDropdownOverlay(window, before)
    for _, child in ipairs(window.ScreenGui:GetChildren()) do
        if child.Name == "AstraV38DropdownOverlay" and not before[child] then
            return child
        end
    end
    return nil
end

local function v39EnsurePopoverShadow(overlay, popover)
    local shadow = overlay:FindFirstChild("AstraV39PopoverShadow")
    if shadow then return shadow end

    shadow = Instance.new("ImageLabel")
    shadow.Name = "AstraV39PopoverShadow"
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://1316045217"
    shadow.ImageColor3 = Color3.new(0,0,0)
    shadow.ImageTransparency = 0.64
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(10,10,118,118)
    shadow.ZIndex = math.max(160, popover.ZIndex - 1)
    shadow.Parent = overlay
    return shadow
end

local function v39RelayoutDropdown(window, row, overlay, popover, top, list, shadow)
    if not window or window.Destroyed or not overlay.Visible then return end
    local camera = workspace.CurrentCamera
    if not camera then return end

    local viewport = camera.ViewportSize
    local margin = AstraUI.DesignSystem.Layout.PopoverMargin
    local portrait = viewport.X < AstraUI.DesignSystem.Breakpoints.Phone
        or viewport.X < viewport.Y * 0.78

    local topHeight = top and top.Size.Y.Offset or 0
    local chrome = 20 + topHeight + 8
    local contentHeight = math.max(44, list.AbsoluteCanvasSize.Y)
    local desiredList = math.min(contentHeight, portrait and 320 or 276)
    local desiredHeight = chrome + desiredList

    local width, height, x, y

    if portrait then
        width = math.clamp(
            viewport.X - margin * 2,
            math.min(260, viewport.X - margin * 2),
            math.min(AstraUI.DesignSystem.Layout.BottomSheetMaxWidth, viewport.X - margin * 2)
        )
        local maxHeight = math.max(150, math.min(viewport.Y * 0.72, viewport.Y - margin * 2))
        height = math.clamp(desiredHeight, 132, maxHeight)
        x = math.floor((viewport.X - width) * 0.5)
        y = math.max(margin, viewport.Y - height - margin)
        overlay.BackgroundTransparency = 0.56
    else
        width = math.clamp(
            math.max(286, row.AbsoluteSize.X * 0.42),
            286,
            AstraUI.DesignSystem.Layout.PopoverMaxWidth
        )

        local rowY = row.AbsolutePosition.Y
        local rowBottom = rowY + row.AbsoluteSize.Y
        local belowAvailable = math.max(0, viewport.Y - margin - rowBottom - 7)
        local aboveAvailable = math.max(0, rowY - margin - 7)
        local openBelow = belowAvailable >= math.min(desiredHeight, 176) or belowAvailable >= aboveAvailable
        local available = openBelow and belowAvailable or aboveAvailable

        height = math.clamp(
            math.min(desiredHeight, available),
            math.min(126, math.max(available, 80)),
            math.max(126, available)
        )

        x = math.clamp(
            row.AbsolutePosition.X + row.AbsoluteSize.X - width,
            margin,
            math.max(margin, viewport.X - width - margin)
        )
        if openBelow then
            y = rowBottom + 7
        else
            y = rowY - height - 7
        end
        y = math.clamp(y, margin, math.max(margin, viewport.Y - height - margin))
        overlay.BackgroundTransparency = 1
    end

    popover.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
    popover.Size = UDim2.fromOffset(math.floor(width), math.floor(height))
    v38SetCorner(popover, portrait and 18 or 16)
    v38SetStroke(popover, window.Theme.BorderDefault, 0.30, 1)

    if list then
        list.Position = UDim2.fromOffset(10, 10 + topHeight + 8)
        list.Size = UDim2.new(1, -20, 1, -(20 + topHeight + 8))
        local hasOverflow = list.AbsoluteCanvasSize.Y > list.AbsoluteSize.Y + 3
        list.ScrollBarThickness = hasOverflow and (v38IsTouchPrimary() and 2 or 3) or 0
        list.ScrollBarImageColor3 = window.Theme.Scrollbar
        list.ScrollBarImageTransparency = hasOverflow and 0.40 or 1
        list.VerticalScrollBarInset = Enum.ScrollBarInset.Always
    end

    if shadow then
        shadow.Visible = not portrait
        shadow.Position = UDim2.fromOffset(math.floor(x - 18), math.floor(y - 18))
        shadow.Size = UDim2.fromOffset(math.floor(width + 36), math.floor(height + 36))
        shadow.ImageColor3 = window.Theme.Shadow
    end
end

local function v39DecorateDropdown(window, object, before)
    local row = object and object.Instance
    if not row then return end

    local overlay = v39FindNewDropdownOverlay(window, before)
    if not overlay then return end
    local popover = overlay:FindFirstChild("Popover")
    if not popover then return end
    local top = popover:FindFirstChild("Top")
    local list = popover:FindFirstChild("Options")
    if not list then return end

    local shadow = v39EnsurePopoverShadow(overlay, popover)

    local pad = list:FindFirstChild("AstraV39ListPadding")
    if not pad then
        pad = Instance.new("UIPadding")
        pad.Name = "AstraV39ListPadding"
        pad.PaddingBottom = UDim.new(0, 4)
        pad.PaddingRight = UDim.new(0, 2)
        pad.Parent = list
    end

    local function relayout()
        task.defer(function()
            if overlay.Parent and overlay.Visible then
                v39RelayoutDropdown(window, row, overlay, popover, top, list, shadow)
            end
        end)
    end

    window:_connect(overlay:GetPropertyChangedSignal("Visible"), relayout)
    window:_connect(list:GetPropertyChangedSignal("AbsoluteCanvasSize"), relayout)
    window:_connect(row:GetPropertyChangedSignal("AbsolutePosition"), relayout)
    window:_connect(row:GetPropertyChangedSignal("AbsoluteSize"), relayout)

    if workspace.CurrentCamera then
        window:_connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), relayout)
    end

    window:OnThemeChanged(function()
        if popover.Parent then
            popover.BackgroundColor3 = window.Theme.Surface
            v38SetStroke(popover, window.Theme.BorderDefault, 0.30, 1)
            list.ScrollBarImageColor3 = window.Theme.Scrollbar
            shadow.ImageColor3 = window.Theme.Shadow
        end
    end)
end

-- --------------------------------------------------------------------------
-- Action hierarchy V3.9.
-- --------------------------------------------------------------------------

local function v39EnsureActionGradient(button)
    local gradient = button:FindFirstChild("AstraV39ActionGradient")
    if not gradient then
        gradient = Instance.new("UIGradient")
        gradient.Name = "AstraV39ActionGradient"
        gradient.Rotation = 90
        gradient.Parent = button
    end
    return gradient
end

local function v39StyleAction(window, button, style, disabled)
    if not button or not button.Parent then return end
    style = string.lower(tostring(style or "primary"))
    disabled = disabled == true
    local theme = window.Theme

    local background, textColor, borderColor, borderTransparency, backgroundTransparency
    local useGradient = false

    if disabled then
        background = theme.DisabledSurface
        textColor = theme.DisabledText
        borderColor = theme.BorderSubtle
        borderTransparency = 0.82
        backgroundTransparency = 0
    elseif style == "secondary" then
        background = theme.Surface3
        textColor = theme.TextPrimary
        borderColor = theme.BorderDefault
        borderTransparency = 0.56
        backgroundTransparency = 0.08
    elseif style == "ghost" then
        background = theme.Surface2
        textColor = theme.TextSecondary
        borderColor = theme.BorderSubtle
        borderTransparency = 1
        backgroundTransparency = 1
    elseif style == "danger" then
        background = theme.Danger
        textColor = v38AccentText(theme.Danger)
        borderColor = theme.Danger
        borderTransparency = 0.68
        backgroundTransparency = 0
        useGradient = true
    else
        background = theme.Accent
        textColor = theme.AccentText
        borderColor = theme.Accent
        borderTransparency = 0.68
        backgroundTransparency = 0
        useGradient = true
    end

    button.BackgroundColor3 = background
    button.TextColor3 = textColor
    button.BackgroundTransparency = backgroundTransparency
    v38SetStroke(button, borderColor, borderTransparency, 1)

    local gradient = v39EnsureActionGradient(button)
    gradient.Enabled = useGradient and not disabled
    if gradient.Enabled then
        local topColor = v38Mix(background, Color3.new(1,1,1), 0.055)
        local bottomColor = v38Mix(background, Color3.new(0,0,0), 0.055)
        gradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, topColor),
            ColorSequenceKeypoint.new(1, bottomColor),
        })
    end
end

local function v39RestyleActions(window)
    if not window.ScreenGui then return end
    for _, obj in ipairs(window.ScreenGui:GetDescendants()) do
        if obj:IsA("TextButton") and obj:GetAttribute("AstraV38Role") == "Action" then
            v39StyleAction(
                window,
                obj,
                obj:GetAttribute("AstraV38Style"),
                obj:GetAttribute("AstraV38Disabled") == true
            )
        end
    end
end

-- --------------------------------------------------------------------------
-- Quality audit for development/debugging.
-- --------------------------------------------------------------------------

function Window:GetQualityReport()
    local report = {
        Version = V39_VERSION,
        Theme = AstraUI:AuditTheme(self.Theme),
        Tabs = #(self.Tabs or {}),
        VisibleRows = 0,
        ScrollableTabs = 0,
        SelectableObjects = 0,
        Popovers = #(self._v38Popovers or {}),
        Density = self.Density or "Comfortable",
    }

    for _, tab in ipairs(self.Tabs or {}) do
        if tab.Page then
            if tab.Page.AbsoluteCanvasSize.Y > tab.Page.AbsoluteSize.Y + 3 then
                report.ScrollableTabs += 1
            end
            for _, obj in ipairs(tab.Page:GetDescendants()) do
                if obj:IsA("GuiObject") and obj:GetAttribute("AstraV38Role") == "Row" and obj.Visible then
                    report.VisibleRows += 1
                end
                if (obj:IsA("TextButton") or obj:IsA("ImageButton")) and obj.Selectable then
                    report.SelectableObjects += 1
                end
            end
        end
    end
    return report
end

-- --------------------------------------------------------------------------
-- Public method overrides / integrations.
-- --------------------------------------------------------------------------

local _AstraV39Dropdown = Tab._addDropdown
function Tab:_addDropdown(parent, data)
    local before = {}
    for _, child in ipairs(self.Window.ScreenGui:GetChildren()) do
        if child.Name == "AstraV38DropdownOverlay" then before[child] = true end
    end

    local object = _AstraV39Dropdown(self, parent, data)
    v39DecorateDropdown(self.Window, object, before)
    return object
end

local _AstraV39Button = Tab._addButton
function Tab:_addButton(parent, data)
    data = data or {}
    local object = _AstraV39Button(self, parent, data)
    local row = object and object.Instance
    if row then
        for _, child in ipairs(row:GetChildren()) do
            if child:IsA("TextButton") and child.AnchorPoint.X > 0.9 then
                v39StyleAction(
                    self.Window,
                    child,
                    data.Style or (data.Danger and "Danger") or "Primary",
                    data.Disabled == true
                )
                break
            end
        end
    end
    return object
end

local _AstraV39CreateTab = Window.CreateTab
function Window:CreateTab(options)
    local tab = _AstraV39CreateTab(self, options)
    if tab then
        v39InstallPageState(self, tab)
        if tab.Button then
            v39AttachTooltip(self, tab.Button, tab.Name or (options and options.Name) or "Tab", true)
        end
        if tab.Page and tab == self.CurrentTab then
            task.defer(function()
                if not self.Destroyed then v39RestorePage(self, tab) end
            end)
        end
    end
    return tab
end

local _AstraV39SelectTab = Window.SelectTab
function Window:SelectTab(tab)
    if self.CurrentTab and self.CurrentTab.Page and self.CurrentTab._v39Restoring ~= true then
        self.CurrentTab._v39ScrollY = self.CurrentTab.Page.CanvasPosition.Y
    end

    _AstraV39SelectTab(self, tab)

    if tab then
        v39InstallPageState(self, tab)
        v39ApplyPagePadding(self, tab.Page)
        v39RestorePage(self, tab)

        -- Older motion layers animate page.Position. V3.9 always resolves to
        -- the canonical origin after the entrance, avoiding clipped headers.
        task.delay(AstraUI.DesignSystem.Motion.Emphasis + 0.03, function()
            if not self.Destroyed and tab.Page and tab.Page.Parent and tab == self.CurrentTab then
                tab.Page.Position = UDim2.fromOffset(0,0)
            end
        end)
    end
end

local _AstraV39SetDensity = Window.SetDensity
function Window:SetDensity(mode)
    local result = _AstraV39SetDensity(self, mode)
    for _, tab in ipairs(self.Tabs or {}) do
        if tab.Page then v39ApplyPagePadding(self, tab.Page) end
    end
    return result
end

local _AstraV39SetTheme = Window.SetTheme
function Window:SetTheme(themePatch)
    local merged = v38Copy(self.Theme or AstraUI.Themes.Midnight)
    for key, value in pairs(themePatch or {}) do merged[key] = value end
    local normalized = v39NormalizeTheme(merged)
    _AstraV39SetTheme(self, normalized)
    self.Theme = normalized

    task.defer(function()
        if self.Destroyed then return end
        v39ApplyTypography(self)
        v39RefreshSidebarDivider(self)
        v39RestyleActions(self)

        if self._v39Tooltip and self._v39Tooltip.Parent then
            self._v39Tooltip.BackgroundColor3 = self.Theme.Surface3
            local label = self._v39Tooltip:FindFirstChild("Label")
            if label then label.TextColor3 = self.Theme.TextPrimary end
            v38SetStroke(self._v39Tooltip, self.Theme.BorderDefault, 0.42, 1)
        end
    end)
end

function Window:SetThemePreset(name)
    local preset = AstraUI.Themes[tostring(name or "")]
    if not preset then return false, "Unknown theme preset" end
    self._darkTheme = v38Copy(preset)
    self:SetTheme(v39NormalizeTheme(preset))
    return true
end

function AstraUI:CreateTheme(options)
    options = options or {}
    local baseName = tostring(options.Base or "Midnight")
    local base = AstraUI.Themes[baseName] or AstraUI.Themes.Midnight
    local theme = v38Copy(base)

    if typeof(options.Accent) == "Color3" then
        theme.Accent = options.Accent
        theme.Accent2 = (typeof(options.Accent2) == "Color3")
            and options.Accent2
            or v38Mix(options.Accent, Color3.new(1,1,1), 0.22)
    end

    for key, value in pairs(options.Override or {}) do
        theme[key] = value
    end
    return v39NormalizeTheme(theme)
end

function AstraUI:AuditTheme(theme)
    local t = v39NormalizeTheme(theme or AstraUI.Themes.Midnight)
    local primaryBackground = v38Contrast(t.TextPrimary, t.Background)
    local primarySurface = math.min(
        v38Contrast(t.TextPrimary, t.Surface),
        v38Contrast(t.TextPrimary, t.Surface2),
        v38Contrast(t.TextPrimary, t.Surface3)
    )
    local secondarySurface = math.min(
        v38Contrast(t.TextSecondary, t.Surface),
        v38Contrast(t.TextSecondary, t.Surface2),
        v38Contrast(t.TextSecondary, t.Surface3)
    )
    local accentSurface = v38Contrast(t.Accent, t.Surface2)
    local accentText = v38Contrast(t.AccentText, t.Accent)

    return {
        TextContrast = primaryBackground,
        PrimarySurfaceContrast = primarySurface,
        SecondarySurfaceContrast = secondarySurface,
        AccentContrast = accentSurface,
        AccentTextContrast = accentText,
        TextPass = primaryBackground >= 4.5,
        PrimarySurfacePass = primarySurface >= 4.5,
        SecondaryPass = secondarySurface >= 4.5,
        ComponentPass = accentSurface >= 3,
        AccentTextPass = accentText >= 4.5,
    }
end

local _AstraV39CreateWindow = AstraUI.CreateWindow
function AstraUI:CreateWindow(options)
    options = options or {}
    local prepared = {}
    for key, value in pairs(options) do prepared[key] = value end

    if prepared.Theme then
        prepared.Theme = v39NormalizeTheme(prepared.Theme)
    else
        prepared.Theme = v39NormalizeTheme(AstraUI.Themes.Midnight)
    end

    local window = _AstraV39CreateWindow(self, prepared)
    window.Theme = v39NormalizeTheme(window.Theme)

    v39ApplyTypography(window)
    v39RefreshSidebarDivider(window)
    v39RestyleActions(window)

    -- Tooltip labels for icon-only chrome.
    if window.SidebarButton then v39AttachTooltip(window, window.SidebarButton, "Navigation", false) end
    if window.ThemeButton then v39AttachTooltip(window, window.ThemeButton, "Theme", false) end
    if window.MinimizeButton then v39AttachTooltip(window, window.MinimizeButton, "Minimize", false) end
    if window.CloseButton then v39AttachTooltip(window, window.CloseButton, "Close", false) end

    for _, tab in ipairs(window.Tabs or {}) do
        v39InstallPageState(window, tab)
        if tab.Button then v39AttachTooltip(window, tab.Button, tab.Name or "Tab", true) end
    end

    local function refreshAdaptive()
        if window.Destroyed then return end
        v39ApplyTypography(window)
        v39RefreshSidebarDivider(window)
        for _, tab in ipairs(window.Tabs or {}) do
            if tab.Page then
                v39ApplyPagePadding(window, tab.Page)
                if tab == window.CurrentTab then
                    local current = tab.Page.CanvasPosition.Y
                    tab.Page.CanvasPosition = Vector2.new(0, v39ClampCanvasY(tab.Page, current))
                end
            end
        end
        v39HideTooltip(window)
    end

    if workspace.CurrentCamera then
        window:_connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), refreshAdaptive)
    end
    window:_connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
        task.defer(refreshAdaptive)
    end)

    task.defer(refreshAdaptive)
    return window
end

AstraUI.Version = "3.9.1-executor"
end)()


-- ==========================================================================
-- AstraUI V3.10 - Visual Depth & Interaction Hierarchy
-- A deliberately visible refinement layer built on V3.9.1.
-- This layer does not add new component types; it improves optical hierarchy,
-- elevation, button priority, chrome separation and theme consistency.
-- ==========================================================================
;(function()
local V310_VERSION = "3.10.0-executor"

local function v310Mix(a,b,t)
    return Color3.new(
        a.R + (b.R-a.R)*t,
        a.G + (b.G-a.G)*t,
        a.B + (b.B-a.B)*t
    )
end

local function v310EnsureCorner(obj, radius)
    if not obj or not obj.Parent then return nil end
    local c=obj:FindFirstChildOfClass("UICorner")
    if not c then
        c=Instance.new("UICorner")
        c.Parent=obj
    end
    c.CornerRadius=UDim.new(0,radius or 12)
    return c
end

local function v310EnsureStroke(obj, name)
    if not obj or not obj.Parent then return nil end
    local s=obj:FindFirstChild(name)
    if s and not s:IsA("UIStroke") then s:Destroy(); s=nil end
    if not s then
        s=Instance.new("UIStroke")
        s.Name=name
        s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
        s.Parent=obj
    end
    return s
end

local function v310SetStroke(obj, color, transparency, thickness, name)
    local s=v310EnsureStroke(obj,name or "AstraV310Stroke")
    if s then
        s.Color=color
        s.Transparency=transparency or 0
        s.Thickness=thickness or 1
    end
    return s
end

local function v310EnsureTopHighlight(obj, name)
    if not obj or not obj.Parent then return nil end
    local line=obj:FindFirstChild(name)
    if not line then
        line=Instance.new("Frame")
        line.Name=name
        line.BackgroundTransparency=1
        line.BorderSizePixel=0
        line.Position=UDim2.fromOffset(10,0)
        line.Size=UDim2.new(1,-20,0,1)
        line.ZIndex=math.max(obj.ZIndex+1,2)
        line.Parent=obj
    end
    return line
end

local function v310EnsureGradient(button)
    local g=button:FindFirstChild("AstraV310Gradient")
    if not g then
        g=Instance.new("UIGradient")
        g.Name="AstraV310Gradient"
        g.Rotation=90
        g.Parent=button
    end
    return g
end

local function v310IsAction(obj)
    return obj:IsA("TextButton") and obj:GetAttribute("AstraV38Role")=="Action"
end

local function v310StyleAction(window, button)
    if not window or not button or not button.Parent then return end
    local theme=window.Theme
    local style=string.lower(tostring(button:GetAttribute("AstraV38Style") or "Primary"))
    local disabled=button:GetAttribute("AstraV38Disabled")==true
    local gradient=v310EnsureGradient(button)
    local stroke=v310EnsureStroke(button,"AstraV310ActionStroke")
    local top=v310EnsureTopHighlight(button,"AstraV310ActionHighlight")
    v310EnsureCorner(button,11)

    if disabled then
        button.BackgroundColor3=theme.DisabledSurface or theme.Surface3
        button.BackgroundTransparency=0
        button.TextColor3=theme.DisabledText or theme.TextSecondary
        gradient.Enabled=false
        stroke.Color=theme.BorderSubtle or theme.Border
        stroke.Transparency=0.78
        top.BackgroundTransparency=1
        return
    end

    if style=="secondary" then
        -- Secondary is intentionally neutral. The previous V3.9 could still
        -- read almost like a second primary button in some themes.
        button.BackgroundColor3=theme.Surface3
        button.BackgroundTransparency=0.02
        button.TextColor3=theme.TextPrimary
        stroke.Color=theme.BorderStrong or theme.BorderDefault or theme.Border
        stroke.Transparency=0.50
        gradient.Enabled=false
        top.BackgroundColor3=theme.TextPrimary
        top.BackgroundTransparency=0.95
    elseif style=="ghost" then
        button.BackgroundColor3=theme.Surface2
        button.BackgroundTransparency=1
        button.TextColor3=theme.TextSecondary
        stroke.Color=theme.BorderSubtle or theme.Border
        stroke.Transparency=1
        gradient.Enabled=false
        top.BackgroundTransparency=1
    elseif style=="danger" then
        local base=theme.Danger
        button.BackgroundColor3=base
        button.BackgroundTransparency=0
        button.TextColor3=Color3.new(1,1,1)
        stroke.Color=v310Mix(base,Color3.new(1,1,1),0.24)
        stroke.Transparency=0.55
        gradient.Enabled=true
        gradient.Color=ColorSequence.new({
            ColorSequenceKeypoint.new(0,v310Mix(base,Color3.new(1,1,1),0.08)),
            ColorSequenceKeypoint.new(1,v310Mix(base,Color3.new(0,0,0),0.08)),
        })
        top.BackgroundColor3=Color3.new(1,1,1)
        top.BackgroundTransparency=0.88
    else
        local base=theme.Accent
        button.BackgroundColor3=base
        button.BackgroundTransparency=0
        button.TextColor3=theme.AccentText or Color3.new(1,1,1)
        stroke.Color=v310Mix(base,Color3.new(1,1,1),0.28)
        stroke.Transparency=0.52
        gradient.Enabled=true
        gradient.Color=ColorSequence.new({
            ColorSequenceKeypoint.new(0,v310Mix(base,Color3.new(1,1,1),0.10)),
            ColorSequenceKeypoint.new(0.55,base),
            ColorSequenceKeypoint.new(1,v310Mix(base,Color3.new(0,0,0),0.10)),
        })
        top.BackgroundColor3=Color3.new(1,1,1)
        top.BackgroundTransparency=0.86
    end
end

local function v310StyleRow(window,row)
    if not window or not row or not row.Parent then return end
    if row:GetAttribute("AstraV38Role")~="Row" then return end
    local theme=window.Theme
    row.BackgroundColor3=theme.Surface2
    row.BackgroundTransparency=0
    v310EnsureCorner(row,12)
    v310SetStroke(row,theme.BorderSubtle or theme.Border,0.82,1,"AstraV310RowStroke")
    local top=v310EnsureTopHighlight(row,"AstraV310RowHighlight")
    top.BackgroundColor3=theme.TextPrimary
    top.BackgroundTransparency=0.955

    for _,child in ipairs(row:GetChildren()) do
        if child:IsA("TextLabel") then
            local y=child.Position.Y.Offset
            child.TextColor3=(y<=16) and theme.TextPrimary or theme.TextSecondary
        end
    end
end

local function v310StyleSection(window,section)
    if not window or not section or not section.Parent then return end
    if section:GetAttribute("AstraV38Role")~="Section" then return end
    local theme=window.Theme
    -- Sections are deliberately quieter than their rows. This creates a clear
    -- three-level hierarchy: background -> section -> interactive row.
    section.BackgroundColor3=theme.Surface
    section.BackgroundTransparency=0
    v310EnsureCorner(section,15)
    v310SetStroke(section,theme.BorderSubtle or theme.Border,0.91,1,"AstraV310SectionStroke")
    local top=v310EnsureTopHighlight(section,"AstraV310SectionHighlight")
    top.Position=UDim2.fromOffset(14,0)
    top.Size=UDim2.new(1,-28,0,1)
    top.BackgroundColor3=theme.TextPrimary
    top.BackgroundTransparency=0.97
end

local function v310StyleField(window,obj)
    if not window or not obj or not obj.Parent then return end
    local theme=window.Theme
    local role=obj:GetAttribute("AstraV38Role")
    if role=="DropdownDisplay" or role=="InputHolder" then
        obj.BackgroundColor3=theme.Surface3
        obj.BackgroundTransparency=0
        v310EnsureCorner(obj,10)
        v310SetStroke(obj,theme.BorderDefault or theme.Border,0.68,1,"AstraV310FieldStroke")
        local top=v310EnsureTopHighlight(obj,"AstraV310FieldHighlight")
        top.Position=UDim2.fromOffset(8,0)
        top.Size=UDim2.new(1,-16,0,1)
        top.BackgroundColor3=theme.TextPrimary
        top.BackgroundTransparency=0.965
    end
end

local function v310StyleChrome(window)
    if not window or window.Destroyed then return end
    local theme=window.Theme

    if window.Root then
        v310SetStroke(window.Root,theme.BorderDefault or theme.Border,0.46,1,"AstraV310RootStroke")
        local top=v310EnsureTopHighlight(window.Root,"AstraV310RootHighlight")
        top.Position=UDim2.fromOffset(16,0)
        top.Size=UDim2.new(1,-32,0,1)
        top.BackgroundColor3=theme.TextPrimary
        top.BackgroundTransparency=0.94
    end

    if window.Topbar then
        local divider=window.Topbar:FindFirstChild("AstraV310TopbarDivider")
        if not divider then
            divider=Instance.new("Frame")
            divider.Name="AstraV310TopbarDivider"
            divider.BorderSizePixel=0
            divider.AnchorPoint=Vector2.new(0,1)
            divider.Position=UDim2.new(0,14,1,0)
            divider.Size=UDim2.new(1,-28,0,1)
            divider.ZIndex=window.Topbar.ZIndex+1
            divider.Parent=window.Topbar
        end
        divider.BackgroundColor3=theme.BorderSubtle or theme.Border
        divider.BackgroundTransparency=0.72
    end

    if window.SearchBox and window.SearchBox.Parent then
        local holder=window.SearchBox.Parent
        holder.BackgroundColor3=theme.Surface2
        v310SetStroke(holder,theme.BorderDefault or theme.Border,0.64,1,"AstraV310SearchStroke")
    end

    for _,control in ipairs({window.SidebarButton,window.ThemeButton,window.MinimizeButton,window.CloseButton}) do
        if control and control.Parent then
            control.BackgroundColor3=theme.Surface2
            v310SetStroke(control,theme.BorderSubtle or theme.Border,0.72,1,"AstraV310ChromeStroke")
            local hi=v310EnsureTopHighlight(control,"AstraV310ChromeHighlight")
            hi.Position=UDim2.fromOffset(7,0)
            hi.Size=UDim2.new(1,-14,0,1)
            hi.BackgroundColor3=theme.TextPrimary
            hi.BackgroundTransparency=0.94
        end
    end
end

local function v310StyleTabs(window)
    if not window or window.Destroyed then return end
    local theme=window.Theme
    for _,tab in ipairs(window.Tabs or {}) do
        local selected=tab==window.CurrentTab
        if tab.Button then
            tab.Button.BackgroundColor3=selected and theme.AccentSoft or theme.Surface
            tab.Button.BackgroundTransparency=selected and 0.10 or 1
            v310SetStroke(tab.Button,selected and theme.Accent or (theme.BorderSubtle or theme.Border),selected and 0.68 or 1,1,"AstraV310TabStroke")
        end
        if tab.ButtonText then
            tab.ButtonText.TextColor3=selected and theme.TextPrimary or theme.TextSecondary
        end
        if tab.Indicator then
            tab.Indicator.BackgroundColor3=theme.Accent
            tab.Indicator.BackgroundTransparency=selected and 0 or 1
            tab.Indicator.Size=selected and UDim2.fromOffset(3,20) or UDim2.fromOffset(3,14)
        end
    end
end

local function v310Restyle(window)
    if not window or window.Destroyed or not window.ScreenGui then return end
    v310StyleChrome(window)
    v310StyleTabs(window)
    for _,obj in ipairs(window.ScreenGui:GetDescendants()) do
        if obj:IsA("GuiObject") then
            if obj:GetAttribute("AstraV38Role")=="Row" then v310StyleRow(window,obj) end
            if obj:GetAttribute("AstraV38Role")=="Section" then v310StyleSection(window,obj) end
            local role=obj:GetAttribute("AstraV38Role")
            if role=="DropdownDisplay" or role=="InputHolder" then v310StyleField(window,obj) end
        end
        if v310IsAction(obj) then v310StyleAction(window,obj) end
    end
end

-- New rows/sections/actions receive V3.10 styling immediately, rather than
-- waiting for a theme refresh.
local _V310Row=Tab._row
function Tab:_row(parent,height)
    local row=_V310Row(self,parent,height)
    task.defer(function()
        if self.Window and not self.Window.Destroyed and row and row.Parent then v310StyleRow(self.Window,row) end
    end)
    return row
end

local _V310Section=Tab.CreateSection
function Tab:CreateSection(options)
    local section=_V310Section(self,options)
    task.defer(function()
        if self.Window and not self.Window.Destroyed and section and section.Frame then
            v310StyleSection(self.Window,section.Frame)
            for _,obj in ipairs(section.Frame:GetDescendants()) do
                if obj:IsA("GuiObject") and obj:GetAttribute("AstraV38Role")=="Row" then v310StyleRow(self.Window,obj) end
            end
        end
    end)
    return section
end

local _V310Button=Tab._addButton
function Tab:_addButton(parent,data)
    local object=_V310Button(self,parent,data)
    task.defer(function()
        if not self.Window or self.Window.Destroyed then return end
        local row=object and object.Instance
        if row then
            v310StyleRow(self.Window,row)
            for _,obj in ipairs(row:GetDescendants()) do
                if v310IsAction(obj) then v310StyleAction(self.Window,obj) end
            end
        end
    end)
    return object
end

local _V310CreateTab=Window.CreateTab
function Window:CreateTab(options)
    local tab=_V310CreateTab(self,options)
    task.defer(function()
        if not self.Destroyed then v310StyleTabs(self) end
    end)
    return tab
end

local _V310SelectTab=Window.SelectTab
function Window:SelectTab(tab)
    _V310SelectTab(self,tab)
    task.defer(function()
        if not self.Destroyed then v310StyleTabs(self) end
    end)
end

local _V310SetTheme=Window.SetTheme
function Window:SetTheme(themePatch)
    local result=_V310SetTheme(self,themePatch)
    task.defer(function()
        if not self.Destroyed then v310Restyle(self) end
    end)
    return result
end

local _V310CreateWindow=AstraUI.CreateWindow
function AstraUI:CreateWindow(options)
    local window=_V310CreateWindow(self,options)
    task.defer(function()
        if window and not window.Destroyed then v310Restyle(window) end
    end)
    return window
end

AstraUI.Version=V310_VERSION
end)()

-- ============================================================================
-- AstraUI V3.11 - Identity, Access & Runtime Content
-- Adds a first-class local-player profile, key metadata/session APIs and
-- reusable information-rich content components without changing existing API.
-- ============================================================================
;(function()
local V311_VERSION = "3.11.0"

local function v311Copy(source)
    local out = {}
    for k,v in pairs(source or {}) do out[k] = v end
    return out
end

local function v311NowUnix()
    local ok, value = pcall(os.time)
    return ok and tonumber(value) or 0
end

local function v311NowClock()
    local ok, value = pcall(os.clock)
    return ok and tonumber(value) or 0
end

local function v311FormatDuration(seconds, compact)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if compact then
        if days > 0 then return string.format("%dd %02dh", days, hours) end
        if hours > 0 then return string.format("%dh %02dm", hours, minutes) end
        if minutes > 0 then return string.format("%dm %02ds", minutes, secs) end
        return string.format("%ds", secs)
    end

    if days > 0 then return string.format("%dd %dh %dm", days, hours, minutes) end
    if hours > 0 then return string.format("%dh %dm %ds", hours, minutes, secs) end
    if minutes > 0 then return string.format("%dm %ds", minutes, secs) end
    return string.format("%ds", secs)
end

local function v311MaskKey(value)
    value = tostring(value or "")
    local len = #value
    if len == 0 then return "Not stored" end
    if len <= 4 then return string.rep("•", len) end
    if len <= 8 then return string.sub(value,1,2) .. string.rep("•", math.max(2,len-4)) .. string.sub(value,-2) end
    return string.sub(value,1,4) .. string.rep("•", math.min(8, math.max(4,len-8))) .. string.sub(value,-4)
end

local function v311ToneColor(theme, tone)
    tone = string.lower(tostring(tone or "muted"))
    if tone == "accent" or tone == "primary" then return theme.Accent end
    if tone == "success" then return theme.Success end
    if tone == "warning" then return theme.Warning end
    if tone == "danger" or tone == "error" then return theme.Danger end
    return theme.TextSecondary or theme.Muted or theme.Text
end

local function v311NormalizeKeyInfo(info, activate)
    info = v311Copy(type(info) == "table" and info or {})
    local now = v311NowUnix()

    info.Tier = info.Tier or info.Plan or info.Name or info.Type
    info.Status = info.Status or info.State
    info.Duration = tonumber(info.Duration or info.DurationSeconds or info.Lifetime or info.ValidFor)
    info.ExpiresAt = tonumber(info.ExpiresAt or info.Expiry or info.Expires)
    info.ActivatedAt = tonumber(info.ActivatedAt or info.StartedAt or info.CreatedAt)

    if activate then
        if not info.ActivatedAt or info.ActivatedAt <= 0 then info.ActivatedAt = now end
        if (not info.ExpiresAt or info.ExpiresAt <= 0) and info.Duration and info.Duration > 0 and info.Permanent ~= true then
            info.ExpiresAt = now + info.Duration
        end
    end

    if info.Permanent == true then
        info.ExpiresAt = nil
    end

    return info
end

function AstraUI:FormatDuration(seconds, compact)
    return v311FormatDuration(seconds, compact)
end

function Window:FormatDuration(seconds, compact)
    return v311FormatDuration(seconds, compact)
end

function Window:GetSessionPlaytime()
    local started = tonumber(self._astraSessionClock) or v311NowClock()
    return math.max(0, math.floor(v311NowClock() - started))
end

function Window:GetKeyInfo()
    local info = v311Copy(self._astraKeyInfo or {})
    local now = v311NowUnix()
    if info.ExpiresAt and info.ExpiresAt > 0 then
        info.Remaining = math.max(0, info.ExpiresAt - now)
        info.Expired = info.Remaining <= 0
        if info.Expired then info.Status = "Expired" end
    else
        info.Remaining = nil
        info.Expired = false
    end
    return info
end

function Window:GetKeyRemaining()
    local info = self:GetKeyInfo()
    return info.Remaining
end

function Window:IsKeyExpired()
    return self:GetKeyInfo().Expired == true
end

function Window:OnKeyInfoChanged(callback)
    if type(callback) ~= "function" then
        return {Disconnect = function() end}
    end
    self._astraKeyListeners = self._astraKeyListeners or {}
    local entry = {Callback = callback, Connected = true}
    table.insert(self._astraKeyListeners, entry)
    return {
        Disconnect = function() entry.Connected = false end
    }
end

function Window:SetKeyInfo(info, enteredKey)
    local nextInfo = v311NormalizeKeyInfo(info, true)
    nextInfo.Status = nextInfo.Status or "Unlocked"
    if enteredKey ~= nil then nextInfo.MaskedKey = v311MaskKey(enteredKey) end
    if not nextInfo.MaskedKey and self._astraKeyInfo then nextInfo.MaskedKey = self._astraKeyInfo.MaskedKey end
    self._astraKeyInfo = nextInfo
    self.KeyUnlocked = string.lower(tostring(nextInfo.Status)) ~= "locked" and not self:IsKeyExpired()

    for _,entry in ipairs(self._astraKeyListeners or {}) do
        if entry.Connected then safeCall(entry.Callback, self:GetKeyInfo(), self) end
    end
    return self:GetKeyInfo()
end

function Window:GetSessionInfo()
    local player = Players.LocalPlayer
    local executorName = "Unknown"
    pcall(function()
        local caps = self.Library and self.Library.GetCapabilities and self.Library:GetCapabilities()
        if caps and caps.ExecutorName then executorName = tostring(caps.ExecutorName) end
    end)

    return {
        StartedAt = self._astraSessionUnix,
        Playtime = self:GetSessionPlaytime(),
        PlaytimeText = v311FormatDuration(self:GetSessionPlaytime(), false),
        Player = player,
        DisplayName = player and player.DisplayName or "Player",
        Username = player and player.Name or "Unknown",
        UserId = player and player.UserId or 0,
        AccountAge = player and player.AccountAge or 0,
        PlayerCount = #Players:GetPlayers(),
        PlaceId = game.PlaceId,
        JobId = game.JobId,
        Executor = executorName,
        Key = self:GetKeyInfo(),
    }
end

local function v311Theme(window, key, fallback)
    local t = window.Theme or {}
    return t[key] or t[fallback] or Color3.fromRGB(255,255,255)
end

local function v311AddCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 10)
    c.Parent = parent
    return c
end

local function v311AddStroke(parent, color, transparency, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Transparency = transparency or 0
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function v311Text(parent, text, size, color, font, xalign)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Text = tostring(text or "")
    label.TextSize = size or 12
    label.TextColor3 = color
    label.Font = font or Enum.Font.Gotham
    label.TextXAlignment = xalign or Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.Parent = parent
    return label
end

local function v311ResponsivePortrait()
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280,720)
    return viewport.X < 620 or viewport.Y > viewport.X * 1.08
end

-- Rich local-player profile -------------------------------------------------
function Tab:_addPlayerProfile(parent, data)
    data = data or {}
    local window = self.Window
    local player = Players.LocalPlayer
    local holder = Instance.new("Frame")
    holder.Name = "AstraPlayerProfile"
    holder.Size = UDim2.new(1,0,0,178)
    holder.BackgroundColor3 = v311Theme(window,"Surface","Background")
    holder.BorderSizePixel = 0
    holder.ClipsDescendants = true
    holder.Parent = parent
    holder:SetAttribute("AstraV311Role","PlayerProfile")
    v311AddCorner(holder, 15)
    local holderStroke = v311AddStroke(holder, v311Theme(window,"BorderSubtle","Border"), 0.78, 1)

    local accentBar = Instance.new("Frame")
    accentBar.Name = "AccentBar"
    accentBar.Size = UDim2.new(0,3,0,48)
    accentBar.Position = UDim2.fromOffset(0,18)
    accentBar.BackgroundColor3 = window.Theme.Accent
    accentBar.BorderSizePixel = 0
    accentBar.Parent = holder
    v311AddCorner(accentBar,999)

    local avatarShell = Instance.new("Frame")
    avatarShell.Name = "AvatarShell"
    avatarShell.Position = UDim2.fromOffset(18,16)
    avatarShell.Size = UDim2.fromOffset(70,70)
    avatarShell.BackgroundColor3 = v311Theme(window,"Surface3","Surface2")
    avatarShell.BorderSizePixel = 0
    avatarShell.Parent = holder
    v311AddCorner(avatarShell, 16)
    local avatarStroke = v311AddStroke(avatarShell, window.Theme.Accent, 0.55, 1)

    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.BackgroundTransparency = 1
    avatar.Position = UDim2.fromOffset(4,4)
    avatar.Size = UDim2.new(1,-8,1,-8)
    avatar.Image = player and ("rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=150&h=150") or ""
    avatar.ScaleType = Enum.ScaleType.Crop
    avatar.Parent = avatarShell
    v311AddCorner(avatar,13)

    local displayName = v311Text(holder, player and player.DisplayName or "Local Player", 15, v311Theme(window,"TextPrimary","Text"), Enum.Font.GothamBold)
    displayName.Position = UDim2.fromOffset(104,17)
    displayName.Size = UDim2.new(1,-260,0,22)

    local username = v311Text(holder, player and ("@" .. player.Name) or "@player", 10, v311Theme(window,"TextSecondary","Muted"), Enum.Font.Gotham)
    username.Position = UDim2.fromOffset(104,40)
    username.Size = UDim2.new(1,-260,0,18)

    local account = v311Text(holder, player and ("Account age · " .. tostring(player.AccountAge) .. " days") or "Local session", 10, v311Theme(window,"TextSecondary","Muted"), Enum.Font.Gotham)
    account.Position = UDim2.fromOffset(104,59)
    account.Size = UDim2.new(1,-260,0,18)

    local statusPill = Instance.new("Frame")
    statusPill.Name = "AccessStatus"
    statusPill.AnchorPoint = Vector2.new(1,0)
    statusPill.Position = UDim2.new(1,-16,0,18)
    statusPill.Size = UDim2.fromOffset(104,28)
    statusPill.BackgroundColor3 = v311Theme(window,"Surface3","Surface2")
    statusPill.BorderSizePixel = 0
    statusPill.Parent = holder
    v311AddCorner(statusPill,999)
    local statusDot = Instance.new("Frame")
    statusDot.Size = UDim2.fromOffset(7,7)
    statusDot.Position = UDim2.fromOffset(11,10)
    statusDot.BorderSizePixel = 0
    statusDot.Parent = statusPill
    v311AddCorner(statusDot,999)
    local statusLabel = v311Text(statusPill,"LOCAL",9,v311Theme(window,"TextPrimary","Text"),Enum.Font.GothamBold)
    statusLabel.Position = UDim2.fromOffset(25,0)
    statusLabel.Size = UDim2.new(1,-34,1,0)

    local statsFrame = Instance.new("Frame")
    statsFrame.Name = "Stats"
    statsFrame.BackgroundTransparency = 1
    statsFrame.Position = UDim2.fromOffset(16,100)
    statsFrame.Size = UDim2.new(1,-32,0,60)
    statsFrame.Parent = holder

    local grid = Instance.new("UIGridLayout")
    grid.FillDirection = Enum.FillDirection.Horizontal
    grid.FillDirectionMaxCells = 4
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.CellPadding = UDim2.fromOffset(8,0)
    grid.CellSize = UDim2.new(0.25,-6,1,0)
    grid.Parent = statsFrame

    local statRefs = {}
    local function makeStat(order, key, labelText)
        local card = Instance.new("Frame")
        card.Name = key
        card.LayoutOrder = order
        card.BackgroundColor3 = v311Theme(window,"Surface2","Surface")
        card.BorderSizePixel = 0
        card.Parent = statsFrame
        v311AddCorner(card,10)
        local st = v311AddStroke(card,v311Theme(window,"BorderSubtle","Border"),0.86,1)
        local label = v311Text(card,labelText,8,v311Theme(window,"TextSecondary","Muted"),Enum.Font.GothamBold)
        label.Position = UDim2.fromOffset(10,7)
        label.Size = UDim2.new(1,-20,0,14)
        local value = v311Text(card,"—",11,v311Theme(window,"TextPrimary","Text"),Enum.Font.GothamBold)
        value.Position = UDim2.fromOffset(10,23)
        value.Size = UDim2.new(1,-20,0,25)
        statRefs[key] = {Card=card, Stroke=st, Label=label, Value=value}
    end
    makeStat(1,"Playtime", data.PlaytimeLabel or "PLAYTIME")
    makeStat(2,"Key", data.KeyLabel or "ACCESS")
    makeStat(3,"Remaining", data.RemainingLabel or "REMAINING")
    makeStat(4,"Account", data.AccountLabel or "ACCOUNT")

    local expiryRail = Instance.new("Frame")
    expiryRail.Name = "ExpiryRail"
    expiryRail.Position = UDim2.new(0,18,1,-7)
    expiryRail.Size = UDim2.new(1,-36,0,2)
    expiryRail.BackgroundColor3 = v311Theme(window,"Surface3","Surface2")
    expiryRail.BorderSizePixel = 0
    expiryRail.Parent = holder
    v311AddCorner(expiryRail,999)
    local expiryFill = Instance.new("Frame")
    expiryFill.Size = UDim2.fromScale(1,1)
    expiryFill.BackgroundColor3 = window.Theme.Accent
    expiryFill.BorderSizePixel = 0
    expiryFill.Parent = expiryRail
    v311AddCorner(expiryFill,999)

    local object = {Instance=holder, Stats=statRefs}

    local function applyTheme()
        if not holder.Parent or window.Destroyed then return end
        holder.BackgroundColor3 = v311Theme(window,"Surface","Background")
        holderStroke.Color = v311Theme(window,"BorderSubtle","Border")
        accentBar.BackgroundColor3 = window.Theme.Accent
        avatarShell.BackgroundColor3 = v311Theme(window,"Surface3","Surface2")
        avatarStroke.Color = window.Theme.Accent
        displayName.TextColor3 = v311Theme(window,"TextPrimary","Text")
        username.TextColor3 = v311Theme(window,"TextSecondary","Muted")
        account.TextColor3 = v311Theme(window,"TextSecondary","Muted")
        statusPill.BackgroundColor3 = v311Theme(window,"Surface3","Surface2")
        statusLabel.TextColor3 = v311Theme(window,"TextPrimary","Text")
        expiryRail.BackgroundColor3 = v311Theme(window,"Surface3","Surface2")
        expiryFill.BackgroundColor3 = window.Theme.Accent
        for _,ref in pairs(statRefs) do
            ref.Card.BackgroundColor3 = v311Theme(window,"Surface2","Surface")
            ref.Stroke.Color = v311Theme(window,"BorderSubtle","Border")
            ref.Label.TextColor3 = v311Theme(window,"TextSecondary","Muted")
            ref.Value.TextColor3 = v311Theme(window,"TextPrimary","Text")
        end
    end

    local function updateLayout()
        if not holder.Parent then return end
        local portrait = v311ResponsivePortrait()
        if portrait then
            holder.Size = UDim2.new(1,0,0,250)
            avatarShell.Position = UDim2.fromOffset(16,16)
            avatarShell.Size = UDim2.fromOffset(62,62)
            displayName.Position = UDim2.fromOffset(94,16)
            displayName.Size = UDim2.new(1,-112,0,22)
            username.Position = UDim2.fromOffset(94,39)
            username.Size = UDim2.new(1,-112,0,18)
            account.Position = UDim2.fromOffset(94,58)
            account.Size = UDim2.new(1,-112,0,18)
            statusPill.Position = UDim2.fromOffset(16,88)
            statusPill.AnchorPoint = Vector2.new(0,0)
            statsFrame.Position = UDim2.fromOffset(16,124)
            statsFrame.Size = UDim2.new(1,-32,0,108)
            grid.FillDirectionMaxCells = 2
            grid.CellPadding = UDim2.fromOffset(8,8)
            grid.CellSize = UDim2.new(0.5,-4,0,50)
        else
            holder.Size = UDim2.new(1,0,0,178)
            avatarShell.Position = UDim2.fromOffset(18,16)
            avatarShell.Size = UDim2.fromOffset(70,70)
            displayName.Position = UDim2.fromOffset(104,17)
            displayName.Size = UDim2.new(1,-260,0,22)
            username.Position = UDim2.fromOffset(104,40)
            username.Size = UDim2.new(1,-260,0,18)
            account.Position = UDim2.fromOffset(104,59)
            account.Size = UDim2.new(1,-260,0,18)
            statusPill.AnchorPoint = Vector2.new(1,0)
            statusPill.Position = UDim2.new(1,-16,0,18)
            statsFrame.Position = UDim2.fromOffset(16,100)
            statsFrame.Size = UDim2.new(1,-32,0,60)
            grid.FillDirectionMaxCells = 4
            grid.CellPadding = UDim2.fromOffset(8,0)
            grid.CellSize = UDim2.new(0.25,-6,1,0)
        end
    end

    local function refresh()
        if not holder.Parent or window.Destroyed then return end
        local session = window:GetSessionInfo()
        local key = session.Key or {}
        local status = tostring(key.Status or (window.Options and window.Options.KeySystem and window.Options.KeySystem.Enabled and "Locked" or "Not required"))
        local lower = string.lower(status)
        local tone = "muted"
        if lower == "unlocked" or lower == "active" or lower == "valid" then tone = "success" end
        if lower == "expired" or lower == "revoked" then tone = "danger" end
        if lower == "locked" or lower == "checking" then tone = "warning" end
        statusDot.BackgroundColor3 = v311ToneColor(window.Theme,tone)
        statusLabel.Text = string.upper(status)

        statRefs.Playtime.Value.Text = v311FormatDuration(session.Playtime,true)
        local accessText = key.Tier or key.Plan or status
        statRefs.Key.Value.Text = tostring(accessText or "—")

        if key.ExpiresAt then
            statRefs.Remaining.Value.Text = key.Expired and "Expired" or v311FormatDuration(key.Remaining or 0,true)
            local duration = tonumber(key.Duration)
            if not duration and key.ActivatedAt then duration = math.max(1,key.ExpiresAt-key.ActivatedAt) end
            if duration and duration > 0 then
                local ratio = math.clamp((key.Remaining or 0)/duration,0,1)
                expiryFill.Size = UDim2.fromScale(ratio,1)
                expiryFill.Visible = true
            else
                expiryFill.Visible = false
            end
        else
            statRefs.Remaining.Value.Text = (lower == "locked") and "—" or "Never"
            expiryFill.Size = UDim2.fromScale(1,1)
            expiryFill.Visible = lower ~= "locked"
        end

        statRefs.Account.Value.Text = tostring(session.AccountAge) .. " days"
        if data.ShowMaskedKey == true and key.MaskedKey then
            username.Text = (player and ("@" .. player.Name) or "@player") .. "  ·  " .. key.MaskedKey
        else
            username.Text = player and ("@" .. player.Name) or "@player"
        end
    end

    function object:Refresh() refresh() end
    function object:GetPlayer() return player end
    function object:GetSessionInfo() return window:GetSessionInfo() end
    function object:GetKeyInfo() return window:GetKeyInfo() end
    function object:SetKeyInfo(info) return window:SetKeyInfo(info) end
    function object:Destroy() if holder then holder:Destroy() end end

    window:OnThemeChanged(function() applyTheme(); refresh() end)
    window:OnKeyInfoChanged(function() refresh() end)
    window:_registerSearch(holder, (data.Name or "Local Player Profile") .. " player profile key playtime account access")

    task.spawn(function()
        updateLayout()
        applyTheme()
        refresh()
        local lastViewport = Vector2.new()
        while holder.Parent and not window.Destroyed do
            local camera = workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize or Vector2.new()
            if viewport ~= lastViewport then lastViewport = viewport; updateLayout() end
            refresh()
            task.wait(1)
        end
    end)

    return object
end

-- Generic stat grid ---------------------------------------------------------
function Tab:_addStatGrid(parent, data)
    data = data or {}
    local window = self.Window
    local items = data.Items or data.Stats or {}
    local holder = Instance.new("Frame")
    holder.Name = "AstraStatGrid"
    holder.Size = UDim2.new(1,0,0,0)
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.BackgroundTransparency = 1
    holder.Parent = parent
    holder:SetAttribute("AstraV311Role","StatGrid")

    local grid = Instance.new("UIGridLayout")
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.CellPadding = UDim2.fromOffset(8,8)
    grid.Parent = holder

    local refs = {}
    local function resolveValue(item)
        if type(item.Value) == "function" then
            local ok,result = pcall(item.Value, window)
            return ok and result or "—"
        end
        return item.Value
    end

    for index,item in ipairs(items) do
        local card = Instance.new("Frame")
        card.LayoutOrder = index
        card.BackgroundColor3 = v311Theme(window,"Surface2","Surface")
        card.BorderSizePixel = 0
        card.Parent = holder
        v311AddCorner(card,11)
        local st = v311AddStroke(card,v311Theme(window,"BorderSubtle","Border"),0.84,1)
        local label = v311Text(card,item.Label or item.Name or ("STAT " .. index),8,v311Theme(window,"TextSecondary","Muted"),Enum.Font.GothamBold)
        label.Position = UDim2.fromOffset(11,7)
        label.Size = UDim2.new(1,-22,0,14)
        local value = v311Text(card,resolveValue(item) or "—",12,v311ToneColor(window.Theme,item.Tone or "text"),Enum.Font.GothamBold)
        value.Position = UDim2.fromOffset(11,23)
        value.Size = UDim2.new(1,-22,0,25)
        refs[item.Id or item.Key or index] = {Card=card,Stroke=st,Label=label,Value=value,Data=item}
    end

    local object = {Instance=holder,Items=refs}
    local function layout()
        local portrait = v311ResponsivePortrait()
        local columns = tonumber(data.Columns) or (portrait and 2 or math.min(4,math.max(1,#items)))
        local rows = math.max(1,math.ceil(#items/columns))
        grid.FillDirectionMaxCells = columns
        grid.CellSize = UDim2.new(1/columns,-(8*(columns-1))/columns,0,data.CellHeight or 56)
        holder.Size = UDim2.new(1,0,0,rows*(data.CellHeight or 56)+(rows-1)*8)
    end
    local function refresh()
        for _,ref in pairs(refs) do
            ref.Value.Text = tostring(resolveValue(ref.Data) or "—")
            ref.Value.TextColor3 = ref.Data.Tone and v311ToneColor(window.Theme,ref.Data.Tone) or v311Theme(window,"TextPrimary","Text")
            ref.Card.BackgroundColor3 = v311Theme(window,"Surface2","Surface")
            ref.Stroke.Color = v311Theme(window,"BorderSubtle","Border")
            ref.Label.TextColor3 = v311Theme(window,"TextSecondary","Muted")
        end
    end
    function object:Set(key,value,tone)
        local ref = refs[key]
        if not ref then return false end
        ref.Data.Value = value
        if tone then ref.Data.Tone = tone end
        refresh(); return true
    end
    function object:Refresh() refresh() end
    function object:Get(key) local ref=refs[key]; return ref and ref.Value.Text or nil end

    window:OnThemeChanged(refresh)
    layout(); refresh()
    if tonumber(data.AutoRefresh) and tonumber(data.AutoRefresh)>0 then
        task.spawn(function()
            while holder.Parent and not window.Destroyed do refresh(); task.wait(math.max(0.25,tonumber(data.AutoRefresh))) end
        end)
    end
    task.spawn(function()
        local last=Vector2.new()
        while holder.Parent and not window.Destroyed do
            local cam=workspace.CurrentCamera; local vp=cam and cam.ViewportSize or Vector2.new()
            if vp~=last then last=vp; layout() end
            task.wait(0.75)
        end
    end)
    return object
end

-- Reusable key/value information list --------------------------------------
function Tab:_addInfoList(parent, data)
    data = data or {}
    local window = self.Window
    local items = data.Items or data.Rows or {}
    local holder = Instance.new("Frame")
    holder.Name = "AstraInfoList"
    holder.Size = UDim2.new(1,0,0,0)
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.BackgroundColor3 = v311Theme(window,"Surface","Background")
    holder.BorderSizePixel = 0
    holder.Parent = parent
    v311AddCorner(holder,13)
    local holderStroke = v311AddStroke(holder,v311Theme(window,"BorderSubtle","Border"),0.88,1)
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = holder

    local refs = {}
    local function resolve(item)
        if type(item.Value)=="function" then
            local ok,result=pcall(item.Value,window)
            return ok and result or "—"
        end
        return item.Value
    end
    for i,item in ipairs(items) do
        local row=Instance.new("Frame")
        row.LayoutOrder=i
        row.Size=UDim2.new(1,0,0,data.RowHeight or 42)
        row.BackgroundTransparency=1
        row.Parent=holder
        if i>1 then
            local div=Instance.new("Frame")
            div.Size=UDim2.new(1,-24,0,1)
            div.Position=UDim2.fromOffset(12,0)
            div.BackgroundColor3=v311Theme(window,"BorderSubtle","Border")
            div.BackgroundTransparency=0.78
            div.BorderSizePixel=0
            div.Parent=row
        end
        local label=v311Text(row,item.Label or item.Name or ("Item "..i),10,v311Theme(window,"TextSecondary","Muted"),Enum.Font.Gotham)
        label.Position=UDim2.fromOffset(12,0); label.Size=UDim2.new(0.48,-12,1,0)
        local value=v311Text(row,resolve(item) or "—",10,v311Theme(window,"TextPrimary","Text"),Enum.Font.GothamMedium,Enum.TextXAlignment.Right)
        value.AnchorPoint=Vector2.new(1,0); value.Position=UDim2.new(1,-12,0,0); value.Size=UDim2.new(0.52,-12,1,0)
        refs[item.Id or item.Key or i]={Row=row,Label=label,Value=value,Data=item}
    end

    local object={Instance=holder,Items=refs}
    local function refresh()
        holder.BackgroundColor3=v311Theme(window,"Surface","Background")
        holderStroke.Color=v311Theme(window,"BorderSubtle","Border")
        for _,ref in pairs(refs) do
            ref.Label.TextColor3=v311Theme(window,"TextSecondary","Muted")
            ref.Value.TextColor3=ref.Data.Tone and v311ToneColor(window.Theme,ref.Data.Tone) or v311Theme(window,"TextPrimary","Text")
            ref.Value.Text=tostring(resolve(ref.Data) or "—")
        end
    end
    function object:Set(key,value,tone)
        local ref=refs[key]; if not ref then return false end
        ref.Data.Value=value; if tone then ref.Data.Tone=tone end; refresh(); return true
    end
    function object:Refresh() refresh() end
    window:OnThemeChanged(refresh); refresh()
    if tonumber(data.AutoRefresh) and tonumber(data.AutoRefresh)>0 then
        task.spawn(function() while holder.Parent and not window.Destroyed do refresh(); task.wait(math.max(0.25,tonumber(data.AutoRefresh))) end end)
    end
    return object
end

function Tab:AddPlayerProfile(data) return self:_addPlayerProfile(self.Page,data) end
function Tab:AddStatGrid(data) return self:_addStatGrid(self.Page,data) end
function Tab:AddInfoList(data) return self:_addInfoList(self.Page,data) end

local _V311CreateSection = Tab.CreateSection
function Tab:CreateSection(options)
    local section = _V311CreateSection(self,options)
    function section:AddPlayerProfile(data) return self.Tab:_addPlayerProfile(self.Content or self.Frame,data) end
    function section:AddStatGrid(data) return self.Tab:_addStatGrid(self.Content or self.Frame,data) end
    function section:AddInfoList(data) return self.Tab:_addInfoList(self.Content or self.Frame,data) end
    return section
end

-- Convenience page: one call creates a complete profile/access dashboard.
function Window:CreateProfileTab(options)
    options = options or {}
    local tab = self:CreateTab({
        Name = options.Name or "Profile",
        Icon = options.Icon or "info",
        Description = options.Description or "Player, access and session information",
    })

    local profile = tab:AddPlayerProfile({
        Name = options.Name or "Local Player",
        ShowMaskedKey = options.ShowMaskedKey == true,
    })

    local runtime = tab:CreateSection({Name=options.RuntimeTitle or "Session",Description="Live local session information",Collapsible=options.Collapsible==true})
    local stats = runtime:AddStatGrid({
        AutoRefresh = 1,
        Items = {
            {Id="Players",Label="PLAYERS",Value=function(w) return tostring(#Players:GetPlayers()) end},
            {Id="Playtime",Label="PLAYTIME",Value=function(w) return v311FormatDuration(w:GetSessionPlaytime(),true) end},
            {Id="Account",Label="ACCOUNT AGE",Value=function(w) local p=Players.LocalPlayer; return p and (tostring(p.AccountAge).." days") or "—" end},
            {Id="Executor",Label="EXECUTOR",Value=function(w) local s=w:GetSessionInfo(); return s.Executor end},
        }
    })

    local access = tab:CreateSection({Name=options.AccessTitle or "Access",Description="Key metadata and environment",Collapsible=true})
    local info = access:AddInfoList({
        AutoRefresh = 1,
        Items = {
            {Id="Status",Label="Key status",Value=function(w) return tostring(w:GetKeyInfo().Status or "Not required") end},
            {Id="Tier",Label="Access tier",Value=function(w) local k=w:GetKeyInfo(); return tostring(k.Tier or k.Plan or "Default") end},
            {Id="Duration",Label="Key duration",Value=function(w) local k=w:GetKeyInfo(); if k.Permanent then return "Permanent" end; if k.Duration then return v311FormatDuration(k.Duration,false) end; return k.ExpiresAt and "Timed" or "Unlimited" end},
            {Id="Remaining",Label="Remaining",Value=function(w) local k=w:GetKeyInfo(); if k.ExpiresAt then return k.Expired and "Expired" or v311FormatDuration(k.Remaining or 0,false) end; return "Never" end},
            {Id="Key",Label="Key",Value=function(w) return tostring(w:GetKeyInfo().MaskedKey or "Not stored") end},
            {Id="UserId",Label="User ID",Value=function() local p=Players.LocalPlayer; return p and tostring(p.UserId) or "—" end},
            {Id="Place",Label="Place ID",Value=function() return tostring(game.PlaceId) end},
        }
    })

    return tab, profile, stats, info
end

-- Integrate key validation metadata into the existing key gate --------------
local _V311CreateWindow = AstraUI.CreateWindow
function AstraUI:CreateWindow(options)
    options = v311Copy(options or {})
    local keyConfig = type(options.KeySystem)=="table" and v311Copy(options.KeySystem) or options.KeySystem
    local windowRef = nil
    local pendingMeta = nil

    if type(keyConfig)=="table" then
        local rawValidate = keyConfig.Validate
        local rawOnSuccess = keyConfig.OnSuccess

        if type(rawValidate)=="function" then
            keyConfig.Validate = function(value)
                local ok,a,b,c = pcall(rawValidate,value)
                if not ok then return false,"Validator failed." end
                local valid=false
                local message=nil
                local meta=nil

                if type(a)=="table" then
                    valid = a.Valid==true or a.Success==true or a.Authorized==true
                    message = a.Message or a.message
                    meta = a.KeyInfo or a.Metadata or a.Meta
                    if not meta and valid then meta=a end
                else
                    valid = a==true
                    if type(b)=="table" then
                        meta=b
                        message=b.Message or b.message
                    else
                        message=type(b)=="string" and b or nil
                        if type(c)=="table" then meta=c end
                    end
                end

                if valid then pendingMeta = meta end
                return valid,message
            end
        end

        keyConfig.OnSuccess = function(value)
            if windowRef then
                local meta = pendingMeta or keyConfig.Metadata or keyConfig.KeyInfo or {}
                meta = v311Copy(meta)
                meta.Status = meta.Status or "Unlocked"
                windowRef:SetKeyInfo(meta,value)
            end
            safeCall(rawOnSuccess,value,windowRef)
        end
        options.KeySystem = keyConfig
    end

    local window = _V311CreateWindow(self,options)
    windowRef = window
    window._astraSessionClock = v311NowClock()
    window._astraSessionUnix = v311NowUnix()
    window._astraKeyListeners = window._astraKeyListeners or {}

    local initial = type(keyConfig)=="table" and (keyConfig.Metadata or keyConfig.KeyInfo) or nil
    window._astraKeyInfo = v311NormalizeKeyInfo(initial,false)
    if type(keyConfig)=="table" and keyConfig.Enabled then
        window._astraKeyInfo.Status = window.KeyUnlocked and "Unlocked" or "Locked"
    else
        window._astraKeyInfo.Status = window._astraKeyInfo.Status or "Not required"
    end

    return window
end

AstraUI.Version = V311_VERSION
end)()

-- ============================================================================
-- AstraUI V4.0 - Application Framework
-- A broad application-layer expansion on top of the V3.11 foundation.
-- The goal is to make Astra capable of building complete executor dashboards,
-- not only rows of toggles/sliders/dropdowns.
-- ============================================================================
;(function()
local V4_VERSION = "4.0.0-application"

local GuiService = nil
local StatsService = nil
local MarketplaceService = nil
pcall(function() GuiService = game:GetService("GuiService") end)
pcall(function() StatsService = game:GetService("Stats") end)
pcall(function() MarketplaceService = game:GetService("MarketplaceService") end)

local function v4Copy(source)
    local out = {}
    for k,v in pairs(source or {}) do out[k]=v end
    return out
end

local function v4Clamp(v,a,b)
    return math.max(a,math.min(b,v))
end

local function v4Mix(a,b,t)
    return Color3.new(a.R+(b.R-a.R)*t,a.G+(b.G-a.G)*t,a.B+(b.B-a.B)*t)
end

local function v4Tone(window,tone)
    tone=string.lower(tostring(tone or "accent"))
    if tone=="success" then return window.Theme.Success end
    if tone=="warning" then return window.Theme.Warning end
    if tone=="danger" or tone=="error" then return window.Theme.Danger end
    if tone=="muted" or tone=="neutral" then return window.Theme.TextSecondary or window.Theme.Muted end
    return window.Theme.Accent
end

local function v4Round(parent,r)
    local c=Instance.new("UICorner")
    c.CornerRadius=UDim.new(0,r or 10)
    c.Parent=parent
    return c
end

local function v4Stroke(parent,color,alpha,thickness)
    local s=Instance.new("UIStroke")
    s.Color=color or Color3.new(1,1,1)
    s.Transparency=alpha or 0
    s.Thickness=thickness or 1
    s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
    s.Parent=parent
    return s
end

local function v4Padding(parent,l,r,t,b)
    local p=Instance.new("UIPadding")
    p.PaddingLeft=UDim.new(0,l or 0)
    p.PaddingRight=UDim.new(0,r or l or 0)
    p.PaddingTop=UDim.new(0,t or l or 0)
    p.PaddingBottom=UDim.new(0,b or t or l or 0)
    p.Parent=parent
    return p
end

local function v4List(parent,gap,hAlign)
    local l=Instance.new("UIListLayout")
    l.FillDirection=Enum.FillDirection.Vertical
    l.SortOrder=Enum.SortOrder.LayoutOrder
    l.Padding=UDim.new(0,gap or 6)
    l.HorizontalAlignment=hAlign or Enum.HorizontalAlignment.Left
    l.Parent=parent
    return l
end

local function v4Label(parent,text,size,color,bold)
    local l=Instance.new("TextLabel")
    l.BackgroundTransparency=1
    l.BorderSizePixel=0
    l.Text=tostring(text or "")
    l.TextSize=size or 12
    l.TextColor3=color or Color3.new(1,1,1)
    l.Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham
    l.TextXAlignment=Enum.TextXAlignment.Left
    l.TextYAlignment=Enum.TextYAlignment.Center
    l.TextWrapped=true
    l.Size=UDim2.new(1,0,0,size and size+8 or 20)
    l.Parent=parent
    return l
end

local function v4Button(parent,text,size,bg,fg)
    local b=Instance.new("TextButton")
    b.AutoButtonColor=false
    b.BorderSizePixel=0
    b.BackgroundColor3=bg
    b.Text=tostring(text or "")
    b.TextColor3=fg or Color3.new(1,1,1)
    b.TextSize=11
    b.Font=Enum.Font.GothamMedium
    b.Size=size or UDim2.fromOffset(90,32)
    b.Parent=parent
    v4Round(b,10)
    return b
end

local function v4FormatDuration(seconds,short)
    seconds=math.max(0,math.floor(tonumber(seconds) or 0))
    local d=math.floor(seconds/86400); seconds%=86400
    local h=math.floor(seconds/3600); seconds%=3600
    local m=math.floor(seconds/60); local s=seconds%60
    if short then
        if d>0 then return string.format("%dd %dh",d,h) end
        if h>0 then return string.format("%dh %dm",h,m) end
        if m>0 then return string.format("%dm %ds",m,s) end
        return string.format("%ds",s)
    end
    local parts={}
    if d>0 then table.insert(parts,d.."d") end
    if h>0 then table.insert(parts,h.."h") end
    if m>0 then table.insert(parts,m.."m") end
    if #parts<2 and s>0 then table.insert(parts,s.."s") end
    return #parts>0 and table.concat(parts," ") or "0s"
end

local function v4SafeText(value,window)
    if type(value)=="function" then
        local ok,result=pcall(value,window)
        if ok then return tostring(result == nil and "—" or result) end
        return "Error"
    end
    if value==nil then return "—" end
    return tostring(value)
end

local function v4GetPreferredInput()
    local result="Unknown"
    pcall(function()
        local p=UserInputService.PreferredInput
        result=p and p.Name or result
    end)
    if result=="Unknown" then
        if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then result="Touch"
        elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then result="Gamepad"
        else result="KeyboardAndMouse" end
    end
    return result
end

local function v4GetPing()
    local ping=0
    if StatsService then
        pcall(function()
            local network=StatsService.Network
            local item=network and network.ServerStatsItem and network.ServerStatsItem["Data Ping"]
            if item then ping=tonumber(item:GetValue()) or 0 end
        end)
    end
    return math.floor(ping+0.5)
end

local function v4GetMemory()
    local memory=0
    if StatsService then
        pcall(function() memory=StatsService:GetTotalMemoryUsageMb() end)
    end
    return math.floor((tonumber(memory) or 0)+0.5)
end

local function v4GetSafeArea()
    local tl,br=Vector2.zero,Vector2.zero
    if GuiService then
        pcall(function() tl,br=GuiService:GetGuiInset() end)
    end
    return tl,br
end

local function v4GetLayoutProfile()
    local camera=workspace.CurrentCamera
    local vp=camera and camera.ViewportSize or Vector2.new(1280,720)
    local input=v4GetPreferredInput()
    if input=="Gamepad" and vp.X>=1000 then return "GamepadTV",vp end
    if vp.X<=360 then return "TinyPortrait",vp end
    if vp.Y>vp.X then
        if vp.X<520 then return "TouchPortrait",vp end
        return "TabletPortrait",vp
    end
    if input=="Touch" then
        if vp.X<900 then return "TouchLandscape",vp end
        return "TabletLandscape",vp
    end
    if vp.X>=1600 then return "DesktopWide",vp end
    return "Desktop",vp
end

-- Public metadata ------------------------------------------------------------
AstraUI.ApplicationFramework = {
    Version = V4_VERSION,
    Features = {
        "Dashboard","PlayerProfile","ActivityFeed","CommandPalette","GlobalSearch",
        "Announcement","Changelog","WhatsNew","QuickActions","SegmentedControl",
        "Checkbox","RadioGroup","Stepper","RangeSlider","NumberInput","ComboBox",
        "TagInput","Badges","ProgressCard","CircularProgress","Skeleton","StateCards",
        "DataGrid","Lists","PlayerList","ServerCard","RuntimeMonitor","PerformanceGraph",
        "SystemHealth","CapabilityViewer","Dependencies","KeyCard","LockedFeatures",
        "ConfigManager","Autosave","UndoRedo","ConfigDiff","Presets","FlagInspector",
        "DebugConsole","DeveloperMode","Playground","NotificationCenter","Snackbar",
        "ModalSuite","BottomSheet","SidePanel","Drawer","Accordion","Subtabs",
        "Pagination","VirtualizedList","LazyRendering","Pooling","AdaptiveInput",
        "GamepadNavigation","KeyboardNavigation","Shortcuts","KeyboardAwareness",
        "PreferredTextSize","UIScale","Density","MotionIntensity","HighContrast",
        "ReduceTransparency","ColorBlindStates","SafeArea","Breakpoints","Localization",
        "IconLibrary","Avatar","UserCard","StatusDot","Timeline","Favorites","Recent"
    }
}

AstraUI.Icons = {
    home="home", search="search", settings="settings", visuals="visuals", automation="automation",
    profile="info", user="info", server="runtime", key="config", shield="config", clock="runtime",
    play="runtime", pause="runtime", save="config", folder="config", trash="config", copy="config",
    check="info", warning="info", error="info", info="info", star="info", pin="info", bell="info",
    command="runtime", terminal="runtime", refresh="runtime", download="config", upload="config",
    arrow="runtime", chevron="runtime", lock="config", unlock="config", eye="visuals", eyeoff="visuals"
}

function AstraUI:Localize(value,locale)
    if type(value)=="function" then
        local ok,result=pcall(value,locale or "en-us")
        return ok and tostring(result or "") or ""
    end
    if type(value)=="table" then
        local key=string.lower(tostring(locale or "en-us"))
        return tostring(value[key] or value[string.sub(key,1,2)] or value.Default or value.default or next(value) and select(2,next(value)) or "")
    end
    return tostring(value or "")
end

function AstraUI:CreatePool(factory,reset)
    local free={}
    local active={}
    local pool={}
    function pool:Acquire(...)
        local item=table.remove(free)
        if not item then item=factory(...) end
        active[item]=true
        return item
    end
    function pool:Release(item)
        if not item or not active[item] then return end
        active[item]=nil
        if type(reset)=="function" then pcall(reset,item) end
        table.insert(free,item)
    end
    function pool:Clear()
        for item in pairs(active) do pcall(function() item:Destroy() end) end
        for _,item in ipairs(free) do pcall(function() item:Destroy() end) end
        table.clear(active); table.clear(free)
    end
    return pool
end

-- Window application state --------------------------------------------------
local function v4InitWindow(window)
    if window._v4Ready then return end
    window._v4Ready=true
    window._v4Commands={}
    window._v4Activity={}
    window._v4Notifications={}
    window._v4Pinned={}
    window._v4Recent={}
    window._v4History={}
    window._v4Redo={}
    window._v4Presets={}
    window._v4Shortcuts={}
    window._v4Logs={}
    window._v4LazyTabs={}
    window._v4Preferences={
        UIScale=1,
        Density=window.Density or "Comfortable",
        MotionIntensity="Normal",
        ReduceTransparency=false,
        HighContrast=false,
        ColorBlindMode="None",
        RespectPreferredTextSize=true,
    }
    window._v4Telemetry={FPS=60,Ping=0,Memory=0,PreferredInput=v4GetPreferredInput(),LayoutProfile=v4GetLayoutProfile()}
    window._v4FrameCount=0
    window._v4FrameElapsed=0
    window._v4NotificationId=0
    window._v4ActivityId=0

    window:_connect(RunService.RenderStepped,function(dt)
        window._v4FrameCount+=1
        window._v4FrameElapsed+=dt
        if window._v4FrameElapsed>=1 then
            local elapsed=window._v4FrameElapsed
            window._v4Telemetry.FPS=math.floor(window._v4FrameCount/elapsed+0.5)
            window._v4Telemetry.Ping=v4GetPing()
            window._v4Telemetry.Memory=v4GetMemory()
            window._v4Telemetry.PreferredInput=v4GetPreferredInput()
            window._v4Telemetry.LayoutProfile=v4GetLayoutProfile()
            window._v4FrameCount=0
            window._v4FrameElapsed=0
        end
    end)

    -- Adaptive input changes without making touch depend on mouse hover.
    pcall(function()
        window:_connect(UserInputService:GetPropertyChangedSignal("PreferredInput"),function()
            window._v4Telemetry.PreferredInput=v4GetPreferredInput()
            window._v4Telemetry.LayoutProfile=v4GetLayoutProfile()
        end)
    end)

    -- Central shortcut manager.
    window:_connect(UserInputService.InputBegan,function(input,processed)
        if processed then return end
        for _,shortcut in ipairs(window._v4Shortcuts) do
            if shortcut.Enabled~=false and input.KeyCode==shortcut.Key then
                local modifiersOK=true
                if shortcut.Ctrl then modifiersOK=UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) end
                if modifiersOK and shortcut.Shift then modifiersOK=UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift) end
                if modifiersOK and shortcut.Alt then modifiersOK=UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) or UserInputService:IsKeyDown(Enum.KeyCode.RightAlt) end
                if modifiersOK then safeCall(shortcut.Callback,shortcut) end
            end
        end
    end)
end

local _V4CreateWindow=AstraUI.CreateWindow
function AstraUI:CreateWindow(options)
    options=v4Copy(options or {})
    if options.ShowMoreButton==nil then options.ShowMoreButton=true end
    local window=_V4CreateWindow(self,options)
    v4InitWindow(window)

    -- Optional topbar More button. ASCII avoids font/tofu issues.
    if options.ShowMoreButton~=false and window.ThemeButton and window.ThemeButton.Parent then
        local host=window.ThemeButton.Parent
        local more=v4Button(host,"...",UDim2.fromOffset(34,34),window.Theme.Surface2,window.Theme.TextSecondary)
        more.Name="AstraMoreButton"
        more.TextSize=14
        more.AnchorPoint=Vector2.new(0,0)
        window.MoreButton=more
        if window.MinimizeButton then
            host.Size=UDim2.fromOffset(118,34)
            window.ThemeButton.Position=UDim2.fromOffset(0,0)
            window.MinimizeButton.Position=UDim2.fromOffset(42,0)
            more.Position=UDim2.fromOffset(84,0)
        end
        window:_connect(more.MouseButton1Click,function() window:OpenMoreMenu(more) end)
    end

    -- Default commands make the palette useful immediately.
    window:RegisterCommand({Name="Home",Category="Navigation",Keywords={"home","dashboard"},Callback=function() if window.Tabs[1] then window:SelectTab(window.Tabs[1]) end end})
    window:RegisterCommand({Name="Toggle Sidebar",Category="Interface",Keywords={"sidebar","menu"},Callback=function() window:ToggleSidebar() end})
    window:RegisterCommand({Name="Center Interface",Category="Interface",Keywords={"center","reset position"},Callback=function() window:Center() end})
    window:RegisterCommand({Name="Save Config",Category="Config",Keywords={"save","config"},Shortcut="Ctrl+S",Callback=function() if window.SaveConfigFile then window:SaveConfigFile() end end})
    window:RegisterCommand({Name="Load Config",Category="Config",Keywords={"load","config"},Callback=function() if window.LoadConfigFile then window:LoadConfigFile() end end})
    window:RegisterCommand({Name="Undo",Category="Edit",Keywords={"undo","back"},Shortcut="Ctrl+Z",Callback=function() window:Undo() end})
    window:RegisterCommand({Name="Redo",Category="Edit",Keywords={"redo"},Shortcut="Ctrl+Y",Callback=function() window:Redo() end})

    window:RegisterShortcut({Key=Enum.KeyCode.K,Ctrl=true,Name="Command Palette",Callback=function() window:OpenCommandPalette() end})
    window:RegisterShortcut({Key=Enum.KeyCode.S,Ctrl=true,Name="Save Config",Callback=function() if window.SaveConfigFile then window:SaveConfigFile() end end})
    window:RegisterShortcut({Key=Enum.KeyCode.Z,Ctrl=true,Name="Undo",Callback=function() window:Undo() end})
    window:RegisterShortcut({Key=Enum.KeyCode.Y,Ctrl=true,Name="Redo",Callback=function() window:Redo() end})

    return window
end

function Window:GetTelemetry()
    v4InitWindow(self)
    local t=v4Copy(self._v4Telemetry)
    local camera=workspace.CurrentCamera
    local vp=camera and camera.ViewportSize or Vector2.zero
    t.Viewport=vp
    t.ViewportText=string.format("%d×%d",vp.X,vp.Y)
    t.PlayerCount=#Players:GetPlayers()
    t.MaxPlayers=Players.MaxPlayers
    t.SessionPlaytime=self.GetSessionPlaytime and self:GetSessionPlaytime() or 0
    t.SessionPlaytimeText=v4FormatDuration(t.SessionPlaytime,true)
    t.AstraVersion=AstraUI.Version
    t.Executor=(self.GetSessionInfo and self:GetSessionInfo().Executor) or "Unknown"
    return t
end

function Window:GetLayoutProfile()
    local profile,vp=v4GetLayoutProfile()
    return profile,vp
end

function Window:GetSafeArea()
    return v4GetSafeArea()
end

-- Activity / logging --------------------------------------------------------
function Window:LogActivity(data)
    v4InitWindow(self)
    data=v4Copy(data or {})
    self._v4ActivityId+=1
    local item={
        Id=self._v4ActivityId,
        Title=tostring(data.Title or "Activity"),
        Description=tostring(data.Description or data.Content or ""),
        Tone=data.Tone or data.Type or "accent",
        Icon=data.Icon,
        Time=os.time(),
        Clock=os.clock(),
        Metadata=data.Metadata,
    }
    table.insert(self._v4Activity,1,item)
    while #self._v4Activity>(tonumber(data.MaxHistory) or 100) do table.remove(self._v4Activity) end
    return item
end

function Window:GetActivity(limit)
    v4InitWindow(self)
    local out={}
    for i=1,math.min(#self._v4Activity,tonumber(limit) or #self._v4Activity) do out[i]=self._v4Activity[i] end
    return out
end

function Window:ClearActivity()
    v4InitWindow(self); table.clear(self._v4Activity)
end

function Window:Log(level,message,details)
    v4InitWindow(self)
    local entry={Time=os.time(),Level=string.upper(tostring(level or "INFO")),Message=tostring(message or ""),Details=details}
    table.insert(self._v4Logs,entry)
    while #self._v4Logs>300 do table.remove(self._v4Logs,1) end
    return entry
end

-- Notification history and snackbar ----------------------------------------
local _V4Notify=Window.Notify
function Window:Notify(options)
    v4InitWindow(self)
    options=v4Copy(options or {})
    self._v4NotificationId+=1
    local key=tostring(options.Title or "Notification").."\0"..tostring(options.Content or options.Text or "")
    local found=nil
    for _,n in ipairs(self._v4Notifications) do if n.Key==key then found=n; break end end
    if found then
        found.Count=(found.Count or 1)+1
        found.Time=os.time()
    else
        table.insert(self._v4Notifications,1,{Id=self._v4NotificationId,Key=key,Title=options.Title or "Notification",Content=options.Content or options.Text or "",Type=options.Type or "info",Time=os.time(),Count=1})
    end
    while #self._v4Notifications>100 do table.remove(self._v4Notifications) end
    if options.Persistent==true then options.Duration=86400 end
    return _V4Notify(self,options)
end

function Window:GetNotifications()
    v4InitWindow(self); return self._v4Notifications
end

function Window:ShowSnackbar(options)
    options=type(options)=="table" and options or {Text=tostring(options)}
    local host=self.ScreenGui
    if not host then return end
    local card=Instance.new("Frame")
    card.Name="AstraSnackbar"
    card.AnchorPoint=Vector2.new(0.5,1)
    card.Position=UDim2.new(0.5,0,1,-24)
    card.Size=UDim2.fromOffset(math.min(420,math.max(180,120+#tostring(options.Text or options.Content or "")*4)),42)
    card.BackgroundColor3=self.Theme.Surface3
    card.BorderSizePixel=0
    card.ZIndex=300
    card.Parent=host
    v4Round(card,12); v4Stroke(card,self.Theme.BorderDefault or self.Theme.Border,0.45,1)
    local text=v4Label(card,options.Text or options.Content or "Done",11,self.Theme.TextPrimary,true)
    text.Position=UDim2.fromOffset(14,0); text.Size=UDim2.new(1,-28,1,0); text.TextWrapped=false
    card.Position=UDim2.new(0.5,0,1,18)
    tween(card,0.18,{Position=UDim2.new(0.5,0,1,-24)})
    task.delay(options.Duration or 2.2,function()
        if card and card.Parent then
            tween(card,0.14,{Position=UDim2.new(0.5,0,1,18),BackgroundTransparency=1})
            task.delay(0.15,function() if card then card:Destroy() end end)
        end
    end)
    return card
end

-- Commands / global search --------------------------------------------------
function Window:RegisterCommand(command)
    v4InitWindow(self)
    command=v4Copy(command or {})
    command.Name=tostring(command.Name or "Command")
    command.Category=tostring(command.Category or "General")
    command.Keywords=command.Keywords or {}
    table.insert(self._v4Commands,command)
    return command
end
Window.AddCommand=Window.RegisterCommand

function Window:SearchAll(query)
    v4InitWindow(self)
    query=string.lower(tostring(query or ""))
    local results={}
    local function add(kind,name,description,callback,score,source)
        table.insert(results,{Kind=kind,Name=name,Description=description or "",Callback=callback,Score=score or 0,Source=source})
    end
    for _,cmd in ipairs(self._v4Commands) do
        local hay=string.lower(cmd.Name.." "..cmd.Category.." "..table.concat(cmd.Keywords or {}," "))
        if query=="" or string.find(hay,query,1,true) then add("Command",cmd.Name,cmd.Category,cmd.Callback,string.find(string.lower(cmd.Name),query,1,true) and 3 or 1,cmd) end
    end
    for _,tab in ipairs(self.Tabs or {}) do
        local hay=string.lower(tostring(tab.Name or "").." "..tostring(tab.Description or ""))
        if query=="" or string.find(hay,query,1,true) then add("Tab",tab.Name,tab.Description,function() self:SelectTab(tab) end,string.find(string.lower(tab.Name),query,1,true) and 3 or 1,tab) end
    end
    for _,item in ipairs(self._searchItems or {}) do
        local text=tostring(item.SearchText or "")
        if item.Instance and item.Instance.Parent and (query=="" or string.find(string.lower(text),query,1,true)) then
            add("Control",text,"Interface control",function()
                local tab=nil
                for _,candidate in ipairs(self.Tabs or {}) do if item.Instance:IsDescendantOf(candidate.Page) then tab=candidate; break end end
                if tab then self:SelectTab(tab) end
            end,1,item)
        end
    end
    table.sort(results,function(a,b) if a.Score==b.Score then return a.Name<b.Name end return a.Score>b.Score end)
    return results
end

function Window:OpenCommandPalette(initial)
    if self._v4Palette and self._v4Palette.Parent then self._v4Palette:Destroy() end
    local overlay=Instance.new("Frame")
    overlay.Name="AstraCommandPalette"
    overlay.Size=UDim2.fromScale(1,1)
    overlay.BackgroundColor3=Color3.new(0,0,0)
    overlay.BackgroundTransparency=0.38
    overlay.BorderSizePixel=0
    overlay.ZIndex=500
    overlay.Parent=self.ScreenGui
    self._v4Palette=overlay

    local panel=Instance.new("Frame")
    panel.AnchorPoint=Vector2.new(0.5,0)
    panel.Position=UDim2.new(0.5,0,0,72)
    panel.Size=UDim2.fromOffset(520,430)
    panel.BackgroundColor3=self.Theme.Surface
    panel.BorderSizePixel=0
    panel.ZIndex=501
    panel.Parent=overlay
    v4Round(panel,16); v4Stroke(panel,self.Theme.BorderDefault or self.Theme.Border,0.30,1)

    local profile=self:GetLayoutProfile()
    if profile=="TouchPortrait" or profile=="TinyPortrait" then
        panel.AnchorPoint=Vector2.new(0.5,1)
        panel.Position=UDim2.new(0.5,0,1,-8)
        panel.Size=UDim2.new(1,-16,0,math.min(520,(workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y or 700)-36))
    end

    local input=Instance.new("TextBox")
    input.ClearTextOnFocus=false
    input.PlaceholderText="Search commands, tabs and controls..."
    input.PlaceholderColor3=self.Theme.TextSecondary
    input.Text=tostring(initial or "")
    input.TextColor3=self.Theme.TextPrimary
    input.TextSize=13
    input.Font=Enum.Font.Gotham
    input.TextXAlignment=Enum.TextXAlignment.Left
    input.BackgroundColor3=self.Theme.Surface2
    input.BorderSizePixel=0
    input.Position=UDim2.fromOffset(12,12)
    input.Size=UDim2.new(1,-24,0,44)
    input.ZIndex=502
    input.Parent=panel
    v4Round(input,11); v4Stroke(input,self.Theme.BorderDefault or self.Theme.Border,0.5,1); v4Padding(input,14,14,0,0)

    local list=Instance.new("ScrollingFrame")
    list.BackgroundTransparency=1; list.BorderSizePixel=0; list.Position=UDim2.fromOffset(12,68); list.Size=UDim2.new(1,-24,1,-80)
    list.AutomaticCanvasSize=Enum.AutomaticSize.Y; list.CanvasSize=UDim2.new(); list.ScrollBarThickness=2; list.ScrollBarImageColor3=self.Theme.Scrollbar or self.Theme.TextSecondary; list.ZIndex=502; list.Parent=panel
    local layout=v4List(list,6); v4Padding(list,0,4,0,4)

    local selected=1
    local rendered={}
    local function close() if overlay then overlay:Destroy() end self._v4Palette=nil end
    local function render()
        for _,child in ipairs(list:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
        rendered={}
        local results=self:SearchAll(input.Text)
        for i=1,math.min(#results,24) do
            local result=results[i]
            local row=v4Button(list,"",UDim2.new(1,-4,0,48),self.Theme.Surface2,self.Theme.TextPrimary)
            row.LayoutOrder=i; row.ZIndex=503
            local name=v4Label(row,result.Name,12,self.Theme.TextPrimary,true); name.Position=UDim2.fromOffset(12,5); name.Size=UDim2.new(1,-100,0,18); name.ZIndex=504
            local desc=v4Label(row,result.Kind.." · "..result.Description,10,self.Theme.TextSecondary,false); desc.Position=UDim2.fromOffset(12,24); desc.Size=UDim2.new(1,-100,0,16); desc.ZIndex=504
            local kind=v4Label(row,result.Kind,9,self.Theme.TextSecondary,true); kind.AnchorPoint=Vector2.new(1,0.5); kind.Position=UDim2.new(1,-12,0.5,0); kind.Size=UDim2.fromOffset(76,18); kind.TextXAlignment=Enum.TextXAlignment.Right; kind.ZIndex=504
            local function activate() close(); safeCall(result.Callback,result) end
            self:_connect(row.MouseButton1Click,activate)
            rendered[i]={Button=row,Activate=activate}
        end
        selected=v4Clamp(selected,1,math.max(1,#rendered))
    end
    self:_connect(input:GetPropertyChangedSignal("Text"),render)
    self:_connect(overlay.InputBegan,function(io)
        if io.UserInputType==Enum.UserInputType.MouseButton1 and io.Position.X<panel.AbsolutePosition.X then close() end
    end)
    self:_connect(UserInputService.InputBegan,function(io,processed)
        if not overlay.Parent then return end
        if io.KeyCode==Enum.KeyCode.Escape then close()
        elseif io.KeyCode==Enum.KeyCode.Down then selected=v4Clamp(selected+1,1,#rendered)
        elseif io.KeyCode==Enum.KeyCode.Up then selected=v4Clamp(selected-1,1,#rendered)
        elseif io.KeyCode==Enum.KeyCode.Return and rendered[selected] then rendered[selected].Activate() end
    end)
    render(); task.defer(function() if input.Parent then input:CaptureFocus() end end)
    return overlay
end

-- Context menus / transient surfaces ---------------------------------------
function Window:ContextMenu(anchor,items,options)
    options=options or {}
    if self._v4Context and self._v4Context.Parent then self._v4Context:Destroy() end
    local overlay=Instance.new("TextButton")
    overlay.Text=""; overlay.AutoButtonColor=false; overlay.BackgroundTransparency=1; overlay.Size=UDim2.fromScale(1,1); overlay.ZIndex=600; overlay.Parent=self.ScreenGui
    local menu=Instance.new("Frame")
    menu.BackgroundColor3=self.Theme.Surface3; menu.BorderSizePixel=0; menu.Size=UDim2.fromOffset(options.Width or 190,math.max(38,#items*40+8)); menu.ZIndex=601; menu.Parent=overlay
    v4Round(menu,12); v4Stroke(menu,self.Theme.BorderDefault or self.Theme.Border,0.35,1); v4Padding(menu,4,4,4,4); v4List(menu,2)
    local pos=anchor and anchor.AbsolutePosition or UserInputService:GetMouseLocation()
    local size=anchor and anchor.AbsoluteSize or Vector2.zero
    menu.Position=UDim2.fromOffset(pos.X,pos.Y+size.Y+4)
    task.defer(function()
        local vp=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,720)
        local x=math.min(menu.AbsolutePosition.X,vp.X-menu.AbsoluteSize.X-8)
        local y=math.min(menu.AbsolutePosition.Y,vp.Y-menu.AbsoluteSize.Y-8)
        menu.Position=UDim2.fromOffset(math.max(8,x),math.max(8,y))
    end)
    self._v4Context=overlay
    for i,item in ipairs(items or {}) do
        local b=v4Button(menu,item.Text or item.Name or "Action",UDim2.new(1,0,0,38),self.Theme.Surface3,self.Theme.TextPrimary)
        b.LayoutOrder=i; b.TextXAlignment=Enum.TextXAlignment.Left; v4Padding(b,12,8,0,0)
        if item.Danger then b.TextColor3=self.Theme.Danger end
        self:_connect(b.MouseButton1Click,function() overlay:Destroy(); self._v4Context=nil; safeCall(item.Callback,item) end)
    end
    self:_connect(overlay.MouseButton1Click,function() overlay:Destroy(); self._v4Context=nil end)
    return overlay
end

function Window:AttachContextMenu(gui,items)
    if not gui then return end
    local touchToken=0
    self:_connect(gui.InputBegan,function(io)
        if io.UserInputType==Enum.UserInputType.MouseButton2 then self:ContextMenu(gui,items)
        elseif io.UserInputType==Enum.UserInputType.Touch then
            touchToken+=1; local token=touchToken
            task.delay(0.55,function() if token==touchToken and gui.Parent then self:ContextMenu(gui,items) end end)
        end
    end)
    self:_connect(gui.InputEnded,function(io) if io.UserInputType==Enum.UserInputType.Touch then touchToken+=1 end end)
end

function Window:OpenMoreMenu(anchor)
    local items={
        {Name="Command Palette",Callback=function() self:OpenCommandPalette() end},
        {Name="Save configuration",Callback=function() if self.SaveConfigFile then self:SaveConfigFile() end end},
        {Name="Load configuration",Callback=function() if self.LoadConfigFile then self:LoadConfigFile() end end},
        {Name="Notification Center",Callback=function() self:OpenNotificationCenter() end},
        {Name="Center interface",Callback=function() self:Center() end},
        {Name="Toggle sidebar",Callback=function() self:ToggleSidebar() end},
        {Name="Reset controls",Callback=function() if self.ResetConfig then self:ResetConfig(true) end end},
        {Name="Unload",Danger=true,Callback=function() self:Destroy() end},
    }
    return self:ContextMenu(anchor,items,{Width=210})
end

function Window:BottomSheet(options)
    options=options or {}
    local overlay=Instance.new("TextButton")
    overlay.Text=""; overlay.AutoButtonColor=false; overlay.Size=UDim2.fromScale(1,1); overlay.BackgroundColor3=Color3.new(0,0,0); overlay.BackgroundTransparency=0.45; overlay.ZIndex=650; overlay.Parent=self.ScreenGui
    local sheet=Instance.new("Frame")
    sheet.AnchorPoint=Vector2.new(0.5,1); sheet.Position=UDim2.new(0.5,0,1,12); sheet.Size=UDim2.new(1,-16,0,options.Height or 360); sheet.BackgroundColor3=self.Theme.Surface; sheet.BorderSizePixel=0; sheet.ZIndex=651; sheet.Parent=overlay
    v4Round(sheet,18); v4Stroke(sheet,self.Theme.BorderDefault or self.Theme.Border,0.32,1)
    local handle=Instance.new("Frame"); handle.AnchorPoint=Vector2.new(0.5,0); handle.Position=UDim2.new(0.5,0,0,8); handle.Size=UDim2.fromOffset(38,4); handle.BackgroundColor3=self.Theme.TextSecondary; handle.BackgroundTransparency=0.55; handle.BorderSizePixel=0; handle.ZIndex=652; handle.Parent=sheet; v4Round(handle,999)
    local title=v4Label(sheet,options.Title or "",15,self.Theme.TextPrimary,true); title.Position=UDim2.fromOffset(16,18); title.Size=UDim2.new(1,-32,0,24); title.ZIndex=652
    local content=Instance.new("Frame"); content.BackgroundTransparency=1; content.Position=UDim2.fromOffset(16,50); content.Size=UDim2.new(1,-32,1,-66); content.ZIndex=652; content.Parent=sheet
    local closed=false
    local function close()
        if closed then return end; closed=true
        tween(sheet,0.18,{Position=UDim2.new(0.5,0,1,16)}); tween(overlay,0.18,{BackgroundTransparency=1})
        task.delay(0.19,function() if overlay then overlay:Destroy() end end)
    end
    self:_connect(overlay.MouseButton1Click,close)
    tween(sheet,0.22,{Position=UDim2.new(0.5,0,1,-8)})
    if type(options.Build)=="function" then safeCall(options.Build,content,close,self) end
    return {Overlay=overlay,Sheet=sheet,Content=content,Close=close}
end

function Window:SidePanel(options)
    options=options or {}
    local overlay=Instance.new("TextButton"); overlay.Text=""; overlay.AutoButtonColor=false; overlay.Size=UDim2.fromScale(1,1); overlay.BackgroundColor3=Color3.new(0,0,0); overlay.BackgroundTransparency=0.55; overlay.ZIndex=640; overlay.Parent=self.ScreenGui
    local panel=Instance.new("Frame"); panel.AnchorPoint=Vector2.new(1,0); panel.Position=UDim2.new(1,options.Width or 360,0,0); panel.Size=UDim2.new(0,options.Width or 360,1,0); panel.BackgroundColor3=self.Theme.Surface; panel.BorderSizePixel=0; panel.ZIndex=641; panel.Parent=overlay
    local title=v4Label(panel,options.Title or "Panel",16,self.Theme.TextPrimary,true); title.Position=UDim2.fromOffset(18,16); title.Size=UDim2.new(1,-36,0,26); title.ZIndex=642
    local content=Instance.new("Frame"); content.BackgroundTransparency=1; content.Position=UDim2.fromOffset(16,54); content.Size=UDim2.new(1,-32,1,-70); content.ZIndex=642; content.Parent=panel
    local function close() tween(panel,0.18,{Position=UDim2.new(1,panel.Size.X.Offset,0,0)}); task.delay(0.19,function() if overlay then overlay:Destroy() end end) end
    self:_connect(overlay.MouseButton1Click,close); tween(panel,0.22,{Position=UDim2.new(1,0,0,0)})
    if type(options.Build)=="function" then safeCall(options.Build,content,close,self) end
    return {Overlay=overlay,Panel=panel,Content=content,Close=close}
end

function Window:Drawer(options)
    options=options or {}; options.Width=options.Width or 300
    return self:SidePanel(options)
end

-- Modal suite ---------------------------------------------------------------
function Window:Alert(options)
    options=type(options)=="table" and options or {Content=tostring(options)}
    return self:Dialog({Title=options.Title or "Alert",Content=options.Content or options.Text or "",Buttons={{Text=options.ButtonText or "OK",Style="accent",Callback=options.Callback}}})
end
function Window:Confirm(options)
    options=options or {}
    return self:Dialog({Title=options.Title or "Confirm",Content=options.Content or "Are you sure?",Buttons={{Text=options.CancelText or "Cancel",Style="neutral",Callback=options.OnCancel},{Text=options.ConfirmText or "Confirm",Style=options.Danger and "danger" or "accent",Callback=options.OnConfirm}}})
end
function Window:Prompt(options)
    options=options or {}
    return self:BottomSheet({Title=options.Title or "Input",Height=220,Build=function(parent,close)
        local box=Instance.new("TextBox"); box.ClearTextOnFocus=false; box.PlaceholderText=options.Placeholder or "Type here..."; box.Text=tostring(options.Default or ""); box.TextColor3=self.Theme.TextPrimary; box.PlaceholderColor3=self.Theme.TextSecondary; box.BackgroundColor3=self.Theme.Surface2; box.BorderSizePixel=0; box.Size=UDim2.new(1,0,0,44); box.TextSize=12; box.Font=Enum.Font.Gotham; box.Parent=parent; v4Round(box,10); v4Stroke(box,self.Theme.BorderDefault or self.Theme.Border,0.5,1); v4Padding(box,12,12,0,0)
        local ok=v4Button(parent,options.ConfirmText or "Continue",UDim2.fromOffset(110,36),self.Theme.Accent,self.Theme.AccentText); ok.AnchorPoint=Vector2.new(1,0); ok.Position=UDim2.new(1,0,0,58)
        self:_connect(ok.MouseButton1Click,function() local value=box.Text; close(); safeCall(options.Callback,value) end)
        task.defer(function() box:CaptureFocus() end)
    end})
end
function Window:Choice(options)
    options=options or {}
    return self:BottomSheet({Title=options.Title or "Choose",Height=math.min(480,100+(#(options.Options or {})*44)),Build=function(parent,close)
        local list=Instance.new("ScrollingFrame"); list.Size=UDim2.fromScale(1,1); list.BackgroundTransparency=1; list.BorderSizePixel=0; list.AutomaticCanvasSize=Enum.AutomaticSize.Y; list.CanvasSize=UDim2.new(); list.ScrollBarThickness=2; list.Parent=parent; v4List(list,6)
        for _,choice in ipairs(options.Options or {}) do local text=type(choice)=="table" and (choice.Name or choice.Text) or tostring(choice); local b=v4Button(list,text,UDim2.new(1,0,0,40),self.Theme.Surface2,self.Theme.TextPrimary); self:_connect(b.MouseButton1Click,function() close(); safeCall(options.Callback,type(choice)=="table" and (choice.Value or choice.Name) or choice) end) end
    end})
end
function Window:ProgressModal(options)
    options=options or {}
    local sheet=self:BottomSheet({Title=options.Title or "Working...",Height=190})
    local bar=Instance.new("Frame"); bar.BackgroundColor3=self.Theme.Surface3; bar.BorderSizePixel=0; bar.Size=UDim2.new(1,0,0,6); bar.Position=UDim2.fromOffset(0,28); bar.Parent=sheet.Content; v4Round(bar,999)
    local fill=Instance.new("Frame"); fill.BackgroundColor3=self.Theme.Accent; fill.BorderSizePixel=0; fill.Size=UDim2.fromScale(0,1); fill.Parent=bar; v4Round(fill,999)
    local label=v4Label(sheet.Content,"0%",12,self.Theme.TextPrimary,true); label.Position=UDim2.fromOffset(0,44); label.Size=UDim2.new(1,0,0,22)
    local object={}
    function object:Set(value,text) value=v4Clamp(tonumber(value) or 0,0,1); tween(fill,0.15,{Size=UDim2.fromScale(value,1)}); label.Text=text or math.floor(value*100+0.5).."%" end
    function object:Close() sheet.Close() end
    return object
end

-- Notification center -------------------------------------------------------
function Window:OpenNotificationCenter()
    return self:SidePanel({Title="Notifications",Width=340,Build=function(parent)
        local list=Instance.new("ScrollingFrame"); list.Size=UDim2.fromScale(1,1); list.BackgroundTransparency=1; list.BorderSizePixel=0; list.AutomaticCanvasSize=Enum.AutomaticSize.Y; list.CanvasSize=UDim2.new(); list.ScrollBarThickness=2; list.Parent=parent; local layout=v4List(list,8)
        local notes=self:GetNotifications()
        if #notes==0 then local empty=v4Label(list,"No notifications yet.",12,self.Theme.TextSecondary,false); empty.Size=UDim2.new(1,0,0,42) end
        for i,n in ipairs(notes) do
            local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,64); row.BackgroundColor3=self.Theme.Surface2; row.BorderSizePixel=0; row.LayoutOrder=i; row.Parent=list; v4Round(row,11); v4Stroke(row,self.Theme.BorderSubtle or self.Theme.Border,0.75,1)
            local title=v4Label(row,n.Title,11,self.Theme.TextPrimary,true); title.Position=UDim2.fromOffset(12,7); title.Size=UDim2.new(1,-58,0,18)
            local content=v4Label(row,n.Content,9,self.Theme.TextSecondary,false); content.Position=UDim2.fromOffset(12,27); content.Size=UDim2.new(1,-24,0,28)
            if (n.Count or 1)>1 then local count=v4Label(row,"×"..n.Count,9,self.Theme.Accent,true); count.AnchorPoint=Vector2.new(1,0); count.Position=UDim2.new(1,-10,0,7); count.Size=UDim2.fromOffset(38,18); count.TextXAlignment=Enum.TextXAlignment.Right end
        end
    end})
end

-- Shortcuts -----------------------------------------------------------------
function Window:RegisterShortcut(data)
    v4InitWindow(self)
    data=v4Copy(data or {})
    if type(data.Key)=="string" then data.Key=Enum.KeyCode[data.Key] end
    if typeof(data.Key)~="EnumItem" then return nil,"Invalid key" end
    table.insert(self._v4Shortcuts,data)
    return data
end

function Window:GetShortcuts() v4InitWindow(self); return self._v4Shortcuts end

-- History / undo / redo -----------------------------------------------------
local _V4SetFlag=Window.SetFlag
function Window:SetFlag(flag,value,...)
    v4InitWindow(self)
    local old=self.Flags and self.Flags[flag]
    if not self._v4HistoryApplying and flag and old~=value then
        table.insert(self._v4History,{Flag=flag,Before=old,After=value,Time=os.time()})
        while #self._v4History>100 do table.remove(self._v4History,1) end
        table.clear(self._v4Redo)
    end
    return _V4SetFlag(self,flag,value,...)
end

function Window:Undo()
    v4InitWindow(self)
    local change=table.remove(self._v4History)
    if not change then self:ShowSnackbar("Nothing to undo"); return false end
    self._v4HistoryApplying=true
    local current=self.Flags[change.Flag]
    _V4SetFlag(self,change.Flag,change.Before)
    self._v4HistoryApplying=false
    table.insert(self._v4Redo,{Flag=change.Flag,Before=change.Before,After=current,Time=os.time()})
    self:ShowSnackbar("Undone: "..change.Flag)
    return true
end

function Window:Redo()
    v4InitWindow(self)
    local change=table.remove(self._v4Redo)
    if not change then self:ShowSnackbar("Nothing to redo"); return false end
    self._v4HistoryApplying=true
    _V4SetFlag(self,change.Flag,change.After)
    self._v4HistoryApplying=false
    table.insert(self._v4History,change)
    self:ShowSnackbar("Redone: "..change.Flag)
    return true
end

function Window:DiffConfig(config)
    if type(config)=="string" then local ok,result=pcall(HttpService.JSONDecode,HttpService,config); if ok then config=result else return {} end end
    local changes={}
    for flag,new in pairs(config or {}) do local old=self.Flags[flag]; if tostring(old)~=tostring(new) then table.insert(changes,{Flag=flag,Before=old,After=new}) end end
    return changes
end

function Window:RegisterPreset(name,config)
    v4InitWindow(self); self._v4Presets[tostring(name)]=v4Copy(config or {}); return self._v4Presets[tostring(name)]
end
function Window:ApplyPreset(name)
    v4InitWindow(self); local preset=self._v4Presets[tostring(name)]; if not preset then return false,"Unknown preset" end
    for flag,value in pairs(preset) do self:SetFlag(flag,value) end
    self:ShowSnackbar("Preset applied: "..tostring(name)); return true
end
function Window:GetPresets() v4InitWindow(self); return self._v4Presets end

function Window:EnableAutosave(interval,path)
    v4InitWindow(self)
    self._v4Autosave={Enabled=true,Interval=math.max(2,tonumber(interval) or 10),Path=path,State="Saved"}
    local token={}; self._v4Autosave.Token=token
    task.spawn(function()
        local last=""
        while self._v4Autosave and self._v4Autosave.Enabled and self._v4Autosave.Token==token and not self.Destroyed do
            task.wait(self._v4Autosave.Interval)
            local current=self.ExportConfig and self:ExportConfig() or ""
            if current~=last then
                self._v4Autosave.State="Saving"
                local ok= false
                if self.SaveConfigFile then ok=self:SaveConfigFile(path) end
                self._v4Autosave.State=ok and "Saved" or "Unavailable"
                last=current
            end
        end
    end)
    return self._v4Autosave
end
function Window:DisableAutosave() if self._v4Autosave then self._v4Autosave.Enabled=false end end
function Window:GetAutosaveState() return self._v4Autosave and self._v4Autosave.State or "Off" end

-- Favorites / recent --------------------------------------------------------
function Window:PinAction(data)
    v4InitWindow(self); data=v4Copy(data or {}); local key=tostring(data.Id or data.Name or #self._v4Pinned+1); self._v4Pinned[key]=data; return data
end
function Window:UnpinAction(id) v4InitWindow(self); self._v4Pinned[tostring(id)]=nil end
function Window:GetPinnedActions() v4InitWindow(self); local out={}; for _,v in pairs(self._v4Pinned) do table.insert(out,v) end return out end
function Window:RecordRecent(data)
    v4InitWindow(self); data=v4Copy(data or {}); data.Time=os.time(); table.insert(self._v4Recent,1,data); while #self._v4Recent>20 do table.remove(self._v4Recent) end
end
function Window:GetRecentActions(limit) v4InitWindow(self); local out={}; for i=1,math.min(#self._v4Recent,limit or 8) do out[i]=self._v4Recent[i] end return out end

-- Accessibility / adaptive preferences -------------------------------------
function Window:SetUIScale(value)
    v4InitWindow(self); value=v4Clamp(tonumber(value) or 1,0.72,1.25); self._v4Preferences.UIScale=value
    if self.Scale then self.Scale.Scale=(self.ResponsiveScale or 1)*value end
    return value
end
function Window:SetMotionIntensity(mode)
    v4InitWindow(self); mode=tostring(mode or "Normal"); self._v4Preferences.MotionIntensity=mode
    self.ReduceMotion=string.lower(mode)=="reduced"
    self.Options.Effects=string.lower(mode)~="reduced"
end
function Window:SetReduceTransparency(state)
    v4InitWindow(self); self._v4Preferences.ReduceTransparency=state==true
    for _,obj in ipairs(self.ScreenGui:GetDescendants()) do
        if obj:IsA("Frame") and obj.BackgroundTransparency>0 and obj.BackgroundTransparency<1 and obj:GetAttribute("AstraV38Role") then obj.BackgroundTransparency=state and 0 or obj.BackgroundTransparency end
    end
end
function Window:SetHighContrast(state)
    v4InitWindow(self); self._v4Preferences.HighContrast=state==true
    if state then
        self:SetTheme({TextPrimary=Color3.new(1,1,1),TextSecondary=Color3.fromRGB(210,214,224),BorderSubtle=Color3.fromRGB(90,96,112),BorderDefault=Color3.fromRGB(115,122,142)})
    else
        self:SetThemePreset(self.Options.ThemePreset or "Midnight")
    end
end
function Window:SetColorBlindMode(mode) v4InitWindow(self); self._v4Preferences.ColorBlindMode=tostring(mode or "None") end
function Window:GetAccessibilityPreferences() v4InitWindow(self); return v4Copy(self._v4Preferences) end

function Window:ApplyPreferredTextSize()
    v4InitWindow(self)
    if not self._v4Preferences.RespectPreferredTextSize or not GuiService then return 1 end
    local scale=1
    pcall(function()
        local name=tostring(GuiService.PreferredTextSize)
        if string.find(name,"Large") then scale=1.12 end
        if string.find(name,"ExtraLarge") then scale=1.22 end
        if string.find(name,"Small") then scale=0.94 end
    end)
    for _,obj in ipairs(self.ScreenGui:GetDescendants()) do if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then if not obj:GetAttribute("AstraV4BaseTextSize") then obj:SetAttribute("AstraV4BaseTextSize",obj.TextSize) end; obj.TextSize=math.floor((obj:GetAttribute("AstraV4BaseTextSize") or obj.TextSize)*scale+0.5) end end
    return scale
end

function Window:GetInputHint(action)
    local input=v4GetPreferredInput()
    if input=="Touch" then return "Tap" end
    if input=="Gamepad" then return action and ("Press "..tostring(action.Gamepad or "A")) or "Press A" end
    return action and tostring(action.Keyboard or "Enter") or "Enter"
end

-- Requirements / access -----------------------------------------------------
function Window:CheckRequirement(requirement)
    if type(requirement)=="function" then local ok,result=pcall(requirement,self); return ok and result==true end
    local req=string.lower(tostring(requirement or ""))
    if req=="premium" or req=="premiumkey" then local k=self.GetKeyInfo and self:GetKeyInfo() or {}; return not k.Expired and string.lower(tostring(k.Tier or k.Plan or ""))~="free" and string.lower(tostring(k.Status or ""))~="locked" end
    local caps=self.Library and self.Library.GetCapabilities and self.Library:GetCapabilities() or (AstraUI.GetCapabilities and self.Library:GetCapabilities())
    if type(caps)=="table" then for k,v in pairs(caps) do if string.lower(k)==req then return v==true end end end
    return false
end

-- Breadcrumbs ---------------------------------------------------------------
function Window:SetBreadcrumbs(parts)
    parts=parts or {}
    if self.PageDesc then self.PageDesc.Text=table.concat(parts,"  /  ") end
end

-- Tab groups ----------------------------------------------------------------
function Window:CreateTabGroup(name)
    local group={Window=self,Name=tostring(name or "Group"),Order=(#self.Tabs+1)*100}
    local label=Instance.new("TextLabel")
    label.BackgroundTransparency=1; label.Text=string.upper(group.Name); label.TextColor3=self.Theme.TextSecondary; label.TextTransparency=0.2; label.TextSize=9; label.Font=Enum.Font.GothamBold; label.TextXAlignment=Enum.TextXAlignment.Left; label.Size=UDim2.new(1,-12,0,22); label.LayoutOrder=group.Order; label.Parent=self.TabList; v4Padding(label,8,0,0,0)
    group.Label=label; group.Count=0
    function group:CreateTab(options)
        self.Count+=1
        local tab=self.Window:CreateTab(options)
        if tab.Button then tab.Button.LayoutOrder=self.Order+self.Count end
        return tab
    end
    return group
end

-- Announcement / What's New -------------------------------------------------
function Window:SetAnnouncement(options)
    options=options or {}
    if self._v4Announcement and self._v4Announcement.Parent then self._v4Announcement:Destroy() end
    local banner=Instance.new("Frame"); banner.BackgroundColor3=self.Theme.Surface2; banner.BorderSizePixel=0; banner.Position=UDim2.fromOffset(16,64); banner.Size=UDim2.new(1,-32,0,58); banner.ZIndex=20; banner.Parent=self.Main; v4Round(banner,12); v4Stroke(banner,v4Tone(self,options.Type or "accent"),0.55,1)
    local strip=Instance.new("Frame"); strip.BackgroundColor3=v4Tone(self,options.Type or "accent"); strip.BorderSizePixel=0; strip.Size=UDim2.fromOffset(3,34); strip.Position=UDim2.fromOffset(9,12); strip.Parent=banner; v4Round(strip,999)
    local title=v4Label(banner,options.Title or "Announcement",11,self.Theme.TextPrimary,true); title.Position=UDim2.fromOffset(22,8); title.Size=UDim2.new(1,-50,0,18)
    local body=v4Label(banner,options.Content or "",9,self.Theme.TextSecondary,false); body.Position=UDim2.fromOffset(22,27); body.Size=UDim2.new(1,-50,0,22)
    if options.Dismissible~=false then local close=v4Button(banner,"x",UDim2.fromOffset(24,24),self.Theme.Surface3,self.Theme.TextSecondary); close.AnchorPoint=Vector2.new(1,0.5); close.Position=UDim2.new(1,-10,0.5,0); self:_connect(close.MouseButton1Click,function() banner:Destroy(); if self.Pages then self.Pages.Position=UDim2.fromOffset(0,66); self.Pages.Size=UDim2.new(1,0,1,-66) end end) end
    self._v4Announcement=banner
    if self.Pages then self.Pages.Position=UDim2.fromOffset(0,126); self.Pages.Size=UDim2.new(1,0,1,-126) end
    return banner
end

function Window:ShowWhatsNew(options)
    options=options or {}
    local changes=options.Changes or {}
    return self:BottomSheet({Title=options.Title or ("What's New · "..tostring(options.Version or AstraUI.Version)),Height=math.min(520,150+#changes*42),Build=function(parent,close)
        local list=Instance.new("ScrollingFrame"); list.Size=UDim2.new(1,0,1,-50); list.BackgroundTransparency=1; list.BorderSizePixel=0; list.AutomaticCanvasSize=Enum.AutomaticSize.Y; list.CanvasSize=UDim2.new(); list.ScrollBarThickness=2; list.Parent=parent; v4List(list,6)
        for i,item in ipairs(changes) do local row=Instance.new("Frame"); row.Size=UDim2.new(1,0,0,38); row.BackgroundColor3=self.Theme.Surface2; row.BorderSizePixel=0; row.LayoutOrder=i; row.Parent=list; v4Round(row,9); local tag=v4Label(row,string.upper(tostring(item.Type or "NEW")),9,v4Tone(self,item.Tone or (item.Type=="Fixed" and "success" or "accent")),true); tag.Position=UDim2.fromOffset(10,0); tag.Size=UDim2.fromOffset(72,38); local txt=v4Label(row,item.Text or item.Description or "",10,self.Theme.TextPrimary,false); txt.Position=UDim2.fromOffset(82,0); txt.Size=UDim2.new(1,-92,1,0) end
        local got=v4Button(parent,options.ButtonText or "Got it",UDim2.fromOffset(96,34),self.Theme.Accent,self.Theme.AccentText); got.AnchorPoint=Vector2.new(1,1); got.Position=UDim2.new(1,0,1,0); self:_connect(got.MouseButton1Click,close)
    end})
end

-- Generic component enhancers ----------------------------------------------
local function v4EnhanceControl(window,object,data)
    if not object then return object end
    data=data or {}
    object._v4Data=data
    if object.Instance then
        window:AttachContextMenu(object.Instance,{
            {Name="Reset to default",Callback=function() if object.GetDefault and object.Set then object:Set(object:GetDefault(),true) end end},
            {Name="Pin to Quick Access",Callback=function() object:Pin() end},
        })
    end
    function object:Pin()
        window:PinAction({Id=data.Flag or data.Name,Name=data.Name or data.Title or "Control",Description=data.Description,Callback=function() if self.Fire then self:Fire() end end})
    end
    function object:SetLocked(state,reason)
        state=state==true; self._v4Locked=state
        if self.SetDisabled then self:SetDisabled(state) end
        if self.Instance then
            local old=self.Instance:FindFirstChild("AstraV4LockOverlay")
            if old then old:Destroy() end
            if state then
                local overlay=Instance.new("Frame"); overlay.Name="AstraV4LockOverlay"; overlay.BackgroundColor3=window.Theme.Surface; overlay.BackgroundTransparency=0.15; overlay.BorderSizePixel=0; overlay.Size=UDim2.fromScale(1,1); overlay.ZIndex=50; overlay.Parent=self.Instance; v4Round(overlay,11)
                local label=v4Label(overlay,"LOCKED · "..tostring(reason or "Access required"),9,window.Theme.TextSecondary,true); label.Size=UDim2.fromScale(1,1); label.TextXAlignment=Enum.TextXAlignment.Center; label.ZIndex=51
            end
        end
    end
    function object:SetContextMenu(items) if self.Instance then window:AttachContextMenu(self.Instance,items) end end
    return object
end

local function v4WrapControl(methodName)
    local old=Tab[methodName]
    if type(old)~="function" then return end
    Tab[methodName]=function(self,parent,data)
        data=data or {}
        local raw=v4Copy(data)
        local cb=raw.Callback
        if cb then raw.Callback=function(...)
            self.Window:RecordRecent({Name=raw.Name or raw.Title or methodName,Description=raw.Description})
            return cb(...)
        end end
        local obj=old(self,parent,raw)
        if raw.Favorite then self.Window:PinAction({Id=raw.Flag or raw.Name,Name=raw.Name,Description=raw.Description,Callback=function() if obj and obj.Fire then obj:Fire() end end}) end
        return v4EnhanceControl(self.Window,obj,raw)
    end
end
for _,name in ipairs({"_addButton","_addToggle","_addSlider","_addInput","_addDropdown","_addKeybind","_addColorPicker","_addTextArea"}) do v4WrapControl(name) end

-- Rich component builders ---------------------------------------------------
function Tab:_addQuickActions(parent,data)
    data=data or {}; local actions=data.Actions or {}
    local row=self:_row(parent,78); self:_titleBlock(row,data,12)
    local holder=Instance.new("Frame"); holder.BackgroundTransparency=1; holder.Position=UDim2.fromOffset(12,42); holder.Size=UDim2.new(1,-24,0,28); holder.Parent=row
    local layout=Instance.new("UIListLayout"); layout.FillDirection=Enum.FillDirection.Horizontal; layout.HorizontalAlignment=Enum.HorizontalAlignment.Right; layout.VerticalAlignment=Enum.VerticalAlignment.Center; layout.Padding=UDim.new(0,6); layout.Parent=holder
    local object={Instance=row,Buttons={}}
    for _,action in ipairs(actions) do
        local b=v4Button(holder,action.Text or action.Name or "Action",UDim2.fromOffset(math.clamp(46+#tostring(action.Text or action.Name or "")*5,72,126),28),action.Primary and self.Window.Theme.Accent or self.Window.Theme.Surface3,action.Primary and self.Window.Theme.AccentText or self.Window.Theme.TextPrimary)
        table.insert(object.Buttons,b); self.Window:_connect(b.MouseButton1Click,function() self.Window:RecordRecent({Name=action.Text or action.Name}); safeCall(action.Callback,action) end)
    end
    return v4EnhanceControl(self.Window,object,data)
end

function Tab:_addSegmentedControl(parent,data)
    data=data or {}; local options=data.Options or {}; local value=data.Default or options[1]; local flag=data.Flag; if flag and self.Window.Flags[flag]~=nil then value=self.Window.Flags[flag] end
    local row=self:_row(parent,76); self:_titleBlock(row,data,12)
    local holder=Instance.new("Frame"); holder.BackgroundColor3=self.Window.Theme.Surface3; holder.BorderSizePixel=0; holder.Position=UDim2.fromOffset(12,41); holder.Size=UDim2.new(1,-24,0,28); holder.Parent=row; v4Round(holder,9); v4Padding(holder,3,3,3,3)
    local layout=Instance.new("UIListLayout"); layout.FillDirection=Enum.FillDirection.Horizontal; layout.HorizontalAlignment=Enum.HorizontalAlignment.Left; layout.Padding=UDim.new(0,3); layout.Parent=holder
    local object={Instance=row,Buttons={}}
    local function paint()
        for opt,b in pairs(object.Buttons) do local selected=tostring(opt)==tostring(value); b.BackgroundColor3=selected and self.Window.Theme.Accent or self.Window.Theme.Surface3; b.TextColor3=selected and self.Window.Theme.AccentText or self.Window.Theme.TextSecondary end
    end
    local function set(v,fire) value=v; if flag then self.Window.Flags[flag]=v end; paint(); if fire~=false then safeCall(data.Callback,v) end end
    for _,opt in ipairs(options) do local b=v4Button(holder,tostring(opt),UDim2.new(1/math.max(1,#options),-3,1,0),self.Window.Theme.Surface3,self.Window.Theme.TextSecondary); object.Buttons[opt]=b; self.Window:_connect(b.MouseButton1Click,function() set(opt,true) end) end
    function object:Set(v,fire) set(v,fire) end; function object:Get() return value end; function object:GetDefault() return data.Default or options[1] end
    if flag then self.Window.Flags[flag]=value; self.Window.FlagObjects[flag]=object end; paint(); return v4EnhanceControl(self.Window,object,data)
end

function Tab:_addCheckbox(parent,data)
    data=data or {}; local value=data.Default==true; local flag=data.Flag; if flag and self.Window.Flags[flag]~=nil then value=self.Window.Flags[flag]==true end
    local row=self:_row(parent,52); self:_titleBlock(row,data,54)
    local box=v4Button(row,"",UDim2.fromOffset(24,24),self.Window.Theme.Surface3,self.Window.Theme.TextPrimary); box.AnchorPoint=Vector2.new(1,0.5); box.Position=UDim2.new(1,-12,0.5,0); v4Stroke(box,self.Window.Theme.BorderDefault or self.Window.Theme.Border,0.45,1)
    local a=Instance.new("Frame"); a.BorderSizePixel=0; a.Size=UDim2.fromOffset(8,2); a.Position=UDim2.fromOffset(4,12); a.Rotation=40; a.Parent=box
    local b=Instance.new("Frame"); b.BorderSizePixel=0; b.Size=UDim2.fromOffset(11,2); b.Position=UDim2.fromOffset(9,10); b.Rotation=-48; b.Parent=box
    local object={Instance=row}
    local function paint() box.BackgroundColor3=value and self.Window.Theme.Accent or self.Window.Theme.Surface3; a.BackgroundColor3=self.Window.Theme.AccentText; b.BackgroundColor3=self.Window.Theme.AccentText; a.Visible=value; b.Visible=value end
    local function set(v,fire) value=v==true; if flag then self.Window.Flags[flag]=value end; paint(); if fire~=false then safeCall(data.Callback,value) end end
    self.Window:_connect(box.MouseButton1Click,function() set(not value,true) end); self.Window:_connect(row.InputBegan,function(io) if io.UserInputType==Enum.UserInputType.Touch then set(not value,true) end end)
    function object:Set(v,fire) set(v,fire) end; function object:Get() return value end; function object:GetDefault() return data.Default==true end
    if flag then self.Window.Flags[flag]=value; self.Window.FlagObjects[flag]=object end; paint(); return v4EnhanceControl(self.Window,object,data)
end

function Tab:_addRadioGroup(parent,data)
    data=data or {}; local options=data.Options or {}; local value=data.Default or options[1]; local flag=data.Flag; if flag and self.Window.Flags[flag]~=nil then value=self.Window.Flags[flag] end
    local height=44+#options*34; local row=self:_row(parent,height); self:_titleBlock(row,data,12)
    local holder=Instance.new("Frame"); holder.BackgroundTransparency=1; holder.Position=UDim2.fromOffset(12,40); holder.Size=UDim2.new(1,-24,0,#options*34); holder.Parent=row; v4List(holder,2)
    local object={Instance=row,Options={}}
    local function paint() for opt,entry in pairs(object.Options) do local selected=tostring(opt)==tostring(value); entry.Dot.Visible=selected; entry.Button.TextColor3=selected and self.Window.Theme.TextPrimary or self.Window.Theme.TextSecondary end end
    local function set(v,fire) value=v; if flag then self.Window.Flags[flag]=v end; paint(); if fire~=false then safeCall(data.Callback,v) end end
    for _,opt in ipairs(options) do
        local item=v4Button(holder,tostring(opt),UDim2.new(1,0,0,32),self.Window.Theme.Surface3,self.Window.Theme.TextSecondary); item.TextXAlignment=Enum.TextXAlignment.Left; v4Padding(item,38,8,0,0)
        local ring=Instance.new("Frame"); ring.BackgroundTransparency=1; ring.BorderSizePixel=0; ring.Position=UDim2.fromOffset(10,8); ring.Size=UDim2.fromOffset(16,16); ring.Parent=item; v4Round(ring,999); v4Stroke(ring,self.Window.Theme.BorderDefault or self.Window.Theme.Border,0.25,1.4)
        local dot=Instance.new("Frame"); dot.AnchorPoint=Vector2.new(0.5,0.5); dot.Position=UDim2.fromScale(0.5,0.5); dot.Size=UDim2.fromOffset(8,8); dot.BackgroundColor3=self.Window.Theme.Accent; dot.BorderSizePixel=0; dot.Parent=ring; v4Round(dot,999)
        object.Options[opt]={Button=item,Dot=dot}; self.Window:_connect(item.MouseButton1Click,function() set(opt,true) end)
    end
    function object:Set(v,fire) set(v,fire) end; function object:Get() return value end; function object:GetDefault() return data.Default or options[1] end
    if flag then self.Window.Flags[flag]=value; self.Window.FlagObjects[flag]=object end; paint(); return v4EnhanceControl(self.Window,object,data)
end

function Tab:_addStepper(parent,data)
    data=data or {}; local min=tonumber(data.Min) or 0; local max=tonumber(data.Max) or 100; local step=tonumber(data.Step or data.Increment) or 1; local value=v4Clamp(tonumber(data.Default) or min,min,max); local flag=data.Flag; if flag and self.Window.Flags[flag]~=nil then value=v4Clamp(tonumber(self.Window.Flags[flag]) or value,min,max) end
    local row=self:_row(parent,54); self:_titleBlock(row,data,150)
    local holder=Instance.new("Frame"); holder.BackgroundTransparency=1; holder.AnchorPoint=Vector2.new(1,0.5); holder.Position=UDim2.new(1,-12,0.5,0); holder.Size=UDim2.fromOffset(142,32); holder.Parent=row
    local minus=v4Button(holder,"-",UDim2.fromOffset(32,32),self.Window.Theme.Surface3,self.Window.Theme.TextPrimary); minus.Position=UDim2.fromOffset(0,0)
    local valueLabel=v4Label(holder,"",12,self.Window.Theme.TextPrimary,true); valueLabel.Position=UDim2.fromOffset(38,0); valueLabel.Size=UDim2.fromOffset(66,32); valueLabel.TextXAlignment=Enum.TextXAlignment.Center
    local plus=v4Button(holder,"+",UDim2.fromOffset(32,32),self.Window.Theme.Surface3,self.Window.Theme.TextPrimary); plus.Position=UDim2.fromOffset(110,0)
    local object={Instance=row}
    local function set(v,fire) value=v4Clamp(math.floor((tonumber(v) or value)/step+0.5)*step,min,max); valueLabel.Text=tostring(value)..tostring(data.Suffix or ""); if flag then self.Window.Flags[flag]=value end; if fire~=false then safeCall(data.Callback,value) end end
    self.Window:_connect(minus.MouseButton1Click,function() set(value-step,true) end); self.Window:_connect(plus.MouseButton1Click,function() set(value+step,true) end)
    function object:Set(v,fire) set(v,fire) end; function object:Get() return value end; function object:GetDefault() return tonumber(data.Default) or min end
    if flag then self.Window.Flags[flag]=value; self.Window.FlagObjects[flag]=object end; set(value,false); return v4EnhanceControl(self.Window,object,data)
end

function Tab:_addNumberInput(parent,data)
    local object=self:_addStepper(parent,data)
    return object
end

function Tab:_addRangeSlider(parent,data)
    data=data or {}; local min=tonumber(data.Min) or 0; local max=tonumber(data.Max) or 100; local low=v4Clamp(tonumber(data.DefaultMin or data.Low) or min,min,max); local high=v4Clamp(tonumber(data.DefaultMax or data.High) or max,min,max); if low>high then low,high=high,low end
    local row=self:_row(parent,82); self:_titleBlock(row,data,88)
    local valueLabel=v4Label(row,"",10,self.Window.Theme.Accent,true); valueLabel.AnchorPoint=Vector2.new(1,0); valueLabel.Position=UDim2.new(1,-12,0,8); valueLabel.Size=UDim2.fromOffset(86,16); valueLabel.TextXAlignment=Enum.TextXAlignment.Right
    local bar=Instance.new("Frame"); bar.BackgroundColor3=self.Window.Theme.Surface3; bar.BorderSizePixel=0; bar.Position=UDim2.fromOffset(14,58); bar.Size=UDim2.new(1,-28,0,5); bar.Parent=row; v4Round(bar,999)
    local fill=Instance.new("Frame"); fill.BackgroundColor3=self.Window.Theme.Accent; fill.BorderSizePixel=0; fill.Parent=bar; v4Round(fill,999)
    local k1=Instance.new("Frame"); k1.AnchorPoint=Vector2.new(0.5,0.5); k1.Size=UDim2.fromOffset(14,14); k1.BackgroundColor3=Color3.new(1,1,1); k1.BorderSizePixel=0; k1.Parent=bar; v4Round(k1,999); v4Stroke(k1,self.Window.Theme.Accent,0,2)
    local k2=k1:Clone(); k2.Parent=bar
    local drag=nil; local object={Instance=row}
    local function paint() local a=(low-min)/(max-min); local b=(high-min)/(max-min); k1.Position=UDim2.fromScale(a,0.5); k2.Position=UDim2.fromScale(b,0.5); fill.Position=UDim2.fromScale(a,0); fill.Size=UDim2.fromScale(b-a,1); valueLabel.Text=tostring(low).." – "..tostring(high)..tostring(data.Suffix or "") end
    local function update(pos,which,fire) local alpha=v4Clamp((pos.X-bar.AbsolutePosition.X)/math.max(1,bar.AbsoluteSize.X),0,1); local v=min+(max-min)*alpha; local inc=tonumber(data.Increment) or 1; v=math.floor(v/inc+0.5)*inc; if which==1 then low=math.min(v,high) else high=math.max(v,low) end; paint(); if fire~=false then safeCall(data.Callback,low,high) end end
    self.Window:_connect(bar.InputBegan,function(io) if io.UserInputType==Enum.UserInputType.Touch or io.UserInputType==Enum.UserInputType.MouseButton1 then local x=io.Position.X; local d1=math.abs(x-k1.AbsolutePosition.X); local d2=math.abs(x-k2.AbsolutePosition.X); drag=d1<=d2 and 1 or 2; update(io.Position,drag,true) end end)
    self.Window:_connect(UserInputService.InputChanged,function(io) if drag and (io.UserInputType==Enum.UserInputType.Touch or io.UserInputType==Enum.UserInputType.MouseMovement) then update(io.Position,drag,true) end end)
    self.Window:_connect(UserInputService.InputEnded,function(io) if io.UserInputType==Enum.UserInputType.Touch or io.UserInputType==Enum.UserInputType.MouseButton1 then drag=nil end end)
    function object:Set(a,b,fire) low=v4Clamp(tonumber(a) or low,min,max); high=v4Clamp(tonumber(b) or high,min,max); if low>high then low,high=high,low end; paint(); if fire~=false then safeCall(data.Callback,low,high) end end; function object:Get() return low,high end; paint(); return v4EnhanceControl(self.Window,object,data)
end

function Tab:_addComboBox(parent,data)
    data=v4Copy(data or {}); data.Searchable=true; data.SearchThreshold=0
    return self:_addDropdown(parent,data)
end

function Tab:_addTagInput(parent,data)
    data=data or {}; local tags={}; for _,v in ipairs(data.Default or {}) do tags[#tags+1]=tostring(v) end
    local row=self:_row(parent,104); self:_titleBlock(row,data,12)
    local holder=Instance.new("Frame"); holder.BackgroundTransparency=1; holder.Position=UDim2.fromOffset(12,40); holder.Size=UDim2.new(1,-24,0,28); holder.Parent=row
    local list=Instance.new("UIListLayout"); list.FillDirection=Enum.FillDirection.Horizontal; list.Padding=UDim.new(0,5); list.Parent=holder
    local input=Instance.new("TextBox"); input.ClearTextOnFocus=false; input.PlaceholderText=data.Placeholder or "Add tag and press Enter"; input.Text=""; input.TextColor3=self.Window.Theme.TextPrimary; input.PlaceholderColor3=self.Window.Theme.TextSecondary; input.BackgroundColor3=self.Window.Theme.Surface3; input.BorderSizePixel=0; input.Position=UDim2.fromOffset(12,72); input.Size=UDim2.new(1,-24,0,26); input.TextSize=10; input.Font=Enum.Font.Gotham; input.Parent=row; v4Round(input,8); v4Padding(input,10,10,0,0)
    local object={Instance=row}
    local function render() for _,c in ipairs(holder:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end; for i,tag in ipairs(tags) do local chip=v4Button(holder,tag.."  x",UDim2.fromOffset(math.clamp(30+#tag*6,60,110),26),self.Window.Theme.AccentSoft or self.Window.Theme.Surface3,self.Window.Theme.TextPrimary); self.Window:_connect(chip.MouseButton1Click,function() table.remove(tags,i); render(); safeCall(data.Callback,tags) end) end end
    self.Window:_connect(input.FocusLost,function(enter) if enter and input.Text~="" then tags[#tags+1]=input.Text; input.Text=""; render(); safeCall(data.Callback,tags) end end)
    function object:Get() return tags end; function object:Set(new,fire) tags={}; for _,v in ipairs(new or {}) do tags[#tags+1]=tostring(v) end; render(); if fire~=false then safeCall(data.Callback,tags) end end; render(); return v4EnhanceControl(self.Window,object,data)
end

function Tab:_addBadge(parent,data)
    data=data or {}; local row=self:_row(parent,52); self:_titleBlock(row,data,100)
    local badge=v4Label(row,data.Text or data.Value or data.Badge or "NEW",9,v4Tone(self.Window,data.Tone),true); badge.AnchorPoint=Vector2.new(1,0.5); badge.Position=UDim2.new(1,-12,0.5,0); badge.Size=UDim2.fromOffset(88,26); badge.TextXAlignment=Enum.TextXAlignment.Center; badge.BackgroundColor3=v4Mix(v4Tone(self.Window,data.Tone),self.Window.Theme.Surface2,0.75); badge.BackgroundTransparency=0; v4Round(badge,999); v4Stroke(badge,v4Tone(self.Window,data.Tone),0.45,1)
    local object={Instance=row}; function object:Set(text,tone) badge.Text=tostring(text); badge.TextColor3=v4Tone(self.Window,tone or data.Tone) end; return object
end

function Tab:_addProgressCard(parent,data)
    data=data or {}; local min=tonumber(data.Min) or 0; local max=tonumber(data.Max) or 100; local value=tonumber(data.Default or data.Value) or min
    local row=self:_row(parent,92); self:_titleBlock(row,data,90)
    local val=v4Label(row,"",10,self.Window.Theme.Accent,true); val.AnchorPoint=Vector2.new(1,0); val.Position=UDim2.new(1,-12,0,8); val.Size=UDim2.fromOffset(86,18); val.TextXAlignment=Enum.TextXAlignment.Right
    local bar=Instance.new("Frame"); bar.BackgroundColor3=self.Window.Theme.Surface3; bar.BorderSizePixel=0; bar.Position=UDim2.fromOffset(12,58); bar.Size=UDim2.new(1,-24,0,7); bar.Parent=row; v4Round(bar,999)
    local fill=Instance.new("Frame"); fill.BackgroundColor3=v4Tone(self.Window,data.Tone); fill.BorderSizePixel=0; fill.Parent=bar; v4Round(fill,999)
    local sub=v4Label(row,data.Subtext or data.Footer or "",9,self.Window.Theme.TextSecondary,false); sub.Position=UDim2.fromOffset(12,68); sub.Size=UDim2.new(1,-24,0,16)
    local object={Instance=row}
    local function set(v,text) value=v4Clamp(tonumber(v) or value,min,max); local alpha=(value-min)/(max-min); tween(fill,0.16,{Size=UDim2.fromScale(alpha,1)}); val.Text=text or (tostring(value)..tostring(data.Suffix or "%")) end
    function object:Set(v,text) set(v,text) end; function object:Get() return value end; set(value); return object
end

function Tab:_addCircularProgress(parent,data)
    data=data or {}; local value=v4Clamp(tonumber(data.Default or data.Value) or 0,0,100)
    local row=self:_row(parent,88); self:_titleBlock(row,data,92)
    local ring=Instance.new("Frame"); ring.BackgroundTransparency=1; ring.AnchorPoint=Vector2.new(1,0.5); ring.Position=UDim2.new(1,-14,0.5,0); ring.Size=UDim2.fromOffset(60,60); ring.Parent=row
    local segments={}
    for i=1,16 do local seg=Instance.new("Frame"); seg.AnchorPoint=Vector2.new(0.5,1); seg.Position=UDim2.fromScale(0.5,0.5); seg.Size=UDim2.fromOffset(3,11); seg.Rotation=(i-1)*22.5; seg.BackgroundColor3=self.Window.Theme.Surface3; seg.BorderSizePixel=0; seg.Parent=ring; v4Round(seg,999); segments[i]=seg end
    local label=v4Label(ring,"",11,self.Window.Theme.TextPrimary,true); label.Size=UDim2.fromScale(1,1); label.TextXAlignment=Enum.TextXAlignment.Center
    local object={Instance=row}; local function set(v) value=v4Clamp(tonumber(v) or value,0,100); label.Text=math.floor(value+0.5).."%"; local active=math.floor((value/100)*#segments+0.5); for i,s in ipairs(segments) do s.BackgroundColor3=i<=active and v4Tone(self.Window,data.Tone) or self.Window.Theme.Surface3 end end; function object:Set(v) set(v) end; function object:Get() return value end; set(value); return object
end

function Tab:_addSkeleton(parent,data)
    data=data or {}; local row=self:_row(parent,data.Height or 82); row:SetAttribute("AstraV4Skeleton",true)
    local lines={0.55,0.8,0.42}; for i,w in ipairs(data.Widths or lines) do local f=Instance.new("Frame"); f.BackgroundColor3=self.Window.Theme.Surface3; f.BorderSizePixel=0; f.BackgroundTransparency=0.08; f.Position=UDim2.new(0,12,0,10+(i-1)*22); f.Size=UDim2.new(w,-12,0,12); f.Parent=row; v4Round(f,6) end
    return {Instance=row}
end

function Tab:_addStateCard(parent,data)
    data=data or {}; local row=self:_row(parent,data.Height or 112)
    local tone=v4Tone(self.Window,data.Tone or data.Type); local title=v4Label(row,data.Title or data.Name or "State",13,self.Window.Theme.TextPrimary,true); title.Position=UDim2.fromOffset(14,14); title.Size=UDim2.new(1,-28,0,22)
    local body=v4Label(row,data.Content or data.Description or "",10,self.Window.Theme.TextSecondary,false); body.Position=UDim2.fromOffset(14,40); body.Size=UDim2.new(1,-28,0,34)
    local dot=Instance.new("Frame"); dot.BackgroundColor3=tone; dot.BorderSizePixel=0; dot.Size=UDim2.fromOffset(7,7); dot.Position=UDim2.fromOffset(14,84); dot.Parent=row; v4Round(dot,999)
    if data.Action then local b=v4Button(row,data.Action.Text or "Retry",UDim2.fromOffset(88,30),self.Window.Theme.Surface3,self.Window.Theme.TextPrimary); b.AnchorPoint=Vector2.new(1,1); b.Position=UDim2.new(1,-12,1,-10); self.Window:_connect(b.MouseButton1Click,function() safeCall(data.Action.Callback) end) end
    return {Instance=row}
end

function Tab:_addList(parent,data)
    data=data or {}; local items=data.Items or {}; local height=data.Height or math.min(320,50+#items*44); local row=self:_row(parent,height); self:_titleBlock(row,data,12)
    local list=Instance.new("ScrollingFrame"); list.BackgroundTransparency=1; list.BorderSizePixel=0; list.Position=UDim2.fromOffset(10,40); list.Size=UDim2.new(1,-20,1,-48); list.AutomaticCanvasSize=Enum.AutomaticSize.Y; list.CanvasSize=UDim2.new(); list.ScrollBarThickness=2; list.Parent=row; v4List(list,5)
    local object={Instance=row,List=list}
    local function render(newItems) items=newItems or items; for _,c in ipairs(list:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end; for i,item in ipairs(items) do local itemData=type(item)=="table" and item or {Name=tostring(item)}; local b=v4Button(list,"",UDim2.new(1,-4,0,40),self.Window.Theme.Surface3,self.Window.Theme.TextPrimary); b.LayoutOrder=i; local n=v4Label(b,itemData.Name or itemData.Title or tostring(i),10,self.Window.Theme.TextPrimary,true); n.Position=UDim2.fromOffset(10,3); n.Size=UDim2.new(1,-20,0,17); local d=v4Label(b,itemData.Description or itemData.Value or "",9,self.Window.Theme.TextSecondary,false); d.Position=UDim2.fromOffset(10,20); d.Size=UDim2.new(1,-20,0,15); self.Window:_connect(b.MouseButton1Click,function() safeCall(data.Callback,itemData,i) end) end end
    function object:SetItems(new) render(new or {}) end; function object:GetItems() return items end; render(items); return object
end

function Tab:_addDataGrid(parent,data)
    data=data or {}; local columns=data.Columns or {}; local rows=data.Rows or {}; local height=data.Height or 300
    local outer=self:_row(parent,height); self:_titleBlock(outer,data,12)
    local grid=Instance.new("Frame"); grid.BackgroundColor3=self.Window.Theme.Surface3; grid.BorderSizePixel=0; grid.Position=UDim2.fromOffset(10,40); grid.Size=UDim2.new(1,-20,1,-48); grid.Parent=outer; v4Round(grid,10)
    local header=Instance.new("Frame"); header.BackgroundColor3=self.Window.Theme.Surface; header.BorderSizePixel=0; header.Size=UDim2.new(1,0,0,34); header.Parent=grid
    local list=Instance.new("ScrollingFrame"); list.BackgroundTransparency=1; list.BorderSizePixel=0; list.Position=UDim2.fromOffset(0,36); list.Size=UDim2.new(1,0,1,-36); list.AutomaticCanvasSize=Enum.AutomaticSize.Y; list.CanvasSize=UDim2.new(); list.ScrollBarThickness=2; list.Parent=grid; v4List(list,1)
    local widths={}; local total=0; for i,col in ipairs(columns) do widths[i]=tonumber(col.Width) or 1; total+=widths[i] end
    local render
    local x=0; for i,col in ipairs(columns) do local w=widths[i]/math.max(1,total); local h=v4Button(header,col.Name or col.Key or ("Column "..i),UDim2.new(w,-1,1,0),self.Window.Theme.Surface,self.Window.Theme.TextSecondary); h.Position=UDim2.new(x,0,0,0); h.TextXAlignment=Enum.TextXAlignment.Left; v4Padding(h,8,4,0,0); x+=w; if col.Sortable~=false then self.Window:_connect(h.MouseButton1Click,function() local key=col.Key or i; table.sort(rows,function(a,b) return tostring(type(a)=="table" and a[key] or a)<tostring(type(b)=="table" and b[key] or b) end); if render then render() end end) end end
    render=function() for _,c in ipairs(list:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end; for ri,rowData in ipairs(rows) do local r=Instance.new("TextButton"); r.Text=""; r.AutoButtonColor=false; r.BackgroundColor3=self.Window.Theme.Surface2; r.BorderSizePixel=0; r.Size=UDim2.new(1,0,0,36); r.LayoutOrder=ri; r.Parent=list; local xx=0; for ci,col in ipairs(columns) do local w=widths[ci]/math.max(1,total); local key=col.Key or ci; local val=type(rowData)=="table" and rowData[key] or rowData; local l=v4Label(r,val,9,self.Window.Theme.TextPrimary,false); l.Position=UDim2.new(xx,8,0,0); l.Size=UDim2.new(w,-16,1,0); l.TextWrapped=false; xx+=w end; self.Window:_connect(r.MouseButton1Click,function() safeCall(data.Callback,rowData,ri) end) end end
    local object={Instance=outer}; function object:SetRows(new) rows=new or {}; render() end; function object:GetRows() return rows end; render(); return object
end

function Tab:_addPlayerList(parent,data)
    data=data or {}; local listObject=self:_addList(parent,{Name=data.Name or "Players",Description=data.Description or "Players in the current server",Height=data.Height or 320,Items={},Callback=data.Callback})
    local function collect() local out={}; for _,p in ipairs(Players:GetPlayers()) do table.insert(out,{Name=p.DisplayName,Description="@"..p.Name,Player=p}) end; table.sort(out,function(a,b) return a.Name<b.Name end); return out end
    local function refresh() listObject:SetItems(collect()) end; self.Window:_connect(Players.PlayerAdded,refresh); self.Window:_connect(Players.PlayerRemoving,refresh); refresh(); return listObject
end

function Tab:_addServerCard(parent,data)
    data=data or {}; return self:_addInfoList(parent,{Name=data.Name or "Server",Description=data.Description or "Current server information",AutoRefresh=2,Items={{Label="Players",Value=function() return #Players:GetPlayers().." / "..tostring(Players.MaxPlayers) end},{Label="Place ID",Value=function() return tostring(game.PlaceId) end},{Label="Job ID",Value=function() local id=tostring(game.JobId or ""); return #id>12 and (string.sub(id,1,6).."…"..string.sub(id,-4)) or id end},{Label="Ping",Value=function(w) return tostring(w:GetTelemetry().Ping).." ms" end}}})
end

function Tab:_addRuntimeMonitor(parent,data)
    data=data or {}; return self:_addStatGrid(parent,{Name=data.Name or "Runtime",Description=data.Description or "Live client telemetry",AutoRefresh=1,Items={{Label="FPS",Value=function(w) return tostring(w:GetTelemetry().FPS) end},{Label="PING",Value=function(w) return tostring(w:GetTelemetry().Ping).." ms" end},{Label="MEMORY",Value=function(w) return tostring(w:GetTelemetry().Memory).." MB" end},{Label="INPUT",Value=function(w) return tostring(w:GetTelemetry().PreferredInput) end}}})
end

function Tab:_addPerformanceGraph(parent,data)
    data=data or {}; local row=self:_row(parent,data.Height or 150); self:_titleBlock(row,data,60)
    local graph=Instance.new("Frame"); graph.BackgroundColor3=self.Window.Theme.Surface3; graph.BorderSizePixel=0; graph.Position=UDim2.fromOffset(12,42); graph.Size=UDim2.new(1,-24,1,-54); graph.Parent=row; v4Round(graph,9)
    local points={}; local maxPoints=tonumber(data.Points) or 30; local object={Instance=row,Points=points}
    local function lineBetween(parent,a,b,color) local dx=b.X-a.X; local dy=b.Y-a.Y; local length=math.sqrt(dx*dx+dy*dy); local f=Instance.new("Frame"); f.AnchorPoint=Vector2.new(0,0.5); f.Position=UDim2.fromOffset(a.X,a.Y); f.Size=UDim2.fromOffset(length,2); f.Rotation=math.deg(math.atan2(dy,dx)); f.BackgroundColor3=color; f.BorderSizePixel=0; f.Parent=parent; return f end
    local function render() for _,c in ipairs(graph:GetChildren()) do if c:IsA("Frame") and c.Name=="Line" then c:Destroy() end end; if #points<2 then return end; local minV=data.Min; local maxV=data.Max; if minV==nil or maxV==nil then minV=math.huge; maxV=-math.huge; for _,v in ipairs(points) do minV=math.min(minV,v); maxV=math.max(maxV,v) end; if minV==maxV then minV-=1; maxV+=1 end end; local size=graph.AbsoluteSize; for i=2,#points do local x1=(i-2)/math.max(1,maxPoints-1)*size.X; local x2=(i-1)/math.max(1,maxPoints-1)*size.X; local y1=size.Y-(points[i-1]-minV)/(maxV-minV)*size.Y; local y2=size.Y-(points[i]-minV)/(maxV-minV)*size.Y; local line=lineBetween(graph,Vector2.new(x1,y1),Vector2.new(x2,y2),v4Tone(self.Window,data.Tone)); line.Name="Line" end end
    function object:Push(v) points[#points+1]=tonumber(v) or 0; while #points>maxPoints do table.remove(points,1) end; render() end
    if data.Value then task.spawn(function() while row.Parent and not self.Window.Destroyed do object:Push(tonumber(v4SafeText(data.Value,self.Window)) or 0); task.wait(data.Interval or 1) end end) end
    return object
end

function Tab:_addSystemHealth(parent,data)
    data=data or {}; local items=data.Items or {{Name="UI",Check=function() return not self.Window.Destroyed end},{Name="Config",Check=function() return self.Window.ExportConfig~=nil end},{Name="Key",Check=function() local k=self.Window.GetKeyInfo and self.Window:GetKeyInfo() or {}; return k.Status~="Locked" and not k.Expired end},{Name="Filesystem",Check=function() local c=self.Window.Library:GetCapabilities(); return c.FileSystem==true end},{Name="Clipboard",Check=function() local c=self.Window.Library:GetCapabilities(); return c.Clipboard==true end}}
    local mapped={}; for _,item in ipairs(items) do mapped[#mapped+1]={Label=item.Name,Value=function() local ok,result=pcall(item.Check,self.Window); return ok and result and "Healthy" or "Unavailable" end} end
    return self:_addInfoList(parent,{Name=data.Name or "System Health",Description=data.Description or "Core feature availability",AutoRefresh=2,Items=mapped})
end

function Tab:_addCapabilityViewer(parent,data)
    local caps=self.Window.Library:GetCapabilities(); local rows={}; for k,v in pairs(caps) do if type(v)=="boolean" then rows[#rows+1]={Name=k,Description=v and "Available" or "Unavailable"} end end; table.sort(rows,function(a,b) return a.Name<b.Name end); return self:_addList(parent,{Name=(data and data.Name) or "Capabilities",Description=(data and data.Description) or "Executor/runtime capabilities",Items=rows,Height=(data and data.Height) or 330})
end

function Tab:_addDependencyBox(parent,data)
    data=data or {}; local items={}; for _,req in ipairs(data.Requires or data.Items or {}) do items[#items+1]={Label=tostring(req),Value=function(w) return w:CheckRequirement(req) and "Available" or "Missing" end} end; return self:_addInfoList(parent,{Name=data.Name or "Dependencies",Description=data.Description or "Feature requirements",AutoRefresh=2,Items=items})
end

function Tab:_addKeyCard(parent,data)
    data=data or {}; local row=self:_row(parent,188); local title=v4Label(row,data.Name or "License",13,self.Window.Theme.TextPrimary,true); title.Position=UDim2.fromOffset(14,12); title.Size=UDim2.new(1,-28,0,22)
    local status=v4Label(row,"",9,self.Window.Theme.Accent,true); status.AnchorPoint=Vector2.new(1,0); status.Position=UDim2.new(1,-14,0,13); status.Size=UDim2.fromOffset(100,22); status.TextXAlignment=Enum.TextXAlignment.Right
    local tier=v4Label(row,"",18,self.Window.Theme.TextPrimary,true); tier.Position=UDim2.fromOffset(14,42); tier.Size=UDim2.new(1,-28,0,28)
    local key=v4Label(row,"",10,self.Window.Theme.TextSecondary,false); key.Position=UDim2.fromOffset(14,72); key.Size=UDim2.new(1,-28,0,22)
    local remain=v4Label(row,"",10,self.Window.Theme.TextSecondary,false); remain.Position=UDim2.fromOffset(14,100); remain.Size=UDim2.new(1,-28,0,22)
    local bar=Instance.new("Frame"); bar.BackgroundColor3=self.Window.Theme.Surface3; bar.BorderSizePixel=0; bar.Position=UDim2.fromOffset(14,136); bar.Size=UDim2.new(1,-28,0,7); bar.Parent=row; v4Round(bar,999)
    local fill=Instance.new("Frame"); fill.BackgroundColor3=self.Window.Theme.Accent; fill.BorderSizePixel=0; fill.Parent=bar; v4Round(fill,999)
    local meta=v4Label(row,"",9,self.Window.Theme.TextSecondary,false); meta.Position=UDim2.fromOffset(14,150); meta.Size=UDim2.new(1,-28,0,28)
    local object={Instance=row}
    local function refresh() local k=self.Window.GetKeyInfo and self.Window:GetKeyInfo() or {}; local permanent=k.Permanent==true; status.Text=permanent and "LIFETIME" or tostring(k.Status or "Not required"):upper(); tier.Text=tostring(k.Tier or k.Plan or "Default"); key.Text="Key  "..tostring(k.MaskedKey or "Not stored"); if permanent then remain.Text="Remaining  ∞"; fill.Size=UDim2.fromScale(1,1) else local remaining=tonumber(k.Remaining) or self.Window:GetKeyRemaining(); remain.Text="Remaining  "..(k.Expired and "Expired" or v4FormatDuration(remaining,false)); local duration=tonumber(k.Duration) or 0; fill.Size=UDim2.fromScale(duration>0 and v4Clamp(remaining/duration,0,1) or (k.Expired and 0 or 1),1) end; meta.Text="Issued  "..tostring(k.CreatedAt or k.IssuedAt or "—").."    ·    HWID  "..tostring(k.HWIDStatus or k.HwidStatus or "—") end
    task.spawn(function() while row.Parent and not self.Window.Destroyed do refresh(); task.wait(1) end end); refresh(); function object:Refresh() refresh() end; return object
end

function Tab:_addLockedFeature(parent,data)
    data=data or {}; local row=self:_row(parent,data.Height or 88); local title=v4Label(row,data.Name or "Premium Feature",12,self.Window.Theme.TextPrimary,true); title.Position=UDim2.fromOffset(14,13); title.Size=UDim2.new(1,-130,0,20); local desc=v4Label(row,data.Description or "Requires additional access.",10,self.Window.Theme.TextSecondary,false); desc.Position=UDim2.fromOffset(14,37); desc.Size=UDim2.new(1,-28,0,34); local badge=v4Label(row,string.upper(data.Badge or "LOCKED"),9,self.Window.Theme.Warning,true); badge.AnchorPoint=Vector2.new(1,0); badge.Position=UDim2.new(1,-14,0,13); badge.Size=UDim2.fromOffset(92,24); badge.TextXAlignment=Enum.TextXAlignment.Center; badge.BackgroundColor3=v4Mix(self.Window.Theme.Warning,self.Window.Theme.Surface2,0.82); badge.BackgroundTransparency=0; v4Round(badge,999)
    return {Instance=row,Unlock=function() badge.Text="UNLOCKED"; badge.TextColor3=self.Window.Theme.Success; safeCall(data.OnUnlock) end}
end

function Tab:_addActivityFeed(parent,data)
    data=data or {}; local list=self:_addList(parent,{Name=data.Name or "Recent Activity",Description=data.Description or "Latest actions in this Astra session",Height=data.Height or 300,Items={}})
    local function refresh() local items={}; for _,a in ipairs(self.Window:GetActivity(data.Limit or 8)) do local ago=math.floor(os.time()-a.Time); items[#items+1]={Name=a.Title,Description=(a.Description~="" and (a.Description.." · ") or "")..(ago<5 and "Now" or v4FormatDuration(ago,true).." ago")} end; list:SetItems(items) end
    task.spawn(function() while list.Instance.Parent and not self.Window.Destroyed do refresh(); task.wait(data.AutoRefresh or 1) end end); refresh(); return list
end

function Tab:_addChangelog(parent,data)
    data=data or {}; local items={}; for _,c in ipairs(data.Changes or {}) do items[#items+1]={Name=(c.Type or "Changed").." · "..tostring(c.Text or c.Description or ""),Description=c.Date or ""} end; return self:_addList(parent,{Name=data.Name or ("Changelog "..tostring(data.Version or "")),Description=data.Description or data.Date or "Latest changes",Items=items,Height=data.Height or math.min(340,70+#items*44)})
end

function Tab:_addTimeline(parent,data)
    data=data or {}; local items={}; for _,e in ipairs(data.Items or {}) do items[#items+1]={Name=tostring(e.Time or "").."  "..tostring(e.Title or e.Name or "Event"),Description=e.Description or ""} end; return self:_addList(parent,{Name=data.Name or "Timeline",Description=data.Description or "Activity timeline",Items=items,Height=data.Height or 300})
end

function Tab:_addAnnouncement(parent,data)
    data=data or {}; local row=self:_row(parent,data.Height or 86); local tone=v4Tone(self.Window,data.Type or data.Tone); local strip=Instance.new("Frame"); strip.BackgroundColor3=tone; strip.BorderSizePixel=0; strip.Position=UDim2.fromOffset(10,12); strip.Size=UDim2.fromOffset(3,(data.Height or 86)-24); strip.Parent=row; v4Round(strip,999); local title=v4Label(row,data.Title or data.Name or "Announcement",12,self.Window.Theme.TextPrimary,true); title.Position=UDim2.fromOffset(22,12); title.Size=UDim2.new(1,-36,0,20); local body=v4Label(row,data.Content or data.Description or "",10,self.Window.Theme.TextSecondary,false); body.Position=UDim2.fromOffset(22,34); body.Size=UDim2.new(1,-36,1,-44); return {Instance=row}
end

function Tab:_addAvatar(parent,data)
    data=data or {}; local userId=tonumber(data.UserId) or (Players.LocalPlayer and Players.LocalPlayer.UserId) or 0; local row=self:_row(parent,data.Height or 84); local img=Instance.new("ImageLabel"); img.BackgroundColor3=self.Window.Theme.Surface3; img.BorderSizePixel=0; img.Position=UDim2.fromOffset(12,12); img.Size=UDim2.fromOffset(60,60); img.ScaleType=Enum.ScaleType.Crop; img.Parent=row; v4Round(img,999); local title=v4Label(row,data.Name or "Avatar",12,self.Window.Theme.TextPrimary,true); title.Position=UDim2.fromOffset(86,16); title.Size=UDim2.new(1,-98,0,20); local sub=v4Label(row,"User ID · "..tostring(userId),10,self.Window.Theme.TextSecondary,false); sub.Position=UDim2.fromOffset(86,39); sub.Size=UDim2.new(1,-98,0,18); task.spawn(function() local ok,url=pcall(Players.GetUserThumbnailAsync,Players,userId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size180x180); if ok and img.Parent then img.Image=url end end); return {Instance=row,Image=img}
end

function Tab:_addUserCard(parent,data)
    data=data or {}; local p=data.Player or Players.LocalPlayer; local row=self:_row(parent,data.Height or 92); local img=Instance.new("ImageLabel"); img.BackgroundColor3=self.Window.Theme.Surface3; img.BorderSizePixel=0; img.Position=UDim2.fromOffset(12,14); img.Size=UDim2.fromOffset(62,62); img.Parent=row; img.ScaleType=Enum.ScaleType.Crop; v4Round(img,14); local name=v4Label(row,p and p.DisplayName or data.DisplayName or "Player",13,self.Window.Theme.TextPrimary,true); name.Position=UDim2.fromOffset(88,19); name.Size=UDim2.new(1,-180,0,22); local user=v4Label(row,"@"..tostring(p and p.Name or data.Username or "unknown"),10,self.Window.Theme.TextSecondary,false); user.Position=UDim2.fromOffset(88,44); user.Size=UDim2.new(1,-180,0,18); if p then task.spawn(function() local ok,url=pcall(Players.GetUserThumbnailAsync,Players,p.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size180x180); if ok and img.Parent then img.Image=url end end) end; if data.ButtonText then local b=v4Button(row,data.ButtonText,UDim2.fromOffset(78,32),self.Window.Theme.Surface3,self.Window.Theme.TextPrimary); b.AnchorPoint=Vector2.new(1,0.5); b.Position=UDim2.new(1,-12,0.5,0); self.Window:_connect(b.MouseButton1Click,function() safeCall(data.Callback,p) end) end; return {Instance=row,Player=p}
end

function Tab:_addStatusDot(parent,data)
    data=data or {}; local row=self:_row(parent,52); self:_titleBlock(row,data,108); local holder=Instance.new("Frame"); holder.BackgroundTransparency=1; holder.AnchorPoint=Vector2.new(1,0.5); holder.Position=UDim2.new(1,-12,0.5,0); holder.Size=UDim2.fromOffset(98,24); holder.Parent=row; local dot=Instance.new("Frame"); dot.BackgroundColor3=v4Tone(self.Window,data.Tone); dot.BorderSizePixel=0; dot.Position=UDim2.fromOffset(0,8); dot.Size=UDim2.fromOffset(8,8); dot.Parent=holder; v4Round(dot,999); local text=v4Label(holder,data.Value or "Ready",10,self.Window.Theme.TextSecondary,true); text.Position=UDim2.fromOffset(14,0); text.Size=UDim2.new(1,-14,1,0); local object={Instance=row}; function object:Set(value,tone) text.Text=tostring(value); dot.BackgroundColor3=v4Tone(self.Window,tone or data.Tone) end; return object
end

function Tab:_addPagination(parent,data)
    data=data or {}; local page=tonumber(data.Page) or 1; local pages=math.max(1,tonumber(data.Pages) or 1); local row=self:_row(parent,58); self:_titleBlock(row,data,190)
    local holder=Instance.new("Frame"); holder.BackgroundTransparency=1; holder.AnchorPoint=Vector2.new(1,0.5); holder.Position=UDim2.new(1,-12,0.5,0); holder.Size=UDim2.fromOffset(180,32); holder.Parent=row
    local prev=v4Button(holder,"<",UDim2.fromOffset(32,32),self.Window.Theme.Surface3,self.Window.Theme.TextPrimary); local label=v4Label(holder,"",10,self.Window.Theme.TextPrimary,true); label.Position=UDim2.fromOffset(38,0); label.Size=UDim2.fromOffset(104,32); label.TextXAlignment=Enum.TextXAlignment.Center; local nextB=v4Button(holder,">",UDim2.fromOffset(32,32),self.Window.Theme.Surface3,self.Window.Theme.TextPrimary); nextB.Position=UDim2.fromOffset(148,0)
    local object={Instance=row}; local function set(v,fire) page=v4Clamp(math.floor(tonumber(v) or page),1,pages); label.Text=page.." / "..pages; if fire~=false then safeCall(data.Callback,page,pages) end end; self.Window:_connect(prev.MouseButton1Click,function() set(page-1,true) end); self.Window:_connect(nextB.MouseButton1Click,function() set(page+1,true) end); function object:SetPage(v,fire) set(v,fire) end; function object:SetPages(v) pages=math.max(1,tonumber(v) or pages); set(page,false) end; function object:GetPage() return page end; set(page,false); return object
end

function Tab:_addVirtualList(parent,data)
    data=data or {}; local items=data.Items or {}; local itemHeight=tonumber(data.ItemHeight) or 38; local height=data.Height or 300; local outer=self:_row(parent,height); self:_titleBlock(outer,data,12)
    local sf=Instance.new("ScrollingFrame"); sf.BackgroundTransparency=1; sf.BorderSizePixel=0; sf.Position=UDim2.fromOffset(10,40); sf.Size=UDim2.new(1,-20,1,-48); sf.CanvasSize=UDim2.fromOffset(0,#items*itemHeight); sf.ScrollBarThickness=2; sf.Parent=outer
    local pool={}; local visible={}; local object={Instance=outer,List=sf}
    local function acquire() local f=table.remove(pool); if f then f.Visible=true; return f end; f=Instance.new("TextButton"); f.Text=""; f.AutoButtonColor=false; f.BackgroundColor3=self.Window.Theme.Surface3; f.BorderSizePixel=0; f.Size=UDim2.new(1,-4,0,itemHeight-2); f.Parent=sf; v4Round(f,8); local l=v4Label(f,"",10,self.Window.Theme.TextPrimary,false); l.Name="Text"; l.Position=UDim2.fromOffset(10,0); l.Size=UDim2.new(1,-20,1,0); return f end
    local function recycle() for _,f in pairs(visible) do f.Visible=false; table.insert(pool,f) end; visible={} end
    local function render() recycle(); local first=math.max(1,math.floor(sf.CanvasPosition.Y/itemHeight)+1); local count=math.ceil(sf.AbsoluteSize.Y/itemHeight)+2; for i=first,math.min(#items,first+count) do local f=acquire(); f.Position=UDim2.fromOffset(0,(i-1)*itemHeight); local textLabel=f:FindFirstChild("Text"); if textLabel then textLabel.Text=tostring(type(items[i])=="table" and (items[i].Name or items[i].Text or i) or items[i]) end; visible[i]=f; f:SetAttribute("AstraV4Index",i) end end
    self.Window:_connect(sf:GetPropertyChangedSignal("CanvasPosition"),render); self.Window:_connect(sf:GetPropertyChangedSignal("AbsoluteSize"),render); function object:SetItems(new) items=new or {}; sf.CanvasSize=UDim2.fromOffset(0,#items*itemHeight); render() end; render(); return object
end

function Tab:_addFlagInspector(parent,data)
    data=data or {}; local grid=self:_addDataGrid(parent,{Name=data.Name or "Flag Inspector",Description=data.Description or "Live values for every registered flag",Height=data.Height or 340,Columns={{Name="Flag",Key="Flag",Width=1.3},{Name="Value",Key="Value",Width=1}},Rows={}})
    local function refresh() local rows={}; for k,v in pairs(self.Window.Flags or {}) do rows[#rows+1]={Flag=k,Value=typeof(v)=="Color3" and tostring(v) or (type(v)=="table" and "table" or tostring(v))} end; table.sort(rows,function(a,b) return a.Flag<b.Flag end); grid:SetRows(rows) end; task.spawn(function() while grid.Instance.Parent and not self.Window.Destroyed do refresh(); task.wait(data.AutoRefresh or 1) end end); refresh(); return grid
end

function Tab:_addDebugConsole(parent,data)
    data=data or {}; local list=self:_addList(parent,{Name=data.Name or "Astra Console",Description=data.Description or "Internal framework events",Height=data.Height or 340,Items={}})
    local function refresh() local items={}; for i=math.max(1,#self.Window._v4Logs-(data.Limit or 50)+1),#self.Window._v4Logs do local e=self.Window._v4Logs[i]; items[#items+1]={Name="["..e.Level.."] "..e.Message,Description=os.date("%H:%M:%S",e.Time)} end; list:SetItems(items) end; task.spawn(function() while list.Instance.Parent and not self.Window.Destroyed do refresh(); task.wait(1) end end); return list
end

function Tab:_addBreakpointInspector(parent,data)
    return self:_addInfoList(parent,{Name=(data and data.Name) or "Responsive Inspector",Description=(data and data.Description) or "Current viewport and adaptive state",AutoRefresh=0.5,Items={{Label="Viewport",Value=function(w) return w:GetTelemetry().ViewportText end},{Label="Layout profile",Value=function(w) return w:GetLayoutProfile() end},{Label="Input",Value=function(w) return w:GetTelemetry().PreferredInput end},{Label="UI scale",Value=function(w) return string.format("%.2f",w._v4Preferences.UIScale or 1) end},{Label="Density",Value=function(w) return tostring(w.Density or w._v4Preferences.Density) end}}})
end

function Tab:_addShortcutViewer(parent,data)
    local items={}; for _,s in ipairs(self.Window:GetShortcuts()) do local keys={}; if s.Ctrl then keys[#keys+1]="Ctrl" end; if s.Shift then keys[#keys+1]="Shift" end; if s.Alt then keys[#keys+1]="Alt" end; keys[#keys+1]=s.Key.Name; items[#items+1]={Label=s.Name or "Shortcut",Value=table.concat(keys," + ")} end; return self:_addInfoList(parent,{Name=(data and data.Name) or "Keyboard Shortcuts",Description=(data and data.Description) or "Available Astra shortcuts",Items=items})
end

-- Config manager ------------------------------------------------------------
function Tab:_addConfigManager(parent,data)
    data=data or {}; local row=self:_row(parent,data.Height or 290); self:_titleBlock(row,data,12)
    local status=v4Label(row,"",9,self.Window.Theme.TextSecondary,false); status.Position=UDim2.fromOffset(12,40); status.Size=UDim2.new(1,-24,0,18)
    local actions=Instance.new("Frame"); actions.BackgroundTransparency=1; actions.Position=UDim2.fromOffset(12,62); actions.Size=UDim2.new(1,-24,0,34); actions.Parent=row; local lay=Instance.new("UIListLayout"); lay.FillDirection=Enum.FillDirection.Horizontal; lay.Padding=UDim.new(0,6); lay.Parent=actions
    local save=v4Button(actions,"Save",UDim2.fromOffset(80,32),self.Window.Theme.Accent,self.Window.Theme.AccentText); local load=v4Button(actions,"Load",UDim2.fromOffset(80,32),self.Window.Theme.Surface3,self.Window.Theme.TextPrimary); local reset=v4Button(actions,"Reset",UDim2.fromOffset(80,32),self.Window.Theme.Surface3,self.Window.Theme.TextPrimary)
    local diffList=Instance.new("ScrollingFrame"); diffList.BackgroundTransparency=1; diffList.BorderSizePixel=0; diffList.Position=UDim2.fromOffset(12,106); diffList.Size=UDim2.new(1,-24,1,-116); diffList.AutomaticCanvasSize=Enum.AutomaticSize.Y; diffList.CanvasSize=UDim2.new(); diffList.ScrollBarThickness=2; diffList.Parent=row; v4List(diffList,4)
    local function show(msg) status.Text=tostring(msg) end
    self.Window:_connect(save.MouseButton1Click,function() local ok,res=self.Window:SaveConfigFile(data.Path); show(ok and "Saved" or tostring(res)); self.Window:LogActivity({Title="Config saved",Description=tostring(data.Path or self.Window.Options.ConfigPath or "default"),Tone=ok and "success" or "warning"}) end)
    self.Window:_connect(load.MouseButton1Click,function() local ok,res=self.Window:LoadConfigFile(data.Path); show(ok and "Loaded" or tostring(res)); self.Window:LogActivity({Title="Config loaded",Description=tostring(data.Path or self.Window.Options.ConfigPath or "default"),Tone=ok and "success" or "warning"}) end)
    self.Window:_connect(reset.MouseButton1Click,function() self.Window:Confirm({Title="Reset configuration?",Content="All compatible controls will return to defaults.",Danger=true,OnConfirm=function() self.Window:ResetConfig(true); show("Reset") end}) end)
    if data.Autosave then self.Window:EnableAutosave(data.AutosaveInterval or 10,data.Path) end
    task.spawn(function() while row.Parent and not self.Window.Destroyed do show("Autosave: "..self.Window:GetAutosaveState().." · Flags: "..tostring((function() local c=0; for _ in pairs(self.Window.Flags or {}) do c+=1 end; return c end)())); task.wait(2) end end)
    return {Instance=row}
end

-- Subtabs / accordion / lazy ------------------------------------------------
function Tab:CreateSubTabs(options)
    options=options or {}; local host=Instance.new("Frame"); host.BackgroundTransparency=1; host.Size=UDim2.new(1,0,0,0); host.AutomaticSize=Enum.AutomaticSize.Y; host.Parent=self.Page; local buttons=Instance.new("Frame"); buttons.BackgroundColor3=self.Window.Theme.Surface; buttons.BorderSizePixel=0; buttons.Size=UDim2.new(1,0,0,38); buttons.Parent=host; v4Round(buttons,10); local buttonLayout=Instance.new("UIListLayout"); buttonLayout.FillDirection=Enum.FillDirection.Horizontal; buttonLayout.Padding=UDim.new(0,4); buttonLayout.Parent=buttons; local content=Instance.new("Frame"); content.BackgroundTransparency=1; content.Position=UDim2.fromOffset(0,46); content.Size=UDim2.new(1,0,0,0); content.AutomaticSize=Enum.AutomaticSize.Y; content.Parent=host
    local group={Tab=self,Window=self.Window,Host=host,Pages={},Buttons={},Current=nil}
    local function select(page) group.Current=page; for _,p in ipairs(group.Pages) do p.Frame.Visible=p==page; p.Button.BackgroundColor3=p==page and group.Window.Theme.AccentSoft or group.Window.Theme.Surface; p.Button.TextColor3=p==page and group.Window.Theme.TextPrimary or group.Window.Theme.TextSecondary end end
    function group:Create(name)
        local page={Group=self,Name=tostring(name)}; local b=v4Button(buttons,page.Name,UDim2.fromOffset(math.clamp(40+#page.Name*7,72,130),32),self.Window.Theme.Surface,self.Window.Theme.TextSecondary); page.Button=b; local frame=Instance.new("Frame"); frame.BackgroundTransparency=1; frame.Size=UDim2.new(1,0,0,0); frame.AutomaticSize=Enum.AutomaticSize.Y; frame.Parent=content; v4List(frame,7); page.Frame=frame; table.insert(self.Pages,page); table.insert(self.Buttons,b); self.Window:_connect(b.MouseButton1Click,function() select(page) end)
        local methods={}; for nameFn,under in pairs({AddButton="_addButton",AddToggle="_addToggle",AddSlider="_addSlider",AddInput="_addInput",AddDropdown="_addDropdown",AddKeybind="_addKeybind",AddCheckbox="_addCheckbox",AddSegmentedControl="_addSegmentedControl",AddStepper="_addStepper",AddList="_addList"}) do methods[nameFn]=function(_,data) return self.Tab[under](self.Tab,frame,data) end end; setmetatable(page,{__index=methods}); if #self.Pages==1 then select(page) else frame.Visible=false end; return page
    end
    return group
end

function Tab:AddAccordion(data)
    data=data or {}; local section=self:CreateSection({Name=data.Name or "Accordion",Description=data.Description})
    for _,item in ipairs(data.Items or {}) do
        local container=Instance.new("Frame"); container.BackgroundColor3=self.Window.Theme.Surface2; container.BorderSizePixel=0; container.Size=UDim2.new(1,0,0,42); container.Parent=section.Content or section.Frame; v4Round(container,10)
        local header=v4Button(container,item.Title or item.Name or "Item",UDim2.new(1,0,0,42),self.Window.Theme.Surface2,self.Window.Theme.TextPrimary); header.TextXAlignment=Enum.TextXAlignment.Left; v4Padding(header,12,12,0,0)
        local body=Instance.new("Frame"); body.BackgroundTransparency=1; body.Position=UDim2.fromOffset(10,48); body.Size=UDim2.new(1,-20,0,0); body.AutomaticSize=Enum.AutomaticSize.Y; body.Visible=false; body.Parent=container; v4List(body,6)
        if type(item.Build)=="function" then safeCall(item.Build,body,self) elseif item.Content then local l=v4Label(body,item.Content,10,self.Window.Theme.TextSecondary,false); l.AutomaticSize=Enum.AutomaticSize.Y end
        local open=false; self.Window:_connect(header.MouseButton1Click,function() open=not open; body.Visible=open; container.AutomaticSize=open and Enum.AutomaticSize.Y or Enum.AutomaticSize.None; if not open then container.Size=UDim2.new(1,0,0,42) end end)
    end
    return section
end

function Tab:CreateLazySection(options,builder)
    local placeholder=self:CreateSection({Name=(options and options.Name) or "Lazy content",Description=(options and options.Description) or "Builds on first view"})
    local built=false
    local function build() if built then return end; built=true; if type(builder)=="function" then safeCall(builder,placeholder,self) end end
    if self.Window.CurrentTab==self then build() else self.Window._v4LazyTabs[self]=self.Window._v4LazyTabs[self] or {}; table.insert(self.Window._v4LazyTabs[self],build) end
    return placeholder
end

local _V4SelectTab=Window.SelectTab
function Window:SelectTab(tab)
    _V4SelectTab(self,tab)
    if self._v4LazyTabs and self._v4LazyTabs[tab] then local builders=self._v4LazyTabs[tab]; self._v4LazyTabs[tab]=nil; for _,build in ipairs(builders) do safeCall(build) end end
end

-- Direct component API ------------------------------------------------------
local directMethods={
    AddQuickActions="_addQuickActions", AddSegmentedControl="_addSegmentedControl", AddCheckbox="_addCheckbox",
    AddRadioGroup="_addRadioGroup", AddStepper="_addStepper", AddNumberInput="_addNumberInput",
    AddRangeSlider="_addRangeSlider", AddComboBox="_addComboBox", AddTagInput="_addTagInput",
    AddBadge="_addBadge", AddProgressCard="_addProgressCard", AddCircularProgress="_addCircularProgress",
    AddSkeleton="_addSkeleton", AddStateCard="_addStateCard", AddList="_addList", AddDataGrid="_addDataGrid",
    AddPlayerList="_addPlayerList", AddServerCard="_addServerCard", AddRuntimeMonitor="_addRuntimeMonitor",
    AddPerformanceGraph="_addPerformanceGraph", AddSystemHealth="_addSystemHealth", AddCapabilityViewer="_addCapabilityViewer",
    AddDependencyBox="_addDependencyBox", AddKeyCard="_addKeyCard", AddLockedFeature="_addLockedFeature",
    AddActivityFeed="_addActivityFeed", AddChangelog="_addChangelog", AddTimeline="_addTimeline",
    AddAnnouncement="_addAnnouncement", AddAvatar="_addAvatar", AddUserCard="_addUserCard", AddStatusDot="_addStatusDot",
    AddPagination="_addPagination", AddVirtualList="_addVirtualList", AddFlagInspector="_addFlagInspector",
    AddDebugConsole="_addDebugConsole", AddBreakpointInspector="_addBreakpointInspector",
    AddShortcutViewer="_addShortcutViewer", AddConfigManager="_addConfigManager",
}
for public,internal in pairs(directMethods) do Tab[public]=function(self,data) return self[internal](self,self.Page,data) end end

local _V4CreateSection=Tab.CreateSection
function Tab:CreateSection(options)
    local section=_V4CreateSection(self,options)
    if not section then return section end
    local parent=section.Content or section.Frame
    for public,internal in pairs(directMethods) do section[public]=function(_,data) return self[internal](self,parent,data) end end
    function section:SetLocked(state,lockOptions)
        state=state==true; if section._v4Lock and section._v4Lock.Parent then section._v4Lock:Destroy() end
        if state then local overlay=Instance.new("Frame"); overlay.Name="AstraV4SectionLock"; overlay.BackgroundColor3=self.Window.Theme.Surface; overlay.BackgroundTransparency=0.08; overlay.BorderSizePixel=0; overlay.Size=UDim2.fromScale(1,1); overlay.ZIndex=70; overlay.Parent=section.Frame; v4Round(overlay,14); local text=v4Label(overlay,(lockOptions and lockOptions.Reason) or "Premium access required",11,self.Window.Theme.TextSecondary,true); text.Size=UDim2.fromScale(1,1); text.TextXAlignment=Enum.TextXAlignment.Center; text.ZIndex=71; section._v4Lock=overlay end
    end
    function section:Reset() for _,obj in pairs(self.Window.FlagObjects or {}) do if obj.Instance and obj.Instance:IsDescendantOf(section.Frame) and obj.GetDefault and obj.Set then obj:Set(obj:GetDefault(),true) end end end
    return section
end

-- Dashboard / application pages --------------------------------------------
function Window:CreateDashboard(options)
    options=options or {}
    local tab=self:CreateTab({Name=options.Name or "Home",Icon=options.Icon or "home",Description=options.Description or "Overview and quick access"})
    if options.Profile~=false then tab:AddPlayerProfile({Name=options.ProfileTitle or "Local Player",ShowMaskedKey=options.ShowMaskedKey==true}) end
    tab:AddRuntimeMonitor({Name="Session Overview",Description="Live performance and environment"})
    if options.QuickActions~=false then tab:AddQuickActions({Name="Quick Actions",Description="Frequently used actions",Actions=options.Actions or {{Name="Save",Callback=function() if self.SaveConfigFile then self:SaveConfigFile() end end},{Name="Commands",Callback=function() self:OpenCommandPalette() end},{Name="Notifications",Callback=function() self:OpenNotificationCenter() end}}}) end
    if options.Activity~=false then tab:AddActivityFeed({Name="Recent Activity",Limit=6,Height=250}) end
    if options.Changelog then tab:AddChangelog(options.Changelog) end
    return tab
end

function Window:CreateRuntimeTab(options)
    options=options or {}; local tab=self:CreateTab({Name=options.Name or "Runtime",Icon=options.Icon or "runtime",Description=options.Description or "Environment, performance and capabilities"}); tab:AddRuntimeMonitor({}); tab:AddPerformanceGraph({Name="FPS history",Description="Recent render rate",Value=function(w) return w:GetTelemetry().FPS end,Min=0,Max=120,Height=150,Tone="success"}); tab:AddServerCard({}); tab:AddSystemHealth({}); tab:AddCapabilityViewer({Height=300}); return tab
end

function Window:CreateAccessTab(options)
    options=options or {}; local tab=self:CreateTab({Name=options.Name or "Access",Icon=options.Icon or "config",Description=options.Description or "License and access information"}); tab:AddKeyCard({}); tab:AddDependencyBox({Name="Access Requirements",Requires=options.Requires or {"Premium","FileSystem","Clipboard"}}); return tab
end

function Window:CreateSettingsTab(options)
    options=options or {}; local tab=self:CreateTab({Name=options.Name or "Settings",Icon=options.Icon or "settings",Description=options.Description or "Interface and accessibility"}); local interface=tab:CreateSection({Name="Interface",Description="Scale, density and motion"}); interface:AddSlider({Name="UI Scale",Min=72,Max=125,Default=100,Suffix="%",Callback=function(v) self:SetUIScale(v/100) end}); interface:AddSegmentedControl({Name="Density",Options={"Compact","Comfortable","Spacious"},Default=self.Density or "Comfortable",Callback=function(v) if self.SetDensity then self:SetDensity(v) end; self._v4Preferences.Density=v end}); interface:AddSegmentedControl({Name="Motion",Options={"Reduced","Normal","Enhanced"},Default="Normal",Callback=function(v) self:SetMotionIntensity(v) end}); local access=tab:CreateSection({Name="Accessibility",Description="Readability and interaction preferences"}); access:AddCheckbox({Name="High contrast",Default=false,Callback=function(v) self:SetHighContrast(v) end}); access:AddCheckbox({Name="Reduce transparency",Default=false,Callback=function(v) self:SetReduceTransparency(v) end}); access:AddCheckbox({Name="Respect preferred text size",Default=true,Callback=function(v) self._v4Preferences.RespectPreferredTextSize=v; self:ApplyPreferredTextSize() end}); access:AddSegmentedControl({Name="Color states",Options={"None","Deuteranopia","Protanopia","Tritanopia"},Default="None",Callback=function(v) self:SetColorBlindMode(v) end}); local config=tab:CreateSection({Name="Configuration",Description="Persistence and reset"}); config:AddConfigManager({Autosave=options.Autosave==true}); return tab
end

function Window:CreateDeveloperMode(options)
    options=options or {}; local tab=self:CreateTab({Name=options.Name or "Developer",Icon=options.Icon or "runtime",Description=options.Description or "Astra diagnostics and component state"}); tab:AddBreakpointInspector({}); tab:AddFlagInspector({Height=300}); tab:AddDebugConsole({Height=300}); tab:AddShortcutViewer({}); return tab
end

function AstraUI:CreatePlayground(window,options)
    options=options or {}; local tab=window:CreateTab({Name=options.Name or "Playground",Icon=options.Icon or "visuals",Description="Astra component playground"}); local basics=tab:CreateSection({Name="Controls",Description="Interactive primitives"}); basics:AddCheckbox({Name="Checkbox",Description="Boolean selection",Default=true}); basics:AddSegmentedControl({Name="Segmented",Options={"One","Two","Three"},Default="Two"}); basics:AddRadioGroup({Name="Radio Group",Options={"Low","Medium","High"},Default="Medium"}); basics:AddStepper({Name="Stepper",Min=0,Max=10,Default=3}); basics:AddRangeSlider({Name="Range",Min=0,Max=100,DefaultMin=25,DefaultMax=75}); basics:AddTagInput({Name="Tags",Default={"Astra","V4"}}); local content=tab:CreateSection({Name="Content",Description="Application components"}); content:AddBadge({Name="Badge",Text="BETA",Tone="warning"}); content:AddProgressCard({Name="Progress Card",Default=72}); content:AddCircularProgress({Name="Circular Progress",Default=68}); content:AddStatusDot({Name="Status",Value="Healthy",Tone="success"}); content:AddStateCard({Title="Empty State",Content="No items yet. Add something to get started.",Tone="muted"}); return tab
end

-- Advanced profile tab: extend the V3.11 helper with runtime content --------
local _V4ProfileTab=Window.CreateProfileTab
function Window:CreateProfileTab(options)
    options=options or {}; local tab,profile,stats,info=_V4ProfileTab(self,options)
    local extra=tab:CreateSection({Name="Environment",Description="Current client and session state",Collapsible=true})
    extra:AddInfoList({AutoRefresh=1,Items={{Label="FPS",Value=function(w) return tostring(w:GetTelemetry().FPS) end},{Label="Ping",Value=function(w) return tostring(w:GetTelemetry().Ping).." ms" end},{Label="Memory",Value=function(w) return tostring(w:GetTelemetry().Memory).." MB" end},{Label="Input",Value=function(w) return tostring(w:GetTelemetry().PreferredInput) end},{Label="Viewport",Value=function(w) return w:GetTelemetry().ViewportText end},{Label="Astra",Value=function() return AstraUI.Version end}}})
    local key=tab:CreateSection({Name="License",Description="Detailed key metadata",Collapsible=true}); key:AddKeyCard({}); return tab,profile,stats,info
end

-- Automatic control registration in search/recents is already handled by
-- the existing Astra search registry plus the V4 wrappers above.

AstraUI.Version=V4_VERSION
end)()


-- ============================================================================
-- AstraUI V4.0 completeness layer
-- Adds the remaining convenience APIs from the application-framework roadmap.
-- ============================================================================
;(function()
local function v4cCopy(t) local o={}; for k,v in pairs(t or {}) do o[k]=v end; return o end

function Tab:_addToggleGroup(parent,data)
    data=data or {}
    local options=data.Options or {}
    local selected={}
    if type(data.Default)=="table" then
        for k,v in pairs(data.Default) do
            if type(k)=="number" then selected[tostring(v)]=true else selected[tostring(k)]=v==true end
        end
    end
    local height=46+#options*36
    local row=self:_row(parent,height)
    self:_titleBlock(row,data,12)
    local host=Instance.new("Frame")
    host.BackgroundTransparency=1
    host.Position=UDim2.fromOffset(12,40)
    host.Size=UDim2.new(1,-24,0,#options*36)
    host.Parent=row
    local layout=Instance.new("UIListLayout")
    layout.Padding=UDim.new(0,4)
    layout.Parent=host
    local object={Instance=row,Buttons={}}
    local function emit() safeCall(data.Callback,selected) end
    local function make(opt)
        local b=Instance.new("TextButton")
        b.AutoButtonColor=false; b.Text=""; b.BackgroundColor3=self.Window.Theme.Surface3; b.BorderSizePixel=0; b.Size=UDim2.new(1,0,0,32); b.Parent=host
        local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,9); c.Parent=b
        local box=Instance.new("Frame"); box.Position=UDim2.fromOffset(9,7); box.Size=UDim2.fromOffset(18,18); box.BorderSizePixel=0; box.Parent=b
        local cc=Instance.new("UICorner"); cc.CornerRadius=UDim.new(0,5); cc.Parent=box
        local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; l.Text=tostring(opt); l.TextColor3=self.Window.Theme.TextPrimary; l.TextSize=10; l.Font=Enum.Font.Gotham; l.TextXAlignment=Enum.TextXAlignment.Left; l.Position=UDim2.fromOffset(36,0); l.Size=UDim2.new(1,-44,1,0); l.Parent=b
        local function paint() local on=selected[tostring(opt)]==true; box.BackgroundColor3=on and self.Window.Theme.Accent or self.Window.Theme.Surface2; box.BackgroundTransparency=on and 0 or 0.05 end
        self.Window:_connect(b.MouseButton1Click,function() selected[tostring(opt)]=not selected[tostring(opt)]; paint(); emit() end)
        object.Buttons[tostring(opt)]={Button=b,Box=box,Paint=paint}; paint()
    end
    for _,opt in ipairs(options) do make(opt) end
    function object:Get() return selected end
    function object:Set(values,fire)
        selected={}
        for k,v in pairs(values or {}) do if type(k)=="number" then selected[tostring(v)]=true else selected[tostring(k)]=v==true end end
        for _,entry in pairs(self.Buttons) do entry.Paint() end
        if fire~=false then emit() end
    end
    return object
end

function Tab:AddToggleGroup(data) return self:_addToggleGroup(self.Page,data) end

local _V4CSection=Tab.CreateSection
function Tab:CreateSection(options)
    local section=_V4CSection(self,options)
    if section then
        local parent=section.Content or section.Frame
        function section:AddToggleGroup(data) return self.Tab:_addToggleGroup(parent,data) end
        function section:AddEmptyState(data) data=v4cCopy(data or {}); data.Tone=data.Tone or "muted"; data.Title=data.Title or "Nothing here yet"; return self.Tab:_addStateCard(parent,data) end
        function section:AddErrorState(data) data=v4cCopy(data or {}); data.Tone="error"; data.Title=data.Title or "Something went wrong"; return self.Tab:_addStateCard(parent,data) end
        function section:AddSuccessState(data) data=v4cCopy(data or {}); data.Tone="success"; data.Title=data.Title or "Completed"; return self.Tab:_addStateCard(parent,data) end
        function section:AddRecentActions(data) return self.Tab:_addRecentActions(parent,data) end
        function section:AddFavorites(data) return self.Tab:_addFavorites(parent,data) end
        function section:AddConfigDiff(data) return self.Tab:_addConfigDiff(parent,data) end
    end
    return section
end

function Tab:AddEmptyState(data) data=v4cCopy(data or {}); data.Tone=data.Tone or "muted"; data.Title=data.Title or "Nothing here yet"; return self:_addStateCard(self.Page,data) end
function Tab:AddErrorState(data) data=v4cCopy(data or {}); data.Tone="error"; data.Title=data.Title or "Something went wrong"; return self:_addStateCard(self.Page,data) end
function Tab:AddSuccessState(data) data=v4cCopy(data or {}); data.Tone="success"; data.Title=data.Title or "Completed"; return self:_addStateCard(self.Page,data) end

function Tab:_addFavorites(parent,data)
    data=data or {}
    local list=self:_addList(parent,{Name=data.Name or "Favorites",Description=data.Description or "Pinned controls and actions",Height=data.Height or 240,Items={}})
    local function refresh()
        local items={}
        for _,p in ipairs(self.Window:GetPinnedActions()) do items[#items+1]={Name=p.Name or "Pinned",Description=p.Description or "",Pinned=p} end
        list:SetItems(items)
    end
    task.spawn(function() while list.Instance.Parent and not self.Window.Destroyed do refresh(); task.wait(data.AutoRefresh or 1) end end)
    refresh()
    return list
end
function Tab:AddFavorites(data) return self:_addFavorites(self.Page,data) end

function Tab:_addRecentActions(parent,data)
    data=data or {}
    local list=self:_addList(parent,{Name=data.Name or "Recently Used",Description=data.Description or "Latest controls and actions",Height=data.Height or 240,Items={}})
    local function refresh()
        local items={}
        for _,p in ipairs(self.Window:GetRecentActions(data.Limit or 8)) do items[#items+1]={Name=p.Name or "Action",Description=p.Description or ""} end
        list:SetItems(items)
    end
    task.spawn(function() while list.Instance.Parent and not self.Window.Destroyed do refresh(); task.wait(data.AutoRefresh or 1) end end)
    refresh()
    return list
end
function Tab:AddRecentActions(data) return self:_addRecentActions(self.Page,data) end

function Window:RunProtected(name,callback,...)
    local args={...}
    local ok,result=pcall(function() return callback(table.unpack(args)) end)
    if ok then return true,result end
    self:Log("ERROR",tostring(name or "Protected callback").." failed",result)
    self:Notify({Title="Feature error",Content=tostring(result),Type="error",Duration=5})
    return false,result
end

function Window:GetSearchHistory()
    self._v4SearchHistory=self._v4SearchHistory or {}
    return self._v4SearchHistory
end
local _V4CSearchAll=Window.SearchAll
function Window:SearchAll(query)
    self._v4SearchHistory=self._v4SearchHistory or {}
    query=tostring(query or "")
    if query~="" and self._v4SearchHistory[1]~=query then
        table.insert(self._v4SearchHistory,1,query)
        while #self._v4SearchHistory>12 do table.remove(self._v4SearchHistory) end
    end
    return _V4CSearchAll(self,query)
end

function Window:CreateQuickAccess(options)
    options=options or {}
    local tab=self:CreateTab({Name=options.Name or "Quick Access",Icon=options.Icon or "home",Description=options.Description or "Favorites and recently used actions"})
    tab:AddFavorites({Height=220})
    tab:AddRecentActions({Height=220})
    return tab
end

function Window:GetOnScreenKeyboardInfo()
    local visible=false; local pos=Vector2.zero; local size=Vector2.zero
    pcall(function() visible=UserInputService.OnScreenKeyboardVisible end)
    pcall(function() pos=UserInputService.OnScreenKeyboardPosition end)
    pcall(function() size=UserInputService.OnScreenKeyboardSize end)
    return {Visible=visible,Position=pos,Size=size}
end

function Window:EnableKeyboardAwareness()
    if self._v4KeyboardAware then return end
    self._v4KeyboardAware=true
    pcall(function()
        self:_connect(UserInputService:GetPropertyChangedSignal("OnScreenKeyboardVisible"),function()
            local info=self:GetOnScreenKeyboardInfo()
            if info.Visible and self.CurrentTab and self.CurrentTab.Page then
                self.CurrentTab.Page.ScrollBarThickness=3
            end
        end)
    end)
end

function Window:SetGamepadNavigation(enabled)
    if not GuiService then return false end
    enabled=enabled~=false
    pcall(function() GuiService.AutoSelectGuiEnabled=enabled end)
    if enabled then
        for _,obj in ipairs(self.ScreenGui:GetDescendants()) do
            if obj:IsA("TextButton") or obj:IsA("TextBox") then obj.Selectable=true end
        end
        if self.CurrentTab and self.CurrentTab.Page then
            for _,obj in ipairs(self.CurrentTab.Page:GetDescendants()) do
                if obj:IsA("GuiButton") and obj.Visible then pcall(function() GuiService.SelectedObject=obj end); break end
            end
        end
    end
    return true
end

function Window:NormalizeAutomaticSizing()
    task.defer(function()
        for _,row in ipairs(self.ScreenGui:GetDescendants()) do
            if row:IsA("Frame") and row:GetAttribute("AstraV38Role")=="Row" then
                local needed=row.Size.Y.Offset
                for _,child in ipairs(row:GetChildren()) do
                    if child:IsA("TextLabel") and child.TextWrapped and child.Visible then
                        needed=math.max(needed,child.Position.Y.Offset+child.TextBounds.Y+10)
                    end
                end
                if needed>row.Size.Y.Offset then row.Size=UDim2.new(row.Size.X.Scale,row.Size.X.Offset,0,needed) end
            end
        end
    end)
end

function Window:ShowKeyExpirationWarning(threshold)
    threshold=tonumber(threshold) or 86400
    local k=self.GetKeyInfo and self:GetKeyInfo() or {}
    if k.Permanent or not k.ExpiresAt or k.Expired then return false end
    local remaining=self:GetKeyRemaining()
    if remaining<=threshold then
        self:Notify({Title="Key expires soon",Content="Remaining: "..v4FormatDuration(remaining,false),Type="warning",Duration=6})
        return true
    end
    return false
end

function Window:SetAccessLevel(level,metadata)
    local info=v4cCopy(metadata or {})
    info.Tier=level
    info.Status=info.Status or "Unlocked"
    if self.SetKeyInfo then self:SetKeyInfo(info) end
end

function Window:GetConfigFiles(folder)
    folder=folder or "AstraUI"
    local fn=listfiles
    if type(fn)~="function" then return false,"listfiles unavailable" end
    local ok,files=pcall(fn,folder)
    if not ok then return false,files end
    return true,files
end
function Window:DeleteConfig(path)
    if type(delfile)~="function" then return false,"delfile unavailable" end
    local ok,err=pcall(delfile,path); return ok,err
end
function Window:DuplicateConfig(source,destination)
    if type(readfile)~="function" or type(writefile)~="function" then return false,"filesystem unavailable" end
    local ok,data=pcall(readfile,source); if not ok then return false,data end
    local ok2,err=pcall(writefile,destination,data); return ok2,err
end
function Window:RenameConfig(source,destination)
    local ok,err=self:DuplicateConfig(source,destination); if not ok then return false,err end
    local deleted=self:DeleteConfig(source); return deleted,destination
end

function Window:PreviewConfigDiff(config)
    local diff=self:DiffConfig(config)
    return self:BottomSheet({Title="Configuration changes",Height=math.min(520,140+#diff*40),Build=function(parent,close)
        local list=Instance.new("ScrollingFrame"); list.Size=UDim2.new(1,0,1,-46); list.BackgroundTransparency=1; list.BorderSizePixel=0; list.AutomaticCanvasSize=Enum.AutomaticSize.Y; list.CanvasSize=UDim2.new(); list.ScrollBarThickness=2; list.Parent=parent
        local layout=Instance.new("UIListLayout"); layout.Padding=UDim.new(0,5); layout.Parent=list
        for _,change in ipairs(diff) do
            local row=Instance.new("Frame"); row.BackgroundColor3=self.Theme.Surface2; row.BorderSizePixel=0; row.Size=UDim2.new(1,0,0,36); row.Parent=list
            local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,9); c.Parent=row
            local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; l.Text=tostring(change.Flag).."    "..tostring(change.Before).."  →  "..tostring(change.After); l.TextColor3=self.Theme.TextPrimary; l.TextSize=10; l.Font=Enum.Font.Gotham; l.TextXAlignment=Enum.TextXAlignment.Left; l.Position=UDim2.fromOffset(10,0); l.Size=UDim2.new(1,-20,1,0); l.Parent=row
        end
        local done=Instance.new("TextButton"); done.Text="Close"; done.TextSize=10; done.Font=Enum.Font.GothamMedium; done.TextColor3=self.Theme.AccentText; done.BackgroundColor3=self.Theme.Accent; done.BorderSizePixel=0; done.AnchorPoint=Vector2.new(1,1); done.Position=UDim2.new(1,0,1,0); done.Size=UDim2.fromOffset(88,32); done.Parent=parent; local cc=Instance.new("UICorner"); cc.CornerRadius=UDim.new(0,10); cc.Parent=done; self:_connect(done.MouseButton1Click,close)
    end})
end

function Tab:_addConfigDiff(parent,data)
    data=data or {}
    local window=self.Window
    local object=self:_addDataGrid(parent,{Name=data.Name or "Config Diff",Description=data.Description or "Compare current flags against another configuration",Height=data.Height or 260,Columns={{Name="Flag",Key="Flag",Width=1.2},{Name="Before",Key="Before",Width=1},{Name="After",Key="After",Width=1}},Rows={}})
    function object:SetConfig(config) self:SetRows(window:DiffConfig(config)) end
    if data.Config then object:SetRows(window:DiffConfig(data.Config)) end
    return object
end
function Tab:AddConfigDiff(data) return self:_addConfigDiff(self.Page,data) end

function Window:CreateCollapsibleGroup(options)
    options=options or {}
    local tab=options.Tab or self.CurrentTab
    if not tab then return nil end
    options.Collapsible=true
    return tab:CreateSection(options)
end

function Window:CreateShortcutViewer(options)
    local tab=self:CreateTab({Name=(options and options.Name) or "Shortcuts",Icon=(options and options.Icon) or "runtime",Description=(options and options.Description) or "Keyboard and input shortcuts"})
    tab:AddShortcutViewer({})
    return tab
end

function Window:CreateApplication(options)
    options=options or {}
    local result={}
    if options.Dashboard~=false then result.Dashboard=self:CreateDashboard(options.DashboardOptions or {}) end
    if options.Profile~=false then result.Profile=self:CreateProfileTab(options.ProfileOptions or {}) end
    if options.Access~=false then result.Access=self:CreateAccessTab(options.AccessOptions or {}) end
    if options.Runtime~=false then result.Runtime=self:CreateRuntimeTab(options.RuntimeOptions or {}) end
    if options.Settings~=false then result.Settings=self:CreateSettingsTab(options.SettingsOptions or {}) end
    if options.Developer==true then result.Developer=self:CreateDeveloperMode(options.DeveloperOptions or {}) end
    if options.Playground==true then result.Playground=self.Library:CreatePlayground(self,options.PlaygroundOptions or {}) end
    return result
end

AstraUI.Version="4.0.0-application"
end)()


-- ============================================================================
-- AstraUI V4.0 adaptive/icon/config completeness patch
-- ============================================================================
;(function()

function Window:OnPreferredInputChanged(callback)
    self._v4InputListeners=self._v4InputListeners or {}
    table.insert(self._v4InputListeners,callback)
    local alive=true
    local last=v4GetPreferredInput()
    task.spawn(function()
        while alive and not self.Destroyed do
            local now=v4GetPreferredInput()
            if now~=last then last=now; safeCall(callback,now,self:GetLayoutProfile()) end
            task.wait(0.25)
        end
    end)
    return {Disconnect=function() alive=false end}
end

function Window:ApplySafeArea(enabled)
    if enabled==false then return end
    local camera=workspace.CurrentCamera
    if not camera or not self.Root then return end
    local tl,br=self:GetSafeArea()
    if self.Options and self.Options.IgnoreGuiInset==true then
        local vp=camera.ViewportSize
        local safeW=math.max(1,vp.X-tl.X-br.X)
        local safeH=math.max(1,vp.Y-tl.Y-br.Y)
        local cx=tl.X+safeW/2
        local cy=tl.Y+safeH/2
        self.Root.Position=UDim2.fromOffset(cx,cy)
    end
end

local _V4ColorBlind=Window.SetColorBlindMode
function Window:SetColorBlindMode(mode)
    _V4ColorBlind(self,mode)
    mode=string.lower(tostring(mode or "none"))
    if mode=="deuteranopia" or mode=="protanopia" then
        self:SetTheme({Success=Color3.fromRGB(66,135,245),Warning=Color3.fromRGB(245,170,55),Danger=Color3.fromRGB(202,86,255)})
    elseif mode=="tritanopia" then
        self:SetTheme({Success=Color3.fromRGB(61,193,122),Warning=Color3.fromRGB(230,117,202),Danger=Color3.fromRGB(230,90,90)})
    else
        -- Restore semantic state colors from the active preset when possible.
        local preset=self._v38PresetName or "Midnight"
        if self.SetThemePreset then pcall(function() self:SetThemePreset(preset) end) end
    end
end

function AstraUI:RenderIcon(parent,name,window,options)
    options=options or {}
    local size=options.Size or 18
    local color=options.Color or (window and (window.Theme.TextSecondary or window.Theme.Muted)) or Color3.new(1,1,1)
    local host=Instance.new("Frame")
    host.Name="AstraIcon_"..tostring(name)
    host.BackgroundTransparency=1
    host.BorderSizePixel=0
    host.Size=UDim2.fromOffset(size,size)
    host.Parent=parent
    local function line(x,y,w,h,rot)
        local f=Instance.new("Frame"); f.BackgroundColor3=color; f.BorderSizePixel=0; f.Position=UDim2.fromScale(x,y); f.AnchorPoint=Vector2.new(0.5,0.5); f.Size=UDim2.fromScale(w,h); f.Rotation=rot or 0; f.Parent=host; local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(1,0); c.Parent=f; return f
    end
    local function ring(x,y,w,h)
        local f=Instance.new("Frame"); f.BackgroundTransparency=1; f.BorderSizePixel=0; f.Position=UDim2.fromScale(x,y); f.AnchorPoint=Vector2.new(0.5,0.5); f.Size=UDim2.fromScale(w,h); f.Parent=host; local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(1,0); c.Parent=f; local st=Instance.new("UIStroke"); st.Color=color; st.Thickness=1.4; st.Parent=f; return f
    end
    name=string.lower(tostring(name or "info"))
    if name=="search" then ring(.42,.42,.52,.52); line(.72,.72,.36,.09,45)
    elseif name=="user" or name=="profile" then ring(.5,.34,.35,.35); ring(.5,.85,.68,.45)
    elseif name=="server" then line(.5,.25,.72,.12); line(.5,.5,.72,.12); line(.5,.75,.72,.12)
    elseif name=="key" then ring(.32,.5,.36,.36); line(.68,.5,.50,.10); line(.78,.62,.10,.20); line(.9,.58,.08,.16)
    elseif name=="clock" then ring(.5,.5,.82,.82); line(.5,.48,.08,.32,-5); line(.6,.58,.28,.08,35)
    elseif name=="save" then ring(.5,.5,.78,.78); line(.5,.28,.42,.10); line(.5,.68,.38,.26)
    elseif name=="folder" then line(.5,.58,.78,.48); line(.3,.28,.32,.13)
    elseif name=="trash" then line(.5,.62,.52,.56); line(.5,.27,.64,.10); line(.5,.15,.28,.10)
    elseif name=="copy" then ring(.62,.58,.55,.55); ring(.38,.38,.55,.55)
    elseif name=="check" then line(.35,.55,.30,.10,42); line(.62,.48,.50,.10,-45)
    elseif name=="warning" then line(.5,.45,.10,.42); line(.5,.76,.11,.11)
    elseif name=="bell" then ring(.5,.52,.62,.66); line(.5,.87,.18,.10)
    elseif name=="lock" or name=="unlock" then ring(.5,.35,.45,.52); line(.5,.67,.66,.46)
    elseif name=="eye" or name=="eyeoff" then ring(.5,.5,.82,.48); ring(.5,.5,.23,.23); if name=="eyeoff" then line(.5,.5,.95,.08,45) end
    elseif name=="pin" then ring(.5,.36,.40,.40); line(.5,.68,.10,.52); line(.5,.89,.35,.08)
    elseif name=="star" then line(.5,.5,.72,.10); line(.5,.5,.72,.10,72); line(.5,.5,.72,.10,144); line(.5,.5,.72,.10,216); line(.5,.5,.72,.10,288)
    elseif name=="refresh" then ring(.5,.5,.76,.76); line(.75,.24,.28,.08,35)
    elseif name=="terminal" or name=="command" then ring(.5,.5,.82,.68); line(.34,.45,.24,.08,35); line(.34,.58,.24,.08,-35); line(.66,.66,.28,.08)
    elseif name=="play" then line(.45,.5,.62,.10,60); line(.45,.5,.62,.10,-60)
    elseif name=="pause" then line(.36,.5,.12,.62); line(.64,.5,.12,.62)
    elseif name=="info" then ring(.5,.5,.82,.82); line(.5,.58,.09,.34); line(.5,.28,.10,.10)
    else
        line(.5,.5,.70,.10); line(.5,.5,.10,.70)
    end
    return host
end

function Window:CreateLazyTab(options,builder)
    options=options or {}
    local tab=self:CreateTab(options)
    self._v4LazyTabs=self._v4LazyTabs or {}
    self._v4LazyTabs[tab]=self._v4LazyTabs[tab] or {}
    table.insert(self._v4LazyTabs[tab],function() if type(builder)=="function" then safeCall(builder,tab,self) end end)
    return tab
end

function Tab:_addConfigBrowser(parent,data)
    data=data or {}
    local row=self:_row(parent,data.Height or 330)
    self:_titleBlock(row,data,12)
    local folder=data.Folder or "AstraUI"
    local status=Instance.new("TextLabel"); status.BackgroundTransparency=1; status.Text=""; status.TextColor3=self.Window.Theme.TextSecondary; status.TextSize=9; status.Font=Enum.Font.Gotham; status.TextXAlignment=Enum.TextXAlignment.Left; status.Position=UDim2.fromOffset(12,40); status.Size=UDim2.new(1,-24,0,18); status.Parent=row
    local list=Instance.new("ScrollingFrame"); list.BackgroundTransparency=1; list.BorderSizePixel=0; list.Position=UDim2.fromOffset(12,62); list.Size=UDim2.new(1,-24,1,-74); list.AutomaticCanvasSize=Enum.AutomaticSize.Y; list.CanvasSize=UDim2.new(); list.ScrollBarThickness=2; list.Parent=row; local layout=Instance.new("UIListLayout"); layout.Padding=UDim.new(0,5); layout.Parent=list
    local object={Instance=row}
    local function refresh()
        for _,child in ipairs(list:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
        local ok,files=self.Window:GetConfigFiles(folder)
        if not ok then status.Text="Config browsing unavailable: "..tostring(files); return end
        status.Text=tostring(#files).." file(s)"
        for i,path in ipairs(files) do
            local item=Instance.new("Frame"); item.BackgroundColor3=self.Window.Theme.Surface3; item.BorderSizePixel=0; item.Size=UDim2.new(1,-4,0,42); item.LayoutOrder=i; item.Parent=list; local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,9); c.Parent=item
            local name=Instance.new("TextLabel"); name.BackgroundTransparency=1; name.Text=tostring(path):match("[^/\\]+$") or tostring(path); name.TextColor3=self.Window.Theme.TextPrimary; name.TextSize=10; name.Font=Enum.Font.GothamMedium; name.TextXAlignment=Enum.TextXAlignment.Left; name.Position=UDim2.fromOffset(10,0); name.Size=UDim2.new(1,-150,1,0); name.Parent=item
            local load=Instance.new("TextButton"); load.Text="Load"; load.TextSize=9; load.Font=Enum.Font.GothamMedium; load.TextColor3=self.Window.Theme.TextPrimary; load.BackgroundColor3=self.Window.Theme.Surface2; load.BorderSizePixel=0; load.AnchorPoint=Vector2.new(1,0.5); load.Position=UDim2.new(1,-56,0.5,0); load.Size=UDim2.fromOffset(58,28); load.Parent=item; local lc=Instance.new("UICorner"); lc.CornerRadius=UDim.new(0,8); lc.Parent=load
            local del=Instance.new("TextButton"); del.Text="x"; del.TextSize=10; del.Font=Enum.Font.GothamBold; del.TextColor3=self.Window.Theme.Danger; del.BackgroundColor3=self.Window.Theme.Surface2; del.BorderSizePixel=0; del.AnchorPoint=Vector2.new(1,0.5); del.Position=UDim2.new(1,-12,0.5,0); del.Size=UDim2.fromOffset(32,28); del.Parent=item; local dc=Instance.new("UICorner"); dc.CornerRadius=UDim.new(0,8); dc.Parent=del
            self.Window:_connect(load.MouseButton1Click,function() local ok2,res=self.Window:LoadConfigFile(path); self.Window:ShowSnackbar(ok2 and "Loaded "..name.Text or tostring(res)) end)
            self.Window:_connect(del.MouseButton1Click,function() self.Window:Confirm({Title="Delete config?",Content=name.Text,Danger=true,OnConfirm=function() self.Window:DeleteConfig(path); refresh() end}) end)
        end
    end
    function object:Refresh() refresh() end
    refresh()
    return object
end
function Tab:AddConfigBrowser(data) return self:_addConfigBrowser(self.Page,data) end

local _V4IconSection=Tab.CreateSection
function Tab:CreateSection(options)
    local section=_V4IconSection(self,options)
    if section then
        local parent=section.Content or section.Frame
        function section:AddConfigBrowser(data) return self.Tab:_addConfigBrowser(parent,data) end
    end
    return section
end

AstraUI.Version="4.0.0-application"
end)()

return AstraUI.new()
