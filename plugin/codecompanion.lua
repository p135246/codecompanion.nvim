if vim.g.loaded_codecompanion then
  return
end
vim.g.loaded_codecompanion = true

if vim.fn.has("nvim-0.10.0") == 0 then
  return vim.notify("CodeCompanion.nvim requires Neovim 0.10.0+", vim.log.levels.ERROR)
end

local config = require("codecompanion.config")
local api = vim.api

-- Set the highlight groups
api.nvim_set_hl(0, "CodeCompanionChatHeader", { link = "@markup.heading.2.markdown", default = true })
api.nvim_set_hl(0, "CodeCompanionChatSeparator", { link = "@punctuation.special.markdown", default = true })
api.nvim_set_hl(0, "CodeCompanionChatTokens", { link = "Comment", default = true })
api.nvim_set_hl(0, "CodeCompanionChatTool", { link = "Special", default = true })
api.nvim_set_hl(0, "CodeCompanionChatToolGroup", { link = "Constant", default = true })
api.nvim_set_hl(0, "CodeCompanionChatVariable", { link = "Identifier", default = true })
api.nvim_set_hl(0, "CodeCompanionVirtualText", { link = "Comment", default = true })

-- Setup syntax highlighting for the chat buffer
local group = "codecompanion.syntax"
api.nvim_create_augroup(group, { clear = true })
api.nvim_create_autocmd("FileType", {
  pattern = "codecompanion",
  group = group,
  callback = vim.schedule_wrap(function()
    vim.iter(config.strategies.chat.variables):each(function(name, var)
      vim.cmd.syntax('match CodeCompanionChatVariable "#' .. name .. '"')
      if var.opts and var.opts.has_params then
        vim.cmd.syntax('match CodeCompanionChatVariable "#' .. name .. '{[^}]*}"')
      end
    end)
    vim
      .iter(config.strategies.chat.tools)
      :filter(function(name)
        return name ~= "groups" and name ~= "opts"
      end)
      :each(function(name, _)
        vim.cmd.syntax('match CodeCompanionChatTool "@' .. name .. '"')
      end)
    vim.iter(config.strategies.chat.tools.groups):each(function(name, _)
      vim.cmd.syntax('match CodeCompanionChatToolGroup "@' .. name .. '"')
    end)
  end),
})

-- Set the diagnostic namespace for the chat buffer settings
config.INFO_NS = api.nvim_create_namespace("CodeCompanion-info")
config.ERROR_NS = api.nvim_create_namespace("CodeCompanion-error")

local diagnostic_config = {
  underline = false,
  virtual_text = {
    spacing = 2,
    severity = { min = vim.diagnostic.severity.INFO },
  },
  signs = false,
}
vim.diagnostic.config(diagnostic_config, config.INFO_NS)
vim.diagnostic.config(diagnostic_config, config.ERROR_NS)

-- Setup completion for blink.cmp and cmp
local has_cmp, cmp = pcall(require, "cmp")
local has_blink, blink = pcall(require, "blink.cmp")
local has_coc = vim.fn.exists("*coc#rpc#ready") == 1
if has_blink then
  pcall(function()
    local add_provider = blink.add_source_provider or blink.add_provider
    add_provider("codecompanion", {
      name = "CodeCompanion",
      module = "codecompanion.providers.completion.blink",
      enabled = true,
      score_offset = 10,
    })
  end)
  pcall(function()
    blink.add_filetype_source("codecompanion", "codecompanion")
  end)
  -- We need to check for blink alongside cmp as blink.compat has a module that
  -- is detected by a require("cmp") call and a lot of users have it installed
  -- Reference: https://github.com/olimorris/codecompanion.nvim/discussions/501
elseif has_cmp and not has_blink then
  local completion = "codecompanion.providers.completion.cmp"
  cmp.register_source("codecompanion_models", require(completion .. ".models").new(config))
  cmp.register_source("codecompanion_slash_commands", require(completion .. ".slash_commands").new(config))
  cmp.register_source("codecompanion_tools", require(completion .. ".tools").new(config))
  cmp.register_source("codecompanion_variables", require(completion .. ".variables").new())
  cmp.setup.filetype("codecompanion", {
    enabled = true,
    sources = vim.list_extend({
      { name = "codecompanion_models" },
      { name = "codecompanion_slash_commands" },
      { name = "codecompanion_tools" },
      { name = "codecompanion_variables" },
    }, cmp.get_config().sources),
  })
elseif has_coc then
  local completion = require("codecompanion.providers.completion.coc")
  _G.codecompanion_coc_init = completion.init
  _G.codecompanion_coc_complete = completion.complete
  _G.codecompanion_coc_execute = completion.execute
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = completion.ensure_autoload_file
  })
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "codecompanion",
    callback = completion.ensure_buffer_attached
  })
end

-- Capture the last terminal buffer
_G.codecompanion_last_terminal = nil
api.nvim_create_autocmd("TermEnter", {
  desc = "Capture the last terminal buffer",
  callback = function()
    local bufnr = api.nvim_get_current_buf()
    if vim.bo[bufnr].buftype == "terminal" then
      _G.codecompanion_last_terminal = bufnr
    end
  end,
})

-- Register the Tree-sitter filetype
vim.treesitter.language.register("markdown", "codecompanion")
