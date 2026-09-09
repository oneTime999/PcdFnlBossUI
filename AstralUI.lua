--[[
    AstralUI
    Rayfield-inspired UI library for Roblox/Luau executors.
    UI only: no anti-cheat bypasses, game exploits, or automation logic.

    Features:
    - Desktop + mobile layout
    - Draggable window
    - Tabs / sections
    - Buttons / toggles / sliders / inputs / dropdowns / labels
    - Notifications
    - Built-in themes: Default, Halloween, Christmas, Ocean, Sakura, Midnight
    - Runtime theme switching
    - Minimize / close
    - Touch-friendly controls
]]

local AstralUI = {}
AstralUI.__index = AstralUI

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local function clamp(v, a, b)
	return math.max(a, math.min(b, v))
end

local function tween(obj, time, props, style, direction)
	local info = TweenInfo.new(
		time or 0.18,
		style or Enum.EasingStyle.Quint,
		direction or Enum.EasingDirection.Out
	)
	local t = TweenService:Create(obj, info, props)
	t:Play()
	return t
end

local function new(className, props)
	local obj = Instance.new(className)
	for k, v in pairs(props or {}) do
		obj[k] = v
	end
	return obj
end

local function corner(parent, radius)
	return new("UICorner", {
		Parent = parent,
		CornerRadius = UDim.new(0, radius or 10)
	})
end

local function stroke(parent, color, transparency, thickness)
	return new("UIStroke", {
		Parent = parent,
		Color = color or Color3.fromRGB(255,255,255),
		Transparency = transparency or 0.85,
		Thickness = thickness or 1
	})
end

local function padding(parent, l, r, t, b)
	return new("UIPadding", {
		Parent = parent,
		PaddingLeft = UDim.new(0, l or 0),
		PaddingRight = UDim.new(0, r or 0),
		PaddingTop = UDim.new(0, t or 0),
		PaddingBottom = UDim.new(0, b or 0)
	})
end

local function list(parent, direction, gap)
	return new("UIListLayout", {
		Parent = parent,
		FillDirection = direction or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap or 8)
	})
end

local function textSize(text, font, size, maxWidth)
	local service = game:GetService("TextService")
	return service:GetTextSize(text, size, font, Vector2.new(maxWidth or 1000, 1000))
end

local function safeParent()
	local ok, result = pcall(function()
		if gethui then
			return gethui()
		end
	end)
	if ok and result then return result end

	local okCore, hidden = pcall(function()
		if cloneref then
			return cloneref(CoreGui)
		end
		return CoreGui
	end)
	if okCore and hidden then return hidden end

	return LocalPlayer:WaitForChild("PlayerGui")
end

AstralUI.Themes = {
	Default = {
		Background = Color3.fromRGB(15, 17, 22),
		Surface = Color3.fromRGB(21, 24, 31),
		Surface2 = Color3.fromRGB(28, 31, 40),
		Surface3 = Color3.fromRGB(34, 38, 49),
		Accent = Color3.fromRGB(110, 92, 255),
		Accent2 = Color3.fromRGB(143, 128, 255),
		Text = Color3.fromRGB(245, 247, 255),
		SubText = Color3.fromRGB(165, 171, 188),
		Muted = Color3.fromRGB(95, 101, 118),
		Success = Color3.fromRGB(70, 214, 146),
		Danger = Color3.fromRGB(255, 92, 110),
		Warning = Color3.fromRGB(255, 190, 76),
	},
	Halloween = {
		Background = Color3.fromRGB(13, 10, 16),
		Surface = Color3.fromRGB(23, 17, 29),
		Surface2 = Color3.fromRGB(34, 23, 40),
		Surface3 = Color3.fromRGB(45, 29, 50),
		Accent = Color3.fromRGB(255, 121, 28),
		Accent2 = Color3.fromRGB(179, 75, 255),
		Text = Color3.fromRGB(255, 246, 236),
		SubText = Color3.fromRGB(201, 185, 207),
		Muted = Color3.fromRGB(119, 100, 128),
		Success = Color3.fromRGB(94, 220, 121),
		Danger = Color3.fromRGB(255, 73, 93),
		Warning = Color3.fromRGB(255, 174, 54),
	},
	Christmas = {
		Background = Color3.fromRGB(10, 17, 15),
		Surface = Color3.fromRGB(17, 29, 25),
		Surface2 = Color3.fromRGB(22, 39, 33),
		Surface3 = Color3.fromRGB(30, 52, 43),
		Accent = Color3.fromRGB(224, 55, 72),
		Accent2 = Color3.fromRGB(63, 184, 115),
		Text = Color3.fromRGB(248, 255, 251),
		SubText = Color3.fromRGB(181, 204, 191),
		Muted = Color3.fromRGB(99, 126, 111),
		Success = Color3.fromRGB(69, 202, 119),
		Danger = Color3.fromRGB(231, 70, 83),
		Warning = Color3.fromRGB(238, 204, 86),
	},
	Ocean = {
		Background = Color3.fromRGB(8, 16, 27),
		Surface = Color3.fromRGB(12, 27, 44),
		Surface2 = Color3.fromRGB(16, 37, 59),
		Surface3 = Color3.fromRGB(20, 48, 76),
		Accent = Color3.fromRGB(42, 145, 255),
		Accent2 = Color3.fromRGB(70, 203, 255),
		Text = Color3.fromRGB(239, 248, 255),
		SubText = Color3.fromRGB(159, 188, 213),
		Muted = Color3.fromRGB(81, 113, 140),
		Success = Color3.fromRGB(69, 215, 169),
		Danger = Color3.fromRGB(255, 94, 112),
		Warning = Color3.fromRGB(255, 194, 80),
	},
	Sakura = {
		Background = Color3.fromRGB(24, 16, 23),
		Surface = Color3.fromRGB(35, 23, 34),
		Surface2 = Color3.fromRGB(48, 29, 45),
		Surface3 = Color3.fromRGB(61, 36, 57),
		Accent = Color3.fromRGB(255, 104, 170),
		Accent2 = Color3.fromRGB(255, 153, 198),
		Text = Color3.fromRGB(255, 242, 249),
		SubText = Color3.fromRGB(215, 176, 198),
		Muted = Color3.fromRGB(137, 99, 121),
		Success = Color3.fromRGB(89, 215, 151),
		Danger = Color3.fromRGB(255, 86, 117),
		Warning = Color3.fromRGB(255, 196, 101),
	},
	Midnight = {
		Background = Color3.fromRGB(8, 9, 15),
		Surface = Color3.fromRGB(13, 15, 24),
		Surface2 = Color3.fromRGB(20, 22, 35),
		Surface3 = Color3.fromRGB(27, 30, 46),
		Accent = Color3.fromRGB(94, 113, 255),
		Accent2 = Color3.fromRGB(131, 98, 255),
		Text = Color3.fromRGB(241, 244, 255),
		SubText = Color3.fromRGB(154, 162, 190),
		Muted = Color3.fromRGB(82, 89, 112),
		Success = Color3.fromRGB(74, 210, 151),
		Danger = Color3.fromRGB(255, 87, 109),
		Warning = Color3.fromRGB(242, 187, 70),
	}
}

local function disconnectAll(tbl)
	for _, c in ipairs(tbl or {}) do
		pcall(function() c:Disconnect() end)
	end
end

function AstralUI:CreateWindow(config)
	config = config or {}

	local self = setmetatable({}, AstralUI)
	self.Config = config
	self.Name = config.Name or "AstralUI"
	self.ThemeName = config.Theme or "Default"
	self.Theme = AstralUI.Themes[self.ThemeName] or AstralUI.Themes.Default
	self.MobileBreakpoint = config.MobileBreakpoint or 720
	self.Connections = {}
	self.ThemeObjects = {}
	self.Tabs = {}
	self.ActiveTab = nil
	self.Minimized = false
	self.Destroyed = false

	local gui = new("ScreenGui", {
		Name = "AstralUI_" .. tostring(math.random(1000,9999)),
		Parent = safeParent(),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	})
	self.Gui = gui

	local overlay = new("Frame", {
		Parent = gui,
		BackgroundColor3 = Color3.fromRGB(0,0,0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1,1),
		ZIndex = 1
	})
	self.Overlay = overlay

	local scale = new("UIScale", {
		Parent = overlay,
		Scale = config.Scale or 1
	})
	self.ScaleObject = scale

	local shadow = new("ImageLabel", {
		Parent = overlay,
		Name = "Shadow",
		BackgroundTransparency = 1,
		Image = "rbxassetid://6014261993",
		ImageColor3 = Color3.fromRGB(0,0,0),
		ImageTransparency = 0.52,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(49,49,450,450),
		ZIndex = 2
	})

	local main = new("Frame", {
		Parent = overlay,
		Name = "Main",
		AnchorPoint = Vector2.new(0.5,0.5),
		Position = UDim2.fromScale(0.5,0.5),
		BackgroundColor3 = self.Theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 3
	})
	corner(main, 16)
	stroke(main, self.Theme.Surface3, 0.15, 1)
	self.Main = main
	self:RegisterThemeObject(main, "BackgroundColor3", "Background")

	local topbar = new("Frame", {
		Parent = main,
		BackgroundColor3 = self.Theme.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(1,0,0,58),
		ZIndex = 4
	})
	self.Topbar = topbar
	self:RegisterThemeObject(topbar, "BackgroundColor3", "Surface")

	local accentLine = new("Frame", {
		Parent = topbar,
		AnchorPoint = Vector2.new(0,1),
		Position = UDim2.new(0,0,1,0),
		Size = UDim2.new(1,0,0,1),
		BorderSizePixel = 0,
		BackgroundColor3 = self.Theme.Surface3,
		ZIndex = 5
	})
	self:RegisterThemeObject(accentLine, "BackgroundColor3", "Surface3")

	local title = new("TextLabel", {
		Parent = topbar,
		BackgroundTransparency = 1,
		Position = UDim2.new(0,18,0,9),
		Size = UDim2.new(1,-150,0,22),
		Font = Enum.Font.GothamBold,
		Text = self.Name,
		TextColor3 = self.Theme.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5
	})
	self:RegisterThemeObject(title, "TextColor3", "Text")

	local subtitle = new("TextLabel", {
		Parent = topbar,
		BackgroundTransparency = 1,
		Position = UDim2.new(0,18,0,31),
		Size = UDim2.new(1,-150,0,17),
		Font = Enum.Font.Gotham,
		Text = config.Subtitle or "Executor UI Library",
		TextColor3 = self.Theme.SubText,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5
	})
	self:RegisterThemeObject(subtitle, "TextColor3", "SubText")

	local function topButton(text, rightOffset, callback)
		local b = new("TextButton", {
			Parent = topbar,
			AnchorPoint = Vector2.new(1,0.5),
			Position = UDim2.new(1,-rightOffset,0.5,0),
			Size = UDim2.fromOffset(34,34),
			BackgroundColor3 = self.Theme.Surface2,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = text,
			TextColor3 = self.Theme.SubText,
			TextSize = 15,
			Font = Enum.Font.GothamBold,
			ZIndex = 6
		})
		corner(b, 10)
		self:RegisterThemeObject(b, "BackgroundColor3", "Surface2")
		self:RegisterThemeObject(b, "TextColor3", "SubText")
		b.MouseEnter:Connect(function()
			tween(b, .12, {BackgroundColor3 = self.Theme.Surface3, TextColor3 = self.Theme.Text})
		end)
		b.MouseLeave:Connect(function()
			tween(b, .12, {BackgroundColor3 = self.Theme.Surface2, TextColor3 = self.Theme.SubText})
		end)
		b.Activated:Connect(callback)
		return b
	end

	topButton("×", 16, function()
		if config.ConfirmClose == false then
			self:Destroy()
		else
			self:Notify({
				Title = "Close interface?",
				Content = "Press the close button again within 2 seconds.",
				Duration = 2
			})
			if self._closeArmed then
				self:Destroy()
				return
			end
			self._closeArmed = true
			task.delay(2, function()
				if self then self._closeArmed = false end
			end)
		end
	end)

	topButton("–", 58, function()
		self:SetMinimized(not self.Minimized)
	end)

	local body = new("Frame", {
		Parent = main,
		Position = UDim2.new(0,0,0,58),
		Size = UDim2.new(1,0,1,-58),
		BackgroundTransparency = 1,
		ZIndex = 4
	})
	self.Body = body

	local sidebar = new("Frame", {
		Parent = body,
		BackgroundColor3 = self.Theme.Surface,
		BorderSizePixel = 0,
		ZIndex = 4
	})
	self.Sidebar = sidebar
	self:RegisterThemeObject(sidebar, "BackgroundColor3", "Surface")

	local sideList = new("ScrollingFrame", {
		Parent = sidebar,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = self.Theme.Accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 5
	})
	self.SideList = sideList
	self:RegisterThemeObject(sideList, "ScrollBarImageColor3", "Accent")
	padding(sideList, 10, 10, 12, 12)
	list(sideList, Enum.FillDirection.Vertical, 7)

	local content = new("Frame", {
		Parent = body,
		BackgroundTransparency = 1,
		ZIndex = 4
	})
	self.Content = content

	self.NotificationHolder = new("Frame", {
		Parent = gui,
		AnchorPoint = Vector2.new(1,0),
		Position = UDim2.new(1,-16,0,16),
		Size = UDim2.new(0,320,1,-32),
		BackgroundTransparency = 1,
		ZIndex = 50
	})
	list(self.NotificationHolder, Enum.FillDirection.Vertical, 10)

	self.MobileTabButton = new("TextButton", {
		Parent = body,
		BackgroundColor3 = self.Theme.Surface2,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(40,40),
		Position = UDim2.fromOffset(10,10),
		Text = "☰",
		TextColor3 = self.Theme.Text,
		TextSize = 17,
		Font = Enum.Font.GothamBold,
		Visible = false,
		ZIndex = 20,
		AutoButtonColor = false
	})
	corner(self.MobileTabButton, 12)
	self:RegisterThemeObject(self.MobileTabButton, "BackgroundColor3", "Surface2")
	self:RegisterThemeObject(self.MobileTabButton, "TextColor3", "Text")

	self.MobileTabButton.Activated:Connect(function()
		self.Sidebar.Visible = not self.Sidebar.Visible
	end)

	self:MakeDraggable(topbar, main)
	self:UpdateLayout()

	table.insert(self.Connections, workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self:UpdateLayout()
	end))

	if config.ToggleKey then
		table.insert(self.Connections, UIS.InputBegan:Connect(function(input, processed)
			if processed then return end
			if input.KeyCode == config.ToggleKey then
				main.Visible = not main.Visible
				shadow.Visible = main.Visible
			end
		end))
	end

	if config.Theme then
		self:SetTheme(config.Theme, true)
	end

	if config.Intro ~= false then
		main.Size = UDim2.fromOffset(420,260)
		main.BackgroundTransparency = 1
		shadow.ImageTransparency = 1
		task.defer(function()
			self:UpdateLayout(true)
			tween(main, .28, {BackgroundTransparency = 0})
			tween(shadow, .28, {ImageTransparency = 0.52})
		end)
	end

	return self
end

function AstralUI:RegisterThemeObject(obj, property, key)
	table.insert(self.ThemeObjects, {
		Object = obj,
		Property = property,
		Key = key
	})
end

function AstralUI:SetTheme(name, instant)
	local theme = AstralUI.Themes[name]
	if not theme then
		warn("[AstralUI] Unknown theme: " .. tostring(name))
		return false
	end
	self.ThemeName = name
	self.Theme = theme

	for _, item in ipairs(self.ThemeObjects) do
		if item.Object and item.Object.Parent and theme[item.Key] then
			if instant then
				item.Object[item.Property] = theme[item.Key]
			else
				local ok = pcall(function()
					tween(item.Object, .2, {[item.Property] = theme[item.Key]})
				end)
				if not ok then
					item.Object[item.Property] = theme[item.Key]
				end
			end
		end
	end
	return true
end

function AstralUI:UpdateLayout(noTween)
	if not self.Main or not workspace.CurrentCamera then return end
	local viewport = workspace.CurrentCamera.ViewportSize
	local mobile = viewport.X <= self.MobileBreakpoint
	self.IsMobile = mobile

	local width = mobile and math.min(viewport.X - 20, 440) or math.min(viewport.X - 80, 860)
	local height = mobile and math.min(viewport.Y - 70, 560) or math.min(viewport.Y - 110, 590)

	width = math.max(width, 300)
	height = math.max(height, 320)

	local target = UDim2.fromOffset(width, height)
	if noTween then
		self.Main.Size = target
	else
		tween(self.Main, .2, {Size = target})
	end

	self.Main.Position = UDim2.fromScale(.5,.5)
	self.Overlay.Shadow.Size = UDim2.fromOffset(width + 60, height + 60)
	self.Overlay.Shadow.AnchorPoint = Vector2.new(.5,.5)
	self.Overlay.Shadow.Position = UDim2.fromScale(.5,.5)

	if mobile then
		self.Sidebar.Size = UDim2.fromOffset(math.min(width - 30, 250), height - 58)
		self.Sidebar.Position = UDim2.fromOffset(0,0)
		self.Sidebar.Visible = false
		self.Sidebar.ZIndex = 30
		self.SideList.Size = UDim2.fromScale(1,1)

		self.Content.Position = UDim2.fromOffset(0,0)
		self.Content.Size = UDim2.fromScale(1,1)
		self.MobileTabButton.Visible = true
	else
		self.Sidebar.Visible = true
		self.Sidebar.Position = UDim2.fromOffset(0,0)
		self.Sidebar.Size = UDim2.new(0,190,1,0)
		self.SideList.Size = UDim2.fromScale(1,1)
		self.Content.Position = UDim2.fromOffset(190,0)
		self.Content.Size = UDim2.new(1,-190,1,0)
		self.MobileTabButton.Visible = false
	end
end

function AstralUI:SetScale(value)
	self.ScaleObject.Scale = clamp(tonumber(value) or 1, 0.72, 1.25)
end

function AstralUI:MakeDraggable(handle, target)
	local dragging = false
	local dragStart
	local startPos
	local activeInput

	local function update(input)
		if not dragging then return end
		local delta = input.Position - dragStart
		target.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end

	table.insert(self.Connections, handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = target.Position
			activeInput = input

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					activeInput = nil
				end
			end)
		end
	end))

	table.insert(self.Connections, handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
			activeInput = input
		end
	end))

	table.insert(self.Connections, UIS.InputChanged:Connect(function(input)
		if dragging and input == activeInput then
			update(input)
		end
	end))
end

function AstralUI:SetMinimized(state)
	self.Minimized = state
	if state then
		tween(self.Main, .22, {Size = UDim2.fromOffset(self.Main.AbsoluteSize.X, 58)})
		self.Body.Visible = false
	else
		self.Body.Visible = true
		self:UpdateLayout()
	end
end

function AstralUI:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	disconnectAll(self.Connections)
	if self.Gui then
		tween(self.Main, .18, {BackgroundTransparency = 1})
		task.delay(.2, function()
			if self.Gui then self.Gui:Destroy() end
		end)
	end
end

function AstralUI:Notify(data)
	data = data or {}
	local theme = self.Theme
	local holder = self.NotificationHolder
	if not holder then return end

	local frame = new("Frame", {
		Parent = holder,
		BackgroundColor3 = theme.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(1,0,0,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0,
		ZIndex = 51
	})
	corner(frame, 14)
	stroke(frame, theme.Surface3, 0.1, 1)
	padding(frame, 14, 14, 12, 12)
	self:RegisterThemeObject(frame, "BackgroundColor3", "Surface")

	local contentList = list(frame, Enum.FillDirection.Vertical, 5)

	local title = new("TextLabel", {
		Parent = frame,
		BackgroundTransparency = 1,
		Size = UDim2.new(1,0,0,20),
		Font = Enum.Font.GothamBold,
		Text = data.Title or "AstralUI",
		TextColor3 = theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		ZIndex = 52
	})
	self:RegisterThemeObject(title, "TextColor3", "Text")

	local body = new("TextLabel", {
		Parent = frame,
		BackgroundTransparency = 1,
		Size = UDim2.new(1,0,0,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Enum.Font.Gotham,
		Text = data.Content or "",
		TextColor3 = theme.SubText,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		ZIndex = 52
	})
	self:RegisterThemeObject(body, "TextColor3", "SubText")

	local bar = new("Frame", {
		Parent = frame,
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(1,0,0,2),
		ZIndex = 52
	})
	corner(bar, 2)
	self:RegisterThemeObject(bar, "BackgroundColor3", "Accent")

	frame.Position = UDim2.fromOffset(360,0)
	tween(frame, .28, {Position = UDim2.fromOffset(0,0)})

	local duration = tonumber(data.Duration) or 4
	task.spawn(function()
		bar.Size = UDim2.new(1,0,0,2)
		tween(bar, duration, {Size = UDim2.new(0,0,0,2)}, Enum.EasingStyle.Linear)
		task.wait(duration)
		if frame and frame.Parent then
			tween(frame, .22, {
				Position = UDim2.fromOffset(360,0),
				BackgroundTransparency = 1
			})
			task.wait(.24)
			if frame then frame:Destroy() end
		end
	end)
end

function AstralUI:CreateTab(name, icon)
	local tab = {}
	tab.Window = self
	tab.Name = name or "Tab"

	local btn = new("TextButton", {
		Parent = self.SideList,
		BackgroundColor3 = self.Theme.Surface2,
		BorderSizePixel = 0,
		Size = UDim2.new(1,0,0,42),
		AutoButtonColor = false,
		Text = "",
		ZIndex = 7
	})
	corner(btn, 11)
	self:RegisterThemeObject(btn, "BackgroundColor3", "Surface2")

	local indicator = new("Frame", {
		Parent = btn,
		AnchorPoint = Vector2.new(0,.5),
		Position = UDim2.new(0,0,.5,0),
		Size = UDim2.fromOffset(3,0),
		BackgroundColor3 = self.Theme.Accent,
		BorderSizePixel = 0,
		ZIndex = 8
	})
	corner(indicator, 3)
	self:RegisterThemeObject(indicator, "BackgroundColor3", "Accent")

	local txt = new("TextLabel", {
		Parent = btn,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12,0),
		Size = UDim2.new(1,-20,1,0),
		Font = Enum.Font.GothamMedium,
		Text = (icon and (icon .. "  ") or "") .. tab.Name,
		TextColor3 = self.Theme.SubText,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 8
	})
	self:RegisterThemeObject(txt, "TextColor3", "SubText")

	local page = new("ScrollingFrame", {
		Parent = self.Content,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1,1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = self.Theme.Accent,
		Visible = false,
		ZIndex = 5
	})
	self:RegisterThemeObject(page, "ScrollBarImageColor3", "Accent")
	padding(page, 16, 16, 16, 16)
	list(page, Enum.FillDirection.Vertical, 12)

	tab.Button = btn
	tab.Indicator = indicator
	tab.Text = txt
	tab.Page = page

	function tab:Select()
		for _, other in ipairs(self.Window.Tabs) do
			local active = other == self
			other.Page.Visible = active
			if active then
				tween(other.Button, .15, {BackgroundColor3 = self.Window.Theme.Surface3})
				tween(other.Text, .15, {TextColor3 = self.Window.Theme.Text})
				tween(other.Indicator, .18, {Size = UDim2.fromOffset(3,22)})
			else
				tween(other.Button, .15, {BackgroundColor3 = self.Window.Theme.Surface2})
				tween(other.Text, .15, {TextColor3 = self.Window.Theme.SubText})
				tween(other.Indicator, .18, {Size = UDim2.fromOffset(3,0)})
			end
		end
		self.Window.ActiveTab = self
		if self.Window.IsMobile then
			self.Window.Sidebar.Visible = false
		end
	end

	btn.Activated:Connect(function()
		tab:Select()
	end)

	function tab:CreateSection(sectionName)
		return self.Window:_CreateSection(self.Page, sectionName)
	end

	table.insert(self.Tabs, tab)
	if not self.ActiveTab then
		tab:Select()
	end
	return tab
end

function AstralUI:_CreateSection(parent, sectionName)
	local window = self
	local section = {}
	section.Window = self

	local frame = new("Frame", {
		Parent = parent,
		BackgroundColor3 = window.Theme.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(1,0,0,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 6
	})
	corner(frame, 14)
	stroke(frame, window.Theme.Surface3, 0.22, 1)
	padding(frame, 12, 12, 12, 12)
	list(frame, Enum.FillDirection.Vertical, 8)
	window:RegisterThemeObject(frame, "BackgroundColor3", "Surface")

	local title = new("TextLabel", {
		Parent = frame,
		BackgroundTransparency = 1,
		Size = UDim2.new(1,0,0,20),
		Font = Enum.Font.GothamBold,
		Text = sectionName or "Section",
		TextColor3 = window.Theme.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7
	})
	window:RegisterThemeObject(title, "TextColor3", "Text")

	local holder = new("Frame", {
		Parent = frame,
		BackgroundTransparency = 1,
		Size = UDim2.new(1,0,0,0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 7
	})
	local layout = list(holder, Enum.FillDirection.Vertical, 8)

	section.Frame = frame
	section.Holder = holder

	local function controlBase(height)
		local control = new("Frame", {
			Parent = holder,
			BackgroundColor3 = window.Theme.Surface2,
			BorderSizePixel = 0,
			Size = UDim2.new(1,0,0,height or 44),
			ZIndex = 8
		})
		corner(control, 11)
		window:RegisterThemeObject(control, "BackgroundColor3", "Surface2")
		return control
	end

	local function labelText(control, nameText, descText, rightPadding)
		local name = new("TextLabel", {
			Parent = control,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12,6),
			Size = UDim2.new(1,-(rightPadding or 20),0,17),
			Font = Enum.Font.GothamMedium,
			Text = nameText or "Control",
			TextColor3 = window.Theme.Text,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 9
		})
		window:RegisterThemeObject(name, "TextColor3", "Text")

		if descText and descText ~= "" then
			local desc = new("TextLabel", {
				Parent = control,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(12,23),
				Size = UDim2.new(1,-(rightPadding or 20),0,15),
				Font = Enum.Font.Gotham,
				Text = descText,
				TextColor3 = window.Theme.SubText,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 9
			})
			window:RegisterThemeObject(desc, "TextColor3", "SubText")
		end
	end

	function section:AddLabel(text)
		local control = controlBase(38)
		local lbl = new("TextLabel", {
			Parent = control,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12,0),
			Size = UDim2.new(1,-24,1,0),
			Font = Enum.Font.Gotham,
			Text = text or "Label",
			TextColor3 = self.Window.Theme.SubText,
			TextSize = 11,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 9
		})
		self.Window:RegisterThemeObject(lbl, "TextColor3", "SubText")

		local api = {}
		function api:Set(v) lbl.Text = tostring(v) end
		return api
	end

	function section:AddButton(data)
		data = type(data) == "table" and data or {Name = tostring(data)}
		local control = controlBase(data.Description and 48 or 42)
		labelText(control, data.Name or "Button", data.Description, 54)

		local arrow = new("TextLabel", {
			Parent = control,
			AnchorPoint = Vector2.new(1,.5),
			Position = UDim2.new(1,-12,.5,0),
			Size = UDim2.fromOffset(24,24),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = "›",
			TextColor3 = window.Theme.SubText,
			TextSize = 20,
			ZIndex = 9
		})
		window:RegisterThemeObject(arrow, "TextColor3", "SubText")

		local hit = new("TextButton", {
			Parent = control,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1,1),
			Text = "",
			ZIndex = 10
		})

		hit.Activated:Connect(function()
			tween(control, .08, {BackgroundColor3 = window.Theme.Surface3})
			task.delay(.1, function()
				if control and control.Parent then
					tween(control, .12, {BackgroundColor3 = window.Theme.Surface2})
				end
			end)
			if data.Callback then
				task.spawn(function()
					local ok, err = pcall(data.Callback)
					if not ok then warn("[AstralUI Button] " .. tostring(err)) end
				end)
			end
		end)

		return {
			SetName = function(_, v)
				for _, child in ipairs(control:GetChildren()) do
					if child:IsA("TextLabel") and child ~= arrow then
						child.Text = tostring(v)
						break
					end
				end
			end
		}
	end

	function section:AddToggle(data)
		data = data or {}
		local state = data.Default == true
		local control = controlBase(data.Description and 50 or 44)
		labelText(control, data.Name or "Toggle", data.Description, 68)

		local pill = new("Frame", {
			Parent = control,
			AnchorPoint = Vector2.new(1,.5),
			Position = UDim2.new(1,-12,.5,0),
			Size = UDim2.fromOffset(44,24),
			BackgroundColor3 = state and window.Theme.Accent or window.Theme.Surface3,
			BorderSizePixel = 0,
			ZIndex = 9
		})
		corner(pill, 12)
		window:RegisterThemeObject(pill, "BackgroundColor3", state and "Accent" or "Surface3")

		local knob = new("Frame", {
			Parent = pill,
			AnchorPoint = Vector2.new(.5,.5),
			Position = state and UDim2.new(1,-12,.5,0) or UDim2.new(0,12,.5,0),
			Size = UDim2.fromOffset(16,16),
			BackgroundColor3 = window.Theme.Text,
			BorderSizePixel = 0,
			ZIndex = 10
		})
		corner(knob, 8)
		window:RegisterThemeObject(knob, "BackgroundColor3", "Text")

		local hit = new("TextButton", {
			Parent = control,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1,1),
			Text = "",
			ZIndex = 11
		})

		local api = {}
		local function set(v, fire)
			state = v == true
			pill.BackgroundColor3 = state and window.Theme.Accent or window.Theme.Surface3
			tween(knob, .16, {
				Position = state and UDim2.new(1,-12,.5,0) or UDim2.new(0,12,.5,0)
			})
			if fire and data.Callback then
				task.spawn(function()
					local ok, err = pcall(data.Callback, state)
					if not ok then warn("[AstralUI Toggle] " .. tostring(err)) end
				end)
			end
		end

		hit.Activated:Connect(function()
			set(not state, true)
		end)

		function api:Set(v) set(v, true) end
		function api:Get() return state end
		return api
	end

	function section:AddSlider(data)
		data = data or {}
		local min = tonumber(data.Min) or 0
		local max = tonumber(data.Max) or 100
		local step = tonumber(data.Step) or 1
		local value = clamp(tonumber(data.Default) or min, min, max)

		local control = controlBase(64)
		labelText(control, data.Name or "Slider", data.Description, 62)

		local valueLabel = new("TextLabel", {
			Parent = control,
			AnchorPoint = Vector2.new(1,0),
			Position = UDim2.new(1,-12,0,7),
			Size = UDim2.fromOffset(50,16),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = tostring(value),
			TextColor3 = window.Theme.Accent2,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 9
		})
		window:RegisterThemeObject(valueLabel, "TextColor3", "Accent2")

		local track = new("Frame", {
			Parent = control,
			Position = UDim2.new(0,12,1,-17),
			Size = UDim2.new(1,-24,0,5),
			BackgroundColor3 = window.Theme.Surface3,
			BorderSizePixel = 0,
			ZIndex = 9
		})
		corner(track, 3)
		window:RegisterThemeObject(track, "BackgroundColor3", "Surface3")

		local fill = new("Frame", {
			Parent = track,
			Size = UDim2.new((value-min)/(max-min),0,1,0),
			BackgroundColor3 = window.Theme.Accent,
			BorderSizePixel = 0,
			ZIndex = 10
		})
		corner(fill, 3)
		window:RegisterThemeObject(fill, "BackgroundColor3", "Accent")

		local knob = new("Frame", {
			Parent = track,
			AnchorPoint = Vector2.new(.5,.5),
			Position = UDim2.new((value-min)/(max-min),0,.5,0),
			Size = UDim2.fromOffset(14,14),
			BackgroundColor3 = window.Theme.Text,
			BorderSizePixel = 0,
			ZIndex = 11
		})
		corner(knob, 7)
		window:RegisterThemeObject(knob, "BackgroundColor3", "Text")

		local dragging = false

		local api = {}
		local function setValue(v, fire)
			v = clamp(v, min, max)
			v = math.floor((v / step) + 0.5) * step
			v = clamp(v, min, max)
			value = v
			local alpha = (value - min) / (max - min)
			valueLabel.Text = tostring(value)
			tween(fill, .08, {Size = UDim2.new(alpha,0,1,0)}, Enum.EasingStyle.Linear)
			tween(knob, .08, {Position = UDim2.new(alpha,0,.5,0)}, Enum.EasingStyle.Linear)
			if fire and data.Callback then
				task.spawn(function()
					local ok, err = pcall(data.Callback, value)
					if not ok then warn("[AstralUI Slider] " .. tostring(err)) end
				end)
			end
		end

		local function updateFromPosition(x)
			local alpha = clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
			setValue(min + (max-min) * alpha, true)
		end

		track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				updateFromPosition(input.Position.X)
			end
		end)

		UIS.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
				updateFromPosition(input.Position.X)
			end
		end)

		UIS.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)

		function api:Set(v) setValue(tonumber(v) or value, true) end
		function api:Get() return value end
		return api
	end

	function section:AddInput(data)
		data = data or {}
		local control = controlBase(58)
		labelText(control, data.Name or "Input", data.Description, 20)

		local box = new("TextBox", {
			Parent = control,
			Position = UDim2.new(0,10,1,-30),
			Size = UDim2.new(1,-20,0,23),
			BackgroundColor3 = window.Theme.Surface3,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Font = Enum.Font.Gotham,
			PlaceholderText = data.Placeholder or "Type here...",
			PlaceholderColor3 = window.Theme.Muted,
			Text = data.Default or "",
			TextColor3 = window.Theme.Text,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 10
		})
		corner(box, 8)
		padding(box, 8, 8, 0, 0)
		window:RegisterThemeObject(box, "BackgroundColor3", "Surface3")
		window:RegisterThemeObject(box, "TextColor3", "Text")
		window:RegisterThemeObject(box, "PlaceholderColor3", "Muted")

		box.FocusLost:Connect(function(enterPressed)
			if data.Callback then
				task.spawn(function()
					local ok, err = pcall(data.Callback, box.Text, enterPressed)
					if not ok then warn("[AstralUI Input] " .. tostring(err)) end
				end)
			end
		end)

		return {
			Set = function(_, v) box.Text = tostring(v) end,
			Get = function() return box.Text end
		}
	end

	function section:AddDropdown(data)
		data = data or {}
		local options = data.Options or {}
		local current = data.Default
		local opened = false

		local wrapper = new("Frame", {
			Parent = holder,
			BackgroundTransparency = 1,
			Size = UDim2.new(1,0,0,44),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 8
		})

		local control = new("Frame", {
			Parent = wrapper,
			BackgroundColor3 = window.Theme.Surface2,
			BorderSizePixel = 0,
			Size = UDim2.new(1,0,0,44),
			ZIndex = 9
		})
		corner(control, 11)
		window:RegisterThemeObject(control, "BackgroundColor3", "Surface2")
		labelText(control, data.Name or "Dropdown", nil, 150)

		local selected = new("TextLabel", {
			Parent = control,
			AnchorPoint = Vector2.new(1,.5),
			Position = UDim2.new(1,-36,.5,0),
			Size = UDim2.fromOffset(110,22),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = current and tostring(current) or "Select",
			TextColor3 = current and window.Theme.Text or window.Theme.SubText,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 10
		})
		window:RegisterThemeObject(selected, "TextColor3", current and "Text" or "SubText")

		local arrow = new("TextLabel", {
			Parent = control,
			AnchorPoint = Vector2.new(1,.5),
			Position = UDim2.new(1,-10,.5,0),
			Size = UDim2.fromOffset(18,18),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = "⌄",
			TextColor3 = window.Theme.SubText,
			TextSize = 14,
			ZIndex = 10
		})
		window:RegisterThemeObject(arrow, "TextColor3", "SubText")

		local optionsFrame = new("Frame", {
			Parent = wrapper,
			Position = UDim2.fromOffset(0,50),
			Size = UDim2.new(1,0,0,0),
			AutomaticSize = Enum.AutomaticSize.None,
			BackgroundColor3 = window.Theme.Surface2,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Visible = false,
			ZIndex = 12
		})
		corner(optionsFrame, 10)
		padding(optionsFrame, 7,7,7,7)
		window:RegisterThemeObject(optionsFrame, "BackgroundColor3", "Surface2")

		local optionsList = list(optionsFrame, Enum.FillDirection.Vertical, 5)

		local hit = new("TextButton", {
			Parent = control,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1,1),
			Text = "",
			ZIndex = 11
		})

		local api = {}

		local function close()
			opened = false
			tween(arrow, .15, {Rotation = 0})
			tween(optionsFrame, .16, {Size = UDim2.new(1,0,0,0)})
			task.delay(.17, function()
				if optionsFrame then optionsFrame.Visible = false end
			end)
		end

		local function open()
			opened = true
			optionsFrame.Visible = true
			local h = math.min(#options * 33 + 14, 180)
			tween(arrow, .15, {Rotation = 180})
			tween(optionsFrame, .16, {Size = UDim2.new(1,0,0,h)})
		end

		local function choose(v, fire)
			current = v
			selected.Text = tostring(v)
			selected.TextColor3 = window.Theme.Text
			close()
			if fire and data.Callback then
				task.spawn(function()
					local ok, err = pcall(data.Callback, v)
					if not ok then warn("[AstralUI Dropdown] " .. tostring(err)) end
				end)
			end
		end

		local function rebuild(newOptions)
			options = newOptions or {}
			for _, child in ipairs(optionsFrame:GetChildren()) do
				if child:IsA("TextButton") then
					child:Destroy()
				end
			end
			for _, opt in ipairs(options) do
				local ob = new("TextButton", {
					Parent = optionsFrame,
					BackgroundColor3 = window.Theme.Surface3,
					BorderSizePixel = 0,
					Size = UDim2.new(1,0,0,28),
					AutoButtonColor = false,
					Font = Enum.Font.Gotham,
					Text = tostring(opt),
					TextColor3 = window.Theme.Text,
					TextSize = 10,
					ZIndex = 13
				})
				corner(ob, 8)
				window:RegisterThemeObject(ob, "BackgroundColor3", "Surface3")
				window:RegisterThemeObject(ob, "TextColor3", "Text")
				ob.Activated:Connect(function()
					choose(opt, true)
				end)
			end
		end

		rebuild(options)
		hit.Activated:Connect(function()
			if opened then close() else open() end
		end)

		function api:Set(v) choose(v, true) end
		function api:Get() return current end
		function api:Refresh(newOptions)
			rebuild(newOptions)
			current = nil
			selected.Text = "Select"
		end

		return api
	end

	function section:AddThemeSelector(data)
		data = data or {}
		local names = {}
		for name in pairs(AstralUI.Themes) do
			table.insert(names, name)
		end
		table.sort(names)

		return self:AddDropdown({
			Name = data.Name or "Theme",
			Options = names,
			Default = self.Window.ThemeName,
			Callback = function(themeName)
				self.Window:SetTheme(themeName)
				if data.Callback then data.Callback(themeName) end
			end
		})
	end

	return section
end

return AstralUI
