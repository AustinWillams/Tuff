local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local Workspace = game:GetService("Workspace")

local Module = {
    shared = nil,
    _initialized = false,
    _enabled = true,
    _teamCheck = false,
    _playerBoxEnabled = true,
    _skeletonEnabled = false,
    _objectBoxEnabled = true,
    _playerColor = Color3.fromRGB(255, 50, 50),
    _skeletonColor = Color3.fromRGB(210, 50, 80),
    _droneColor = Color3.fromRGB(255, 140, 0),
    _claymoreColor = Color3.fromRGB(255, 0, 0),
    _grenadeColor = Color3.fromRGB(255, 50, 50),
    _allyColor = Color3.fromRGB(0, 200, 0),
    _enemyColor = Color3.fromRGB(255, 50, 50),
    _fovRadius = 150,
    _toggleKey = Enum.KeyCode.F6,
    _espDrawings = {},
    _droneDrawings = {},
    _grenadeDrawings = {},
    _claymoreDrawings = {},
    _fovCircle = nil,
    _renderConn = nil,
    _inputConn = nil,
}

function Module:setShared(shared)
    if type(shared) ~= "table" then
        return false, "shared must be table"
    end

    self.shared = shared

    local ref = shared.cloneref
    if type(ref) ~= "function" then
        ref = shared.ref
    end
    if type(ref) == "function" then
        RunService = ref(game:GetService("RunService"))
        Workspace = ref(game:GetService("Workspace"))
        UserInputService = ref(game:GetService("UserInputService"))
        Players = ref(game:GetService("Players"))
        lp = shared.lp or Players.LocalPlayer
    end

    return true
end

local function nd(t, p)
    local d = Drawing.new(t)
    for k, v in pairs(p) do
        d[k] = v
    end
    return d
end

local function clr(tbl, k)
    if tbl[k] then
        for _, d in pairs(tbl[k]) do
            pcall(function() if d.Remove then d:Remove() end end)
        end
        tbl[k] = nil
    end
end

local function getBB(parts, pad)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    local vis = false
    for _, p in ipairs(parts) do
        if p and p:IsA("BasePart") and p.Transparency < 1 then
            local sp, on = Workspace.CurrentCamera:WorldToViewportPoint(p.Position)
            if on then
                vis = true
                x0 = math.min(x0, sp.X)
                y0 = math.min(y0, sp.Y)
                x1 = math.max(x1, sp.X)
                y1 = math.max(y1, sp.Y)
            end
        end
    end
    if vis then
        x0 = x0 - pad
        y0 = y0 - pad
        x1 = x1 + pad
        y1 = y1 + pad
    end
    return vis, x0, y0, x1, y1
end

local function hpCol(r)
    if r > 0.5 then
        return Color3.fromRGB(0, 255, 80)
    elseif r > 0.25 then
        return Color3.fromRGB(255, 220, 0)
    else
        return Module._enemyColor
    end
end

local function isAllyByHighlight(obj)
    for _, hl in ipairs(Workspace:GetChildren()) do
        if hl:IsA("Highlight") and hl.Adornee == obj then
            return (hl.FillColor.G > 0.5 and hl.FillColor.R < 0.4)
        end
    end
    return false
end

local function getOwnerName(obj)
    local of = obj:FindFirstChild("Owner")
    if of then
        local un = of:FindFirstChild("Username")
        if un then
            return un:IsA("TextLabel") and un.Text or tostring(un.Value)
        end
    end
    return nil
end

local function findCharFromVM(vm)
    local torso = vm:FindFirstChild("torso")
    if not torso then return nil end
    for _, model in ipairs(Workspace:GetChildren()) do
        if model:IsA("Model") and model ~= lp.Character then
            local hrp = model:FindFirstChild("HumanoidRootPart")
            if hrp and (torso.Position - hrp.Position).Magnitude < 15 then return model end
        end
    end
    return nil
end

function Module:_updateESP()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    
    -- Update FOV
    self._fovCircle.Visible = self._enabled
    if self._enabled then
        local vp = camera.ViewportSize
        self._fovCircle.Position = Vector2.new(vp.X/2, vp.Y/2)
    end
    
    if not self._enabled then
        for k in pairs(self._espDrawings) do clr(self._espDrawings, k) end
        for k in pairs(self._droneDrawings) do clr(self._droneDrawings, k) end
        for k in pairs(self._grenadeDrawings) do clr(self._grenadeDrawings, k) end
        for k in pairs(self._claymoreDrawings) do clr(self._claymoreDrawings, k) end
        return
    end
    
    local myRoot = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    local vms = Workspace:FindFirstChild("Viewmodels")
    local seenVM = {}
    
    -- ===== PLAYER ESP =====
    if vms then
        for _, vm in ipairs(vms:GetChildren()) do
            if vm.Name ~= "Viewmodel" then continue end
            local torso = vm:FindFirstChild("torso")
            if not torso or torso.Transparency >= 0.9 then clr(self._espDrawings, vm) continue end
            local char = findCharFromVM(vm)
            if not char then clr(self._espDrawings, vm) continue end
            seenVM[vm] = true
            
            local parts = {}
            for _, n in ipairs({"head", "torso", "shoulder1", "shoulder2", "arm1", "arm2", "hip1", "hip2", "leg1", "leg2"}) do 
                local p = vm:FindFirstChild(n) 
                if p and p:IsA("BasePart") then table.insert(parts, p) end 
            end
            local vis, x0, y0, x1, y1 = getBB(parts, 4)
            if not vis then clr(self._espDrawings, vm) continue end
            
            if not self._espDrawings[vm] then
                self._espDrawings[vm] = {
                    box = nd("Square", {Visible=false, Filled=false, Thickness=1}),
                    tracer = nd("Line", {Visible=false, Thickness=1}),
                    name = nd("Text", {Visible=false, Size=13, Center=true, Outline=true, OutlineColor=Color3.new(0,0,0), Text=""}),
                    health = nd("Text", {Visible=false, Size=11, Center=true, Outline=true, OutlineColor=Color3.new(0,0,0), Color=Color3.fromRGB(255,255,255), Text=""}),
                    weapon = nd("Text", {Visible=false, Size=10, Center=true, Outline=true, OutlineColor=Color3.new(0,0,0), Color=Color3.fromRGB(255,215,80), Text=""}),
                    hpBg = nd("Square", {Visible=false, Filled=true, Thickness=0, Color=Color3.fromRGB(40,40,40)}),
                    hpFill = nd("Square", {Visible=false, Filled=true, Thickness=0})
                }
            end
            local d = self._espDrawings[vm]
            local w, h = x1-x0, y1-y0
            local ally = isAllyByHighlight(vm)
            local col = ally and self._allyColor or self._enemyColor
            local hum = char:FindFirstChildOfClass("Humanoid")
            local hpR = 1
            local hpText = "100hp"
            if hum and hum.MaxHealth > 0 then 
                hpR = math.clamp(hum.Health/hum.MaxHealth, 0, 1) 
                hpText = math.floor(hum.Health).."/"..hum.MaxHealth.."hp" 
            end
            local distS = "?"
            if myRoot then 
                local head = vm:FindFirstChild("head") 
                if head then 
                    distS = math.floor((head.Position - myRoot.Position).Magnitude).."m" 
                end 
            end
            local wpnText = ""
            for _, c in ipairs(vm:GetChildren()) do 
                if c:IsA("Model") then 
                    local lt = c:GetAttribute("loadout_type") 
                    if lt == "primary" or lt == "secondary" then 
                        wpnText = c.Name 
                        break 
                    end 
                end 
            end
            
            d.box.Color = col; d.box.Position = Vector2.new(x0, y0); d.box.Size = Vector2.new(w, h); d.box.Visible = true
            d.tracer.Color = ally and self._allyColor or Color3.fromRGB(255,220,0)
            d.tracer.From = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y); d.tracer.To = Vector2.new(x0 + w/2, y1); d.tracer.Visible = true
            d.name.Color = ally and self._allyColor or Color3.fromRGB(255,255,255)
            d.name.Position = Vector2.new(x0 + w/2, y0 - 20); d.name.Text = (ally and "[ALLY] " or "") .. (char.Name or "Unknown") .. " | " .. distS; d.name.Visible = true
            d.health.Position = Vector2.new(x0 + w/2, y0 - 6); d.health.Text = hpText; d.health.Visible = true
            d.weapon.Position = Vector2.new(x0 + w/2, y1 + 2); d.weapon.Text = wpnText; d.weapon.Visible = wpnText ~= ""
            local bx = x0 - 6; d.hpBg.Position = Vector2.new(bx, y0); d.hpBg.Size = Vector2.new(4, h); d.hpBg.Visible = true
            local fh = math.max(1, math.floor(h * hpR)); d.hpFill.Color = hpCol(hpR); d.hpFill.Position = Vector2.new(bx, y0 + (h - fh)); d.hpFill.Size = Vector2.new(4, fh); d.hpFill.Visible = true
        end
    end
    for vm in pairs(self._espDrawings) do if not seenVM[vm] then clr(self._espDrawings, vm) end end
    
    -- ===== DRONE ESP =====
    local seenDrones = {}
    for _, obj in ipairs(Workspace:GetChildren()) do
        if not obj:HasTag("Drone") then continue end
        local hum = obj:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then clr(self._droneDrawings, obj) continue end
        local parts = {}
        for _, n in ipairs({"Root", "Cam", "Wheel1", "Wheel2", "Collision"}) do 
            local p = obj:FindFirstChild(n) 
            if p and p:IsA("BasePart") then table.insert(parts, p) end 
        end
        local hrp = obj:FindFirstChild("HumanoidRootPart")
        if hrp then table.insert(parts, hrp) end
        local vis, x0, y0, x1, y1 = getBB(parts, 4)
        if not vis then clr(self._droneDrawings, obj) continue end
        seenDrones[obj] = true
        local w, h = x1-x0, y1-y0
        if not self._droneDrawings[obj] then
            self._droneDrawings[obj] = {
                box = nd("Square", {Visible=false, Filled=false, Thickness=1, Color=self._droneColor}),
                tracer = nd("Line", {Visible=false, Thickness=1, Color=self._droneColor}),
                label = nd("Text", {Visible=false, Size=12, Center=true, Outline=true, OutlineColor=Color3.new(0,0,0), Color=self._droneColor, Text=""}),
                hpBg = nd("Square", {Visible=false, Filled=true, Thickness=0, Color=Color3.fromRGB(40,40,40)}),
                hpFill = nd("Square", {Visible=false, Filled=true, Thickness=0, Color=Color3.fromRGB(0,200,255)})
            }
        end
        local dd = self._droneDrawings[obj]
        local hpR = math.clamp(hum.Health/hum.MaxHealth, 0, 1)
        local ddist = myRoot and hrp and math.floor((hrp.Position-myRoot.Position).Magnitude) or 0
        dd.box.Position = Vector2.new(x0, y0); dd.box.Size = Vector2.new(w, h); dd.box.Visible = true
        dd.tracer.From = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y); dd.tracer.To = Vector2.new(x0+w/2, y1); dd.tracer.Visible = true
        dd.label.Position = Vector2.new(x0+w/2, y0-16); dd.label.Text = "[DRONE] "..ddist.."m | "..math.floor(hum.Health).."/"..hum.MaxHealth.."hp"; dd.label.Visible = true
        local dbx = x0-6; dd.hpBg.Position = Vector2.new(dbx, y0); dd.hpBg.Size = Vector2.new(4, h); dd.hpBg.Visible = true
        local dfh = math.max(1, math.floor(h*hpR)); dd.hpFill.Position = Vector2.new(dbx, y0+(h-dfh)); dd.hpFill.Size = Vector2.new(4, dfh); dd.hpFill.Visible = true
    end
    for obj in pairs(self._droneDrawings) do if not seenDrones[obj] then clr(self._droneDrawings, obj) end end
    
    -- ===== GRENADE ESP =====
    local seenGren = {}
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj.Name ~= "FragGrenade" then continue end
        local parts = {}
        for _, n in ipairs({"Cap", "Ring", "Root"}) do 
            local p = obj:FindFirstChild(n) 
            if p and p:IsA("BasePart") then table.insert(parts, p) end 
        end
        local vis, x0, y0, x1, y1 = getBB(parts, 4)
        if not vis then clr(self._grenadeDrawings, obj) continue end
        seenGren[obj] = true
        local w, h = x1-x0, y1-y0
        if not self._grenadeDrawings[obj] then
            self._grenadeDrawings[obj] = {
                box = nd("Square", {Visible=false, Filled=false, Thickness=1, Color=self._grenadeColor}), 
                tracer = nd("Line", {Visible=false, Thickness=1, Color=self._grenadeColor}), 
                label = nd("Text", {Visible=false, Size=12, Center=true, Outline=true, OutlineColor=Color3.new(0,0,0), Color=self._grenadeColor, Text=""})
            }
        end
        local gd = self._grenadeDrawings[obj]
        local root = obj:FindFirstChild("Root")
        local gdist = myRoot and root and math.floor((root.Position-myRoot.Position).Magnitude) or 0
        gd.box.Position = Vector2.new(x0, y0); gd.box.Size = Vector2.new(w, h); gd.box.Visible = true
        gd.tracer.From = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y); gd.tracer.To = Vector2.new(x0+w/2, y1); gd.tracer.Visible = true
        gd.label.Position = Vector2.new(x0+w/2, y0-14); gd.label.Text = "[FRAG] "..gdist.."m"; gd.label.Visible = true
    end
    for g in pairs(self._grenadeDrawings) do if not seenGren[g] then clr(self._grenadeDrawings, g) end end
    
    -- ===== CLAYMORE ESP =====
    local seenClay = {}
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj.Name ~= "Claymore" then continue end
        local parts = {}
        for _, n in ipairs({"Light", "Root", "SwitchButton", "Laser", "Leg"}) do 
            local p = obj:FindFirstChild(n) 
            if p and p:IsA("BasePart") then table.insert(parts, p) end 
        end
        local vis, x0, y0, x1, y1 = getBB(parts, 12)
        if not vis then clr(self._claymoreDrawings, obj) continue end
        seenClay[obj] = true
        local w, h = x1-x0, y1-y0
        if not self._claymoreDrawings[obj] then
            self._claymoreDrawings[obj] = {
                box = nd("Square", {Visible=false, Filled=false, Thickness=1}), 
                tracer = nd("Line", {Visible=false, Thickness=1}), 
                label = nd("Text", {Visible=false, Size=12, Center=true, Outline=true, OutlineColor=Color3.new(0,0,0), Text=""})
            }
        end
        local cd = self._claymoreDrawings[obj]
        local root = obj:FindFirstChild("Root")
        local cdist = myRoot and root and math.floor((root.Position-myRoot.Position).Magnitude) or 0
        local ally = isAllyByHighlight(obj)
        local col = ally and self._allyColor or self._enemyColor
        local oname = getOwnerName(obj)
        cd.box.Color = col; cd.tracer.Color = col; cd.label.Color = col
        cd.box.Position = Vector2.new(x0, y0); cd.box.Size = Vector2.new(w, h); cd.box.Visible = true
        cd.tracer.From = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y); cd.tracer.To = Vector2.new(x0+w/2, y1); cd.tracer.Visible = true
        cd.label.Position = Vector2.new(x0+w/2, y0-14); cd.label.Text = (ally and "[ALLY] " or "[ENEMY] ")..(oname or "Claymore").." "..cdist.."m"; cd.label.Visible = true
    end
    for c in pairs(self._claymoreDrawings) do if not seenClay[c] then clr(self._claymoreDrawings, c) end end
end

function Module:_handleInput(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == self._toggleKey then
        self._enabled = not self._enabled
        print("[ESP] " .. (self._enabled and "ON" or "OFF"))
    end
end

function Module:init(force)
    if self._initialized and not force then
        return true
    end

    if self._initialized and force then
        self:unload()
    end

    -- Create FOV circle
    self._fovCircle = Drawing.new("Circle")
    self._fovCircle.Visible = self._enabled
    self._fovCircle.Radius = self._fovRadius
    self._fovCircle.Thickness = 1
    self._fovCircle.Color = Color3.fromRGB(255, 255, 255)
    self._fovCircle.Filled = false

    -- Connect render step
    self._renderConn = RunService.RenderStepped:Connect(function()
        self:_updateESP()
    end)

    -- Connect input handling
    self._inputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        self:_handleInput(input, gameProcessed)
    end)

    self._initialized = true
    print("[ESP] Loaded | F6: Toggle")
    return true
end

function Module:load(force)
    return self:init(force)
end

function Module:isLoaded()
    return self._initialized
end

function Module:setEnabled(state)
    local okInit, initErr = self:init(false)
    if not okInit then
        return false, initErr
    end
    self._enabled = state == true
    return true
end

function Module:toggle()
    return self:setEnabled(not self._enabled)
end

function Module:setTeamCheck(state)
    self._teamCheck = state == true
    return true
end

function Module:setPlayerBoxEnabled(state)
    self._playerBoxEnabled = state == true
    return true
end

function Module:setSkeletonEnabled(state)
    self._skeletonEnabled = state == true
    return true
end

function Module:setObjectBoxEnabled(state)
    self._objectBoxEnabled = state == true
    return true
end

function Module:setPlayerColor(color)
    if typeof(color) ~= "Color3" then
        return false, "invalid color"
    end
    self._enemyColor = color
    return true
end

function Module:setAllyColor(color)
    if typeof(color) ~= "Color3" then
        return false, "invalid color"
    end
    self._allyColor = color
    return true
end

function Module:setSkeletonColor(color)
    if typeof(color) ~= "Color3" then
        return false, "invalid color"
    end
    self._skeletonColor = color
    return true
end

function Module:setDroneColor(color)
    if typeof(color) ~= "Color3" then 
        return false, "invalid color" 
    end
    self._droneColor = color
    return true
end

function Module:setClaymoreColor(color)
    if typeof(color) ~= "Color3" then 
        return false, "invalid color" 
    end
    self._claymoreColor = color
    return true
end

function Module:setGrenadeColor(color)
    if typeof(color) ~= "Color3" then 
        return false, "invalid color" 
    end
    self._grenadeColor = color
    return true
end

function Module:unload()
    self._enabled = false
    if self._renderConn then
        self._renderConn:Disconnect()
        self._renderConn = nil
    end

    if self._inputConn then
        self._inputConn:Disconnect()
        self._inputConn = nil
    end

    -- Clean up all drawings
    if self._fovCircle then
        self._fovCircle:Remove()
        self._fovCircle = nil
    end

    for _, tbl in ipairs({self._espDrawings, self._droneDrawings, self._grenadeDrawings, self._claymoreDrawings}) do
        if tbl then 
            for _, set in pairs(tbl) do 
                for _, d in pairs(set) do 
                    pcall(function() d:Remove() end) 
                end 
            end 
        end
    end

    self._espDrawings = {}
    self._droneDrawings = {}
    self._grenadeDrawings = {}
    self._claymoreDrawings = {}
    self._initialized = false
    return true
end

return Module
