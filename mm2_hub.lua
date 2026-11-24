--// MM2 Hub | silent aim, ESP, autogun, GUI, keybinds, mobile buttons
--// NOT TESTED against the live game. Remote names/args are marked FILL where they tend to change.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local VirtualUser = game:GetService("VirtualUser")

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

--// ───────────── settings ─────────────
local S = {
	SilentAim = false, FOV = 200, ShowFOV = true, HitChance = 100, Prediction = 0.12,
	AimPart = "HumanoidRootPart", WallCheck = true, MurdererOnly = true,
	ESP = false, GunESP = false, AutoGun = false, AntiAFK = true,
	SpeedOn = false, Speed = 24, JumpOn = false, Jump = 60,
	Aimbot = false, AimbotRMB = false, AimbotSmooth = 0.35,
	AutoShoot = false, ShootDelay = 1.2, AutoThrow = false, ThrowRange = 70, ThrowDelay = 1.5,
	KillAura = false, AuraRange = 12, CoinFarm = false, CoinSpeed = 40,
	Noclip = false, InfJump = false, Fly = false, FlySpeed = 50, Fullbright = false,
}

local K = {
	Menu = Enum.KeyCode.RightShift,
	Aim = Enum.KeyCode.E,
	Shoot = Enum.KeyCode.Q,
	ShootMurd = Enum.KeyCode.R,
	Throw = Enum.KeyCode.F,
	ThrowNear = Enum.KeyCode.G,
	Aimbot = Enum.KeyCode.C,
	AutoShoot = Enum.KeyCode.V,
	ESP = Enum.KeyCode.X,
}

local function notify(t, d)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = t, Text = d or "", Duration = 3 })
	end)
end

--// ───────────── role / target logic ─────────────
-- other players' Backpacks don't replicate, so roles come from the game's own player data first.
local roleCache = {}
local function refreshRoles()
	local okc, data = pcall(function()
		return game:GetService("ReplicatedStorage").Remotes.Extras.GetPlayerData:InvokeServer() -- FILL: path/name if it changes
	end)
	if okc and typeof(data) == "table" then
		local fresh = {}
		for name, d in pairs(data) do
			if typeof(d) == "table" and d.Role then fresh[name] = d.Role end
		end
		roleCache = fresh
	end
end
task.spawn(function() while task.wait(1) do refreshRoles() end end)

local function hasTool(plr, name)
	local c, b = plr.Character, plr:FindFirstChildOfClass("Backpack")
	return (c and c:FindFirstChild(name)) or (b and b:FindFirstChild(name))
end

local function roleOf(plr)
	local r = roleCache[plr.Name]
	if r == "Murderer" then return "Murderer" end
	if r == "Sheriff" or r == "Hero" then return "Sheriff" end
	if hasTool(plr, "Knife") then return "Murderer" end
	if hasTool(plr, "Gun") then return "Sheriff" end
	return "Innocent"
end

local function alive(plr)
	local c = plr.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return c and h and h.Health > 0 and c:FindFirstChild("HumanoidRootPart") ~= nil
end

local function visible(part)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = { LP.Character, part.Parent }
	return Workspace:Raycast(Camera.CFrame.Position, part.Position - Camera.CFrame.Position, p) == nil
end

local function aimOrigin()
	if UIS.MouseEnabled then return UIS:GetMouseLocation() end
	return Camera.ViewportSize / 2
end

-- ignoreFOV: nearest by studs, no wall check. forceRole: only that role.
local function getTarget(ignoreFOV, forceRole)
	local mine = roleOf(LP)
	local myRoot = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
	local best, bestDist = nil, ignoreFOV and math.huge or S.FOV
	local o = aimOrigin()
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and alive(plr) then
			local r = roleOf(plr)
			local ok = true
			if forceRole then
				ok = (r == forceRole)
			elseif mine == "Sheriff" and S.MurdererOnly then
				ok = (r == "Murderer")
			elseif mine == "Murderer" and r == "Murderer" then
				ok = false
			end
			if ok then
				local part = plr.Character:FindFirstChild(S.AimPart) or plr.Character.HumanoidRootPart
				local d
				if ignoreFOV then
					d = (part.Position - (myRoot and myRoot.Position or Camera.CFrame.Position)).Magnitude
				else
					local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
					if onScreen then d = (Vector2.new(sp.X, sp.Y) - o).Magnitude end
				end
				if d and d < bestDist and (ignoreFOV or not S.WallCheck or visible(part)) then
					best, bestDist = plr, d
				end
			end
		end
	end
	return best, bestDist
end

local function predict(t)
	local c = t.Character
	local part = c:FindFirstChild(S.AimPart) or c.HumanoidRootPart
	return part.Position + c.HumanoidRootPart.AssemblyLinearVelocity * S.Prediction
end

local function aimPos(ignoreFOV, forceRole, skipChance)
	if not skipChance and math.random(1, 100) > S.HitChance then return nil end
	local t = getTarget(ignoreFOV, forceRole)
	if not t then return nil end
	return predict(t), t
end

--// ───────────── silent aim hook ─────────────
local hooked = false
if hookmetamethod and getnamecallmethod and checkcaller then
	local old
	local wrap = newcclosure or function(f) return f end
	old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
		local m = getnamecallmethod()
		if S.SilentAim and not checkcaller() and (m == "FireServer" or m == "InvokeServer") then
			local a = { ... }
			-- knife throw: Throw:FireServer(CFrame, Vector3)   --FILL: verify arg layout if it stops landing
			if self.Name == "Throw" and typeof(a[1]) == "CFrame" and typeof(a[2]) == "Vector3" then
				local p = aimPos()
				if p then a[2] = p; return old(self, unpack(a)) end
			-- gun shot: CreateBeam.RemoteFunction:InvokeServer(1, Vector3, "AH2")   --FILL: token string changes
			elseif self.Name == "RemoteFunction" and self.Parent and self.Parent.Name == "CreateBeam" and typeof(a[2]) == "Vector3" then
				local p = aimPos()
				if p then a[2] = p; return old(self, unpack(a)) end
			end
		end
		return old(self, ...)
	end))
	hooked = true
else
	notify("Silent aim", "Executor lacks hookmetamethod. Manual shoot/throw buttons still work.")
end

--// ───────────── actions ─────────────
local lastShot, lastThrow = 0, 0

local function equip(name)
	local c = LP.Character
	if not c then return end
	local tool = c:FindFirstChild(name) or (LP.Backpack and LP.Backpack:FindFirstChild(name))
	if tool and tool.Parent ~= c then
		local h = c:FindFirstChildOfClass("Humanoid")
		if h then h:EquipTool(tool) end
		task.wait(0.05)
	end
	return c:FindFirstChild(name)
end

local function fireGun(pos)
	local gun = equip("Gun")
	if not gun then return false end
	local k = gun:FindFirstChild("KnifeLocal")
	local rf = k and k:FindFirstChild("CreateBeam") and k.CreateBeam:FindFirstChild("RemoteFunction")
	if not rf then return false end
	lastShot = tick()
	pcall(function() rf:InvokeServer(1, pos, "AH2") end) -- FILL: token string changes
	return true
end

local function throwAt(pos)
	local knife = equip("Knife")
	local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
	local ev = knife and knife:FindFirstChild("Throw")
	if not (ev and root) then return false end
	lastThrow = tick()
	pcall(function() ev:FireServer(CFrame.new(root.Position), pos) end) -- FILL: arg layout
	return true
end

local function shoot() -- aimed, inside FOV
	local pos = aimPos(false, nil, true)
	if not pos then notify("Shoot", "No target in FOV") return end
	if not fireGun(pos) then notify("Shoot", "No gun") end
end

local function shootMurderer() -- any range, any angle, through walls
	if roleOf(LP) == "Murderer" then return end
	local pos = aimPos(true, "Murderer", true)
	if not pos then notify("Shoot Murderer", "No murderer found") return end
	if not fireGun(pos) then notify("Shoot Murderer", "No gun") end
end

local function throwKnife() -- aimed, inside FOV
	local pos = aimPos(false, nil, true)
	if not pos then notify("Throw", "No target in FOV") return end
	if not throwAt(pos) then notify("Throw", "No knife") end
end

local function throwNearest() -- nearest player by distance
	local pos = aimPos(true, nil, true)
	if not pos then notify("Throw", "No target") return end
	if not throwAt(pos) then notify("Throw", "No knife") end
end

local function toggleKey(key)
	S[key] = not S[key]
	notify(key, S[key] and "ON" or "OFF")
end

--// ───────────── ESP ─────────────
local espObjs = {}
local function clearESP(plr)
	if espObjs[plr] then espObjs[plr]:Destroy() espObjs[plr] = nil end
end

local roleColor = {
	Murderer = Color3.fromRGB(255, 60, 60),
	Sheriff = Color3.fromRGB(70, 140, 255),
	Innocent = Color3.fromRGB(80, 220, 120),
}

local gunHL
task.spawn(function()
	while task.wait(0.25) do
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LP then
				if S.ESP and alive(plr) then
					local hl = espObjs[plr]
					if not hl or hl.Parent ~= plr.Character then
						clearESP(plr)
						hl = Instance.new("Highlight")
						hl.FillTransparency = 0.6
						hl.OutlineTransparency = 0
						hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
						hl.Parent = plr.Character
						espObjs[plr] = hl
					end
					hl.FillColor = roleColor[roleOf(plr)]
					hl.OutlineColor = hl.FillColor
				else
					clearESP(plr)
				end
			end
		end
		local drop = Workspace:FindFirstChild("GunDrop", true)
		if S.GunESP and drop then
			if not gunHL or gunHL.Parent ~= drop then
				if gunHL then gunHL:Destroy() end
				gunHL = Instance.new("Highlight")
				gunHL.FillColor = Color3.fromRGB(255, 220, 60)
				gunHL.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				gunHL.Parent = drop
			end
		elseif gunHL then
			gunHL:Destroy() gunHL = nil
		end
	end
end)
Players.PlayerRemoving:Connect(clearESP)

--// ───────────── auto gun / movement / afk ─────────────
task.spawn(function()
	while task.wait(0.4) do
		if S.AutoGun and roleOf(LP) ~= "Murderer" then
			local drop = Workspace:FindFirstChild("GunDrop", true)
			local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
			if drop and root and drop:IsA("BasePart") then
				if firetouchinterest then
					firetouchinterest(root, drop, 0) task.wait()
					firetouchinterest(root, drop, 1)
				else
					local back = root.CFrame
					root.CFrame = drop.CFrame
					task.wait(0.2)
					root.CFrame = back
				end
			end
		end
	end
end)

RunService.Heartbeat:Connect(function()
	local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
	if h then
		if S.SpeedOn then h.WalkSpeed = S.Speed end
		if S.JumpOn then h.UseJumpPower = true h.JumpPower = S.Jump end
	end
end)

LP.Idled:Connect(function()
	if S.AntiAFK then
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new())
	end
end)

--// ───────────── combat loops / extra features ─────────────
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

-- aimbot: camera lock
RunService.RenderStepped:Connect(function()
	if not S.Aimbot then return end
	if S.AimbotRMB and UIS.MouseEnabled and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end
	local t = getTarget()
	if not t then return end
	Camera.CFrame = Camera.CFrame:Lerp(CFrame.lookAt(Camera.CFrame.Position, predict(t)), S.AimbotSmooth)
end)

-- auto shoot: sheriff/hero shoots a visible murderer inside the FOV
task.spawn(function()
	while task.wait(0.05) do
		if S.AutoShoot and roleOf(LP) ~= "Murderer" and hasTool(LP, "Gun") and tick() - lastShot > S.ShootDelay then
			local t = getTarget(false, "Murderer")
			if t and math.random(1, 100) <= S.HitChance then fireGun(predict(t)) end
		end
	end
end)

-- auto throw: murderer throws at the nearest player inside range
task.spawn(function()
	while task.wait(0.05) do
		if S.AutoThrow and hasTool(LP, "Knife") and tick() - lastThrow > S.ThrowDelay then
			local t, d = getTarget(true)
			if t and d <= S.ThrowRange then
				if not S.WallCheck or visible(t.Character.HumanoidRootPart) then throwAt(predict(t)) end
			end
		end
	end
end)

-- kill aura: murderer stabs anything in range
task.spawn(function()
	while task.wait(0.12) do
		if S.KillAura and hasTool(LP, "Knife") then
			local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
			if root then
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= LP and alive(p) then
						local r = p.Character.HumanoidRootPart
						if (r.Position - root.Position).Magnitude <= S.AuraRange then
							local knife = equip("Knife")
							if knife then
								pcall(function() knife:Activate() end)
								local h = knife:FindFirstChild("Handle")
								if h and firetouchinterest then -- FILL: some versions need the stab remote instead
									firetouchinterest(h, r, 0)
									firetouchinterest(h, r, 1)
								end
							end
						end
					end
				end
			end
		end
	end
end)

-- coin farm
task.spawn(function()
	while task.wait(0.1) do
		if S.CoinFarm and alive(LP) then
			local root = LP.Character.HumanoidRootPart
			local cont = Workspace:FindFirstChild("CoinContainer", true)
			if cont then
				local best, bd = nil, math.huge
				for _, c in ipairs(cont:GetChildren()) do
					if c:IsA("BasePart") and c.Name == "Coin_Server" then
						local d = (c.Position - root.Position).Magnitude
						if d < bd then best, bd = c, d end
					end
				end
				if best then
					local tw = TweenService:Create(root, TweenInfo.new(math.max(bd / S.CoinSpeed, 0.05), Enum.EasingStyle.Linear), { CFrame = best.CFrame })
					tw:Play()
					tw.Completed:Wait()
				end
			end
		end
	end
end)

-- noclip (also forced on while coin farming)
RunService.Stepped:Connect(function()
	if S.Noclip or S.CoinFarm then
		local c = LP.Character
		if c then
			for _, p in ipairs(c:GetDescendants()) do
				if p:IsA("BasePart") then p.CanCollide = false end
			end
		end
	end
end)

-- infinite jump
UIS.JumpRequest:Connect(function()
	if S.InfJump then
		local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
		if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

-- fly (camera relative, works with the mobile thumbstick)
local flyBV
RunService.Heartbeat:Connect(function()
	local c = LP.Character
	local root = c and c:FindFirstChild("HumanoidRootPart")
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if S.Fly and root and h then
		if not flyBV or flyBV.Parent ~= root then
			if flyBV then flyBV:Destroy() end
			flyBV = Instance.new("BodyVelocity")
			flyBV.MaxForce = Vector3.new(1e5, 1e5, 1e5)
			flyBV.Velocity = Vector3.zero
			flyBV.Parent = root
		end
		h.PlatformStand = true
		local rel = Camera.CFrame:VectorToObjectSpace(h.MoveDirection)
		flyBV.Velocity = (Camera.CFrame.LookVector * -rel.Z + Camera.CFrame.RightVector * rel.X) * S.FlySpeed
	elseif flyBV then
		flyBV:Destroy()
		flyBV = nil
		if h then h.PlatformStand = false end
	end
end)

-- fullbright
local origLight
RunService.Heartbeat:Connect(function()
	if S.Fullbright then
		if not origLight then
			origLight = { Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShading, Lighting.Ambient }
		end
		Lighting.Brightness = 2
		Lighting.ClockTime = 14
		Lighting.FogEnd = 1e6
		Lighting.GlobalShading = false
		Lighting.Ambient = Color3.fromRGB(190, 190, 190)
	elseif origLight then
		Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShading, Lighting.Ambient = unpack(origLight)
		origLight = nil
	end
end)

local function rolesText()
	local m, sh = "?", "?"
	for _, p in ipairs(Players:GetPlayers()) do
		local r = roleOf(p)
		if r == "Murderer" then m = p.Name elseif r == "Sheriff" then sh = p.Name end
	end
	return "Murderer: " .. m .. "\nSheriff: " .. sh
end

--// ───────────── GUI helpers ─────────────
local C = {
	bg = Color3.fromRGB(18, 18, 26), item = Color3.fromRGB(28, 28, 40),
	side = Color3.fromRGB(13, 13, 20), accent = Color3.fromRGB(122, 92, 255),
	text = Color3.fromRGB(235, 235, 245), dim = Color3.fromRGB(140, 140, 160),
	off = Color3.fromRGB(55, 55, 72),
}

local function new(cls, props, parent)
	local i = Instance.new(cls)
	for k, v in pairs(props) do i[k] = v end
	i.Parent = parent
	return i
end
local function corner(p, r) new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, p) end
local function isDown(i) return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch end
local function isMove(i) return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch end

local function draggable(handle, target, gate)
	local dragging, start, orig
	handle.InputBegan:Connect(function(i)
		if isDown(i) and (not gate or gate()) then
			dragging, start, orig = true, i.Position, target.Position
			i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UIS.InputChanged:Connect(function(i)
		if dragging and isMove(i) then
			local d = i.Position - start
			target.Position = UDim2.new(orig.X.Scale, orig.X.Offset + d.X, orig.Y.Scale, orig.Y.Offset + d.Y)
		end
	end)
end

local parentGui = (gethui and gethui()) or game:GetService("CoreGui")
local ok = pcall(function() return parentGui.Name end)
if not ok then parentGui = LP:WaitForChild("PlayerGui") end
local gui = new("ScreenGui", { Name = "MM2Hub", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true }, parentGui)

--// FOV circle
local fov = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Visible = false }, gui)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, fov)
new("UIStroke", { Color = C.accent, Thickness = 1.5 }, fov)
RunService.RenderStepped:Connect(function()
	fov.Visible = S.ShowFOV and S.SilentAim
	fov.Size = UDim2.fromOffset(S.FOV * 2, S.FOV * 2)
	local o = aimOrigin()
	fov.Position = UDim2.fromOffset(o.X, o.Y)
end)

--// main window
local main = new("Frame", { Size = UDim2.fromOffset(540, 370), Position = UDim2.new(0.5, -270, 0.5, -185), BackgroundColor3 = C.bg, BorderSizePixel = 0 }, gui)
corner(main, 12)
new("UIStroke", { Color = C.accent, Transparency = 0.5 }, main)

local top = new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = C.side, BorderSizePixel = 0 }, main)
corner(top, 12)
new("TextLabel", { Size = UDim2.new(1, -50, 1, 0), Position = UDim2.fromOffset(14, 0), BackgroundTransparency = 1, Text = "MM2 Hub", Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left }, top)
local close = new("TextButton", { Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -34, 0, 4), BackgroundColor3 = C.off, Text = "x", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.text }, top)
corner(close, 6)
draggable(top, main)

local function setMenu(v) main.Visible = v end
close.Activated:Connect(function() setMenu(false) end)

local tabBar = new("Frame", { Size = UDim2.new(0, 110, 1, -36), Position = UDim2.fromOffset(0, 36), BackgroundColor3 = C.side, BorderSizePixel = 0 }, main)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, tabBar)
new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, tabBar)

local pages, tabBtns = {}, {}
local function showTab(name)
	for n, p in pairs(pages) do p.Visible = (n == name) end
	for n, b in pairs(tabBtns) do b.BackgroundColor3 = (n == name) and C.accent or C.item end
end

local function addTab(name)
	local b = new("TextButton", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = C.item, Text = name, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.text }, tabBar)
	corner(b, 6)
	local p = new("ScrollingFrame", { Size = UDim2.new(1, -118, 1, -44), Position = UDim2.fromOffset(114, 40), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Visible = false }, main)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, p)
	pages[name], tabBtns[name] = p, b
	b.Activated:Connect(function() showTab(name) end)
	return p
end

local function toggle(page, label, key, cb)
	local f = new("TextButton", { Size = UDim2.new(1, -8, 0, 34), BackgroundColor3 = C.item, Text = "", AutoButtonColor = false }, page)
	corner(f)
	new("TextLabel", { Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1, Text = label, Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left }, f)
	local pill = new("Frame", { Size = UDim2.fromOffset(38, 18), Position = UDim2.new(1, -50, 0.5, -9), BackgroundColor3 = S[key] and C.accent or C.off }, f)
	corner(pill, 9)
	local dot = new("Frame", { Size = UDim2.fromOffset(14, 14), Position = S[key] and UDim2.fromOffset(22, 2) or UDim2.fromOffset(2, 2), BackgroundColor3 = C.text }, pill)
	corner(dot, 7)
	local function refresh()
		pill.BackgroundColor3 = S[key] and C.accent or C.off
		dot.Position = S[key] and UDim2.fromOffset(22, 2) or UDim2.fromOffset(2, 2)
	end
	f.Activated:Connect(function() S[key] = not S[key] refresh() if cb then cb(S[key]) end end)
	RunService.Heartbeat:Connect(refresh) -- keeps in sync with keybinds / mobile buttons
end

local function slider(page, label, min, max, key, step)
	local f = new("Frame", { Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = C.item }, page)
	corner(f)
	local t = new("TextLabel", { Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(12, 4), BackgroundTransparency = 1, Text = label .. ": " .. S[key], Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left }, f)
	local bar = new("Frame", { Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 6), BackgroundColor3 = C.off, BorderSizePixel = 0 }, f)
	corner(bar, 3)
	local fill = new("Frame", { Size = UDim2.new((S[key] - min) / (max - min), 0, 1, 0), BackgroundColor3 = C.accent, BorderSizePixel = 0 }, bar)
	corner(fill, 3)
	local sliding = false
	local function set(x)
		local r = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		local v = min + (max - min) * r
		v = math.floor(v / step + 0.5) * step
		v = tonumber(string.format("%.3f", v))
		S[key] = v
		fill.Size = UDim2.new(r, 0, 1, 0)
		t.Text = label .. ": " .. v
	end
	f.InputBegan:Connect(function(i) if isDown(i) then sliding = true set(i.Position.X) end end)
	UIS.InputEnded:Connect(function(i) if isDown(i) then sliding = false end end)
	UIS.InputChanged:Connect(function(i) if sliding and isMove(i) then set(i.Position.X) end end)
end

local function button(page, label, fn)
	local b = new("TextButton", { Size = UDim2.new(1, -8, 0, 34), BackgroundColor3 = C.item, Text = label, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.text }, page)
	corner(b)
	b.Activated:Connect(fn)
end

local function dropdown(page, label, key, options)
	local b = new("TextButton", { Size = UDim2.new(1, -8, 0, 34), BackgroundColor3 = C.item, Text = label .. ": " .. S[key], Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.text }, page)
	corner(b)
	b.Activated:Connect(function()
		local idx = table.find(options, S[key]) or 0
		S[key] = options[(idx % #options) + 1]
		b.Text = label .. ": " .. S[key]
	end)
end

local listening
local function keybind(page, label, id)
	local b = new("TextButton", { Size = UDim2.new(1, -8, 0, 34), BackgroundColor3 = C.item, Text = label .. ": " .. K[id].Name, Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.text }, page)
	corner(b)
	b.Activated:Connect(function()
		listening = { id = id, btn = b, label = label }
		b.Text = label .. ": press a key..."
	end)
end

--// ───────────── pages ─────────────
local combat = addTab("Combat")
toggle(combat, "Silent Aim", "SilentAim")
toggle(combat, "Aimbot (camera lock)", "Aimbot")
toggle(combat, "Aimbot: hold RMB only (PC)", "AimbotRMB")
slider(combat, "Aimbot Strength", 0.05, 1, "AimbotSmooth", 0.05)
toggle(combat, "Auto Shoot (murderer in view)", "AutoShoot")
slider(combat, "Auto Shoot Delay (s)", 0.2, 5, "ShootDelay", 0.1)
toggle(combat, "Auto Throw (murderer)", "AutoThrow")
slider(combat, "Auto Throw Range", 10, 200, "ThrowRange", 5)
slider(combat, "Auto Throw Delay (s)", 0.5, 5, "ThrowDelay", 0.1)
toggle(combat, "Kill Aura (murderer)", "KillAura")
slider(combat, "Aura Range", 5, 30, "AuraRange", 1)
toggle(combat, "Show FOV Circle", "ShowFOV")
toggle(combat, "Wall Check", "WallCheck")
toggle(combat, "Sheriff: Murderer Only", "MurdererOnly")
slider(combat, "FOV Radius", 40, 600, "FOV", 5)
slider(combat, "Hit Chance %", 1, 100, "HitChance", 1)
slider(combat, "Prediction", 0, 0.4, "Prediction", 0.01)
dropdown(combat, "Aim Part", "AimPart", { "HumanoidRootPart", "Head", "UpperTorso" })
button(combat, "Shoot Murderer (any range)", shootMurderer)
button(combat, "Shoot Gun (aimed)", shoot)
button(combat, "Throw Knife (aimed)", throwKnife)
button(combat, "Throw Knife (nearest)", throwNearest)

local vis = addTab("Visuals")
toggle(vis, "Player ESP (role colors)", "ESP")
toggle(vis, "Gun Drop ESP", "GunESP")
toggle(vis, "Fullbright", "Fullbright")
local rolesLabel = new("TextLabel", { Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = C.item, Text = rolesText(), Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.text }, vis)
corner(rolesLabel)
task.spawn(function() while task.wait(1) do rolesLabel.Text = rolesText() end end)

local plr = addTab("Player")
toggle(plr, "Auto Grab Gun", "AutoGun")
toggle(plr, "Coin Farm", "CoinFarm")
slider(plr, "Coin Farm Speed", 20, 120, "CoinSpeed", 5)
toggle(plr, "Speed", "SpeedOn", function(v)
	if not v then local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") if h then h.WalkSpeed = 16 end end
end)
slider(plr, "Walk Speed", 16, 80, "Speed", 1)
toggle(plr, "Jump Power", "JumpOn")
slider(plr, "Jump Power Value", 50, 150, "Jump", 1)
toggle(plr, "Infinite Jump", "InfJump")
toggle(plr, "Noclip", "Noclip")
toggle(plr, "Fly", "Fly")
slider(plr, "Fly Speed", 20, 150, "FlySpeed", 5)
toggle(plr, "Anti-AFK", "AntiAFK")
button(plr, "Reset Character", function()
	local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
	if h then h.Health = 0 end
end)
button(plr, "Rejoin Server", function()
	game:GetService("TeleportService"):Teleport(game.PlaceId, LP)
end)

local binds = addTab("Keybinds")
keybind(binds, "Toggle Menu", "Menu")
keybind(binds, "Silent Aim", "Aim")
keybind(binds, "Aimbot", "Aimbot")
keybind(binds, "Auto Shoot", "AutoShoot")
keybind(binds, "Shoot (aimed)", "Shoot")
keybind(binds, "Shoot Murderer", "ShootMurd")
keybind(binds, "Throw (aimed)", "Throw")
keybind(binds, "Throw Nearest", "ThrowNear")
keybind(binds, "ESP", "ESP")

--// ───────────── mobile buttons ─────────────
local mobileOn = UIS.TouchEnabled
local editLayout = false
local mobileFolder = new("Folder", {}, gui)
local mobileBtns = {}

local function mobileButton(text, pos, action, stateKey)
	local b = new("TextButton", { Size = UDim2.fromOffset(62, 62), Position = pos, BackgroundColor3 = C.item, BackgroundTransparency = 0.15, Text = text, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.text, Visible = mobileOn }, mobileFolder)
	corner(b, 31)
	new("UIStroke", { Color = C.accent, Thickness = 2 }, b)
	b.Activated:Connect(function() if not editLayout then action() end end)
	draggable(b, b, function() return editLayout end)
	table.insert(mobileBtns, b)
	if stateKey then
		RunService.Heartbeat:Connect(function()
			b.BackgroundColor3 = S[stateKey] and C.accent or C.item
		end)
	end
end

mobileButton("MENU", UDim2.new(1, -80, 0, 70), function() setMenu(not main.Visible) end)
mobileButton("AIM", UDim2.new(1, -80, 0.28, 0), function() toggleKey("SilentAim") end, "SilentAim")
mobileButton("LOCK", UDim2.new(1, -150, 0.28, 0), function() toggleKey("Aimbot") end, "Aimbot")
mobileButton("SHOOT", UDim2.new(1, -150, 0.43, 0), shoot)
mobileButton("THROW", UDim2.new(1, -80, 0.43, 0), throwKnife)
mobileButton("SHOOT\nMURD", UDim2.new(1, -150, 0.58, 0), shootMurderer)
mobileButton("THROW\nNEAR", UDim2.new(1, -80, 0.58, 0), throwNearest)
mobileButton("AUTO\nSHOOT", UDim2.new(1, -150, 0.73, 0), function() toggleKey("AutoShoot") end, "AutoShoot")
mobileButton("ESP", UDim2.new(1, -80, 0.73, 0), function() toggleKey("ESP") end, "ESP")

local mob = addTab("Mobile")
local mobState = { Show = mobileOn }
S.MobileButtons = mobileOn
toggle(mob, "Show Mobile Buttons", "MobileButtons", function(v)
	for _, b in ipairs(mobileBtns) do b.Visible = v end
end)
S.EditLayout = false
toggle(mob, "Edit Layout (drag buttons)", "EditLayout", function(v) editLayout = v end)

--// ───────────── input ─────────────
UIS.InputBegan:Connect(function(i, gp)
	if listening and i.UserInputType == Enum.UserInputType.Keyboard then
		K[listening.id] = i.KeyCode
		listening.btn.Text = listening.label .. ": " .. i.KeyCode.Name
		listening = nil
		return
	end
	if gp or i.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local k = i.KeyCode
	if k == K.Menu then setMenu(not main.Visible)
	elseif k == K.Aim then toggleKey("SilentAim")
	elseif k == K.Aimbot then toggleKey("Aimbot")
	elseif k == K.AutoShoot then toggleKey("AutoShoot")
	elseif k == K.Shoot then shoot()
	elseif k == K.ShootMurd then shootMurderer()
	elseif k == K.Throw then throwKnife()
	elseif k == K.ThrowNear then throwNearest()
	elseif k == K.ESP then toggleKey("ESP") end
end)

showTab("Combat")
notify("MM2 Hub", hooked and "Loaded. Silent aim hook active." or "Loaded. No hook support.")
