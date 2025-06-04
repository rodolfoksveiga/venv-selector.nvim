local config = require 'venv-selector.config'

local M = {}

-- Cache for picker instances
local picker_cache = {}

function M.get_picker()
  local picker_type = config.settings.picker

  -- Normalize picker type
  if picker_type == 'fzf' or picker_type == 'fzf-lua' then
    picker_type = 'fzf'
  else
    picker_type = 'telescope' -- default
  end

  -- Return cached instance if available
  if picker_cache[picker_type] then
    return picker_cache[picker_type]
  end

  -- Create new picker instance
  local picker = require('venv-selector.pickers.' .. picker_type)
  picker_cache[picker_type] = picker

  return picker
end

-- Clear cache (useful for testing or config changes)
function M.clear_cache()
  picker_cache = {}
end

return M
