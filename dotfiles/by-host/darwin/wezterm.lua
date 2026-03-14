local wezterm = require 'wezterm'
local mux = wezterm.mux
local config = wezterm.config_builder()

config.automatically_reload_config = true

config.default_prog = { 'zsh' }
config.font = wezterm.font('JetBrains Mono')
config.font_size = 12.0
config.window_background_opacity = 0.95
config.window_close_confirmation = 'NeverPrompt'

-- Use left Option key as Meta/Alt (matches macos-option-as-alt = left)
config.send_composed_key_when_left_alt_is_pressed = false

-- Non-native fullscreen (matches macos-non-native-fullscreen)
config.native_macos_fullscreen_mode = false

-- Load noctalia-generated colors if available
local colors_file = wezterm.home_dir .. '/.local/share/noctalia/wezterm-colors.lua'
local ok, colors = pcall(dofile, colors_file)
if ok and type(colors) == 'table' then
  config.colors = colors
end

local function niri_deep_mux_bridge_dir()
  local runtime_dir = os.getenv('XDG_RUNTIME_DIR')
  if runtime_dir == nil or runtime_dir == '' then
    runtime_dir = '/tmp'
  end
  return runtime_dir .. '/niri-deep-wezterm-mux'
end

local niri_deep_bridge_dir_initialized = false

local function niri_deep_ensure_mux_bridge_dir()
  if niri_deep_bridge_dir_initialized then
    return true
  end

  local success, _, stderr = wezterm.run_child_process {
    'mkdir',
    '-p',
    niri_deep_mux_bridge_dir(),
  }
  if success then
    niri_deep_bridge_dir_initialized = true
    return true
  end

  if stderr ~= nil and stderr ~= '' then
    wezterm.log_warn('niri-deep mux bridge: failed to create bridge dir stderr=' .. stderr)
  end
  return false
end

local function niri_deep_touch_bridge_ready(pane_id)
  if not niri_deep_ensure_mux_bridge_dir() then
    return
  end

  local handle = io.open(string.format('%s/ready', niri_deep_mux_bridge_dir()), 'w')
  if handle == nil then
    return
  end
  handle:write(tostring(pane_id) .. ' ' .. tostring(os.time()) .. '\n')
  handle:close()
end

local function niri_deep_merge_split_flag(dir)
  if dir == 'west' then
    return '--right'
  elseif dir == 'east' then
    return '--left'
  elseif dir == 'north' then
    return '--bottom'
  elseif dir == 'south' then
    return '--top'
  end
  return nil
end

local function niri_deep_bridge_command_path()
  return string.format('%s/merge.cmd', niri_deep_mux_bridge_dir())
end

local function niri_deep_claim_bridge_command(pane_id)
  if not niri_deep_ensure_mux_bridge_dir() then
    return nil, nil
  end
  local cmd_path = niri_deep_bridge_command_path()
  local claimed_path = string.format('%s.processing.%d', cmd_path, pane_id)
  local ok = os.rename(cmd_path, claimed_path)
  if not ok then
    return nil, nil
  end
  return cmd_path, claimed_path
end

local function niri_deep_restore_bridge_command(claimed_path, cmd_path)
  local ok = os.rename(claimed_path, cmd_path)
  if ok then
    return
  end
  wezterm.log_warn('niri-deep mux bridge: failed to restore command file; dropping stale command')
  os.remove(claimed_path)
end

local function niri_deep_process_mux_bridge(window, pane)
  local pane_id = pane:pane_id()
  niri_deep_touch_bridge_ready(pane_id)

  if not window:is_focused() then
    return
  end

  local cmd_path, claimed_path = niri_deep_claim_bridge_command(pane_id)
  if claimed_path == nil then
    return
  end

  local handle = io.open(claimed_path, 'r')
  if handle == nil then
    os.remove(claimed_path)
    return
  end

  local payload = handle:read('*a') or ''
  handle:close()

  local op, source_pane_id_raw, dir = payload:match('^(%S+)%s+(%d+)%s+(%S+)%s*$')
  if op ~= 'merge' then
    wezterm.log_warn('niri-deep mux bridge: unknown command payload=' .. payload)
    os.remove(claimed_path)
    return
  end

  local source_pane_id = tonumber(source_pane_id_raw)
  if source_pane_id == nil then
    wezterm.log_warn('niri-deep mux bridge: invalid source pane id payload=' .. payload)
    os.remove(claimed_path)
    return
  end

  if source_pane_id == pane_id then
    niri_deep_restore_bridge_command(claimed_path, cmd_path)
    return
  end

  local split_flag = niri_deep_merge_split_flag(dir)
  if split_flag == nil then
    wezterm.log_warn('niri-deep mux bridge: invalid direction in payload=' .. payload)
    os.remove(claimed_path)
    return
  end

  local source_pane = mux.get_pane(source_pane_id)
  if source_pane == nil then
    wezterm.log_warn('niri-deep mux bridge: source pane not found id=' .. tostring(source_pane_id))
    os.remove(claimed_path)
    return
  end

  local success, stdout, stderr = wezterm.run_child_process {
    'wezterm',
    'cli',
    'split-pane',
    '--pane-id',
    tostring(pane_id),
    split_flag,
    '--move-pane-id',
    tostring(source_pane_id),
  }

  if not success then
    wezterm.log_error('niri-deep mux bridge: split-pane failed stderr=' .. (stderr or ''))
    niri_deep_restore_bridge_command(claimed_path, cmd_path)
    return
  end

  if stderr ~= nil and stderr ~= '' then
    wezterm.log_warn('niri-deep mux bridge: split-pane stderr=' .. stderr)
  end
  os.remove(claimed_path)

  wezterm.log_info(
    'niri-deep mux bridge: merged source pane '
      .. tostring(source_pane_id)
      .. ' into target pane '
      .. tostring(pane_id)
      .. ' using '
      .. split_flag
      .. (stdout ~= nil and stdout ~= '' and (' stdout=' .. stdout) or '')
  )
end

wezterm.on('update-right-status', niri_deep_process_mux_bridge)
config.status_update_interval = 250

-- Keybinds (Super/Cmd-based on macOS)
config.keys = {
  { key = 'c', mods = 'SUPER',       action = wezterm.action.CopyTo 'Clipboard' },
  { key = 'v', mods = 'SUPER',       action = wezterm.action.PasteFrom 'Clipboard' },
  { key = 'c', mods = 'SUPER|SHIFT', action = wezterm.action.CopyTo 'Clipboard' },
  { key = 'v', mods = 'SUPER|SHIFT', action = wezterm.action.PasteFrom 'Clipboard' },
  { key = '=', mods = 'SUPER',       action = wezterm.action.IncreaseFontSize },
  { key = '-', mods = 'SUPER',       action = wezterm.action.DecreaseFontSize },
  { key = '0', mods = 'SUPER',       action = wezterm.action.ResetFontSize },
  { key = 'q', mods = 'SUPER',       action = wezterm.action.QuitApplication },
  { key = ',', mods = 'SUPER|SHIFT', action = wezterm.action.ReloadConfiguration },
  { key = 'k', mods = 'SUPER',       action = wezterm.action.ClearScrollback 'ScrollbackAndViewport' },
  { key = 'n', mods = 'SUPER',       action = wezterm.action.SpawnWindow },
  { key = 'w', mods = 'SUPER',       action = wezterm.action.CloseCurrentPane { confirm = false } },
  { key = 'w', mods = 'SUPER|SHIFT', action = wezterm.action.CloseCurrentTab { confirm = false } },
  { key = 't', mods = 'SUPER',       action = wezterm.action.SpawnTab 'CurrentPaneDomain' },
  { key = '[', mods = 'SUPER|SHIFT', action = wezterm.action.ActivateTabRelative(-1) },
  { key = ']', mods = 'SUPER|SHIFT', action = wezterm.action.ActivateTabRelative(1) },
  { key = 'd', mods = 'SUPER',       action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'd', mods = 'SUPER|SHIFT', action = wezterm.action.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = ']', mods = 'SUPER',       action = wezterm.action.ActivatePaneDirection 'Next' },
  { key = '[', mods = 'SUPER',       action = wezterm.action.ActivatePaneDirection 'Prev' },
}

return config
