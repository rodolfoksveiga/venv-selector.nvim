local picker_base = require 'venv-selector.pickers.base'
local config = require 'venv-selector.config'
local utils = require 'venv-selector.utils'

local M = setmetatable({}, { __index = picker_base })

M.fzf_instance = nil

-- Convert results to fzf-lua format (simple strings with icons)
function M.format_results()
  M.prepare_results()
  local formatted = {}

  for i, entry in ipairs(M.results) do
    local display_line = entry.icon .. ' ' .. entry.path
    table.insert(formatted, display_line)
    utils.dbg('Formatted result ' .. i .. ': ' .. display_line)
  end

  return formatted
end

function M.show_results()
  M.prepare_results()
  utils.dbg('Prepared ' .. utils.tablelength(M.results) .. ' results for fzf display')

  -- If we have a pending fzf instance, show it now with all results
  if M.fzf_instance then
    M.fzf_instance()
    M.fzf_instance = nil
  end
end

function M.open()
  if M.should_use_cache() then
    utils.dbg 'Using cached results.'
    return M._show_picker()
  end

  M._refresh_and_show()
end

function M._show_picker()
  local fzf = require 'fzf-lua'
  local formatted_results = M.format_results()

  if #formatted_results == 0 then
    utils.notify 'No virtual environments found'
    return
  end

  utils.dbg('Showing ' .. #formatted_results .. ' results in fzf')

  local opts = {
    prompt = M.get_title() .. '> ',
    winopts = {
      height = 0.4,
      width = 0.4,
      preview = { hidden = 'hidden' },
    },
    fzf_opts = {
      ['--layout'] = 'reverse',
      ['--info'] = 'inline',
      ['--height'] = '100%',
    },
    actions = {
      ['default'] = function(selected, opts)
        utils.dbg 'fzf default action triggered'
        M._handle_selection(selected)
      end,
      ['ctrl-r'] = function(selected, opts)
        utils.dbg 'fzf refresh action triggered'
        return M.open()
      end,
    },
  }

  fzf.fzf_exec(formatted_results, opts)
end

function M._refresh_and_show()
  M.remove_results()

  -- Create a deferred function to show fzf after loading
  M.fzf_instance = function()
    M._show_picker()
  end

  -- Start loading results
  local venv = require 'venv-selector.venv'
  venv.load { force_refresh = true }
end

function M._handle_selection(selected)
  if selected and #selected > 0 then
    local selected_line = selected[1]
    utils.dbg('User selected line: ' .. selected_line)

    -- Find matching entry in results
    local selected_entry = nil
    for _, entry in ipairs(M.results) do
      local formatted_line = entry.icon .. ' ' .. entry.path
      if formatted_line == selected_line then
        selected_entry = { value = entry.path }
        break
      end
    end

    if selected_entry then
      M.activate_venv(selected_entry)
    else
      utils.notify 'Could not find selected environment in results'
    end
  end
end

return M
