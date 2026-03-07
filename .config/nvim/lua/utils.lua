local Self = {}

-- AUTOFORMAT
vim.g.autoformat = true

Self.autofmt = {}

---@param bufnr? integer
Self.autofmt.get = function(bufnr)
  if bufnr == nil or vim.b[bufnr].autoformat == nil then
    return vim.g.autoformat
  else
    return vim.b[bufnr].autoformat
  end
end

---@param global_state boolean
---@param buffer_state boolean
local function notify(global_state, buffer_state)
  local function make_line(name, state)
    local tick = "[" .. (state and "x" or " ") .. "]"
    local status = state and "**Enabled**" or "**Disabled**"
    return "- " .. tick .. " " .. name .. ": " .. status
  end

  local content = (
    "# Autoformat Status"
    .. "\n"
    .. make_line("Global", global_state)
    .. "\n"
    .. make_line("Buffer", buffer_state)
  )

  Snacks.notify[buffer_state and "info" or "warn"](
    content,
    { title = "Autoformat " .. (buffer_state and "Enabled" or "Disabled") }
  )
end

---@param state boolean
---@param bufnr integer
---@param global boolean
Self.autofmt.set = function(state, bufnr, global)
  if global then
    vim.g.autoformat = state
    vim.tbl_map(function(buf)
      vim.b[buf].autoformat = nil
    end, vim.api.nvim_list_bufs())
  else
    vim.b[bufnr].autoformat = state
  end
  notify(vim.g.autoformat, state)
end


-- ROOT
---@class Utils.root
---@overload fun(opts?: table): string
Self.root = setmetatable({}, {
  __call = function(m, ...)
    return m.get(...)
  end,
})

---@class LazyRoot
---@field paths string[]
---@field spec LazyRootSpec

---@alias LazyRootFn fun(buf: number): (string|string[])

---@alias LazyRootSpec string|string[]|LazyRootFn

---@type LazyRootSpec[]
Self.root.spec = { "lsp", { ".git", "lua" }, "cwd" }

Self.root.detectors = {}

function Self.root.detectors.cwd()
  return { vim.uv.cwd() }
end

function Self.root.detectors.lsp(buf)
  local bufpath = Self.root.bufpath(buf)
  if not bufpath then
    return {}
  end
  local roots = {} ---@type string[]
  local clients = vim.lsp.get_clients({ bufnr = buf })
  clients = vim.tbl_filter(function(client)
    return not vim.tbl_contains(vim.g.root_lsp_ignore or {}, client.name)
  end, clients)
  for _, client in pairs(clients) do
    local workspace = client.config.workspace_folders
    for _, ws in pairs(workspace or {}) do
      roots[#roots + 1] = vim.uri_to_fname(ws.uri)
    end
    if client.root_dir then
      roots[#roots + 1] = client.root_dir
    end
  end
  return vim.tbl_filter(function(path)
    path = Utils.norm(path)
    return path and bufpath:find(path, 1, true) == 1
  end, roots)
end

---@param patterns string[]|string
function Self.root.detectors.pattern(buf, patterns)
  patterns = type(patterns) == "string" and { patterns } or patterns
  local path = Self.root.bufpath(buf) or vim.uv.cwd()
  local pattern = vim.fs.find(function(name)
    for _, p in ipairs(patterns) do
      if name == p then
        return true
      end
      if p:sub(1, 1) == "*" and name:find(vim.pesc(p:sub(2)) .. "$") then
        return true
      end
    end
    return false
  end, { path = path, upward = true })[1]
  return pattern and { vim.fs.dirname(pattern) } or {}
end

function Self.root.bufpath(buf)
  return Self.root.realpath(vim.api.nvim_buf_get_name(assert(buf)))
end

function Self.root.cwd()
  return Self.root.realpath(vim.uv.cwd()) or ""
end

function Self.root.realpath(path)
  if path == "" or path == nil then
    return nil
  end
  path = vim.uv.fs_realpath(path) or path
  return Utils.norm(path)
end

---@param spec LazyRootSpec
---@return LazyRootFn
function Self.root.resolve(spec)
  if Self.root.detectors[spec] then
    return Self.root.detectors[spec]
  elseif type(spec) == "function" then
    return spec
  end
  return function(buf)
    return Self.root.detectors.pattern(buf, spec)
  end
end

---@param opts? { buf?: number, spec?: LazyRootSpec[], all?: boolean }
function Self.root.detect(opts)
  opts = opts or {}
  opts.spec = opts.spec or type(vim.g.root_spec) == "table" and vim.g.root_spec or Self.root.spec
  opts.buf = (opts.buf == nil or opts.buf == 0) and vim.api.nvim_get_current_buf() or opts.buf

  local ret = {} ---@type LazyRoot[]
  for _, spec in ipairs(opts.spec) do
    local paths = Self.root.resolve(spec)(opts.buf)
    paths = paths or {}
    paths = type(paths) == "table" and paths or { paths }
    local roots = {} ---@type string[]
    for _, p in ipairs(paths) do
      local pp = Self.root.realpath(p)
      if pp and not vim.tbl_contains(roots, pp) then
        roots[#roots + 1] = pp
      end
    end
    table.sort(roots, function(a, b)
      return #a > #b
    end)
    if #roots > 0 then
      ret[#ret + 1] = { spec = spec, paths = roots }
      if opts.all == false then
        break
      end
    end
  end
  return ret
end

---@type table<number, string>
Self.root.cache = {}

-- returns the root directory based on:
-- * lsp workspace folders
-- * lsp root_dir
-- * root pattern of filename of the current buffer
-- * root pattern of cwd
---@param opts? {normalize?:boolean, buf?:number}
---@return string
function Self.root.get(opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local ret = Self.root.cache[buf]
  if not ret then
    local roots = Self.root.detect({ all = false, buf = buf })
    ret = roots[1] and roots[1].paths[1] or vim.uv.cwd()
    Self.root.cache[buf] = ret
  end
  return ret
end

function Self.root.git()
  local root = Self.root.get()
  local git_root = vim.fs.find(".git", { path = root, upward = true })[1]
  local ret = git_root and vim.fn.fnamemodify(git_root, ":h") or root
  return ret
end

---@param opts? {hl_last?: string}
function Self.root.pretty_path(opts)
  return ""
end

-- NORM
Self.norm = function(path)
  if path:sub(1, 1) == "~" then
    local home = vim.uv.os_homedir()
    if home:sub(-1) == "\\" or home:sub(-1) == "/" then
      home = home:sub(1, -2)
    end
    path = home .. path:sub(2)
  end
  path = path:gsub("\\", "/"):gsub("/+", "/")
  return path:sub(-1) == "/" and path:sub(1, -2) or path
end

-- TERMINAL
Self.terminal = {
  toggle = function()
    Snacks.terminal.toggle()
  end,
}

return Self
