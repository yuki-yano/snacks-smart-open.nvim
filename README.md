# snacks-smart-open.nvim

`snacks-smart-open.nvim` augments the `smart` picker in [snacks.nvim](https://github.com/folke/snacks.nvim) with scoring, learning, and persistence inspired by [smart-open.nvim](https://github.com/danielfalk/smart-open.nvim). The goal is to provide smart-open style relevance inside the Snacks picker without forking Snacks itself.

## Features

- Adds smart-open style signal boosting (open buffers, alternate buffer, project locality, path proximity, frecency, recency) to Snacks picker items via `score_add`.
- Persists usage data in SQLite and applies a Mozilla-style frecency decay (10 day half-life by default).
- Reuses smart-open's weight adaptation algorithm to learn from your selections and adjust future rankings.
- Tracks buffer usage automatically on `BufWinEnter`/`BufWritePost` (configurable) and updates the database after every confirm action.
- Ships entirely as an external module that hooks into Snacks at runtime.
- Provides an additional picker source, `smart_open_files`, that applies the same scoring to the plain `files` finder.

## Installation

Example for lazy.nvim:

```lua
{
  "yuki-yano/snacks-smart-open.nvim",
  dependencies = { "folke/snacks.nvim" },
  config = function()
    require("snacks-smart-open").setup()
  end,
}
```

Call `setup()` after Snacks itself has been initialised. If Snacks is already loaded, the integration begins immediately.

### New picker source

Once installed you can open the smart-open-style file picker with:

```lua
Snacks.picker.smart_open_files()
```

The source inherits Snacks' `files` finder, so options like `cwd`, `hidden`, or `ignored` still apply.

## Configuration

All options are optional; unspecified fields fall back to sensible defaults.

```lua
require("snacks-smart-open").setup({
  apply_to = { "smart", "smart_open_files" },
  db = {
    path = vim.fn.stdpath("data") .. "/snacks/smart-open.sqlite3",
  },
  frecency = {
    half_life_days = 10,
    score_per_access = 100,
    max_lifetime_days = 365,
  },
  weights = {
    path_fzf = 140,
    path_fzy = 140,
    virtual_name_fzf = 131,
    virtual_name_fzy = 131,
    open = 3,
    alt = 4,
    proximity = 13,
    project = 10,
    frecency = 17,
    recency = 9,
  },
  learning = {
    adjustment_points = 0.6,
    promote_cap = 15,
    demote_cap = 1,
    min_weight = 1,
    auto_record = true, -- set to false to disable the BufWinEnter/BufWritePost auto tracker
  },
})
```

- `weights` mirrors smart-open.nvim's initial values; learned adjustments are persisted in the `snacks_smart_open_weights` table.
- `learning.adjustment_points`, `promote_cap`, and `demote_cap` influence how aggressively weights adapt to your selections.
- Set `learning.auto_record = false` if you only want usage recorded when confirming picker choices.
- The SQLite database lives under `stdpath("data")/snacks/smart-open.sqlite3` and uses Snacks' built-in SQLite wrapper.
- `apply_to` controls which picker sources receive the smart-open scoring/learning hooks. The default is `{ "smart", "smart_open_files" }`; add any other source keys here to opt-in. Existing finder behaviour and source-specific defaults remain untouched—only the smart-open scoring and learning logic is layered on top.

## How It Works

1. The plugin wraps `Snacks.picker.sources.smart.transform`, forwarding to the original transform and then injecting smart-open derived score contributions.
2. A confirm action hook stores usage in SQLite, updates frecency decay, and feeds the top results back into the learning routine that nudges signal weights.
3. Runtime state is kept outside Snacks so existing configuration continues to work unchanged.

## License Compatibility

smart-open.nvim is released under the MIT License. This project reimplements its ideas without copying source code, and is likewise distributed under MIT. You may therefore use snacks-smart-open.nvim alongside smart-open.nvim without additional obligations beyond the MIT terms.

## License

MIT © Yuki Yano
