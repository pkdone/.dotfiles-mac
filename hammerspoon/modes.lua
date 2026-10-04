-- modes.lua: the menu-bar mode switcher's settings (engine: mode_switcher.lua).
--
-- Pure data, no Hammerspoon calls, so tests/modes.test.sh and check.sh can validate it
-- outside Hammerspoon. Edit, then reload Hammerspoon (menu-bar icon -> Reload Config).
-- Switching is manual only, from the menu-bar dropdown: no hotkey, no automatic triggers.
--
-- Every mode except Normal records what it changed in
--   ~/Library/Application Support/pdone-modes/state.json
-- (written BEFORE anything changes) and Normal undoes exactly that. Switching from one
-- non-Normal mode to another runs Normal's restore first.

local apps = {
  whatsapp     = 'net.whatsapp.WhatsApp',
  spotify      = 'com.spotify.client',
  -- Chrome PWA (~/Applications/Chrome Apps.localized/YouTube Music.app)
  youtubeMusic = 'com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod',
  slack        = 'com.tinyspeck.slackmacgap',
  granola      = 'com.granola.app',
  finder       = 'com.apple.finder',
  grokBot      = 'com.anysphere.sand',
  chrome       = 'com.google.Chrome',
}

return {
  version = 1,

  -- Menu order. Normal must exist: it's the "undo everything" mode.
  order = { 'Normal', 'WebConf', 'DeepWork' },

  -- Focus can't be set directly on macOS, so each Focus is toggled by a Shortcut that
  -- you create once (see README "Modes" / scripts/manual-steps.sh). check.sh verifies
  -- they exist (`shortcuts list`). A missing Shortcut doesn't stop the mode: the menu
  -- notes it and everything else still runs.
  focus = {
    WebConf  = { on = 'Mode WebConf On',  off = 'Mode WebConf Off'  },
    DeepWork = { on = 'Mode DeepWork On', off = 'Mode DeepWork Off' },
  },

  -- Meeting alerts in DeepWork: Hammerspoon has no calendar permission of its own, so
  -- a Shortcut does the calendar lookup (Shortcuts asks for Calendar access once). It
  -- must output the titles of events starting in the next `minutes` minutes, one per
  -- line. Missing Shortcut = no meeting alerts (the menu says so).
  meetings = {
    shortcut      = 'Mode Upcoming Meetings',
    minutes       = 5,
    checkEverySec = 60,
  },

  -- WebConf's Chrome tidy-up. Closed tabs' addresses are never saved anywhere (not in
  -- state.json, not in the log): they're gone, like closing them by hand.
  chrome = {
    bundle = apps.chrome,
    -- "Personal" tabs: closed in every Chrome window (pinned tabs are kept when Chrome
    -- shows which ones are pinned).
    personalDomains  = { 'youtube.com', 'netflix.com', 'reddit.com', 'facebook.com',
                         'instagram.com', 'web.whatsapp.com', 'open.spotify.com',
                         'amazon.co.uk', 'ebay.co.uk' },
    -- Chrome profile names whose windows are entirely personal (window titles end in
    -- " - <profile>" once Chrome has more than one profile). Empty = none.
    personalProfiles = {},
    -- Closing every non-pinned tab is destructive, so it's scoped:
    --   'off'           never
    --   'work-window'   only the frontmost window of the work profile (default)
    --   'work-windows'  every window of the work profile
    -- Pinned tabs are always kept. If Chrome's tab strip can't be read (window on
    -- another Space, no Accessibility), nothing non-pinned is closed and you're told.
    closeNonPinned   = 'work-window',
    workProfile      = nil,      -- profile name in window titles; nil = single-profile Chrome
    -- Never closed, whatever the rules above say (your call is probably in one of these).
    keepDomains      = { 'meet.google.com', 'zoom.us', 'teams.microsoft.com', 'app.slack.com' },
    pinnedMaxWidth   = 60,       -- px: tab-strip buttons this narrow, leading the strip, are pinned
  },

  modes = {
    Normal = {
      label   = 'Normal',
      icon    = { symbol = 'circle', fallback = '○' },
      -- Normal has no actions of its own: it restores whatever state.json recorded.
    },

    WebConf = {
      label   = 'WebConf (on air)',
      icon    = { symbol = 'record.circle.fill', color = 'red', fallback = '🔴' },
      quit    = { apps.whatsapp, apps.spotify, apps.youtubeMusic },
      hide    = { apps.slack, apps.finder, apps.grokBot },  -- Finder = its windows
      focus   = 'WebConf',
      front   = apps.granola,              -- brought to the front last
      keepDisplayAwake  = true,            -- hs.caffeinate.set('displayIdle', true) while on
      chromeTabs        = true,            -- the chrome rules above
      -- Menu-bar notification badges: macOS has no API to switch them off, so the
      -- WebConf Focus (which silences notifications and badges) is what hides them.
    },

    DeepWork = {
      label   = 'DeepWork',
      icon    = { symbol = 'brain.head.profile', fallback = '🧠' },
      quit    = { apps.slack, apps.whatsapp },
      hide    = { apps.granola },
      focus   = 'DeepWork',                -- Spotify is left alone
      timerMinutes  = 50,                  -- menu-bar countdown; when it ends you choose,
      breakMinutes  = 10,                  --   it never switches by itself
      meetingAlerts = true,                -- see `meetings` above
    },
  },
}
