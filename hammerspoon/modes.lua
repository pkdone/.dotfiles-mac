-- modes.lua: the menu-bar mode switcher's settings (engine: mode_switcher.lua).
--
-- Pure data, no Hammerspoon calls, so tests/modes.test.sh and macconfig-check.sh can validate it
-- outside Hammerspoon. Edit, then reload Hammerspoon (menu-bar icon -> Reload Config).
-- Switching is manual only, from the menu-bar dropdown: no hotkey, no automatic triggers.
--
-- Every mode except Normal records what it changed in
--   ~/Library/Application Support/pdone-modes/state.json
-- (written BEFORE anything changes) and Normal undoes exactly that. Switching from one
-- non-Normal mode to another runs Normal's restore first.

local apps = {
  spotify      = 'com.spotify.client',
  -- Chrome PWA (~/Applications/Chrome Apps.localized/YouTube Music.app)
  youtubeMusic = 'com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod',
  slack        = 'com.tinyspeck.slackmacgap',
  granola      = 'com.granola.app',
  finder       = 'com.apple.finder',
  grokBot      = 'com.anysphere.sand',
  -- Safari web app (File > Add to Dock, manual step whatsapp-web). Not a fixed
  -- bundle id: each Mac gets its own, read from this app when a mode runs.
  whatsappWeb  = { path = '~/Applications/WhatsApp Web.app', name = 'WhatsApp Web' },
}

return {
  version = 1,

  -- Menu order. Normal must exist: it's the "undo everything" mode.
  order = { 'Normal', 'WebConf', 'DeepWork' },

  -- Focus can't be set directly on macOS, so each Focus is toggled by a Shortcut that
  -- you create once (see docs/modes.md / scripts/manual-steps.sh). macconfig-check.sh verifies
  -- they exist (`shortcuts list`). A missing Shortcut doesn't stop the mode: everything
  -- else still runs, the menu offers a clickable Fix, and the switch names the Shortcut.
  focus = {
    WebConf  = { on = 'Mode WebConf On',  off = 'Mode WebConf Off'  },
    DeepWork = { on = 'Mode DeepWork On', off = 'Mode DeepWork Off' },
  },

  modes = {
    Normal = {
      label   = 'Normal',
      icon    = { symbol = 'desktopcomputer', fallback = '🖥' },
      -- Normal has no actions of its own: it restores whatever state.json recorded.
    },

    WebConf = {
      label   = 'WebConf (on air)',
      icon    = { symbol = 'record.circle.fill', color = 'red', fallback = '🔴' },
      quit    = { apps.spotify, apps.youtubeMusic, apps.whatsappWeb },
      hide    = { apps.slack, apps.finder, apps.grokBot },  -- Finder = its windows
      focus   = 'WebConf',
      front   = apps.granola,              -- brought to the front last
      keepDisplayAwake  = true,            -- hs.caffeinate.set('displayIdle', true) while on
      -- Menu-bar notification badges: macOS has no API to switch them off, so the
      -- WebConf Focus (which silences notifications and badges) is what hides them.
    },

    DeepWork = {
      label   = 'DeepWork',
      icon    = { symbol = 'brain.head.profile', fallback = '🧠' },
      quit    = { apps.slack, apps.whatsappWeb },
      hide    = { apps.granola },
      focus   = 'DeepWork',                -- Spotify is left alone
      timerMinutes  = 50,                  -- menu-bar countdown; when it ends you choose,
      breakMinutes  = 10,                  --   it never switches by itself
    },
  },
}
