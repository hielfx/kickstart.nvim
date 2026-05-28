return {
  'git-ai-shim',
  dir = vim.fn.stdpath 'config' .. '/lua/custom/git-ai',
  lazy = false, -- autocmds must register at startup, before the first :w
  config = function()
    require('custom.git-ai').setup()
  end,
}
