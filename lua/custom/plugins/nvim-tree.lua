return {
  'nvim-tree/nvim-tree.lua',
  version = '*',
  lazy = false,
  dependencies = {
    'nvim-tree/nvim-web-devicons',
  },
  config = function()
    require('nvim-tree').setup {}
  end,
  cmd = { 'NvimTreeToggle', 'NvimTreeOpen', 'NvimTreeFocus', 'NvimTreeFindFileToggle' },
  event = 'User DirOpened',
  keys = {
    { '<leader>e', '<cmd>NvimTreeToggle<cr>', desc = 'NvimTree [E]xplorer' },
  },
}
