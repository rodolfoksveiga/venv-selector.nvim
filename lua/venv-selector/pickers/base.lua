-- lua/venv-selector/picker_base.lua
local utils = require 'venv-selector.utils'
local config = require 'venv-selector.config'

local M = {}

M.results = {}

-- Common functionality shared by all pickers
function M.prepare_results()
  local hash = {}
  local res = {}

  for _, v in ipairs(M.results) do
    if not hash[v.path] then
      res[#res + 1] = v
      hash[v.path] = true
    end
  end

  M.results = res
  utils.dbg('There are ' .. utils.tablelength(M.results) .. ' results to show.')
end

function M.remove_results()
  M.results = {}
  utils.dbg 'Removed picker results.'
end

-- Gets called on results from the async search and adds the findings
function M.on_read(err, data)
  if err then
    utils.dbg('Error:' .. err)
  end

  if data then
    local rows = vim.split(data, '\n')
    for _, row in pairs(rows) do
      if row ~= '' then
        utils.dbg('Found venv in parent search: ' .. row)
        table.insert(M.results, { icon = '󰅬', path = utils.remove_last_slash(row), source = 'Search' })
      end
    end
  end
end

-- Common venv activation logic
function M.activate_venv(selected_entry)
  if not selected_entry then
    utils.notify 'No environment selected'
    return
  end

  local venv = require 'venv-selector.venv'

  utils.dbg('Activating venv: ' .. selected_entry.value)
  venv.set_venv_and_system_paths(selected_entry)
  venv.cache_venv(selected_entry)

  -- Verify activation
  if venv.current_venv then
    utils.notify('Successfully activated: ' .. venv.current_venv)
  else
    utils.notify 'Failed to activate virtual environment'
  end
end

-- Get picker title with refresh hint if needed
function M.get_title()
  local title = 'Virtual environments'
  if config.settings.auto_refresh == false then
    title = title .. ' (ctrl-r to refresh)'
  end
  return title
end

-- Check if we should use cached results
function M.should_use_cache()
  return config.settings.auto_refresh == false and next(M.results) ~= nil
end

return M
