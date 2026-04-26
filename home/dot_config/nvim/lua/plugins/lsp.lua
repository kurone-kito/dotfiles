return {
  -- LSP server configurations
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "mason-org/mason.nvim",
      "mason-org/mason-lspconfig.nvim",
      { "j-hui/fidget.nvim", opts = {} },
    },
    config = function()
      require("mason").setup()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "ts_ls",
          "eslint",
          "html",
          "cssls",
          "jsonls",
          "tailwindcss",
          "lua_ls",
        },
      })

      -- Capabilities from blink.cmp
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      local ok, blink = pcall(require, "blink.cmp")
      if ok then
        capabilities = blink.get_lsp_capabilities(capabilities)
      end

      -- On-attach keybindings
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("LspKeymaps", { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = event.buf, desc = desc })
          end
          map("gd", vim.lsp.buf.definition, "Go to definition")
          map("gr", vim.lsp.buf.references, "References")
          map("gI", vim.lsp.buf.implementation, "Go to implementation")
          map("gy", vim.lsp.buf.type_definition, "Type definition")
          map("K", vim.lsp.buf.hover, "Hover documentation")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("<leader>cr", vim.lsp.buf.rename, "Rename symbol")
        end,
      })

      -- Configure individual servers
      local lspconfig = require("lspconfig")

      -- Use vim.lsp.config for Nvim 0.11+ where possible,
      -- fall back to lspconfig for compatibility
      local servers = {
        ts_ls = {},
        eslint = {},
        html = { capabilities = capabilities },
        cssls = { capabilities = capabilities },
        jsonls = {
          capabilities = capabilities,
          settings = {
            json = {
              validate = { enable = true },
            },
          },
        },
        tailwindcss = {},
        lua_ls = {
          settings = {
            Lua = {
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
            },
          },
        },
      }

      for server, config in pairs(servers) do
        config.capabilities = vim.tbl_deep_extend(
          "force",
          capabilities,
          config.capabilities or {}
        )
        lspconfig[server].setup(config)
      end
    end,
  },

  -- Mason (standalone, lazy = false for path setup)
  {
    "mason-org/mason.nvim",
    cmd = "Mason",
    lazy = false,
    opts = {},
  },
}
