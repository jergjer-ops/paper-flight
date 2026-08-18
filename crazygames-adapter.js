(() => {
  if (typeof window.CrazyGames === 'undefined') return;

  const SDK = window.CrazyGames.SDK;
  const LANGUAGE_KEY = 'paper-flight-language';
  const ALL_STORAGE_KEYS = [
    LANGUAGE_KEY,
    'paper-flight-players',
    'paper-flight-active-player',
    'paper-flight-music',
    'paper-flight-effects',
    'paper-flight-vibration',
    'paper-flight-visitor-id',
    'paper-flight-best'
  ];

  const cache = new Map();
  let cgStorageReady = false;

  const ls = {
    getItem(key) { try { return localStorage.getItem(key); } catch (_) { return null; } },
    setItem(key, value) { try { localStorage.setItem(key, String(value)); } catch (_) {} },
    removeItem(key) { try { localStorage.removeItem(key); } catch (_) {} }
  };

  const storage = {
    getItem(key) { return cache.has(key) ? cache.get(key) : null; },
    setItem(key, value) {
      const text = String(value);
      cache.set(key, text);
      ls.setItem(key, text);
      if (cgStorageReady) {
        try { SDK.data.setItem(key, text); } catch (_) {}
      }
    },
    removeItem(key) {
      cache.delete(key);
      ls.removeItem(key);
      if (cgStorageReady) {
        try { SDK.data.removeItem(key); } catch (_) {}
      }
    }
  };

  async function initCgStorage() {
    try {
      for (const k of ALL_STORAGE_KEYS) {
        const v = SDK.data.getItem(k);
        if (v !== null && v !== undefined) {
          cache.set(k, String(v));
        } else {
          const lv = ls.getItem(k);
          if (lv !== null) {
            cache.set(k, lv);
            try { SDK.data.setItem(k, lv); } catch (_) {}
          }
        }
      }
    } catch (_) {
      for (const k of ALL_STORAGE_KEYS) {
        const v = ls.getItem(k);
        if (v !== null) cache.set(k, v);
      }
    }
    cgStorageReady = true;
  }

  const language = () => {
    const saved = storage.getItem(LANGUAGE_KEY);
    if (saved === 'ru' || saved === 'en') return saved;
    const tag = (navigator.language || '').split('-')[0].toLowerCase();
    return tag === 'ru' ? 'ru' : 'en';
  };

  let callbacks = {};

  window.PaperFlightGamePix = {
    storage,
    language,
    initBridgeStorage: initCgStorage,
    loading() {},
    loaded() {},
    updateScore() {},
    registerCallbacks(nextCallbacks = {}) {
      callbacks = nextCallbacks;
    },
    happyMoment() {
      try { SDK.game.happytime(); } catch (_) {}
    },
    gameOver(_score, extraCallbacks) {
      if (extraCallbacks) callbacks = { ...callbacks, ...extraCallbacks };
      return Promise.resolve();
    }
  };

  let sdkReady = false;

  async function initCrazyGames() {
    try {
      await SDK.init();
      sdkReady = true;

      try {
        SDK.game.loadingStart();
      } catch (_) {}

      try {
        const settings = SDK.game.settings;
        if (settings && settings.muteAudio) {
          callbacks.soundOff?.();
        }
        SDK.game.addSettingsChangeListener(newSettings => {
          if (newSettings.muteAudio) callbacks.soundOff?.();
          else callbacks.soundOn?.();
        });
      } catch (_) {}

    } catch (_) {}
  }

  function signalGameReady() {
    if (sdkReady) {
      try { SDK.game.loadingStop(); } catch (_) {}
    }
  }

  window._crazygamesInit = initCrazyGames;
  window._crazygamesReady = signalGameReady;

  for (const eventName of ['contextmenu', 'dragstart', 'selectstart']) {
    document.addEventListener(eventName, e => e.preventDefault(), { passive: false });
  }

  document.addEventListener('visibilitychange', () => {
    const cb = document.hidden ? callbacks.pause : callbacks.resume;
    if (typeof cb === 'function') cb();
  });
  window.addEventListener('pagehide', () => callbacks.pause?.());
  window.addEventListener('pageshow', () => callbacks.resume?.());
})();
