# Lumina UI

Obsidian glassmorphic UI library for Roblox and Luau featuring live theme switching, radial glass accents, a bundled 164-icon Lucide sprite atlas, spring-driven motion, analytics visualization widgets, desktop and touch ergonomics, and zero-`loadstring` single-file distribution bundles.

## Features

- **Obsidian Glass Engine**: Layered depth (`Main`, `HUD`, `Popup`, `Dialog`, `Notification`), directional hairline `UIStroke` highlights, ambient radial blooms, and subtle noise grain.
- **7 Built-in Themes & Live Customization**: `Midnight`, `Ocean`, `Graphite`, `Aurora`, `Sunset`, `Emerald`, and `Light`, plus runtime accent color overrides, custom theme registration (`AddTheme`), and font family switching (`SetFont`).
- **164 Bundled Lucide Icons**: Self-contained sprite atlas (`src/Generated/AssetData.lua`) synced cleanly into asset storage with crisp glyph fallbacks when file APIs are restricted.
- **Rich Control Suite**: `Toggle` (with inline keybinds), `Checkbox`, `Button` (variants + double-click `Confirm`), `ButtonGroup`, `Slider`, `RangeSlider`, `Stepper`, `Input` (numeric/integer/password mask), `Segmented`, `Dropdown` (single, multi, searchable), `Keybind` (`Toggle`, `Hold`, `Always`, mouse support), `ColorPicker` (HSV wheel, alpha, hex, presets, rainbow), and nested `Accordion` containers.
- **Analytics & Data Widgets**: `StatCard` (animated numbers, deltas, sparklines), `Chart` (`Line` and `Bar` modes with live `:Push()`), `ProgressBar` (gradients and status badges), `Table` (search, multi-select checkboxes, badges, row click/action buttons), and `CardGrid`.
- **System HUD & Modals**: Stacking `Notification` toasts with actions & unread history popover, `CommandPalette` (`Ctrl+K`), draggable `Watermark`, live `KeybindList`, lighting `Blur`, `Tooltip`, centered `Dialog` modals (with optional input field), `LoadingScreen` splash, and `KeySystem` verification gate.
- **Persistence & Safety**: JSON `Config` save/load/auto-load/import/export via executor file APIs, automatic re-execution cleanup (`_LuminaInstance`), element `:Lock()`/`:Unlock()`, and a recursion-guarded `Util.ErrorHandler` surfacing callback failures as Error toasts.
- **Zero-`loadstring` Distribution**: `tools/bundle.mjs` produces single-file Luau bundles (`dist/Lumina.lua` and `dist/LuminaExample.lua`) compatible with both Roblox executors and Roblox Studio `ModuleScript` workflows.

## Architecture

```text
src/
├── Lumina.lua                 # Main library entry point, safe ScreenGui host, error boundary
├── Example.lua                # Full-feature interactive showcase
├── Generated/
│   └── AssetData.lua          # Embedded 832x572 Lucide sprite atlas & textures
├── Core/
│   ├── Assets.lua             # Runtime asset hydration & atlas decoding
│   ├── Create.lua             # Instance builder, corners, padding, glass strokes, theme binding
│   ├── Icons.lua              # Atlas icon resolver + single-glyph fallback renderer
│   ├── Maid.lua               # Lifecycle & connection cleanup manager
│   ├── Services.lua           # Lazy cloneref Roblox service accessor
│   ├── Signal.lua             # Lightweight event signal class
│   ├── Theme.lua              # Presets, accent gradients, font presets, live theme bindings
│   ├── Transition.lua         # Mount/unmount scale fades, ripples, hover states, pulses
│   ├── Tween.lua              # Centralized easing curves, speed multiplier, reduce-motion flag
│   └── Util.lua               # Math, color, SafeCall, FS helpers, device detection, globals
├── Systems/
│   ├── Blur.lua               # Lighting BlurEffect controller
│   ├── CommandPalette.lua     # Ctrl+K spotlight search across tabs and elements
│   ├── Config.lua             # JSON serializer/deserializer, profile & auto-load manager
│   ├── Input.lua              # Global keybinds, key capture, drag & window resize helpers
│   ├── KeybindList.lua        # Floating HUD overlay tracking bound keys
│   ├── Notification.lua       # Toast stack manager & unread history feed
│   ├── Tooltip.lua            # Viewport-clamped hover tooltip overlay
│   └── Watermark.lua          # Floating FPS / ping / clock telemetry pill
├── Elements/
│   ├── Base.lua               # Shared element row, card, badge, visibility, lock/unlock, flags
│   ├── Static.lua             # Label, Paragraph, Divider, Header, CodeBlock, Image, ProfileCard
│   ├── Button.lua             # Button & ButtonGroup
│   ├── Toggle.lua             # Toggle (with inline keybind) & Checkbox
│   ├── Slider.lua             # Slider, RangeSlider, Stepper
│   ├── Input.lua              # Single/multiline, numeric, password-masked Input
│   ├── Segmented.lua          # Animated segmented selector
│   ├── Dropdown.lua           # Single/multi searchable popover dropdown
│   ├── Keybind.lua            # Toggle/Hold/Always key & mouse binder
│   ├── ColorPicker.lua        # HSV popover picker with alpha, hex, presets & rainbow
│   ├── Analytics.lua          # StatCard, Chart, ProgressBar, Table, CardGrid
│   └── Accordion.lua          # Collapsible container supporting nested child elements
├── Window/
│   ├── Container.lua          # Shared element factory methods mixin
│   ├── Section.lua            # Collapsible section card container
│   ├── Tab.lua                # Sidebar tab, two-column/full layout bands, SubTab support
│   ├── Dialog.lua             # Modal confirmation & input dialog overlay
│   ├── Loader.lua             # LoadingScreen & KeySystem overlays
│   ├── MobileButton.lua       # Draggable floating restore pill for touch & minimized mode
│   └── Window.lua             # Top-level window, sidebar, breadcrumb, popups, HUD wiring
└── Builders/
    └── SettingsTab.lua        # Prebuilt Appearance, HUD, Config Manager & Diagnostics tab
tools/
└── bundle.mjs                 # Pure Node ESM single-file Luau bundler -> dist/
dist/
├── Lumina.lua                 # Standalone library bundle (returns Lumina)
└── LuminaExample.lua          # Standalone interactive showcase bundle
```

## Quickstart

### Load Complete Showcase (`dist/LuminaExample.lua`)

```lua
loadstring(game:HttpGet("https://your-host/dist/LuminaExample.lua"))()
```

### Load Library & Build Your Own UI (`dist/Lumina.lua`)

```lua
local Lumina = loadstring(game:HttpGet("https://your-host/dist/Lumina.lua"))()

local window = Lumina:CreateWindow({
	Title = "My Workspace",
	Subtitle = "v1.0.0",
	Icon = "sparkles",
	Theme = "Midnight",
	Blur = true,
	Watermark = true,
	KeybindList = true,
	ConfigFolder = "MyWorkspace",
})

local tab = window:AddTab({
	Title = "Overview",
	Icon = "dashboard",
	Category = "Main",
})

local section = tab:AddSection({
	Title = "Automation",
	Icon = "zap",
	Side = "Left",
})

section:AddToggle({
	Title = "Auto Sync",
	Default = true,
	Keybind = Enum.KeyCode.F,
	Flag = "AutoSync",
	Callback = function(enabled)
		print("Auto Sync:", enabled)
	end,
})

window:BuildSettingsTab({
	Category = "System",
	Icon = "settings",
})
```

### Roblox Studio Usage

Paste the contents of `dist/Lumina.lua` directly into a `ModuleScript` (e.g., `ReplicatedStorage.Lumina`), then require it from a `LocalScript`:

```lua
local Lumina = require(game.ReplicatedStorage:WaitForChild("Lumina"))
local window = Lumina:CreateWindow({ Title = "Studio Demo" })
```

`ScreenGui` parenting automatically resolves `gethui()` -> `CoreGui` -> `LocalPlayer.PlayerGui` with `IgnoreGuiInset = true`, `ResetOnSpawn = false`, and `ZIndexBehavior = Enum.ZIndexBehavior.Sibling`.

## API Reference

### `Lumina` Entry Point

- `Lumina.Version`: `"1.0.0"`
- `Lumina.Services`, `Lumina.Util`, `Lumina.Signal`, `Lumina.Maid`, `Lumina.Tween`, `Lumina.Transition`, `Lumina.Theme`, `Lumina.Create`, `Lumina.Assets`, `Lumina.Icons` (also grouped under `Lumina.Core`)
- `Lumina.Input`, `Lumina.Tooltip`, `Lumina.Notification`, `Lumina.Blur`, `Lumina.Watermark`, `Lumina.KeybindList`, `Lumina.CommandPalette`, `Lumina.Config` (also grouped under `Lumina.Systems`)
- `Lumina:CreateWindow(opts)` -> loads assets, initializes input, creates and returns a `Window`
- `Lumina:Notify(opts)` -> sends a toast notification (`Title`, `Content`, `Type`: `"Info"|"Success"|"Warning"|"Error"|"Accent"`, `Duration`, `Icon`, `Actions`)
- `Lumina:KeySystem(opts)` -> mounts verification modal (`Title`, `Subtitle`, `Key`, `Keys`, `Verify`, `KeyUrl`, `SaveKey`, `Folder`, `FileName`, `Closable`, `Yield`, `OnSuccess`, `OnCancel`)
- `Lumina:LoadingScreen(opts)` -> mounts glassmorphic preloader (`Title`, `Subtitle`, `Icon`, `Duration`, `Steps`, `AutoClose`, `Backdrop`, `Yield`, `OnComplete`)
- `Lumina:SetTheme(name, animate?)` / `Lumina:AddTheme(name, overrides)` / `Lumina:SetAccent(color, animate?)` / `Lumina:SetFont(family)`
- `Lumina:Destroy()` / `Lumina:Unload()` -> cleanly destroys active windows, loaders, systems, hooks, and owned `ScreenGui`

### `Window`

- `window:AddCategory(name)`
- `window:AddTab({ Title, Icon?, Category?, Badge? })` -> `Tab`
- `window:SelectTab(tabOrTitleOrIndex, instant?)`
- `window:AddSection(...)` (available on `Tab` and `SubTab`)
- `window:BuildSettingsTab({ Title?, Icon?, Category? })`
- `window:Dialog({ Title, Content, Icon?, Input?, Buttons, Dismissible?, OnClose? })`
- `window:Notify(opts)`
- `window:Toggle()` / `window:SetVisible(bool)` / `window:IsVisible()`
- `window:SetToggleKey(keyCode)` / `window:GetToggleKey()`
- `window:ToggleSidebar(collapsed?)` / `window:SetMobileButtonEnabled(bool)`
- `window:SetTitle(text)` / `window:SetSubtitle(text)`
- `window:Destroy()`
- `window.Flags` -> flag registry indexed by element `Flag`

### Navigation & Containers (`Tab`, `SubTab`, `Section`, `Accordion`)

- `tab:AddSubTab({ Title, Icon? })` -> `SubTab`
- `tab:AddSection({ Title, Subtitle?, Icon?, Side = "Auto"|"Left"|"Right"|"Full", Collapsible?, Collapsed? })` -> `Section`
- Sections, Accordions, Tabs, and SubTabs expose element factories (`AddToggle`, `AddSlider`, `AddDropdown`, `AddTable`, etc., plus shorthand aliases like `Toggle`, `Slider`, etc.).

### Elements & Methods

Every element supports base methods: `:SetTitle(text)`, `:SetDesc(text)`, `:SetVisible(bool)`, `:SetDisabled(bool)`, `:Lock(reason?)`, `:Unlock()`, `:Flash()`, `:OnChanged(fn)`, `:Destroy()`.

| Category | Factories | Key Options & Methods |
| :--- | :--- | :--- |
| **Static & Media** | `AddLabel`, `AddParagraph`, `AddDivider`, `AddHeader`, `AddCodeBlock`, `AddImage`, `AddProfileCard` | `Copyable`, `Badge`, `AccentBar`, `Tags`, `LineNumbers`, `UserId`, `Status`, `:SetValue()`, `:SetContent()`, `:SetCode()`, `:SetStatus()` |
| **Actions** | `AddButton`, `AddButtonGroup` | `Variant` (`"Default"\|"Primary"\|"Danger"\|"Ghost"`), `Confirm`, `ShowArrow`, `Badge`, `:Fire()` |
| **Boolean** | `AddToggle`, `AddCheckbox` | `Default`, `Keybind`, `Flag`, `Callback`, `:Set(val, silent?)`, `:Get()`, `:Toggle()` |
| **Numeric** | `AddSlider`, `AddRangeSlider`, `AddStepper` | `Min`, `Max`, `Step`, `MinGap`, `Prefix`, `Suffix`, `Default`, `Flag`, `:Set()`, `:Get()`, `:Step(delta)` |
| **Text & Selection** | `AddInput`, `AddSegmented`, `AddDropdown`, `AddKeybind`, `AddColorPicker` | `Numeric`, `Integer`, `Mask`, `Multi`, `Searchable`, `AllowMouse`, `Mode`, `Transparency`, `Presets`, `:Set()`, `:Get()`, `:SetValues()` |
| **Analytics** | `AddStatCard`, `AddChart`, `AddProgressBar`, `AddTable`, `AddCardGrid` | `Delta`, `Points`, `Mode` (`"Line"\|"Bar"`), `Badge`, `Gradient`, `Columns`, `Rows`, `Selectable`, `Action`, `:SetValue()`, `:SetPoints()`, `:Push()`, `:SetRows()`, `:GetSelected()`, `:SetActive()` |
| **Grouping** | `AddAccordion` | `Expanded`, `Flag`, `:Expand()`, `:Collapse()`, `:Toggle()`, child element factories |

## Building & Verification

Requires Node.js (v18+ ESM) and optionally `luau-compile` from Luau CLI tools:

```bash
# Generate dist/Lumina.lua and dist/LuminaExample.lua
node tools/bundle.mjs

# Verify Luau syntax & bytecode compilation across source and dist bundles
luau-compile src/Lumina.lua
luau-compile src/Example.lua
luau-compile dist/Lumina.lua
luau-compile dist/LuminaExample.lua
```
