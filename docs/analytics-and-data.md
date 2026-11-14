# Analytics & Rich Content

Bali includes native real-time telemetry widgets (`StatCard`, `Chart`, `ProgressBar`, `Table`, `CardGrid`) alongside rich typography, syntax-highlighted code blocks, and profile cards.

---

## `AddStatCard`

Displays an animated metric counter, percentage trend delta pill, optional Lucide icon, and miniature sparkline curve.

```lua
local netValue = section:AddStatCard({
	Title = "Net Portfolio Value",
	Value = 194280,
	Prefix = "$",
	Decimals = 0,
	Delta = 8.7,
	Icon = "wallet",
	Color = "Accent",
	Points = { 142, 151, 160, 158, 174, 181, 194.28 },
	Glow = true,
	Animate = true,
	Flag = "NetValueStat",
})

netValue:SetValue(201450, 11.4)
netValue:SetPoints({ 150, 162, 170, 185, 194, 201.45 })
```

---

## `AddChart`

Interactive `Line` or `Bar` visualization with optional grid lines, cursor hover value readout, live streaming (`:Push()`), and rolling sample caps (`MaxPoints`).

```lua
local chart = section:AddChart({
	Title = "Throughput (MB/s)",
	Subtitle = "Rolling cluster sample window",
	Mode = "Line", -- "Line" | "Bar"
	Points = { 68, 74, 81, 79, 91, 96, 88 },
	Labels = { "08h", "10h", "14h", "16h", "20h", "22h", "00h" },
	Height = 110,
	Color = "Accent",
	ShowGrid = true,
	Suffix = " MB/s",
	MaxPoints = 18,
})

chart:Push(94, "02h")
```

- **Methods**: `:SetPoints(pointsTbl, labelsTbl?)`, `:Push(value, label?)`, `:Get()`, `:SetTitle(str)`.

---

## `AddProgressBar`

Smooth animated progress track supporting accent gradients, right-aligned status pills, and secondary footer labels.

```lua
local alloc = section:AddProgressBar({
	Title = "Total Allocation",
	Value = 74.5,
	Max = 100,
	Suffix = "%",
	Badge = "8.68% APR",
	SecondaryLabel = "$144,738 / $194,280",
	Gradient = true,
	Height = 8,
	Color = "Accent",
})

alloc:Set(82.0, 100, "9.12% APR")
```

---

## `AddTable`

Searchable multi-column data table with proportional (`Scale`) or pixel column widths, crisp status pills, optional row selection checkboxes, hover feedback, and inline row action buttons.

```lua
local endpoints = section:AddTable({
	Title = "Cluster Endpoints",
	Searchable = true,
	Selectable = true,
	MaxHeight = 240,
	Columns = {
		{ Title = "Endpoint", Key = "Endpoint", Scale = 0.34 },
		{ Title = "Region", Key = "Region", Scale = 0.22 },
		{ Title = "Latency", Key = "Latency", Scale = 0.14, Align = "Right" },
		{ Title = "Health", Key = "Health", Scale = 0.16 },
		{ Title = "", Key = "ActionCol", Scale = 0.14 },
	},
	Rows = {
		{
			Endpoint = { Text = "us-east-alpha", Icon = "server" },
			Region = "Virginia",
			Latency = "11 ms",
			Health = { Badge = "Optimal", Color = "Success" },
		},
	},
	Action = {
		Text = "Inspect",
		Icon = "external-link",
		Callback = function(row)
			print("Inspecting:", row.Endpoint.Text)
		end,
	},
	OnRowClick = function(row, index) end,
})
```

- **Methods**: `:SetRows(rowsTbl)`, `:GetSelected()`, `:SetTitle(str)`.

---

## `AddCardGrid`

Responsive multi-column selection grid (ideal for snapshot selectors, server cards, or strategy cards) with active accent gradient highlight:

```lua
local grid = section:AddCardGrid({
	Default = "wed",
	Cards = {
		{ Id = "mon", Title = "Monday", Icon = "calendar", Stats = { { Label = "Volume", Value = "$142.8K" } } },
		{ Id = "wed", Title = "Wednesday", Icon = "calendar", Stats = { { Label = "Volume", Value = "$194.2K" } } },
	},
	Callback = function(selectedId) end,
})
```

- **Methods**: `:SetActive(id, silent?)`, `:UpdateCard(id, dataTbl)`, `:Get()`.

---

## Static & Media Elements

| Constructor | Highlights | Methods |
| :--- | :--- | :--- |
| `AddLabel` | Key/value row with optional copy button (`Copyable = true`) & status `Badge` | `:SetText(s)`, `:SetValue(v)`, `:Get()`, `:SetBadge(text, colorKey?)` |
| `AddParagraph` | Descriptive card with optional leading accent bar (`AccentBar`), tags & icon | `:SetTitle(s)`, `:SetDesc(s)`, `:SetContent(s)`, `:SetTags(list)` |
| `AddDivider` | Clean centered hairline divider with optional centered label | `—` |
| `AddHeader` | Uppercase category micro-heading with optional trailing badge | `—` |
| `AddCodeBlock` | Language-aware `RichText` syntax-highlighted monospaced snippet viewer (`Luau`/`Lua`/`JSON`/`Python`/`JS`) with per-line gutter alignment and copy button | `:SetCode(src)`, `:Get()` |
| `AddImage` / `AddBanner` | Aspect-preserving `CanvasGroup` rounded image & banner card (`Overlay`, `Badge`, `ScaleType`, `Corner`, `Height`) | `:SetImage(src)`, `:SetCaption(s)` |
| `AddProfileCard` | Displays `LocalPlayer` (or custom `UserId`) avatar headshot, status pill & workspace meta | `:SetTitle(s)`, `:SetDesc(s)`, `:SetStatus(text, colorKey?)` |
