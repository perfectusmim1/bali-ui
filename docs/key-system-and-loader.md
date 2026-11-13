# Loader & Key System

Display a branded glassmorphic splash loader (`Bali:LoadingScreen`) or credential verification gate (`Bali:KeySystem`) before constructing the main workspace window.

![Bali Key Verification Gate](assets/screenshots/key-system.png)

---

## `Bali:LoadingScreen(opts)`

Mounts a centered obsidian splash modal with icon bloom, animated progress track, and step status messages:

```lua
Bali:LoadingScreen({
	Title = "Bali Suite",
	Subtitle = "Initializing runtime modules...",
	Icon = "sparkles",
	Duration = 1.6,
	Steps = {
		"Hydrating Lucide asset atlas...",
		"Calibrating obsidian shaders...",
		"Preparing workspace layout...",
	},
	AutoClose = true,
	Backdrop = true,
	Yield = true, -- pauses caller until steps finish
	OnComplete = function()
		print("Loader finished!")
	end,
})
```

If `Yield = false`, the returned controller exposes `:SetStatus(text)`, `:SetProgress(alpha, statusText?)`, `:Close(onDone?)`, `:Wait()`, and `:Destroy()`.

---

## `Bali:KeySystem(opts)`

Validates user keys against static strings (`Key` / `Keys`), async HTTP verification callbacks (`Verify`), cached local key files (`SaveKey = true`), and clipboard link helpers (`KeyUrl`):

```lua
local unlocked = false

Bali:KeySystem({
	Title = "Bali Access Gate",
	Subtitle = "Enter your workspace license key to continue.",
	Note = "Demo verification key: BALI-DEMO",
	Icon = "key",
	Keys = { "BALI-DEMO" }, -- or custom Verify = function(candidate) return true, "Reason" end
	KeyUrl = "https://example.com/get-key", -- copied on clicking "Get Key"
	SaveKey = true,
	Folder = "Bali",
	FileName = "license.key",
	Closable = true,
	Yield = true,
	OnSuccess = function(key)
		unlocked = true
		print("Authenticated with:", key)
	end,
	OnCancel = function()
		warn("Verification cancelled")
	end,
})

if not unlocked then
	return
end
```

### Verification Option Priority

1. `Verify(candidate)` / `CheckKey(candidate)` / `Callback(candidate)` — custom validator returning `boolean, optionalErrorMessage`.
2. `Keys` (array or dictionary of accepted keys) or `Key` (single accepted string).
3. If `SaveKey = true` and a saved key passes verification on startup, `KeySystem` immediately fires `OnSuccess` without blocking the user again.
