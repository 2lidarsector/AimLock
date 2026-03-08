-- ESP, Aimbot, Fly & Noclip V2.1.0
-- Improvements: ESP batched updates, aimbot target caching, reduced raycast overhead,
-- cleaner code structure, throttled loops, removed redundant pcalls in hot paths.
-- v2.1: delta-time corrected aimbot lerp (frame-rate independent smoothing),
--       per-lock vs periodic random offset modes with configurable re-roll delay.

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local UserInputService= game:GetService("UserInputService")
local Workspace       = game:GetService("Workspace")
local Camera          = Workspace.CurrentCamera
local LocalPlayer     = Players.LocalPlayer
local Lighting        = game:GetService("Lighting")

-- ─── Lighting Snapshot ───────────────────────────────────────────────────────
-- Captured immediately on inject, before we touch anything.

-- Properties we can safely write (Technology is intentionally excluded — read-only in most games)
local LIGHTING_PROPS = {
	"Ambient", "Brightness", "ColorShift_Bottom", "ColorShift_Top",
	"EnvironmentDiffuseScale", "EnvironmentSpecularScale",
	"ExposureCompensation", "FogColor", "FogEnd", "FogStart",
	"GeographicLatitude", "GlobalShadows", "OutdoorAmbient",
	"ShadowSoftness", "TimeOfDay",
}

-- Snapshot original property values
local originalLighting = {}
for _, prop in ipairs(LIGHTING_PROPS) do
	originalLighting[prop] = Lighting[prop]
end

-- Snapshot original children (post-processing effects, Atmosphere, Sky, etc.)
-- We store { instance, originalEnabled } so we can toggle without destroying
local lightingChildren = {}
for _, child in ipairs(Lighting:GetChildren()) do
	local hasEnabled = pcall(function() return child.Enabled end)
	lightingChildren[#lightingChildren + 1] = {
		instance = child,
		-- most effects have .Enabled; Sky/Atmosphere do not, we'll hide via Parent
		hasEnabled = hasEnabled,
	}
end

-- Default Roblox lighting (blank baseplate values, no effects)
local DEFAULT_LIGHTING = {
	Ambient                  = Color3.fromRGB(70, 70, 70),
	Brightness               = 2,
	ColorShift_Bottom        = Color3.fromRGB(0, 0, 0),
	ColorShift_Top           = Color3.fromRGB(0, 0, 0),
	EnvironmentDiffuseScale  = 0.25,
	EnvironmentSpecularScale = 0.25,
	ExposureCompensation     = 0,
	FogColor                 = Color3.fromRGB(192, 192, 192),
	FogEnd                   = 100000,
	FogStart                 = 0,
	GeographicLatitude       = 41.733,
	GlobalShadows            = true,
	OutdoorAmbient           = Color3.fromRGB(70, 70, 70),
	ShadowSoftness           = 0.2,
	TimeOfDay                = "14:00:00",
}

local function applyLightingProps(tbl)
	for _, prop in ipairs(LIGHTING_PROPS) do
		if tbl[prop] ~= nil then
			pcall(function() Lighting[prop] = tbl[prop] end)
		end
	end
end

-- Disable all post-processing children (Atmosphere, Sky, effects)
local function disableLightingChildren()
	for _, entry in ipairs(lightingChildren) do
		local inst = entry.instance
		if inst and inst.Parent then
			pcall(function()
				if inst:IsA("PostProcessingEffect") then
					inst.Enabled = false
				elseif inst:IsA("Atmosphere") or inst:IsA("Sky") then
					inst.Parent = nil -- no .Enabled, must hide via parent
				end
			end)
		end
	end
end

-- Restore all post-processing children to original state
local function restoreLightingChildren()
	for _, entry in ipairs(lightingChildren) do
		local inst = entry.instance
		if inst then
			pcall(function()
				if inst:IsA("PostProcessingEffect") then
					inst.Enabled = true
				elseif inst:IsA("Atmosphere") or inst:IsA("Sky") then
					if inst.Parent ~= Lighting then
						inst.Parent = Lighting
					end
				end
			end)
		end
	end
end

local originalTimeOfDay = originalLighting.TimeOfDay

-- ─── Config ──────────────────────────────────────────────────────────────────

local Config = {
	ESPEnabled            = true,
	OutlineColor          = Color3.fromRGB(255, 255, 255),
	NameSize              = 14,
	NameTransparency      = 0,
	MaxDistance           = 1000,

	AimbotEnabled         = false,
	AimbotFOV             = 100,
	AimbotSpeed           = 0.2,
	AimbotTargets         = {"Head", "UpperTorso"},
	AimbotKey             = Enum.KeyCode.Q,
	ESPKey                = Enum.KeyCode.E,
	AimbotTargetMode      = "Closest Distance", -- "Any" | "Highest HP" | "Lowest HP" | "Closest Distance"
	AimbotTeamCheck       = true,
	AimbotMaxDistance     = 1000,
	AimbotRandomOffset    = false,
	AimbotOffsetMax       = 0.5,
	AimbotOffsetMode      = "PerLock",  -- "PerLock" (one offset per new target lock) | "Periodic" (re-randomise on a timer)
	AimbotOffsetUpdateInterval = 1.0,   -- seconds between re-randomisation when OffsetMode = "Periodic"

	ShowNameESP           = true,
	ShowHealthESP         = true,
	ShowDistanceESP       = true,
	HealthBarHeight       = 5,
	HealthBarTransparency = 0,
	DistanceSize          = 14,
	DistanceTransparency  = 0,
	OutlineTransparency   = 0.3,
	FOVCircleTransparency = 0.5,

	WallCheckEnabled      = true,

	FlyEnabled            = false,
	FlySpeed              = 50,
	FlyKey                = Enum.KeyCode.F,
	FlyForceDisabled      = false,

	NoclipEnabled         = false,
	NoclipKey             = Enum.KeyCode.V,
	NoclipForceDisabled   = false,

	SpeedHackEnabled      = false,
	SpeedHackValue        = 16,
	SpeedHackKey          = Enum.KeyCode.G,
	SpeedHackForceDisabled= false,
	SpeedHackAlwaysOverride = false, -- force WalkSpeed every frame even if humanoid resets it

	TimeOfDayEnabled      = true,
	TimeOfDayMinutes      = 720,
	DefaultLightingEnabled = false, -- replaces game lighting with Roblox defaults

	InfiniteJumpEnabled   = false,
	InfiniteJumpKey       = Enum.KeyCode.Space,
	InfiniteJumpForceDisabled = false,
}

-- ─── State ───────────────────────────────────────────────────────────────────

-- Per-player ESP element cache
local playerCache   = {} -- [player] = { highlight, billboard, nameLabel, healthBarFrame, healthBarFill, distanceLabel, character }

-- Aimbot state
local aiming            = false
local currentTarget     = nil  -- Player
local currentBestPart   = nil  -- BasePart
local currentOffset     = Vector3.zero
local lastOffsetTime    = 0
local lastTargetId      = nil  -- used to detect target changes cheaply

-- GUI pill sync callbacks (populated by createGUI so keybind handler can drive visuals)
local syncPills = {
	esp      = nil,
	aimbot   = nil,
	noclip   = nil,
	fly      = nil,
	speed    = nil,
	jump     = nil,
	tod      = nil,
}

-- Raycast params (reused – avoids allocating a new object every frame)
local rayParams = RaycastParams.new()
rayParams.FilterType    = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater   = true

-- ─── Helpers ─────────────────────────────────────────────────────────────────

-- Format minutes → "HH:MM:SS"
local function minutesToTimeString(totalMinutes)
	local h  = math.floor(totalMinutes / 60) % 24
	local m  = math.floor(totalMinutes % 60)
	local s  = math.floor((totalMinutes % 1) * 60)
	return string.format("%02d:%02d:%02d", h, m, s)
end

-- Safe destroy helper
local function safeDestroy(obj)
	if obj and obj.Parent then
		obj:Destroy()
	end
end

-- Clear cached ESP elements for a player
local function clearCache(player)
	local cache = playerCache[player]
	if not cache then return end
	safeDestroy(cache.highlight)
	safeDestroy(cache.billboard)
	playerCache[player] = nil
end

-- ─── Part Visibility ─────────────────────────────────────────────────────────
-- IMPROVEMENT: Reuses a single RaycastParams object and checks only the
-- specific part passed, instead of re-creating params every call.

local function isPartVisible(part)
	local origin    = Camera.CFrame.Position
	local target    = part.Position
	local direction = target - origin

	-- Exclude the LOCAL player's character to avoid self-occlusion
	local lc = LocalPlayer.Character
	rayParams.FilterDescendantsInstances = lc and {lc} or {}

	local result = Workspace:Raycast(origin, direction, rayParams)
	-- Visible if nothing was hit, or what was hit belongs to the target character
	return not result or result.Instance:IsDescendantOf(part.Parent)
end

-- Wall check: returns true if ANY target part is visible (short-circuits early)
local WALL_CHECK_PARTS = {
	"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso",
	"LeftUpperArm", "RightUpperArm",
}

local function isCharacterVisible(character)
	if not Config.WallCheckEnabled then return true end
	for _, name in ipairs(WALL_CHECK_PARTS) do
		local part = character:FindFirstChild(name)
		if part and isPartVisible(part) then
			return true
		end
	end
	return false
end

-- ─── ESP ─────────────────────────────────────────────────────────────────────
-- IMPROVEMENT: createESP now only creates elements once; subsequent calls
-- just update properties (no repeated Instance.new spam). Billboard layout
-- recalculated only when visibility flags change.

local function createESP(player)
	if player == LocalPlayer then return end
	if not Config.ESPEnabled then return end

	local character = player.Character
	if not character then return end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	local head             = character:FindFirstChild("Head")
	local humanoid         = character:FindFirstChildOfClass("Humanoid")
	if not (humanoidRootPart and head and humanoid) then return end

	-- Distance cull
	local localChar = LocalPlayer.Character
	local localHRP  = localChar and localChar:FindFirstChild("HumanoidRootPart")
	local distance  = localHRP
		and (localHRP.Position - humanoidRootPart.Position).Magnitude
		or  math.huge

	local cache = playerCache[player]

	if distance > Config.MaxDistance then
		-- Outside range – clean up and bail
		if cache then clearCache(player) end
		return
	end

	-- Detect character swap (respawn)
	if cache and cache.character ~= character then
		clearCache(player)
		cache = nil
	end

	-- ── Build elements the first time ──
	if not cache then
		cache = { character = character }
		playerCache[player] = cache

		-- Highlight (outline box)
		local hl = Instance.new("Highlight")
		hl.Name              = "BoxESP"
		hl.Adornee           = character
		hl.FillTransparency  = 1
		hl.OutlineColor      = player.TeamColor and player.TeamColor.Color or Config.OutlineColor
		hl.OutlineTransparency = Config.OutlineTransparency
		hl.Parent            = character
		cache.highlight      = hl

		-- BillboardGui
		local bb = Instance.new("BillboardGui")
		bb.Name          = "NameESP"
		bb.Adornee       = head
		bb.Size          = UDim2.new(0, 120, 0, 60)
		bb.StudsOffset   = Vector3.new(0, 2.5, 0)
		bb.AlwaysOnTop   = true
		bb.MaxDistance   = 0
		bb.Parent        = character
		cache.billboard  = bb

		-- Name label
		local nl = Instance.new("TextLabel")
		nl.Size                 = UDim2.new(1, 0, 0, 20)
		nl.Position             = UDim2.new(0, 0, 0, 0)
		nl.BackgroundTransparency = 1
		nl.Text                 = player.Name
		nl.TextColor3           = player.TeamColor and player.TeamColor.Color or Color3.new(1,1,1)
		nl.Font                 = Enum.Font.SourceSans
		nl.TextScaled           = false
		nl.Parent               = bb
		cache.nameLabel         = nl

		-- Health bar background
		local hbf = Instance.new("Frame")
		hbf.Size                 = UDim2.new(1, 0, 0, Config.HealthBarHeight)
		hbf.BackgroundColor3     = Color3.fromRGB(60, 60, 60)
		hbf.BorderSizePixel      = 0
		hbf.Parent               = bb
		cache.healthBarFrame     = hbf

		-- Health bar fill
		local hbfl = Instance.new("Frame")
		hbfl.Size              = UDim2.new(1, 0, 1, 0)
		hbfl.BackgroundColor3  = Color3.fromHSV(0.33, 1, 1)
		hbfl.BorderSizePixel   = 0
		hbfl.Parent            = hbf
		cache.healthBarFill    = hbfl

		-- Listen for health changes (connection stored so we never double-connect)
		cache.healthConn = humanoid.HealthChanged:Connect(function(hp)
			local ratio = math.clamp(hp / humanoid.MaxHealth, 0, 1)
			hbfl.Size             = UDim2.new(ratio, 0, 1, 0)
			hbfl.BackgroundColor3 = Color3.fromHSV(ratio * 0.33, 1, 1)
		end)

		-- Distance label
		local dl = Instance.new("TextLabel")
		dl.Size                  = UDim2.new(1, 0, 0, 20)
		dl.BackgroundTransparency = 1
		dl.TextColor3            = Color3.new(1,1,1)
		dl.Font                  = Enum.Font.SourceSans
		dl.TextScaled            = false
		dl.Parent                = bb
		cache.distanceLabel      = dl
	end

	-- ── Update existing elements every tick ──
	local hl   = cache.highlight
	local nl   = cache.nameLabel
	local hbf  = cache.healthBarFrame
	local hbfl = cache.healthBarFill
	local dl   = cache.distanceLabel
	local bb   = cache.billboard

	local teamColor = player.TeamColor and player.TeamColor.Color or Config.OutlineColor

	-- Highlight
	hl.OutlineColor       = teamColor
	hl.OutlineTransparency = Config.OutlineTransparency

	-- Name
	nl.TextSize          = Config.NameSize
	nl.TextTransparency  = Config.NameTransparency
	nl.TextStrokeTransparency = Config.NameTransparency
	nl.TextColor3        = teamColor
	nl.Visible           = Config.ShowNameESP

	-- Health bar
	local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
	hbf.Size                 = UDim2.new(1, 0, 0, Config.HealthBarHeight)
	hbf.BackgroundTransparency = Config.HealthBarTransparency
	hbf.Visible              = Config.ShowHealthESP
	hbfl.Size                = UDim2.new(ratio, 0, 1, 0)
	hbfl.BackgroundColor3    = Color3.fromHSV(ratio * 0.33, 1, 1)
	hbfl.BackgroundTransparency = Config.HealthBarTransparency

	-- Distance
	dl.Text              = string.format("[%d]", math.round(distance))
	dl.TextSize          = Config.DistanceSize
	dl.TextColor3        = teamColor
	dl.TextTransparency  = Config.DistanceTransparency
	dl.TextStrokeTransparency = Config.DistanceTransparency
	dl.Visible           = Config.ShowDistanceESP

	-- Reflow billboard positions
	local offsetY = 0
	if Config.ShowNameESP     then nl.Position  = UDim2.new(0,0,0,offsetY); offsetY += 20 end
	if Config.ShowHealthESP   then hbf.Position = UDim2.new(0,0,0,offsetY); offsetY += Config.HealthBarHeight end
	if Config.ShowDistanceESP then dl.Position  = UDim2.new(0,0,0,offsetY) end
end

-- ─── Aimbot ──────────────────────────────────────────────────────────────────
-- IMPROVEMENT: getBestPartAndDist is only called once per player per frame
-- (not twice). Target selection skips WorldToViewportPoint if player is
-- already outside 3D distance. currentTarget is validated cheaply before
-- iterating all players.

local screenCenter = Vector2.new(0, 0) -- updated each frame

local function getBestPartAndDist(player)
	local character = player.Character
	if not character then return nil, math.huge end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return nil, math.huge end

	if Config.AimbotTeamCheck and LocalPlayer.Team and player.Team == LocalPlayer.Team then
		return nil, math.huge
	end

	local localChar = LocalPlayer.Character
	local localHRP  = localChar and localChar:FindFirstChild("HumanoidRootPart")
	local targetHRP = character:FindFirstChild("HumanoidRootPart")
	if not localHRP or not targetHRP then return nil, math.huge end

	if (localHRP.Position - targetHRP.Position).Magnitude > Config.AimbotMaxDistance then
		return nil, math.huge
	end

	local bestPart = nil
	local minDist  = math.huge

	for _, partName in ipairs(Config.AimbotTargets) do
		local part = character:FindFirstChild(partName)
		if part then
			local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
			if onScreen then
				local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
				if dist2D < Config.AimbotFOV and dist2D < minDist and isPartVisible(part) then
					bestPart = part
					minDist  = dist2D
				end
			end
		end
	end

	return bestPart, minDist
end

local function getAimbotTarget()
	-- Fast path: validate current target before scanning everyone
	if currentTarget then
		local alive = currentTarget.Character
			and currentTarget.Character:FindFirstChildOfClass("Humanoid")
		if alive and alive.Health > 0 then
			local part, dist = getBestPartAndDist(currentTarget)
			if part then return currentTarget, part end
		end
		currentTarget = nil
	end

	-- Full scan
	local bestValue = nil
	local bestPlayer, bestPartFound

	local mode = Config.AimbotTargetMode
	local localChar = LocalPlayer.Character
	local localHRP  = localChar and localChar:FindFirstChild("HumanoidRootPart")

	for _, player in ipairs(Players:GetPlayers()) do
		if player == LocalPlayer then continue end

		local part, dist2D = getBestPartAndDist(player)
		if not part then continue end

		if mode == "Any" then
			currentTarget = player
			return player, part
		end

		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		local targetHRP = player.Character:FindFirstChild("HumanoidRootPart")
		local dist3D = (localHRP and targetHRP)
			and (localHRP.Position - targetHRP.Position).Magnitude
			or  math.huge

		local val
		if     mode == "Closest Distance" then val = dist3D
		elseif mode == "Lowest HP"        then val = humanoid.Health
		elseif mode == "Highest HP"       then val = -humanoid.Health -- negate so min-compare works
		end

		if bestValue == nil or val < bestValue then
			bestValue    = val
			bestPlayer   = player
			bestPartFound = part
		end
	end

	currentTarget = bestPlayer
	return bestPlayer, bestPartFound
end

-- ─── FOV Circle ──────────────────────────────────────────────────────────────

local fovFrame, fovStroke -- module-level refs so we can update without searching

local function createFOVCircle()
	local gui       = Instance.new("ScreenGui")
	gui.Name        = "FOVCircle"
	gui.Parent      = LocalPlayer.PlayerGui
	gui.ResetOnSpawn= false
	gui.DisplayOrder= 999

	local frame     = Instance.new("Frame")
	frame.Name      = "MainFrame"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent    = gui

	local corner    = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent   = frame

	local stroke    = Instance.new("UIStroke")
	stroke.Color        = Color3.new(1, 1, 1)
	stroke.Thickness    = 1
	stroke.Transparency = Config.FOVCircleTransparency
	stroke.Parent   = frame

	fovFrame  = frame
	fovStroke = stroke
end

local function updateFOVCircle()
	if not fovFrame then return end
	local r = Config.AimbotFOV
	fovFrame.Size     = UDim2.new(0, r*2, 0, r*2)
	fovFrame.Position = UDim2.new(0.5, -r, 0.5, -r)
	if fovStroke then
		fovStroke.Transparency = Config.FOVCircleTransparency
	end
end

-- ─── GUI ─────────────────────────────────────────────────────────────────────
-- No functional changes to GUI – only minor cleanup (deduplicated corner
-- instance creation into a helper, removed redundant pcalls).

-- ═══════════════════════════════════════════════════════════════════
-- ═══════════════════════════════════════════════════════════════════
--  THEME SYSTEM
-- ═══════════════════════════════════════════════════════════════════

local THEMES = {
	{ name = "Void",     accent = Color3.fromRGB(0,   200, 255), bg = Color3.fromRGB(10, 11, 15) },
	{ name = "Crimson",  accent = Color3.fromRGB(220, 40,  80),  bg = Color3.fromRGB(14, 10, 12) },
	{ name = "Lime",     accent = Color3.fromRGB(80,  230, 80),  bg = Color3.fromRGB(10, 14, 10) },
	{ name = "Gold",     accent = Color3.fromRGB(255, 185, 0),   bg = Color3.fromRGB(14, 13, 9)  },
	{ name = "Lavender", accent = Color3.fromRGB(160, 100, 255), bg = Color3.fromRGB(12, 10, 16) },
	{ name = "White",    accent = Color3.fromRGB(240, 240, 240), bg = Color3.fromRGB(10, 11, 15) },
	{ name = "RGB",      accent = Color3.fromRGB(255, 0,   0),   bg = Color3.fromRGB(10, 11, 15) },
	{ name = "Custom",   accent = Color3.fromRGB(255, 100, 0),   bg = Color3.fromRGB(10, 11, 15) },
}
local currentThemeIdx = 1
local RGB_THEME_IDX   = 7
local rgbHue          = 0

local function buildCLR(accent, bg)
	local function lift(base, r, g, b)
		return Color3.fromRGB(
			math.clamp(math.floor(base.R*255)+r, 0, 255),
			math.clamp(math.floor(base.G*255)+g, 0, 255),
			math.clamp(math.floor(base.B*255)+b, 0, 255)
		)
	end
	local function scalec(c, f)
		return Color3.fromRGB(
			math.clamp(math.floor(c.R*255*f), 0, 255),
			math.clamp(math.floor(c.G*255*f), 0, 255),
			math.clamp(math.floor(c.B*255*f), 0, 255)
		)
	end
	return {
		BG        = bg,
		SURFACE   = lift(bg,  7,  8, 11),
		SURFACE2  = lift(bg, 14, 16, 22),
		BORDER    = lift(bg, 28, 31, 43),
		ACCENT    = accent,
		ACCENT_DIM= scalec(accent, 0.45),
		TEXT      = Color3.fromRGB(220, 225, 240),
		SUBTEXT   = Color3.fromRGB(110, 120, 150),
		TAB_IDLE  = lift(bg, 20, 23, 31),
		WARN      = Color3.fromRGB(255, 160, 0),
	}
end

local CLR = buildCLR(THEMES[1].accent, THEMES[1].bg)

-- Registry of elements to repaint on theme change
-- Entries are either { inst, prop, key } or { repaint = fn }
local themeRegistry = {}
local function reg(inst, prop, key)
	themeRegistry[#themeRegistry+1] = { inst=inst, prop=prop, key=key }
end
local function regFn(fn)
	themeRegistry[#themeRegistry+1] = { repaint=fn }
end

local function applyTheme()
	for _, e in ipairs(themeRegistry) do
		if e.repaint then
			pcall(e.repaint)
		elseif e.inst and e.inst.Parent then
			pcall(function() e.inst[e.prop] = CLR[e.key] end)
		end
	end
	if fovStroke then fovStroke.Color = CLR.ACCENT end
end

-- ─── RGB Cycling Loop ────────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function(dt)
	if currentThemeIdx ~= RGB_THEME_IDX then return end
	rgbHue = (rgbHue + dt * 0.25) % 1
	local h6 = rgbHue * 6
	local i  = math.floor(h6)
	local f  = h6 - i
	local q  = 1 - f
	local r, g, b
	if     i == 0 then r,g,b = 1, f, 0
	elseif i == 1 then r,g,b = q, 1, 0
	elseif i == 2 then r,g,b = 0, 1, f
	elseif i == 3 then r,g,b = 0, q, 1
	elseif i == 4 then r,g,b = f, 0, 1
	else               r,g,b = 1, 0, q
	end
	local newAccent = Color3.new(r, g, b)
	THEMES[RGB_THEME_IDX].accent = newAccent
	local rebuilt = buildCLR(newAccent, THEMES[RGB_THEME_IDX].bg)
	for k, v in pairs(rebuilt) do CLR[k] = v end
	applyTheme()
end)

-- ═══════════════════════════════════════════════════════════════════
--  GUI HELPERS  (all auto-register to themeRegistry)
-- ═══════════════════════════════════════════════════════════════════

local FONT_TITLE = Enum.Font.GothamBold
local FONT_BODY  = Enum.Font.Gotham
local FONT_MONO  = Enum.Font.RobotoMono

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 6)
	c.Parent = parent
	return c
end

local function mkStroke(parent, color, thick, trans)
	local s = Instance.new("UIStroke")
	s.Color        = color or CLR.BORDER
	s.Thickness    = thick or 1
	s.Transparency = trans or 0
	s.Parent       = parent
	return s
end

local function listLayout(parent, pad)
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding   = UDim.new(0, pad or 6)
	l.Parent    = parent
	return l
end

local function padInset(parent, top, right, bottom, left)
	local p = Instance.new("UIPadding")
	p.PaddingTop    = UDim.new(0, top    or 6)
	p.PaddingRight  = UDim.new(0, right  or 6)
	p.PaddingBottom = UDim.new(0, bottom or 6)
	p.PaddingLeft   = UDim.new(0, left   or 6)
	p.Parent = parent
end

-- Pill toggle — returns updateVisual(bool)
local function makePill(parent, labelText, initState, onToggle)
	local row = Instance.new("Frame")
	row.Size             = UDim2.new(1, 0, 0, 32)
	row.BackgroundColor3 = CLR.SURFACE2
	row.BorderSizePixel  = 0
	row.Parent           = parent
	corner(row, 8)
	reg(row, "BackgroundColor3", "SURFACE2")

	local lbl = Instance.new("TextLabel")
	lbl.Size                 = UDim2.new(1, -54, 1, 0)
	lbl.Position             = UDim2.new(0, 10, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text                 = labelText
	lbl.TextColor3           = CLR.TEXT
	lbl.Font                 = FONT_BODY
	lbl.TextSize             = 13
	lbl.TextXAlignment       = Enum.TextXAlignment.Left
	lbl.Parent               = row
	reg(lbl, "TextColor3", "TEXT")

	local track = Instance.new("Frame")
	track.Size             = UDim2.new(0, 36, 0, 18)
	track.Position         = UDim2.new(1, -46, 0.5, -9)
	track.BackgroundColor3 = initState and CLR.ACCENT or CLR.BORDER
	track.BorderSizePixel  = 0
	track.Parent           = row
	corner(track, 9)

	local knob = Instance.new("Frame")
	knob.Size              = UDim2.new(0, 12, 0, 12)
	knob.Position          = initState and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)
	knob.BackgroundColor3  = Color3.new(1,1,1)
	knob.BorderSizePixel   = 0
	knob.Parent            = track
	corner(knob, 6)

	local state = initState
	local function updateVisual(s)
		state                  = s
		track.BackgroundColor3 = s and CLR.ACCENT or CLR.BORDER
		knob.Position          = s and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,3,0.5,-6)
	end

	regFn(function()
		if track and track.Parent then
			track.BackgroundColor3 = state and CLR.ACCENT or CLR.BORDER
		end
	end)

	local btn = Instance.new("TextButton")
	btn.Size                 = UDim2.new(1,0,1,0)
	btn.BackgroundTransparency = 1
	btn.Text                 = ""
	btn.AutoButtonColor      = false
	btn.Parent               = row
	btn.MouseButton1Click:Connect(function()
		updateVisual(onToggle())
	end)

	return updateVisual
end

-- Keybind row
local function makeKeybind(parent, labelText, getKey, onSet)
	local row = Instance.new("Frame")
	row.Size             = UDim2.new(1, 0, 0, 32)
	row.BackgroundColor3 = CLR.SURFACE2
	row.BorderSizePixel  = 0
	row.Parent           = parent
	corner(row, 8)
	reg(row, "BackgroundColor3", "SURFACE2")

	local lbl = Instance.new("TextLabel")
	lbl.Size                 = UDim2.new(0.55, 0, 1, 0)
	lbl.Position             = UDim2.new(0, 10, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text                 = labelText
	lbl.TextColor3           = CLR.SUBTEXT
	lbl.Font                 = FONT_BODY
	lbl.TextSize             = 12
	lbl.TextXAlignment       = Enum.TextXAlignment.Left
	lbl.Parent               = row
	reg(lbl, "TextColor3", "SUBTEXT")

	local keyBtn = Instance.new("TextButton")
	keyBtn.Size             = UDim2.new(0, 68, 0, 22)
	keyBtn.Position         = UDim2.new(1, -76, 0.5, -11)
	keyBtn.BackgroundColor3 = CLR.BG
	keyBtn.TextColor3       = CLR.ACCENT
	keyBtn.Font             = FONT_MONO
	keyBtn.TextSize         = 11
	keyBtn.Text             = "[" .. getKey().Name .. "]"
	keyBtn.AutoButtonColor  = false
	keyBtn.Parent           = row
	corner(keyBtn, 5)
	local ks = mkStroke(keyBtn, CLR.ACCENT_DIM, 1)
	reg(keyBtn, "BackgroundColor3", "BG")
	reg(keyBtn, "TextColor3",       "ACCENT")
	reg(ks,     "Color",            "ACCENT_DIM")

	keyBtn.MouseButton1Click:Connect(function()
		keyBtn.Text       = "..."
		keyBtn.TextColor3 = CLR.WARN
		local inp = UserInputService.InputBegan:Wait()
		if inp.KeyCode ~= Enum.KeyCode.Unknown then
			onSet(inp.KeyCode)
			keyBtn.Text = "[" .. inp.KeyCode.Name .. "]"
		else
			keyBtn.Text = "[" .. getKey().Name .. "]"
		end
		keyBtn.TextColor3 = CLR.ACCENT
	end)

	return keyBtn
end

-- Slider
local function makeSlider(parent, labelText, initRatio, onDrag)
	local wrap = Instance.new("Frame")
	wrap.Size              = UDim2.new(1, 0, 0, 46)
	wrap.BackgroundColor3  = CLR.SURFACE2
	wrap.BorderSizePixel   = 0
	wrap.Parent            = parent
	corner(wrap, 8)
	reg(wrap, "BackgroundColor3", "SURFACE2")

	local lbl = Instance.new("TextLabel")
	lbl.Size               = UDim2.new(0.65, 0, 0, 18)
	lbl.Position           = UDim2.new(0, 10, 0, 6)
	lbl.BackgroundTransparency = 1
	lbl.Text               = labelText
	lbl.TextColor3         = CLR.TEXT
	lbl.Font               = FONT_BODY
	lbl.TextSize           = 12
	lbl.TextXAlignment     = Enum.TextXAlignment.Left
	lbl.Parent             = wrap
	reg(lbl, "TextColor3", "TEXT")

	local valLbl = Instance.new("TextLabel")
	valLbl.Size            = UDim2.new(0.35, -10, 0, 18)
	valLbl.Position        = UDim2.new(0.65, 0, 0, 6)
	valLbl.BackgroundTransparency = 1
	valLbl.Text            = ""
	valLbl.TextColor3      = CLR.ACCENT
	valLbl.Font            = FONT_MONO
	valLbl.TextSize        = 11
	valLbl.TextXAlignment  = Enum.TextXAlignment.Right
	valLbl.Parent          = wrap
	reg(valLbl, "TextColor3", "ACCENT")

	local track = Instance.new("Frame")
	track.Size             = UDim2.new(1, -20, 0, 4)
	track.Position         = UDim2.new(0, 10, 0, 30)
	track.BackgroundColor3 = CLR.BORDER
	track.BorderSizePixel  = 0
	track.Parent           = wrap
	corner(track, 2)
	reg(track, "BackgroundColor3", "BORDER")

	local fill = Instance.new("Frame")
	fill.Size              = UDim2.new(math.clamp(initRatio,0,1), 0, 1, 0)
	fill.BackgroundColor3  = CLR.ACCENT
	fill.BorderSizePixel   = 0
	fill.Parent            = track
	corner(fill, 2)
	reg(fill, "BackgroundColor3", "ACCENT")

	local knob = Instance.new("Frame")
	knob.Size              = UDim2.new(0, 10, 0, 10)
	knob.AnchorPoint       = Vector2.new(0.5, 0.5)
	knob.Position          = UDim2.new(math.clamp(initRatio,0,1), 0, 0.5, 0)
	knob.BackgroundColor3  = Color3.new(1,1,1)
	knob.BorderSizePixel   = 0
	knob.ZIndex            = 2
	knob.Parent            = track
	corner(knob, 5)

	local dragging = false
	local hitbox = Instance.new("TextButton")
	hitbox.Size              = UDim2.new(1, 0, 0, 20)
	hitbox.Position          = UDim2.new(0, 0, 0, -8)
	hitbox.BackgroundTransparency = 1
	hitbox.Text              = ""
	hitbox.ZIndex            = 3
	hitbox.AutoButtonColor   = false
	hitbox.Parent            = track
	hitbox.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end
	end)
	hitbox.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)
	UserInputService.InputChanged:Connect(function(inp)
		if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
			local ratio = math.clamp(
				(inp.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
			fill.Size     = UDim2.new(ratio, 0, 1, 0)
			knob.Position = UDim2.new(ratio, 0, 0.5, 0)
			local dv = onDrag(ratio)
			if dv then valLbl.Text = tostring(dv) end
		end
	end)

	local ok, initVal = pcall(onDrag, initRatio)
	if ok and initVal then valLbl.Text = tostring(initVal) end
	fill.Size     = UDim2.new(math.clamp(initRatio,0,1), 0, 1, 0)
	knob.Position = UDim2.new(math.clamp(initRatio,0,1), 0, 0.5, 0)

	return valLbl
end

-- Cycle button
local function makeCycle(parent, labelText, options, initIdx, onCycle)
	local row = Instance.new("Frame")
	row.Size             = UDim2.new(1, 0, 0, 32)
	row.BackgroundColor3 = CLR.SURFACE2
	row.BorderSizePixel  = 0
	row.Parent           = parent
	corner(row, 8)
	reg(row, "BackgroundColor3", "SURFACE2")

	local lbl = Instance.new("TextLabel")
	lbl.Size                 = UDim2.new(0.45, 0, 1, 0)
	lbl.Position             = UDim2.new(0, 10, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text                 = labelText
	lbl.TextColor3           = CLR.SUBTEXT
	lbl.Font                 = FONT_BODY
	lbl.TextSize             = 12
	lbl.TextXAlignment       = Enum.TextXAlignment.Left
	lbl.Parent               = row
	reg(lbl, "TextColor3", "SUBTEXT")

	local valBtn = Instance.new("TextButton")
	valBtn.Size             = UDim2.new(0.55, -10, 0, 22)
	valBtn.Position         = UDim2.new(0.45, 0, 0.5, -11)
	valBtn.BackgroundColor3 = CLR.BG
	valBtn.TextColor3       = CLR.ACCENT
	valBtn.Font             = FONT_BODY
	valBtn.TextSize         = 11
	valBtn.Text             = options[initIdx]
	valBtn.AutoButtonColor  = false
	valBtn.Parent           = row
	corner(valBtn, 5)
	local vs = mkStroke(valBtn, CLR.ACCENT_DIM, 1)
	reg(valBtn, "BackgroundColor3", "BG")
	reg(valBtn, "TextColor3",       "ACCENT")
	reg(vs,     "Color",            "ACCENT_DIM")

	local idx = initIdx
	valBtn.MouseButton1Click:Connect(function()
		idx = (idx % #options) + 1
		valBtn.Text = options[idx]
		onCycle(idx, options[idx])
	end)
	return valBtn
end

-- Section label
local function makeSectionLabel(parent, text)
	local lbl = Instance.new("TextLabel")
	lbl.Size                 = UDim2.new(1, 0, 0, 20)
	lbl.BackgroundTransparency = 1
	lbl.Text                 = text
	lbl.TextColor3           = CLR.SUBTEXT
	lbl.Font                 = FONT_TITLE
	lbl.TextSize             = 10
	lbl.TextXAlignment       = Enum.TextXAlignment.Left
	lbl.Parent               = parent
	reg(lbl, "TextColor3", "SUBTEXT")
	return lbl
end

-- Scrollable pane
local function makePane(parent)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size                = UDim2.new(1, 0, 1, 0)
	scroll.BackgroundTransparency = 1
	scroll.ScrollingDirection  = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness  = 3
	scroll.ScrollBarImageColor3= CLR.ACCENT_DIM
	scroll.CanvasSize          = UDim2.new(0,0,0,0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.BorderSizePixel     = 0
	scroll.Parent              = parent
	reg(scroll, "ScrollBarImageColor3", "ACCENT_DIM")
	listLayout(scroll, 6)
	padInset(scroll, 8, 8, 12, 8)
	return scroll
end

-- ═══════════════════════════════════════════════════════════════════
--  createGUI
-- ═══════════════════════════════════════════════════════════════════

local function createGUI()
	local pg = LocalPlayer.PlayerGui
	if not pg then return end

	local sg = Instance.new("ScreenGui")
	sg.Name         = "ESP_Aimbot_Config"
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 1000
	sg.Parent       = pg

	-- ── Collapsed pill ──────────────────────────────────────────────
	local pill = Instance.new("TextButton")
	pill.Name             = "CollapsedPill"
	pill.Size             = UDim2.new(0, 96, 0, 30)
	pill.Position         = UDim2.new(0, 14, 0, 14)
	pill.BackgroundColor3 = CLR.SURFACE
	pill.TextColor3       = CLR.ACCENT
	pill.Font             = FONT_TITLE
	pill.TextSize         = 12
	pill.Text             = "◈  VOID"
	pill.Visible          = false
	pill.ZIndex           = 10
	pill.AutoButtonColor  = false
	pill.Parent           = sg
	corner(pill, 15)
	local pillStroke = mkStroke(pill, CLR.ACCENT, 1, 0.35)
	reg(pill,        "BackgroundColor3", "SURFACE")
	reg(pill,        "TextColor3",       "ACCENT")
	reg(pillStroke,  "Color",            "ACCENT")

	-- ── Main window ─────────────────────────────────────────────────
	local win = Instance.new("Frame")
	win.Name             = "MainFrame"
	win.Size             = UDim2.new(0, 300, 0, 440)
	win.Position         = UDim2.new(0, 14, 0, 14)
	win.BackgroundColor3 = CLR.BG
	win.BorderSizePixel  = 0
	win.ClipsDescendants = true
	win.Parent           = sg
	corner(win, 12)
	local winStroke = mkStroke(win, CLR.BORDER, 1)
	reg(win,       "BackgroundColor3", "BG")
	reg(winStroke, "Color",            "BORDER")

	-- ── Title bar ───────────────────────────────────────────────────
	local titleBar = Instance.new("Frame")
	titleBar.Size             = UDim2.new(1, 0, 0, 44)
	titleBar.BackgroundColor3 = CLR.SURFACE
	titleBar.BorderSizePixel  = 0
	titleBar.Parent           = win
	reg(titleBar, "BackgroundColor3", "SURFACE")

	local accentLine = Instance.new("Frame")
	accentLine.Size             = UDim2.new(1, 0, 0, 2)
	accentLine.Position         = UDim2.new(0, 0, 1, -2)
	accentLine.BackgroundColor3 = CLR.ACCENT
	accentLine.BorderSizePixel  = 0
	accentLine.Parent           = titleBar
	reg(accentLine, "BackgroundColor3", "ACCENT")

	local titleIcon = Instance.new("TextLabel")
	titleIcon.Size                 = UDim2.new(0, 30, 1, 0)
	titleIcon.Position             = UDim2.new(0, 10, 0, 0)
	titleIcon.BackgroundTransparency = 1
	titleIcon.Text                 = "◈"
	titleIcon.TextColor3           = CLR.ACCENT
	titleIcon.Font                 = FONT_TITLE
	titleIcon.TextSize             = 18
	titleIcon.Parent               = titleBar
	reg(titleIcon, "TextColor3", "ACCENT")

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size                 = UDim2.new(1, -90, 1, 0)
	titleLbl.Position             = UDim2.new(0, 40, 0, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text                 = "VOID  v2.1"
	titleLbl.TextColor3           = CLR.TEXT
	titleLbl.Font                 = FONT_TITLE
	titleLbl.TextSize             = 13
	titleLbl.TextXAlignment       = Enum.TextXAlignment.Left
	titleLbl.Parent               = titleBar
	reg(titleLbl, "TextColor3", "TEXT")

	local subLbl = Instance.new("TextLabel")
	subLbl.Size                 = UDim2.new(1, -90, 0, 14)
	subLbl.Position             = UDim2.new(0, 40, 0, 26)
	subLbl.BackgroundTransparency = 1
	subLbl.Text                 = "ESP · AIMBOT · MOVEMENT"
	subLbl.TextColor3           = CLR.SUBTEXT
	subLbl.Font                 = FONT_BODY
	subLbl.TextSize             = 9
	subLbl.TextXAlignment       = Enum.TextXAlignment.Left
	subLbl.Parent               = titleBar
	reg(subLbl, "TextColor3", "SUBTEXT")

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size             = UDim2.new(0, 28, 0, 28)
	closeBtn.Position         = UDim2.new(1, -36, 0.5, -14)
	closeBtn.BackgroundColor3 = CLR.SURFACE2
	closeBtn.TextColor3       = CLR.SUBTEXT
	closeBtn.Font             = FONT_TITLE
	closeBtn.TextSize         = 14
	closeBtn.Text             = "–"
	closeBtn.AutoButtonColor  = false
	closeBtn.Parent           = titleBar
	corner(closeBtn, 7)
	reg(closeBtn, "BackgroundColor3", "SURFACE2")
	reg(closeBtn, "TextColor3",       "SUBTEXT")
	closeBtn.MouseEnter:Connect(function() closeBtn.TextColor3 = CLR.ACCENT end)
	closeBtn.MouseLeave:Connect(function() closeBtn.TextColor3 = CLR.SUBTEXT end)
	closeBtn.MouseButton1Click:Connect(function()
		win.Visible  = false
		pill.Visible = true
	end)
	pill.MouseButton1Click:Connect(function()
		win.Visible  = true
		pill.Visible = false
	end)

	-- ── Drag ────────────────────────────────────────────────────────
	local dragging, dragStart, startPos
	local function setupDrag(el)
		el.InputBegan:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging  = true
				dragStart = inp.Position
				startPos  = win.Position
				inp.Changed:Connect(function()
					if inp.UserInputState == Enum.UserInputState.End then dragging = false end
				end)
			end
		end)
		el.InputChanged:Connect(function(inp)
			if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
				local d  = inp.Position - dragStart
				local np = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X,
					startPos.Y.Scale, startPos.Y.Offset+d.Y)
				win.Position  = np
				pill.Position = np
			end
		end)
	end
	setupDrag(titleBar)
	setupDrag(pill)

	-- ── Tab bar ─────────────────────────────────────────────────────
	local TAB_NAMES = {"ESP","AIMBOT","MOVE","ENV","THEME"}
	local TAB_ICONS = {"👁","🎯","🏃","🌤","🎨"}

	local tabBar = Instance.new("Frame")
	tabBar.Size             = UDim2.new(1, 0, 0, 38)
	tabBar.Position         = UDim2.new(0, 0, 0, 44)
	tabBar.BackgroundColor3 = CLR.SURFACE
	tabBar.BorderSizePixel  = 0
	tabBar.Parent           = win
	reg(tabBar, "BackgroundColor3", "SURFACE")

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection       = Enum.FillDirection.Horizontal
	tabLayout.SortOrder           = Enum.SortOrder.LayoutOrder
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
	tabLayout.Padding             = UDim.new(0, 2)
	tabLayout.Parent              = tabBar

	local contentArea = Instance.new("Frame")
	contentArea.Size             = UDim2.new(1, 0, 1, -82)
	contentArea.Position         = UDim2.new(0, 0, 0, 82)
	contentArea.BackgroundTransparency = 1
	contentArea.ClipsDescendants = true
	contentArea.Parent           = win

	local pages    = {}
	local tabBtns  = {}
	local tabUnders= {}
	local activeTab = 1

	for i, name in ipairs(TAB_NAMES) do
		local pane = makePane(contentArea)
		pane.Visible = (i == 1)
		pages[i] = pane

		local tb = Instance.new("TextButton")
		tb.Size             = UDim2.new(0, 52, 0, 32)
		tb.BackgroundColor3 = i == 1 and CLR.SURFACE2 or CLR.TAB_IDLE
		tb.TextColor3       = i == 1 and CLR.ACCENT   or CLR.SUBTEXT
		tb.Font             = FONT_TITLE
		tb.TextSize         = 10
		tb.Text             = TAB_ICONS[i] .. " " .. name
		tb.BorderSizePixel  = 0
		tb.AutoButtonColor  = false
		tb.Parent           = tabBar
		corner(tb, 6)
		tabBtns[i] = tb

		local under = Instance.new("Frame")
		under.Size             = UDim2.new(0.7, 0, 0, 2)
		under.Position         = UDim2.new(0.15, 0, 1, -3)
		under.BackgroundColor3 = CLR.ACCENT
		under.BorderSizePixel  = 0
		under.Visible          = (i == 1)
		under.Parent           = tb
		corner(under, 1)
		tabUnders[i] = under

		-- State-aware repaint for this tab button
		do
			local ci = i
			regFn(function()
				if not (tb and tb.Parent) then return end
				if ci == activeTab then
					tb.BackgroundColor3 = CLR.SURFACE2
					tb.TextColor3       = CLR.ACCENT
				else
					tb.BackgroundColor3 = CLR.TAB_IDLE
					tb.TextColor3       = CLR.SUBTEXT
				end
				if under and under.Parent then
					under.BackgroundColor3 = CLR.ACCENT
				end
			end)
		end

		tb.MouseButton1Click:Connect(function()
			pages[activeTab].Visible          = false
			tabBtns[activeTab].BackgroundColor3 = CLR.TAB_IDLE
			tabBtns[activeTab].TextColor3       = CLR.SUBTEXT
			tabUnders[activeTab].Visible        = false
			activeTab = i
			pages[i].Visible    = true
			tb.BackgroundColor3 = CLR.SURFACE2
			tb.TextColor3       = CLR.ACCENT
			under.Visible       = true
		end)
	end

	local espPane   = pages[1]
	local abPane    = pages[2]
	local mvPane    = pages[3]
	local envPane   = pages[4]
	local themePane = pages[5]

	-- ════════════════════ ESP PAGE ════════════════════

	makeSectionLabel(espPane, "  VISIBILITY")

	local espTogPill = makePill(espPane, "ESP", Config.ESPEnabled, function()
		Config.ESPEnabled = not Config.ESPEnabled
		if not Config.ESPEnabled then for p in pairs(playerCache) do clearCache(p) end end
		return Config.ESPEnabled
	end)
	syncPills.esp = espTogPill

	makeKeybind(espPane, "Toggle Key", function() return Config.ESPKey end, function(kc)
		Config.ESPKey = kc
	end)
	makePill(espPane, "Show Names",    Config.ShowNameESP,     function() Config.ShowNameESP     = not Config.ShowNameESP;     return Config.ShowNameESP     end)
	makePill(espPane, "Show Health",   Config.ShowHealthESP,   function() Config.ShowHealthESP   = not Config.ShowHealthESP;   return Config.ShowHealthESP   end)
	makePill(espPane, "Show Distance", Config.ShowDistanceESP, function() Config.ShowDistanceESP = not Config.ShowDistanceESP; return Config.ShowDistanceESP end)

	makeSectionLabel(espPane, "  APPEARANCE")

	makeSlider(espPane, "Name Size",      (Config.NameSize-10)/20,           function(r) Config.NameSize = math.floor(r*20)+10; return Config.NameSize end)
	makeSlider(espPane, "Name Opacity",   1-Config.NameTransparency,         function(r) Config.NameTransparency = 1-r; return string.format("%.0f%%",r*100) end)
	makeSlider(espPane, "Outline Opacity",1-Config.OutlineTransparency,      function(r) Config.OutlineTransparency = 1-r; return string.format("%.0f%%",r*100) end)
	makeSlider(espPane, "HP Bar Height",  (Config.HealthBarHeight-1)/9,      function(r) Config.HealthBarHeight = math.floor(r*9)+1; return Config.HealthBarHeight end)
	makeSlider(espPane, "HP Bar Opacity", 1-Config.HealthBarTransparency,    function(r) Config.HealthBarTransparency = 1-r; return string.format("%.0f%%",r*100) end)
	makeSlider(espPane, "Dist Size",      (Config.DistanceSize-10)/20,       function(r) Config.DistanceSize = math.floor(r*20)+10; return Config.DistanceSize end)
	makeSlider(espPane, "Dist Opacity",   1-Config.DistanceTransparency,     function(r) Config.DistanceTransparency = 1-r; return string.format("%.0f%%",r*100) end)
	makeSlider(espPane, "Max Distance",   (Config.MaxDistance-100)/1900,     function(r) Config.MaxDistance = math.floor(r*1900)+100; return Config.MaxDistance end)

	-- ════════════════════ AIMBOT PAGE ════════════════════

	makeSectionLabel(abPane, "  CONTROL")

	local abTogPill = makePill(abPane, "Aimbot", Config.AimbotEnabled, function()
		Config.AimbotEnabled = not Config.AimbotEnabled; return Config.AimbotEnabled
	end)
	syncPills.aimbot = abTogPill

	makeKeybind(abPane, "Hold Key", function() return Config.AimbotKey end, function(kc) Config.AimbotKey = kc end)
	makePill(abPane, "Team Check", Config.AimbotTeamCheck,  function() Config.AimbotTeamCheck  = not Config.AimbotTeamCheck;  return Config.AimbotTeamCheck  end)
	makePill(abPane, "Wall Check", Config.WallCheckEnabled, function() Config.WallCheckEnabled = not Config.WallCheckEnabled; return Config.WallCheckEnabled end)

	makeSectionLabel(abPane, "  TARGETING")

	local modes = {"Any","Highest HP","Lowest HP","Closest Distance"}
	local modeIdx = table.find(modes, Config.AimbotTargetMode) or 1
	makeCycle(abPane, "Target Mode", modes, modeIdx, function(_, v)
		Config.AimbotTargetMode = v; currentTarget = nil
	end)

	makeSectionLabel(abPane, "  TARGET PARTS")

	local allParts = {"Head","HumanoidRootPart","UpperTorso","LowerTorso",
		"LeftUpperArm","RightUpperArm","LeftLowerArm","RightLowerArm",
		"LeftHand","RightHand","LeftUpperLeg","RightUpperLeg",
		"LeftLowerLeg","RightLowerLeg","LeftFoot","RightFoot"}
	for _, pn in ipairs(allParts) do
		makePill(abPane, pn, table.find(Config.AimbotTargets,pn)~=nil, function()
			local idx = table.find(Config.AimbotTargets, pn)
			if idx then table.remove(Config.AimbotTargets, idx); return false
			else        table.insert(Config.AimbotTargets, pn);  return true end
		end)
	end

	makeSectionLabel(abPane, "  TUNING")

	makeSlider(abPane, "Smoothness",   (Config.AimbotSpeed-0.1)/0.9,        function(r) Config.AimbotSpeed = r*0.9+0.1; return string.format("%.2f",Config.AimbotSpeed) end)
	makeSlider(abPane, "FOV Radius",   (Config.AimbotFOV-10)/190,           function(r) Config.AimbotFOV = math.floor(r*190)+10; updateFOVCircle(); return Config.AimbotFOV end)
	makeSlider(abPane, "FOV Opacity",  1-Config.FOVCircleTransparency,      function(r) Config.FOVCircleTransparency = 1-r; if fovStroke then fovStroke.Transparency=1-r end; return string.format("%.0f%%",r*100) end)
	makeSlider(abPane, "Max Distance", (Config.AimbotMaxDistance-100)/4900, function(r) Config.AimbotMaxDistance = math.floor(r*4900)+100; return Config.AimbotMaxDistance end)

	makeSectionLabel(abPane, "  RANDOM OFFSET")

	makePill(abPane, "Random Offset", Config.AimbotRandomOffset, function()
		Config.AimbotRandomOffset = not Config.AimbotRandomOffset; return Config.AimbotRandomOffset
	end)
	makeSlider(abPane, "Offset Max", Config.AimbotOffsetMax/2, function(r)
		Config.AimbotOffsetMax = r*2; return string.format("%.2f",Config.AimbotOffsetMax)
	end)

	local offsetModes = {"PerLock","Periodic"}
	local omIdx = table.find(offsetModes, Config.AimbotOffsetMode) or 1
	local delayWrap

	makeCycle(abPane, "Offset Mode", offsetModes, omIdx, function(_, v)
		Config.AimbotOffsetMode = v
		if delayWrap then delayWrap.Visible = (v == "Periodic") end
	end)

	delayWrap = Instance.new("Frame")
	delayWrap.Size              = UDim2.new(1,0,0,0)
	delayWrap.AutomaticSize     = Enum.AutomaticSize.Y
	delayWrap.BackgroundTransparency = 1
	delayWrap.Visible           = Config.AimbotOffsetMode == "Periodic"
	delayWrap.Parent            = abPane
	local dw = Instance.new("UIListLayout")
	dw.Padding = UDim.new(0,6); dw.Parent = delayWrap

	makeSlider(delayWrap, "Re-roll Delay", (Config.AimbotOffsetUpdateInterval-0.1)/9.9, function(r)
		Config.AimbotOffsetUpdateInterval = r*9.9+0.1
		return string.format("%.1fs", Config.AimbotOffsetUpdateInterval)
	end)

	-- ════════════════════ MOVEMENT PAGE ════════════════════

	makeSectionLabel(mvPane, "  FLY")

	local flyPill = makePill(mvPane, "Fly", Config.FlyEnabled, function()
		if Config.FlyForceDisabled then return Config.FlyEnabled end
		Config.FlyEnabled = not Config.FlyEnabled; return Config.FlyEnabled
	end)
	syncPills.fly = flyPill

	makeKeybind(mvPane, "Fly Key", function() return Config.FlyKey end, function(kc) Config.FlyKey = kc end)
	makeSlider(mvPane, "Fly Speed", (Config.FlySpeed-10)/190, function(r)
		Config.FlySpeed = math.floor(r*190)+10; return Config.FlySpeed
	end)
	makePill(mvPane, "Force Disable Fly", Config.FlyForceDisabled, function()
		Config.FlyForceDisabled = not Config.FlyForceDisabled
		if Config.FlyForceDisabled and Config.FlyEnabled then
			Config.FlyEnabled = false; flyPill(false)
		end
		return Config.FlyForceDisabled
	end)

	makeSectionLabel(mvPane, "  NOCLIP")

	local ncPill = makePill(mvPane, "Noclip", Config.NoclipEnabled, function()
		if Config.NoclipForceDisabled then return Config.NoclipEnabled end
		Config.NoclipEnabled = not Config.NoclipEnabled
		if not Config.NoclipEnabled then
			local ch = LocalPlayer.Character
			if ch then for _,p in ipairs(ch:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=true end end end
		end
		return Config.NoclipEnabled
	end)
	syncPills.noclip = ncPill

	makeKeybind(mvPane, "Noclip Key", function() return Config.NoclipKey end, function(kc) Config.NoclipKey = kc end)
	makePill(mvPane, "Force Disable Noclip", Config.NoclipForceDisabled, function()
		Config.NoclipForceDisabled = not Config.NoclipForceDisabled
		if Config.NoclipForceDisabled and Config.NoclipEnabled then
			Config.NoclipEnabled = false; ncPill(false)
			local ch = LocalPlayer.Character
			if ch then for _,p in ipairs(ch:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=true end end end
		end
		return Config.NoclipForceDisabled
	end)

	makeSectionLabel(mvPane, "  SPEED")

	local shPill = makePill(mvPane, "Speed Hack", Config.SpeedHackEnabled, function()
		if Config.SpeedHackForceDisabled then return Config.SpeedHackEnabled end
		Config.SpeedHackEnabled = not Config.SpeedHackEnabled
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = Config.SpeedHackEnabled and Config.SpeedHackValue or 16 end
		return Config.SpeedHackEnabled
	end)
	syncPills.speed = shPill

	makeKeybind(mvPane, "Speed Key", function() return Config.SpeedHackKey end, function(kc) Config.SpeedHackKey = kc end)
	makeSlider(mvPane, "Walk Speed", (Config.SpeedHackValue-16)/84, function(r)
		Config.SpeedHackValue = math.floor(r*84)+16
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum and Config.SpeedHackEnabled then hum.WalkSpeed = Config.SpeedHackValue end
		return Config.SpeedHackValue
	end)
	makePill(mvPane, "Always Override Speed", Config.SpeedHackAlwaysOverride, function()
		Config.SpeedHackAlwaysOverride = not Config.SpeedHackAlwaysOverride
		return Config.SpeedHackAlwaysOverride
	end)
	makePill(mvPane, "Force Disable Speed", Config.SpeedHackForceDisabled, function()
		Config.SpeedHackForceDisabled = not Config.SpeedHackForceDisabled
		if Config.SpeedHackForceDisabled and Config.SpeedHackEnabled then
			Config.SpeedHackEnabled = false; shPill(false)
			local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum.WalkSpeed = 16 end
		end
		return Config.SpeedHackForceDisabled
	end)

	makeSectionLabel(mvPane, "  JUMP")

	local ijPill = makePill(mvPane, "Infinite Jump", Config.InfiniteJumpEnabled, function()
		if Config.InfiniteJumpForceDisabled then return Config.InfiniteJumpEnabled end
		Config.InfiniteJumpEnabled = not Config.InfiniteJumpEnabled
		return Config.InfiniteJumpEnabled
	end)
	syncPills.jump = ijPill

	makeKeybind(mvPane, "Jump Key", function() return Config.InfiniteJumpKey end, function(kc) Config.InfiniteJumpKey = kc end)
	makePill(mvPane, "Force Disable Jump", Config.InfiniteJumpForceDisabled, function()
		Config.InfiniteJumpForceDisabled = not Config.InfiniteJumpForceDisabled
		if Config.InfiniteJumpForceDisabled and Config.InfiniteJumpEnabled then
			Config.InfiniteJumpEnabled = false; ijPill(false)
		end
		return Config.InfiniteJumpForceDisabled
	end)

	-- ════════════════════ ENVIRONMENT PAGE ════════════════════

	makeSectionLabel(envPane, "  LIGHTING OVERRIDE")

	local defLightPill
	local todPill

	defLightPill = makePill(envPane, "Default Roblox Lighting", Config.DefaultLightingEnabled, function()
		Config.DefaultLightingEnabled = not Config.DefaultLightingEnabled
		if Config.DefaultLightingEnabled then
			if Config.TimeOfDayEnabled then
				Config.TimeOfDayEnabled = false
				if todPill then todPill(false) end
			end
			applyLightingProps(DEFAULT_LIGHTING)
			disableLightingChildren()
		else
			applyLightingProps(originalLighting)
			restoreLightingChildren()
		end
		return Config.DefaultLightingEnabled
	end)

	-- Red revert button
	local revertRow = Instance.new("Frame")
	revertRow.Size             = UDim2.new(1,0,0,32)
	revertRow.BackgroundColor3 = Color3.fromRGB(55,18,18)
	revertRow.BorderSizePixel  = 0
	revertRow.Parent           = envPane
	corner(revertRow, 8)
	mkStroke(revertRow, Color3.fromRGB(140,40,40), 1)

	local revertBtn = Instance.new("TextButton")
	revertBtn.Size                 = UDim2.new(1,0,1,0)
	revertBtn.BackgroundTransparency = 1
	revertBtn.Text                 = "⟳  Revert to Game Lighting"
	revertBtn.TextColor3           = Color3.fromRGB(255,90,90)
	revertBtn.Font                 = FONT_TITLE
	revertBtn.TextSize             = 12
	revertBtn.AutoButtonColor      = false
	revertBtn.Parent               = revertRow
	revertBtn.MouseEnter:Connect(function() revertRow.BackgroundColor3 = Color3.fromRGB(80,22,22) end)
	revertBtn.MouseLeave:Connect(function() revertRow.BackgroundColor3 = Color3.fromRGB(55,18,18) end)
	revertBtn.MouseButton1Click:Connect(function()
		Config.DefaultLightingEnabled = false
		Config.TimeOfDayEnabled       = false
		defLightPill(false)
		if todPill then todPill(false) end
		applyLightingProps(originalLighting)
		restoreLightingChildren()
	end)

	makeSectionLabel(envPane, "  TIME OF DAY")

	todPill = makePill(envPane, "Time of Day Override", Config.TimeOfDayEnabled, function()
		Config.TimeOfDayEnabled = not Config.TimeOfDayEnabled
		if Config.TimeOfDayEnabled then
			if Config.DefaultLightingEnabled then
				Config.DefaultLightingEnabled = false
				defLightPill(false)
				applyLightingProps(originalLighting)
				restoreLightingChildren()
			end
			Lighting.TimeOfDay = minutesToTimeString(Config.TimeOfDayMinutes)
		else
			Lighting.TimeOfDay = originalTimeOfDay
		end
		return Config.TimeOfDayEnabled
	end)
	syncPills.tod = todPill

	makeSlider(envPane, "Time of Day", Config.TimeOfDayMinutes/1440, function(r)
		Config.TimeOfDayMinutes = r*1440
		local ts = minutesToTimeString(Config.TimeOfDayMinutes)
		if Config.TimeOfDayEnabled then Lighting.TimeOfDay = ts end
		return ts
	end)

	-- ════════════════════ THEME PAGE ════════════════════

	makeSectionLabel(themePane, "  PRESETS")

	local presetGrid = Instance.new("Frame")
	presetGrid.Size              = UDim2.new(1, 0, 0, 0)
	presetGrid.AutomaticSize     = Enum.AutomaticSize.Y
	presetGrid.BackgroundTransparency = 1
	presetGrid.Parent            = themePane

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize    = UDim2.new(0.5, -4, 0, 30)
	gridLayout.CellPadding = UDim2.new(0, 4, 0, 4)
	gridLayout.SortOrder   = Enum.SortOrder.LayoutOrder
	gridLayout.Parent      = presetGrid

	local presetBtns = {}

	local function refreshPresetBtns()
		for idx, btn in ipairs(presetBtns) do
			if idx == currentThemeIdx then
				btn.BackgroundColor3 = CLR.ACCENT
				btn.TextColor3       = CLR.BG
			else
				btn.BackgroundColor3 = CLR.SURFACE2
				btn.TextColor3       = CLR.TEXT
			end
		end
	end

	for i, theme in ipairs(THEMES) do
		local btn = Instance.new("TextButton")
		btn.Size             = UDim2.new(1, 0, 1, 0)
		btn.BackgroundColor3 = i == currentThemeIdx and CLR.ACCENT or CLR.SURFACE2
		btn.TextColor3       = i == currentThemeIdx and CLR.BG     or CLR.TEXT
		btn.Font             = FONT_TITLE
		btn.TextSize         = 11
		btn.Text             = theme.name
		btn.BorderSizePixel  = 0
		btn.AutoButtonColor  = false
		btn.Parent           = presetGrid
		corner(btn, 6)
		presetBtns[i] = btn

		local dot = Instance.new("Frame")
		dot.Size             = UDim2.new(0, 8, 0, 8)
		dot.Position         = UDim2.new(0, 8, 0.5, -4)
		dot.BackgroundColor3 = theme.accent
		dot.BorderSizePixel  = 0
		dot.Parent           = btn
		corner(dot, 4)

		regFn(function()
			if not (btn and btn.Parent) then return end
			if i == currentThemeIdx then
				btn.BackgroundColor3 = CLR.ACCENT
				btn.TextColor3       = CLR.BG
			else
				btn.BackgroundColor3 = CLR.SURFACE2
				btn.TextColor3       = CLR.TEXT
			end
		end)

		btn.MouseButton1Click:Connect(function()
			currentThemeIdx = i
			local t = THEMES[i]
			local newCLR = buildCLR(t.accent, t.bg)
			for k, v in pairs(newCLR) do CLR[k] = v end
			applyTheme()
			refreshPresetBtns()
			pill.Text     = "◈  " .. t.name:upper()
			titleLbl.Text = t.name:upper() .. "  v2.1"
		end)
	end

	makeSectionLabel(themePane, "  CUSTOM ACCENT (R / G / B)")

	local customR = math.floor(THEMES[#THEMES].accent.R * 255)
	local customG = math.floor(THEMES[#THEMES].accent.G * 255)
	local customB = math.floor(THEMES[#THEMES].accent.B * 255)

	local previewDot = Instance.new("Frame")
	previewDot.Size             = UDim2.new(1, 0, 0, 18)
	previewDot.BackgroundColor3 = THEMES[#THEMES].accent
	previewDot.BorderSizePixel  = 0
	previewDot.Parent           = themePane
	corner(previewDot, 6)

	local function updateCustomPreview()
		local newAccent = Color3.fromRGB(
			math.clamp(customR, 0, 255),
			math.clamp(customG, 0, 255),
			math.clamp(customB, 0, 255)
		)
		THEMES[#THEMES].accent      = newAccent
		previewDot.BackgroundColor3 = newAccent
		if currentThemeIdx == #THEMES then
			local newCLR = buildCLR(newAccent, THEMES[#THEMES].bg)
			for k, v in pairs(newCLR) do CLR[k] = v end
			applyTheme()
			refreshPresetBtns()
		end
	end

	makeSlider(themePane, "Red",   customR/255, function(r) customR = math.floor(r*255); updateCustomPreview(); return customR end)
	makeSlider(themePane, "Green", customG/255, function(r) customG = math.floor(r*255); updateCustomPreview(); return customG end)
	makeSlider(themePane, "Blue",  customB/255, function(r) customB = math.floor(r*255); updateCustomPreview(); return customB end)

	makeSectionLabel(themePane, "  APPLY")

	local applyBtn = Instance.new("TextButton")
	applyBtn.Size             = UDim2.new(1, 0, 0, 32)
	applyBtn.BackgroundColor3 = CLR.SURFACE2
	applyBtn.TextColor3       = CLR.ACCENT
	applyBtn.Font             = FONT_TITLE
	applyBtn.TextSize         = 12
	applyBtn.Text             = "Apply Custom Theme"
	applyBtn.BorderSizePixel  = 0
	applyBtn.AutoButtonColor  = false
	applyBtn.Parent           = themePane
	corner(applyBtn, 8)
	mkStroke(applyBtn, CLR.ACCENT_DIM, 1)
	reg(applyBtn, "BackgroundColor3", "SURFACE2")
	reg(applyBtn, "TextColor3",       "ACCENT")

	applyBtn.MouseButton1Click:Connect(function()
		currentThemeIdx = #THEMES
		local newAccent = THEMES[#THEMES].accent
		local newCLR    = buildCLR(newAccent, THEMES[#THEMES].bg)
		for k, v in pairs(newCLR) do CLR[k] = v end
		applyTheme()
		refreshPresetBtns()
		pill.Text     = "◈  CUSTOM"
		titleLbl.Text = "CUSTOM  v2.1"
	end)
end
-- ─── Input Handling ──────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end -- don't fire when typing in GUI
	local kc = input.KeyCode

	if kc == Config.AimbotKey and Config.AimbotEnabled then
		aiming = true

	elseif kc == Config.ESPKey then
		Config.ESPEnabled = not Config.ESPEnabled
		if not Config.ESPEnabled then for p in pairs(playerCache) do clearCache(p) end end
		if syncPills.esp then syncPills.esp(Config.ESPEnabled) end

	elseif kc == Config.FlyKey and not Config.FlyForceDisabled then
		Config.FlyEnabled = not Config.FlyEnabled
		if syncPills.fly then syncPills.fly(Config.FlyEnabled) end

	elseif kc == Config.NoclipKey and not Config.NoclipForceDisabled then
		Config.NoclipEnabled = not Config.NoclipEnabled
		if syncPills.noclip then syncPills.noclip(Config.NoclipEnabled) end
		if not Config.NoclipEnabled then
			local char = LocalPlayer.Character
			if char then
				for _, part in ipairs(char:GetDescendants()) do
					if part:IsA("BasePart") then part.CanCollide = true end
				end
			end
		end

	elseif kc == Config.SpeedHackKey and not Config.SpeedHackForceDisabled then
		Config.SpeedHackEnabled = not Config.SpeedHackEnabled
		if syncPills.speed then syncPills.speed(Config.SpeedHackEnabled) end
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = Config.SpeedHackEnabled and Config.SpeedHackValue or 16 end

	elseif kc == Config.InfiniteJumpKey and Config.InfiniteJumpEnabled and not Config.InfiniteJumpForceDisabled then
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Config.AimbotKey then
		aiming        = false
		currentTarget = nil
		currentBestPart = nil
		currentOffset = Vector3.zero
		lastOffsetTime= 0
	end
end)

-- ─── Main RenderStepped Loop ─────────────────────────────────────────────────

RunService.RenderStepped:Connect(function(dt)
	local character = LocalPlayer.Character
	local hrp       = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid  = character and character:FindFirstChildOfClass("Humanoid")

	-- Update shared screen centre once per frame
	local vp = Camera.ViewportSize
	screenCenter = Vector2.new(vp.X * 0.5, vp.Y * 0.5)

	-- ── Aimbot ──
	if Config.AimbotEnabled and aiming then
		local target, bestPart = getAimbotTarget()
		if target and bestPart then
			local isNewLock = bestPart ~= currentBestPart

			-- Random offset logic
			if Config.AimbotRandomOffset then
				local now = tick()
				local shouldRoll = isNewLock  -- always re-roll on a new lock

				if not shouldRoll and Config.AimbotOffsetMode == "Periodic" then
					shouldRoll = (now - lastOffsetTime) >= Config.AimbotOffsetUpdateInterval
				end

				if shouldRoll then
					local m = Config.AimbotOffsetMax
					currentOffset = Vector3.new(
						math.random(-100, 100) / 100 * m,
						math.random(-100, 100) / 100 * m,
						math.random(-100, 100) / 100 * m
					)
					lastOffsetTime = now
				end
			else
				currentOffset = Vector3.zero
			end

			currentBestPart = bestPart

			local targetPos = bestPart.Position + currentOffset
			local camCF     = Camera.CFrame
			local targetCF  = CFrame.new(camCF.Position, targetPos)

			-- Delta-time corrected lerp: speed is now "fraction of gap closed per second"
			-- rather than per frame, so it feels the same at any framerate.
			-- Formula: alpha = 1 - (1 - speed)^(dt * 60)  (normalised to 60 fps baseline)
			local alpha = 1 - (1 - Config.AimbotSpeed) ^ (dt * 60)
			Camera.CFrame = camCF:Lerp(targetCF, alpha)
		end
	end

	-- ── Fly ──
	if hrp and Config.FlyEnabled and not Config.FlyForceDisabled then
		local bv = hrp:FindFirstChild("FlyBV")
		if not bv then
			bv          = Instance.new("BodyVelocity")
			bv.Name     = "FlyBV"
			bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
			bv.Velocity = Vector3.zero
			bv.Parent   = hrp
		end
		local dir = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W)           then dir += Camera.CFrame.LookVector  end
		if UserInputService:IsKeyDown(Enum.KeyCode.S)           then dir -= Camera.CFrame.LookVector  end
		if UserInputService:IsKeyDown(Enum.KeyCode.A)           then dir -= Camera.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D)           then dir += Camera.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space)       then dir += Vector3.yAxis             end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis             end
		bv.Velocity = (dir.Magnitude > 0 and dir.Unit or Vector3.zero) * Config.FlySpeed
		if humanoid then humanoid.PlatformStand = true end
	else
		local bv = hrp and hrp:FindFirstChild("FlyBV")
		if bv then bv:Destroy() end
		if humanoid then humanoid.PlatformStand = false end
	end

	-- ── Speed Hack ──
	-- AlwaysOverride: re-applies every frame so games that reset WalkSpeed can't fight it
	if humanoid and Config.SpeedHackEnabled and not Config.SpeedHackForceDisabled then
		if Config.SpeedHackAlwaysOverride or humanoid.WalkSpeed ~= Config.SpeedHackValue then
			humanoid.WalkSpeed = Config.SpeedHackValue
		end
	end

	updateFOVCircle()
end)

-- ─── Noclip Loop ─────────────────────────────────────────────────────────────
-- RunService.Stepped fires right before the physics step, so setting
-- CanCollide = false here sticks for the whole physics tick.
-- Heartbeat fires AFTER physics, giving the engine a window to re-enable
-- collision each frame — which is why disabling mid-air "stuck" before.

RunService.Stepped:Connect(function()
	if not (Config.NoclipEnabled and not Config.NoclipForceDisabled) then return end
	local char = LocalPlayer.Character
	if not char then return end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			part.CanCollide = false
		end
	end
end)

-- ─── ESP Update Loop ─────────────────────────────────────────────────────────
-- IMPROVEMENT: Reduced tick from every frame to every 0.1 s for ESP label
-- updates (distance, hp ratio). Highlights and connections are persistent.
-- Full rebuild only happens on character change.

local ESP_UPDATE_RATE = 0.1 -- seconds
local lastESPUpdate   = 0

RunService.Heartbeat:Connect(function()
	local now = tick()
	if now - lastESPUpdate < ESP_UPDATE_RATE then return end
	lastESPUpdate = now

	if Config.ESPEnabled then
		for _, player in ipairs(Players:GetPlayers()) do
			createESP(player)
		end
	else
		for p in pairs(playerCache) do clearCache(p) end
	end
end)

-- ─── Player Events ───────────────────────────────────────────────────────────

local function onCharacterAdded(player, character)
	-- Small delay so character parts load
	task.wait(0.5)
	if Config.ESPEnabled then createESP(player) end

	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid then
		humanoid.Died:Connect(function()
			clearCache(player)
			if player == currentTarget then currentTarget = nil end
		end)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		onCharacterAdded(player, char)
	end)
	player:GetPropertyChangedSignal("Team"):Connect(function()
		clearCache(player) -- force ESP rebuild with new team colour
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	clearCache(player)
	if player == currentTarget then currentTarget = nil end
end)

-- ─── Initialise ──────────────────────────────────────────────────────────────

-- ─── RGB Theme Loop ─────────────────────────────────────────────────────────
RunService.Heartbeat:Connect(function(dt)
	if currentThemeIdx ~= RGB_THEME_IDX then return end
	rgbHue = (rgbHue + dt * 0.25) % 1   -- full cycle ~4 seconds
	-- HSV → RGB (pure hue, full saturation & value)
	local h6  = rgbHue * 6
	local i   = math.floor(h6)
	local f   = h6 - i
	local q   = 1 - f
	local r, g, b
	if     i == 0 then r,g,b = 1,  f,  0
	elseif i == 1 then r,g,b = q,  1,  0
	elseif i == 2 then r,g,b = 0,  1,  f
	elseif i == 3 then r,g,b = 0,  q,  1
	elseif i == 4 then r,g,b = f,  0,  1
	else               r,g,b = 1,  0,  q
	end
	local newAccent = Color3.new(r, g, b)
	THEMES[RGB_THEME_IDX].accent = newAccent
	-- Mutate CLR in place so applyTheme() picks up the new accent
	local rebuilt = buildCLR(newAccent, THEMES[RGB_THEME_IDX].bg)
	for k, v in pairs(rebuilt) do CLR[k] = v end
	applyTheme()
end)

local function initialize()
	-- Set time of day from config
	if Config.TimeOfDayEnabled then
		Lighting.TimeOfDay = minutesToTimeString(Config.TimeOfDayMinutes)
	end

	-- Bootstrap ESP for players already in the game
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			onCharacterAdded(player, player.Character)
		end
	end

	-- FOV circle must exist before createGUI so slider init callbacks can reference fovStroke safely
	createFOVCircle()
	updateFOVCircle()
	createGUI()

	print("[ESP v2.1] Loaded successfully.")
end

initialize()
