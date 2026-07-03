-- ~/.hammerspoon/init.lua
-- Claude board: open a set of claude.ai chats as app-mode windows and tile them.
-- Layout only — no status, no notifications (by design).
--
-- Hotkeys:
--   Opt+Cmd+C  -> open your standing set of chats and tile them into a grid
--   Opt+Cmd+R  -> re-tile Claude windows that are already open

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

------------------------------------------------------------------------
-- 2) How to open a clean app-mode window.
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

-- Even-ish grid (cols x rows) for n windows.
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

-- Open the whole set and tile each window as it appears.
local function openBoard()
  local screen = hs.screen.mainScreen()
  local n = #CLAUDE_URLS
  for i, url in ipairs(CLAUDE_URLS) do
    local idx = i - 1
    hs.timer.doAfter(idx * SPAWN_STAGGER, function()
      openAppWindow(url)
      hs.timer.doAfter(PLACE_DELAY, function()
        local app = hs.application.get(BROWSER)
        local win = app and app:focusedWindow()
        if win then win:setFrame(cellFrame(idx, n, screen)) end
      end)
    end)
  end
end

-- Re-tile Claude windows already open (title heuristic).
local function retileExisting()
  local screen = hs.screen.mainScreen()
  local app = hs.application.get(BROWSER)
  if not app then return end
  local wins = {}
  for _, w in ipairs(app:allWindows()) do
    local t = (w:title() or ""):lower()
    if t:find("claude") then wins[#wins + 1] = w end
  end
  for i, w in ipairs(wins) do
    w:setFrame(cellFrame(i - 1, #wins, screen))
  end
end

------------------------------------------------------------------------
-- Hotkeys
------------------------------------------------------------------------
hs.hotkey.bind({ "alt", "cmd" }, "C", openBoard)
hs.hotkey.bind({ "alt", "cmd" }, "R", retileExisting)

hs.alert.show("Claude board loaded")
