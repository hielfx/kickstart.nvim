return {
  'folke/persistence.nvim',
  event = 'BufReadPre', -- this will only start session saving when an actual file was opened
  opts = {
    -- add any custom options here
  },
  keys = {
    {
      '<leader>qs',
      function()
        require('persistence').load()
      end,
      mode = 'n',
      desc = 'Load the [S]ession for Current Directory',
    },
    {
      '<leader>qS',
      function()
        require('persistence').select()
      end,
      mode = 'n',
      desc = '[S]elect a Session to Load',
    },
    {
      '<leader>ql',
      function()
        require('persistence').load { last = true }
      end,
      mode = 'n',
      desc = 'Load the [L]ast Session',
    },
    {
      '<leader>qd',
      function()
        require('persistence').stop()
      end,
      mode = 'n',
      desc = "Stop Persistence => Session Won't Be Saved On Exit",
    },
  },
}
