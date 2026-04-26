return {
  -- Keybinding help
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>c", group = "code" },
        { "<leader>f", group = "find" },
        { "<leader>g", group = "git" },
        { "<leader>h", group = "hunk" },
      },
    },
  },

  -- Auto-close brackets and quotes
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    opts = {},
  },

  -- Comment toggle
  {
    "numToStr/Comment.nvim",
    keys = {
      { "gc", mode = { "n", "v" }, desc = "Toggle comment" },
      { "gb", mode = { "n", "v" }, desc = "Toggle block comment" },
    },
    opts = {},
  },

  -- Surround text objects
  {
    "kylechui/nvim-surround",
    event = "VeryLazy",
    opts = {},
  },

  -- File explorer
  {
    "stevearc/oil.nvim",
    keys = {
      { "<leader>e", "<cmd>Oil<CR>", desc = "File explorer" },
      { "-", "<cmd>Oil<CR>", desc = "File explorer" },
    },
    opts = {
      view_options = { show_hidden = true },
    },
  },
}
