--[[
	Bali UI · Full Feature Showcase
	Demonstrates every Core system, Window capability, and UI element in a cohesive
	obsidian analytics workspace inspired by modern telemetry dashboards.
]]

local Bali = require("Bali")

-- Safely inspect LocalPlayer for avatar + welcome profile banner
local playerName = "Architect"
local playerUserId = 1
pcall(function()
	local lp = Bali.Services.Players.LocalPlayer
	if lp then
		playerName = (lp.DisplayName ~= "" and lp.DisplayName) or lp.Name
		playerUserId = lp.UserId
	end
end)

-- Pre-window boot toast (automatically migrates once CreateWindow mounts)
Bali:Notify({
	Title = "Initializing Bali",
	Content = "Mounting obsidian glass workspace...",
	Type = "Accent",
	Duration = 2.5,
})

local window = Bali:CreateWindow({
	Title = "Bali Suite",
	Subtitle = "v" .. Bali.Version,
	Icon = "sparkles",
	ShowUser = true,
	Size = UDim2.fromOffset(860, 570),
	ToggleKey = Enum.KeyCode.RightShift,
	Watermark = {
		Enabled = true,
		Title = "Bali Suite",
		Text = "Analytics Workspace",
	},
	KeybindList = {
		Enabled = true,
		Mode = "ActiveOnly",
	},
	Blur = true,
	BlurIntensity = 12,
	ConfigFolder = "BaliShowcase",
})

window:Notify({
	Title = "Bali Suite Ready",
	Content = "Press RightShift to toggle UI, or Ctrl+K to open Command Palette.",
	Type = "Success",
	Duration = 4.5,
})

-- Shared lifetime guard for background telemetry loop
local alive = true
local streamEnabled = false
window.Maid:Give(function()
	alive = false
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- Category: Overview
-- ══════════════════════════════════════════════════════════════════════════════

local dashboardTab = window:AddTab({
	Title = "Dashboard",
	Icon = "dashboard",
	Category = "Overview",
	Badge = "Live",
})

-- ─── Snapshot Dataset ────────────────────────────────────────────────────────
local snapshots = {
	mon = {
		Title = "Monday",
		Portfolio = 142800,
		PortfolioDelta = 4.20,
		Throughput = 71.2,
		ThroughputDelta = 2.85,
		ChartMetric = "94.1%",
		Allocation = 61.0,
		AllocationBadge = "7.40% APR",
		AllocationSub = "$87,108 / $142,800",
		Utilization = 54,
		UtilSub = "21 / 38 Nodes",
		Points = { 58, 63, 60, 68, 72, 70, 76 },
		Labels = { "08h", "10h", "12h", "14h", "16h", "18h", "20h" },
	},
	tue = {
		Title = "Tuesday",
		Portfolio = 168450,
		PortfolioDelta = 6.14,
		Throughput = 79.8,
		ThroughputDelta = 3.90,
		ChartMetric = "96.7%",
		Allocation = 68.5,
		AllocationBadge = "8.12% APR",
		AllocationSub = "$115,388 / $168,450",
		Utilization = 59,
		UtilSub = "23 / 38 Nodes",
		Points = { 62, 69, 73, 71, 78, 82, 84 },
		Labels = { "08h", "10h", "12h", "14h", "16h", "18h", "20h" },
	},
	wed = {
		Title = "Wednesday",
		Portfolio = 194280,
		PortfolioDelta = 8.68,
		Throughput = 86.4,
		ThroughputDelta = 4.25,
		ChartMetric = "98.4%",
		Allocation = 74.5,
		AllocationBadge = "8.68% APR",
		AllocationSub = "$144,738 / $194,280",
		Utilization = 62,
		UtilSub = "24 / 38 Nodes",
		Points = { 68, 74, 79, 77, 85, 91, 95 },
		Labels = { "08h", "10h", "12h", "14h", "16h", "18h", "20h" },
	},
	thu = {
		Title = "Thursday",
		Portfolio = 211040,
		PortfolioDelta = 9.42,
		Throughput = 92.6,
		ThroughputDelta = 5.60,
		ChartMetric = "99.1%",
		Allocation = 82.0,
		AllocationBadge = "9.42% APR",
		AllocationSub = "$173,052 / $211,040",
		Utilization = 71,
		UtilSub = "27 / 38 Nodes",
		Points = { 74, 79, 86, 88, 92, 96, 99 },
		Labels = { "08h", "10h", "12h", "14h", "16h", "18h", "20h" },
	},
}

local activeDayId = "wed"
local activeChartMode = "Line"

-- ─── Hero Welcome & Day Selector (Full Width) ────────────────────────────────
local heroSection = dashboardTab:AddSection({
	Title = "Executive Overview",
	Subtitle = "Real-time workspace telemetry, active yield, and cluster balance.",
	Icon = "sparkles",
	Side = "Full",
	Collapsible = false,
})

local profileCard
local revenueCard
local latencyCard
local lineChart
local barChart
local allocBar
local utilBar
local telemetryTable

local function makeBaseRows()
	return {
		{
			Icon = "server",
			Node = "us-east-alpha",
			Region = "Virginia",
			Latency = "12 ms",
			Status = { Text = "Optimal", Color = "Success", Badge = true },
		},
		{
			Icon = "server",
			Node = "eu-central-core",
			Region = "Frankfurt",
			Latency = "24 ms",
			Status = { Text = "Optimal", Color = "Success", Badge = true },
		},
		{
			Icon = "database",
			Node = "ap-tokyo-stream",
			Region = "Tokyo",
			Latency = "48 ms",
			Status = { Text = "Elevated", Color = "Warning", Badge = true },
		},
		{
			Icon = "cloud",
			Node = "us-west-edge",
			Region = "Oregon",
			Latency = "18 ms",
			Status = { Text = "Optimal", Color = "Success", Badge = true },
		},
		{
			Icon = "cpu",
			Node = "sa-east-vault",
			Region = "Sao Paulo",
			Latency = "--",
			Status = { Text = "Standby", Color = "Muted", Badge = true },
		},
	}
end

local currentRows = makeBaseRows()

local function applyDaySnapshot(dayId)
	local snap = snapshots[dayId]
	if not snap then
		return
	end
	activeDayId = dayId

	if revenueCard then
		revenueCard:SetValue(snap.Portfolio, snap.PortfolioDelta)
		revenueCard:SetPoints(snap.Points)
	end
	if latencyCard then
		latencyCard:SetValue(snap.Throughput, snap.ThroughputDelta)
		latencyCard:SetPoints(snap.Points)
	end
	if lineChart then
		lineChart:SetPoints(snap.Points, snap.Labels)
	end
	if barChart then
		barChart:SetPoints(snap.Points, snap.Labels)
	end
	if allocBar then
		allocBar:Set(snap.Allocation, 100, snap.AllocationBadge)
	end
	if utilBar then
		utilBar:Set(snap.Utilization, 100, snap.Utilization >= 75 and "Heavy" or "Nominal")
	end
	if profileCard then
		profileCard:SetStatus("Snapshot: " .. snap.Title, "Success")
	end
end

profileCard = heroSection:AddProfileCard({
	UserId = playerUserId,
	Title = playerName .. " · Bali Workspace",
	Subtitle = "SEDA Analytics Cluster · Build v" .. Bali.Version,
	Status = "Snapshot: Wednesday",
	StatusColor = "Success",
	Button = {
		Title = "Sync Snapshot",
		Icon = "refresh",
		Callback = function()
			applyDaySnapshot(activeDayId)
			if telemetryTable then
				telemetryTable:SetRows(currentRows)
			end
			window:Notify({
				Title = "Telemetry Synced",
				Content = "Refreshed " .. snapshots[activeDayId].Title .. " metrics and endpoint table.",
				Type = "Info",
				Duration = 2.5,
			})
		end,
	},
})

heroSection:AddCardGrid({
	Default = "wed",
	Cards = {
		{
			Id = "mon",
			Title = "Monday",
			Icon = "calendar",
			Metrics = {
				{ Label = "Volume", Value = "$142.8K" },
				{ Label = "Delta", Value = "+4.20%" },
			},
		},
		{
			Id = "tue",
			Title = "Tuesday",
			Icon = "calendar",
			Metrics = {
				{ Label = "Volume", Value = "$168.4K" },
				{ Label = "Delta", Value = "+6.14%" },
			},
		},
		{
			Id = "wed",
			Title = "Wednesday",
			Icon = "calendar",
			Active = true,
			Metrics = {
				{ Label = "Volume", Value = "$194.2K" },
				{ Label = "Delta", Value = "+8.68%" },
			},
		},
		{
			Id = "thu",
			Title = "Thursday",
			Icon = "calendar",
			Metrics = {
				{ Label = "Volume", Value = "$211.0K" },
				{ Label = "Delta", Value = "+9.42%" },
			},
		},
	},
	Callback = function(id)
		applyDaySnapshot(id)
	end,
})

-- ─── Performance Analytics (Left Column) ─────────────────────────────────────
local perfSection = dashboardTab:AddSection({
	Title = "Performance Analytics",
	Subtitle = "Toggle between smooth spline curves and columnar distribution.",
	Icon = "trending-up",
	Side = "Left",
})

revenueCard = perfSection:AddStatCard({
	Title = "Net Portfolio Value",
	Value = snapshots.wed.Portfolio,
	Prefix = "$",
	Decimals = 0,
	Delta = snapshots.wed.PortfolioDelta,
	Icon = "wallet",
	Color = "Accent",
	Glow = true,
	Points = snapshots.wed.Points,
})

perfSection:AddSegmented({
	Title = "Visualization Mode",
	Values = {
		{ Title = "Line", Icon = "chart-line", Value = "Line" },
		{ Title = "Bar", Icon = "chart-bar", Value = "Bar" },
	},
	Default = "Line",
	Callback = function(mode)
		activeChartMode = mode
		if lineChart then
			lineChart:SetVisible(mode == "Line")
		end
		if barChart then
			barChart:SetVisible(mode == "Bar")
		end
	end,
})

lineChart = perfSection:AddChart({
	Title = "Hourly Execution Rate",
	Subtitle = "Cluster throughput index",
	Value = snapshots.wed.ChartMetric,
	Mode = "Line",
	Points = snapshots.wed.Points,
})
lineChart:SetPoints(snapshots.wed.Points, snapshots.wed.Labels)

barChart = perfSection:AddChart({
	Title = "Hourly Execution Rate",
	Subtitle = "Cluster throughput index",
	Value = snapshots.wed.ChartMetric,
	Mode = "Bar",
	Points = snapshots.wed.Points,
})
barChart:SetPoints(snapshots.wed.Points, snapshots.wed.Labels)
barChart:SetVisible(false)

-- ─── Allocation & Capacity (Right Column) ────────────────────────────────────
local healthSection = dashboardTab:AddSection({
	Title = "Allocation & Capacity",
	Subtitle = "Live throughput telemetry, APR bounds, and simulation.",
	Icon = "gauge",
	Side = "Right",
})

latencyCard = healthSection:AddStatCard({
	Title = "Active Throughput",
	Value = snapshots.wed.Throughput,
	Suffix = " k/s",
	Decimals = 1,
	Delta = snapshots.wed.ThroughputDelta,
	Icon = "zap",
	Color = "Success",
	Points = snapshots.wed.Points,
})

allocBar = healthSection:AddProgressBar({
	Title = "Total Allocation",
	Value = snapshots.wed.Allocation,
	Max = 100,
	Suffix = "%",
	Badge = snapshots.wed.AllocationBadge,
	SecondaryLabel = snapshots.wed.AllocationSub,
	Gradient = true,
	Color = "Accent",
})

utilBar = healthSection:AddProgressBar({
	Title = "Compute Utilization",
	Value = snapshots.wed.Utilization,
	Max = 100,
	Suffix = "%",
	Badge = "Nominal",
	SecondaryLabel = snapshots.wed.UtilSub,
	Color = "Success",
})

local tickCounter = 0
local function pushTelemetryTick()
	tickCounter += 1
	local nextPoint = math.clamp(78 + ((tickCounter * 17) % 21), 50, 99)
	local label = string.format("T+%02d", tickCounter)
	if lineChart then
		lineChart:Push(nextPoint, label)
	end
	if barChart then
		barChart:Push(nextPoint, label)
	end

	local nextPortfolio = snapshots[activeDayId].Portfolio + (tickCounter * 480)
	local nextThroughput = math.floor((82 + (nextPoint - 70) * 0.6) * 10) / 10
	if revenueCard then
		revenueCard:SetValue(nextPortfolio, snapshots[activeDayId].PortfolioDelta + 0.35)
	end
	if latencyCard then
		latencyCard:SetValue(nextThroughput, 5.10)
	end

	local nextAlloc = math.min(98, snapshots[activeDayId].Allocation + ((tickCounter % 6) * 2.5))
	if allocBar then
		allocBar:Set(nextAlloc, 100, string.format("%.2f%% APR", 8.5 + (nextAlloc * 0.012)))
	end

	if currentRows[1] then
		currentRows[1].Latency = tostring(10 + (tickCounter % 7)) .. " ms"
		if telemetryTable then
			telemetryTable:SetRows(currentRows)
		end
	end
end

healthSection:AddToggle({
	Title = "Live Telemetry Stream",
	Description = "Pushes simulated ticks every 1.5s (auto-stops on unload).",
	Icon = "activity",
	Default = false,
	Flag = "Dashboard_LiveStream",
	Callback = function(state)
		streamEnabled = state == true
	end,
})

healthSection:AddButtonGroup({
	Buttons = {
		{
			Title = "Push Tick",
			Icon = "zap",
			Variant = "Primary",
			Callback = function()
				pushTelemetryTick()
				window:Notify({
					Title = "Telemetry Updated",
					Content = string.format("Pushed tick #%d to %s chart and metrics.", tickCounter, activeChartMode),
					Type = "Success",
					Duration = 2.2,
				})
			end,
		},
		{
			Title = "Reset Baseline",
			Icon = "rotate-cw",
			Variant = "Default",
			Callback = function()
				tickCounter = 0
				currentRows = makeBaseRows()
				applyDaySnapshot(activeDayId)
				if telemetryTable then
					telemetryTable:SetRows(currentRows)
				end
				window:Notify({
					Title = "Baseline Restored",
					Content = "Metrics and table reset to " .. snapshots[activeDayId].Title .. " baseline.",
					Type = "Info",
					Duration = 2.2,
				})
			end,
		},
	},
})

task.spawn(function()
	while alive and not window._destroyed do
		task.wait(1.5)
		if not alive or window._destroyed then
			break
		end
		if streamEnabled then
			pushTelemetryTick()
		end
	end
end)

-- ─── Interactive Telemetry Table (Full Width) ────────────────────────────────
local matrixSection = dashboardTab:AddSection({
	Title = "Node & Endpoint Matrix",
	Subtitle = "Searchable telemetry grid with multi-selection, status pills, and row actions.",
	Icon = "database",
	Side = "Full",
})

telemetryTable = matrixSection:AddTable({
	Title = "Cluster Endpoints",
	Columns = {
		{ Key = "Node", Title = "Endpoint", Width = 0.34 },
		{ Key = "Region", Title = "Region", Width = 0.24 },
		{ Key = "Latency", Title = "Latency", Width = 0.18, Align = "Right" },
		{ Key = "Status", Title = "Health", Width = 0.24 },
	},
	Rows = currentRows,
	Selectable = true,
	Searchable = true,
	MaxHeight = 230,
	OnRowClick = function(row, idx)
		window:Notify({
			Title = row.Node,
			Content = string.format("Row #%d · Region: %s · Latency: %s", idx, tostring(row.Region), tostring(row.Latency)),
			Type = "Info",
			Duration = 2.5,
		})
	end,
	Action = {
		Title = "Inspect",
		Icon = "external",
		Callback = function(row, idx)
			local healthText = type(row.Status) == "table" and row.Status.Text or tostring(row.Status)
			window:Dialog({
				Title = "Endpoint Diagnostics",
				Content = string.format(
					"Node #%d: %s\nRegion: %s\nObserved Latency: %s\nHealth State: %s",
					idx,
					tostring(row.Node),
					tostring(row.Region),
					tostring(row.Latency),
					tostring(healthText)
				),
				Icon = "server",
				Buttons = {
					{ Title = "Close", Variant = "Primary" },
				},
			})
		end,
	},
})

local extraNodeIdx = 0
matrixSection:AddButtonGroup({
	Buttons = {
		{
			Title = "Add Edge Node",
			Icon = "plus",
			Variant = "Primary",
			Callback = function()
				extraNodeIdx += 1
				table.insert(currentRows, {
					Icon = "globe",
					Node = string.format("eu-london-edge-%02d", extraNodeIdx),
					Region = "London",
					Latency = tostring(15 + (extraNodeIdx * 3) % 19) .. " ms",
					Status = { Text = "Optimal", Color = "Success", Badge = true },
				})
				telemetryTable:SetRows(currentRows)
			end,
		},
		{
			Title = "Inspect Selected",
			Icon = "list-checks",
			Variant = "Default",
			Callback = function()
				local selected = telemetryTable:GetSelected()
				local count = #selected
				window:Notify({
					Title = "Selection Summary",
					Content = count > 0 and string.format("%d endpoint(s) currently selected.", count)
						or "No rows selected. Use row checkboxes first.",
					Type = count > 0 and "Success" or "Warning",
					Duration = 2.8,
				})
			end,
		},
		{
			Title = "Cycle Latencies",
			Icon = "refresh",
			Variant = "Default",
			Callback = function()
				for i, row in ipairs(currentRows) do
					if i < #currentRows or row.Latency ~= "--" then
						local ms = 9 + ((i * 7 + tickCounter) % 34)
						row.Latency = tostring(ms) .. " ms"
						if ms > 32 then
							row.Status = { Text = "Elevated", Color = "Warning", Badge = true }
						else
							row.Status = { Text = "Optimal", Color = "Success", Badge = true }
						end
					end
				end
				telemetryTable:SetRows(currentRows)
			end,
		},
	},
})

-- ══════════════════════════════════════════════════════════════════════════════
-- Category: Overview -> Tab: Controls (with 3 SubTabs)
-- ══════════════════════════════════════════════════════════════════════════════

local controlsTab = window:AddTab({
	Title = "Controls",
	Icon = "sliders",
	Category = "Overview",
})

local interactiveSub = controlsTab:AddSubTab({ Title = "Interactive", Icon = "zap" })
local pickersSub = controlsTab:AddSubTab({ Title = "Inputs & Pickers", Icon = "palette" })
local layoutSub = controlsTab:AddSubTab({ Title = "Layout & Rich", Icon = "layers" })

-- ─── SubTab 1: Interactive ───────────────────────────────────────────────────
local switchesSection = interactiveSub:AddSection({
	Title = "Switches & Actions",
	Subtitle = "Toggles with inline keybinds, checkboxes, and action variants.",
	Icon = "toggle",
	Side = "Left",
})

switchesSection:AddToggle({
	Title = "Smart Automation",
	Description = "Toggle auto-balancing with an inline bound shortcut.",
	Icon = "zap",
	Default = true,
	Keybind = Enum.KeyCode.F,
	Flag = "Controls_SmartAutomation",
	Tooltip = "Click the hotkey badge on the right to rebind.",
	Callback = function(state)
		Bali.Watermark.SetText(state and "Automation On" or "Automation Idle")
	end,
})

switchesSection:AddCheckbox({
	Title = "Strict Telemetry Validation",
	Description = "Validate checksums before writing local config snapshots.",
	Default = true,
	Flag = "Controls_StrictValidation",
})

switchesSection:AddButton({
	Title = "Probe Latency",
	Description = "Standard button with arrow indicator and status badge.",
	Icon = "wifi",
	Variant = "Default",
	ShowArrow = true,
	Badge = "12ms",
	Callback = function()
		window:Notify({
			Title = "Probe Complete",
			Content = "Edge cluster responded in 12 ms.",
			Type = "Info",
			Duration = 2.5,
		})
	end,
})

switchesSection:AddButton({
	Title = "Deploy Workspace",
	Description = "Accent-filled primary call to action.",
	Icon = "rocket",
	Variant = "Primary",
	Callback = function()
		window:Notify({
			Title = "Deployment Queued",
			Content = "Broadcast updated configuration to all nodes.",
			Type = "Success",
			Duration = 3,
		})
	end,
})

switchesSection:AddButton({
	Title = "Purge Local Cache",
	Description = "Requires second click confirmation before executing.",
	Icon = "trash",
	Variant = "Danger",
	Confirm = "Confirm purge?",
	Callback = function()
		window:Notify({
			Title = "Cache Purged",
			Content = "Temporary telemetry buffers cleared.",
			Type = "Warning",
			Duration = 3,
		})
	end,
})

switchesSection:AddButtonGroup({
	Title = "Quick Operations",
	Buttons = {
		{
			Title = "Verify",
			Icon = "shield-check",
			Variant = "Primary",
			Tooltip = "Verify config integrity",
			Callback = function()
				window:Notify({ Title = "Verified", Content = "All flags passed schema check.", Type = "Success" })
			end,
		},
		{
			Title = "Snapshot",
			Icon = "save",
			Variant = "Default",
			Callback = function()
				window:Notify({ Title = "Snapshot", Content = "Memory snapshot captured.", Type = "Info" })
			end,
		},
		{
			Title = "Reset",
			Icon = "undo",
			Variant = "Danger",
			Callback = function()
				window:Notify({ Title = "Reset", Content = "Simulation parameters restored.", Type = "Info" })
			end,
		},
	},
})

local rangeSection = interactiveSub:AddSection({
	Title = "Sliders & Lock State",
	Subtitle = "Continuous sliders, dual-thumb ranges, steppers, and lock guards.",
	Icon = "sliders",
	Side = "Right",
})

rangeSection:AddSlider({
	Title = "Polling Frequency",
	Description = "Smooth scrub or click value badge to type exact number.",
	Icon = "gauge",
	Min = 10,
	Max = 240,
	Step = 5,
	Default = 120,
	Suffix = " Hz",
	Flag = "Controls_PollingHz",
})

rangeSection:AddRangeSlider({
	Title = "Target Latency Window",
	Description = "Dual-thumb lower and upper latency bounds.",
	Min = 5,
	Max = 200,
	Step = 5,
	MinGap = 15,
	Default = { Min = 20, Max = 85 },
	Suffix = " ms",
	Flag = "Controls_LatencyBand",
})

rangeSection:AddStepper({
	Title = "Worker Threads",
	Description = "Discrete increment / decrement stepper control.",
	Min = 1,
	Max = 16,
	Step = 1,
	Default = 4,
	Suffix = " threads",
	Flag = "Controls_WorkerThreads",
})

local lockedDemoSlider = rangeSection:AddSlider({
	Title = "Protected Gain Limit",
	Description = "Demonstrates element :Lock(reason) and :Unlock().",
	Min = 0,
	Max = 100,
	Step = 1,
	Default = 55,
	Suffix = "%",
	Flag = "Controls_ProtectedGain",
})
lockedDemoSlider:Lock("Locked by Policy")

rangeSection:AddToggle({
	Title = "Lock Protected Control",
	Description = "Toggle between locked overlay and unlocked interaction.",
	Icon = "lock",
	Default = true,
	Callback = function(isLocked)
		if isLocked then
			lockedDemoSlider:Lock("Locked by Policy")
		else
			lockedDemoSlider:Unlock()
		end
	end,
})

-- ─── SubTab 2: Inputs & Pickers ──────────────────────────────────────────────
local selectionSection = pickersSub:AddSection({
	Title = "Menus & Hotkeys",
	Subtitle = "Single/multi searchable dropdowns, segmented tabs, and keybinds.",
	Icon = "list",
	Side = "Left",
})

selectionSection:AddDropdown({
	Title = "Balancing Strategy",
	Description = "Single-select popover menu.",
	Values = { "Balanced", "Low Latency", "High Throughput", "Eco Saver" },
	Default = "Balanced",
	Flag = "Pickers_Strategy",
})

selectionSection:AddDropdown({
	Title = "Edge Clusters",
	Description = "Multi-select dropdown with live search filter.",
	Values = {
		"US-East (Virginia)",
		"US-West (Oregon)",
		"EU-Central (Frankfurt)",
		"EU-West (London)",
		"AP-Northeast (Tokyo)",
		"AP-Southeast (Singapore)",
	},
	Multi = true,
	Searchable = true,
	Default = { "US-East (Virginia)", "EU-Central (Frankfurt)" },
	Flag = "Pickers_Clusters",
})

selectionSection:AddSegmented({
	Title = "Sampling Window",
	Description = "Spring-animated segmented pill control.",
	Values = { "Adaptive", "Fixed", "Burst" },
	Default = "Adaptive",
	Flag = "Pickers_SamplingWindow",
})

selectionSection:AddKeybind({
	Title = "Capture Trigger",
	Description = "Supports Toggle, Hold, Always modes + Mouse inputs.",
	Default = Enum.KeyCode.G,
	Mode = "Toggle",
	AllowMouse = true,
	Flag = "Pickers_CaptureKey",
	Callback = function(active)
		window:Notify({
			Title = "Capture Keybind",
			Content = active and "Capture state toggled ON." or "Capture state toggled OFF.",
			Type = "Info",
			Duration = 2,
		})
	end,
})

local inputSection = pickersSub:AddSection({
	Title = "Inputs & Color Studio",
	Subtitle = "Text boxes, numeric filters, password masking, and HSV color picker.",
	Icon = "palette",
	Side = "Right",
})

inputSection:AddInput({
	Title = "Workspace Alias",
	Description = "Standard text box with quick clear button.",
	Icon = "pencil",
	Placeholder = "Enter workspace alias...",
	Default = "Production-Alpha",
	Clearable = true,
	Flag = "Pickers_Alias",
})

inputSection:AddInput({
	Title = "Gateway Port",
	Description = "Numeric & integer constrained input field.",
	BoxIcon = "hash",
	Placeholder = "8443",
	Default = "8443",
	Numeric = true,
	Integer = true,
	MaxLength = 5,
	Flag = "Pickers_Port",
})

inputSection:AddInput({
	Title = "Access Token",
	Description = "Password-masked input with reveal eye toggle.",
	BoxIcon = "key",
	Placeholder = "Paste secret token...",
	Default = "bali_live_9821a",
	Mask = true,
	Flag = "Pickers_Token",
})

inputSection:AddColorPicker({
	Title = "Highlight Swatch",
	Description = "HSV square, hue/alpha sliders, hex editor, presets, and rainbow.",
	Default = Color3.fromRGB(214, 64, 236),
	Transparency = 0.15,
	Presets = {
		Color3.fromRGB(214, 64, 236),
		Color3.fromRGB(59, 130, 246),
		Color3.fromRGB(45, 212, 191),
		Color3.fromRGB(52, 211, 153),
		Color3.fromRGB(251, 113, 133),
		Color3.fromRGB(251, 191, 36),
	},
	Flag = "Pickers_Swatch",
})

-- ─── SubTab 3: Layout & Rich ─────────────────────────────────────────────────
local editorialSection = layoutSub:AddSection({
	Title = "Typography & Accordion",
	Subtitle = "Headers, copyable labels, rich paragraphs, and nested containers.",
	Icon = "type",
	Side = "Left",
})

editorialSection:AddHeader({
	Title = "Design System",
	Icon = "sparkles",
	Badge = "Tokens",
	Uppercase = true,
})

editorialSection:AddLabel({
	Title = "Runtime Signature",
	Value = "Bali Core v" .. Bali.Version,
	Icon = "cpu",
	Badge = "Verified",
	BadgeColor = "Success",
	Copyable = true,
	CopyValue = "Bali-Core-v" .. Bali.Version,
})

editorialSection:AddParagraph({
	Title = "Obsidian Glass Architecture",
	Content = "Layers stack inside an isolated ZIndex hierarchy with directional glass strokes, radial corner blooms, live theme subscriptions, and Lucide vector sprite icons.",
	Icon = "info",
	AccentBar = true,
	Tags = { "Glassmorphism", "Lucide 48px", "Luau" },
})

editorialSection:AddDivider({
	Title = "Nested Container",
})

local diagAccordion = editorialSection:AddAccordion({
	Title = "Diagnostic Buffer Settings",
	Description = "Expandable container hosting nested controls.",
	Icon = "sliders",
	Expanded = true,
	Flag = "Layout_DiagAccordion",
})

diagAccordion:AddToggle({
	Title = "Frame Time Capture",
	Description = "Record frame deltas for profiler diagnostics.",
	Default = false,
	Flag = "Layout_FrameCapture",
})

diagAccordion:AddSlider({
	Title = "Ring Buffer Capacity",
	Min = 64,
	Max = 512,
	Step = 64,
	Default = 256,
	Suffix = " KB",
	Flag = "Layout_RingBuffer",
})

diagAccordion:AddButton({
	Title = "Flush Diagnostic Ring",
	Icon = "trash",
	Variant = "Default",
	Callback = function()
		window:Notify({
			Title = "Diagnostics",
			Content = "Diagnostic ring buffer flushed cleanly.",
			Type = "Info",
			Duration = 2.2,
		})
	end,
})

local mediaSection = layoutSub:AddSection({
	Title = "Code & Visual Assets",
	Subtitle = "Syntax-formatted code snippets and glassmorphic media frames.",
	Icon = "code",
	Side = "Right",
})

mediaSection:AddCodeBlock({
	Title = "Luau Quickstart",
	Code = [[local Bali = require("Bali")

local win = Bali:CreateWindow({
	Title = "Bali Suite",
	Theme = "Midnight",
	Blur = true,
})

local tab = win:AddTab({ Title = "Overview", Icon = "dashboard" })
local sec = tab:AddSection({ Title = "Controls" })
sec:AddToggle({ Title = "Enabled", Default = true })]],
	LineNumbers = true,
	MaxHeight = 190,
})

mediaSection:AddImage({
	Title = "Bundled Icon Atlas",
	Caption = "832x572 Lucide SDF/PNG sprite sheet loaded at runtime",
	Image = Bali.Assets.Get("Atlas") or "rbxassetid://0",
	Height = 148,
	ScaleType = Enum.ScaleType.Fit,
})

-- ══════════════════════════════════════════════════════════════════════════════
-- Category: System -> Notifications & Modals + Auto-Built Settings
-- ══════════════════════════════════════════════════════════════════════════════

local systemTab = window:AddTab({
	Title = "Notifications & Modals",
	Icon = "bell",
	Category = "System",
})

local toastsSection = systemTab:AddSection({
	Title = "Toast Notifications",
	Subtitle = "Stacking notifications with severity variants, actions, and error boundary.",
	Icon = "bell",
	Side = "Left",
})

toastsSection:AddButton({
	Title = "Info Notification",
	Icon = "info",
	Callback = function()
		Bali:Notify({
			Title = "Workspace Notice",
			Content = "Background metrics synchronized with local cluster.",
			Type = "Info",
			Duration = 3.5,
		})
	end,
})

toastsSection:AddButton({
	Title = "Success Notification",
	Icon = "circle-check",
	Callback = function()
		Bali:Notify({
			Title = "Build Validated",
			Content = "All modules passed luau-compile verification.",
			Type = "Success",
			Duration = 3.5,
		})
	end,
})

toastsSection:AddButton({
	Title = "Warning Notification",
	Icon = "triangle-alert",
	Callback = function()
		Bali:Notify({
			Title = "Memory Threshold",
			Content = "Ring buffer utilization exceeded 80% ceiling.",
			Type = "Warning",
			Duration = 4,
		})
	end,
})

toastsSection:AddButton({
	Title = "Error Notification",
	Icon = "circle-x",
	Callback = function()
		Bali:Notify({
			Title = "Socket Interrupted",
			Content = "Secondary relay timed out after 3000ms.",
			Type = "Error",
			Duration = 4,
		})
	end,
})

toastsSection:AddButton({
	Title = "Interactive Action Toast",
	Icon = "sparkles",
	Variant = "Primary",
	Callback = function()
		Bali:Notify({
			Title = "Update Package Ready",
			Content = "Bali Suite v1.0.1 includes improved blur transitions.",
			Type = "Accent",
			Duration = 8,
			Actions = {
				{
					Title = "Apply Now",
					Primary = true,
					Callback = function()
						Bali:Notify({
							Title = "Updated",
							Content = "Applied update cleanly without restart.",
							Type = "Success",
							Duration = 2.5,
						})
					end,
				},
				{
					Title = "Dismiss",
					Dismiss = true,
				},
			},
		})
	end,
})

toastsSection:AddButton({
	Title = "Test Error Boundary",
	Description = "Triggers Util.SafeCall failure to preview automatic error toasts.",
	Icon = "bug",
	Variant = "Danger",
	Callback = function()
		Bali.Util.SafeCall(function()
			error("Simulated callback exception caught by Bali ErrorHandler")
		end)
	end,
})

local modalsSection = systemTab:AddSection({
	Title = "Modals, Loaders & Tools",
	Subtitle = "Centered glass dialogs, splash loaders, key gate, and Command Palette.",
	Icon = "command",
	Side = "Right",
})

modalsSection:AddButton({
	Title = "Confirmation Dialog",
	Icon = "triangle-alert",
	Callback = function()
		window:Dialog({
			Title = "Reset Telemetry State?",
			Content = "This clears temporary session counters while preserving saved profiles.",
			Icon = "triangle-alert",
			Buttons = {
				{ Title = "Cancel", Variant = "Default" },
				{
					Title = "Reset State",
					Variant = "Danger",
					Callback = function()
						tickCounter = 0
						applyDaySnapshot("wed")
						window:Notify({
							Title = "State Cleared",
							Content = "Session counters restored to initial state.",
							Type = "Success",
						})
					end,
				},
			},
		})
	end,
})

modalsSection:AddButton({
	Title = "Input Dialog",
	Icon = "pencil",
	Callback = function()
		window:Dialog({
			Title = "Rename Active Cluster",
			Content = "Provide a clean identifier for the telemetry watermark label.",
			Icon = "pencil",
			Input = {
				Label = "Cluster Label",
				Placeholder = "e.g. EU-Core-01",
				Default = "Analytics Workspace",
			},
			Buttons = {
				{ Title = "Cancel", Variant = "Default" },
				{
					Title = "Apply Name",
					Variant = "Primary",
					Callback = function(value)
						local clean = Bali.Util.Trim(value or "")
						if clean ~= "" then
							Bali.Watermark.SetText(clean)
							window:Notify({
								Title = "Watermark Updated",
								Content = "Cluster label set to '" .. clean .. "'.",
								Type = "Success",
							})
						end
					end,
				},
			},
		})
	end,
})

modalsSection:AddButton({
	Title = "Preview Loading Screen",
	Icon = "loader",
	Callback = function()
		Bali:LoadingScreen({
			Title = "Bali Suite",
			Subtitle = "Synchronizing glassmorphic telemetry...",
			Icon = "sparkles",
			Duration = 2.0,
			Steps = {
				"Loading vector atlas...",
				"Hydrating theme tokens...",
				"Binding spring transitions...",
				"Ready",
			},
			OnComplete = function()
				window:Notify({
					Title = "LoadingScreen Complete",
					Content = "Splash preloader finished smoothly.",
					Type = "Success",
					Duration = 2.5,
				})
			end,
		})
	end,
})

modalsSection:AddButton({
	Title = "Preview Key System",
	Icon = "key",
	Callback = function()
		Bali:KeySystem({
			Title = "Bali Access Gate",
			Subtitle = "Demo verification key: BALI-DEMO",
			Icon = "key",
			Key = "BALI-DEMO",
			Closable = true,
			OnSuccess = function(acceptedKey)
				window:Notify({
					Title = "Key Accepted",
					Content = "Verified key '" .. tostring(acceptedKey) .. "'.",
					Type = "Success",
				})
			end,
		})
	end,
})

modalsSection:AddButton({
	Title = "Open Command Palette",
	Description = "Also accessible anytime via Ctrl+K or the sidebar spotlight pill.",
	Icon = "search",
	Variant = "Primary",
	Tooltip = "Press Ctrl+K anywhere inside the workspace",
	Callback = function()
		Bali.CommandPalette.Open()
	end,
})

modalsSection:AddButton({
	Title = "Hover Tooltip Showcase",
	Description = "Hover over this row to display a viewport-clamped glass tooltip.",
	Icon = "circle-help",
	Tooltip = "Smart Tooltip: dynamically avoids viewport edges and follows hover delay.",
	Callback = function()
		window:Notify({
			Title = "Tooltip Tip",
			Content = "Tooltips also bind automatically to topbar action buttons.",
			Type = "Info",
			Duration = 2.5,
		})
	end,
})

-- Auto-built Settings tab (Appearance, HUD, Config Manager, Session Diagnostics)
window:BuildSettingsTab({
	Category = "System",
	Icon = "settings",
})
