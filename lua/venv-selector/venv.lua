local system = require 'venv-selector.system'
local utils = require 'venv-selector.utils'
local config = require 'venv-selector.config'

local M = {}

M.current_python_path = nil
M.current_venv = nil
M.current_bin_path = nil
M.fd_handle = nil
M.path_to_search = nil

-- Add a completion counter to track async operations
M.pending_operations = 0

-- Get the appropriate picker module based on config
local function get_picker()
  return require('venv-selector.pickers.factory').get_picker()
end

function M.load(action)
  local act = action or {}

  local ready_for_new_search = M.fd_handle == nil or M.fd_handle:is_closing() == true
  if ready_for_new_search == false then
    utils.dbg 'Cannot start a new search while old one is running.'
    return
  end

  local buffer_dir = config.get_buffer_dir()
  M.pending_operations = 0

  -- Check if we're in a git repository
  local git_root = utils.find_git_root(buffer_dir)
  local in_git_repo = git_root ~= nil

  utils.dbg('Buffer dir: ' .. buffer_dir)
  if git_root then
    utils.dbg('Git root: ' .. git_root)
    utils.dbg 'In git repo: true'
  else
    utils.dbg 'In git repo: false'
  end

  -- Only search for parent venvs if search option is true
  if config.settings.search == true then
    if act.force_refresh == true then
      if M.path_to_search == nil then
        utils.dbg 'No previous search path when asked to refresh results.'
        M.path_to_search = utils.find_parent_dir(buffer_dir, config.settings.parents)
        M.find_parent_venvs(M.path_to_search)
      else
        utils.dbg('User refreshed results - buffer_dir is: ' .. buffer_dir)
        M.path_to_search = utils.find_parent_dir(buffer_dir, config.settings.parents)
        M.find_parent_venvs(M.path_to_search)
      end
    else
      M.path_to_search = utils.find_parent_dir(buffer_dir, config.settings.parents)
      M.find_parent_venvs(M.path_to_search)
    end
  else
    M.find_other_venvs(in_git_repo, git_root)
  end
end

-- This gets called as soon as the parent venv search is done.
function M.find_other_venvs(in_git_repo, git_root)
  in_git_repo = in_git_repo or false
  local picker = get_picker()

  -- Increment pending operations counter
  if config.settings.search_workspace == true then
    M.pending_operations = M.pending_operations + 1
  end
  if config.settings.search_venv_managers == true then
    M.pending_operations = M.pending_operations + 1
  end

  if config.settings.search_workspace == true then
    M.find_workspace_venvs(in_git_repo, git_root)
  end

  if config.settings.search_venv_managers == true then
    M.find_venv_manager_venvs(in_git_repo, git_root)
  end

  -- If no other operations are pending, show results immediately
  if M.pending_operations == 0 then
    picker.show_results()
  end
end

-- Look for workspace venvs, but filter them if we're in a git repo
function M.find_workspace_venvs(in_git_repo, git_root)
  vim.schedule(function()
    local picker = get_picker()
    local workspace_folders = M.list_pyright_workspace_folders()

    -- If we're in a git repo, filter workspace folders to only include those within the git root
    if in_git_repo and git_root and config.settings.respect_git_root ~= false then
      local filtered_folders = {}
      for _, folder in ipairs(workspace_folders) do
        if utils.starts_with(folder, git_root) then
          table.insert(filtered_folders, folder)
          utils.dbg('Including workspace folder within git repo: ' .. folder)
        else
          utils.dbg('Excluding workspace folder outside git repo: ' .. folder)
        end
      end
      workspace_folders = filtered_folders
    end

    local search_path_string = utils.create_fd_search_path_string(workspace_folders)
    if search_path_string:len() ~= 0 then
      local search_path_regexp = utils.create_fd_venv_names_regexp(config.settings.name)
      local cmd = config.settings.fd_binary_name
        .. " -HItd --absolute-path --color never '"
        .. search_path_regexp
        .. "' "
        .. search_path_string
      utils.dbg('Running search for workspace venvs with: ' .. cmd)
      local openPop = assert(io.popen(cmd, 'r'))

      for row in openPop:lines() do
        if row ~= '' then
          utils.dbg('Found venv in Workspace search: ' .. row)
          table.insert(picker.results, { icon = '', path = utils.remove_last_slash(row), source = 'Workspace' })
        end
      end

      openPop:close()
    else
      utils.dbg 'Found no workspaces to search for venvs (after git filtering).'
    end

    M.pending_operations = M.pending_operations - 1
    if M.pending_operations == 0 then
      picker.show_results()
    end
  end)
end

-- Look for venv manager venvs, but skip them if we're in a git repo
function M.find_venv_manager_venvs(in_git_repo, git_root)
  vim.schedule(function()
    local picker = get_picker()

    -- If we're in a git repo and respect_git_root is true, skip global venv managers
    if in_git_repo and git_root and config.settings.respect_git_root ~= false then
      utils.dbg('Skipping venv manager search because we are in git repository: ' .. git_root)
      M.pending_operations = M.pending_operations - 1
      if M.pending_operations == 0 then
        picker.show_results()
      end
      return
    end

    local paths = {
      config.settings.poetry_path,
      config.settings.pdm_path,
      config.settings.pipenv_path,
      config.settings.pyenv_path,
      config.settings.hatch_path,
      config.settings.venvwrapper_path,
      config.settings.anaconda_envs_path,
    }
    local search_path_string = utils.create_fd_search_path_string(paths)
    if search_path_string:len() ~= 0 then
      local cmd = config.settings.fd_binary_name
        .. ' . -HItd -tl --absolute-path --max-depth 1 --color never '
        .. search_path_string
        .. " --exclude '3.*.*'"
      utils.dbg('Running search for venv manager venvs with: ' .. cmd)
      local openPop = assert(io.popen(cmd, 'r'))

      for row in openPop:lines() do
        if row ~= '' then
          utils.dbg('Found venv in VenvManager search: ' .. row)
          table.insert(picker.results, { icon = '', path = utils.remove_last_slash(row), source = 'VenvManager' })
        end
      end

      openPop:close()

      -- If $CONDA_PREFIX is defined and exists, add the path as an existing venv
      if vim.fn.isdirectory(config.settings.anaconda_base_path) ~= 0 then
        table.insert(picker.results, {
          icon = '',
          path = utils.remove_last_slash(config.settings.anaconda_base_path .. '/'),
          source = 'VenvManager',
        })
      end
    else
      utils.dbg 'Found no venv manager directories to search for venvs.'
    end

    M.pending_operations = M.pending_operations - 1
    if M.pending_operations == 0 then
      picker.show_results()
    end
  end)
end

-- Start a search for venvs in all directories under the start_dir
-- Async function to search for venvs
function M.find_parent_venvs(parent_dir)
  local picker = get_picker()
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)
  if stdout == nil or stderr == nil then
    utils.dbg 'Failed to create pipes for fd process.'
    return
  end

  local venv_names = utils.create_fd_venv_names_regexp(config.settings.name)
  local fdconfig = {
    args = { '--absolute-path', '--color', 'never', '-E', '/proc', '-HItd', venv_names, parent_dir },
    stdio = { nil, stdout, stderr },
  }

  if config.settings.anaconda_base_path:len() > 0 then
    table.insert(fdconfig.args, '-E')
    table.insert(fdconfig.args, config.settings.anaconda_base_path)
  end

  if config.settings.anaconda_envs_path:len() > 0 then
    table.insert(fdconfig.args, '-E')
    table.insert(fdconfig.args, config.settings.anaconda_envs_path)
  end

  utils.dbg("Looking for parent venvs in '" .. parent_dir .. "' using the following parameters:")
  utils.dbg(fdconfig.args)

  -- Check if we're in a git repo and pass that info along
  local buffer_dir = config.get_buffer_dir()
  local git_root = utils.find_git_root(buffer_dir)
  local in_git_repo = git_root ~= nil

  M.fd_handle = vim.loop.spawn(
    config.settings.fd_binary_name,
    fdconfig,
    vim.schedule_wrap(function() -- on exit
      stdout:read_stop()
      stderr:read_stop()
      stdout:close()
      stderr:close()
      M.find_other_venvs(in_git_repo, git_root)
      M.fd_handle:close()
    end)
  )
  vim.loop.read_start(stdout, picker.on_read)
end

-- [Rest of the functions remain the same...]
function M.set_venv_and_system_paths(venv_row)
  utils.dbg 'Getting local system info...'
  local sys = system.get_info()
  utils.dbg(sys)
  local venv_path = venv_row.value
  local new_bin_path
  local venv_python

  if sys.python_parent_path:len() == 0 then
    new_bin_path = venv_path
    venv_python = new_bin_path .. sys.path_sep .. sys.python_name
  else
    new_bin_path = venv_path .. sys.path_sep .. sys.python_parent_path
    venv_python = new_bin_path .. sys.path_sep .. sys.python_name
  end

  if vim.fn.executable(venv_python) == 0 then
    utils.notify("The python path '" .. venv_python .. "' doesnt exist.")
    return
  end

  if config.settings.dap_enabled == true then
    M.setup_dap_venv(venv_python)
  end

  if config.settings.notify_user_on_activate == true then
    utils.notify("Activated '" .. venv_python .. "'")
  end

  for _, hook in ipairs(config.settings.changed_venv_hooks) do
    hook(venv_path, venv_python)
  end

  local current_system_path = vim.fn.getenv 'PATH'
  local prev_bin_path = M.current_bin_path

  if prev_bin_path ~= nil then
    current_system_path = string.gsub(current_system_path, utils.escape_pattern(prev_bin_path .. sys.path_env_sep), '')
  end

  local new_system_path = new_bin_path .. sys.path_env_sep .. current_system_path
  vim.fn.setenv('PATH', new_system_path)
  M.current_bin_path = new_bin_path

  if vim.fn.has 'win32' == 1 then
    local venv_path_std = string.gsub(venv_path, '/', '\\')
    local conda_base_path_std = string.gsub(config.settings.anaconda_base_path, '/', '\\')
    local conda_envs_path_std = string.gsub(config.settings.anaconda_envs_path, '/', '\\')
    local is_conda_base = string.find(venv_path_std, conda_base_path_std)
    local is_conda_env = string.find(venv_path, conda_envs_path_std)
    if is_conda_base == 1 or is_conda_env == 1 then
      vim.fn.setenv('CONDA_PREFIX', venv_path)
    else
      vim.fn.setenv('VIRTUAL_ENV', venv_path)
    end
  else
    vim.fn.setenv('VIRTUAL_ENV', venv_path)
  end

  M.current_python_path = venv_python
  M.current_venv = venv_path
  utils.dbg 'Finished setting venv and system paths.'
end

function M.deactivate_venv()
  local current_system_path = vim.fn.getenv 'PATH'
  local prev_bin_path = M.current_bin_path

  if prev_bin_path ~= nil then
    local sys = system.get_info()
    current_system_path = string.gsub(current_system_path, utils.escape_pattern(prev_bin_path .. sys.path_env_sep), '')
    vim.fn.setenv('PATH', current_system_path)
  end

  vim.fn.setenv('VIRTUAL_ENV', nil)
  M.current_python_path = nil
  M.current_venv = nil
end

function M.list_pyright_workspace_folders()
  local workspace_folders = {}
  local workspace_folders_found = false
  for _, client in pairs((vim.lsp.get_clients or vim.lsp.get_active_clients)()) do
    if vim.tbl_contains({ 'basedpyright', 'pyright', 'pylance' }, client.name) then
      for _, folder in pairs(client.workspace_folders or {}) do
        utils.dbg('Found workspace folder: ' .. folder.name)
        table.insert(workspace_folders, folder.name)
        workspace_folders_found = true
      end
    end
  end
  if workspace_folders_found == false then
    utils.dbg 'No workspace folders found'
  end

  return workspace_folders
end

function M.setup_dap_venv(venv_python)
  require('dap-python').resolve_python = function()
    return venv_python
  end
end

function M.retrieve_from_cache()
  if vim.fn.filereadable(config.settings.cache_file) == 1 then
    local cache_file = vim.fn.readfile(config.settings.cache_file)
    if cache_file ~= nil and cache_file[1] ~= nil then
      local venv_cache = vim.fn.json_decode(cache_file[1])
      if venv_cache ~= nil and venv_cache[vim.fn.getcwd()] ~= nil then
        M.set_venv_and_system_paths(venv_cache[vim.fn.getcwd()])
        return
      end
    end
  end
end

function M.cache_venv(venv)
  local venv_cache = {
    [vim.fn.getcwd()] = { value = venv.value },
  }

  if vim.fn.filewritable(config.settings.cache_file) == 0 then
    vim.fn.mkdir(vim.fn.expand(config.settings.cache_dir), 'p')
  end

  local venv_cache_json = nil

  if vim.fn.filereadable(config.settings.cache_file) == 1 then
    local cached_file = vim.fn.readfile(config.settings.cache_file)
    if cached_file ~= nil and cached_file[1] ~= nil then
      local cached_json = vim.fn.json_decode(cached_file[1])
      local merged_cache = vim.tbl_deep_extend('force', cached_json, venv_cache)
      venv_cache_json = vim.fn.json_encode(merged_cache)
    end
  else
    venv_cache_json = vim.fn.json_encode(venv_cache)
  end
  vim.fn.writefile({ venv_cache_json }, config.settings.cache_file)
end

return M
