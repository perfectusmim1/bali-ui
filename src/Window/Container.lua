--[[
	Bali UI · Window/Container
	Attaches all element factory methods and common aliases onto any container
	(Section, Accordion, Tab, SubTab), providing unified ctx wiring.
]]

local Static = require("Elements/Static")
local Button = require("Elements/Button")
local Toggle = require("Elements/Toggle")
local Slider = require("Elements/Slider")
local Input = require("Elements/Input")
local Segmented = require("Elements/Segmented")
local Dropdown = require("Elements/Dropdown")
local Keybind = require("Elements/Keybind")
local ColorPicker = require("Elements/ColorPicker")
local Analytics = require("Elements/Analytics")
local Accordion = require("Elements/Accordion")

local Container = {}

local function resolveCtor(module, exportKey)
	if type(module) == "table" then
		if type(module.new) == "function" then
			return module.new
		end
		local nested = exportKey and module[exportKey]
		if type(nested) == "table" and type(nested.new) == "function" then
			return nested.new
		end
	elseif type(module) == "function" then
		return module
	end
	error("[Bali] Missing element constructor for " .. tostring(exportKey))
end

local FACTORIES = {
	{ Methods = { "AddLabel", "Label" }, Ctor = resolveCtor(Static.Label, "Label") },
	{ Methods = { "AddParagraph", "Paragraph" }, Ctor = resolveCtor(Static.Paragraph, "Paragraph") },
	{ Methods = { "AddDivider", "Divider" }, Ctor = resolveCtor(Static.Divider, "Divider") },
	{ Methods = { "AddHeader", "Header" }, Ctor = resolveCtor(Static.Header, "Header") },
	{ Methods = { "AddCodeBlock", "CodeBlock" }, Ctor = resolveCtor(Static.CodeBlock, "CodeBlock") },
	{ Methods = { "AddImage", "Image" }, Ctor = resolveCtor(Static.Image, "Image") },
	{ Methods = { "AddProfileCard", "ProfileCard" }, Ctor = resolveCtor(Static.ProfileCard, "ProfileCard") },

	{ Methods = { "AddButton", "Button" }, Ctor = resolveCtor(Button.Button, "Button") },
	{ Methods = { "AddButtonGroup", "ButtonGroup" }, Ctor = resolveCtor(Button.ButtonGroup, "ButtonGroup") },

	{ Methods = { "AddToggle", "Toggle" }, Ctor = resolveCtor(Toggle.Toggle, "Toggle") },
	{ Methods = { "AddCheckbox", "Checkbox" }, Ctor = resolveCtor(Toggle.Checkbox, "Checkbox") },

	{ Methods = { "AddSlider", "Slider" }, Ctor = resolveCtor(Slider.Slider, "Slider") },
	{ Methods = { "AddRangeSlider", "RangeSlider" }, Ctor = resolveCtor(Slider.RangeSlider, "RangeSlider") },
	{ Methods = { "AddStepper", "Stepper" }, Ctor = resolveCtor(Slider.Stepper, "Stepper") },

	{ Methods = { "AddInput", "Input", "AddTextBox" }, Ctor = resolveCtor(Input, "Input") },
	{ Methods = { "AddSegmented", "Segmented" }, Ctor = resolveCtor(Segmented, "Segmented") },
	{ Methods = { "AddDropdown", "Dropdown" }, Ctor = resolveCtor(Dropdown, "Dropdown") },
	{ Methods = { "AddKeybind", "Keybind" }, Ctor = resolveCtor(Keybind, "Keybind") },
	{ Methods = { "AddColorPicker", "ColorPicker" }, Ctor = resolveCtor(ColorPicker, "ColorPicker") },

	{ Methods = { "AddStatCard", "StatCard" }, Ctor = resolveCtor(Analytics.StatCard, "StatCard") },
	{ Methods = { "AddChart", "Chart" }, Ctor = resolveCtor(Analytics.Chart, "Chart") },
	{ Methods = { "AddProgressBar", "ProgressBar" }, Ctor = resolveCtor(Analytics.ProgressBar, "ProgressBar") },
	{ Methods = { "AddTable", "Table" }, Ctor = resolveCtor(Analytics.Table, "Table") },
	{ Methods = { "AddCardGrid", "CardGrid" }, Ctor = resolveCtor(Analytics.CardGrid, "CardGrid") },

	{ Methods = { "AddAccordion", "Accordion" }, Ctor = resolveCtor(Accordion, "Accordion") },
}

local function normalizeOptions(options, extra)
	if type(options) == "string" and type(extra) == "function" then
		return { Title = options, Callback = extra }
	end
	return options
end

function Container.Attach(target, parentFrame, tab, section, window, subTab)
	assert(type(target) == "table", "[Bali] Container.Attach expects a target table")
	assert(typeof(parentFrame) == "Instance", "[Bali] Container.Attach expects a parent Instance")

	local ctx = {
		Window = window,
		Tab = tab,
		SubTab = subTab,
		Section = section,
		PopupLayer = window and window.PopupLayer or nil,
		DialogLayer = window and window.DialogLayer or nil,
		Maid = target.Maid
			or (section and section.Maid)
			or (subTab and subTab.Maid)
			or (tab and tab.Maid)
			or (window and window.Maid),
	}

	function ctx.RegisterElement(record)
		if type(record) ~= "table" then
			return nil
		end

		local elem = record.Element or record
		local entry = record
		if not record.Element then
			entry = {
				Type = elem.Type or "Element",
				Title = elem.Title,
				Desc = elem.Desc or elem.Description,
				Flag = elem.Flag,
				Tab = tab,
				SubTab = subTab,
				Section = section,
				Element = elem,
			}
		else
			entry.Tab = entry.Tab or tab
			entry.SubTab = entry.SubTab or subTab
			entry.Section = entry.Section or section
			entry.Flag = entry.Flag or (elem and elem.Flag)
		end

		if window then
			if type(window._elements) == "table" then
				table.insert(window._elements, entry)
			end
			local flag = entry.Flag
			if flag ~= nil and flag ~= "" then
				if type(window._registry) == "table" then
					window._registry[flag] = elem
				end
				if type(window.Flags) == "table" and window.Flags ~= window._registry then
					window.Flags[flag] = elem
				end
			end

			if elem and type(elem.Maid) == "table" and type(elem.Maid.Give) == "function" then
				elem.Maid:Give(function()
					if type(window._elements) == "table" then
						local index = table.find(window._elements, entry)
						if index then
							table.remove(window._elements, index)
						end
					end
					if flag ~= nil and flag ~= "" then
						if type(window._registry) == "table" and window._registry[flag] == elem then
							window._registry[flag] = nil
						end
						if type(window.Flags) == "table" and window.Flags[flag] == elem then
							window.Flags[flag] = nil
						end
					end
				end)
			end
		end

		return entry
	end

	function ctx.OpenPopup(id, frame, anchorGui, onClose)
		if window and type(window.OpenPopup) == "function" then
			return window:OpenPopup(id, frame, anchorGui, onClose)
		end
		return nil
	end

	function ctx.ClosePopup(id)
		if window and type(window.ClosePopup) == "function" then
			window:ClosePopup(id)
		end
	end

	function ctx.AttachContainer(subTarget, subParent, subTabArg, subSectionArg, subWindowArg)
		return Container.Attach(
			subTarget,
			subParent,
			subTabArg or tab,
			subSectionArg or section,
			subWindowArg or window,
			subTab
		)
	end

	local nextOrder = 0

	for _, factory in ipairs(FACTORIES) do
		local ctor = factory.Ctor
		local function addElement(self, options, extra)
			if type(self._beforeAdd) == "function" then
				self:_beforeAdd()
			end
			local resolved = normalizeOptions(options, extra)
			local element = ctor(parentFrame, resolved, ctx)
			if type(element) == "table" and typeof(element.Frame) == "Instance" and element.Frame.LayoutOrder == 0 then
				nextOrder += 1
				element.Frame.LayoutOrder = nextOrder
			end
			return element
		end

		for _, methodName in ipairs(factory.Methods) do
			if target[methodName] == nil then
				target[methodName] = addElement
			end
		end
	end

	target._ctx = ctx
	return target
end

return Container
