-- stable



local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
-- Configuration table, you may edit this if youd like
-- to have the same settings on inject
local Config = {
	ESPEnabled = true,
	OutlineColor = Color3.fromRGB(255, 255, 255),
	NameSize = 14,
	NameTransparency = 0, -- 0 (opaque) to 1 (transparent)
	MaxDistance = 1000,
	AimbotEnabled = false,
	AimbotFOV = 100,
	AimbotSpeed = 0.2,
	AimbotTargets = {"Head", "UpperTorso"},
	AimbotKey = Enum.KeyCode.Q,
	ESPKey = Enum.KeyCode.E,
	AimbotTargetMode = "Closest Distance", -- "Any", "Highest HP", "Lowest HP", "Closest Distance"
	AimbotTeamCheck = true,
	ShowNameESP = true,
	ShowHealthESP = true,
	ShowDistanceESP = true, -- New: Toggle for distance ESP
	HealthBarHeight = 5, -- 1 to 10
	HealthBarTransparency = 0, -- 0 (opaque) to 1 (transparent)
	DistanceSize = 14, -- New: Size for distance text
	DistanceTransparency = 0, -- New: Transparency for distance text
	FOVCircleTransparency = 0.5, -- 0 (opaque) to 1 (transparent)
	WallCheckEnabled = true, -- Toggle for wall check
	FlyEnabled = false,
	FlySpeed = 50,
	FlyKey = Enum.KeyCode.F,
	FlyForceDisabled = false,
	NoclipEnabled = false,
	NoclipKey = Enum.KeyCode.V,
	NoclipForceDisabled = false,
	AimbotRandomOffset = false, -- Enable/disable random offset
	AimbotOffsetMax = 0.5, -- Max offset variation in studs (slider range 0-2)
	AimbotOffsetUpdateInterval = 100, -- Do not edit, offset update interval in seconds
	SpeedHackEnabled = false, -- New: Toggle for speed hack
	SpeedHackValue = 16, -- New: Default walk speed, slider 16-100
	SpeedHackKey = Enum.KeyCode.G, -- New: Key to toggle speed hack
	SpeedHackForceDisabled = false, -- New: Force disable for speed hack
	OutlineTransparency = 0.3, -- 0 (opaque) to 1 (transparent)
	AimbotMaxDistance = 1000
}
-- Cache for player characters and ESP elements
local playerCache = {}
-- Aimbot variables
local currentOffset = Vector3.new(0, 0, 0)
local lastTarget = nil
local currentBestPart = nil
local lastUpdateTime = 0
-- Create GUI
local function createGUI()
	local success, errorMsg = pcall(function()
		-- Ensure PlayerGui exists
		if not LocalPlayer.PlayerGui then
			warn("PlayerGui not found!")
			return
		end
		-- Create ScreenGui
		local ScreenGui = Instance.new("ScreenGui")
		ScreenGui.Name = "ESP_Aimbot_Config"
		ScreenGui.Parent = LocalPlayer.PlayerGui
		ScreenGui.ResetOnSpawn = false
		ScreenGui.DisplayOrder = 1000
		ScreenGui.Enabled = true
		print("ScreenGui created and parented to PlayerGui")
		local Frame = Instance.new("Frame")
		Frame.Size = UDim2.new(0, 250, 0, 300)
		Frame.Position = UDim2.new(0, 10, 0, 10)
		Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		Frame.BorderSizePixel = 0
		Frame.Visible = true
		Frame.Parent = ScreenGui
		Frame.Name = "MainFrame"
		print("MainFrame created")
		local UICorner = Instance.new("UICorner")
		UICorner.CornerRadius = UDim.new(0, 8)
		UICorner.Parent = Frame
		local UIGradient = Instance.new("UIGradient")
		UIGradient.Color = ColorSequence.new{
			ColorSequenceKeypoint.new(0, Color3.fromRGB(50, 50, 50)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 20))
		}
		UIGradient.Parent = Frame
		local UIStroke = Instance.new("UIStroke")
		UIStroke.Color = Color3.fromRGB(100, 100, 100)
		UIStroke.Thickness = 1
		UIStroke.Parent = Frame
		-- Minimize Button
		local MinimizeButton = Instance.new("TextButton")
		MinimizeButton.Size = UDim2.new(0, 30, 0, 30)
		MinimizeButton.Position = UDim2.new(1, -40, 0, 10)
		MinimizeButton.Text = "-" -- + or -
		MinimizeButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		MinimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		MinimizeButton.Font = Enum.Font.SourceSansBold
		MinimizeButton.TextSize = 16
		MinimizeButton.Parent = Frame
		local MinimizeCorner = Instance.new("UICorner")
		MinimizeCorner.CornerRadius = UDim.new(0, 5)
		MinimizeCorner.Parent = MinimizeButton
		-- Minimize Toggle Button
		local ToggleButton = Instance.new("TextButton")
		ToggleButton.Size = UDim2.new(0, 50, 0, 50)
		ToggleButton.Position = UDim2.new(0, 10, 0, 10)
		ToggleButton.Text = ">" -- < or >
		ToggleButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		ToggleButton.Font = Enum.Font.SourceSansBold
		ToggleButton.TextSize = 20
		ToggleButton.Visible = false
		ToggleButton.Parent = ScreenGui
		local ToggleCorner = Instance.new("UICorner")
		ToggleCorner.CornerRadius = UDim.new(0, 8)
		ToggleCorner.Parent = ToggleButton
		-- Minimize Logic
		MinimizeButton.MouseButton1Click:Connect(function()
			Frame.Visible = false
			ToggleButton.Visible = true
			print("Minimized GUI")
		end)
		ToggleButton.MouseButton1Click:Connect(function()
			Frame.Visible = true
			ToggleButton.Visible = false
			print("Restored GUI")
		end)
		-- Dragging functionality
		local dragging, dragStart, startPos
		local function setupDragging(element)
			element.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					dragging = true
					dragStart = input.Position
					startPos = Frame.Position
					input.Changed:Connect(function()
						if input.UserInputState == Enum.UserInputState.End then
							dragging = false
						end
					end)
				end
			end)
			element.InputChanged:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
					local delta = input.Position - dragStart
					Frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
					ToggleButton.Position = Frame.Position
				end
			end)
		end
		setupDragging(Frame)
		setupDragging(ToggleButton)
		-- Title
		local Title = Instance.new("TextLabel")
		Title.Size = UDim2.new(0, 190, 0, 30)
		Title.Position = UDim2.new(0, 10, 0, 10)
		Title.Text = "ESP, Aimbot, Fly & Noclip V1.2.2"
		Title.TextColor3 = Color3.fromRGB(255, 255, 255)
		Title.BackgroundTransparency = 1
		Title.Font = Enum.Font.SourceSansBold
		Title.TextSize = 18
		Title.Parent = Frame
		print("Title created")
		-- Scrolling Frame
		local ScrollingFrame = Instance.new("ScrollingFrame")
		ScrollingFrame.Position = UDim2.new(0, 10, 0, 50)
		ScrollingFrame.Size = UDim2.new(0, 230, 0, 240)
		ScrollingFrame.BackgroundTransparency = 1
		ScrollingFrame.ScrollingDirection = Enum.ScrollingDirection.Y
		ScrollingFrame.ScrollBarThickness = 6
		ScrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
		ScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
		ScrollingFrame.Parent = Frame
		print("ScrollingFrame created")
		local listLayout = Instance.new("UIListLayout")
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Padding = UDim.new(0, 5)
		listLayout.Parent = ScrollingFrame
		-- Function to create collapsible section
		local function createSection(headerText, isExpanded)
			local sectionHeader = Instance.new("TextButton")
			sectionHeader.Size = UDim2.new(1, 0, 0, 30)
			sectionHeader.Text = headerText .. (isExpanded and " [-]" or " [+]")
			sectionHeader.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
			sectionHeader.TextColor3 = Color3.fromRGB(255, 255, 255)
			sectionHeader.Font = Enum.Font.SourceSansBold
			sectionHeader.TextSize = 16
			sectionHeader.Parent = ScrollingFrame
			local headerCorner = Instance.new("UICorner")
			headerCorner.CornerRadius = UDim.new(0, 5)
			headerCorner.Parent = sectionHeader
			local controlsFrame = Instance.new("Frame")
			controlsFrame.Size = UDim2.new(1, 0, 0, 0)
			controlsFrame.AutomaticSize = Enum.AutomaticSize.Y
			controlsFrame.BackgroundTransparency = 1
			controlsFrame.Visible = isExpanded
			controlsFrame.Parent = ScrollingFrame
			local controlsLayout = Instance.new("UIListLayout")
			controlsLayout.SortOrder = Enum.SortOrder.LayoutOrder
			controlsLayout.Padding = UDim.new(0, 5)
			controlsLayout.Parent = controlsFrame
			sectionHeader.MouseButton1Click:Connect(function()
				controlsFrame.Visible = not controlsFrame.Visible
				sectionHeader.Text = headerText .. (controlsFrame.Visible and " [-]" or " [+]")
			end)
			return controlsFrame
		end
		-- ESP Section - or +
		local espControls = createSection("ESP Settings", true)
		-- ESP Toggle
		local ESPToggle = Instance.new("TextButton")
		ESPToggle.Name = "ESPToggle"
		ESPToggle.Size = UDim2.new(1, 0, 0, 30)
		ESPToggle.Text = "ESP: ON [" .. Config.ESPKey.Name .. "]"
		ESPToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		ESPToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		ESPToggle.Font = Enum.Font.SourceSans
		ESPToggle.TextSize = 16
		ESPToggle.Parent = espControls
		local ESPToggleCorner = Instance.new("UICorner")
		ESPToggleCorner.CornerRadius = UDim.new(0, 5)
		ESPToggleCorner.Parent = ESPToggle
		ESPToggle.MouseButton1Click:Connect(function()
			Config.ESPEnabled = not Config.ESPEnabled
			ESPToggle.Text = "ESP: " .. (Config.ESPEnabled and "ON" or "OFF") .. " [" .. Config.ESPKey.Name .. "]"
		end)
		-- ESP Keybind
		local ESPKeybind = Instance.new("TextButton")
		ESPKeybind.Size = UDim2.new(1, 0, 0, 30)
		ESPKeybind.Text = "Set ESP Key: " .. Config.ESPKey.Name -- Default E
		ESPKeybind.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		ESPKeybind.TextColor3 = Color3.fromRGB(255, 255, 255)
		ESPKeybind.Font = Enum.Font.SourceSans
		ESPKeybind.TextSize = 16
		ESPKeybind.Parent = espControls
		local ESPKeybindCorner = Instance.new("UICorner")
		ESPKeybindCorner.CornerRadius = UDim.new(0, 5)
		ESPKeybindCorner.Parent = ESPKeybind
		ESPKeybind.MouseButton1Click:Connect(function()
			ESPKeybind.Text = "Set ESP Key: Press a key..."
			local input = UserInputService.InputBegan:Wait()
			if input.KeyCode ~= Enum.KeyCode.Unknown then
				Config.ESPKey = input.KeyCode
				ESPKeybind.Text = "Set ESP Key: " .. Config.ESPKey.Name
				ESPToggle.Text = "ESP: " .. (Config.ESPEnabled and "ON" or "OFF") .. " [" .. Config.ESPKey.Name .. "]"
			else
				ESPKeybind.Text = "Set ESP Key: " .. Config.ESPKey.Name
			end
		end)
		-- Name Size Slider
		local NameSizeLabel = Instance.new("TextLabel")
		NameSizeLabel.Size = UDim2.new(1, 0, 0, 20)
		NameSizeLabel.Text = "Name Size: " .. Config.NameSize
		NameSizeLabel.BackgroundTransparency = 1
		NameSizeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		NameSizeLabel.Font = Enum.Font.SourceSans
		NameSizeLabel.TextSize = 14
		NameSizeLabel.Parent = espControls
		local NameSizeSlider = Instance.new("Frame")
		NameSizeSlider.Size = UDim2.new(1, 0, 0, 10)
		NameSizeSlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		NameSizeSlider.Parent = espControls
		local NameSizeSliderCorner = Instance.new("UICorner")
		NameSizeSliderCorner.CornerRadius = UDim.new(0, 5)
		NameSizeSliderCorner.Parent = NameSizeSlider
		local NameSizeFill = Instance.new("Frame")
		NameSizeFill.Size = UDim2.new((Config.NameSize - 10) / 20, 0, 1, 0)
		NameSizeFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		NameSizeFill.Parent = NameSizeSlider
		local NameSizeFillCorner = Instance.new("UICorner")
		NameSizeFillCorner.CornerRadius = UDim.new(0, 5)
		NameSizeFillCorner.Parent = NameSizeFill
		local draggingNameSlider
		NameSizeSlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingNameSlider = true
			end
		end)
		NameSizeSlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingNameSlider = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingNameSlider then
				local sliderPos = math.clamp((input.Position.X - NameSizeSlider.AbsolutePosition.X) / NameSizeSlider.AbsoluteSize.X, 0, 1)
				Config.NameSize = math.floor(sliderPos * 20) + 10
				NameSizeLabel.Text = "Name Size: " .. Config.NameSize
				NameSizeFill.Size = UDim2.new(sliderPos, 0, 1, 0)
			end
		end)
		-- Name Transparency Slider
		local NameTransparencyLabel = Instance.new("TextLabel")
		NameTransparencyLabel.Size = UDim2.new(1, 0, 0, 20)
		NameTransparencyLabel.Text = "Name Transparency: " .. string.format("%.2f", Config.NameTransparency)
		NameTransparencyLabel.BackgroundTransparency = 1
		NameTransparencyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		NameTransparencyLabel.Font = Enum.Font.SourceSans
		NameTransparencyLabel.TextSize = 14
		NameTransparencyLabel.Parent = espControls
		local NameTransparencySlider = Instance.new("Frame")
		NameTransparencySlider.Size = UDim2.new(1, 0, 0, 10)
		NameTransparencySlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		NameTransparencySlider.Parent = espControls
		local NameTransparencySliderCorner = Instance.new("UICorner")
		NameTransparencySliderCorner.CornerRadius = UDim.new(0, 5)
		NameTransparencySliderCorner.Parent = NameTransparencySlider
		local NameTransparencyFill = Instance.new("Frame")
		NameTransparencyFill.Size = UDim2.new(Config.NameTransparency, 0, 1, 0)
		NameTransparencyFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		NameTransparencyFill.Parent = NameTransparencySlider
		local NameTransparencyFillCorner = Instance.new("UICorner")
		NameTransparencyFillCorner.CornerRadius = UDim.new(0, 5)
		NameTransparencyFillCorner.Parent = NameTransparencyFill
		local draggingNameTransparency
		NameTransparencySlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingNameTransparency = true
			end
		end)
		NameTransparencySlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingNameTransparency = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingNameTransparency then
				local sliderPos = math.clamp((input.Position.X - NameTransparencySlider.AbsolutePosition.X) / NameTransparencySlider.AbsoluteSize.X, 0, 1)
				Config.NameTransparency = sliderPos
				NameTransparencyLabel.Text = "Name Transparency: " .. string.format("%.2f", Config.NameTransparency)
				NameTransparencyFill.Size = UDim2.new(sliderPos, 0, 1, 0)
			end
		end)
		-- Max Distance Slider
		local DistanceLabel = Instance.new("TextLabel")
		DistanceLabel.Size = UDim2.new(1, 0, 0, 20)
		DistanceLabel.Text = "Max Distance: " .. Config.MaxDistance
		DistanceLabel.BackgroundTransparency = 1
		DistanceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		DistanceLabel.Font = Enum.Font.SourceSans
		DistanceLabel.TextSize = 14
		DistanceLabel.Parent = espControls
		local DistanceSlider = Instance.new("Frame")
		DistanceSlider.Size = UDim2.new(1, 0, 0, 10)
		DistanceSlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		DistanceSlider.Parent = espControls
		local DistanceSliderCorner = Instance.new("UICorner")
		DistanceSliderCorner.CornerRadius = UDim.new(0, 5)
		DistanceSliderCorner.Parent = DistanceSlider
		local DistanceFill = Instance.new("Frame")
		DistanceFill.Size = UDim2.new((Config.MaxDistance - 100) / 1900, 0, 1, 0)
		DistanceFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		DistanceFill.Parent = DistanceSlider
		local DistanceFillCorner = Instance.new("UICorner")
		DistanceFillCorner.CornerRadius = UDim.new(0, 5)
		DistanceFillCorner.Parent = DistanceFill
		local draggingDistance
		DistanceSlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingDistance = true
			end
		end)
		DistanceSlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingDistance = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingDistance then
				local sliderPos = math.clamp((input.Position.X - DistanceSlider.AbsolutePosition.X) / DistanceSlider.AbsoluteSize.X, 0, 1)
				Config.MaxDistance = math.floor(sliderPos * 1900) + 100
				DistanceLabel.Text = "Max Distance: " .. Config.MaxDistance
				DistanceFill.Size = UDim2.new(sliderPos, 0, 1, 0)
			end
		end)
		-- Show Name Toggle
		local ShowNameToggle = Instance.new("TextButton")
		ShowNameToggle.Size = UDim2.new(1, 0, 0, 30)
		ShowNameToggle.Text = "Show Names: " .. (Config.ShowNameESP and "ON" or "OFF")
		ShowNameToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		ShowNameToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		ShowNameToggle.Font = Enum.Font.SourceSans
		ShowNameToggle.TextSize = 16
		ShowNameToggle.Parent = espControls
		local ShowNameToggleCorner = Instance.new("UICorner")
		ShowNameToggleCorner.CornerRadius = UDim.new(0, 5)
		ShowNameToggleCorner.Parent = ShowNameToggle
		ShowNameToggle.MouseButton1Click:Connect(function()
			Config.ShowNameESP = not Config.ShowNameESP
			ShowNameToggle.Text = "Show Names: " .. (Config.ShowNameESP and "ON" or "OFF")
		end)
		-- Show Health Toggle
		local ShowHealthToggle = Instance.new("TextButton")
		ShowHealthToggle.Size = UDim2.new(1, 0, 0, 30)
		ShowHealthToggle.Text = "Show Health: " .. (Config.ShowHealthESP and "ON" or "OFF")
		ShowHealthToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		ShowHealthToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		ShowHealthToggle.Font = Enum.Font.SourceSans
		ShowHealthToggle.TextSize = 16
		ShowHealthToggle.Parent = espControls
		local ShowHealthToggleCorner = Instance.new("UICorner")
		ShowHealthToggleCorner.CornerRadius = UDim.new(0, 5)
		ShowHealthToggleCorner.Parent = ShowHealthToggle
		ShowHealthToggle.MouseButton1Click:Connect(function()
			Config.ShowHealthESP = not Config.ShowHealthESP
			ShowHealthToggle.Text = "Show Health: " .. (Config.ShowHealthESP and "ON" or "OFF")
		end)
		-- Health Bar Height Slider
		local HealthBarLabel = Instance.new("TextLabel")
		HealthBarLabel.Size = UDim2.new(1, 0, 0, 20)
		HealthBarLabel.Text = "Health Bar Height: " .. Config.HealthBarHeight
		HealthBarLabel.BackgroundTransparency = 1
		HealthBarLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		HealthBarLabel.Font = Enum.Font.SourceSans
		HealthBarLabel.TextSize = 14
		HealthBarLabel.Parent = espControls
		local HealthBarSlider = Instance.new("Frame")
		HealthBarSlider.Size = UDim2.new(1, 0, 0, 10)
		HealthBarSlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		HealthBarSlider.Parent = espControls
		local HealthBarSliderCorner = Instance.new("UICorner")
		HealthBarSliderCorner.CornerRadius = UDim.new(0, 5)
		HealthBarSliderCorner.Parent = HealthBarSlider
		local HealthBarFill = Instance.new("Frame")
		HealthBarFill.Size = UDim2.new((Config.HealthBarHeight - 1) / 9, 0, 1, 0)
		HealthBarFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		HealthBarFill.Parent = HealthBarSlider
		local HealthBarFillCorner = Instance.new("UICorner")
		HealthBarFillCorner.CornerRadius = UDim.new(0, 5)
		HealthBarFillCorner.Parent = HealthBarFill
		local draggingHealthBar
		HealthBarSlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingHealthBar = true
			end
		end)
		HealthBarSlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingHealthBar = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingHealthBar then
				local sliderPos = math.clamp((input.Position.X - HealthBarSlider.AbsolutePosition.X) / HealthBarSlider.AbsoluteSize.X, 0, 1)
				Config.HealthBarHeight = math.floor(sliderPos * 9) + 1
				HealthBarLabel.Text = "Health Bar Height: " .. Config.HealthBarHeight
				HealthBarFill.Size = UDim2.new(sliderPos, 0, 1, 0)
			end
		end)
		-- Health Bar Transparency Slider
		local HealthBarTransparencyLabel = Instance.new("TextLabel")
		HealthBarTransparencyLabel.Size = UDim2.new(1, 0, 0, 20)
		HealthBarTransparencyLabel.Text = "Health Bar Transparency: " .. string.format("%.2f", Config.HealthBarTransparency)
		HealthBarTransparencyLabel.BackgroundTransparency = 1
		HealthBarTransparencyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		HealthBarTransparencyLabel.Font = Enum.Font.SourceSans
		HealthBarTransparencyLabel.TextSize = 14
		HealthBarTransparencyLabel.Parent = espControls
		local HealthBarTransparencySlider = Instance.new("Frame")
		HealthBarTransparencySlider.Size = UDim2.new(1, 0, 0, 10)
		HealthBarTransparencySlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		HealthBarTransparencySlider.Parent = espControls
		local HealthBarTransparencySliderCorner = Instance.new("UICorner")
		HealthBarTransparencySliderCorner.CornerRadius = UDim.new(0, 5)
		HealthBarTransparencySliderCorner.Parent = HealthBarTransparencySlider
		local HealthBarTransparencyFill = Instance.new("Frame")
		HealthBarTransparencyFill.Size = UDim2.new(Config.HealthBarTransparency, 0, 1, 0)
		HealthBarTransparencyFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		HealthBarTransparencyFill.Parent = HealthBarTransparencySlider
		local HealthBarTransparencyFillCorner = Instance.new("UICorner")
		HealthBarTransparencyFillCorner.CornerRadius = UDim.new(0, 5)
		HealthBarTransparencyFillCorner.Parent = HealthBarTransparencyFill
		local draggingHealthBarTransparency
		HealthBarTransparencySlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingHealthBarTransparency = true
			end
		end)
		HealthBarTransparencySlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingHealthBarTransparency = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingHealthBarTransparency then
				local sliderPos = math.clamp((input.Position.X - HealthBarTransparencySlider.AbsolutePosition.X) / HealthBarTransparencySlider.AbsoluteSize.X, 0, 1)
				Config.HealthBarTransparency = sliderPos
				HealthBarTransparencyLabel.Text = "Health Bar Transparency: " .. string.format("%.2f", Config.HealthBarTransparency)
				HealthBarTransparencyFill.Size = UDim2.new(sliderPos, 0, 1, 0)
			end
		end)
		-- Show Distance Toggle (New)
		local ShowDistanceToggle = Instance.new("TextButton")
		ShowDistanceToggle.Size = UDim2.new(1, 0, 0, 30)
		ShowDistanceToggle.Text = "Show Distance: " .. (Config.ShowDistanceESP and "ON" or "OFF")
		ShowDistanceToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		ShowDistanceToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		ShowDistanceToggle.Font = Enum.Font.SourceSans
		ShowDistanceToggle.TextSize = 16
		ShowDistanceToggle.Parent = espControls
		local ShowDistanceToggleCorner = Instance.new("UICorner")
		ShowDistanceToggleCorner.CornerRadius = UDim.new(0, 5)
		ShowDistanceToggleCorner.Parent = ShowDistanceToggle
		ShowDistanceToggle.MouseButton1Click:Connect(function()
			Config.ShowDistanceESP = not Config.ShowDistanceESP
			ShowDistanceToggle.Text = "Show Distance: " .. (Config.ShowDistanceESP and "ON" or "OFF")
		end)
		-- Distance Size Slider (New)
		local DistanceSizeLabel = Instance.new("TextLabel")
		DistanceSizeLabel.Size = UDim2.new(1, 0, 0, 20)
		DistanceSizeLabel.Text = "Distance Size: " .. Config.DistanceSize
		DistanceSizeLabel.BackgroundTransparency = 1
		DistanceSizeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		DistanceSizeLabel.Font = Enum.Font.SourceSans
		DistanceSizeLabel.TextSize = 14
		DistanceSizeLabel.Parent = espControls
		local DistanceSizeSlider = Instance.new("Frame")
		DistanceSizeSlider.Size = UDim2.new(1, 0, 0, 10)
		DistanceSizeSlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		DistanceSizeSlider.Parent = espControls
		local DistanceSizeSliderCorner = Instance.new("UICorner")
		DistanceSizeSliderCorner.CornerRadius = UDim.new(0, 5)
		DistanceSizeSliderCorner.Parent = DistanceSizeSlider
		local DistanceSizeFill = Instance.new("Frame")
		DistanceSizeFill.Size = UDim2.new((Config.DistanceSize - 10) / 20, 0, 1, 0)
		DistanceSizeFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		DistanceSizeFill.Parent = DistanceSizeSlider
		local DistanceSizeFillCorner = Instance.new("UICorner")
		DistanceSizeFillCorner.CornerRadius = UDim.new(0, 5)
		DistanceSizeFillCorner.Parent = DistanceSizeFill
		local draggingDistanceSize
		DistanceSizeSlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingDistanceSize = true
			end
		end)
		DistanceSizeSlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingDistanceSize = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingDistanceSize then
				local sliderPos = math.clamp((input.Position.X - DistanceSizeSlider.AbsolutePosition.X) / DistanceSizeSlider.AbsoluteSize.X, 0, 1)
				Config.DistanceSize = math.floor(sliderPos * 20) + 10
				DistanceSizeLabel.Text = "Distance Size: " .. Config.DistanceSize
				DistanceSizeFill.Size = UDim2.new(sliderPos, 0, 1, 0)
			end
		end)
		-- Distance Transparency Slider (New)
		local DistanceTransparencyLabel = Instance.new("TextLabel")
		DistanceTransparencyLabel.Size = UDim2.new(1, 0, 0, 20)
		DistanceTransparencyLabel.Text = "Distance Transparency: " .. string.format("%.2f", Config.DistanceTransparency)
		DistanceTransparencyLabel.BackgroundTransparency = 1
		DistanceTransparencyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		DistanceTransparencyLabel.Font = Enum.Font.SourceSans
		DistanceTransparencyLabel.TextSize = 14
		DistanceTransparencyLabel.Parent = espControls
		local DistanceTransparencySlider = Instance.new("Frame")
		DistanceTransparencySlider.Size = UDim2.new(1, 0, 0, 10)
		DistanceTransparencySlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		DistanceTransparencySlider.Parent = espControls
		local DistanceTransparencySliderCorner = Instance.new("UICorner")
		DistanceTransparencySliderCorner.CornerRadius = UDim.new(0, 5)
		DistanceTransparencySliderCorner.Parent = DistanceTransparencySlider
		local DistanceTransparencyFill = Instance.new("Frame")
		DistanceTransparencyFill.Size = UDim2.new(Config.DistanceTransparency, 0, 1, 0)
		DistanceTransparencyFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		DistanceTransparencyFill.Parent = DistanceTransparencySlider
		local DistanceTransparencyFillCorner = Instance.new("UICorner")
		DistanceTransparencyFillCorner.CornerRadius = UDim.new(0, 5)
		DistanceTransparencyFillCorner.Parent = DistanceTransparencyFill
		local draggingDistanceTransparency
		DistanceTransparencySlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingDistanceTransparency = true
			end
		end)
		DistanceTransparencySlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingDistanceTransparency = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingDistanceTransparency then
				local sliderPos = math.clamp((input.Position.X - DistanceTransparencySlider.AbsolutePosition.X) / DistanceTransparencySlider.AbsoluteSize.X, 0, 1)
				Config.DistanceTransparency = sliderPos
				DistanceTransparencyLabel.Text = "Distance Transparency: " .. string.format("%.2f", Config.DistanceTransparency)
				DistanceTransparencyFill.Size = UDim2.new(sliderPos, 0, 1, 0)
			end
		end)
		-- Outline Transparency Slider
		local OutlineTransparencyLabel = Instance.new("TextLabel")
		OutlineTransparencyLabel.Size = UDim2.new(1, 0, 0, 20)
		OutlineTransparencyLabel.Text = "Outline Transparency: " .. string.format("%.2f", Config.OutlineTransparency)
		OutlineTransparencyLabel.BackgroundTransparency = 1
		OutlineTransparencyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		OutlineTransparencyLabel.Font = Enum.Font.SourceSans
		OutlineTransparencyLabel.TextSize = 14
		OutlineTransparencyLabel.Parent = espControls
		local OutlineTransparencySlider = Instance.new("Frame")
		OutlineTransparencySlider.Size = UDim2.new(1, 0, 0, 10)
		OutlineTransparencySlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		OutlineTransparencySlider.Parent = espControls
		local OutlineTransparencySliderCorner = Instance.new("UICorner")
		OutlineTransparencySliderCorner.CornerRadius = UDim.new(0, 5)
		OutlineTransparencySliderCorner.Parent = OutlineTransparencySlider
		local OutlineTransparencyFill = Instance.new("Frame")
		OutlineTransparencyFill.Size = UDim2.new(Config.OutlineTransparency, 0, 1, 0)
		OutlineTransparencyFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		OutlineTransparencyFill.Parent = OutlineTransparencySlider
		local OutlineTransparencyFillCorner = Instance.new("UICorner")
		OutlineTransparencyFillCorner.CornerRadius = UDim.new(0, 5)
		OutlineTransparencyFillCorner.Parent = OutlineTransparencyFill
		local draggingOutlineTransparency
		OutlineTransparencySlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingOutlineTransparency = true
			end
		end)
		OutlineTransparencySlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingOutlineTransparency = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingOutlineTransparency then
				local sliderPos = math.clamp((input.Position.X - OutlineTransparencySlider.AbsolutePosition.X) / OutlineTransparencySlider.AbsoluteSize.X, 0, 1)
				Config.OutlineTransparency = sliderPos
				OutlineTransparencyLabel.Text = "Outline Transparency: " .. string.format("%.2f", Config.OutlineTransparency)
				OutlineTransparencyFill.Size = UDim2.new(sliderPos, 0, 1, 0)
			end
		end)
		-- Aimbot Section
		local aimbotControls = createSection("Aimbot Settings", true)
		-- Aimbot Toggle
		local AimbotToggle = Instance.new("TextButton")
		AimbotToggle.Name = "AimbotToggle"
		AimbotToggle.Size = UDim2.new(1, 0, 0, 30)
		AimbotToggle.Text = "Aimbot: OFF [" .. Config.AimbotKey.Name .. "]"
		AimbotToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		AimbotToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		AimbotToggle.Font = Enum.Font.SourceSans
		AimbotToggle.TextSize = 16
		AimbotToggle.Parent = aimbotControls
		local AimbotToggleCorner = Instance.new("UICorner")
		AimbotToggleCorner.CornerRadius = UDim.new(0, 5)
		AimbotToggleCorner.Parent = AimbotToggle
		AimbotToggle.MouseButton1Click:Connect(function()
			Config.AimbotEnabled = not Config.AimbotEnabled
			AimbotToggle.Text = "Aimbot: " .. (Config.AimbotEnabled and "ON" or "OFF") .. " [" .. Config.AimbotKey.Name .. "]"
		end)
		-- Aimbot Keybind
		local AimbotKeybind = Instance.new("TextButton")
		AimbotKeybind.Size = UDim2.new(1, 0, 0, 30)
		AimbotKeybind.Text = "Set Aimbot Key: " .. Config.AimbotKey.Name
		AimbotKeybind.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		AimbotKeybind.TextColor3 = Color3.fromRGB(255, 255, 255)
		AimbotKeybind.Font = Enum.Font.SourceSans
		AimbotKeybind.TextSize = 16
		AimbotKeybind.Parent = aimbotControls
		local AimbotKeybindCorner = Instance.new("UICorner")
		AimbotKeybindCorner.CornerRadius = UDim.new(0, 5)
		AimbotKeybindCorner.Parent = AimbotKeybind
		AimbotKeybind.MouseButton1Click:Connect(function()
			AimbotKeybind.Text = "Set Aimbot Key: Press a key..."
			local input = UserInputService.InputBegan:Wait()
			if input.KeyCode ~= Enum.KeyCode.Unknown then
				Config.AimbotKey = input.KeyCode
				AimbotKeybind.Text = "Set Aimbot Key: " .. Config.AimbotKey.Name
				AimbotToggle.Text = "Aimbot: " .. (Config.AimbotEnabled and "ON" or "OFF") .. " [" .. Config.AimbotKey.Name .. "]"
			else
				AimbotKeybind.Text = "Set Aimbot Key: " .. Config.AimbotKey.Name
			end
		end)
		-- Aimbot Target Mode Toggle
		local modes = {"Any", "Highest HP", "Lowest HP", "Closest Distance"}
		local modeIndex = table.find(modes, Config.AimbotTargetMode) or 1
		local TargetToggle = Instance.new("TextButton")
		TargetToggle.Size = UDim2.new(1, 0, 0, 30)
		TargetToggle.Text = "Aimbot Target: " .. Config.AimbotTargetMode
		TargetToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		TargetToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		TargetToggle.Font = Enum.Font.SourceSans
		TargetToggle.TextSize = 16
		TargetToggle.Parent = aimbotControls
		local TargetToggleCorner = Instance.new("UICorner")
		TargetToggleCorner.CornerRadius = UDim.new(0, 5)
		TargetToggleCorner.Parent = TargetToggle
		TargetToggle.MouseButton1Click:Connect(function()
			modeIndex = (modeIndex % #modes) + 1
			Config.AimbotTargetMode = modes[modeIndex]
			TargetToggle.Text = "Aimbot Target: " .. Config.AimbotTargetMode
		end)
		-- Select Target Parts
		local TargetPartsLabel = Instance.new("TextLabel")
		TargetPartsLabel.Size = UDim2.new(1, 0, 0, 20)
		TargetPartsLabel.Text = "Select Target Parts:"
		TargetPartsLabel.BackgroundTransparency = 1
		TargetPartsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		TargetPartsLabel.Font = Enum.Font.SourceSans
		TargetPartsLabel.TextSize = 14
		TargetPartsLabel.Parent = aimbotControls
		local ScrollNote = Instance.new("TextLabel")
		ScrollNote.Size = UDim2.new(1, 0, 0, 20)
		ScrollNote.Text = "(Scroll to see all parts)"
		ScrollNote.BackgroundTransparency = 1
		ScrollNote.TextColor3 = Color3.fromRGB(200, 200, 200)
		ScrollNote.Font = Enum.Font.SourceSansItalic
		ScrollNote.TextSize = 14
		ScrollNote.Parent = aimbotControls
		local partsScrolling = Instance.new("ScrollingFrame")
		partsScrolling.Size = UDim2.new(1, 0, 0, 200)
		partsScrolling.BackgroundTransparency = 1
		partsScrolling.ScrollingDirection = Enum.ScrollingDirection.Y
		partsScrolling.ScrollBarThickness = 6
		partsScrolling.CanvasSize = UDim2.new(0, 0, 0, 0)
		partsScrolling.AutomaticCanvasSize = Enum.AutomaticSize.Y
		partsScrolling.Parent = aimbotControls
		local partsListLayout = Instance.new("UIListLayout")
		partsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		partsListLayout.Padding = UDim.new(0, 5)
		partsListLayout.Parent = partsScrolling
		local availableParts = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot"}
		for _, partName in ipairs(availableParts) do
			local PartToggle = Instance.new("TextButton")
			PartToggle.Size = UDim2.new(1, 0, 0, 30)
			local isSelected = table.find(Config.AimbotTargets, partName) ~= nil
			PartToggle.Text = partName .. ": " .. (isSelected and "ON" or "OFF")
			PartToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
			PartToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
			PartToggle.Font = Enum.Font.SourceSans
			PartToggle.TextSize = 16
			PartToggle.Parent = partsScrolling
			local PartToggleCorner = Instance.new("UICorner")
			PartToggleCorner.CornerRadius = UDim.new(0, 5)
			PartToggleCorner.Parent = PartToggle
			PartToggle.MouseButton1Click:Connect(function()
				local index = table.find(Config.AimbotTargets, partName)
				if index then
					table.remove(Config.AimbotTargets, index)
					PartToggle.Text = partName .. ": OFF"
				else
					table.insert(Config.AimbotTargets, partName)
					PartToggle.Text = partName .. ": ON"
				end
			end)
		end
		-- Aimbot FOV Slider
		local FOVLabel = Instance.new("TextLabel")
		FOVLabel.Size = UDim2.new(1, 0, 0, 20)
		FOVLabel.Text = "Aimbot FOV: " .. Config.AimbotFOV
		FOVLabel.BackgroundTransparency = 1
		FOVLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		FOVLabel.Font = Enum.Font.SourceSans
		FOVLabel.TextSize = 14
		FOVLabel.Parent = aimbotControls
		local FOVSlider = Instance.new("Frame")
		FOVSlider.Size = UDim2.new(1, 0, 0, 10)
		FOVSlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		FOVSlider.Parent = aimbotControls
		local FOVSliderCorner = Instance.new("UICorner")
		FOVSliderCorner.CornerRadius = UDim.new(0, 5)
		FOVSliderCorner.Parent = FOVSlider
		local FOVFill = Instance.new("Frame")
		FOVFill.Size = UDim2.new((Config.AimbotFOV - 10) / 190, 0, 1, 0)
		FOVFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		FOVFill.Parent = FOVSlider
		local FOVFillCorner = Instance.new("UICorner")
		FOVFillCorner.CornerRadius = UDim.new(0, 5)
		FOVFillCorner.Parent = FOVFill
		local draggingFOV
		FOVSlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingFOV = true
			end
		end)
		FOVSlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingFOV = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingFOV then
				local sliderPos = math.clamp((input.Position.X - FOVSlider.AbsolutePosition.X) / FOVSlider.AbsoluteSize.X, 0, 1)
				Config.AimbotFOV = math.floor(sliderPos * 190) + 10
				FOVLabel.Text = "Aimbot FOV: " .. Config.AimbotFOV
				FOVFill.Size = UDim2.new(sliderPos, 0, 1, 0)
			end
		end)
		-- FOV Circle Transparency Slider
		local FOVCircleTransparencyLabel = Instance.new("TextLabel")
		FOVCircleTransparencyLabel.Size = UDim2.new(1, 0, 0, 20)
		FOVCircleTransparencyLabel.Text = "FOV Circle Transparency: " .. string.format("%.2f", Config.FOVCircleTransparency)
		FOVCircleTransparencyLabel.BackgroundTransparency = 1
		FOVCircleTransparencyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		FOVCircleTransparencyLabel.Font = Enum.Font.SourceSans
		FOVCircleTransparencyLabel.TextSize = 14
		FOVCircleTransparencyLabel.Parent = aimbotControls
		local FOVCircleTransparencySlider = Instance.new("Frame")
		FOVCircleTransparencySlider.Size = UDim2.new(1, 0, 0, 10)
		FOVCircleTransparencySlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		FOVCircleTransparencySlider.Parent = aimbotControls
		local FOVCircleTransparencySliderCorner = Instance.new("UICorner")
		FOVCircleTransparencySliderCorner.CornerRadius = UDim.new(0, 5)
		FOVCircleTransparencySliderCorner.Parent = FOVCircleTransparencySlider
		local FOVCircleTransparencyFill = Instance.new("Frame")
		FOVCircleTransparencyFill.Size = UDim2.new(Config.FOVCircleTransparency, 0, 1, 0)
		FOVCircleTransparencyFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		FOVCircleTransparencyFill.Parent = FOVCircleTransparencySlider
		local FOVCircleTransparencyFillCorner = Instance.new("UICorner")
		FOVCircleTransparencyFillCorner.CornerRadius = UDim.new(0, 5)
		FOVCircleTransparencyFillCorner.Parent = FOVCircleTransparencyFill
		local draggingFOVCircleTransparency
		FOVCircleTransparencySlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingFOVCircleTransparency = true
			end
		end)
		FOVCircleTransparencySlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingFOVCircleTransparency = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingFOVCircleTransparency then
				local sliderPos = math.clamp((input.Position.X - FOVCircleTransparencySlider.AbsolutePosition.X) / FOVCircleTransparencySlider.AbsoluteSize.X, 0, 1)
				Config.FOVCircleTransparency = sliderPos
				FOVCircleTransparencyLabel.Text = "FOV Circle Transparency: " .. string.format("%.2f", Config.FOVCircleTransparency)
				FOVCircleTransparencyFill.Size = UDim2.new(sliderPos, 0, 1, 0)
				local fovUIStroke = FOVCircle.MainFrame:FindFirstChild("UIStroke")
				if fovUIStroke then
					fovUIStroke.Transparency = Config.FOVCircleTransparency
				end
			end
		end)
		-- Aimbot Speed Slider
		local SpeedLabel = Instance.new("TextLabel")
		SpeedLabel.Size = UDim2.new(1, 0, 0, 20)
		SpeedLabel.Text = "Aimbot Speed: " .. string.format("%.2f", Config.AimbotSpeed)
		SpeedLabel.BackgroundTransparency = 1
		SpeedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		SpeedLabel.Font = Enum.Font.SourceSans
		SpeedLabel.TextSize = 14
		SpeedLabel.Parent = aimbotControls
		local SpeedSlider = Instance.new("Frame")
		SpeedSlider.Size = UDim2.new(1, 0, 0, 10)
		SpeedSlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		SpeedSlider.Parent = aimbotControls
		local SpeedSliderCorner = Instance.new("UICorner")
		SpeedSliderCorner.CornerRadius = UDim.new(0, 5)
		SpeedSliderCorner.Parent = SpeedSlider
		local SpeedFill = Instance.new("Frame")
		SpeedFill.Size = UDim2.new((Config.AimbotSpeed - 0.1) / 0.9, 0, 1, 0)
		SpeedFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		SpeedFill.Parent = SpeedSlider
		local SpeedFillCorner = Instance.new("UICorner")
		SpeedFillCorner.CornerRadius = UDim.new(0, 5)
		SpeedFillCorner.Parent = SpeedFill
		local draggingSpeed
		SpeedSlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingSpeed = true
			end
		end)
		SpeedSlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingSpeed = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingSpeed then
				local sliderPos = math.clamp((input.Position.X - SpeedSlider.AbsolutePosition.X) / SpeedSlider.AbsoluteSize.X, 0, 1)
				Config.AimbotSpeed = sliderPos * 0.9 + 0.1
				SpeedLabel.Text = "Aimbot Speed: " .. string.format("%.2f", Config.AimbotSpeed)
				SpeedFill.Size = UDim2.new(sliderPos, 0, 1, 0)
			end
		end)
		-- Aimbot Team Check Toggle
		local TeamCheckToggle = Instance.new("TextButton")
		TeamCheckToggle.Size = UDim2.new(1, 0, 0, 30)
		TeamCheckToggle.Text = "Aimbot Team Check: " .. (Config.AimbotTeamCheck and "ON" or "OFF")
		TeamCheckToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		TeamCheckToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		TeamCheckToggle.Font = Enum.Font.SourceSans
		TeamCheckToggle.TextSize = 16
		TeamCheckToggle.Parent = aimbotControls
		local TeamCheckToggleCorner = Instance.new("UICorner")
		TeamCheckToggleCorner.CornerRadius = UDim.new(0, 5)
		TeamCheckToggleCorner.Parent = TeamCheckToggle
		TeamCheckToggle.MouseButton1Click:Connect(function()
			Config.AimbotTeamCheck = not Config.AimbotTeamCheck
			TeamCheckToggle.Text = "Aimbot Team Check: " .. (Config.AimbotTeamCheck and "ON" or "OFF")
		end)
		-- Wall Check Toggle
		local WallCheckToggle = Instance.new("TextButton")
		WallCheckToggle.Size = UDim2.new(1, 0, 0, 30)
		WallCheckToggle.Text = "Wall Check: " .. (Config.WallCheckEnabled and "ON" or "OFF")
		WallCheckToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		WallCheckToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		WallCheckToggle.Font = Enum.Font.SourceSans
		WallCheckToggle.TextSize = 16
		WallCheckToggle.Parent = aimbotControls
		local WallCheckToggleCorner = Instance.new("UICorner")
		WallCheckToggleCorner.CornerRadius = UDim.new(0, 5)
		WallCheckToggleCorner.Parent = WallCheckToggle
		WallCheckToggle.MouseButton1Click:Connect(function()
			Config.WallCheckEnabled = not Config.WallCheckEnabled
			WallCheckToggle.Text = "Wall Check: " .. (Config.WallCheckEnabled and "ON" or "OFF")
		end)
		-- Aimbot Max Distance Slider
		local AimbotDistanceLabel = Instance.new("TextLabel")
		AimbotDistanceLabel.Size = UDim2.new(1, 0, 0, 20)
		AimbotDistanceLabel.Text = "Aimbot Max Distance: " .. Config.AimbotMaxDistance
		AimbotDistanceLabel.BackgroundTransparency = 1
		AimbotDistanceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		AimbotDistanceLabel.Font = Enum.Font.SourceSans
		AimbotDistanceLabel.TextSize = 14
		AimbotDistanceLabel.Parent = aimbotControls
		local AimbotDistanceSlider = Instance.new("Frame")
		AimbotDistanceSlider.Size = UDim2.new(1, 0, 0, 10)
		AimbotDistanceSlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		AimbotDistanceSlider.Parent = aimbotControls
		local AimbotDistanceSliderCorner = Instance.new("UICorner")
		AimbotDistanceSliderCorner.CornerRadius = UDim.new(0, 5)
		AimbotDistanceSliderCorner.Parent = AimbotDistanceSlider
		local AimbotDistanceFill = Instance.new("Frame")
		AimbotDistanceFill.Size = UDim2.new((Config.AimbotMaxDistance - 100) / 1900, 0, 1, 0)
		AimbotDistanceFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		AimbotDistanceFill.Parent = AimbotDistanceSlider
		local AimbotDistanceFillCorner = Instance.new("UICorner")
		AimbotDistanceFillCorner.CornerRadius = UDim.new(0, 5)
		AimbotDistanceFillCorner.Parent = AimbotDistanceFill
		local draggingAimbotDistance
		AimbotDistanceSlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingAimbotDistance = true
			end
		end)
		AimbotDistanceSlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingAimbotDistance = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingAimbotDistance then
				local sliderPos = math.clamp((input.Position.X - AimbotDistanceSlider.AbsolutePosition.X) / AimbotDistanceSlider.AbsoluteSize.X, 0, 1)
				Config.AimbotMaxDistance = math.floor(sliderPos * 1900) + 100
				AimbotDistanceLabel.Text = "Aimbot Max Distance: " .. Config.AimbotMaxDistance
				AimbotDistanceFill.Size = UDim2.new(sliderPos, 0, 1, 0)
			end
		end)
		-- Random Offset Toggle
		local RandomOffsetToggle = Instance.new("TextButton")
		RandomOffsetToggle.Size = UDim2.new(1, 0, 0, 30)
		RandomOffsetToggle.Text = "Random Offset: " .. (Config.AimbotRandomOffset and "ON" or "OFF")
		RandomOffsetToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		RandomOffsetToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		RandomOffsetToggle.Font = Enum.Font.SourceSans
		RandomOffsetToggle.TextSize = 16
		RandomOffsetToggle.Parent = aimbotControls
		local RandomOffsetToggleCorner = Instance.new("UICorner")
		RandomOffsetToggleCorner.CornerRadius = UDim.new(0, 5)
		RandomOffsetToggleCorner.Parent = RandomOffsetToggle
		RandomOffsetToggle.MouseButton1Click:Connect(function()
			Config.AimbotRandomOffset = not Config.AimbotRandomOffset
			RandomOffsetToggle.Text = "Random Offset: " .. (Config.AimbotRandomOffset and "ON" or "OFF")
		end)
		-- Offset Max Slider
		local OffsetMaxLabel = Instance.new("TextLabel")
		OffsetMaxLabel.Size = UDim2.new(1, 0, 0, 20)
		OffsetMaxLabel.Text = "Offset Max: " .. string.format("%.2f", Config.AimbotOffsetMax)
		OffsetMaxLabel.BackgroundTransparency = 1
		OffsetMaxLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		OffsetMaxLabel.Font = Enum.Font.SourceSans
		OffsetMaxLabel.TextSize = 14
		OffsetMaxLabel.Parent = aimbotControls
		local OffsetMaxSlider = Instance.new("Frame")
		OffsetMaxSlider.Size = UDim2.new(1, 0, 0, 10)
		OffsetMaxSlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		OffsetMaxSlider.Parent = aimbotControls
		local OffsetMaxSliderCorner = Instance.new("UICorner")
		OffsetMaxSliderCorner.CornerRadius = UDim.new(0, 5)
		OffsetMaxSliderCorner.Parent = OffsetMaxSlider
		local OffsetMaxFill = Instance.new("Frame")
		OffsetMaxFill.Size = UDim2.new(Config.AimbotOffsetMax / 2, 0, 1, 0)
		OffsetMaxFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		OffsetMaxFill.Parent = OffsetMaxSlider
		local OffsetMaxFillCorner = Instance.new("UICorner")
		OffsetMaxFillCorner.CornerRadius = UDim.new(0, 5)
		OffsetMaxFillCorner.Parent = OffsetMaxFill
		local draggingOffsetMax
		OffsetMaxSlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingOffsetMax = true
			end
		end)
		OffsetMaxSlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingOffsetMax = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingOffsetMax then
				local sliderPos = math.clamp((input.Position.X - OffsetMaxSlider.AbsolutePosition.X) / OffsetMaxSlider.AbsoluteSize.X, 0, 1)
				Config.AimbotOffsetMax = sliderPos * 2
				OffsetMaxLabel.Text = "Offset Max: " .. string.format("%.2f", Config.AimbotOffsetMax)
				OffsetMaxFill.Size = UDim2.new(sliderPos, 0, 1, 0)
			end
		end)
		-- Movement Section
		local movementControls = createSection("Movement Settings", true)
		-- Fly Toggle
		local FlyToggle = Instance.new("TextButton")
		FlyToggle.Name = "FlyToggle"
		FlyToggle.Size = UDim2.new(1, 0, 0, 30)
		FlyToggle.Text = "Fly: OFF [" .. Config.FlyKey.Name .. "]"
		FlyToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		FlyToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		FlyToggle.Font = Enum.Font.SourceSans
		FlyToggle.TextSize = 16
		FlyToggle.Parent = movementControls
		local FlyToggleCorner = Instance.new("UICorner")
		FlyToggleCorner.CornerRadius = UDim.new(0, 5)
		FlyToggleCorner.Parent = FlyToggle
		FlyToggle.MouseButton1Click:Connect(function()
			if not Config.FlyForceDisabled then
				Config.FlyEnabled = not Config.FlyEnabled
				FlyToggle.Text = "Fly: " .. (Config.FlyEnabled and "ON" or "OFF") .. " [" .. Config.FlyKey.Name .. "]"
			end
		end)
		-- Fly Keybind
		local FlyKeybind = Instance.new("TextButton")
		FlyKeybind.Size = UDim2.new(1, 0, 0, 30)
		FlyKeybind.Text = "Set Fly Key: " .. Config.FlyKey.Name
		FlyKeybind.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		FlyKeybind.TextColor3 = Color3.fromRGB(255, 255, 255)
		FlyKeybind.Font = Enum.Font.SourceSans
		FlyKeybind.TextSize = 16
		FlyKeybind.Parent = movementControls
		local FlyKeybindCorner = Instance.new("UICorner")
		FlyKeybindCorner.CornerRadius = UDim.new(0, 5)
		FlyKeybindCorner.Parent = FlyKeybind
		FlyKeybind.MouseButton1Click:Connect(function()
			FlyKeybind.Text = "Set Fly Key: Press a key..."
			local input = UserInputService.InputBegan:Wait()
			if input.KeyCode ~= Enum.KeyCode.Unknown then
				Config.FlyKey = input.KeyCode
				FlyKeybind.Text = "Set Fly Key: " .. Config.FlyKey.Name
				FlyToggle.Text = "Fly: " .. (Config.FlyEnabled and "ON" or "OFF") .. " [" .. Config.FlyKey.Name .. "]"
			else
				FlyKeybind.Text = "Set Fly Key: " .. Config.FlyKey.Name
			end
		end)
		-- Fly Speed Slider
		local FlySpeedLabel = Instance.new("TextLabel")
		FlySpeedLabel.Size = UDim2.new(1, 0, 0, 20)
		FlySpeedLabel.Text = "Fly Speed: " .. Config.FlySpeed
		FlySpeedLabel.BackgroundTransparency = 1
		FlySpeedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		FlySpeedLabel.Font = Enum.Font.SourceSans
		FlySpeedLabel.TextSize = 14
		FlySpeedLabel.Parent = movementControls
		local FlySpeedSlider = Instance.new("Frame")
		FlySpeedSlider.Size = UDim2.new(1, 0, 0, 10)
		FlySpeedSlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		FlySpeedSlider.Parent = movementControls
		local FlySpeedSliderCorner = Instance.new("UICorner")
		FlySpeedSliderCorner.CornerRadius = UDim.new(0, 5)
		FlySpeedSliderCorner.Parent = FlySpeedSlider
		local FlySpeedFill = Instance.new("Frame")
		FlySpeedFill.Size = UDim2.new((Config.FlySpeed - 10) / 190, 0, 1, 0)
		FlySpeedFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		FlySpeedFill.Parent = FlySpeedSlider
		local FlySpeedFillCorner = Instance.new("UICorner")
		FlySpeedFillCorner.CornerRadius = UDim.new(0, 5)
		FlySpeedFillCorner.Parent = FlySpeedFill
		local draggingFlySpeed
		FlySpeedSlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingFlySpeed = true
			end
		end)
		FlySpeedSlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingFlySpeed = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingFlySpeed then
				local sliderPos = math.clamp((input.Position.X - FlySpeedSlider.AbsolutePosition.X) / FlySpeedSlider.AbsoluteSize.X, 0, 1)
				Config.FlySpeed = math.floor(sliderPos * 190) + 10
				FlySpeedLabel.Text = "Fly Speed: " .. Config.FlySpeed
				FlySpeedFill.Size = UDim2.new(sliderPos, 0, 1, 0)
			end
		end)
		-- Fly Force Disable Toggle
		local FlyForceDisableToggle = Instance.new("TextButton")
		FlyForceDisableToggle.Name = "FlyForceDisableToggle"
		FlyForceDisableToggle.Size = UDim2.new(1, 0, 0, 30)
		FlyForceDisableToggle.Text = "Force Disable Fly: OFF"
		FlyForceDisableToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		FlyForceDisableToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		FlyForceDisableToggle.Font = Enum.Font.SourceSans
		FlyForceDisableToggle.TextSize = 16
		FlyForceDisableToggle.Parent = movementControls
		local FlyForceDisableToggleCorner = Instance.new("UICorner")
		FlyForceDisableToggleCorner.CornerRadius = UDim.new(0, 5)
		FlyForceDisableToggleCorner.Parent = FlyForceDisableToggle
		FlyForceDisableToggle.MouseButton1Click:Connect(function()
			Config.FlyForceDisabled = not Config.FlyForceDisabled
			FlyForceDisableToggle.Text = "Force Disable Fly: " .. (Config.FlyForceDisabled and "ON" or "OFF")
			if Config.FlyForceDisabled then
				if Config.FlyEnabled then
					Config.FlyEnabled = false
					local FlyToggle = movementControls:FindFirstChild("FlyToggle")
					if FlyToggle then
						FlyToggle.Text = "Fly: OFF [" .. Config.FlyKey.Name .. "]"
					end
				end
				local character = LocalPlayer.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if hrp and hrp:FindFirstChild("FlyBV") then
					hrp.FlyBV:Destroy()
				end
				if humanoid then
					humanoid.PlatformStand = false
				end
			end
		end)
		-- Noclip Toggle
		local NoclipToggle = Instance.new("TextButton")
		NoclipToggle.Name = "NoclipToggle"
		NoclipToggle.Size = UDim2.new(1, 0, 0, 30)
		NoclipToggle.Text = "Noclip: OFF [" .. Config.NoclipKey.Name .. "]"
		NoclipToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		NoclipToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		NoclipToggle.Font = Enum.Font.SourceSans
		NoclipToggle.TextSize = 16
		NoclipToggle.Parent = movementControls
		local NoclipToggleCorner = Instance.new("UICorner")
		NoclipToggleCorner.CornerRadius = UDim.new(0, 5)
		NoclipToggleCorner.Parent = NoclipToggle
		NoclipToggle.MouseButton1Click:Connect(function()
			if not Config.NoclipForceDisabled then
				Config.NoclipEnabled = not Config.NoclipEnabled
				NoclipToggle.Text = "Noclip: " .. (Config.NoclipEnabled and "ON" or "OFF") .. " [" .. Config.NoclipKey.Name .. "]"
				if not Config.NoclipEnabled then
					local character = LocalPlayer.Character
					if character then
						for _, part in ipairs(character:GetDescendants()) do
							if part:IsA("BasePart") then
								part.CanCollide = true
							end
						end
					end
				end
			end
		end)
		-- Noclip Keybind
		local NoclipKeybind = Instance.new("TextButton")
		NoclipKeybind.Size = UDim2.new(1, 0, 0, 30)
		NoclipKeybind.Text = "Set Noclip Key: " .. Config.NoclipKey.Name
		NoclipKeybind.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		NoclipKeybind.TextColor3 = Color3.fromRGB(255, 255, 255)
		NoclipKeybind.Font = Enum.Font.SourceSans
		NoclipKeybind.TextSize = 16
		NoclipKeybind.Parent = movementControls
		local NoclipKeybindCorner = Instance.new("UICorner")
		NoclipKeybindCorner.CornerRadius = UDim.new(0, 5)
		NoclipKeybindCorner.Parent = NoclipKeybind
		NoclipKeybind.MouseButton1Click:Connect(function()
			NoclipKeybind.Text = "Set Noclip Key: Press a key..."
			local input = UserInputService.InputBegan:Wait()
			if input.KeyCode ~= Enum.KeyCode.Unknown then
				Config.NoclipKey = input.KeyCode
				NoclipKeybind.Text = "Set Noclip Key: " .. Config.NoclipKey.Name
				NoclipToggle.Text = "Noclip: " .. (Config.NoclipEnabled and "ON" or "OFF") .. " [" .. Config.NoclipKey.Name .. "]"
			else
				NoclipKeybind.Text = "Set Noclip Key: " .. Config.NoclipKey.Name
			end
		end)
		-- Noclip Force Disable Toggle
		local NoclipForceDisableToggle = Instance.new("TextButton")
		NoclipForceDisableToggle.Name = "NoclipForceDisableToggle"
		NoclipForceDisableToggle.Size = UDim2.new(1, 0, 0, 30)
		NoclipForceDisableToggle.Text = "Force Disable Noclip: OFF"
		NoclipForceDisableToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		NoclipForceDisableToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		NoclipForceDisableToggle.Font = Enum.Font.SourceSans
		NoclipForceDisableToggle.TextSize = 16
		NoclipForceDisableToggle.Parent = movementControls
		local NoclipForceDisableToggleCorner = Instance.new("UICorner")
		NoclipForceDisableToggleCorner.CornerRadius = UDim.new(0, 5)
		NoclipForceDisableToggleCorner.Parent = NoclipForceDisableToggle
		NoclipForceDisableToggle.MouseButton1Click:Connect(function()
			Config.NoclipForceDisabled = not Config.NoclipForceDisabled
			NoclipForceDisableToggle.Text = "Force Disable Noclip: " .. (Config.NoclipForceDisabled and "ON" or "OFF")
			if Config.NoclipForceDisabled then
				if Config.NoclipEnabled then
					Config.NoclipEnabled = false
					local NoclipToggle = movementControls:FindFirstChild("NoclipToggle")
					if NoclipToggle then
						NoclipToggle.Text = "Noclip: OFF [" .. Config.NoclipKey.Name .. "]"
					end
				end
				local character = LocalPlayer.Character
				if character then
					for _, part in ipairs(character:GetDescendants()) do
						if part:IsA("BasePart") then
							part.CanCollide = true
						end
					end
				end
			end
		end)
		-- New: Speed Hack Toggle
		local SpeedHackToggle = Instance.new("TextButton")
		SpeedHackToggle.Name = "SpeedHackToggle"
		SpeedHackToggle.Size = UDim2.new(1, 0, 0, 30)
		SpeedHackToggle.Text = "Speed Hack: OFF [" .. Config.SpeedHackKey.Name .. "]"
		SpeedHackToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		SpeedHackToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		SpeedHackToggle.Font = Enum.Font.SourceSans
		SpeedHackToggle.TextSize = 16
		SpeedHackToggle.Parent = movementControls
		local SpeedHackToggleCorner = Instance.new("UICorner")
		SpeedHackToggleCorner.CornerRadius = UDim.new(0, 5)
		SpeedHackToggleCorner.Parent = SpeedHackToggle
		SpeedHackToggle.MouseButton1Click:Connect(function()
			if not Config.SpeedHackForceDisabled then
				Config.SpeedHackEnabled = not Config.SpeedHackEnabled
				SpeedHackToggle.Text = "Speed Hack: " .. (Config.SpeedHackEnabled and "ON" or "OFF") .. " [" .. Config.SpeedHackKey.Name .. "]"
				local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.WalkSpeed = Config.SpeedHackEnabled and Config.SpeedHackValue or 16
				end
			end
		end)
		-- Speed Hack Keybind
		local SpeedHackKeybind = Instance.new("TextButton")
		SpeedHackKeybind.Size = UDim2.new(1, 0, 0, 30)
		SpeedHackKeybind.Text = "Set Speed Hack Key: " .. Config.SpeedHackKey.Name
		SpeedHackKeybind.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		SpeedHackKeybind.TextColor3 = Color3.fromRGB(255, 255, 255)
		SpeedHackKeybind.Font = Enum.Font.SourceSans
		SpeedHackKeybind.TextSize = 16
		SpeedHackKeybind.Parent = movementControls
		local SpeedHackKeybindCorner = Instance.new("UICorner")
		SpeedHackKeybindCorner.CornerRadius = UDim.new(0, 5)
		SpeedHackKeybindCorner.Parent = SpeedHackKeybind
		SpeedHackKeybind.MouseButton1Click:Connect(function()
			SpeedHackKeybind.Text = "Set Speed Hack Key: Press a key..."
			local input = UserInputService.InputBegan:Wait()
			if input.KeyCode ~= Enum.KeyCode.Unknown then
				Config.SpeedHackKey = input.KeyCode
				SpeedHackKeybind.Text = "Set Speed Hack Key: " .. Config.SpeedHackKey.Name
				SpeedHackToggle.Text = "Speed Hack: " .. (Config.SpeedHackEnabled and "ON" or "OFF") .. " [" .. Config.SpeedHackKey.Name .. "]"
			else
				SpeedHackKeybind.Text = "Set Speed Hack Key: " .. Config.SpeedHackKey.Name
			end
		end)
		-- Speed Hack Value Slider
		local SpeedHackValueLabel = Instance.new("TextLabel")
		SpeedHackValueLabel.Size = UDim2.new(1, 0, 0, 20)
		SpeedHackValueLabel.Text = "Speed Hack Value: " .. Config.SpeedHackValue
		SpeedHackValueLabel.BackgroundTransparency = 1
		SpeedHackValueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		SpeedHackValueLabel.Font = Enum.Font.SourceSans
		SpeedHackValueLabel.TextSize = 14
		SpeedHackValueLabel.Parent = movementControls
		local SpeedHackValueSlider = Instance.new("Frame")
		SpeedHackValueSlider.Size = UDim2.new(1, 0, 0, 10)
		SpeedHackValueSlider.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		SpeedHackValueSlider.Parent = movementControls
		local SpeedHackValueSliderCorner = Instance.new("UICorner")
		SpeedHackValueSliderCorner.CornerRadius = UDim.new(0, 5)
		SpeedHackValueSliderCorner.Parent = SpeedHackValueSlider
		local SpeedHackValueFill = Instance.new("Frame")
		SpeedHackValueFill.Size = UDim2.new((Config.SpeedHackValue - 16) / 84, 0, 1, 0)
		SpeedHackValueFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
		SpeedHackValueFill.Parent = SpeedHackValueSlider
		local SpeedHackValueFillCorner = Instance.new("UICorner")
		SpeedHackValueFillCorner.CornerRadius = UDim.new(0, 5)
		SpeedHackValueFillCorner.Parent = SpeedHackValueFill
		local draggingSpeedHackValue
		SpeedHackValueSlider.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingSpeedHackValue = true
			end
		end)
		SpeedHackValueSlider.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				draggingSpeedHackValue = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement and draggingSpeedHackValue then
				local sliderPos = math.clamp((input.Position.X - SpeedHackValueSlider.AbsolutePosition.X) / SpeedHackValueSlider.AbsoluteSize.X, 0, 1)
				Config.SpeedHackValue = math.floor(sliderPos * 84) + 16
				SpeedHackValueLabel.Text = "Speed Hack Value: " .. Config.SpeedHackValue
				SpeedHackValueFill.Size = UDim2.new(sliderPos, 0, 1, 0)
				local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
				if humanoid and Config.SpeedHackEnabled then
					humanoid.WalkSpeed = Config.SpeedHackValue
				end
			end
		end)
		-- New: Speed Hack Force Disable Toggle
		local SpeedHackForceDisableToggle = Instance.new("TextButton")
		SpeedHackForceDisableToggle.Name = "SpeedHackForceDisableToggle"
		SpeedHackForceDisableToggle.Size = UDim2.new(1, 0, 0, 30)
		SpeedHackForceDisableToggle.Text = "Force Disable Speed Hack: OFF"
		SpeedHackForceDisableToggle.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		SpeedHackForceDisableToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
		SpeedHackForceDisableToggle.Font = Enum.Font.SourceSans
		SpeedHackForceDisableToggle.TextSize = 16
		SpeedHackForceDisableToggle.Parent = movementControls
		local SpeedHackForceDisableToggleCorner = Instance.new("UICorner")
		SpeedHackForceDisableToggleCorner.CornerRadius = UDim.new(0, 5)
		SpeedHackForceDisableToggleCorner.Parent = SpeedHackForceDisableToggle
		SpeedHackForceDisableToggle.MouseButton1Click:Connect(function()
			Config.SpeedHackForceDisabled = not Config.SpeedHackForceDisabled
			SpeedHackForceDisableToggle.Text = "Force Disable Speed Hack: " .. (Config.SpeedHackForceDisabled and "ON" or "OFF")
			if Config.SpeedHackForceDisabled then
				if Config.SpeedHackEnabled then
					Config.SpeedHackEnabled = false
					local SpeedHackToggle = movementControls:FindFirstChild("SpeedHackToggle")
					if SpeedHackToggle then
						SpeedHackToggle.Text = "Speed Hack: OFF [" .. Config.SpeedHackKey.Name .. "]"
					end
				end
				local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.WalkSpeed = 16
				end
			end
		end)
		print("GUI creation completed")
	end)
	if not success then
		warn("GUI creation failed: " .. tostring(errorMsg))
	end
end
-- Create FOV Circle
local function createFOVCircle()
	local success, errorMsg = pcall(function()
		local FOVCircle = Instance.new("ScreenGui")
		FOVCircle.Name = "FOVCircle"
		FOVCircle.Parent = LocalPlayer.PlayerGui
		FOVCircle.ResetOnSpawn = false
		FOVCircle.DisplayOrder = 999
		FOVCircle.Enabled = true
		local FOVFrame = Instance.new("Frame")
		FOVFrame.Name = "MainFrame"
		FOVFrame.Size = UDim2.new(0, Config.AimbotFOV * 2, 0, Config.AimbotFOV * 2)
		FOVFrame.Position = UDim2.new(0.5, -Config.AimbotFOV, 0.5, -Config.AimbotFOV)
		FOVFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		FOVFrame.BackgroundTransparency = 1
		FOVFrame.BorderSizePixel = 0
		FOVFrame.Parent = FOVCircle
		local UICorner = Instance.new("UICorner")
		UICorner.CornerRadius = UDim.new(1, 0)
		UICorner.Parent = FOVFrame
		local UIStroke = Instance.new("UIStroke")
		UIStroke.Color = Color3.fromRGB(255, 255, 255)
		UIStroke.Thickness = 1
		UIStroke.Transparency = Config.FOVCircleTransparency
		UIStroke.Parent = FOVFrame
		print("FOV Circle created")
	end)
	if not success then
		warn("FOV Circle creation failed: " .. tostring(errorMsg))
	end
end
-- Update FOV Circle
local function updateFOVCircle()
	local FOVCircle = LocalPlayer.PlayerGui:FindFirstChild("FOVCircle")
	if FOVCircle then
		local FOVFrame = FOVCircle:FindFirstChild("MainFrame")
		if FOVFrame then
			local size = Config.AimbotFOV * 2
			FOVFrame.Size = UDim2.new(0, size, 0, size)
			FOVFrame.Position = UDim2.new(0.5, -Config.AimbotFOV, 0.5, -Config.AimbotFOV)
			local UIStroke = FOVFrame:FindFirstChild("UIStroke")
			if UIStroke then
				UIStroke.Transparency = Config.FOVCircleTransparency
			end
		end
	end
end
-- ESP Function
local function createESP(player)
	if not Config.ESPEnabled or player == LocalPlayer then
		return
	end
	local character = player.Character
	if not character then return end
	local cache = playerCache[player] or {}
	playerCache[player] = cache
	if cache.character ~= character then
		if cache.highlight then
			cache.highlight:Destroy()
			cache.highlight = nil
		end
		if cache.billboard then
			cache.billboard:Destroy()
			cache.billboard = nil
		end
		cache.character = character
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (humanoidRootPart and head and humanoid) then return end
	local localCharacter = LocalPlayer.Character
	local localHRP = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	local distance = localHRP and (localHRP.Position - humanoidRootPart.Position).Magnitude or math.huge
	if distance > Config.MaxDistance then
		if cache.highlight then
			cache.highlight:Destroy()
			cache.highlight = nil
		end
		if cache.billboard then
			cache.billboard:Destroy()
			cache.billboard = nil
		end
		cache.character = nil
		return
	end
	local highlight = cache.highlight
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "BoxESP"
		highlight.Adornee = character
		highlight.FillTransparency = 1
		highlight.OutlineColor = player.Team and player.Team.TeamColor.Color or Config.OutlineColor
		highlight.OutlineTransparency = Config.OutlineTransparency
		highlight.Parent = character
		cache.highlight = highlight
	else
		highlight.OutlineColor = player.Team and player.Team.TeamColor.Color or Config.OutlineColor
		highlight.OutlineTransparency = Config.OutlineTransparency
		highlight.Adornee = character
	end
	if not (Config.ShowNameESP or Config.ShowHealthESP or Config.ShowDistanceESP) then
		if cache.billboard then
			cache.billboard:Destroy()
			cache.billboard = nil
		end
		return
	end
	local billboard = cache.billboard
	if not billboard then
		billboard = Instance.new("BillboardGui")
		billboard.Name = "NameESP"
		billboard.Adornee = head
		billboard.Size = UDim2.new(0, 100, 0, 50)
		billboard.StudsOffset = Vector3.new(0, 2.5, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 0
		billboard.Parent = character
		cache.billboard = billboard
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, 0, 0, 20)
		nameLabel.Position = UDim2.new(0, 0, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = player.Name
		nameLabel.TextColor3 = player.Team and player.Team.TeamColor.Color or Color3.fromRGB(255, 255, 255)
		nameLabel.TextTransparency = Config.NameTransparency
		nameLabel.TextStrokeTransparency = Config.NameTransparency -- Fixed: No clamp, full control
		nameLabel.TextScaled = false -- Fixed: Disable scaling to allow manual size control
		nameLabel.Font = Enum.Font.SourceSans
		nameLabel.TextSize = Config.NameSize
		nameLabel.Parent = billboard
		cache.nameLabel = nameLabel
		local healthBarFrame = Instance.new("Frame")
		healthBarFrame.Size = UDim2.new(1, 0, 0, Config.HealthBarHeight)
		healthBarFrame.Position = UDim2.new(0, 0, 0, 20)
		healthBarFrame.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		healthBarFrame.BackgroundTransparency = Config.HealthBarTransparency
		healthBarFrame.BorderSizePixel = 0
		healthBarFrame.Parent = billboard
		cache.healthBarFrame = healthBarFrame
		local healthBarFill = Instance.new("Frame")
		healthBarFill.Size = UDim2.new(humanoid.Health / humanoid.MaxHealth, 0, 1, 0)
		healthBarFill.BackgroundColor3 = Color3.fromHSV(math.clamp(humanoid.Health / humanoid.MaxHealth / 3, 0, 0.33), 1, 1)
		healthBarFill.BackgroundTransparency = Config.HealthBarTransparency
		healthBarFill.BorderSizePixel = 0
		healthBarFill.Parent = healthBarFrame
		cache.healthBarFill = healthBarFill
		humanoid.HealthChanged:Connect(function(health)
			healthBarFill.Size = UDim2.new(math.clamp(health / humanoid.MaxHealth, 0, 1), 0, 1, 0)
			healthBarFill.BackgroundColor3 = Color3.fromHSV(math.clamp(health / humanoid.MaxHealth / 3, 0, 0.33), 1, 1)
			healthBarFill.BackgroundTransparency = Config.HealthBarTransparency
		end)
		-- New: Distance Label
		local distanceLabel = Instance.new("TextLabel")
		distanceLabel.Size = UDim2.new(1, 0, 0, 20)
		distanceLabel.Position = UDim2.new(0, 0, 0, 20 + Config.HealthBarHeight)
		distanceLabel.BackgroundTransparency = 1
		distanceLabel.Text = "[" .. math.round(distance) .. "]"
		distanceLabel.TextColor3 = player.Team and player.Team.TeamColor.Color or Color3.fromRGB(255, 255, 255)
		distanceLabel.TextTransparency = Config.DistanceTransparency
		distanceLabel.TextStrokeTransparency = Config.DistanceTransparency
		distanceLabel.TextScaled = false -- Fixed: Disable scaling to allow manual size control
		distanceLabel.Font = Enum.Font.SourceSans
		distanceLabel.TextSize = Config.DistanceSize
		distanceLabel.Parent = billboard
		cache.distanceLabel = distanceLabel
	else
		billboard.Adornee = head
	end
	local nameLabel = cache.nameLabel
	local healthBarFrame = cache.healthBarFrame
	local healthBarFill = cache.healthBarFill
	local distanceLabel = cache.distanceLabel
	if nameLabel then
		nameLabel.TextSize = Config.NameSize
		nameLabel.TextColor3 = player.Team and player.Team.TeamColor.Color or Color3.fromRGB(255, 255, 255)
		nameLabel.TextTransparency = Config.NameTransparency
		nameLabel.TextStrokeTransparency = Config.NameTransparency -- Fixed
		nameLabel.Visible = Config.ShowNameESP
	end
	if healthBarFrame then
		healthBarFrame.Size = UDim2.new(1, 0, 0, Config.HealthBarHeight)
		healthBarFrame.BackgroundTransparency = Config.HealthBarTransparency
		healthBarFrame.Visible = Config.ShowHealthESP
	end
	if healthBarFill then
		healthBarFill.BackgroundTransparency = Config.HealthBarTransparency
	end
	if distanceLabel then
		distanceLabel.Text = "[" .. math.round(distance) .. "]"
		distanceLabel.TextSize = Config.DistanceSize
		distanceLabel.TextColor3 = player.Team and player.Team.TeamColor.Color or Color3.fromRGB(255, 255, 255)
		distanceLabel.TextTransparency = Config.DistanceTransparency
		distanceLabel.TextStrokeTransparency = Config.DistanceTransparency
		distanceLabel.Visible = Config.ShowDistanceESP
	end
	local offsetY = 0
	if Config.ShowNameESP then
		nameLabel.Position = UDim2.new(0, 0, 0, offsetY)
		offsetY = offsetY + 20
	end
	if Config.ShowHealthESP then
		healthBarFrame.Position = UDim2.new(0, 0, 0, offsetY)
		offsetY = offsetY + Config.HealthBarHeight
	end
	if Config.ShowDistanceESP then
		distanceLabel.Position = UDim2.new(0, 0, 0, offsetY)
		offsetY = offsetY + 20
	end
end
-- Part Visibility Check
local function isPartVisible(part)
	if not part then return false end
	local origin = Camera.CFrame.Position
	local direction = (part.Position - origin).Unit * (part.Position - origin).Magnitude
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {LocalPlayer.Character}
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local result = Workspace:Raycast(origin, direction, params)
	return not result or result.Instance:IsDescendantOf(part.Parent)
end
-- Wall Check Function (checks if any part is visible)
local function isVisible(character)
	if not Config.WallCheckEnabled then
		return true
	end
	local partsToCheck = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot"}
	for _, partName in ipairs(partsToCheck) do
		local part = character:FindFirstChild(partName)
		if part and isPartVisible(part) then
			return true
		end
	end
	return false
end
-- Get Best Part and 2D Distance for A Player
local function getBestPartAndDist(player)
	local character = player.Character
	if not character then return nil, math.huge end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return nil, math.huge end
	if Config.AimbotTeamCheck and LocalPlayer.Team and player.Team == LocalPlayer.Team then return nil, math.huge end
	local localCharacter = LocalPlayer.Character
	local localHRP = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	local targetHRP = character:FindFirstChild("HumanoidRootPart")
	if not localHRP or not targetHRP then return nil, math.huge end
	local dist3D = (localHRP.Position - targetHRP.Position).Magnitude
	if dist3D > Config.AimbotMaxDistance then return nil, math.huge end
	local minDist = math.huge
	local bestPart = nil
	local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
	for _, partName in ipairs(Config.AimbotTargets) do
		local part = character:FindFirstChild(partName)
		if part then
			local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
			if onScreen then
				local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
				if dist2D < Config.AimbotFOV and dist2D < minDist then
					local visible = not Config.WallCheckEnabled or isPartVisible(part)
					if visible then
						bestPart = part
						minDist = dist2D
					end
				end
			end
		end
	end
	return bestPart, minDist
end
-- Aimbot Function
local currentTarget = nil
local function getClosestPlayerInFOV()
	local localCharacter = LocalPlayer.Character
	local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
	-- Check current target
	if currentTarget and currentTarget.Character then
		local _, dist = getBestPartAndDist(currentTarget)
		if dist < Config.AimbotFOV then
			return currentTarget
		end
	end
	currentTarget = nil
	local bestValue
	local compareFunc
	local getValue
	if Config.AimbotTargetMode == "Highest HP" then
		bestValue = -math.huge
		compareFunc = function(val, best) return val > best end
		getValue = function(dist, hp, dist3D) return hp end
	elseif Config.AimbotTargetMode == "Lowest HP" then
		bestValue = math.huge
		compareFunc = function(val, best) return val < best end
		getValue = function(dist, hp, dist3D) return hp end
	elseif Config.AimbotTargetMode == "Closest Distance" then
		bestValue = math.huge
		compareFunc = function(val, best) return val < best end
		getValue = function(dist, hp, dist3D) return dist3D end
	elseif Config.AimbotTargetMode == "Any" then
		compareFunc = function() return true end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			local bestPart, dist2D = getBestPartAndDist(player)
			if bestPart then
				local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
				local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
				local dist3D = localRoot and targetRoot and (localRoot.Position - targetRoot.Position).Magnitude or math.huge
				if Config.AimbotTargetMode == "Any" then
					currentTarget = player
					return currentTarget
				else
					local val = getValue(dist2D, humanoid.Health, dist3D)
					if compareFunc(val, bestValue) then
						bestValue = val
						currentTarget = player
					end
				end
			end
		end
	end
	return currentTarget
end
-- Aimbot and ESP Toggle Logic
local aiming = false
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Config.AimbotKey and Config.AimbotEnabled then
		aiming = true
	elseif input.KeyCode == Config.ESPKey then
		Config.ESPEnabled = not Config.ESPEnabled
		local ESPToggle = LocalPlayer.PlayerGui:FindFirstChild("ESP_Aimbot_Config") and LocalPlayer.PlayerGui.ESP_Aimbot_Config.MainFrame.ScrollingFrame:FindFirstChild("ESPToggle", true)
		if ESPToggle then
			ESPToggle.Text = "ESP: " .. (Config.ESPEnabled and "ON" or "OFF") .. " [" .. Config.ESPKey.Name .. "]"
		end
	elseif input.KeyCode == Config.FlyKey then
		if not Config.FlyForceDisabled then
			Config.FlyEnabled = not Config.FlyEnabled
			local FlyToggle = LocalPlayer.PlayerGui:FindFirstChild("ESP_Aimbot_Config") and LocalPlayer.PlayerGui.ESP_Aimbot_Config.MainFrame.ScrollingFrame:FindFirstChild("FlyToggle", true)
			if FlyToggle then
				FlyToggle.Text = "Fly: " .. (Config.FlyEnabled and "ON" or "OFF") .. " [" .. Config.FlyKey.Name .. "]"
			end
		end
	elseif input.KeyCode == Config.NoclipKey then
		if not Config.NoclipForceDisabled then
			Config.NoclipEnabled = not Config.NoclipEnabled
			local NoclipToggle = LocalPlayer.PlayerGui:FindFirstChild("ESP_Aimbot_Config") and LocalPlayer.PlayerGui.ESP_Aimbot_Config.MainFrame.ScrollingFrame:FindFirstChild("NoclipToggle", true)
			if NoclipToggle then
				NoclipToggle.Text = "Noclip: " .. (Config.NoclipEnabled and "ON" or "OFF") .. " [" .. Config.NoclipKey.Name .. "]"
			end
			if not Config.NoclipEnabled then
				local character = LocalPlayer.Character
				if character then
					for _, part in ipairs(character:GetDescendants()) do
						if part:IsA("BasePart") then
							part.CanCollide = true
						end
					end
				end
			end
		end
	elseif input.KeyCode == Config.SpeedHackKey then
		if not Config.SpeedHackForceDisabled then
			Config.SpeedHackEnabled = not Config.SpeedHackEnabled
			local SpeedHackToggle = LocalPlayer.PlayerGui:FindFirstChild("ESP_Aimbot_Config") and LocalPlayer.PlayerGui.ESP_Aimbot_Config.MainFrame.ScrollingFrame:FindFirstChild("SpeedHackToggle", true)
			if SpeedHackToggle then
				SpeedHackToggle.Text = "Speed Hack: " .. (Config.SpeedHackEnabled and "ON" or "OFF") .. " [" .. Config.SpeedHackKey.Name .. "]"
			end
			local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = Config.SpeedHackEnabled and Config.SpeedHackValue or 16
			end
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Config.AimbotKey then
		aiming = false
		currentTarget = nil
		lastTarget = nil
		currentBestPart = nil
		currentOffset = Vector3.new(0, 0, 0)
		lastUpdateTime = 0
	end
end)
-- Main Loop for Aimbot and Fly
RunService.RenderStepped:Connect(function(deltaTime)
	local character = LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if Config.AimbotEnabled and aiming then
		local target = getClosestPlayerInFOV()
		if target and target.Character then
			local bestPart, _ = getBestPartAndDist(target)
			if bestPart then
				if target ~= lastTarget or bestPart ~= currentBestPart then
					lastTarget = target
					currentBestPart = bestPart
					lastUpdateTime = tick()
					if Config.AimbotRandomOffset then
						currentOffset = Vector3.new(
							math.random(-100, 100)/100 * Config.AimbotOffsetMax,
							math.random(-100, 100)/100 * Config.AimbotOffsetMax,
							math.random(-100, 100)/100 * Config.AimbotOffsetMax
						)
					else
						currentOffset = Vector3.new(0, 0, 0)
					end
				else
					if Config.AimbotRandomOffset then
						local now = tick()
						if now - lastUpdateTime >= Config.AimbotOffsetUpdateInterval then
							currentOffset = Vector3.new(
								math.random(-100, 100)/100 * Config.AimbotOffsetMax,
								math.random(-100, 100)/100 * Config.AimbotOffsetMax,
								math.random(-100, 100)/100 * Config.AimbotOffsetMax
							)
							lastUpdateTime = now
						end
					end
				end
				local targetPos = bestPart.Position + currentOffset
				local cameraCFrame = Camera.CFrame
				local targetCFrame = CFrame.new(cameraCFrame.Position, targetPos)
				Camera.CFrame = cameraCFrame:Lerp(targetCFrame, Config.AimbotSpeed)
			end
		end
	end
	-- Fly Logic
	if hrp and Config.FlyEnabled and not Config.FlyForceDisabled then
		if not hrp:FindFirstChild("FlyBV") then
			local bv = Instance.new("BodyVelocity")
			bv.Name = "FlyBV"
			bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
			bv.Velocity = Vector3.new(0, 0, 0)
			bv.Parent = hrp
		end
		local moveDir = Vector3.new(0, 0, 0)
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + Camera.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - Camera.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - Camera.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + Camera.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0, 1, 0) end
		if moveDir.Magnitude > 0 then
			moveDir = moveDir.Unit
		end
		hrp.FlyBV.Velocity = moveDir * Config.FlySpeed
		if humanoid then
			humanoid.PlatformStand = true
		end
	else
		if hrp and hrp:FindFirstChild("FlyBV") then
			hrp.FlyBV:Destroy()
		end
		if humanoid then
			humanoid.PlatformStand = false
		end
	end
	-- Speed Hack Logic (applied every frame if enabled)
	if humanoid and Config.SpeedHackEnabled and not Config.SpeedHackForceDisabled then
		humanoid.WalkSpeed = Config.SpeedHackValue
	end
	updateFOVCircle()
end)
-- Noclip Loop
RunService.Heartbeat:Connect(function()
	local character = LocalPlayer.Character
	if Config.NoclipEnabled and not Config.NoclipForceDisabled and character then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and part.CanCollide then
				part.CanCollide = false
			end
		end
	end
end)
-- ESP Update Loop
spawn(function()
	while true do
		if Config.ESPEnabled then
			for _, player in ipairs(Players:GetPlayers()) do
				createESP(player)
			end
		else
			for player, cache in pairs(playerCache) do
				if cache.highlight then
					cache.highlight:Destroy()
				end
				if cache.billboard then
					cache.billboard:Destroy()
				end
				playerCache[player] = nil
			end
		end
		wait(1)
	end
end)
-- Player Events
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		wait(0.5)
		createESP(player)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if humanoid then
			humanoid.Died:Connect(function()
				local cache = playerCache[player]
				if cache then
					if cache.highlight then
						cache.highlight:Destroy()
						cache.highlight = nil
					end
					if cache.billboard then
						cache.billboard:Destroy()
						cache.billboard = nil
					end
					cache.character = nil
				end
				if player == currentTarget then
					currentTarget = nil
				end
			end)
		end
	end)
	player:GetPropertyChangedSignal("Team"):Connect(function()
		if player.Character then
			createESP(player)
		end
	end)
end)
Players.PlayerRemoving:Connect(function(player)
	local cache = playerCache[player]
	if cache then
		if cache.highlight then
			cache.highlight:Destroy()
		end
		if cache.billboard then
			cache.billboard:Destroy()
		end
		playerCache[player] = nil
	end
	if player == currentTarget then
		currentTarget = nil
	end
end)
-- Initialize
local function initialize()
	local success, errorMsg = pcall(function()
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				createESP(player)
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid.Died:Connect(function()
						local cache = playerCache[player]
						if cache then
							if cache.highlight then
								cache.highlight:Destroy()
								cache.highlight = nil
							end
							if cache.billboard then
								cache.billboard:Destroy()
								cache.billboard = nil
							end
							cache.character = nil
						end
						if player == currentTarget then
							currentTarget = nil
						end
					end)
				end
			end
		end
		
		createGUI()
		print("GUI Created")
		createFOVCircle()
		print("FOV Circle Created...")
		print("Initialization completed")
	end)
	if not success then
		warn("Initialization failed, error detected: " .. tostring(errorMsg))
	end
end
initialize()
