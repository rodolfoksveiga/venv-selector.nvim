local picker_base = require 'venv-selector.pickers.base'
local config = require 'venv-selector.config'
local utils = require 'venv-selector.utils'

local M = setmetatable({}, { __index = picker_base })

function M.show_results()
  local finders = require 'telescope.finders'
  local actions_state = require 'telescope.actions.state'
  local entry_display = require 'telescope.pickers.entry_display'

  M.prepare_results()
  local displayer = entry_display.create {
    separator = ' ',
    items = {
      { width = 2 },
      { width = 0.95 },
    },
  }

  local finder = finders.new_table {
    results = M.results,
    entry_maker = function(entry)
      entry.value = entry.path
      entry.ordinal = entry.path
      entry.display = function(e)
        return displayer {
          { e.icon },
          { e.path },
        }
      end
      return entry
    end,
  }

  local bufnr = vim.api.nvim_get_current_buf()
  local picker = actions_state.get_current_picker(bufnr)
  if picker ~= nil then
    picker:refresh(finder, { reset_prompt = true })
  end
end

function M.open()
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values
  local pickers = require 'telescope.pickers'
  local actions_state = require 'telescope.actions.state'
  local actions = require 'telescope.actions'
  local entry_display = require 'telescope.pickers.entry_display'

  if M.should_use_cache() then
    utils.dbg 'Using cached results.'
    return M._show_picker()
  end

  local venv = require 'venv-selector.venv'
  venv.load()
end

function M._show_picker()
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values
  local pickers = require 'telescope.pickers'
  local actions_state = require 'telescope.actions.state'
  local actions = require 'telescope.actions'
  local entry_display = require 'telescope.pickers.entry_display'

  local displayer = entry_display.create {
    separator = ' ',
    items = {
      { width = 2 },
      { width = 0.95 },
    },
  }

  local finder = finders.new_table {
    results = M.results,
    entry_maker = function(entry)
      entry.value = entry.path
      entry.ordinal = entry.path
      entry.display = function(e)
        return displayer {
          { e.icon },
          { e.path },
        }
      end
      return entry
    end,
  }

  local opts = {
    prompt_title = M.get_title(),
    finder = finder,
    layout_strategy = 'horizontal',
    layout_config = {
      height = 0.4,
      width = 120,
      prompt_position = 'top',
    },
    cwd = require('telescope.utils').buffer_dir(),
    sorting_strategy = 'ascending',
    sorter = conf.file_sorter {},
    attach_mappings = function(bufnr, map)
      map('i', '<cr>', function()
        local selection = actions_state.get_selected_entry()
        if selection then
          M.activate_venv(selection)
        end
        actions.close(bufnr)
      end)

      map('i', '<C-r>', function()
        M.remove_results()
        local picker = actions_state.get_current_picker(bufnr)
        picker:refresh(finder, { reset_prompt = true })
        vim.defer_fn(function()
          local venv = require 'venv-selector.venv'
          venv.load { force_refresh = true }
        end, 10)
      end)

      return true
    end,
  }

  pickers.new({}, opts):find()
end

return M
