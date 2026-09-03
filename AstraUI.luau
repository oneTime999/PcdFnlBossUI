--[[fitagem leve + lock.Active = false
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

    unlock.MouseButton1Click:Connect(validate)
    keyInput.FocusLost:Connect(function(enterPressed)
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

    tabButton.MouseButton1Click:Connect(function()
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

    action.MouseButton1Click:Connect(function()
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

    function object:Set(newValue)
        set(newValue, true)
    end

    function object:Get()
        return value
    end

    function object:_sync(newValue)
        set(newValue, true)
    end

    switch.MouseButton1Click:Connect(function()
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

    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromInput(input)
        end
    end)

    bar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            setFromInput(input)
        end
    end)

    function object:Set(newValue)
        set(newValue, true)
    end

    function object:Get()
        return value
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

    input.FocusLost:Connect(function(enterPressed)
        if data.CallbackOnEnter and not enterPressed then
            return
        end
        commit(input.Text, true)
    end)

    function object:Set(newValue)
        input.Text = tostring(newValue or "")
        commit(input.Text, true)
    end

    function object:Get()
        return data.Numeric and tonumber(input.Text) or input.Text
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
    local object = {}
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

            item.MouseButton1Click:Connect(function()
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

    header.MouseButton1Click:Connect(function()
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

    keyButton.MouseButton1Click:Connect(function()
        listening = true
        keyButton.Text = "Press a key..."
    end)

    UserInputService.InputBegan:Connect(function(input, processed)
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

    function object:Set(newKey)
        current = normalizeKeyCode(newKey)
        keyButton.Text = current.Name

        if flag then
            self.Window.Flags[flag] = current
        end

        safeCall(data.Changed, current)
    end

    function object:Get()
        return current
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

return AstraUI.new()
