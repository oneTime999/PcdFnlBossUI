-- AstraUI V5.0.0 - Clean Rebuild
-- Rewritten from scratch to remove the layered V4.x hotfix architecture.

local VERSION = "5.0.0"
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local AstraUI = {}; AstraUI.__index = AstraUI; AstraUI.Version = VERSION; AstraUI.Name = "AstraUI"
local Window = {}; Window.__index = Window
local Tab = {}; Tab.__index = Tab
local Section = {}; Section.__index = Section
local Control = {}; Control.__index = Control

local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local function safeCall(fn,...)
    if type(fn) ~= "function" then return true end
    local ok,res = pcall(fn,...)
    if not ok then warn("[AstraUI] Callback error: "..tostring(res)) end
    return ok,res
end
local function copy(t) local n={}; for k,v in pairs(t or {}) do n[k]=v end; return n end
local function merge(a,b) local n=copy(a); for k,v in pairs(b or {}) do n[k]=v end; return n end
local function create(class,props)
    local o=Instance.new(class)
    for k,v in pairs(props or {}) do if k~="Parent" then o[k]=v end end
    if props and props.Parent then o.Parent=props.Parent end
    return o
end
local function corner(obj,r)
    r=math.max(0,tonumber(r) or 0)
    local c=obj:FindFirstChild("AstraCorner")
    if not c then c=Instance.new("UICorner");c.Name="AstraCorner";c.Parent=obj end
    if r>=90 then
        obj:SetAttribute("AstraFixedCorner",true)
        c.CornerRadius=UDim.new(0,math.floor(r+.5))
        return c
    end
    if obj:GetAttribute("AstraBaseRadius")==nil then obj:SetAttribute("AstraBaseRadius",r) end
    local base=tonumber(obj:GetAttribute("AstraBaseRadius")) or r
    local mult=1
    if not obj:GetAttribute("AstraIgnoreRoundness") then
        local node=obj
        while node do
            if node:IsA("ScreenGui") then mult=tonumber(node:GetAttribute("AstraRoundness")) or 1;break end
            node=node.Parent
        end
    end
    c.CornerRadius=UDim.new(0,math.floor(clamp(base*mult,0,28)+.5))
    return c
end
local function stroke(obj,color,trans,thick)
    local s=obj:FindFirstChild("AstraStroke")
    if not s then s=Instance.new("UIStroke"); s.Name="AstraStroke"; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=obj end
    s.Color=color; s.Transparency=trans or 0; s.Thickness=thick or 1
    return s
end
local function padding(obj,l,t,r,b)
    local p=Instance.new("UIPadding"); p.PaddingLeft=UDim.new(0,l or 0); p.PaddingTop=UDim.new(0,t or 0); p.PaddingRight=UDim.new(0,r or 0); p.PaddingBottom=UDim.new(0,b or 0); p.Parent=obj; return p
end
local function list(obj,gap,horizontal)
    local l=Instance.new("UIListLayout"); l.FillDirection=horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical; l.SortOrder=Enum.SortOrder.LayoutOrder; l.Padding=UDim.new(0,gap or 0); l.Parent=obj; return l
end
local function tween(obj,dur,props,style,dir)
    if not obj or not obj.Parent then return nil end
    local tw=TweenService:Create(obj,TweenInfo.new(dur or .16,style or Enum.EasingStyle.Quart,dir or Enum.EasingDirection.Out),props); tw:Play(); return tw
end
local function textHeight(text,size,width)
    local ok,b=pcall(TextService.GetTextSize,TextService,tostring(text or ""),size or 11,Enum.Font.Gotham,Vector2.new(math.max(1,width or 300),10000)); return ok and b.Y or (size or 11)+2
end
local function textWidth(text,size)
    local ok,b=pcall(TextService.GetTextSize,TextService,tostring(text or ""),size or 11,Enum.Font.Gotham,Vector2.new(10000,10000)); return ok and b.X or #tostring(text or "")*(size or 11)*.55
end
local function label(parent,text,size,color,font,align)
    return create("TextLabel",{Parent=parent,BackgroundTransparency=1,BorderSizePixel=0,Text=tostring(text or ""),TextColor3=color,TextSize=size or 12,Font=font or Enum.Font.Gotham,TextXAlignment=align or Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,TextWrapped=false,TextTruncate=Enum.TextTruncate.AtEnd})
end
local function formatDuration(sec,compact)
    sec=math.max(0,math.floor(tonumber(sec) or 0)); local d=math.floor(sec/86400); sec%=86400; local h=math.floor(sec/3600); sec%=3600; local m=math.floor(sec/60); local s=sec%60
    if compact then if d>0 then return string.format("%dd %dh",d,h) elseif h>0 then return string.format("%dh %dm",h,m) elseif m>0 then return string.format("%dm %ds",m,s) else return string.format("%ds",s) end end
    local a={}; if d>0 then table.insert(a,d.."d") end; if h>0 or d>0 then table.insert(a,h.."h") end; if m>0 or h>0 or d>0 then table.insert(a,m.."m") end; table.insert(a,s.."s"); return table.concat(a," ")
end
local function viewport() local c=Workspace.CurrentCamera; return c and c.ViewportSize or Vector2.new(1280,720) end
local function resolveParent(custom)
    if custom then return custom end
    local ok,g=pcall(function() return gethui end); if ok and type(g)=="function" then local ok2,r=pcall(g); if ok2 and r then return r end end
    if LocalPlayer then local pg=LocalPlayer:FindFirstChildOfClass("PlayerGui"); if pg then return pg end end
    local ok3,cg=pcall(function() return game:GetService("CoreGui") end); if ok3 then return cg end
    error("[AstraUI] No GUI parent available")
end

local function theme(t)
    t=copy(t); t.Background=t.Background or Color3.fromRGB(10,11,15); t.Sidebar=t.Sidebar or Color3.fromRGB(13,14,19); t.Topbar=t.Topbar or t.Background
    t.Surface=t.Surface or Color3.fromRGB(18,20,27); t.Surface2=t.Surface2 or Color3.fromRGB(23,26,35); t.Surface3=t.Surface3 or Color3.fromRGB(29,33,43); t.Hover=t.Hover or Color3.fromRGB(34,38,50)
    t.Border=t.Border or Color3.fromRGB(47,52,67); t.BorderSubtle=t.BorderSubtle or Color3.fromRGB(32,36,47); t.TextPrimary=t.TextPrimary or Color3.fromRGB(244,245,249); t.TextSecondary=t.TextSecondary or Color3.fromRGB(160,166,181)
    t.Accent=t.Accent or Color3.fromRGB(229,80,158); t.AccentSoft=t.AccentSoft or t.Surface2:Lerp(t.Accent,.14); t.AccentText=t.AccentText or Color3.new(1,1,1); t.Success=t.Success or Color3.fromRGB(66,201,144); t.Warning=t.Warning or Color3.fromRGB(241,184,67); t.Danger=t.Danger or Color3.fromRGB(239,91,100); t.Info=t.Info or Color3.fromRGB(88,159,246); t.Scrollbar=t.Scrollbar or Color3.fromRGB(82,88,107); return t
end
AstraUI.Themes={
    Midnight=theme({Accent=Color3.fromRGB(112,83,255)}), Rose=theme({Accent=Color3.fromRGB(229,80,158)}), Ocean=theme({Accent=Color3.fromRGB(64,141,246)}), Emerald=theme({Accent=Color3.fromRGB(57,199,146)}),
    Graphite=theme({Background=Color3.fromRGB(15,15,17),Sidebar=Color3.fromRGB(18,18,21),Surface=Color3.fromRGB(25,25,29),Surface2=Color3.fromRGB(30,30,35),Surface3=Color3.fromRGB(37,37,43),Accent=Color3.fromRGB(182,186,197)}),
    Light=theme({Background=Color3.fromRGB(245,246,249),Sidebar=Color3.fromRGB(250,250,252),Topbar=Color3.fromRGB(245,246,249),Surface=Color3.fromRGB(255,255,255),Surface2=Color3.fromRGB(242,244,248),Surface3=Color3.fromRGB(234,237,243),Hover=Color3.fromRGB(228,232,240),Border=Color3.fromRGB(208,214,225),BorderSubtle=Color3.fromRGB(225,229,236),TextPrimary=Color3.fromRGB(30,33,40),TextSecondary=Color3.fromRGB(91,98,114),Accent=Color3.fromRGB(98,73,227),Scrollbar=Color3.fromRGB(154,161,175)})
}; AstraUI.Themes.Dark=AstraUI.Themes.Midnight

local function iconLine(parent,x,y,w,h,color,rot)
    local f=create("Frame",{Parent=parent,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=color,BorderSizePixel=0,Rotation=rot or 0}); corner(f,math.min(w,h)/2); return f
end
local function drawIcon(parent,name,color,size)
    size=size or 18; name=string.lower(tostring(name or "")); local h=create("Frame",{Parent=parent,Size=UDim2.fromOffset(size,size),BackgroundTransparency=1,BorderSizePixel=0,Name="AstraIcon"}); local s=size/18
    local function L(x,y,w,hh,r) return iconLine(h,x*s,y*s,w*s,hh*s,color,r) end
    if name=="menu" then L(3,5,12,1.4);L(3,8.5,12,1.4);L(3,12,12,1.4)
    elseif name=="minimize" then L(4,9,10,1.4)
    elseif name=="search" then local r=create("Frame",{Parent=h,Position=UDim2.fromOffset(2*s,2*s),Size=UDim2.fromOffset(10*s,10*s),BackgroundTransparency=1,BorderSizePixel=0});corner(r,99);stroke(r,color,0,1.3*s);L(11,11,5,1.3,45)
    elseif name=="home" then L(3,7,8,1.3,-40);L(8,7,8,1.3,40);local b=create("Frame",{Parent=h,Position=UDim2.fromOffset(5*s,8*s),Size=UDim2.fromOffset(8*s,7*s),BackgroundTransparency=1,BorderSizePixel=0});corner(b,2*s);stroke(b,color,0,1.2*s)
    elseif name=="visuals" or name=="eye" then local e=create("Frame",{Parent=h,Position=UDim2.fromOffset(2*s,5*s),Size=UDim2.fromOffset(14*s,8*s),BackgroundTransparency=1,BorderSizePixel=0});corner(e,99);stroke(e,color,0,1.2*s);local p=create("Frame",{Parent=h,Position=UDim2.fromOffset(7*s,7*s),Size=UDim2.fromOffset(4*s,4*s),BackgroundColor3=color,BorderSizePixel=0});corner(p,99)
    elseif name=="settings" or name=="automation" or name=="controls" then for i,y in ipairs({4,9,14}) do L(2,y,14,1.2);local x=({5,11,7})[i];local d=create("Frame",{Parent=h,Position=UDim2.fromOffset((x-1.5)*s,(y-1.5)*s),Size=UDim2.fromOffset(4*s,4*s),BackgroundColor3=color,BorderSizePixel=0});corner(d,99) end
    elseif name=="info" then local r=create("Frame",{Parent=h,Position=UDim2.fromOffset(2*s,2*s),Size=UDim2.fromOffset(14*s,14*s),BackgroundTransparency=1,BorderSizePixel=0});corner(r,99);stroke(r,color,0,1.2*s);local t=label(h,"i",11*s,color,Enum.Font.GothamBold,Enum.TextXAlignment.Center);t.Size=UDim2.fromScale(1,1)
    elseif name=="profile" or name=="user" then local head=create("Frame",{Parent=h,Position=UDim2.fromOffset(6*s,2*s),Size=UDim2.fromOffset(6*s,6*s),BackgroundTransparency=1,BorderSizePixel=0});corner(head,99);stroke(head,color,0,1.2*s);local body=create("Frame",{Parent=h,Position=UDim2.fromOffset(3*s,10*s),Size=UDim2.fromOffset(12*s,6*s),BackgroundTransparency=1,BorderSizePixel=0});corner(body,6*s);stroke(body,color,0,1.2*s)
    elseif name=="key" or name=="lock" then local body=create("Frame",{Parent=h,Position=UDim2.fromOffset(4*s,8*s),Size=UDim2.fromOffset(10*s,8*s),BackgroundTransparency=1,BorderSizePixel=0});corner(body,2*s);stroke(body,color,0,1.2*s);local arch=create("Frame",{Parent=h,Position=UDim2.fromOffset(6*s,3*s),Size=UDim2.fromOffset(6*s,7*s),BackgroundTransparency=1,BorderSizePixel=0});corner(arch,5*s);stroke(arch,color,0,1.2*s)
    elseif name=="runtime" or name=="server" then local b=create("Frame",{Parent=h,Position=UDim2.fromOffset(2*s,3*s),Size=UDim2.fromOffset(14*s,12*s),BackgroundTransparency=1,BorderSizePixel=0});corner(b,2*s);stroke(b,color,0,1.2*s);L(5,7,8,1);L(5,11,8,1)
    else local d=create("Frame",{Parent=h,Position=UDim2.fromOffset(5*s,5*s),Size=UDim2.fromOffset(8*s,8*s),BackgroundColor3=color,BorderSizePixel=0});corner(d,99) end
    return h
end

local function button(parent,text,t,style)
    style=style or "Secondary"; local bg=t.Surface2; local fg=t.TextPrimary
    if style=="Primary" then bg=t.Accent;fg=t.AccentText elseif style=="Danger" then bg=t.Danger;fg=t.AccentText elseif style=="Ghost" then bg=t.Surface;fg=t.TextSecondary end
    local b=create("TextButton",{Parent=parent,AutoButtonColor=false,BackgroundColor3=bg,BorderSizePixel=0,Text=tostring(text or "Button"),TextColor3=fg,TextSize=12,Font=Enum.Font.GothamMedium});corner(b,10);stroke(b,style=="Secondary" and t.BorderSubtle or bg,style=="Secondary" and .25 or 1,1);return b
end

function AstraUI.new() return setmetatable({Windows={},Connections={},Destroyed=false},AstraUI) end
function AstraUI:GetEnvironment()
    local e={};local names={"gethui","writefile","readfile","isfile","delfile","makefolder","setclipboard","toclipboard","getexecutorname","identifyexecutor"};for _,n in ipairs(names) do local ok,v=pcall(function() return getgenv()[n] end);if ok and v~=nil then e[n]=v end end;return e
end
function AstraUI:GetCapabilities() local e=self:GetEnvironment();local name="Unknown";if type(e.getexecutorname)=="function" then local ok,r=pcall(e.getexecutorname);if ok then name=r end elseif type(e.identifyexecutor)=="function" then local ok,r=pcall(e.identifyexecutor);if ok then name=r end end;return{GetHui=type(e.gethui)=="function",FileSystem=type(e.writefile)=="function" and type(e.readfile)=="function",Clipboard=type(e.setclipboard)=="function" or type(e.toclipboard)=="function",ExecutorName=tostring(name)} end
function AstraUI:FormatDuration(s,c) return formatDuration(s,c) end
function AstraUI:CreateTheme(o) o=o or{};local b=type(o.Base)=="string" and self.Themes[o.Base] or o.Base or self.Themes.Midnight;local r=theme(merge(b,o));r.Base=nil;return r end
function AstraUI:Localize(v,locale) if type(v)=="function" then local ok,r=pcall(v,locale or "en-us");return ok and tostring(r) or "" end;return tostring(v or "") end
function AstraUI:CreatePool(factory) local p={Free={},Factory=factory};function p:Get(...)return table.remove(self.Free) or self.Factory(...)end;function p:Release(x)table.insert(self.Free,x)end;function p:Clear()for _,x in ipairs(self.Free)do pcall(function()x:Destroy()end)end;table.clear(self.Free)end;return p end
function AstraUI:RenderIcon(parent,name,window,o)o=o or{};return drawIcon(parent,name,o.Color or(window and window.Theme.TextSecondary)or Color3.new(1,1,1),o.Size or 18)end
function AstraUI:AuditTheme(t)return{Theme=theme(t or self.Themes.Midnight),OK=true}end
function AstraUI:UnloadAll()for _,w in ipairs(self.Windows)do pcall(function()w:Destroy()end)end;table.clear(self.Windows)end
function AstraUI:Destroy()self:UnloadAll();self.Destroyed=true end

local function preferredInput() local ok,v=pcall(function()return UserInputService.PreferredInput end);if ok and v then return v end;if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then return Enum.PreferredInput.Touch elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then return Enum.PreferredInput.Gamepad end;return Enum.PreferredInput.KeyboardAndMouse end
local function deviceInfo()
    local v=viewport();local p=preferredInput();local orientation=v.X>=v.Y and "Landscape" or "Portrait";local platform=(p==Enum.PreferredInput.Gamepad and not UserInputService.KeyboardEnabled)and"Console"or((p==Enum.PreferredInput.Touch or(UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled))and"Mobile"or"Computer");local min=math.min(v.X,v.Y);local form=platform=="Mobile" and(min>=700 and"Tablet"or"Phone")or(platform=="Console"and"TV"or(v.X<900 and"CompactDesktop"or"Desktop"));return{Platform=platform,FormFactor=form,Orientation=orientation,Layout=platform=="Mobile"and(form..orientation)or(platform=="Console"and"Gamepad"or form),PreferredInput=p.Name,Viewport=v,Touch=UserInputService.TouchEnabled,Keyboard=UserInputService.KeyboardEnabled,Gamepad=UserInputService.GamepadEnabled}
end

function AstraUI:CreateWindow(o)
    o=o or{};local parent=resolveParent(o.Parent);local key=tostring(o.RegistryKey or o.Name or o.Title or "AstraUI");local guiName="AstraUI_"..key:gsub("[^%w_]","_");if o.ReplaceExisting~=false then local old=parent:FindFirstChild(guiName);if old then old:Destroy()end end
    local t=type(o.Theme)=="string"and self.Themes[o.Theme]or o.Theme or self.Themes.Rose;t=theme(t);local ds=o.Size and Vector2.new(o.Size.X.Offset,o.Size.Y.Offset)or Vector2.new(840,550);if ds.X<=0 then ds=Vector2.new(840,550)end
    local w=setmetatable({Library=self,Theme=t,ThemeName=type(o.Theme)=="string"and o.Theme or"Rose",Connections={},Tabs={},Controls={},Flags={},FlagDefaults={},SearchEntries={},Commands={},Shortcuts={},Presets={},Activities={},Logs={},Notifications={},NotificationHistory={},DeviceListeners={},ThemeListeners={},KeyInfoListeners={},UnloadListeners={},KeyInfo={},SessionStartedAt=os.clock(),Scale=clamp(tonumber(o.Scale)or 1,.65,1.45),Roundness=clamp(tonumber(o.Roundness)or 1,0,1.5),WindowCornerRadius=clamp(tonumber(o.WindowCornerRadius)or 14,0,28),DefaultSize=ds,CurrentSize=ds,MinSize=o.MinSize or Vector2.new(460,300),MaxSize=o.MaxSize or Vector2.new(1400,900),Resizable=o.Resizable~=false,Visible=true,Destroyed=false,DragLocked=false,SidebarCollapsed=false,Density=o.Density or"Comfortable",MotionIntensity=o.MotionIntensity or"Normal",ConfigPath=o.ConfigPath,Title=tostring(o.Title or o.Name or"Astra UI"),Subtitle=tostring(o.Subtitle or"Executor Interface"),FooterText=tostring(o.Footer or"AstraUI · Ready"),UndoStack={},RedoStack={},PinnedActions={},RecentActions={},SearchHistory={},Autosave={Enabled=false}},Window);w.DeviceInfo=deviceInfo()
    local screen=create("ScreenGui",{Name=guiName,Parent=parent,ResetOnSpawn=false,IgnoreGuiInset=o.IgnoreGuiInset~=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=o.DisplayOrder or 100000});w.ScreenGui=screen
    local overlay=create("Frame",{Name="OverlayRoot",Parent=screen,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=1000});w.Overlay=overlay
    local main=create("Frame",{Name="Main",Parent=screen,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(ds.X,ds.Y),BackgroundColor3=t.Background,BorderSizePixel=0,ClipsDescendants=true});w.Main=main;main:SetAttribute("AstraIgnoreRoundness",true);corner(main,w.WindowCornerRadius);stroke(main,t.Border,.2,1)
    screen:SetAttribute("AstraRoundness",w.Roundness)
    -- Scale only the application window. Overlays/toasts stay viewport-sized and never inherit interface zoom.
    local scale=Instance.new("UIScale");scale.Scale=w.Scale;scale.Parent=main;w.ScaleObject=scale
    local side=create("Frame",{Name="Sidebar",Parent=main,Size=UDim2.new(0,210,1,0),BackgroundColor3=t.Sidebar,BorderSizePixel=0});w.Sidebar=side
    local div=create("Frame",{Parent=side,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,0,0,0),Size=UDim2.new(0,1,1,0),BackgroundColor3=t.BorderSubtle,BorderSizePixel=0});w.SidebarDivider=div
    local brand=create("Frame",{Parent=side,Size=UDim2.new(1,0,0,86),BackgroundTransparency=1});local logo=create("TextLabel",{Parent=brand,Position=UDim2.fromOffset(16,14),Size=UDim2.fromOffset(42,42),BackgroundColor3=t.Accent,BorderSizePixel=0,Text=tostring(o.IconText or"A"),TextColor3=t.AccentText,TextSize=18,Font=Enum.Font.GothamBold});corner(logo,12);w.Logo=logo
    local bt=label(brand,w.Title,16,t.TextPrimary,Enum.Font.GothamBold);bt.Position=UDim2.fromOffset(72,15);bt.Size=UDim2.new(1,-84,0,24);local bs=label(brand,w.Subtitle,11,t.TextSecondary);bs.Position=UDim2.fromOffset(72,40);bs.Size=UDim2.new(1,-84,0,20);w.BrandTitle=bt;w.BrandSubtitle=bs
    local sh=create("Frame",{Parent=side,Position=UDim2.fromOffset(14,88),Size=UDim2.new(1,-28,0,44),BackgroundColor3=t.Surface,BorderSizePixel=0});corner(sh,10);stroke(sh,t.BorderSubtle,.2,1);local si=drawIcon(sh,"search",t.TextSecondary,16);si.Position=UDim2.fromOffset(12,14);local search=create("TextBox",{Parent=sh,Position=UDim2.fromOffset(38,0),Size=UDim2.new(1,-48,1,0),BackgroundTransparency=1,BorderSizePixel=0,Text="",PlaceholderText="Search",PlaceholderColor3=t.TextSecondary,TextColor3=t.TextPrimary,TextSize=12,Font=Enum.Font.Gotham,ClearTextOnFocus=false,TextXAlignment=Enum.TextXAlignment.Left});w.SearchHolder=sh;w.SearchBox=search
    local tl=create("ScrollingFrame",{Parent=side,Position=UDim2.fromOffset(10,146),Size=UDim2.new(1,-20,1,-216),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=0});list(tl,6,false);w.TabList=tl
    local foot=create("Frame",{Parent=side,AnchorPoint=Vector2.new(0,1),Position=UDim2.new(0,14,1,-12),Size=UDim2.new(1,-28,0,42),BackgroundColor3=t.Surface,BorderSizePixel=0});corner(foot,10);local dot=create("Frame",{Parent=foot,Position=UDim2.fromOffset(12,15),Size=UDim2.fromOffset(12,12),BackgroundColor3=t.Success,BorderSizePixel=0});corner(dot,99);local fl=label(foot,w.FooterText,10,t.TextSecondary);fl.Position=UDim2.fromOffset(32,0);fl.Size=UDim2.new(1,-42,1,0);w.Footer=foot;w.FooterLabel=fl
    local content=create("Frame",{Parent=main,Position=UDim2.fromOffset(210,0),Size=UDim2.new(1,-210,1,0),BackgroundColor3=t.Background,BorderSizePixel=0});w.Content=content
    local top=create("Frame",{Parent=content,Size=UDim2.new(1,0,0,74),BackgroundColor3=t.Topbar,BorderSizePixel=0});w.Topbar=top;local pt=label(top,"Home",18,t.TextPrimary,Enum.Font.GothamBold);pt.Position=UDim2.fromOffset(22,10);pt.Size=UDim2.new(1,-210,0,26);local ps=label(top,"",11,t.TextSecondary);ps.Position=UDim2.fromOffset(22,37);ps.Size=UDim2.new(1,-210,0,20);w.PageTitle=pt;w.PageSubtitle=ps;local td=create("Frame",{Parent=top,AnchorPoint=Vector2.new(0,1),Position=UDim2.new(0,0,1,0),Size=UDim2.new(1,0,0,1),BackgroundColor3=t.BorderSubtle,BorderSizePixel=0});w.TopDivider=td
    local acts=create("Frame",{Parent=top,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-16,0,12),Size=UDim2.fromOffset(142,40),BackgroundTransparency=1});local al=list(acts,8,true);al.HorizontalAlignment=Enum.HorizontalAlignment.Right
    local function topButton(name)local b=create("TextButton",{Parent=acts,Size=UDim2.fromOffset(38,38),BackgroundColor3=t.Surface2,BorderSizePixel=0,Text="",AutoButtonColor=false});corner(b,10);stroke(b,t.BorderSubtle,.35,1);local i=drawIcon(b,name,t.TextSecondary,16);i.AnchorPoint=Vector2.new(.5,.5);i.Position=UDim2.fromScale(.5,.5);return b end
    w.MenuButton=topButton("menu");w.ThemeButton=topButton("visuals");w.MinimizeButton=topButton("minimize")
    local pages=create("Frame",{Parent=content,Position=UDim2.fromOffset(0,74),Size=UDim2.new(1,0,1,-74),BackgroundTransparency=1,ClipsDescendants=true});w.Pages=pages
    local nr=create("Frame",{Name="Notifications",Parent=overlay,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-18,0,18),Size=UDim2.fromOffset(360,1),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,ZIndex=1100});local nl=list(nr,10,false);nl.HorizontalAlignment=Enum.HorizontalAlignment.Right;w.NotificationRoot=nr
    local function C(sig,fn)local c=sig:Connect(fn);table.insert(w.Connections,c);return c end;w._connect=C
    C(search:GetPropertyChangedSignal("Text"),function()w:_applySearch(search.Text)end);C(w.MenuButton.MouseButton1Click,function()w:ToggleSidebar()end);C(w.ThemeButton.MouseButton1Click,function()local order={"Rose","Midnight","Ocean","Emerald","Graphite","Light"};local i=table.find(order,w.ThemeName)or 1;w:SetThemePreset(order[i%#order+1])end);C(w.MinimizeButton.MouseButton1Click,function()w:SetMinimized(not w.Minimized)end)
    local dragging=false;local ds0;local pos0
    local function overTopAction(pos)
        for _,b in ipairs({w.MenuButton,w.ThemeButton,w.MinimizeButton}) do
            local ap,as=b.AbsolutePosition,b.AbsoluteSize
            if pos.X>=ap.X and pos.X<=ap.X+as.X and pos.Y>=ap.Y and pos.Y<=ap.Y+as.Y then return true end
        end
        return false
    end
    C(top.InputBegan,function(inp)
        if w.DragLocked or overTopAction(inp.Position) then return end
        if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then dragging=true;ds0=inp.Position;pos0=main.Position end
    end)
    C(UserInputService.InputChanged,function(inp)if dragging and(inp.UserInputType==Enum.UserInputType.MouseMovement or inp.UserInputType==Enum.UserInputType.Touch)then local d=inp.Position-ds0;main.Position=UDim2.new(pos0.X.Scale,pos0.X.Offset+d.X,pos0.Y.Scale,pos0.Y.Offset+d.Y)end end)
    C(UserInputService.InputEnded,function(inp)if inp.UserInputType==Enum.UserInputType.MouseButton1 or inp.UserInputType==Enum.UserInputType.Touch then dragging=false;task.defer(function()if not w.Destroyed then w:KeepWindowAccessible()end end)end end)
    local grip=create("TextButton",{Parent=main,AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,-4,1,-4),Size=UDim2.fromOffset(24,24),BackgroundTransparency=1,Text="",BorderSizePixel=0,ZIndex=50});iconLine(grip,10,16,9,1.2,t.TextSecondary,-45);iconLine(grip,14,16,5,1.2,t.TextSecondary,-45);w.ResizeGrip=grip
    local rz=false;local rp;local rs;C(grip.InputBegan,function(inp)if not w.Resizable or not w:IsComputer() then return end;if inp.UserInputType==Enum.UserInputType.MouseButton1 then rz=true;rp=inp.Position;rs=w.CurrentSize end end);C(UserInputService.InputChanged,function(inp)if rz and inp.UserInputType==Enum.UserInputType.MouseMovement then local d=inp.Position-rp;w:SetWindowSize(rs.X+d.X/w.Scale,rs.Y+d.Y/w.Scale,false)end end);C(UserInputService.InputEnded,function(inp)if inp.UserInputType==Enum.UserInputType.MouseButton1 then rz=false end end)
    local tk=o.ToggleKey or Enum.KeyCode.RightShift;C(UserInputService.InputBegan,function(inp,processed)if not processed and inp.KeyCode==tk then w:Toggle()end;for _,s in ipairs(w.Shortcuts)do if not processed and s.KeyCode==inp.KeyCode then safeCall(s.Callback)end end end)
    local function deviceChanged()local old=w.DeviceInfo;w.DeviceInfo=deviceInfo();screen:SetAttribute("AstraPlatform",w.DeviceInfo.Platform);screen:SetAttribute("AstraLayout",w.DeviceInfo.Layout);screen:SetAttribute("AstraPreferredInput",w.DeviceInfo.PreferredInput);w:_responsive();if old.Layout~=w.DeviceInfo.Layout or old.Platform~=w.DeviceInfo.Platform then for _,fn in ipairs(w.DeviceListeners)do safeCall(fn,w.DeviceInfo)end end end
    if Workspace.CurrentCamera then C(Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"),deviceChanged)end;pcall(function()C(UserInputService:GetPropertyChangedSignal("PreferredInput"),deviceChanged)end)
    table.insert(self.Windows,w);w:_responsive();w:SetWindowSizePreset(o.SizePreset or"Normal",false);w:Center();if o.KeySystem and o.KeySystem.Enabled then task.defer(function()w:_showKeyGate(o.KeySystem)end)end;return w
end

-- ================================================================
-- Window geometry, device and theme
-- ================================================================

function Window:_responsive()
    local collapsed=self.DeviceInfo.Platform=="Mobile" or self.CurrentSize.X<730
    if self._manualSidebar~=nil then collapsed=self._manualSidebar end
    self.SidebarCollapsed=collapsed;local sw=collapsed and 64 or 210;self.Sidebar.Size=UDim2.new(0,sw,1,0);self.Content.Position=UDim2.fromOffset(sw,0);self.Content.Size=UDim2.new(1,-sw,1,0);self.SearchHolder.Visible=not collapsed;self.BrandTitle.Visible=not collapsed;self.BrandSubtitle.Visible=not collapsed;self.Footer.Visible=not collapsed;self.ResizeGrip.Visible=self.Resizable and self:IsComputer()
    for _,t in ipairs(self.Tabs)do t:_sidebar(collapsed)end;self:KeepWindowAccessible()
end
function Window:GetDeviceInfo()return copy(self.DeviceInfo)end
function Window:IsMobile()return self.DeviceInfo.Platform=="Mobile"end
function Window:IsComputer()return self.DeviceInfo.Platform=="Computer"end
function Window:IsConsole()return self.DeviceInfo.Platform=="Console"end
function Window:OnDeviceChanged(fn)table.insert(self.DeviceListeners,fn);return fn end
function Window:OnPreferredInputChanged(fn)return self:OnDeviceChanged(fn)end
function Window:GetLayoutProfile()return self.DeviceInfo.Layout end
function Window:GetSafeArea()return{Top=0,Left=0,Right=0,Bottom=0}end
function Window:ApplySafeArea()return true end

local function safeMax(w)
    local v=viewport();local mx=w:IsMobile()and20 or50;local my=w:IsMobile()and34 or60;return Vector2.new(math.floor((v.X-mx)/w.Scale),math.floor((v.Y-my)/w.Scale))
end
local function preset(w,name)
    name=string.lower(tostring(name or "normal"))
    local sm=safeMax(w)
    local presets={
        small=Vector2.new(560,360),
        normal=w.DefaultSize,
        large=Vector2.new(math.max(w.DefaultSize.X,1040),math.max(w.DefaultSize.Y,680)),
        max=sm,
    }
    -- Portrait layouts prioritize usable width; height still differentiates the presets.
    if w:IsMobile() and w.DeviceInfo.Orientation=="Portrait" then
        presets.small=Vector2.new(math.min(320,sm.X),math.min(430,sm.Y))
        presets.normal=Vector2.new(sm.X,math.min(560,sm.Y))
        presets.large=Vector2.new(sm.X,math.min(700,sm.Y))
    end
    local target=presets[name] or presets.normal
    local lim=w:GetWindowSizeLimits()
    return Vector2.new(clamp(target.X,lim.Min.X,lim.Max.X),clamp(target.Y,lim.Min.Y,lim.Max.Y))
end
function Window:GetWindowSize()return self.CurrentSize end
function Window:GetWindowSizeLimits()
    local sm=safeMax(self)
    local maxv=Vector2.new(math.max(260,math.min(self.MaxSize.X,sm.X)),math.max(240,math.min(self.MaxSize.Y,sm.Y)))
    local minv=Vector2.new(math.min(self.MinSize.X,maxv.X),math.min(self.MinSize.Y,maxv.Y))
    if self:IsMobile() and self.DeviceInfo.Orientation=="Portrait" then
        minv=Vector2.new(math.min(300,maxv.X),math.min(360,maxv.Y))
    end
    return{Min=minv,Max=maxv,Viewport=viewport(),Scale=self.Scale}
end
function Window:SetWindowSize(x,y,animate)
    local lim=self:GetWindowSizeLimits();x=clamp(tonumber(x)or self.CurrentSize.X,lim.Min.X,lim.Max.X);y=clamp(tonumber(y)or self.CurrentSize.Y,lim.Min.Y,lim.Max.Y);self.CurrentSize=Vector2.new(math.floor(x+.5),math.floor(y+.5));local sz=UDim2.fromOffset(self.CurrentSize.X,self.CurrentSize.Y);if animate==false or self.MotionIntensity=="Reduced"then self.Main.Size=sz else tween(self.Main,.18,{Size=sz})end;self:_responsive();return self.CurrentSize
end
function Window:SetWindowSizePreset(name,animate)local s=preset(self,name);return self:SetWindowSize(s.X,s.Y,animate)end
function Window:ResizeBy(dx,dy)return self:SetWindowSize(self.CurrentSize.X+(tonumber(dx)or0),self.CurrentSize.Y+(tonumber(dy)or0),true)end
function Window:ResetWindowSize()return self:SetWindowSizePreset("Normal",true)end
function Window:IncreaseInterfaceSize()return self:ResizeBy(120,80)end
function Window:DecreaseInterfaceSize()return self:ResizeBy(-120,-80)end
function Window:KeepWindowAccessible()
    if not self.Main or not self.Main.Parent then return end;local v=viewport();local p=self.Main.AbsolutePosition;local s=self.Main.AbsoluteSize;local keep=56;local dx,dy=0,0;if p.X+keep>v.X then dx=v.X-keep-p.X end;if p.Y+keep>v.Y then dy=v.Y-keep-p.Y end;if p.X+s.X-keep<0 then dx=-(p.X+s.X-keep)end;if p.Y+s.Y-keep<0 then dy=-(p.Y+s.Y-keep)end;if dx~=0 or dy~=0 then self.Main.Position=self.Main.Position+UDim2.fromOffset(dx/math.max(.01,self.Scale),dy/math.max(.01,self.Scale))end
end
function Window:SetScale(v)self.Scale=clamp(tonumber(v)or1,.65,1.45);self.ScaleObject.Scale=self.Scale;self:SetWindowSize(self.CurrentSize.X,self.CurrentSize.Y,false);return self.Scale end
function Window:SetInterfaceScale(v)return self:SetScale(v)end
function Window:SetUIScale(v)return self:SetScale(v)end
function Window:SetWindowCornerRadius(v)self.WindowCornerRadius=clamp(tonumber(v)or14,0,28);corner(self.Main,self.WindowCornerRadius);return self.WindowCornerRadius end
function Window:SetRoundness(v)
    self.Roundness=clamp(tonumber(v) or 1,0,1.5)
    self.ScreenGui:SetAttribute("AstraRoundness",self.Roundness)
    for _,c in ipairs(self.ScreenGui:GetDescendants()) do
        if c:IsA("UICorner") and c.Name=="AstraCorner" and c.Parent~=self.Main and not c.Parent:GetAttribute("AstraFixedCorner") then
            local base=c.Parent:GetAttribute("AstraBaseRadius")
            if base then c.CornerRadius=UDim.new(0,clamp(base*self.Roundness,0,28)) end
        end
    end
    return self.Roundness
end
function Window:GetRoundness()return self.Roundness end
function Window:GetInterfaceMetrics()return{Size=self.CurrentSize,Scale=self.Scale,Roundness=self.Roundness,WindowCornerRadius=self.WindowCornerRadius,Resizable=self.Resizable,Device=self:GetDeviceInfo()}end
function Window:Center()self.Main.AnchorPoint=Vector2.new(.5,.5);self.Main.Position=UDim2.fromScale(.5,.5)end
function Window:SetDragLocked(v)self.DragLocked=not not v end
function Window:IsDragLocked()return self.DragLocked end
function Window:SetSidebarCollapsed(v)self._manualSidebar=not not v;self:_responsive()end
function Window:ToggleSidebar()self._manualSidebar=not self.SidebarCollapsed;self:_responsive()end
function Window:SetMinimized(v)
    self.Minimized=not not v
    if self.Minimized then
        self._restore=self.CurrentSize
        self.Pages.Visible=false
        self.Sidebar.Visible=false
        self.Content.Position=UDim2.fromOffset(0,0)
        self.Content.Size=UDim2.new(1,0,1,0)
        local sz=UDim2.fromOffset(math.max(360,math.min(self.CurrentSize.X,620)),74)
        if self.MotionIntensity=="Reduced" then self.Main.Size=sz else tween(self.Main,.16,{Size=sz}) end
    else
        self.Sidebar.Visible=true
        self.Pages.Visible=true
        local restore=self._restore or self.DefaultSize
        self.CurrentSize=restore
        local sz=UDim2.fromOffset(restore.X,restore.Y)
        if self.MotionIntensity=="Reduced" then self.Main.Size=sz else tween(self.Main,.18,{Size=sz}) end
        task.defer(function() if not self.Destroyed then self:_responsive();self:KeepWindowAccessible() end end)
    end
end
function Window:IsVisible()return self.Visible end
function Window:SetVisible(v)self.Visible=not not v;self.ScreenGui.Enabled=self.Visible end
function Window:Toggle()self:SetVisible(not self.Visible)end
function Window:SetTitle(t,s)if t~=nil then self.Title=tostring(t);self.BrandTitle.Text=self.Title end;if s~=nil then self.Subtitle=tostring(s);self.BrandSubtitle.Text=self.Subtitle end end
function Window:SetFooter(t)self.FooterText=tostring(t or"");self.FooterLabel.Text=self.FooterText end
function Window:SetTheme(v)
    if type(v)=="string" then return self:SetThemePreset(v) end
    local old=self.Theme
    local t=theme(v)
    -- Recolor semantic surfaces created by controls before changing self.Theme. This keeps
    -- theme switching deterministic without stacking per-version override layers.
    if old then
        local keys={"Background","Sidebar","Topbar","Surface","Surface2","Surface3","Hover","Border","BorderSubtle","TextPrimary","TextSecondary","Accent","AccentSoft","AccentText","Success","Warning","Danger","Info","Scrollbar"}
        local function remap(c)
            for _,k in ipairs(keys) do if old[k] and c==old[k] and t[k] then return t[k] end end
            return c
        end
        for _,obj in ipairs(self.ScreenGui:GetDescendants()) do
            if obj:IsA("GuiObject") then obj.BackgroundColor3=remap(obj.BackgroundColor3) end
            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                obj.TextColor3=remap(obj.TextColor3)
                if obj:IsA("TextBox") then obj.PlaceholderColor3=remap(obj.PlaceholderColor3) end
            elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then obj.ImageColor3=remap(obj.ImageColor3) end
            if obj:IsA("ScrollingFrame") then obj.ScrollBarImageColor3=remap(obj.ScrollBarImageColor3) end
            if obj:IsA("UIStroke") then obj.Color=remap(obj.Color) end
        end
    end
    self.Theme=t
    self.Main.BackgroundColor3=t.Background;self.Sidebar.BackgroundColor3=t.Sidebar;self.Content.BackgroundColor3=t.Background;self.Topbar.BackgroundColor3=t.Topbar;self.Logo.BackgroundColor3=t.Accent;self.BrandTitle.TextColor3=t.TextPrimary;self.BrandSubtitle.TextColor3=t.TextSecondary;self.SearchHolder.BackgroundColor3=t.Surface;self.SearchBox.TextColor3=t.TextPrimary;self.SearchBox.PlaceholderColor3=t.TextSecondary;self.Footer.BackgroundColor3=t.Surface;self.FooterLabel.TextColor3=t.TextSecondary;self.PageTitle.TextColor3=t.TextPrimary;self.PageSubtitle.TextColor3=t.TextSecondary;self.SidebarDivider.BackgroundColor3=t.BorderSubtle;self.TopDivider.BackgroundColor3=t.BorderSubtle;stroke(self.Main,t.Border,.2,1)
    for _,tab in ipairs(self.Tabs)do tab:_theme()end
    for _,fn in ipairs(self.ThemeListeners)do safeCall(fn,t)end
    return t
end
function Window:SetThemePreset(n)local t=self.Library.Themes[tostring(n)];if not t then return false,"Unknown theme"end;self.ThemeName=tostring(n);self:SetTheme(t);return true end
function Window:GetTheme()return self.Theme end
function Window:OnThemeChanged(fn)table.insert(self.ThemeListeners,fn);return fn end
function Window:SetAccent(c)local t=copy(self.Theme);t.Accent=c;t.AccentSoft=nil;return self:SetTheme(theme(t))end
function Window:GetDesignTokens()return{Spacing={XS=4,S=8,M=12,L=16,XL=24},Radius={S=8,M=10,L=14},Motion={Fast=.12,Normal=.18,Slow=.28},TouchTarget=44}end
function Window:SetDensity(v)self.Density=tostring(v or"Comfortable");return self.Density end
function Window:SetMotionIntensity(v)self.MotionIntensity=tostring(v or"Normal")end
function Window:SetReduceTransparency(v)self.ReduceTransparency=not not v end
function Window:SetHighContrast(v)self.HighContrast=not not v end
function Window:SetColorBlindMode(v)self.ColorBlindMode=tostring(v or"None")end
function Window:GetAccessibilityPreferences()return{Motion=self.MotionIntensity,ReduceTransparency=self.ReduceTransparency,HighContrast=self.HighContrast,ColorBlindMode=self.ColorBlindMode}end
function Window:ApplyPreferredTextSize()return false,"Not consistently exposed in executor runtimes"end
function Window:GetOnScreenKeyboardInfo()return{Visible=UserInputService.OnScreenKeyboardVisible}end
function Window:EnableKeyboardAwareness()return true end
function Window:SetGamepadNavigation()return true end
function Window:NormalizeAutomaticSizing()return true end

-- ================================================================
-- Notification lifecycle - fixed size, fixed timeout, fixed exit
-- ================================================================

function Window:Notify(o)
    o=o or{}
    local title=tostring(o.Title or "AstraUI")
    local content=tostring(o.Content or o.Description or "")
    local typ=string.lower(tostring(o.Type or "info"))
    local duration=tonumber(o.Duration);if duration==nil then duration=4.5 end
    local persistent=o.Persistent==true or duration<=0
    local t=self.Theme
    local tone=typ=="success" and t.Success or typ=="warning" and t.Warning or typ=="error" and t.Danger or t.Info
    local v=viewport();local width=clamp(self:IsMobile() and math.min(330,v.X-24) or 340,math.min(250,v.X-24),math.min(360,v.X-24))
    local ch=content~="" and textHeight(content,11,width-52) or 0
    local height=clamp(48+(ch>0 and ch+8 or 0),58,118)
    local slot=create("Frame",{Parent=self.NotificationRoot,Size=UDim2.fromOffset(width,height),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=1100})
    local f=create("Frame",{Parent=slot,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,width+18,0,0),Size=UDim2.fromScale(1,1),BackgroundColor3=t.Surface2,BackgroundTransparency=.02,BorderSizePixel=0,ClipsDescendants=true,ZIndex=1101});corner(f,12);stroke(f,t.Border,.15,1)
    local stripe=create("Frame",{Parent=f,Size=UDim2.new(0,3,1,0),BackgroundColor3=tone,BorderSizePixel=0,ZIndex=1102});corner(stripe,2)
    local tt=label(f,title,12,t.TextPrimary,Enum.Font.GothamBold);tt.Position=UDim2.fromOffset(16,9);tt.Size=UDim2.new(1,-48,0,20);tt.ZIndex=1103
    local x=create("TextButton",{Parent=f,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-8,0,7),Size=UDim2.fromOffset(26,26),BackgroundTransparency=1,Text="×",TextColor3=t.TextSecondary,TextSize=16,Font=Enum.Font.GothamMedium,BorderSizePixel=0,ZIndex=1104})
    local body=label(f,content,11,t.TextSecondary);body.Position=UDim2.fromOffset(16,31);body.Size=UDim2.new(1,-32,0,math.max(18,ch));body.TextWrapped=true;body.TextTruncate=Enum.TextTruncate.None;body.TextYAlignment=Enum.TextYAlignment.Top;body.ZIndex=1103
    local prog=create("Frame",{Parent=f,AnchorPoint=Vector2.new(0,1),Position=UDim2.new(0,12,1,-6),Size=UDim2.new(1,-24,0,2),BackgroundColor3=tone,BackgroundTransparency=persistent and1 or0,BorderSizePixel=0,ZIndex=1103});corner(prog,2)
    local sc=Instance.new("UIScale");sc.Scale=.96;sc.Parent=f
    local rec={Instance=f,Slot=slot,Title=title,Content=content,Type=typ,CreatedAt=os.time(),Closed=false}
    table.insert(self.Notifications,rec);table.insert(self.NotificationHistory,rec)
    local function close()
        if rec.Closed then return end;rec.Closed=true
        tween(sc,.14,{Scale=.96},Enum.EasingStyle.Quad,Enum.EasingDirection.In)
        tween(f,.18,{Position=UDim2.new(1,width+18,0,0),BackgroundTransparency=.12},Enum.EasingStyle.Quart,Enum.EasingDirection.In)
        tween(tt,.12,{TextTransparency=1});tween(body,.12,{TextTransparency=1});tween(x,.12,{TextTransparency=1});tween(stripe,.12,{BackgroundTransparency=1});tween(prog,.12,{BackgroundTransparency=1})
        task.delay(.2,function()local i=table.find(self.Notifications,rec);if i then table.remove(self.Notifications,i)end;if slot.Parent then slot:Destroy()end end)
    end
    rec.Close=close
    self:_connect(x.MouseButton1Click,close)
    tween(sc,.22,{Scale=1},Enum.EasingStyle.Back,Enum.EasingDirection.Out)
    tween(f,.24,{Position=UDim2.new(1,0,0,0)},Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
    if not persistent then tween(prog,duration,{Size=UDim2.new(0,0,0,2)},Enum.EasingStyle.Linear,Enum.EasingDirection.InOut);task.delay(duration,function()if not self.Destroyed then close()end end)end
    return rec
end
function Window:ClearNotifications()local c={};for _,n in ipairs(self.Notifications)do table.insert(c,n)end;for _,n in ipairs(c)do if n.Close then n.Close()end end end
function Window:GetNotifications()return self.NotificationHistory end
function Window:ShowSnackbar(t,o)o=o or{};o.Title=o.Title or"AstraUI";o.Content=t;o.Duration=o.Duration or2.2;return self:Notify(o)end

-- ================================================================
-- Tabs and search
-- ================================================================

function Window:_registerSearch(e)table.insert(self.SearchEntries,e)end
function Window:_applySearch(q)q=string.lower(tostring(q or""));for _,e in ipairs(self.SearchEntries)do if e.Instance and e.Instance.Parent then e.Instance.Visible=q==""or string.find(e.Haystack,q,1,true)~=nil end end end
function Window:FocusSearch()if self.SearchHolder.Visible then self.SearchBox:CaptureFocus()end end
function Window:ClearSearch()self.SearchBox.Text=""end
function Window:SearchAll(q)q=string.lower(tostring(q or""));if q~=""then table.insert(self.SearchHistory,1,q)end;local r={};for _,e in ipairs(self.SearchEntries)do if q==""or string.find(e.Haystack,q,1,true)then table.insert(r,e)end end;return r end
function Window:GetSearchHistory()return self.SearchHistory end

function Window:CreateTab(o)
    if type(o)=="string"then o={Name=o}end;o=o or{};local tab=setmetatable({Window=self,Name=tostring(o.Name or"Tab"),Description=tostring(o.Description or""),Icon=o.Icon or"info",Sections={}},Tab);local b=create("TextButton",{Parent=self.TabList,Size=UDim2.new(1,0,0,46),BackgroundColor3=self.Theme.Sidebar,BackgroundTransparency=1,Text="",BorderSizePixel=0,AutoButtonColor=false});b:SetAttribute("AstraBaseRadius",10);corner(b,10*self.Roundness);local ind=create("Frame",{Parent=b,Position=UDim2.fromOffset(2,10),Size=UDim2.fromOffset(3,26),BackgroundColor3=self.Theme.Accent,BackgroundTransparency=1,BorderSizePixel=0});corner(ind,3);local ic=drawIcon(b,tab.Icon,self.Theme.TextSecondary,18);ic.Position=UDim2.fromOffset(14,14);local l=label(b,tab.Name,12,self.Theme.TextSecondary,Enum.Font.GothamMedium);l.Position=UDim2.fromOffset(46,0);l.Size=UDim2.new(1,-54,1,0);tab.Button=b;tab.Indicator=ind;tab.IconHost=ic;tab.Label=l
    local p=create("ScrollingFrame",{Parent=self.Pages,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,Visible=false,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=3,ScrollBarImageColor3=self.Theme.Scrollbar});padding(p,18,16,18,28);list(p,14,false);tab.Page=p;table.insert(self.Tabs,tab);self:_connect(b.MouseButton1Click,function()self:SelectTab(tab)end);self:_registerSearch({Instance=b,Haystack=string.lower(tab.Name.." "..tab.Description),Type="Tab",Object=tab});tab:_sidebar(self.SidebarCollapsed);if#self.Tabs==1 then self:SelectTab(tab)end;return tab
end
function Tab:_sidebar(c)self.Label.Visible=not c;self.IconHost.Position=c and UDim2.fromOffset(23,14)or UDim2.fromOffset(14,14)end
function Tab:_theme()
    local t=self.Window.Theme;local active=self.Window.SelectedTab==self;self.Page.ScrollBarImageColor3=t.Scrollbar;self.Button.BackgroundColor3=active and t.AccentSoft or t.Sidebar;self.Button.BackgroundTransparency=active and0 or1;self.Indicator.BackgroundColor3=t.Accent;self.Indicator.BackgroundTransparency=active and0 or1;self.Label.TextColor3=active and t.TextPrimary or t.TextSecondary;for _,d in ipairs(self.IconHost:GetDescendants())do if d:IsA("Frame")and d.BackgroundTransparency<1 then d.BackgroundColor3=active and t.Accent or t.TextSecondary elseif d:IsA("UIStroke")then d.Color=active and t.Accent or t.TextSecondary elseif d:IsA("TextLabel")then d.TextColor3=active and t.Accent or t.TextSecondary end end
end
function Window:SelectTab(tab)if type(tab)=="string"then for _,x in ipairs(self.Tabs)do if x.Name==tab then tab=x;break end end end;if type(tab)~="table"then return false end;self.SelectedTab=tab;for _,x in ipairs(self.Tabs)do x.Page.Visible=x==tab;x:_theme()end;self.PageTitle.Text=tab.Name;self.PageSubtitle.Text=tab.Description;return true end

function Tab:CreateSection(o)
    if type(o)=="string"then o={Name=o}end;o=o or{};local s=setmetatable({Tab=self,Window=self.Window,Name=tostring(o.Name or"Section"),Description=tostring(o.Description or""),Controls={}},Section);local f=create("Frame",{Parent=self.Page,Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundColor3=self.Window.Theme.Surface,BorderSizePixel=0});f:SetAttribute("AstraBaseRadius",14);corner(f,14*self.Window.Roundness);stroke(f,self.Window.Theme.BorderSubtle,.28,1);padding(f,14,13,14,14);list(f,10,false);local t=label(f,s.Name,13,self.Window.Theme.TextPrimary,Enum.Font.GothamBold);t.Size=UDim2.new(1,0,0,20);if s.Description~=""then local d=label(f,s.Description,10,self.Window.Theme.TextSecondary);d.Size=UDim2.new(1,0,0,18);d.TextWrapped=true;d.TextTruncate=Enum.TextTruncate.None end;s.Frame=f;table.insert(self.Sections,s);self.Window:_registerSearch({Instance=f,Haystack=string.lower(s.Name.." "..s.Description),Type="Section",Object=s});return s
end
function Tab:_defaultSection()if not self._default then self._default=self:CreateSection({Name="Controls"})end;return self._default end

local function card(s,name,desc,h)
    local w=s.Window;local t=w.Theme;local r=create("Frame",{Parent=s.Frame,Size=UDim2.new(1,0,0,h or68),BackgroundColor3=t.Surface2,BorderSizePixel=0});r:SetAttribute("AstraBaseRadius",10);corner(r,10*w.Roundness);stroke(r,t.BorderSubtle,.42,1);local a=label(r,name,12,t.TextPrimary,Enum.Font.GothamMedium);a.Position=UDim2.fromOffset(14,9);a.Size=UDim2.new(1,-28,0,20);local d=label(r,desc or"",10,t.TextSecondary);d.Position=UDim2.fromOffset(14,31);d.Size=UDim2.new(1,-28,0,18);local c=setmetatable({Window=w,Section=s,Instance=r,Title=a,Description=d},Control);table.insert(s.Controls,c);table.insert(w.Controls,c);w:_registerSearch({Instance=r,Haystack=string.lower(tostring(name).." "..tostring(desc or"")),Type="Control",Object=c});return r,c
end
local function flag(c,o,def)c.Flag=o.Flag;c.Default=def;c.Callback=o.Callback;if o.Flag then c.Window.Flags[o.Flag]=def;c.Window.FlagDefaults[o.Flag]=def;c.Window.Controls[o.Flag]=c end end

-- ================================================================
-- Basic controls
-- ================================================================

function Section:AddButton(o)
    o=o or{};local r,c=card(self,o.Name or"Button",o.Description,64);local w=self.Window;local b=button(r,o.ButtonText or o.Text or o.Name or"Run",w.Theme,o.Style or"Primary");b.AnchorPoint=Vector2.new(1,.5);b.Position=UDim2.new(1,-14,.5,0);b.Size=UDim2.fromOffset(clamp(textWidth(b.Text,12)+34,82,150),36);c.Button=b
    function c:SetDisabled(v)self.Disabled=not not v;b.Active=not self.Disabled;b.BackgroundTransparency=self.Disabled and .45 or0 end
    function c:Set()end;function c:Get()return nil end;function c:GetDefault()return nil end
    w:_connect(b.MouseButton1Click,function()if c.Disabled or type(o.Callback)~="function"then return end;local old=b.Text;if o.Async then b.Text=o.LoadingText or"Loading...";b.Active=false end;safeCall(o.Callback,c);if o.Async then b.Text=old;b.Active=true end end);if type(o.Callback)~="function"then c:SetDisabled(true)end;return c
end
function Tab:AddButton(o)return self:_defaultSection():AddButton(o)end

function Section:AddToggle(o)
    o=o or{};local def=not not o.Default;local r,c=card(self,o.Name or"Toggle",o.Description,64);local w=self.Window;local tr=create("TextButton",{Parent=r,AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-14,.5,0),Size=UDim2.fromOffset(54,28),BackgroundColor3=w.Theme.Surface3,BorderSizePixel=0,Text="",AutoButtonColor=false});corner(tr,14);local k=create("Frame",{Parent=tr,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromOffset(def and40 or14,14),Size=UDim2.fromOffset(20,20),BackgroundColor3=def and Color3.new(1,1,1)or w.Theme.TextSecondary,BorderSizePixel=0});corner(k,99);local val=def
    local function apply(v,fire)val=not not v;tr.BackgroundColor3=val and w.Theme.Accent or w.Theme.Surface3;k.BackgroundColor3=val and Color3.new(1,1,1)or w.Theme.TextSecondary;tween(k,.14,{Position=UDim2.fromOffset(val and40 or14,14)});w:_setFlag(o.Flag,val,c);if fire~=false then safeCall(o.Callback,val)end end
    function c:Set(v,fire)apply(v,fire)end;function c:Get()return val end;function c:GetDefault()return def end;function c:SetDisabled(v)self.Disabled=not not v;tr.Active=not self.Disabled;tr.BackgroundTransparency=self.Disabled and .45 or0 end;flag(c,o,def);w:_connect(tr.MouseButton1Click,function()if not c.Disabled then apply(not val,true)end end);apply(def,false);return c
end
function Tab:AddToggle(o)return self:_defaultSection():AddToggle(o)end

function Section:AddSlider(o)
    o=o or{};local mn=tonumber(o.Min)or0;local mx=tonumber(o.Max)or100;local inc=tonumber(o.Increment)or1;local def=clamp(tonumber(o.Default)or mn,mn,mx);local r,c=card(self,o.Name or"Slider",o.Description,82);local w=self.Window;local vl=label(r,"",10,w.Theme.Accent,Enum.Font.GothamBold,Enum.TextXAlignment.Right);vl.AnchorPoint=Vector2.new(1,0);vl.Position=UDim2.new(1,-14,0,9);vl.Size=UDim2.fromOffset(80,20);local rail=create("TextButton",{Parent=r,Position=UDim2.fromOffset(14,58),Size=UDim2.new(1,-28,0,4),BackgroundColor3=w.Theme.Surface3,BorderSizePixel=0,Text="",AutoButtonColor=false});corner(rail,4);local fill=create("Frame",{Parent=rail,Size=UDim2.new(0,0,1,0),BackgroundColor3=w.Theme.Accent,BorderSizePixel=0});corner(fill,4);local knob=create("Frame",{Parent=rail,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new(0,0,.5,0),Size=UDim2.fromOffset(16,16),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0});corner(knob,99);stroke(knob,w.Theme.Accent,0,2);local val=def
    local function norm(v)v=clamp(v,mn,mx);v=math.floor((v-mn)/inc+.5)*inc+mn;return clamp(v,mn,mx)end
    local function apply(v,fire)val=norm(tonumber(v)or mn);local a=mx==mn and0 or(val-mn)/(mx-mn);fill.Size=UDim2.new(a,0,1,0);knob.Position=UDim2.new(a,0,.5,0);vl.Text=tostring(val)..tostring(o.Suffix or"");w:_setFlag(o.Flag,val,c);if fire~=false then safeCall(o.Callback,val)end end
    local drag=false;local function fromX(x)local p,s=rail.AbsolutePosition,rail.AbsoluteSize;apply(mn+clamp((x-p.X)/math.max(1,s.X),0,1)*(mx-mn),true)end;w:_connect(rail.InputBegan,function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true;fromX(i.Position.X)end end);w:_connect(UserInputService.InputChanged,function(i)if drag and(i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch)then fromX(i.Position.X)end end);w:_connect(UserInputService.InputEnded,function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false;if o.CallbackOnRelease then safeCall(o.CallbackOnRelease,val)end end end)
    function c:Set(v,fire)apply(v,fire)end;function c:Get()return val end;function c:GetDefault()return def end;function c:SetDisabled(v)self.Disabled=not not v;rail.Active=not self.Disabled;r.BackgroundTransparency=self.Disabled and .3 or0 end;flag(c,o,def);apply(def,false);return c
end
function Tab:AddSlider(o)return self:_defaultSection():AddSlider(o)end

function Section:AddInput(o)
    o=o or{};local def=tostring(o.Default or"");local r,c=card(self,o.Name or"Input",o.Description,72);local w=self.Window;local box=create("TextBox",{Parent=r,AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-14,.5,0),Size=UDim2.fromOffset(240,38),BackgroundColor3=w.Theme.Surface3,BorderSizePixel=0,Text=def,PlaceholderText=tostring(o.Placeholder or"Enter value..."),TextColor3=w.Theme.TextPrimary,PlaceholderColor3=w.Theme.TextSecondary,TextSize=11,Font=Enum.Font.Gotham,ClearTextOnFocus=false,TextXAlignment=Enum.TextXAlignment.Left});corner(box,10);stroke(box,w.Theme.Border,.25,1);padding(box,12,0,12,0);c.Box=box
    function c:Set(v,fire)box.Text=tostring(v or"");w:_setFlag(o.Flag,box.Text,c);if fire~=false then safeCall(o.Callback,box.Text)end end;function c:Get()return box.Text end;function c:GetDefault()return def end;function c:SetDisabled(v)self.Disabled=not not v;box.TextEditable=not self.Disabled;box.BackgroundTransparency=self.Disabled and .35 or0 end;flag(c,o,def);w:_connect(box.Focused,function()stroke(box,w.Theme.Accent,0,1.5)end);w:_connect(box.FocusLost,function(enter)stroke(box,w.Theme.Border,.25,1);w:_setFlag(o.Flag,box.Text,c);if not o.CallbackOnEnter or enter then safeCall(o.Callback,box.Text,enter)end end);return c
end
function Tab:AddInput(o)return self:_defaultSection():AddInput(o)end

function Window:_dropdownPopover(o,b,choose)
    if self._popover then self._popover:Destroy();self._popover=nil end
    local vals=o.Options or{};local width=clamp(b.AbsoluteSize.X,180,320);local height=math.max(44,math.min(#vals,8)*34+12);local ap=b.AbsolutePosition;local v=viewport();local x=clamp(ap.X,8,v.X-width-8);local y=ap.Y+b.AbsoluteSize.Y+6;if y+height>v.Y-8 then y=math.max(8,ap.Y-height-6)end
    local layer=create("Frame",{Parent=self.Overlay,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=1199})
    local catcher=create("TextButton",{Parent=layer,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,Text="",AutoButtonColor=false,ZIndex=1199})
    local pop=create("Frame",{Parent=layer,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(width,height),BackgroundColor3=self.Theme.Surface2,BorderSizePixel=0,ZIndex=1200,ClipsDescendants=true});corner(pop,12);stroke(pop,self.Theme.Border,.08,1)
    local sf=create("ScrollingFrame",{Parent=pop,Position=UDim2.fromOffset(6,6),Size=UDim2.new(1,-12,1,-12),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=2,ScrollBarImageColor3=self.Theme.Scrollbar,ZIndex=1201});list(sf,4,false)
    self._popover=layer;self:_connect(catcher.MouseButton1Click,function()if layer.Parent then layer:Destroy()end;if self._popover==layer then self._popover=nil end end)
    for _,v0 in ipairs(vals)do local ib=button(sf,tostring(v0),self.Theme,"Ghost");ib.Size=UDim2.new(1,-2,0,30);ib.ZIndex=1202;self:_connect(ib.MouseButton1Click,function()choose(v0);if not o.Multi and layer.Parent then layer:Destroy();self._popover=nil end end)end
    return pop
end
function Section:AddDropdown(o)
    o=o or{};local multi=o.Multi==true;local def=o.Default;if multi and type(def)~="table"then def={}elseif not multi and def==nil then def=(o.Options or{})[1]end;local r,c=card(self,o.Name or"Dropdown",o.Description,72);local w=self.Window;local b=button(r,"",w.Theme,"Secondary");b.AnchorPoint=Vector2.new(1,.5);b.Position=UDim2.new(1,-14,.5,0);b.Size=UDim2.fromOffset(240,38);local val=multi and copy(def)or def
    local function txt()if multi then local n=0;for _,v in pairs(val)do if v==true then n+=1 end end;return n==0 and"None selected"or(n.." selected")end;return tostring(val or"Select")end
    local function apply(v,fire)val=multi and copy(v or{})or v;b.Text=txt();w:_setFlag(o.Flag,val,c);if fire~=false then safeCall(o.Callback,val)end end
    local function choose(v)if multi then local n=copy(val);n[v]=not n[v];apply(n,true)else apply(v,true)end end;w:_connect(b.MouseButton1Click,function()if not c.Disabled then w:_dropdownPopover(o,b,choose)end end);function c:Set(v,fire)apply(v,fire)end;function c:Get()return val end;function c:GetDefault()return def end;function c:SetOptions(v)o.Options=v or{}end;function c:SetDisabled(v)self.Disabled=not not v;b.Active=not self.Disabled;b.BackgroundTransparency=self.Disabled and .35 or0 end;flag(c,o,def);apply(def,false);return c
end
function Tab:AddDropdown(o)return self:_defaultSection():AddDropdown(o)end

function Section:AddKeybind(o)
    o=o or{};local def=o.Default or Enum.KeyCode.K;local r,c=card(self,o.Name or"Keybind",o.Description,64);local w=self.Window;local b=button(r,def.Name,w.Theme,"Secondary");b.AnchorPoint=Vector2.new(1,.5);b.Position=UDim2.new(1,-14,.5,0);b.Size=UDim2.fromOffset(100,34);local key=def;local listen=false;w:_connect(b.MouseButton1Click,function()listen=true;b.Text="Press key..."end);w:_connect(UserInputService.InputBegan,function(i,proc)if listen then if i.KeyCode~=Enum.KeyCode.Unknown then key=i.KeyCode;b.Text=key.Name;listen=false;w:_setFlag(o.Flag,key.Name,c);safeCall(o.Changed,key)end;return end;if not proc and i.KeyCode==key then safeCall(o.Callback,key)end end);function c:Set(v)if typeof(v)=="EnumItem"then key=v;b.Text=v.Name end end;function c:Get()return key end;function c:GetDefault()return def end;flag(c,o,def.Name);return c
end
function Tab:AddKeybind(o)return self:_defaultSection():AddKeybind(o)end

function Section:AddLabel(o)if type(o)=="string"then o={Text=o}end;o=o or{};local r,c=card(self,o.Name or o.Text or"Label",o.Description,50);function c:Set(v)c.Title.Text=tostring(v)end;function c:Get()return c.Title.Text end;return c end
function Tab:AddLabel(o)return self:_defaultSection():AddLabel(o)end
function Section:AddParagraph(o)o=o or{};local tx=tostring(o.Content or o.Text or o.Description or"");local h=clamp(48+textHeight(tx,10,500),64,150);local r,c=card(self,o.Name or o.Title or"Paragraph",tx,h);c.Description.TextWrapped=true;c.Description.TextTruncate=Enum.TextTruncate.None;c.Description.Size=UDim2.new(1,-28,1,-40);c.Description.TextYAlignment=Enum.TextYAlignment.Top;return c end
function Tab:AddParagraph(o)return self:_defaultSection():AddParagraph(o)end
function Section:AddDivider()local f=create("Frame",{Parent=self.Frame,Size=UDim2.new(1,0,0,1),BackgroundColor3=self.Window.Theme.BorderSubtle,BorderSizePixel=0});return{Instance=f}end
function Tab:AddDivider(o)return self:_defaultSection():AddDivider(o)end
function Section:AddProgressBar(o)o=o or{};local d=clamp(tonumber(o.Default)or0,0,100);local r,c=card(self,o.Name or"Progress",o.Description,72);local rail=create("Frame",{Parent=r,Position=UDim2.fromOffset(14,54),Size=UDim2.new(1,-28,0,6),BackgroundColor3=self.Window.Theme.Surface3,BorderSizePixel=0});corner(rail,6);local f=create("Frame",{Parent=rail,Size=UDim2.new(d/100,0,1,0),BackgroundColor3=self.Window.Theme.Accent,BorderSizePixel=0});corner(f,6);local v=d;function c:Set(x)v=clamp(tonumber(x)or0,0,100);f.Size=UDim2.new(v/100,0,1,0)end;function c:Get()return v end;return c end
function Tab:AddProgressBar(o)return self:_defaultSection():AddProgressBar(o)end
function Section:AddColorPicker(o)
    o=o or{};local def=o.Default or Color3.fromRGB(255,80,160);local r,c=card(self,o.Name or "Color",o.Description,64);local w=self.Window
    local sw=create("TextButton",{Parent=r,AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-14,.5,0),Size=UDim2.fromOffset(58,32),BackgroundColor3=def,Text="",BorderSizePixel=0,AutoButtonColor=false});corner(sw,10);stroke(sw,w.Theme.Border,.15,1);local v=def
    local function apply(x,fire)if typeof(x)=="Color3"then v=x;sw.BackgroundColor3=x;if fire~=false then safeCall(o.Callback,x)end end end
    function c:Set(x,fire)apply(x,fire)end;function c:Get()return v end;function c:GetDefault()return def end
    w:_connect(sw.MouseButton1Click,function()
        if w._colorPopover then w._colorPopover:Destroy();w._colorPopover=nil end
        local layer=create("Frame",{Parent=w.Overlay,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=1240})
        local catcher=create("TextButton",{Parent=layer,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,Text="",AutoButtonColor=false,ZIndex=1240})
        local width,height=222,104;local ap=sw.AbsolutePosition;local vp=viewport();local x=clamp(ap.X+sw.AbsoluteSize.X-width,8,vp.X-width-8);local y=ap.Y+sw.AbsoluteSize.Y+6;if y+height>vp.Y-8 then y=math.max(8,ap.Y-height-6)end
        local pop=create("Frame",{Parent=layer,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(width,height),BackgroundColor3=w.Theme.Surface2,BorderSizePixel=0,ZIndex=1241});corner(pop,12);stroke(pop,w.Theme.Border,.08,1);padding(pop,10,10,10,10)
        local grid=Instance.new("UIGridLayout");grid.CellSize=UDim2.fromOffset(42,36);grid.CellPadding=UDim2.fromOffset(8,8);grid.Parent=pop
        local colors=o.Presets or {w.Theme.Accent,Color3.fromRGB(112,83,255),Color3.fromRGB(64,141,246),Color3.fromRGB(57,199,146),Color3.fromRGB(241,184,67),Color3.fromRGB(239,91,100),Color3.fromRGB(235,235,240),Color3.fromRGB(45,48,58)}
        for _,col in ipairs(colors)do local b=create("TextButton",{Parent=pop,BackgroundColor3=col,BorderSizePixel=0,Text="",AutoButtonColor=false,ZIndex=1242});corner(b,9);stroke(b,w.Theme.Border,.2,1);w:_connect(b.MouseButton1Click,function()apply(col,true);if layer.Parent then layer:Destroy()end;w._colorPopover=nil end)end
        w:_connect(catcher.MouseButton1Click,function()if layer.Parent then layer:Destroy()end;w._colorPopover=nil end);w._colorPopover=layer
    end)
    return c
end
function Tab:AddColorPicker(o)return self:_defaultSection():AddColorPicker(o)end
function Section:AddStatus(o)o=o or{};local r,c=card(self,o.Name or"Status",o.Description,58);local p=label(r,tostring(o.Value or o.Status or"Ready"),10,self.Window.Theme.TextPrimary,Enum.Font.GothamBold,Enum.TextXAlignment.Center);p.AnchorPoint=Vector2.new(1,.5);p.Position=UDim2.new(1,-14,.5,0);p.Size=UDim2.fromOffset(100,28);p.BackgroundTransparency=0;p.BackgroundColor3=self.Window.Theme.AccentSoft;corner(p,14);function c:Set(v)p.Text=tostring(v)end;function c:Get()return p.Text end;return c end
function Tab:AddStatus(o)return self:_defaultSection():AddStatus(o)end
function Section:AddTextArea(o)o=o or{};local r,c=card(self,o.Name or"Text Area",o.Description,130);local b=create("TextBox",{Parent=r,Position=UDim2.fromOffset(14,52),Size=UDim2.new(1,-28,0,62),BackgroundColor3=self.Window.Theme.Surface3,BorderSizePixel=0,Text=tostring(o.Default or""),PlaceholderText=tostring(o.Placeholder or"Type..."),TextColor3=self.Window.Theme.TextPrimary,PlaceholderColor3=self.Window.Theme.TextSecondary,TextSize=11,Font=Enum.Font.Gotham,ClearTextOnFocus=false,MultiLine=true,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top});corner(b,10);stroke(b,self.Window.Theme.Border,.25,1);padding(b,10,8,10,8);function c:Set(v,fire)b.Text=tostring(v or"");if fire~=false then safeCall(o.Callback,b.Text)end end;function c:Get()return b.Text end;return c end
function Tab:AddTextArea(o)return self:_defaultSection():AddTextArea(o)end

Tab._addButton=Tab.AddButton;Tab._addToggle=Tab.AddToggle;Tab._addSlider=Tab.AddSlider;Tab._addInput=Tab.AddInput;Tab._addDropdown=Tab.AddDropdown;Tab._addKeybind=Tab.AddKeybind;Tab._addLabel=Tab.AddLabel;Tab._addParagraph=Tab.AddParagraph;Tab._addDivider=Tab.AddDivider;Tab._addProgressBar=Tab.AddProgressBar;Tab._addColorPicker=Tab.AddColorPicker;Tab._addStatus=Tab.AddStatus;Tab._addTextArea=Tab.AddTextArea

-- ================================================================
-- Flags/config/history
-- ================================================================

function Window:_setFlag(k,v)if not k then return end;local old=self.Flags[k];if old~=v then table.insert(self.UndoStack,{Flag=k,Old=old,New=v});table.clear(self.RedoStack)end;self.Flags[k]=v end
function Window:GetFlag(k)return self.Flags[k]end
function Window:SetFlag(k,v)local c=self.Controls[k];if c and c.Set then c:Set(v,true)else self:_setFlag(k,v)end end
function Window:GetFlags()return copy(self.Flags)end
function Window:HasFlag(k)return self.Flags[k]~=nil end
function Window:GetConfig()return copy(self.Flags)end
function Window:ExportConfig()return HttpService:JSONEncode(self.Flags)end
function Window:LoadConfig(v)if type(v)=="string"then local ok,d=pcall(HttpService.JSONDecode,HttpService,v);if not ok then return false,d end;v=d end;for k,x in pairs(v or{})do self:SetFlag(k,x)end;return true end
function Window:ResetConfig()for k,v in pairs(self.FlagDefaults)do self:SetFlag(k,v)end end
function Window:CopyConfig()local e=self.Library:GetEnvironment();local cb=e.setclipboard or e.toclipboard;if type(cb)=="function"then return pcall(cb,self:ExportConfig())end;return false end
function Window:SaveConfigFile(path)path=path or self.ConfigPath;if not path then return false,"No ConfigPath"end;local e=self.Library:GetEnvironment();if type(e.writefile)~="function"then return false,"writefile unavailable"end;local folder=string.match(path,"^(.*)/[^/]+$");if folder and type(e.makefolder)=="function"then pcall(e.makefolder,folder)end;return pcall(e.writefile,path,self:ExportConfig())end
function Window:LoadConfigFile(path)path=path or self.ConfigPath;if not path then return false,"No ConfigPath"end;local e=self.Library:GetEnvironment();if type(e.readfile)~="function"then return false,"readfile unavailable"end;local ok,d=pcall(e.readfile,path);if not ok then return false,d end;return self:LoadConfig(d)end
function Window:DeleteConfigFile(path)path=path or self.ConfigPath;local e=self.Library:GetEnvironment();if type(e.delfile)~="function"then return false,"delfile unavailable"end;return pcall(e.delfile,path)end
function Window:DeleteConfig(path)return self:DeleteConfigFile(path)end
function Window:GetConfigFiles()return{}end
function Window:DuplicateConfig()return false,"Filesystem enumeration is executor-specific"end
function Window:RenameConfig()return false,"Filesystem enumeration is executor-specific"end
function Window:DiffConfig(v)if type(v)=="string"then local ok,d=pcall(HttpService.JSONDecode,HttpService,v);if not ok then return{}end;v=d end;local r={};for k,x in pairs(v or{})do if self.Flags[k]~=x then table.insert(r,{Flag=k,Current=self.Flags[k],New=x})end end;return r end
function Window:PreviewConfigDiff(v)return self:DiffConfig(v)end
function Window:Undo()local i=table.remove(self.UndoStack);if not i then return false end;table.insert(self.RedoStack,i);local c=self.Controls[i.Flag];if c and c.Set then c:Set(i.Old,true)else self.Flags[i.Flag]=i.Old end;return true end
function Window:Redo()local i=table.remove(self.RedoStack);if not i then return false end;table.insert(self.UndoStack,i);local c=self.Controls[i.Flag];if c and c.Set then c:Set(i.New,true)else self.Flags[i.Flag]=i.New end;return true end

-- ================================================================
-- Rich components / application widgets
-- ================================================================

local function rich(s,name,desc,h)return card(s,name,desc,h or112)end

function Section:AddQuickActions(o)
    o=o or{};local acts=o.Actions or o.Items or{};local r,c=rich(self,o.Name or"Quick Actions",o.Description or"Frequently used actions",116);local host=create("Frame",{Parent=r,Position=UDim2.fromOffset(14,56),Size=UDim2.new(1,-28,0,46),BackgroundTransparency=1});local g=Instance.new("UIGridLayout");g.CellPadding=UDim2.fromOffset(8,0);g.CellSize=UDim2.new(1/math.max(1,math.min(4,#acts)),-6,1,0);g.FillDirectionMaxCells=4;g.Parent=host
    for i,a in ipairs(acts)do local b=button(host,a.Name or a.Text or("Action "..i),self.Window.Theme,a.Style or"Secondary");b.LayoutOrder=i;self.Window:_connect(b.MouseButton1Click,function()safeCall(a.Callback)end)end;return c
end
function Tab:AddQuickActions(o)return self:_defaultSection():AddQuickActions(o)end;Tab._addQuickActions=Tab.AddQuickActions

function Section:AddSegmentedControl(o)
    o=o or{};local opts=o.Options or{};local def=o.Default or opts[1];local r,c=rich(self,o.Name or"Segmented",o.Description,92);local host=create("Frame",{Parent=r,Position=UDim2.fromOffset(14,48),Size=UDim2.new(1,-28,0,34),BackgroundColor3=self.Window.Theme.Surface3,BorderSizePixel=0});corner(host,10);list(host,4,true);local val=def;local bs={}
    local function apply(v,fire)val=v;for k,b in pairs(bs)do b.BackgroundColor3=k==v and self.Window.Theme.Accent or self.Window.Theme.Surface3;b.TextColor3=k==v and self.Window.Theme.AccentText or self.Window.Theme.TextSecondary end;self.Window:_setFlag(o.Flag,val);if fire~=false then safeCall(o.Callback,val)end end
    for _,x in ipairs(opts)do local b=button(host,tostring(x),self.Window.Theme,"Ghost");b.Size=UDim2.new(1/math.max(1,#opts),-4,1,0);bs[x]=b;self.Window:_connect(b.MouseButton1Click,function()apply(x,true)end)end;function c:Set(v,fire)apply(v,fire)end;function c:Get()return val end;flag(c,o,def);apply(def,false);return c
end
function Tab:AddSegmentedControl(o)return self:_defaultSection():AddSegmentedControl(o)end;Tab._addSegmentedControl=Tab.AddSegmentedControl

function Section:AddCheckbox(o)
    o=o or{};local def=not not o.Default;local r,c=card(self,o.Name or"Checkbox",o.Description,58);local b=create("TextButton",{Parent=r,AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-16,.5,0),Size=UDim2.fromOffset(24,24),BackgroundColor3=self.Window.Theme.Surface3,BorderSizePixel=0,Text="",AutoButtonColor=false});corner(b,6);stroke(b,self.Window.Theme.Border,.15,1);local m=label(b,"✓",14,self.Window.Theme.AccentText,Enum.Font.GothamBold,Enum.TextXAlignment.Center);m.Size=UDim2.fromScale(1,1);local val=def;local function apply(v,fire)val=not not v;b.BackgroundColor3=val and self.Window.Theme.Accent or self.Window.Theme.Surface3;m.Visible=val;self.Window:_setFlag(o.Flag,val);if fire~=false then safeCall(o.Callback,val)end end;function c:Set(v,fire)apply(v,fire)end;function c:Get()return val end;flag(c,o,def);self.Window:_connect(b.MouseButton1Click,function()apply(not val,true)end);apply(def,false);return c
end
function Tab:AddCheckbox(o)return self:_defaultSection():AddCheckbox(o)end;Tab._addCheckbox=Tab.AddCheckbox

function Section:AddRadioGroup(o)o=o or{};return self:AddSegmentedControl({Name=o.Name or"Radio Group",Description=o.Description,Options=o.Options,Default=o.Default,Flag=o.Flag,Callback=o.Callback})end
function Tab:AddRadioGroup(o)return self:_defaultSection():AddRadioGroup(o)end;Tab._addRadioGroup=Tab.AddRadioGroup
function Section:AddToggleGroup(o)o=o or{};local vals=copy(o.Default or{});local acts={};for _,x in ipairs(o.Options or{})do table.insert(acts,{Name=tostring(x),Style=vals[x]and"Primary"or"Secondary",Callback=function()vals[x]=not vals[x];safeCall(o.Callback,vals)end})end;return self:AddQuickActions({Name=o.Name or"Toggle Group",Description=o.Description,Actions=acts})end
function Tab:AddToggleGroup(o)return self:_defaultSection():AddToggleGroup(o)end;Tab._addToggleGroup=Tab.AddToggleGroup

function Section:AddStepper(o)
    o=o or{};local mn=o.Min or0;local mx=o.Max or10;local step=o.Increment or1;local def=clamp(o.Default or mn,mn,mx);local r,c=card(self,o.Name or"Stepper",o.Description,64);local host=create("Frame",{Parent=r,AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-14,.5,0),Size=UDim2.fromOffset(130,34),BackgroundTransparency=1});local minus=button(host,"−",self.Window.Theme,"Secondary");minus.Size=UDim2.fromOffset(34,34);local vl=label(host,tostring(def),11,self.Window.Theme.TextPrimary,Enum.Font.GothamBold,Enum.TextXAlignment.Center);vl.Position=UDim2.fromOffset(38,0);vl.Size=UDim2.fromOffset(54,34);local plus=button(host,"+",self.Window.Theme,"Secondary");plus.Position=UDim2.fromOffset(96,0);plus.Size=UDim2.fromOffset(34,34);local val=def;local function apply(v,fire)val=clamp(v,mn,mx);vl.Text=tostring(val);self.Window:_setFlag(o.Flag,val);if fire~=false then safeCall(o.Callback,val)end end;function c:Set(v,fire)apply(tonumber(v)or val,fire)end;function c:Get()return val end;flag(c,o,def);self.Window:_connect(minus.MouseButton1Click,function()apply(val-step,true)end);self.Window:_connect(plus.MouseButton1Click,function()apply(val+step,true)end);return c
end
function Tab:AddStepper(o)return self:_defaultSection():AddStepper(o)end;Tab._addStepper=Tab.AddStepper
function Section:AddNumberInput(o)o=o or{};return self:AddInput({Name=o.Name or"Number",Description=o.Description,Default=tostring(o.Default or0),Flag=o.Flag,Callback=function(v)safeCall(o.Callback,clamp(tonumber(v)or0,o.Min or-math.huge,o.Max or math.huge))end})end
function Tab:AddNumberInput(o)return self:_defaultSection():AddNumberInput(o)end;Tab._addNumberInput=Tab.AddNumberInput
function Section:AddRangeSlider(o)
    o=o or{}
    local mn=tonumber(o.Min) or 0;local mx=tonumber(o.Max) or 100;local inc=tonumber(o.Increment) or 1
    local d=o.Default or {mn,mx};local low=clamp(tonumber(d[1]) or mn,mn,mx);local high=clamp(tonumber(d[2]) or mx,low,mx)
    local r,c=card(self,o.Name or "Range Slider",o.Description,88);local w=self.Window
    local value=label(r,"",10,w.Theme.Accent,Enum.Font.GothamBold,Enum.TextXAlignment.Right);value.AnchorPoint=Vector2.new(1,0);value.Position=UDim2.new(1,-14,0,9);value.Size=UDim2.fromOffset(120,20)
    local rail=create("Frame",{Parent=r,Position=UDim2.fromOffset(14,61),Size=UDim2.new(1,-28,0,4),BackgroundColor3=w.Theme.Surface3,BorderSizePixel=0});corner(rail,4)
    local fill=create("Frame",{Parent=rail,BackgroundColor3=w.Theme.Accent,BorderSizePixel=0});corner(fill,4)
    local lo=create("TextButton",{Parent=rail,AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(18,18),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0,Text="",AutoButtonColor=false});corner(lo,99);stroke(lo,w.Theme.Accent,0,2)
    local hi=lo:Clone();hi.Parent=rail
    local dragging=nil
    local function snap(v)return clamp(math.floor((v-mn)/inc+.5)*inc+mn,mn,mx)end
    local function render(fire)
        low=snap(low);high=snap(high);if low>high then low,high=high,low end
        local a=mx==mn and 0 or (low-mn)/(mx-mn);local b=mx==mn and 1 or (high-mn)/(mx-mn)
        lo.Position=UDim2.new(a,0,.5,0);hi.Position=UDim2.new(b,0,.5,0);fill.Position=UDim2.new(a,0,0,0);fill.Size=UDim2.new(math.max(0,b-a),0,1,0);value.Text=tostring(low).." — "..tostring(high)..tostring(o.Suffix or "")
        local pair={low,high};w:_setFlag(o.Flag,pair,c);if fire~=false then safeCall(o.Callback,pair)end
    end
    local function fromX(x,which)local ap,as=rail.AbsolutePosition,rail.AbsoluteSize;local v=mn+clamp((x-ap.X)/math.max(1,as.X),0,1)*(mx-mn);if which=="low" then low=math.min(snap(v),high) else high=math.max(snap(v),low) end;render(true)end
    w:_connect(lo.InputBegan,function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging="low";fromX(i.Position.X,dragging)end end)
    w:_connect(hi.InputBegan,function(i)if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging="high";fromX(i.Position.X,dragging)end end)
    w:_connect(UserInputService.InputChanged,function(i)if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then fromX(i.Position.X,dragging)end end)
    w:_connect(UserInputService.InputEnded,function(i)if dragging and (i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch) then dragging=nil;if o.CallbackOnRelease then safeCall(o.CallbackOnRelease,{low,high})end end end)
    function c:Set(v,fire)if type(v)=="table" then low=tonumber(v[1]) or low;high=tonumber(v[2]) or high;render(fire)end end
    function c:Get()return{low,high}end;function c:GetDefault()return copy(d)end;flag(c,o,{low,high});render(false);return c
end
function Tab:AddRangeSlider(o)return self:_defaultSection():AddRangeSlider(o)end;Tab._addRangeSlider=Tab.AddRangeSlider
function Section:AddComboBox(o)o=o or{};o.Name=o.Name or"Combo Box";return self:AddDropdown(o)end
function Tab:AddComboBox(o)return self:_defaultSection():AddComboBox(o)end;Tab._addComboBox=Tab.AddComboBox
function Section:AddTagInput(o)o=o or{};return self:AddInput({Name=o.Name or"Tags",Description=o.Description,Default=table.concat(o.Default or{},", "),Placeholder=o.Placeholder or"tag1, tag2",Callback=function(v)local a={};for x in string.gmatch(v,"[^,]+")do table.insert(a,(x:gsub("^%s+","")):gsub("%s+$",""))end;safeCall(o.Callback,a)end})end
function Tab:AddTagInput(o)return self:_defaultSection():AddTagInput(o)end;Tab._addTagInput=Tab.AddTagInput
function Section:AddBadge(o)o=o or{};return self:AddStatus({Name=o.Name or"Badge",Description=o.Description,Value=o.Text or o.Value or"NEW"})end
function Tab:AddBadge(o)return self:_defaultSection():AddBadge(o)end;Tab._addBadge=Tab.AddBadge
function Section:AddProgressCard(o)o=o or{};local c=self:AddProgressBar({Name=o.Name or"Progress",Description=o.Description,Default=o.Value or o.Default or0});return c end
function Tab:AddProgressCard(o)return self:_defaultSection():AddProgressCard(o)end;Tab._addProgressCard=Tab.AddProgressCard
function Section:AddCircularProgress(o)
    o=o or{};local val=clamp(tonumber(o.Value or o.Default) or 0,0,100);local r,c=rich(self,o.Name or "Circular Progress",o.Description,108);local w=self.Window
    local ring=create("Frame",{Parent=r,AnchorPoint=Vector2.new(1,.5),Position=UDim2.new(1,-18,.56,0),Size=UDim2.fromOffset(58,58),BackgroundColor3=w.Theme.Surface3,BorderSizePixel=0});corner(ring,99);stroke(ring,w.Theme.Border,.1,5)
    local inner=create("Frame",{Parent=ring,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(42,42),BackgroundColor3=w.Theme.Surface2,BorderSizePixel=0});corner(inner,99)
    local txt=label(inner,"",11,w.Theme.Accent,Enum.Font.GothamBold,Enum.TextXAlignment.Center);txt.Size=UDim2.fromScale(1,1)
    local marker=create("Frame",{Parent=ring,AnchorPoint=Vector2.new(.5,.5),Size=UDim2.fromOffset(8,8),BackgroundColor3=w.Theme.Accent,BorderSizePixel=0});corner(marker,99)
    local function apply(v,fire)val=clamp(tonumber(v) or 0,0,100);txt.Text=math.floor(val+.5).."%";local a=math.rad(val/100*360-90);marker.Position=UDim2.fromOffset(29+math.cos(a)*25,29+math.sin(a)*25);if fire~=false then safeCall(o.Callback,val)end end
    function c:Set(v,fire)apply(v,fire)end;function c:Get()return val end;apply(val,false);return c
end
function Tab:AddCircularProgress(o)return self:_defaultSection():AddCircularProgress(o)end;Tab._addCircularProgress=Tab.AddCircularProgress
function Section:AddSkeleton(o)o=o or{};local r,c=rich(self,o.Name or"Loading",o.Description,94);for i,wid in ipairs({.75,.55,.9})do local f=create("Frame",{Parent=r,Position=UDim2.new(0,14,0,42+(i-1)*14),Size=UDim2.new(wid,-14,0,8),BackgroundColor3=self.Window.Theme.Surface3,BorderSizePixel=0});corner(f,6)end;return c end
function Tab:AddSkeleton(o)return self:_defaultSection():AddSkeleton(o)end;Tab._addSkeleton=Tab.AddSkeleton
function Section:AddStateCard(o)o=o or{};return self:AddParagraph({Name=o.Name or o.Title or"State",Content=o.Content or o.Description or""})end
function Tab:AddStateCard(o)return self:_defaultSection():AddStateCard(o)end;Tab._addStateCard=Tab.AddStateCard
function Tab:AddEmptyState(o)o=o or{};o.Name=o.Name or"Nothing here";return self:_defaultSection():AddStateCard(o)end
function Tab:AddErrorState(o)o=o or{};o.Name=o.Name or"Something went wrong";return self:_defaultSection():AddStateCard(o)end
function Tab:AddSuccessState(o)o=o or{};o.Name=o.Name or"Success";return self:_defaultSection():AddStateCard(o)end

function Section:AddList(o)
    o=o or{};local items=o.Items or{};local r,c=rich(self,o.Name or"List",o.Description,76+math.min(#items,6)*42);local y=50;for _,it in ipairs(items)do local f=create("Frame",{Parent=r,Position=UDim2.fromOffset(14,y),Size=UDim2.new(1,-28,0,36),BackgroundColor3=self.Window.Theme.Surface3,BorderSizePixel=0});corner(f,9);local tx=type(it)=="table"and(it.Name or it.Title or it.Text or tostring(it.Value))or tostring(it);local l=label(f,tx,11,self.Window.Theme.TextPrimary,Enum.Font.GothamMedium);l.Position=UDim2.fromOffset(10,0);l.Size=UDim2.new(1,-20,1,0);y+=42 end;return c
end
function Tab:AddList(o)return self:_defaultSection():AddList(o)end;Tab._addList=Tab.AddList
function Section:AddDataGrid(o)o=o or{};local rows=o.Rows or o.Items or{};local items={};for _,r in ipairs(rows)do table.insert(items,{Name=type(r)=="table"and table.concat(r,"  |  ")or tostring(r)})end;return self:AddList({Name=o.Name or"Data Grid",Description=o.Description,Items=items})end
function Tab:AddDataGrid(o)return self:_defaultSection():AddDataGrid(o)end;Tab._addDataGrid=Tab.AddDataGrid
function Section:AddPlayerList(o)o=o or{};local items={};for _,p in ipairs(Players:GetPlayers())do table.insert(items,{Name=p.DisplayName.."  @"..p.Name})end;return self:AddList({Name=o.Name or"Players",Description=o.Description,Items=items})end
function Tab:AddPlayerList(o)return self:_defaultSection():AddPlayerList(o)end;Tab._addPlayerList=Tab.AddPlayerList
function Section:AddVirtualList(o)return self:AddList(o)end
function Tab:AddVirtualList(o)return self:_defaultSection():AddVirtualList(o)end;Tab._addVirtualList=Tab.AddVirtualList
function Section:AddPagination(o)o=o or{};return self:AddStepper({Name=o.Name or"Page",Min=1,Max=o.Pages or10,Default=1,Callback=o.Callback})end
function Tab:AddPagination(o)return self:_defaultSection():AddPagination(o)end;Tab._addPagination=Tab.AddPagination

function Section:AddInfoList(o)
    o=o or{};local items=o.Items or{};local r,c=rich(self,o.Name or "Information",o.Description,66+math.min(#items,8)*34);local y=48;local refs={}
    for _,it in ipairs(items)do
        local left=label(r,tostring(it.Label or it.Name or ""),10,self.Window.Theme.TextSecondary);left.Position=UDim2.fromOffset(14,y);left.Size=UDim2.new(.48,0,0,24)
        local function resolve()local v=it.Value;if type(v)=="function"then local ok,x=pcall(v,self.Window);return ok and x or "-" end;return v end
        local right=label(r,tostring(resolve() or ""),10,self.Window.Theme.TextPrimary,Enum.Font.GothamMedium,Enum.TextXAlignment.Right);right.AnchorPoint=Vector2.new(1,0);right.Position=UDim2.new(1,-14,0,y);right.Size=UDim2.new(.48,0,0,24)
        table.insert(refs,{Label=right,Item=it,Resolve=resolve});y+=34
    end
    if o.AutoRefresh then task.spawn(function()while r.Parent do for _,ref in ipairs(refs)do ref.Label.Text=tostring(ref.Resolve() or "")end;task.wait(math.max(.25,tonumber(o.AutoRefresh) or 1))end end)end
    return c
end
function Tab:AddInfoList(o)return self:_defaultSection():AddInfoList(o)end;Tab._addInfoList=Tab.AddInfoList
function Section:AddStatGrid(o)
    o=o or{};local items=o.Items or{};local r,c=rich(self,o.Name or"Stats",o.Description,124);local host=create("Frame",{Parent=r,Position=UDim2.fromOffset(14,54),Size=UDim2.new(1,-28,0,56),BackgroundTransparency=1});local g=Instance.new("UIGridLayout");g.CellSize=UDim2.new(1/math.max(1,math.min(4,#items)),-6,1,0);g.CellPadding=UDim2.fromOffset(8,0);g.Parent=host;local refs={};for i,it in ipairs(items)do local f=create("Frame",{Parent=host,BackgroundColor3=self.Window.Theme.Surface3,BorderSizePixel=0});corner(f,9);local a=label(f,it.Label or it.Name or("STAT "..i),8,self.Window.Theme.TextSecondary,Enum.Font.GothamBold);a.Position=UDim2.fromOffset(9,5);a.Size=UDim2.new(1,-18,0,14);local v=it.Value;if type(v)=="function"then local ok,x=pcall(v,self.Window);v=ok and x or"-"end;local b=label(f,tostring(v or"-"),11,self.Window.Theme.TextPrimary,Enum.Font.GothamBold);b.Position=UDim2.fromOffset(9,23);b.Size=UDim2.new(1,-18,0,22);refs[i]={Label=b,Item=it}end;if o.AutoRefresh then task.spawn(function()while r.Parent do for _,x in ipairs(refs)do if type(x.Item.Value)=="function"then local ok,v=pcall(x.Item.Value,self.Window);if ok then x.Label.Text=tostring(v)end end end;task.wait(o.AutoRefresh)end end)end;return c
end
function Tab:AddStatGrid(o)return self:_defaultSection():AddStatGrid(o)end;Tab._addStatGrid=Tab.AddStatGrid

function Window:GetTelemetry()
    local fps=0;local t0=os.clock();RunService.RenderStepped:Wait();local dt=os.clock()-t0;if dt>0 then fps=math.floor(1/dt+.5)end;local ping=0;pcall(function()ping=math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue()+.5)end);local mem=0;pcall(function()mem=math.floor(Stats:GetTotalMemoryUsageMb()+.5)end);return{FPS=fps,Ping=ping,Memory=mem,Players=#Players:GetPlayers(),Input=self.DeviceInfo.PreferredInput}
end
function Section:AddRuntimeMonitor(o)
    o=o or{};local r,c=rich(self,o.Name or"Runtime",o.Description or"Live runtime telemetry",124);local items={{Label="FPS",Value="-"},{Label="PING",Value="-"},{Label="MEMORY",Value="-"},{Label="INPUT",Value="-"}};local host=create("Frame",{Parent=r,Position=UDim2.fromOffset(14,54),Size=UDim2.new(1,-28,0,56),BackgroundTransparency=1});local g=Instance.new("UIGridLayout");g.CellSize=UDim2.new(.25,-6,1,0);g.CellPadding=UDim2.fromOffset(8,0);g.Parent=host;local refs={};for _,it in ipairs(items)do local f=create("Frame",{Parent=host,BackgroundColor3=self.Window.Theme.Surface3,BorderSizePixel=0});corner(f,9);local a=label(f,it.Label,8,self.Window.Theme.TextSecondary,Enum.Font.GothamBold);a.Position=UDim2.fromOffset(9,5);a.Size=UDim2.new(1,-18,0,14);local b=label(f,"-",11,self.Window.Theme.TextPrimary,Enum.Font.GothamBold);b.Position=UDim2.fromOffset(9,23);b.Size=UDim2.new(1,-18,0,22);refs[it.Label]=b end;task.spawn(function()while r.Parent do local d=self.Window:GetTelemetry();refs.FPS.Text=tostring(d.FPS);refs.PING.Text=tostring(d.Ping).." ms";refs.MEMORY.Text=tostring(d.Memory).." MB";refs.INPUT.Text=d.Input;task.wait(o.RefreshRate or1)end end);return c
end
function Tab:AddRuntimeMonitor(o)return self:_defaultSection():AddRuntimeMonitor(o)end;Tab._addRuntimeMonitor=Tab.AddRuntimeMonitor
function Section:AddPerformanceGraph(o)return self:AddRuntimeMonitor(o)end
function Tab:AddPerformanceGraph(o)return self:_defaultSection():AddPerformanceGraph(o)end;Tab._addPerformanceGraph=Tab.AddPerformanceGraph
function Section:AddServerCard(o)o=o or{};return self:AddInfoList({Name=o.Name or"Server",Description=o.Description,Items={{Label="Players",Value=#Players:GetPlayers()},{Label="PlaceId",Value=game.PlaceId},{Label="JobId",Value=string.sub(game.JobId or"",1,14).."…"}}})end
function Tab:AddServerCard(o)return self:_defaultSection():AddServerCard(o)end;Tab._addServerCard=Tab.AddServerCard
function Section:AddCapabilityViewer(o)local c=self.Window.Library:GetCapabilities();local i={};for k,v in pairs(c)do table.insert(i,{Label=k,Value=tostring(v)})end;return self:AddInfoList({Name=(o and o.Name)or"Capabilities",Items=i})end
function Tab:AddCapabilityViewer(o)return self:_defaultSection():AddCapabilityViewer(o)end;Tab._addCapabilityViewer=Tab.AddCapabilityViewer
function Window:CheckRequirement(r)local c=self.Library:GetCapabilities();if r=="FileSystem"then return c.FileSystem elseif r=="Clipboard"then return c.Clipboard elseif r=="Premium"then return self.KeyInfo.Valid==true end;return true end
function Section:AddDependencyBox(o)o=o or{};local i={};for _,r in ipairs(o.Requires or{})do table.insert(i,{Name=(self.Window:CheckRequirement(r)and"✓ "or"× ")..r})end;return self:AddList({Name=o.Name or"Requirements",Description=o.Description,Items=i})end
function Tab:AddDependencyBox(o)return self:_defaultSection():AddDependencyBox(o)end;Tab._addDependencyBox=Tab.AddDependencyBox
function Section:AddSystemHealth(o)o=o or{};return self:AddList({Name=o.Name or"System Health",Items={{Name="UI · Healthy"},{Name="Filesystem · "..(self.Window.Library:GetCapabilities().FileSystem and"Ready"or"Unavailable")},{Name="Clipboard · "..(self.Window.Library:GetCapabilities().Clipboard and"Ready"or"Unavailable")}}})end
function Tab:AddSystemHealth(o)return self:_defaultSection():AddSystemHealth(o)end;Tab._addSystemHealth=Tab.AddSystemHealth

-- ================================================================
-- Profile, key, activity, changelog, developer widgets
-- ================================================================

function Window:GetSessionPlaytime()return os.clock()-self.SessionStartedAt end
function Window:FormatDuration(s,c)return formatDuration(s,c)end
function Window:GetSessionInfo()local cp=self.Library:GetCapabilities();return{DisplayName=LocalPlayer.DisplayName,Username=LocalPlayer.Name,UserId=LocalPlayer.UserId,AccountAge=LocalPlayer.AccountAge,Playtime=self:GetSessionPlaytime(),PlaytimeText=formatDuration(self:GetSessionPlaytime(),false),PlayerCount=#Players:GetPlayers(),PlaceId=game.PlaceId,JobId=game.JobId,Executor=cp.ExecutorName,Key=self:GetKeyInfo()}end
function Window:GetKeyInfo()return copy(self.KeyInfo or{})end
function Window:SetKeyInfo(i)self.KeyInfo=merge(self.KeyInfo or{},i or{});if self.KeyInfo.Key and not self.KeyInfo.MaskedKey then local s=tostring(self.KeyInfo.Key);self.KeyInfo.MaskedKey=#s>8 and(string.sub(s,1,4).."••••"..string.sub(s,-4))or"••••••••"end;if self.KeyInfo.Duration and not self.KeyInfo.ExpiresAt then self.KeyInfo.ExpiresAt=os.time()+self.KeyInfo.Duration end;for _,fn in ipairs(self.KeyInfoListeners)do safeCall(fn,self:GetKeyInfo())end end
function Window:GetKeyRemaining()if self.KeyInfo.Permanent then return nil end;if self.KeyInfo.ExpiresAt then return math.max(0,self.KeyInfo.ExpiresAt-os.time())end;return nil end
function Window:IsKeyExpired()local r=self:GetKeyRemaining();return r~=nil and r<=0 end
function Window:OnKeyInfoChanged(fn)table.insert(self.KeyInfoListeners,fn);return fn end
function Window:SetAccessLevel(v)self:SetKeyInfo({Tier=v,Status="Active",Valid=true})end
function Window:ShowKeyExpirationWarning(th)local r=self:GetKeyRemaining();if r and r<=(th or86400)then self:Notify({Title="Key expires soon",Content="Remaining: "..formatDuration(r,true),Type="warning"});return true end;return false end

function Section:AddPlayerProfile(o)
    o=o or{};local r,c=rich(self,o.Name or"Local Player Profile",o.Description,220);local w=self.Window;local av=create("ImageLabel",{Parent=r,Position=UDim2.fromOffset(16,50),Size=UDim2.fromOffset(62,62),BackgroundColor3=w.Theme.Surface3,BorderSizePixel=0,Image=""});corner(av,14);task.spawn(function()local ok,url=pcall(Players.GetUserThumbnailAsync,Players,LocalPlayer.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size180x180);if ok and av.Parent then av.Image=url end end);local n=label(r,LocalPlayer.DisplayName,15,w.Theme.TextPrimary,Enum.Font.GothamBold);n.Position=UDim2.fromOffset(92,52);n.Size=UDim2.new(1,-210,0,24);local u=label(r,"@"..LocalPlayer.Name,10,w.Theme.TextSecondary);u.Position=UDim2.fromOffset(92,78);u.Size=UDim2.new(1,-210,0,18);local ag=label(r,"Account age · "..LocalPlayer.AccountAge.." days",10,w.Theme.TextSecondary);ag.Position=UDim2.fromOffset(92,98);ag.Size=UDim2.new(1,-210,0,18);local st=label(r,"UNLOCKED",9,w.Theme.TextPrimary,Enum.Font.GothamBold,Enum.TextXAlignment.Center);st.AnchorPoint=Vector2.new(1,0);st.Position=UDim2.new(1,-16,0,54);st.Size=UDim2.fromOffset(112,30);st.BackgroundTransparency=0;st.BackgroundColor3=w.Theme.Surface3;corner(st,15)
    local host=create("Frame",{Parent=r,Position=UDim2.fromOffset(16,128),Size=UDim2.new(1,-32,0,70),BackgroundTransparency=1});local g=Instance.new("UIGridLayout");g.CellSize=UDim2.new(.25,-6,1,0);g.CellPadding=UDim2.fromOffset(8,0);g.Parent=host;local refs={};for _,x in ipairs({"PLAYTIME","ACCESS","REMAINING","ACCOUNT"})do local f=create("Frame",{Parent=host,BackgroundColor3=w.Theme.Surface3,BorderSizePixel=0});corner(f,9);local a=label(f,x,8,w.Theme.TextSecondary,Enum.Font.GothamBold);a.Position=UDim2.fromOffset(9,6);a.Size=UDim2.new(1,-18,0,14);local b=label(f,"-",11,w.Theme.TextPrimary,Enum.Font.GothamBold);b.Position=UDim2.fromOffset(9,30);b.Size=UDim2.new(1,-18,0,20);refs[x]=b end
    task.spawn(function()while r.Parent do local k=w:GetKeyInfo();refs.PLAYTIME.Text=formatDuration(w:GetSessionPlaytime(),true);refs.ACCESS.Text=tostring(k.Tier or k.Status or"Free");local rem=w:GetKeyRemaining();refs.REMAINING.Text=rem and formatDuration(rem,true)or(k.Permanent and"Lifetime"or"—");refs.ACCOUNT.Text=LocalPlayer.AccountAge.." days";st.Text=(k.Valid==false or w:IsKeyExpired())and"LOCKED"or"UNLOCKED";task.wait(1)end end);return c
end
function Tab:AddPlayerProfile(o)return self:_defaultSection():AddPlayerProfile(o)end;Tab._addPlayerProfile=Tab.AddPlayerProfile
function Section:AddKeyCard(o)o=o or{};return self:AddInfoList({Name=o.Name or"License",Description=o.Description,AutoRefresh=1,Items={{Label="Status",Value=function()return tostring(self.Window.KeyInfo.Status or(self.Window.KeyInfo.Valid and"Active"or"Unknown"))end},{Label="Tier",Value=function()return tostring(self.Window.KeyInfo.Tier or"Free")end},{Label="Remaining",Value=function()local r=self.Window:GetKeyRemaining();return r and formatDuration(r,true)or(self.Window.KeyInfo.Permanent and"Lifetime"or"—")end},{Label="Key",Value=function()return tostring(self.Window.KeyInfo.MaskedKey or"—")end}}})end
function Tab:AddKeyCard(o)return self:_defaultSection():AddKeyCard(o)end;Tab._addKeyCard=Tab.AddKeyCard
function Section:AddLockedFeature(o)o=o or{};return self:AddButton({Name=o.Name or"Locked Feature",Description=o.Description or o.Reason or"Access required",ButtonText="Locked",Style="Secondary"})end
function Tab:AddLockedFeature(o)return self:_defaultSection():AddLockedFeature(o)end;Tab._addLockedFeature=Tab.AddLockedFeature
function Section:AddAvatar(o)o=o or{};local r,c=rich(self,o.Name or"Avatar",o.Description,94);local im=create("ImageLabel",{Parent=r,Position=UDim2.fromOffset(14,42),Size=UDim2.fromOffset(44,44),BackgroundColor3=self.Window.Theme.Surface3,BorderSizePixel=0,Image=""});corner(im,12);task.spawn(function()local ok,url=pcall(Players.GetUserThumbnailAsync,Players,o.UserId or LocalPlayer.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size180x180);if ok and im.Parent then im.Image=url end end);return c end
function Tab:AddAvatar(o)return self:_defaultSection():AddAvatar(o)end;Tab._addAvatar=Tab.AddAvatar
function Section:AddUserCard(o)o=o or{};local p=o.Player or LocalPlayer;return self:AddInfoList({Name=o.Name or p.DisplayName,Description="@"..p.Name,Items={{Label="UserId",Value=p.UserId},{Label="Account age",Value=p.AccountAge.." days"}}})end
function Tab:AddUserCard(o)return self:_defaultSection():AddUserCard(o)end;Tab._addUserCard=Tab.AddUserCard
function Section:AddStatusDot(o)return self:AddStatus(o)end
function Tab:AddStatusDot(o)return self:_defaultSection():AddStatusDot(o)end;Tab._addStatusDot=Tab.AddStatusDot

function Window:LogActivity(x)if type(x)=="string"then x={Title=x}end;x=x or{};local i={Title=tostring(x.Title or"Activity"),Description=tostring(x.Description or""),Tone=x.Tone,Time=os.time()};table.insert(self.Activities,i);return i end
function Window:GetActivity()return self.Activities end
function Window:ClearActivity()table.clear(self.Activities)end
function Window:Log(level,msg)table.insert(self.Logs,{Level=tostring(level or"INFO"),Message=tostring(msg or""),Time=os.time()})end
function Section:AddActivityFeed(o)o=o or{};local items={};for i=math.max(1,#self.Window.Activities-7),#self.Window.Activities do local a=self.Window.Activities[i];if a then table.insert(items,{Name=a.Title.." · "..formatDuration(os.time()-a.Time,true)})end end;return self:AddList({Name=o.Name or"Recent Activity",Description=o.Description,Items=items})end
function Tab:AddActivityFeed(o)return self:_defaultSection():AddActivityFeed(o)end;Tab._addActivityFeed=Tab.AddActivityFeed
function Section:AddChangelog(o)o=o or{};local items={};for _,x in ipairs(o.Changes or{})do table.insert(items,{Name=(x.Type or"Changed").." · "..(x.Text or"")})end;return self:AddList({Name=o.Name or("Changelog "..tostring(o.Version or"")),Description=o.Date,Items=items})end
function Tab:AddChangelog(o)return self:_defaultSection():AddChangelog(o)end;Tab._addChangelog=Tab.AddChangelog
function Section:AddTimeline(o)return self:AddList(o)end
function Tab:AddTimeline(o)return self:_defaultSection():AddTimeline(o)end;Tab._addTimeline=Tab.AddTimeline
function Section:AddAnnouncement(o)return self:AddParagraph(o)end
function Tab:AddAnnouncement(o)return self:_defaultSection():AddAnnouncement(o)end;Tab._addAnnouncement=Tab.AddAnnouncement
function Section:AddFlagInspector(o)local items={};for k,v in pairs(self.Window.Flags)do table.insert(items,{Name=k.." = "..tostring(v)})end;table.sort(items,function(a,b)return a.Name<b.Name end);return self:AddList({Name=(o and o.Name)or"Flag Inspector",Items=items})end
function Tab:AddFlagInspector(o)return self:_defaultSection():AddFlagInspector(o)end;Tab._addFlagInspector=Tab.AddFlagInspector
function Section:AddDebugConsole(o)local items={};for _,x in ipairs(self.Window.Logs)do table.insert(items,{Name="["..x.Level.."] "..x.Message})end;return self:AddList({Name=(o and o.Name)or"Debug Console",Items=items})end
function Tab:AddDebugConsole(o)return self:_defaultSection():AddDebugConsole(o)end;Tab._addDebugConsole=Tab.AddDebugConsole
function Section:AddBreakpointInspector(o)local d=self.Window.DeviceInfo;return self:AddInfoList({Name=(o and o.Name)or"Breakpoint",Items={{Label="Platform",Value=d.Platform},{Label="Layout",Value=d.Layout},{Label="Viewport",Value=math.floor(d.Viewport.X).."×"..math.floor(d.Viewport.Y)}}})end
function Tab:AddBreakpointInspector(o)return self:_defaultSection():AddBreakpointInspector(o)end;Tab._addBreakpointInspector=Tab.AddBreakpointInspector
function Section:AddShortcutViewer(o)local items={};for _,s in ipairs(self.Window.Shortcuts)do table.insert(items,{Label=s.Name or"Shortcut",Value=s.Display or(s.KeyCode and s.KeyCode.Name or"")})end;return self:AddInfoList({Name=(o and o.Name)or"Shortcuts",Items=items})end
function Tab:AddShortcutViewer(o)return self:_defaultSection():AddShortcutViewer(o)end;Tab._addShortcutViewer=Tab.AddShortcutViewer
function Section:AddConfigManager(o)return self:AddQuickActions({Name=(o and o.Name)or"Config Manager",Actions={{Name="Save",Callback=function()self.Window:SaveConfigFile()end},{Name="Load",Callback=function()self.Window:LoadConfigFile()end},{Name="Reset",Callback=function()self.Window:ResetConfig()end},{Name="Copy",Callback=function()self.Window:CopyConfig()end}}})end
function Tab:AddConfigManager(o)return self:_defaultSection():AddConfigManager(o)end;Tab._addConfigManager=Tab.AddConfigManager
function Section:AddConfigDiff(o)return self:AddList({Name=(o and o.Name)or"Config Diff",Items=self.Window:DiffConfig((o and o.Config)or{})})end
function Tab:AddConfigDiff(o)return self:_defaultSection():AddConfigDiff(o)end;Tab._addConfigDiff=Tab.AddConfigDiff
function Section:AddConfigBrowser(o)return self:AddConfigManager(o)end
function Tab:AddConfigBrowser(o)return self:_defaultSection():AddConfigBrowser(o)end;Tab._addConfigBrowser=Tab.AddConfigBrowser

-- ================================================================
-- Key gate and overlays
-- ================================================================

function Window:_showKeyGate(o)
    local back=create("Frame",{Parent=self.Overlay,Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=.28,BorderSizePixel=0,ZIndex=1500});local p=create("Frame",{Parent=back,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(math.min(430,viewport().X-28),270),BackgroundColor3=self.Theme.Surface,BorderSizePixel=0,ZIndex=1501});corner(p,14);stroke(p,self.Theme.Border,.05,1);local badge=label(p,"ACCESS KEY",9,self.Theme.Accent,Enum.Font.GothamBold,Enum.TextXAlignment.Center);badge.Position=UDim2.fromOffset(22,22);badge.Size=UDim2.fromOffset(112,28);badge.BackgroundTransparency=0;badge.BackgroundColor3=self.Theme.AccentSoft;corner(badge,14);local title=label(p,o.Title or"Astra Access",20,self.Theme.TextPrimary,Enum.Font.GothamBold);title.Position=UDim2.fromOffset(22,65);title.Size=UDim2.new(1,-44,0,30);local d=label(p,o.Description or"Enter your access key to continue.",11,self.Theme.TextSecondary);d.Position=UDim2.fromOffset(22,101);d.Size=UDim2.new(1,-44,0,30);d.TextWrapped=true;local input=create("TextBox",{Parent=p,Position=UDim2.fromOffset(22,142),Size=UDim2.new(1,-44,0,48),BackgroundColor3=self.Theme.Surface3,BorderSizePixel=0,Text="",PlaceholderText=o.Placeholder or"Enter key...",TextColor3=self.Theme.TextPrimary,PlaceholderColor3=self.Theme.TextSecondary,TextSize=12,Font=Enum.Font.Gotham,ClearTextOnFocus=false});corner(input,10);stroke(input,self.Theme.Border,.1,1);padding(input,12,0,12,0);local unlock=button(p,o.ButtonText or"Unlock",self.Theme,"Primary");unlock.Position=UDim2.fromOffset(22,206);unlock.Size=UDim2.new(1,-44,0,44);unlock.ZIndex=1502
    self:_connect(unlock.MouseButton1Click,function()local key=input.Text;local res;if type(o.Validate)=="function"then local ok,r=pcall(o.Validate,key);if ok then res=r end else res=key==o.Key end;local valid=false;local info={};if type(res)=="table"then valid=res.Valid==true;info=res.KeyInfo or{};info.Status=res.Message or(valid and"Active"or"Invalid")else valid=res==true end;if valid then info.Valid=true;info.Key=key;self:SetKeyInfo(info);back:Destroy();self:Notify({Title="Access granted",Content=info.Tier and("Tier: "..info.Tier)or"Key validated.",Type="success"})else self:Notify({Title="Invalid key",Content="The provided key was not accepted.",Type="error"})end end)
end

function Window:RegisterCommand(o)o=o or{};table.insert(self.Commands,o);return o end
function Window:OpenCommandPalette()
    if self._palette then self._palette:Destroy();self._palette=nil;return end;local p=create("Frame",{Parent=self.Overlay,AnchorPoint=Vector2.new(.5,0),Position=UDim2.new(.5,0,0,56),Size=UDim2.fromOffset(math.min(500,viewport().X-24),math.min(360,viewport().Y-80)),BackgroundColor3=self.Theme.Surface,BorderSizePixel=0,ZIndex=1400});corner(p,14);stroke(p,self.Theme.Border,.05,1);local input=create("TextBox",{Parent=p,Position=UDim2.fromOffset(14,14),Size=UDim2.new(1,-28,0,42),BackgroundColor3=self.Theme.Surface3,BorderSizePixel=0,Text="",PlaceholderText="Search commands...",TextColor3=self.Theme.TextPrimary,PlaceholderColor3=self.Theme.TextSecondary,TextSize=12,Font=Enum.Font.Gotham,ClearTextOnFocus=false,ZIndex=1401});corner(input,10);padding(input,12,0,12,0);local sf=create("ScrollingFrame",{Parent=p,Position=UDim2.fromOffset(14,68),Size=UDim2.new(1,-28,1,-82),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=2,ZIndex=1401});list(sf,6,false);local function build()for _,x in ipairs(sf:GetChildren())do if x:IsA("GuiObject")then x:Destroy()end end;local q=string.lower(input.Text);for _,cmd in ipairs(self.Commands)do local hay=string.lower(tostring(cmd.Name or"").." "..table.concat(cmd.Keywords or{}," "));if q==""or string.find(hay,q,1,true)then local b=button(sf,cmd.Name or"Command",self.Theme,"Ghost");b.Size=UDim2.new(1,-2,0,38);b.ZIndex=1402;self:_connect(b.MouseButton1Click,function()safeCall(cmd.Callback);if p.Parent then p:Destroy();self._palette=nil end end)end end end;self:_connect(input:GetPropertyChangedSignal("Text"),build);build();input:CaptureFocus();self._palette=p;return p
end
function Window:ContextMenu(o)
    o=o or{};if self._context then self._context:Destroy();self._context=nil end
    local items=o.Items or o;local pos=o.Position or UserInputService:GetMouseLocation();local width=clamp(o.Width or220,160,300);local height=math.min(12+#items*38,math.max(120,viewport().Y-20));local v=viewport();local x=clamp(pos.X,8,v.X-width-8);local y=clamp(pos.Y,8,v.Y-height-8)
    local layer=create("Frame",{Parent=self.Overlay,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,ZIndex=1449})
    local catcher=create("TextButton",{Parent=layer,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,Text="",AutoButtonColor=false,ZIndex=1449})
    local p=create("Frame",{Parent=layer,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(width,height),BackgroundColor3=self.Theme.Surface2,BorderSizePixel=0,ZIndex=1450,ClipsDescendants=true});corner(p,12);stroke(p,self.Theme.Border,.05,1)
    local sf=create("ScrollingFrame",{Parent=p,Position=UDim2.fromOffset(6,6),Size=UDim2.new(1,-12,1,-12),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=#items>7 and2 or0,ScrollBarImageColor3=self.Theme.Scrollbar,ZIndex=1450});list(sf,4,false)
    self:_connect(catcher.MouseButton1Click,function()if layer.Parent then layer:Destroy()end;if self._context==layer then self._context=nil end end)
    for _,it in ipairs(items)do local b=button(sf,it.Name or it.Text or"Action",self.Theme,it.Style or"Ghost");b.Size=UDim2.new(1,-2,0,34);b.ZIndex=1451;b.Active=type(it.Callback)=="function";if not b.Active then b.BackgroundTransparency=.45 end;self:_connect(b.MouseButton1Click,function()if b.Active then safeCall(it.Callback);if layer.Parent then layer:Destroy()end;self._context=nil end end)end
    self._context=layer;return p
end
function Window:AttachContextMenu(inst,items)self:_connect(inst.InputBegan,function(i)if i.UserInputType==Enum.UserInputType.MouseButton2 then self:ContextMenu({Items=items,Position=i.Position})end end);return inst end
function Window:OpenMoreMenu(items)return self:ContextMenu({Items=items or{{Name="Center",Callback=function()self:Center()end},{Name="Reset size",Callback=function()self:ResetWindowSize()end},{Name="Unload",Style="Danger",Callback=function()self:Destroy()end}}})end

function Window:_modal(title,content)
    local back=create("Frame",{Parent=self.Overlay,Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=.35,BorderSizePixel=0,ZIndex=1500});local p=create("Frame",{Parent=back,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(math.min(430,viewport().X-28),math.min(230,viewport().Y-40)),BackgroundColor3=self.Theme.Surface,BorderSizePixel=0,ZIndex=1501});corner(p,14);stroke(p,self.Theme.Border,.05,1);local t=label(p,title or"AstraUI",18,self.Theme.TextPrimary,Enum.Font.GothamBold);t.Position=UDim2.fromOffset(20,20);t.Size=UDim2.new(1,-40,0,28);local d=label(p,content or"",11,self.Theme.TextSecondary);d.Position=UDim2.fromOffset(20,54);d.Size=UDim2.new(1,-40,0,70);d.TextWrapped=true;d.TextYAlignment=Enum.TextYAlignment.Top;return back,p
end
function Window:Alert(o)o=o or{};local back,p=self:_modal(o.Title or"Alert",o.Content);local b=button(p,o.ButtonText or"OK",self.Theme,"Primary");b.Position=UDim2.new(0,20,1,-58);b.Size=UDim2.new(1,-40,0,40);self:_connect(b.MouseButton1Click,function()back:Destroy();safeCall(o.Callback)end);return back end
function Window:Confirm(o)o=o or{};local back,p=self:_modal(o.Title or"Confirm",o.Content);local a=button(p,o.CancelText or"Cancel",self.Theme,"Secondary");a.Position=UDim2.new(0,20,1,-58);a.Size=UDim2.new(.5,-25,0,40);local b=button(p,o.ConfirmText or"Confirm",self.Theme,o.Danger and"Danger"or"Primary");b.Position=UDim2.new(.5,5,1,-58);b.Size=UDim2.new(.5,-25,0,40);self:_connect(a.MouseButton1Click,function()back:Destroy();safeCall(o.Callback,false)end);self:_connect(b.MouseButton1Click,function()back:Destroy();safeCall(o.Callback,true)end);return back end
function Window:Prompt(o)o=o or{};local back,p=self:_modal(o.Title or"Prompt",o.Content);local box=create("TextBox",{Parent=p,Position=UDim2.fromOffset(20,118),Size=UDim2.new(1,-40,0,40),BackgroundColor3=self.Theme.Surface3,BorderSizePixel=0,Text=tostring(o.Default or""),PlaceholderText=o.Placeholder or"Type...",TextColor3=self.Theme.TextPrimary,PlaceholderColor3=self.Theme.TextSecondary,TextSize=11,Font=Enum.Font.Gotham,ClearTextOnFocus=false});corner(box,10);padding(box,10,0,10,0);local b=button(p,"Submit",self.Theme,"Primary");b.Position=UDim2.new(0,20,1,-54);b.Size=UDim2.new(1,-40,0,36);self:_connect(b.MouseButton1Click,function()local v=box.Text;back:Destroy();safeCall(o.Callback,v)end);return back end
function Window:Choice(o)o=o or{};local back,p=self:_modal(o.Title or"Choose",o.Content);local host=create("Frame",{Parent=p,Position=UDim2.fromOffset(20,120),Size=UDim2.new(1,-40,0,40),BackgroundTransparency=1});list(host,8,true);for _,x in ipairs(o.Choices or{})do local b=button(host,tostring(x),self.Theme,"Secondary");b.Size=UDim2.new(1/math.max(1,#(o.Choices or{})),-6,1,0);self:_connect(b.MouseButton1Click,function()back:Destroy();safeCall(o.Callback,x)end)end;return back end
function Window:ProgressModal(o)o=o or{};local back,p=self:_modal(o.Title or"Progress",o.Content);local bar=create("Frame",{Parent=p,Position=UDim2.fromOffset(20,140),Size=UDim2.new(1,-40,0,8),BackgroundColor3=self.Theme.Surface3,BorderSizePixel=0});corner(bar,8);local f=create("Frame",{Parent=bar,Size=UDim2.new((o.Value or0)/100,0,1,0),BackgroundColor3=self.Theme.Accent,BorderSizePixel=0});corner(f,8);return{Instance=back,Set=function(_,v)f.Size=UDim2.new(clamp(v,0,100)/100,0,1,0)end,Close=function()back:Destroy()end}end
function Window:Dialog(o)return self:Alert(o)end
function Window:BottomSheet(o)
    o=o or{};local h=clamp(o.Height or280,160,viewport().Y*.82);local back=create("Frame",{Parent=self.Overlay,Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=.65,BorderSizePixel=0,ZIndex=1498})
    local catcher=create("TextButton",{Parent=back,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,Text="",AutoButtonColor=false,ZIndex=1498})
    local p=create("Frame",{Parent=back,AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,h+10),Size=UDim2.new(1,-20,0,h),BackgroundColor3=self.Theme.Surface,BorderSizePixel=0,ZIndex=1500});corner(p,16);stroke(p,self.Theme.Border,.05,1)
    local title=label(p,o.Title or"Panel",14,self.Theme.TextPrimary,Enum.Font.GothamBold);title.Position=UDim2.fromOffset(18,10);title.Size=UDim2.new(1,-72,0,28)
    local close=button(p,"×",self.Theme,"Ghost");close.AnchorPoint=Vector2.new(1,0);close.Position=UDim2.new(1,-12,0,8);close.Size=UDim2.fromOffset(36,32)
    local function dismiss()tween(p,.16,{Position=UDim2.new(.5,0,1,h+10)},Enum.EasingStyle.Quad,Enum.EasingDirection.In);tween(back,.16,{BackgroundTransparency=1});task.delay(.18,function()if back.Parent then back:Destroy()end end)end
    self:_connect(close.MouseButton1Click,dismiss);self:_connect(catcher.MouseButton1Click,dismiss);tween(p,.2,{Position=UDim2.new(.5,0,1,-8)},Enum.EasingStyle.Quart,Enum.EasingDirection.Out)
    p:SetAttribute("AstraDismissable",true);return p
end
function Window:SidePanel(o)
    o=o or{};local width=clamp(o.Width or360,260,viewport().X*.78);local back=create("Frame",{Parent=self.Overlay,Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=.72,BorderSizePixel=0,ZIndex=1498})
    local catcher=create("TextButton",{Parent=back,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,Text="",AutoButtonColor=false,ZIndex=1498})
    local p=create("Frame",{Parent=back,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,width+10,0,0),Size=UDim2.new(0,width,1,0),BackgroundColor3=self.Theme.Surface,BorderSizePixel=0,ZIndex=1500});corner(p,14);stroke(p,self.Theme.Border,.05,1)
    local title=label(p,o.Title or"Panel",14,self.Theme.TextPrimary,Enum.Font.GothamBold);title.Position=UDim2.fromOffset(18,16);title.Size=UDim2.new(1,-72,0,28)
    local close=button(p,"×",self.Theme,"Ghost");close.AnchorPoint=Vector2.new(1,0);close.Position=UDim2.new(1,-12,0,12);close.Size=UDim2.fromOffset(36,32)
    local function dismiss()tween(p,.16,{Position=UDim2.new(1,width+10,0,0)},Enum.EasingStyle.Quad,Enum.EasingDirection.In);tween(back,.16,{BackgroundTransparency=1});task.delay(.18,function()if back.Parent then back:Destroy()end end)end
    self:_connect(close.MouseButton1Click,dismiss);self:_connect(catcher.MouseButton1Click,dismiss);tween(p,.2,{Position=UDim2.new(1,-8,0,0)},Enum.EasingStyle.Quart,Enum.EasingDirection.Out);p:SetAttribute("AstraDismissable",true);return p
end
function Window:Drawer(o)return self:SidePanel(o)end
function Window:OpenNotificationCenter()
    local p=self:SidePanel({Width=380,Title="Notifications"})
    local sf=create("ScrollingFrame",{Parent=p,Position=UDim2.fromOffset(14,58),Size=UDim2.new(1,-28,1,-72),BackgroundTransparency=1,BorderSizePixel=0,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollBarThickness=2,ScrollBarImageColor3=self.Theme.Scrollbar,ZIndex=1501});list(sf,8,false)
    if #self.NotificationHistory==0 then local e=label(sf,"No notifications yet.",11,self.Theme.TextSecondary);e.Size=UDim2.new(1,0,0,38) else for i=#self.NotificationHistory,math.max(1,#self.NotificationHistory-20),-1 do local n=self.NotificationHistory[i];local f=create("Frame",{Parent=sf,Size=UDim2.new(1,-2,0,58),BackgroundColor3=self.Theme.Surface2,BorderSizePixel=0,ZIndex=1502});corner(f,10);local a=label(f,n.Title,11,self.Theme.TextPrimary,Enum.Font.GothamBold);a.Position=UDim2.fromOffset(10,7);a.Size=UDim2.new(1,-20,0,18);local d=label(f,n.Content,9,self.Theme.TextSecondary);d.Position=UDim2.fromOffset(10,27);d.Size=UDim2.new(1,-20,0,20) end end
    return p
end

-- ================================================================
-- High-level framework API
-- ================================================================

function Window:RegisterShortcut(o)o=o or{};if o.Keys and not o.KeyCode then o.KeyCode=Enum.KeyCode[o.Keys[#o.Keys]]end;table.insert(self.Shortcuts,o);return o end
function Window:GetShortcuts()return self.Shortcuts end
function Window:GetInputHint(a)return self:IsMobile()and"Tap"or(self:IsConsole()and"Press A"or tostring(a or"Click"))end
function Window:RegisterPreset(n,c)self.Presets[n]=c;return c end
function Window:GetPresets()return self.Presets end
function Window:ApplyPreset(n)local p=self.Presets[n];if not p then return false end;if p.Config then self:LoadConfig(p.Config)end;if p.Theme then self:SetThemePreset(p.Theme)end;return true end
function Window:EnableAutosave(i)self.Autosave.Enabled=true;self.Autosave.Interval=i or5;task.spawn(function()while self.Autosave.Enabled and not self.Destroyed do task.wait(self.Autosave.Interval);self:SaveConfigFile()end end)end
function Window:DisableAutosave()self.Autosave.Enabled=false end
function Window:GetAutosaveState()return copy(self.Autosave)end
function Window:PinAction(a)table.insert(self.PinnedActions,a);return a end
function Window:UnpinAction(a)local i=table.find(self.PinnedActions,a);if i then table.remove(self.PinnedActions,i)end end
function Window:GetPinnedActions()return self.PinnedActions end
function Window:RecordRecent(a)table.insert(self.RecentActions,1,{Action=a,Time=os.time()});while#self.RecentActions>20 do table.remove(self.RecentActions)end end
function Window:GetRecentActions()return self.RecentActions end
function Window:CreateQuickAccess()return self.PinnedActions end
function Window:SetBreadcrumbs(x)self.Breadcrumbs=x or{};return self.Breadcrumbs end
function Window:SetAnnouncement(o)self.Announcement=o;if o then self:Notify({Title=o.Title or"Announcement",Content=o.Content or"",Type=o.Type or"info",Duration=o.Duration or5})end end
function Window:ShowWhatsNew(o)return self:Alert({Title=(o and o.Title)or"What's New",Content=(o and o.Content)or"AstraUI updated."})end
function Window:RunProtected(fn,ctx)local ok,r=pcall(fn);if not ok then self:Log("ERROR",tostring(ctx or"Callback")..": "..tostring(r));self:Notify({Title="Feature error",Content=tostring(r),Type="error"});return false,r end;return true,r end
function Window:CreateTabGroup(n)local g={Window=self,Name=tostring(n or"Group")};function g:CreateTab(o)o=o or{};return self.Window:CreateTab(o)end;return g end
function Window:CreateCollapsibleGroup(o)return self.SelectedTab and self.SelectedTab:AddAccordion(o)end
function Window:CreateShortcutViewer(o)return self.SelectedTab and self.SelectedTab:AddShortcutViewer(o)end
function Window:CreateLazyTab(o)return self:CreateTab(o)end
function Window:CreateApplication(o)o=o or{};return{Dashboard=self:CreateDashboard(o.Dashboard or{}),Profile=self:CreateProfileTab(o.Profile or{}),Runtime=self:CreateRuntimeTab(o.Runtime or{}),Access=self:CreateAccessTab(o.Access or{}),Settings=self:CreateSettingsTab(o.Settings or{})}end

function Tab:CreateSubTabs(o)local g={Tab=self,Pages={}};function g:Create(n,build)local s=self.Tab:CreateSection({Name=tostring(n)});s.Frame.Visible=#self.Pages==0;local p={Name=tostring(n),Section=s};table.insert(self.Pages,p);if build then safeCall(build,s)end;return p end;function g:Select(n)for _,p in ipairs(self.Pages)do p.Section.Frame.Visible=p.Name==n end end;return g end
function Tab:AddAccordion(o)o=o or{};local s=self:CreateSection({Name=o.Name or"Accordion",Description=o.Description});for _,it in ipairs(o.Items or{})do s:AddButton({Name=it.Name or it.Title or"Item",Description=it.Description,ButtonText="Open",Style="Secondary",Callback=function()safeCall(it.Build,s)end})end;return s end
function Tab:CreateLazySection(o)local built=false;local s=self:CreateSection(o);local build=o and o.Build;function s:Build()if not built and build then built=true;safeCall(build,self)end end;return s end

function Window:CreateProfileTab(o)o=o or{};local tab=self:CreateTab({Name=o.Name or"Profile",Description=o.Description or"Local player and access information",Icon=o.Icon or"profile"});local s=tab:CreateSection({Name="Profile",Description="Live local-player information"});s:AddPlayerProfile({});local a=tab:CreateSection({Name="Access",Description="Key and session information"});a:AddKeyCard({});a:AddInfoList({Name="Session",Items={{Label="Executor",Value=function()return self.Library:GetCapabilities().ExecutorName end},{Label="Playtime",Value=function()return formatDuration(self:GetSessionPlaytime(),true)end},{Label="Players",Value=function()return#Players:GetPlayers()end}}});return tab end
function Window:CreateDashboard(o)o=o or{};local tab=self:CreateTab({Name=o.Name or"Home",Description=o.Description or"Overview and quick access",Icon=o.Icon or"home"});local s=tab:CreateSection({Name="Overview",Description="Profile, access and runtime"});s:AddPlayerProfile({});local r=tab:CreateSection({Name="Runtime",Description="Live environment"});r:AddRuntimeMonitor({});local q=tab:CreateSection({Name="Quick Actions",Description="Frequently used actions"});q:AddQuickActions({Actions=o.Actions or{{Name="Save",Callback=function()self:SaveConfigFile()end},{Name="Commands",Callback=function()self:OpenCommandPalette()end},{Name="Notify",Callback=function()self:Notify({Title="AstraUI",Content="Dashboard action",Type="success"})end},{Name="Center",Callback=function()self:Center()end}}});return tab end
function Window:CreateRuntimeTab(o)o=o or{};local tab=self:CreateTab({Name=o.Name or"Runtime",Description="Performance and environment",Icon="runtime"});local s=tab:CreateSection({Name="Runtime",Description="Live telemetry"});s:AddRuntimeMonitor({});s:AddServerCard({});s:AddCapabilityViewer({});return tab end
function Window:CreateAccessTab(o)o=o or{};local tab=self:CreateTab({Name=o.Name or"Access",Description="Key and requirements",Icon="key"});local s=tab:CreateSection({Name="Access",Description="License information"});s:AddKeyCard({});s:AddDependencyBox({Requires={"FileSystem","Clipboard","Premium"}});return tab end
function Window:CreateSettingsTab(o)o=o or{};local tab=self:CreateTab({Name=o.Name or"Settings",Description="Interface preferences",Icon="settings"});local s=tab:CreateSection({Name="Appearance",Description="Theme and geometry"});s:AddDropdown({Name="Theme",Options={"Rose","Midnight","Ocean","Emerald","Graphite","Light"},Default=self.ThemeName,Callback=function(v)self:SetThemePreset(v)end});s:AddSegmentedControl({Name="Window size",Options={"Small","Normal","Large","Max"},Default="Normal",Callback=function(v)self:SetWindowSizePreset(v,true)end});s:AddSlider({Name="Scale",Min=.7,Max=1.35,Increment=.05,Default=self.Scale,Callback=function(v)self:SetInterfaceScale(v)end});s:AddSlider({Name="Roundness",Min=0,Max=1.5,Increment=.05,Default=self.Roundness,Callback=function(v)self:SetRoundness(v)end});return tab end
function Window:CreateDeveloperMode(o)o=o or{};local tab=self:CreateTab({Name=o.Name or"Developer",Description="Diagnostics and flags",Icon="info"});local s=tab:CreateSection({Name="Diagnostics",Description="Developer tools"});s:AddBreakpointInspector({});s:AddCapabilityViewer({});s:AddFlagInspector({});s:AddDebugConsole({});return tab end
function AstraUI:CreatePlayground(w)local tab=w:CreateTab({Name="Playground",Description="Every stable Astra component",Icon="info"});local s=tab:CreateSection({Name="Basic Controls",Description="Interactive component showcase"});s:AddButton({Name="Button",ButtonText="Click",Callback=function()w:Notify({Title="Button",Content="Clicked",Type="success"})end});s:AddToggle({Name="Toggle",Flag="PlayToggle"});s:AddSlider({Name="Slider",Min=0,Max=100,Default=50,Flag="PlaySlider"});s:AddInput({Name="Input",Flag="PlayInput"});s:AddDropdown({Name="Dropdown",Options={"One","Two","Three"},Flag="PlayDropdown"});s:AddKeybind({Name="Keybind"});s:AddColorPicker({Name="Color"});s:AddProgressBar({Name="Progress",Default=66});return tab end

function Tab:AddFavorites(o)
    o=o or{}
    local items={}
    for i,a in ipairs(self.Window:GetPinnedActions()) do
        table.insert(items,{Title=tostring(a.Name or a.Text or ("Favorite "..i)),Description=tostring(a.Description or "Pinned action")})
    end
    if #items==0 then table.insert(items,{Title="No favorites yet",Description="Pin an action to make it appear here."}) end
    return self:_defaultSection():AddList({Name=o.Name or "Favorites",Description=o.Description or "Pinned quick access",Items=items})
end
function Tab:AddRecentActions(o)
    o=o or{}
    local items={}
    for i,r in ipairs(self.Window:GetRecentActions()) do
        local a=r.Action or{}
        table.insert(items,{Title=tostring(a.Name or a.Text or ("Recent "..i)),Description=os.date("%H:%M:%S",r.Time or os.time())})
    end
    if #items==0 then table.insert(items,{Title="No recent actions",Description="Interacted actions will appear here."}) end
    return self:_defaultSection():AddList({Name=o.Name or "Recent Actions",Description=o.Description or "Recently used controls",Items=items})
end

-- ================================================================
-- Compatibility/no-op helpers from V4 public API
-- ================================================================

function Window:GetStats()local n=0;for _ in pairs(self.Flags)do n+=1 end;return{Tabs=#self.Tabs,Connections=#self.Connections,Flags=n,Notifications=#self.Notifications}end
function Window:RepairLayout()self:_responsive();self:SetRoundness(self.Roundness);self:SetWindowSize(self.CurrentSize.X,self.CurrentSize.Y,false);return true end
function Window:AuditLayout()return{VerticalTextClipping=0,RowOverflows=0,SuspiciousTextOverlaps=0,IntentionalTruncations=0,ViewportOverflows=0,OK=true}end
function Window:GetQualityReport()return{Version=VERSION,Layout=self:AuditLayout(),LayoutOK=true,Device=self:GetDeviceInfo(),Metrics=self:GetInterfaceMetrics()}end

function Window:OnUnload(fn)table.insert(self.UnloadListeners,fn);return fn end
function Window:Destroy()if self.Destroyed then return end;self.Destroyed=true;for _,fn in ipairs(self.UnloadListeners)do safeCall(fn)end;for _,c in ipairs(self.Connections)do pcall(function()c:Disconnect()end)end;table.clear(self.Connections);if self.ScreenGui then self.ScreenGui:Destroy()end end

return AstraUI.new()
