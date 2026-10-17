# brightspace.nvim

Browse TU Delft Brightspace from Neovim. Open a workspace with courses, a content tree, upcoming deadlines, and new announcements or material. PDFs open in your desktop viewer; announcements and HTML pages stay in Neovim. Jupyter notebooks open as persistent local working copies in separate tabs.

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
- `:Brightspace logout`: forget credentials and cookies, close the workspace, and remove cached course data and downloaded files. Local notebook working copies remain.

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
  notebook_dir = false, -- default: stdpath("data") .. "/brightspace/notebooks"
  keymap = "<leader>bs", -- false disables this mapping
  cache_ttl = 300,       -- refresh interval and cache lifetime, seconds
  keepalive = 600,       -- session check interval, seconds; 0 disables it
  deadline_days = 30,
})
```

Course access dates determine whether a course is current when available. Otherwise the plugin uses academic-year and quarter labels such as `2026/27 Q1`. Date-free course labels use approximate academic-quarter boundaries; `Q` always exposes older or unclassified offerings. Programme/community units with a non-course org-unit type are excluded.

## Jupyter notebooks

Press Enter on a `.ipynb` file in the content tree. Brightspace downloads it once to
`stdpath("data")/brightspace/notebooks/<course-id>/<topic-id>/<filename>.ipynb`
and opens it in an editable Neovim tab. Set `notebook_dir` to use another root.
Reopening focuses the existing buffer, including unsaved edits. Refreshes, remote
file revisions, and logout never replace or delete your working copy. To start
again from a newer course version, move your working copy elsewhere first.
Downloads with a notebook filename, URL, or notebook MIME type are recognized.

Notebook support is optional: without a notebook editor plugin, Neovim shows the
original JSON. The [example lazy.nvim configuration](examples/notebooks.lua)
uses [Jupytext](https://github.com/goerz/jupytext.nvim) to edit notebooks as
[Markdown](https://jupytext.readthedocs.io/en/latest/formats.html),
[render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)
to render prose and LaTeX equations, [image.nvim](https://github.com/3rd/image.nvim)
to show notebook images, and [Molten](https://github.com/benlubas/molten-nvim) to
run Python code cells and display their outputs. Markdown cells render as prose;
code cells appear as fenced Python blocks. Saving writes the `.ipynb` with its
metadata and outputs, ready to open in Jupyter.

To install this optional Python setup with `uv`:

```sh
notebook_env="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/notebook-venv"
uv venv "$notebook_env"
uv pip install --python "$notebook_env/bin/python" \
  pynvim jupytext jupyter-client ipykernel nbformat pillow \
  numpy matplotlib control ipympl pylatexenc
install -m 755 scripts/latex2text-notebook "$notebook_env/bin/latex2text-notebook"
install -m 644 scripts/latex2text-notebook.py "$notebook_env/bin/latex2text-notebook.py"
"$notebook_env/bin/python" -m ipykernel install --user --name brightspace-python --display-name 'Brightspace Python'
python3 - <<'PYKERNEL'
import json
from pathlib import Path
p = Path.home() / '.local/share/jupyter/kernels/brightspace-python/kernel.json'
spec = json.loads(p.read_text())
spec.setdefault('env', {})['MPLBACKEND'] = 'module://matplotlib_inline.backend_inline'
p.write_text(json.dumps(spec, indent=2) + '\n')
PYKERNEL
cp examples/notebooks.lua ~/.config/nvim/lua/plugins/notebooks.lua
```

Install the plugins with your lazy.nvim configuration, then run
`:UpdateRemotePlugins` and `:TSInstall markdown markdown_inline latex python`.
Restart Neovim after installation. Inline image rendering uses Ghostty's Kitty
graphics support and the ImageMagick CLI (`convert`); install ImageMagick if
that command is missing. Use `<leader>np` to open a plot in your desktop image
viewer if inline images are unavailable.
NvChad users must also set `vim.g.loaded_python3_provider = nil` **after**
`require "nvchad.options"` in their options file. The example sets the Python
provider to this environment; keep an existing provider if it already contains
the required packages. Course-specific packages can be installed with
`uv pip install --python "$notebook_env/bin/python" <package>`. NumPy, Matplotlib,
ipympl, and pylatexenc are installed in the current notebook environment. ipympl
enables `%matplotlib widget`; pylatexenc converts notebook equations to readable
Unicode math in Neovim.

| Key | Action |
| --- | --- |
| `<leader>ni` | Choose a kernel; select `brightspace-python` |
| `<leader>nr` | Run the current code cell |
| `<leader>nn` | Run the current code cell and move to the next |
| `]h` / `[h` | Move to the next / previous code cell |
| `<leader>no` | Show cell output |
| `<leader>nl` | Load previously saved outputs after starting a kernel |
| `<leader>np` | Open the cell's plot in an external image viewer |
| `<leader>nx` | Interrupt execution |
| `<leader>nq` | Stop the kernel |
| `:w` | Save the notebook and current kernel outputs |

After choosing a kernel, wait for Molten’s “ready” message before running a cell.
Markdown headings, lists, links, tables, equations, and code blocks render in
place. Bare display environments such as `\begin{cases}...\end{cases}` are
automatically wrapped for Markdown rendering when a notebook opens. Notebook PNG
attachments and plot outputs display inline in Ghostty.
Text output appears below its cell; `<leader>no` opens it in a window.
Additional Jupyter kernels can be registered
for course environments. Use the appropriate working directory and keep any
required datasets alongside your local work. Brightspace does not upload or
submit edited notebooks.

## Local data and privacy

Credentials are stored in the desktop keyring under `service=brightspace.nvim`. Passwords travel to subprocesses on standard input. Session cookies use a private file with mode `0600`.

- Cookies: `stdpath("state")/brightspace/cookies.txt`
- Course data and file downloads: `stdpath("cache")/brightspace/`
- Seen state: `stdpath("data")/brightspace/seen.json`
- Editable notebooks: `stdpath("data")/brightspace/notebooks/` (or `notebook_dir`)

Cached content is private local data. Logout clears cookies, credentials, JSON caches, and cached downloads; seen markers and notebook working copies remain. Environment variables `BRIGHTSPACE_STATE_DIR`, `BRIGHTSPACE_CACHE_DIR`, and `BRIGHTSPACE_DATA_DIR` can override these directories.

Closing the workspace stops polling and session keepalive. Cached courses remain available when offline. Some course tools may be unavailable to your account; the workspace reports partial failures and retains cached data.

## Development

```sh
make test
```

Set `PLENARY_DIR` if Plenary is not installed under `stdpath("data")/lazy/plenary.nvim`. Tests use synthetic course data, fake authentication, temporary directories, and a local HTTP server.

API field and route references: [enrollments](https://docs.valence.desire2learn.com/res/enroll.html), [course content](https://docs.valence.desire2learn.com/res/content.html), and [calendar](https://docs.valence.desire2learn.com/res/calendar.html).
