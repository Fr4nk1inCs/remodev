local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out,                            "WarningMsg" },
      { "\nPress any key to exit" },
    }, true, {})
    vim.fn.gather()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

local function fzf_pick(command, opts)
  command = command ~= "auto" and command or "files"
  opts = opts or {}
  opts = vim.deepcopy(opts)

  if command == "buffers" then
    opts.sort_mru = true
    opts.sort_lastused = true
  end

  if not opts.cwd and opts.root ~= false then
    opts.cwd = Utils.root({ buf = opts.buf })
  end

  return function()
    require("fzf-lua")[command](opts)
  end
end

local function term_nav(dir)
  ---@param self snacks.terminal
  return function(self)
    return self:is_floating() and "<c-" .. dir .. ">" or vim.schedule(function()
      vim.cmd.wincmd(dir)
    end)
  end
end


require("lazy").setup({
  ui = { border = "rounded" },
  install = { colorscheme = "nordfox" },
  {
    "EdenEast/nightfox.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      groups = {
        all = {
          FloatBorder = { fg = "fg3", bg = "bg0" },
          FloatTitle = { fg = "syntax.func", bg = "bg0" },
        },
      },
    },
    config = function(_, opts)
      require("nightfox").setup(opts)
      vim.cmd.colorscheme("nordfox")
    end,
  },
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      bigfile = { enabled = true },
      terminal = {
        win = {
          keys = {
            nav_h = { "<C-h>", term_nav("h"), desc = "Go to Left Window", expr = true, mode = "t" },
            nav_j = { "<C-j>", term_nav("j"), desc = "Go to Lower Window", expr = true, mode = "t" },
            nav_k = { "<C-k>", term_nav("k"), desc = "Go to Upper Window", expr = true, mode = "t" },
            nav_l = { "<C-l>", term_nav("l"), desc = "Go to Right Window", expr = true, mode = "t" },
          },
        },
      },
      notifier = { enabled = true },
      input = { enabled = true },
      dashboard = {
        preset = {
          header = "███████╗██████╗ ██╗  ██╗███╗   ██╗██╗  ██╗ ██╗██╗███╗   ██╗\n" ..
              "██╔════╝██╔══██╗██║  ██║████╗  ██║██║ ██╔╝███║██║████╗  ██║\n" ..
              "█████╗  ██████╔╝███████║██╔██╗ ██║█████╔╝ ╚██║██║██╔██╗ ██║\n" ..
              "██╔══╝  ██╔══██╗╚════██║██║╚██╗██║██╔═██╗  ██║██║██║╚██╗██║\n" ..
              "██║     ██║  ██║     ██║██║ ╚████║██║  ██╗ ██║██║██║ ╚████║\n" ..
              "╚═╝     ╚═╝  ╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═╝╚═╝╚═╝  ╚═══╝\n",
          keys = {
            { icon = " ", key = "s", desc = "Restore Session", section = "session" },
            { icon = " ", key = "q", desc = "Quit", action = ":qa" },
          },
        },
        sections = {
          { section = "header" },
          { section = "keys", padding = 1 },
          { icon = " ", title = "Recent Files", section = "recent_files", limit = 8, indent = 2, padding = 1 },
          { icon = " ", title = "Projects", section = "projects", limit = 6, indent = 2, padding = 1 },
          { section = "startup" },
        },
      },
      indent = {
        indent = { enabled = false },
        animate = { enabled = false },
        chunk = { enabled = true, char = { corner_top = "╭", corner_bottom = "╰" } },
      },
      statuscolumn = { enabled = true, folds = { open = true, git_hl = true } },
      words = { enabled = true },
    },
  },
  {
    "neovim/nvim-lspconfig",
    config = function(_, _) end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
  },
  {
    "ibhagwan/fzf-lua",
    cmd = "FzfLua",
    event = "VeryLazy",
    opts = function(_, opts)
      local fzf = require("fzf-lua")
      local config = fzf.config
      local actions = fzf.actions

      -- Quickfix
      config.defaults.keymap.fzf["ctrl-q"] = "select-all+accept"
      config.defaults.keymap.fzf["ctrl-u"] = "half-page-up"
      config.defaults.keymap.fzf["ctrl-d"] = "half-page-down"
      config.defaults.keymap.fzf["ctrl-x"] = "jump"
      config.defaults.keymap.fzf["ctrl-f"] = "preview-page-down"
      config.defaults.keymap.fzf["ctrl-b"] = "preview-page-up"
      config.defaults.keymap.builtin["<c-f>"] = "preview-page-down"
      config.defaults.keymap.builtin["<c-b>"] = "preview-page-up"

      -- Toggle root dir / cwd
      config.defaults.actions.files["ctrl-r"] = function(_, ctx)
        local o = vim.deepcopy(ctx.__call_opts)
        o.root = o.root == false
        o.buf = ctx.__CTX.bufnr

        o.cwd = o.root and Utils.root({ buf = o.buf }) or nil
        require("fzf-lua")[ctx.__INFO.cmd](o)
      end
      config.defaults.actions.files["alt-c"] = config.defaults.actions.files["ctrl-r"]
      config.set_action_helpstr(config.defaults.actions.files["ctrl-r"], "toggle-root-dir")

      local img_previewer ---@type string[]?
      for _, v in ipairs({
        { cmd = "ueberzug", args = {} },
        { cmd = "chafa",    args = { "{file}", "--format=symbols" } },
        { cmd = "viu",      args = { "-b" } },
      }) do
        if vim.fn.executable(v.cmd) == 1 then
          img_previewer = vim.list_extend({ v.cmd }, v.args)
          break
        end
      end

      return {
        "default-title",
        fzf_colors = true,
        fzf_opts = {
          ["--no-scrollbar"] = true,
        },
        defaults = {
          -- formatter = "path.filename_first",
          formatter = "path.dirname_first",
        },
        previewers = {
          builtin = {
            extensions = {
              ["png"] = img_previewer,
              ["jpg"] = img_previewer,
              ["jpeg"] = img_previewer,
              ["gif"] = img_previewer,
              ["webp"] = img_previewer,
            },
            ueberzug_scaler = "fit_contain",
          },
        },
        winopts = {
          width = 0.8,
          height = 0.8,
          row = 0.5,
          col = 0.5,
          preview = {
            scrollchars = { "┃", "" },
          },
        },
        files = {
          cwd_prompt = false,
          actions = {
            ["alt-i"] = { actions.toggle_ignore },
            ["alt-h"] = { actions.toggle_hidden },
          },
        },
        grep = {
          actions = {
            ["alt-i"] = { actions.toggle_ignore },
            ["alt-h"] = { actions.toggle_hidden },
          },
        },
        lsp = {
          symbols = {
            symbol_hl = function(s)
              return "TroubleIcon" .. s
            end,
            symbol_fmt = function(s)
              return s:lower() .. "\t"
            end,
            child_prefix = false,
          },
          code_actions = {
            previewer = vim.fn.executable("delta") == 1 and "codeaction_native" or "codeaction",
          },
        },
      }
    end,
    config = function(_, opts)
      if opts[1] == "default-title" then
        -- use the same prompt for all pickers for profile `default-title` and
        -- profiles that use `default-title` as base profile
        local function fix(t)
          t.prompt = t.prompt ~= nil and " " or nil
          for _, v in pairs(t) do
            if type(v) == "table" then
              fix(v)
            end
          end
          return t
        end
        opts = vim.tbl_deep_extend("force", fix(require("fzf-lua.profiles.default-title")), opts)
        opts[1] = nil
      end
      require("fzf-lua").setup(opts)
      require("fzf-lua").register_ui_select()
    end,
    keys = {
      {
        "<c-j>",
        "<c-j>",
        ft = "fzf",
        mode = "t",
        nowait = true,
      },
      {
        "<c-k>",
        "<c-k>",
        ft = "fzf",
        mode = "t",
        nowait = true,
      },

      { "<leader>,",       fzf_pick("buffers"),                       desc = "Switch Buffer" },
      { "<leader>/",       fzf_pick("live_grep"),                     desc = "Grep (root)" },
      { "<leader>:",       fzf_pick("command_history"),               desc = "Command history" },
      { "<leader><space>", fzf_pick("files"),                         desc = "Find files (root)" },
      -- find
      { "<leader>fb",      fzf_pick("buffers"),                       desc = "Buffers" },
      { "<leader>ff",      fzf_pick("files"),                         desc = "Find files (root)" },
      { "<leader>fF",      fzf_pick("files", { root = false }),       desc = "Find files (cwd)" },
      { "<leader>fg",      fzf_pick("git_files"),                     desc = "Find files (git-files)" },
      { "<leader>fr",      fzf_pick("oldfiles"),                      desc = "Recent" },
      { "<leader>fR",      fzf_pick("oldfiles", { root = false }),    desc = "Recent (all)" },
      -- git
      { "<leader>gc",      fzf_pick("git_commits"),                   desc = "Commits" },
      { "<leader>gs",      fzf_pick("git_status"),                    desc = "Status" },
      -- search
      { '<leader>s"',      fzf_pick("registers"),                     desc = "Registers" },
      { "<leader>sa",      fzf_pick("autocmds"),                      desc = "Auto commands" },
      { "<leader>sb",      fzf_pick("grep_curbuf"),                   desc = "Buffer" },
      { "<leader>sc",      fzf_pick("command_history"),               desc = "Command history" },
      { "<leader>sC",      fzf_pick("commands"),                      desc = "Commands" },
      { "<leader>sd",      fzf_pick("diagnostics_document"),          desc = "Document diagnostics" },
      { "<leader>sD",      fzf_pick("diagnostics_workspace"),         desc = "Workspace diagnostics" },
      { "<leader>sg",      fzf_pick("live_grep"),                     desc = "Grep (root)" },
      { "<leader>sG",      fzf_pick("live_grep", { root = false }),   desc = "Grep (cwd)" },
      { "<leader>sh",      fzf_pick("help_tags"),                     desc = "Help pages" },
      { "<leader>sH",      fzf_pick("highlights"),                    desc = "Search highlight groups" },
      { "<leader>sj",      fzf_pick("jumps"),                         desc = "Jumplist" },
      { "<leader>sk",      fzf_pick("keymaps"),                       desc = "Keymaps" },
      { "<leader>sl",      fzf_pick("loclist"),                       desc = "Location list" },
      { "<leader>sM",      fzf_pick("man_pages"),                     desc = "Man pages" },
      { "<leader>sm",      fzf_pick("marks"),                         desc = "Jump to mark" },
      { "<leader>sR",      fzf_pick("resume"),                        desc = "Resume" },
      { "<leader>sq",      fzf_pick("quickfix"),                      desc = "Quickfix List" },
      { "<leader>sw",      fzf_pick("grep_cword"),                    desc = "Word (root)" },
      { "<leader>sW",      fzf_pick("grep_cword", { root = false }),  desc = "Word (cwd)" },
      { "<leader>sw",      fzf_pick("grep_visual"),                   desc = "Selection (root)",        mode = "v" },
      { "<leader>sW",      fzf_pick("grep_visual", { root = false }), desc = "Selection (cwd)",         mode = "v" },
      { "<leader>uC",      fzf_pick("colorschemes"),                  desc = "Colorscheme with preview" },
    },
  },
  {
    "saghen/blink.cmp",

    -- use a release tag to download pre-built binaries
    version = "*",
    -- AND/OR build from source, requires nightly: https://rust-lang.github.io/rustup/concepts/channels.html#working-with-nightly-rust
    -- build = 'cargo build --release',
    -- If you use nix, you can build from source using latest nightly rust with:
    -- build = 'nix run .#build-plugin',

    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      -- 'default' for mappings similar to built-in completion
      -- 'super-tab' for mappings similar to vscode (tab to accept, arrow keys to navigate)
      -- 'enter' for mappings similar to 'super-tab' but with 'enter' to accept
      -- See the full "keymap" documentation for information on defining your own keymap.
      keymap = {
        ["<c-space>"] = { "accept", "fallback" },
        ["<c-b>"] = { "scroll_documentation_up", "fallback" },
        ["<c-f>"] = { "scroll_documentation_down", "fallback" },
        ["<c-k>"] = { "cancel", "fallback" },
        ["<cr>"] = { "accept", "fallback" },
        ["<s-tab>"] = { "select_prev", "fallback" },
        ["<tab>"] = { "select_next", "fallback" },
      },

      appearance = {
        -- Sets the fallback highlight groups to nvim-cmp's highlight groups
        -- Useful for when your theme doesn't support blink.cmp
        -- Will be removed in a future release
        use_nvim_cmp_as_default = true,
        -- Set to 'mono' for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
        -- Adjusts spacing to ensure icons are aligned
        nerd_font_variant = "normal",
      },

      completion = {
        list = {
          selection = { preselect = false },
        },
        accept = {
          auto_brackets = { enabled = true },
        },
        menu = {
          border = "rounded",
          draw = {
            columns = {
              { "label",     "label_description", gap = 1 },
              { "kind_icon", "kind" },
            },
          },
        },
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 200,
          window = {
            border = "rounded",
          },
        },
      },

      cmdline = {

        keymap = {
          ["<cr>"] = { "accept", "fallback" },
        },
        completion = {
          ghost_text = { enabled = false },
          menu = { auto_show = true },
          list = { selection = { preselect = false } },
        },
      },

      signature = {
        enabled = true,
        window = { border = "rounded" },
      },

      -- Default list of enabled providers defined so that you can extend it
      -- elsewhere in your config, without redefining it, due to `opts_extend`
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
    },
    opts_extend = { "sources.default" },
  },
  {
    "echasnovski/mini.icons",
    lazy = true,
    opts = {
      file = {
        [".keep"] = { glyph = "󰊢", hl = "MiniIconsGrey" },
        ["devcontainer.json"] = { glyph = "", hl = "MiniIconsAzure" },
      },
      filetype = {
        dotenv = { glyph = "", hl = "MiniIconsYellow" },
      },
    },
    init = function()
      package.preload["nvim-web-devicons"] = function()
        require("mini.icons").mock_nvim_web_devicons()
        return package.loaded["nvim-web-devicons"]
      end
    end,
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts_extend = { "spec" },
    opts = {
      preset = "helix",
      spec = {
        {
          mode = { "n", "v" },
          { "<leader><tab>", group = "tabs" },
          { "<leader>c", group = "code" },
          { "<leader>d", group = "debug" },
          { "<leader>dp", group = "profiler" },
          { "<leader>f", group = "file/find" },
          { "<leader>g", group = "git" },
          { "<leader>gh", group = "hunks" },
          { "<leader>q", group = "quit/session" },
          { "<leader>s", group = "search" },
          { "<leader>u", group = "ui", icon = { icon = "󰙵 ", color = "cyan" } },
          { "<leader>x", group = "diagnostics/quickfix", icon = { icon = "󱖫 ", color = "green" } },
          { "[", group = "prev" },
          { "]", group = "next" },
          { "g", group = "goto" },
          { "gs", group = "surround" },
          { "z", group = "fold" },
          {
            "<leader>b",
            group = "buffer",
            expand = function()
              return require("which-key.extras").expand.buf()
            end,
          },
          {
            "<leader>w",
            group = "windows",
            proxy = "<c-w>",
            expand = function()
              return require("which-key.extras").expand.win()
            end,
          },
          -- better descriptions
          { "gx", desc = "Open with system app" },
        },
      },
    },
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Buffer Keymaps (which-key)",
      },
      {
        "<c-w><space>",
        function()
          require("which-key").show({ keys = "<c-w>", loop = true })
        end,
        desc = "Window Hydra Mode (which-key)",
      },
    },
  },
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    vscode = true,
    opts = {
      ---@type table<string, Flash.Config>
      modes = {
        char = {
          keys = { "f", "F", "t", "T" },
        },
      },
    },
    -- stylua: ignore
    keys = {
      { "s",     mode = { "n", "x", "o" }, function() require("flash").jump() end,              desc = "Flash" },
      { "S",     mode = { "n", "o", "x" }, function() require("flash").treesitter() end,        desc = "Flash Treesitter" },
      { "r",     mode = "o",               function() require("flash").remote() end,            desc = "Remote Flash" },
      { "R",     mode = { "o", "x" },      function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
      { "<c-s>", mode = { "c" },           function() require("flash").toggle() end,            desc = "Toggle Flash Search" },
    },
  },
  {
    "b0o/incline.nvim",
    event = "VeryLazy",
    opts = {
      ignore = {
        filetypes = {
          "alpha",
          "dashboard",
          "lazy",
          "mason",
          "NvimTree",
          "neo-tree",
          "Outline",
          "toggleterm",
          "Trouble",
        },
      },
      render = function(props)
        local devicons = require("nvim-web-devicons")

        local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(props.buf), ":t")
        if filename == "" then
          filename = "[No Name]"
        end
        local ft_icon, ft_color = devicons.get_icon_color(filename)

        local function get_git_diff()
          local icons = { removed = " ", changed = " ", added = " " }
          local signs = vim.b[props.buf].gitsigns_status_dict
          local labels = {}
          if signs == nil then
            return labels
          end
          for name, icon in pairs(icons) do
            if tonumber(signs[name]) and signs[name] > 0 then
              table.insert(labels, { " " .. icon .. signs[name], group = "Diff" .. name })
            end
          end
          if #labels > 0 then
            table.insert(labels, 1, { " │" })
          end
          return labels
        end

        local function get_diagnostic_label()
          local icons = { error = " ", warn = " ", info = " ", hint = " " }
          local label = {}

          for severity, icon in pairs(icons) do
            local n = #vim.diagnostic.get(props.buf, { severity = vim.diagnostic.severity[string.upper(severity)] })
            if n > 0 then
              table.insert(label, { " " .. icon .. n, group = "DiagnosticSign" .. severity })
            end
          end
          if #label > 0 then
            table.insert(label, 1, { " │" })
          end
          return label
        end

        local modified = vim.bo[props.buf].modified

        return {
          { ft_icon and (ft_icon .. " ") or "", guifg = ft_color, guibg = "None" },
          { (modified and "•" or "") .. filename, gui = modified and "bold,italic" or "bold" },
          { get_diagnostic_label() },
          { get_git_diff() },
        }
      end,
    },
  },
})
