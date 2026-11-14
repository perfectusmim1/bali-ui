# Architecture & Motion

Bali uses a layered modular architecture inside `src/` compiled into self-contained single-file artifacts (`dist/Bali.lua` and `dist/BaliExample.lua`) by `tools/bundle.mjs`.

---

## Module Structure

```text
src/
├── Bali.lua                 # Library entrypoint, ScreenGui manager, global lifecycle hooks
├── Example.lua              # Interactive showcase workspace
├── Generated/
│   └── AssetData.lua        # Embedded 1024x704 Lucide sprite atlas & UI banner/noise textures
├── Core/
│   ├── Assets.lua           # Runtime PNG/Lua asset decoder and sprite lookup
│   ├── Create.lua           # Declarative Instance factory (Corner, Padding, GlassStroke, List)
│   ├── Icons.lua            # Bundled Lucide resolver + asset ID & glyph fallback renderer
│   ├── Maid.lua             # Automatic signal, tween, thread, and Instance cleanup
│   ├── Services.lua         # Lazy cloneref Roblox service registry
│   ├── Signal.lua           # Lightweight typed event signal
│   ├── Theme.lua            # Live theme engine, preset palettes, accent gradients & typography
│   ├── Transition.lua       # Position/transparency mount glides, press ripples & hover transitions
│   ├── Tween.lua            # Centralized Quint easing curves, speed multiplier & reduce motion
│   └── Util.lua             # Math, color, SafeCall/ErrorHandler, FS wrappers, device helpers
├── Systems/
│   ├── Blur.lua             # Lighting BlurEffect controller synced to window visibility
│   ├── CommandPalette.lua   # Ctrl+K spotlight search across tabs, controls & actions
│   ├── Config.lua           # Built-in JSON serializer, profile storage & auto-load system
│   ├── Input.lua            # Global keybinds, key capture, drag & clamped window resize
│   ├── KeybindList.lua      # Floating active/all keybinds HUD overlay
│   ├── Notification.lua     # Toast stack manager & unread history timeline
│   ├── Tooltip.lua          # Viewport-clamped hover tooltip overlay
│   └── Watermark.lua        # Top-left FPS, ping, and live clock telemetry pill
├── Elements/
│   ├── Base.lua             # Shared Card, Row, Badge, LockOverlay, Flag binding & Flash helpers
│   ├── Static.lua           # Label, Paragraph, Divider, Header, CodeBlock, Image, ProfileCard
│   ├── Button.lua           # Button & ButtonGroup
│   ├── Toggle.lua           # Toggle (with inline keybind) & Checkbox
│   ├── Slider.lua           # Slider, RangeSlider & Stepper
│   ├── Input.lua            # Single-line, numeric/integer & masked password Input
│   ├── Segmented.lua        # Segmented pill selector
│   ├── Dropdown.lua         # Single/multi searchable popover Dropdown
│   ├── Keybind.lua          # Toggle/Hold/Always keyboard & mouse keybind picker
│   ├── ColorPicker.lua      # HSV square, hue/alpha sliders, hex/RGB inputs, presets & rainbow
│   ├── Analytics.lua        # StatCard, Chart, ProgressBar, Table & CardGrid
│   └── Accordion.lua        # Expandable nested element container
├── Window/
│   ├── Container.lua        # Unified Add* factory mixin attached to Tab, SubTab, Section & Accordion
│   ├── Dialog.lua           # Modal alert, confirmation & prompt dialog overlay
│   ├── Loader.lua           # LoadingScreen & KeySystem verification gate
│   ├── MobileButton.lua     # Draggable floating restore pill for touch & minimized windows
│   ├── Section.lua          # Collapsible glassmorphic section cards
│   ├── Tab.lua              # Sidebar tabs, two-column/full bands & SubTab navigation
│   └── Window.lua           # Main obsidian window, sidebar, breadcrumb, top actions & popups
└── Builders/
    └── SettingsTab.lua      # Ready-to-use Appearance, HUD, Config Manager & Diagnostics tab
```

---

## ZIndex Layer Isolation

Inside the root `ScreenGui`, Bali isolates depth into dedicated container frames so dropdowns, color pickers, tooltips, modals, and toasts never z-fight or get clipped by parent `ScrollingFrame` bounds:

| Layer Frame | `ZIndex` | Responsibilities |
| :--- | :--- | :--- |
| `BaliMainLayer` | `1` | Primary window chassis, sidebar, breadcrumb header, tab scrolling canvases |
| `BaliHUDLayer` | `20` | `Watermark`, `KeybindList`, draggable `MobileButton` restore pill |
| `BaliPopupLayer` | `100` | `Dropdown` menus, `ColorPicker` popovers, `CommandPalette`, `Notification` history popover, `Tooltip` |
| `BaliDialogLayer` | `200` | Centered `Dialog` confirmation & prompt overlays |
| `BaliNotifyLayer` | `400` | Viewport-anchored `Notification` toast stack |

---

## Motion, Typography & Rendering Pipeline

### Deceleration Tweens Without Layout Jitter

`Core/Tween` and `Core/Transition` standardize on unified `Quint Out` deceleration (`Tween.Fast = 0.14s`, `Tween.Normal = 0.22s`, `Tween.Smooth = 0.32s`) rather than elastic overshoot or permanent `UIScale` transforms on resting cards:

- **Zero scale stretching at rest**: Hover, mount, tab switch, sub-tab cross-slide, minimize/restore morphs, and button press states keep text crisp at native `1x` resolution — automatically cleaning up temporary transition scales and never injecting `Scale(1,1)` washes inside `UIListLayout` or `AutomaticSize` controls.
- **Modal pointer isolation**: Open popovers (`Dropdown`, `ColorPicker`, `NotificationPopover`), `CommandPalette`, and `Dialog` overlays install active input sinks and `Transition.IsOverlayBlocking` guards so underlying sliders and buttons ignore stray pointer events while overlays are open.
- **Global speed & accessibility**: Set `Bali.Tween.Speed` or toggle `Bali.Tween.Reduced = true` (also exposed in Settings) to adjust motion speed or skip non-essential transitions.

### Lucide Icon Atlas (`Core/Icons`)

`Generated/AssetData` embeds **164 vector-crisp Lucide icons** packed into a `1024x704` sprite sheet alongside custom procedural obsidian-glass banner artwork (`v5`), hydrated at startup via `getcustomasset` / `getsynasset` when supported. Every icon slot gracefully degrades to clean monochrome glyphs or supports raw `rbxassetid://` and numeric Roblox asset IDs:

```lua
section:AddButton({
	Title = "Run Diagnostics",
	Icon = "activity", -- Bundled Lucide name or "rbxassetid://..."
})
```
