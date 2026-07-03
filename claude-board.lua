-- ~/.hammerspoon/init.lua
-- Claude board: open a set of claude.ai chats as app-mode windows and tile them.
-- Optionally include the Claude desktop app as one of the tiles.
-- Layout only — no status, no notifications (by design).
--
-- Hotkeys:
--   Opt+Cmd+C  -> open your standing set of chats and tile them into a grid
--   Opt+Cmd+R  -> re-tile Claude windows that are already open
--   Opt+Cmd+X  -> close Claude board windows

hs.window.animationDuration = 0  -- instant snap, no slide animation

------------------------------------------------------------------------
-- 1) Your standing set of chats.
--    Use "https://claude.ai/new" for a fresh chat, or paste a specific
--    ongoing chat as "https://claude.ai/chat/<id>". Add/remove freely.
--    (There's no API to auto-discover your chats, so this is a manual list.)
------------------------------------------------------------------------
local CLAUDE_URLS = {
  "https://claude.ai/new",
  "https://claude.ai/new",
  "https://claude.ai/new",
  "https://claude.ai/new",
}

-- How many tiles Opt+Cmd+C should create on a fresh board open.
-- The default 4 keeps the board in a steady 2x2. If the desktop app is
-- already open and included, it counts as one of these tiles.
local BOARD_TILE_LIMIT = 4

------------------------------------------------------------------------
-- 2) Include the Claude desktop app as a tile?
--    true  -> the desktop app takes the top-left cell if it is already open;
--             otherwise that slot becomes another browser chat.
--    false -> browser windows only (original behavior).
--
--    The desktop app is single-window: its Chat / Code / Cowork tabs live
--    inside that one pane, so it's exactly one tile — whichever tab is
--    active is what shows. Tiling can't split the tabs into separate cells.
--
--    DESKTOP_BUNDLE_ID is the most reliable way to find the native app. If
--    Anthropic changes it, focus the app and run this in the Hammerspoon console:
--      hs.application.frontmostApplication():bundleID()
--
--    DESKTOP_APP is a fallback. If the tile still doesn't move, focus the app
--    and run:
--      hs.application.frontmostApplication():name()
------------------------------------------------------------------------
local INCLUDE_DESKTOP = true
local DESKTOP_BUNDLE_ID = "com.anthropic.claudefordesktop"
local DESKTOP_APP     = "Claude"

------------------------------------------------------------------------
-- 3) How to open a clean app-mode window.
--    Chrome/Edge support --app. Safari cannot do CLI app-mode.
--    For Edge: replace "Google Chrome" with "Microsoft Edge".
--
--    Want the board isolated from your everyday browsing? Add a dedicated
--    profile dir (you'll log into claude.ai once inside it):
--      ... --args --user-data-dir="$HOME/.claude-board-chrome" --app='%s'
------------------------------------------------------------------------
local BROWSER = "Google Chrome"

local function openAppWindow(url)
  hs.execute(string.format(
    [[/usr/bin/open -na "%s" --args --app='%s']], BROWSER, url))
end

------------------------------------------------------------------------
-- Timing — bump these if windows don't reliably land in their cells.
------------------------------------------------------------------------
local SPAWN_STAGGER = 0.6   -- seconds between opening each window
local PLACE_DELAY   = 0.45  -- seconds to wait for a window before moving it

-- Even-ish grid (cols x rows) for n windows. The fresh-open path caps this
-- at BOARD_TILE_LIMIT, so the default board is a steady 2x2.
local function gridDims(n)
  local cols = math.ceil(math.sqrt(n))
  local rows = math.ceil(n / cols)
  return cols, rows
end

-- Frame for cell index i (0-based) on the given screen.
local function cellFrame(i, n, screen)
  local f = screen:frame()          -- usable area, excludes menu bar + Dock
  local cols, rows = gridDims(n)
  local col = i % cols
  local row = math.floor(i / cols)
  local w = f.w / cols
  local h = f.h / rows
  return { x = f.x + col * w, y = f.y + row * h, w = w, h = h }
end

local function desktopApp()
  return hs.application.get(DESKTOP_BUNDLE_ID) or hs.application.get(DESKTOP_APP)
end

local function prepareWindow(win)
  if win and not win:isVisible() then win:unminimize() end
  return win
end

local function firstUsableWindow(app)
  if not app then return nil end

  local main = app:mainWindow()
  if main and main:isStandard() then return prepareWindow(main) end

  local fallback = main

  for _, win in ipairs(app:visibleWindows()) do
    if win:isStandard() then return prepareWindow(win) end
    fallback = fallback or win
  end

  for _, win in ipairs(app:allWindows()) do
    if win:isStandard() then
      return prepareWindow(win)
    end
    fallback = fallback or win
  end

  return prepareWindow(fallback)
end

local function desktopWindow()
  if not INCLUDE_DESKTOP then return nil end

  local app = desktopApp()
  if not app then return nil end

  app:unhide()
  return firstUsableWindow(app)
end

local function browserApps()
  local apps = {}
  local seen = {}

  for _, app in ipairs(hs.application.runningApplications()) do
    if app:name() == BROWSER then
      local key = app:pid() or tostring(app)
      if not seen[key] then
        apps[#apps + 1] = app
        seen[key] = true
      end
    end
  end

  return apps
end

local function isClaudeBrowserWindow(win)
  local title = (win:title() or ""):lower()

  -- Claude app-mode browser windows are usually "New chat - Claude" or
  -- "<conversation title> - Claude". Some Chrome builds append the browser name.
  -- Avoid broad substring matching so pages like GitHub repos named
  -- "claude-board" do not get swept into the grid.
  return title == "claude"
    or title:match("%s%-%sclaude$") ~= nil
    or title:match("%s%-%sclaude%s%-%s") ~= nil
    or title:match("^claude%s%-%s") ~= nil
end

local function claudeBrowserWindows(limit)
  local wins = {}
  local seen = {}

  for _, app in ipairs(browserApps()) do
    for _, win in ipairs(app:allWindows()) do
      local key = win:id() or tostring(win)
      if not seen[key] and isClaudeBrowserWindow(win) then
        wins[#wins + 1] = win
        seen[key] = true
        if limit and #wins >= limit then return wins end
      end
    end
  end

  return wins
end

local function openBrowserTile(url, idx, n, screen)
  openAppWindow(url)
  hs.timer.doAfter(PLACE_DELAY, function()
    local win = hs.window.focusedWindow()
    local focusedApp = win and win:application()
    if not (focusedApp and focusedApp:name() == BROWSER) then
      for _, app in ipairs(browserApps()) do
        win = app:focusedWindow()
        if win then break end
      end
    end

    if win then win:setFrame(cellFrame(idx, n, screen)) end
  end)
end

-- Open a fresh board and tile each window as it appears.
local function openBoard()
  local screen = hs.screen.mainScreen()
  local dwin = desktopWindow()
  local wantsDesktop = dwin ~= nil and BOARD_TILE_LIMIT > 0
  local offset = wantsDesktop and 1 or 0
  local browserCount = math.min(#CLAUDE_URLS, math.max(BOARD_TILE_LIMIT - offset, 0))
  local n = browserCount + offset

  if n == 0 then return end

  if wantsDesktop then
    dwin:setFrame(cellFrame(0, n, screen))
  end

  for i = 1, browserCount do
    local url = CLAUDE_URLS[i]
    local idx = (i - 1) + offset
    hs.timer.doAfter((i - 1) * SPAWN_STAGGER, function()
      openBrowserTile(url, idx, n, screen)
    end)
  end
end

-- Re-tile Claude windows already open (desktop app first, then browser).
local function retileExisting()
  local screen = hs.screen.mainScreen()
  local wins = {}

  local dwin = desktopWindow()
  if dwin then
    wins[#wins + 1] = dwin
  end

  local browserLimit = math.max(BOARD_TILE_LIMIT - #wins, 0)
  for _, win in ipairs(claudeBrowserWindows(browserLimit)) do
    wins[#wins + 1] = win
  end

  if #wins == 0 then
    hs.alert.show("No Claude board windows found")
    return
  end

  for i, w in ipairs(wins) do
    w:setFrame(cellFrame(i - 1, #wins, screen))
  end
end

-- Close Claude board windows without touching unrelated browser windows.
local function closeBoard()
  local closed = 0
  local dwin = desktopWindow()
  if dwin then
    dwin:close()
    closed = closed + 1
  end

  for _, win in ipairs(claudeBrowserWindows()) do
    win:close()
    closed = closed + 1
  end

  hs.alert.show(string.format("Closed %d Claude board window%s", closed, closed == 1 and "" or "s"))
end

------------------------------------------------------------------------
-- Hotkeys
------------------------------------------------------------------------
hs.hotkey.bind({ "alt", "cmd" }, "C", openBoard)
hs.hotkey.bind({ "alt", "cmd" }, "R", retileExisting)
hs.hotkey.bind({ "alt", "cmd" }, "X", closeBoard)

hs.alert.show("Claude board loaded")
