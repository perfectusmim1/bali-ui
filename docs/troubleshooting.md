# Troubleshooting & Building

---

## Building Standalone Bundles

Source modules inside `src/` use clean relative `require("...")` calls. To regenerate the standalone single-file bundles under `dist/` (`dist/Bali.lua` and `dist/BaliExample.lua`) without runtime `loadstring`:

```bash
# Requires Node.js v18+
node tools/bundle.mjs
```

`tools/bundle.mjs` topologically packages all `src/` modules into isolated module closures inside `dist/Bali.lua` (returning `Bali`) and `dist/BaliExample.lua` (library + interactive showcase).

### Offline Luau Compilation & Verification

```bash
# Verify Luau syntax & bytecode compilation across source and dist bundles
luau-compile src/Bali.lua
luau-compile src/Example.lua
luau-compile dist/Bali.lua
luau-compile dist/BaliExample.lua

# Run full headless mock-Roblox behavioral & regression suite (requires Zune)
zune run tests/mock_roblox_verify.luau
```

### Regenerating Lucide Icon Atlas (`src/Generated/AssetData.lua`)

Requires Node dependencies inside `tools/assets/` (`npm install`):

```bash
node tools/assets/generate.mjs
```

---

## Common Runtime Behavior & Fixes

### 1. Re-Executing Script Shows Duplicate Windows

Always avoid modifying `ScreenGui.Name` manually outside Bali, or call `Bali:Unload()` / `Bali:Destroy()` during development hot-reloads. `Bali:CreateWindow()` automatically invokes legacy cleanup on `_BaliInstance` and removes stray `BaliUI` / `BaliBlur` instances on every fresh execution.

### 2. Config Saves Work In Executor But Not Persisting Between Studio Runs

Roblox Studio sandboxes `writefile` / `readfile`. When filesystem APIs are absent, `Bali.Systems.Config` transparently persists snapshots in memory (`memoryStore`) so `Export()`, `Import()`, `Save()`, and `Load()` remain functional during playtesting without throwing errors. Inside Roblox Studio, use `Config.Export()` / `DataStoreService` if cross-session cloud persistence is required.

### 3. Icons Appear as Unicode Glyphs Instead of Vector Sprites

When an environment blocks `getcustomasset` / `getsynasset` or binary file writes, `Core/Icons` automatically renders crisp vector glyph fallbacks rather than invisible boxes. Ensure `getcustomasset` is enabled if you want the full 164-icon `832x572` Lucide PNG sheet hydrated.
