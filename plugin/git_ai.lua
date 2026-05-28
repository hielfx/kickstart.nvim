-- git-ai Neovim known_human shim
-- Fires `git-ai checkpoint known_human` on BufWritePost so human edits get
-- proper attribution instead of falling through to untracked/"unknown".
-- Mirrors the VS Code extension's known-human-checkpoint-manager.ts contract.
--
-- Toggle:  vim.g.git_ai_enabled = false  (default true)
-- Debug:   vim.g.git_ai_debug   = true   (default false)
-- Binary:  vim.g.git_ai_bin     = "/path/to/git-ai"  (overrides auto-resolve)

if vim.g.loaded_git_ai then
  return
end
vim.g.loaded_git_ai = 1

if vim.g.git_ai_enabled == nil then
  vim.g.git_ai_enabled = true
end

local uv = vim.uv or vim.loop

local M = {
  debounce_ms = 500,
  timers = {}, -- [repo_root] = timer
  pending = {}, -- [repo_root] = { [abs_path] = true }
  repo_root_cache = {}, -- [dir] = root_or_false
  last_error = nil,
  last_fired = nil,
}

local function log(...)
  if vim.g.git_ai_debug then
    local parts = { '[git-ai]' }
    for _, v in ipairs { ... } do
      parts[#parts + 1] = tostring(v)
    end
    vim.schedule(function()
      vim.notify(table.concat(parts, ' '), vim.log.levels.INFO)
    end)
  end
end

local function resolve_binary()
  if vim.g.git_ai_bin and vim.g.git_ai_bin ~= '' then
    return vim.g.git_ai_bin
  end
  local env_bin = vim.env.GIT_AI_BIN
  if env_bin and env_bin ~= '' then
    return env_bin
  end
  local home_bin = vim.fn.expand '~/.git-ai/bin/git-ai'
  if vim.fn.executable(home_bin) == 1 then
    return home_bin
  end
  local on_path = vim.fn.exepath 'git-ai'
  if on_path and on_path ~= '' then
    return on_path
  end
  return nil
end

local function find_repo_root(dir)
  local cached = M.repo_root_cache[dir]
  if cached ~= nil then
    return cached or nil
  end
  local result = vim.fn.systemlist { 'git', '-C', dir, 'rev-parse', '--show-toplevel' }
  if vim.v.shell_error ~= 0 or #result == 0 then
    M.repo_root_cache[dir] = false
    return nil
  end
  local root = result[1]
  M.repo_root_cache[dir] = root
  return root
end

local function should_skip(bufnr, path)
  if not path or path == '' then
    return true
  end
  if vim.bo[bufnr].buftype ~= '' then
    return true
  end
  local ok, name = pcall(vim.api.nvim_buf_get_name, bufnr)
  if not ok or name == '' then
    return true
  end
  -- skip anything inside a .git/ directory
  if path:match '/%.git/' or path:match '\\%.git\\' then
    return true
  end
  return false
end

local function read_buffer_contents(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, '\n')
  if vim.bo[bufnr].endofline ~= false then
    content = content .. '\n'
  end
  return content
end

local function fire(repo_root)
  local pending = M.pending[repo_root] or {}
  M.pending[repo_root] = nil

  local bin = resolve_binary()
  if not bin then
    M.last_error = 'git-ai binary not found (set vim.g.git_ai_bin or $GIT_AI_BIN)'
    log(M.last_error)
    return
  end

  local edited_filepaths = {}
  local dirty_files = {}

  for path, bufnr in pairs(pending) do
    -- bufnr may be nil if buffer was wiped between debounce schedule and fire
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
      edited_filepaths[#edited_filepaths + 1] = path
      dirty_files[path] = read_buffer_contents(bufnr)
    end
  end

  if #edited_filepaths == 0 then
    return
  end

  local payload = vim.json.encode {
    editor = 'neovim',
    editor_version = tostring(vim.version()),
    extension_version = '0.1.0-nvim-shim',
    cwd = repo_root,
    edited_filepaths = edited_filepaths,
    dirty_files = dirty_files,
  }

  log('firing known_human for', #edited_filepaths, 'file(s) in', repo_root)
  M.last_fired = { repo_root = repo_root, count = #edited_filepaths, at = os.time() }

  local ok, err = pcall(function()
    vim.system({ bin, 'checkpoint', 'known_human', '--hook-input', 'stdin' }, { stdin = payload, text = true, cwd = repo_root }, function(out)
      if out.code ~= 0 then
        M.last_error = string.format('exit=%d stderr=%s', out.code, (out.stderr or ''):sub(1, 500))
        log('checkpoint failed:', M.last_error)
      else
        M.last_error = nil
        log 'checkpoint ok'
      end
    end)
  end)
  if not ok then
    M.last_error = 'spawn failed: ' .. tostring(err)
    log(M.last_error)
  end
end

local function schedule(repo_root, abs_path, bufnr)
  M.pending[repo_root] = M.pending[repo_root] or {}
  M.pending[repo_root][abs_path] = bufnr

  local timer = M.timers[repo_root]
  if timer then
    timer:stop()
    timer:close()
  end
  timer = uv.new_timer()
  M.timers[repo_root] = timer
  timer:start(
    M.debounce_ms,
    0,
    vim.schedule_wrap(function()
      if M.timers[repo_root] == timer then
        M.timers[repo_root] = nil
      end
      if timer and not timer:is_closing() then
        timer:close()
      end
      fire(repo_root)
    end)
  )
end

local group = vim.api.nvim_create_augroup('GitAiKnownHuman', { clear = true })

vim.api.nvim_create_autocmd('BufWritePost', {
  group = group,
  callback = function(args)
    if not vim.g.git_ai_enabled then
      return
    end
    local bufnr = args.buf
    local path = vim.api.nvim_buf_get_name(bufnr)
    if should_skip(bufnr, path) then
      return
    end

    local abs = vim.fn.fnamemodify(path, ':p')
    local dir = vim.fn.fnamemodify(abs, ':h')
    local root = find_repo_root(dir)
    if not root then
      return
    end

    schedule(root, abs, bufnr)
  end,
})

vim.api.nvim_create_autocmd('VimLeavePre', {
  group = group,
  callback = function()
    for root, timer in pairs(M.timers) do
      if timer and not timer:is_closing() then
        timer:stop()
        timer:close()
      end
      M.timers[root] = nil
    end
  end,
})

-- User commands -------------------------------------------------------------

vim.api.nvim_create_user_command('GitAiEnable', function()
  vim.g.git_ai_enabled = true
  vim.notify('[git-ai] enabled', vim.log.levels.INFO)
end, {})

vim.api.nvim_create_user_command('GitAiDisable', function()
  vim.g.git_ai_enabled = false
  vim.notify('[git-ai] disabled', vim.log.levels.INFO)
end, {})

vim.api.nvim_create_user_command('GitAiStatus', function()
  local bin = resolve_binary()
  local lines = {
    'git-ai Neovim shim',
    '  enabled : ' .. tostring(vim.g.git_ai_enabled),
    '  debug   : ' .. tostring(vim.g.git_ai_debug == true),
    '  binary  : ' .. (bin or '<not found>'),
  }
  if M.last_fired then
    lines[#lines + 1] = string.format('  last    : %d file(s) in %s @ %s', M.last_fired.count, M.last_fired.repo_root, os.date('%H:%M:%S', M.last_fired.at))
  end
  if M.last_error then
    lines[#lines + 1] = '  error   : ' .. M.last_error
  end
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end, {})

vim.api.nvim_create_user_command('GitAiCheckpoint', function()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  if should_skip(bufnr, path) then
    vim.notify('[git-ai] skipping (non-file or .git path)', vim.log.levels.WARN)
    return
  end
  local abs = vim.fn.fnamemodify(path, ':p')
  local dir = vim.fn.fnamemodify(abs, ':h')
  local root = find_repo_root(dir)
  if not root then
    vim.notify('[git-ai] not inside a git repo', vim.log.levels.WARN)
    return
  end
  M.pending[root] = M.pending[root] or {}
  M.pending[root][abs] = bufnr
  fire(root)
end, {})
