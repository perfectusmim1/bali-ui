# Bali UI

**Bali** is an obsidian glassmorphic UI library for Roblox and Luau featuring unified `Quint Out` deceleration motion, crisp `BuilderSans` typography, radial glass strokes, a bundled 164-icon `1024x704` Lucide sprite atlas, live theme switching, real-time analytics widgets, desktop & mobile ergonomics, and zero-`loadstring` single-file distribution bundles.

> **Documentation:** [bali-2.gitbook.io/bali-docs](https://bali-2.gitbook.io/bali-docs/)

---

## Highlights

- **Obsidian Glass Architecture**: Layered depth (`Main`, `HUD`, `Popup`, `Dialog`, `Notify`), directional hairline `UIStroke` highlights, ambient radial blooms, and constant-size fade/glide minimize & restore transitions without `UIScale` jitter.
- **7 Curated Themes & Live Overrides**: `Midnight`, `Ocean`, `Graphite`, `Aurora`, `Sunset`, `Emerald`, and `Light`, plus runtime `SetAccent`, `AddTheme`, and `SetFont` (`Builder`, `Gotham`, `Montserrat`, `Ubuntu`, `Nunito`).
- **164 Bundled Lucide Icons**: Self-contained `1024x704` Lucide sprite atlas (`src/Generated/AssetData.lua`) hydrated cleanly via `getcustomasset` / `getsynasset` with monochrome glyph fallbacks in Roblox Studio.
- **Complete Interactive Suite**: `Button` (with `Confirm` & variants), `ButtonGroup`, `Toggle` (with inline keybinds), `Checkbox`, `Slider`, `RangeSlider`, `Stepper`, `Input` (numeric, integer, password mask, clearable), `Segmented`, `Dropdown` (single, multi, searchable, input-isolated compact popover with per-option `Icon`, `IconColor`, `Image`/`Thumbnail`, `Color`, `Badge`, `RightText`, and `Disabled` states), `Keybind` (`Toggle`, `Hold`, `Always`, mouse binds), `ColorPicker` (HSV square, alpha slider, hex/RGB, presets, rainbow), and nested `Accordion`.
- **Analytics & Data Widgets**: `StatCard` (animated counters, deltas, sparklines), `Chart` (`Line` / `Bar` with live `:Push()`), `ProgressBar`, `Table` (live filter, selectable checkboxes, badges, inline row actions), `CardGrid`, plus rich typography (`Label`, `Paragraph`, `Divider`, `Header`, `CodeBlock` with language-aware `RichText` highlighting, `Image` / `Banner`, `ProfileCard`).
- **System HUD & Lifecycle Safety**: Stackable `Notification` toasts (configurable duration via `SetNotificationDuration`) + unread history bell popover, draggable `Watermark`, live `KeybindList`, window-centered `CommandPalette` (`Ctrl+K`), `Lighting` `Blur`, viewport-clamped `Tooltip`, `Dialog` modals, `LoadingScreen`, `KeySystem`, JSON `Config` & `AutoSave` persistence, animated `window:Unload()`, automatic `_BaliInstance` orphan cleanup on re-execute, and global error boundary (`Util.ErrorHandler`).

---

## Quickstart

### Run Complete Showcase (`dist/BaliExample.lua`)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/perfectusmim1/bali-ui/master/dist/BaliExample.lua"))()
```

### Build With Bali (`dist/Bali.lua`)

```lua
local Bali = loadstring(game:HttpGet("https://raw.githubusercontent.com/perfectusmim1/bali-ui/master/dist/Bali.lua"))()

local window = Bali:CreateWindow({
	Title = "Bali Suite",
	Subtitle = "v1.0.0",
	Icon = "sparkles",
	Theme = "Midnight",
	Blur = true,
	Watermark = true,
	KeybindList = true,
	ConfigFolder = "BaliSuite",
})

local tab = window:AddTab({
	Title = "Overview",
	Icon = "layout-dashboard",
	Category = "Main",
	Badge = "Live",
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

Paste the contents of [`dist/Bali.lua`](dist/Bali.lua) into a `ModuleScript` (e.g. `ReplicatedStorage.Bali`) and require it from any `LocalScript`:

```lua
local Bali = require(game:GetService("ReplicatedStorage"):WaitForChild("Bali"))
local window = Bali:CreateWindow({ Title = "Studio Demo" })
```

`ScreenGui` parenting automatically resolves `gethui()` -> `CoreGui` -> `LocalPlayer.PlayerGui` with `IgnoreGuiInset = true`, `ResetOnSpawn = false`, and `ZIndexBehavior = Enum.ZIndexBehavior.Sibling`.

---

## Documentation

Read the hosted docs at **[bali-2.gitbook.io/bali-docs](https://bali-2.gitbook.io/bali-docs/)** or browse the Markdown source inside [`docs/`](docs/SUMMARY.md):

- [Getting Started](docs/getting-started.md) — Executor quickstart, Studio setup & duplicate window cleanup
- [Architecture & Motion](docs/architecture.md) — Modular hierarchy, `ZIndex` layers, tweens & Lucide atlas
- [Window & Navigation](docs/window-and-navigation.md) — `CreateWindow`, tabs, sub-tabs, sections & `Ctrl+K` palette
- [Interactive Controls](docs/interactive-controls.md) — Buttons, toggles, sliders, inputs, dropdowns, keybinds & color picker
- [Analytics & Rich Content](docs/analytics-and-data.md) — `StatCard`, `Chart`, `ProgressBar`, `Table`, `CardGrid` & static widgets
- [HUD, Notifications & Modals](docs/hud-and-systems.md) — Toasts, bell feed, watermark, keybind list, dialogs & blur
- [Themes & Config Persistence](docs/themes-and-config.md) — Presets, custom themes, JSON export/import & Settings builder
- [Loader & Key System](docs/key-system-and-loader.md) — Splash preloader & license verification gate
- [Troubleshooting & Building](docs/troubleshooting.md) — Re-bundling `dist/Bali.lua` & offline Luau checks

---

## Architecture

```text
src/
├── Bali.lua                 # Main library entry point, safe ScreenGui host, error boundary
├── Example.lua                # Full-feature interactive showcase
├── Generated/
│   └── AssetData.lua          # Embedded 1024x704 Lucide sprite atlas & textures
├── Core/
│   ├── Assets.lua             # Runtime asset hydration & atlas decoding
│   ├── Create.lua             # Instance builder, corners, padding, glass strokes, theme binding
│   ├── Icons.lua              # Atlas icon resolver + single-glyph fallback renderer
│   ├── Maid.lua               # Lifecycle & connection cleanup manager
│   ├── Services.lua           # Lazy cloneref Roblox service accessor
│   ├── Signal.lua             # Lightweight event signal class
│   ├── Theme.lua              # Presets, accent gradients, font presets, live theme bindings
│   ├── Transition.lua         # Mount/unmount glides, ripples, hover states, pulses
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
├── Bali.lua                   # Standalone library bundle (returns Bali)
└── BaliExample.lua            # Standalone interactive showcase bundle
```

---

## Building & Verification

Requires Node.js v18+ (`tools/bundle.mjs`) and optionally `luau-compile` / `zune` for static bytecode checks and headless mock tests:

```bash
# Regenerate dist/Bali.lua and dist/BaliExample.lua
node tools/bundle.mjs

# Verify Luau syntax & bytecode compilation across source and dist bundles
luau-compile src/Bali.lua
luau-compile src/Example.lua
luau-compile dist/Bali.lua
luau-compile dist/BaliExample.lua

# Run headless mock-Roblox behavioral regression suite
zune run tests/mock_roblox_verify.luau
```
