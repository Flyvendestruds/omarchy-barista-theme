-- Hide window borders when a workspace shows only one tiled window.
-- Borders reappear as soon as a second tiled window is present on that
-- workspace. Floating, fullscreen, hidden and unmapped windows are ignored,
-- so dialogs / PiP never force borders back on.

-- Skip when sourced by omarchy-menu-keybindings' lua bind scanner, where hl
-- is a stub and get_workspaces/get_workspace_windows return a self-indexing
-- noop that would make ipairs() below loop forever (hangs --print).
if type(hl.get_workspaces) ~= "function" or type(hl.get_workspace_windows) ~= "function" then
  return
end

-- Barista-gated: the handlers always stay registered (so they can undo
-- on theme switch), but each pass decides via the gate whether to apply
-- the single-window rule or restore stock borders.

local function tiled_windows(ws_id)
  local out = {}
  local ok, wins = pcall(hl.get_workspace_windows, ws_id)
  if not ok or type(wins) ~= "table" then
    return out
  end
  for _, w in ipairs(wins) do
    local ok_w, is_tiled = pcall(function()
      return w.floating == false
        and (w.fullscreen == 0 or w.fullscreen == false or w.fullscreen == nil)
        and w.mapped ~= false
        and w.hidden ~= true
    end)
    if ok_w and is_tiled then
      table.insert(out, w)
    end
  end
  return out
end

local function theme_border()
  local ok, v = pcall(hl.get_config, "general.border_size")
  if ok and type(v) == "number" then
    return v
  end
  return 2
end

local function set_border(win, size)
  local addr_ok, addr = pcall(function()
    return win.address
  end)
  if not addr_ok or addr == nil or addr == "" then
    return
  end
  pcall(hl.dispatch, hl.dsp.window.set_prop({
    window = "address:" .. tostring(addr),
    prop = "border_size",
    value = size,
  }))
end

local function sync_workspace(ws_id)
  local tiled = tiled_windows(ws_id)
  local target = (#tiled <= 1) and 0 or theme_border()
  for _, w in ipairs(tiled) do
    set_border(w, target)
  end
end

local function sync_all()
  local ok, workspaces = pcall(hl.get_workspaces)
  if not ok or type(workspaces) ~= "table" then
    return
  end
  for _, ws in ipairs(workspaces) do
    local ok_id, id = pcall(function()
      return ws.id
    end)
    if ok_id and id ~= nil then
      pcall(sync_workspace, id)
    end
  end
end

-- Barista-gated sync: restores the theme border on every window when
-- barista is NOT active (undoes border_size 0 left behind by a previous
-- barista session), otherwise applies the single-window rule.
local function gated_sync_all()
  local gate_ok, gate = pcall(require, "hypr.barista-gate")
  if gate_ok and gate and gate.active() then
    pcall(sync_all)
    return
  end
  -- Foreign theme: clear any per-window overrides this module set before.
  -- A plain hl.config reload cannot do this: border_size was applied per
  -- window via set_prop, which survives config changes until re-set.
  local ok, workspaces = pcall(hl.get_workspaces)
  if not ok or type(workspaces) ~= "table" then
    return
  end
  local border = theme_border()
  for _, ws in ipairs(workspaces) do
    local ok_id, id = pcall(function()
      return ws.id
    end)
    if ok_id and id ~= nil then
      local ok_w, wins = pcall(hl.get_workspace_windows, id)
      if ok_w and type(wins) == "table" then
        for _, w in ipairs(wins) do
          pcall(set_border, w, border)
        end
      end
    end
  end
end

-- Debounced sync: window/workspace events can fire before the window list
-- settles, so coalesce rapid events into one delayed pass.
local sync_pending = false
local function request_sync()
  if sync_pending then
    return
  end
  sync_pending = true
  local ok = pcall(hl.timer, function()
    sync_pending = false
    pcall(gated_sync_all)
  end, { timeout = 80, type = "oneshot" })
  if not ok then
    sync_pending = false
    pcall(gated_sync_all)
  end
end

hl.on("window.open", request_sync)
hl.on("window.close", request_sync)
hl.on("window.destroy", request_sync)
hl.on("window.move_to_workspace", request_sync)
hl.on("window.fullscreen", request_sync)
hl.on("window.pin", request_sync)
hl.on("workspace.active", request_sync)
hl.on("workspace.created", request_sync)
hl.on("workspace.removed", request_sync)
hl.on("workspace.move_to_monitor", request_sync)
hl.on("workspace.special_active", request_sync)
hl.on("config.reloaded", request_sync)
hl.on("hyprland.start", request_sync)

-- Initial pass for windows already open at (re)load. Gated the same way:
-- restores stock borders when arriving from another theme as well.
pcall(gated_sync_all)
