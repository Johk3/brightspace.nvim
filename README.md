# brightspace.nvim

Browse TU Delft Brightspace from Neovim. Open a workspace with courses, a content tree, upcoming deadlines, and new announcements or material. PDFs open in your desktop viewer; announcements and HTML pages stay in Neovim.

## Requirements

- Neovim 0.10 or newer, Linux, and `curl`.
- `xdg-open`, or a viewer configured below.
- `secret-tool` (`sudo apt install libsecret-tools`) and an unlocked Secret Service keyring for persistent credentials. Without it, credentials remain in memory for the editor session.
- Telescope is optional. Search falls back to `vim.ui.select`.
- Plenary is required only for running tests.

Only TU Delft's NetID/SURFconext login flow is supported. First-time consent or multi-factor authentication may require signing in through a browser.

## Install

For a local checkout with lazy.nvim:

```lua
{
  dir = vim.fn.expand("~/brightspace.nvim"),
  cmd = "Brightspace",
  keys = {
    { "<leader>bs", "<cmd>Brightspace<cr>", desc = "Brightspace" },
  },
  opts = {},
}
```

The plugin makes no network requests until you open its workspace. The first open prompts for your NetID and a hidden password. Subsequent opens reuse cookies or sign in with stored credentials. Never put credentials in your Neovim configuration.

## Commands and navigation

- `:Brightspace` or `:Brightspace open`: open or focus the workspace.
- `:Brightspace refresh`: refresh data from Brightspace.
- `:Brightspace search`: search courses and loaded content.
- `:Brightspace logout`: forget credentials and cookies, close the workspace, and remove cached course data and downloaded files.

Inside the workspace:

| Key | Action |
| --- | --- |
| `<CR>` | Select a course, expand a module, or open an item |
| `o`, `za` | Toggle a module |
| `Q` | Show or hide older quarters |
| `R` | Refresh |
| `/` | Search |
| `m` | Mark the item as seen |
| `M` | Mark the selected course as seen |
| `q` | Close the workspace |

Use ordinary Neovim window navigation (`<C-w>h`, `<C-w>l`) to move between panes. Selecting an older course loads its content on demand. Search includes courses and content already loaded into the workspace or disk cache.

Deadlines cover current courses and the next 30 days. Red means less than 24 hours; yellow means less than three days. New items become seen when opened or explicitly marked. On the first load, material older than seven days is treated as seen.

## Configuration

```lua
require("brightspace").setup({
  base_url = "https://brightspace.tudelft.nl",
  viewer = "xdg-open", -- or { "evince" }
  keymap = "<leader>bs", -- false disables this mapping
  cache_ttl = 300,       -- refresh interval and cache lifetime, seconds
  keepalive = 600,       -- session check interval, seconds; 0 disables it
  deadline_days = 30,
})
```

Course access dates determine whether a course is current when available. Otherwise the plugin uses academic-year and quarter labels such as `2026/27 Q1`. Date-free course labels use approximate academic-quarter boundaries; `Q` always exposes older or unclassified offerings. Programme/community units with a non-course org-unit type are excluded.

## Local data and privacy

Credentials are stored in the desktop keyring under `service=brightspace.nvim`. Passwords travel to subprocesses on standard input. Session cookies use a private file with mode `0600`.

- Cookies: `stdpath("state")/brightspace/cookies.txt`
- Course data and file downloads: `stdpath("cache")/brightspace/`
- Seen state: `stdpath("data")/brightspace/seen.json`

Cached content is private local data. Logout clears cookies, credentials, JSON caches, and downloaded files; seen markers remain. Environment variables `BRIGHTSPACE_STATE_DIR`, `BRIGHTSPACE_CACHE_DIR`, and `BRIGHTSPACE_DATA_DIR` can override these directories.

Closing the workspace stops polling and session keepalive. Cached courses remain available when offline. Some course tools may be unavailable to your account; the workspace reports partial failures and retains cached data.

## Development

```sh
make test
```

Set `PLENARY_DIR` if Plenary is not installed under `stdpath("data")/lazy/plenary.nvim`. Tests use synthetic course data, fake authentication, temporary directories, and a local HTTP server.

API field and route references: [enrollments](https://docs.valence.desire2learn.com/res/enroll.html), [course content](https://docs.valence.desire2learn.com/res/content.html), and [calendar](https://docs.valence.desire2learn.com/res/calendar.html).
