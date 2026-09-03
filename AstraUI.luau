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

local AstraUI = {}
AstraUI.__index = AstraUI
AstraUI.Version = "2.0.0"

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

    local parent = options.Parent
    if not parent then
        if RunService:IsStudio() then
            parent = LocalPlayer:WaitForChild("PlayerGui")
        else
            parent = LocalPlayer:WaitForChild("PlayerGui")
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
        Name = options.Name or "AstraUI",
        ResetOnSpawn = false,
        IgnoreGuiInset = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = options.DisplayOrder or 10,
        Parent = parent,
    })

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

            input.Changed:Connect(function()
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
        if dragging and input == dragInput then
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


return AstraUI.new()
