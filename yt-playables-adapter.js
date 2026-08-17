(() => {
  if (typeof ytgame === 'undefined') return;

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
  let ytStorageReady = false;

  const ls = {
    getItem(key) { try { return localStorage.getItem(key); } catch (_) { return null; } },
    setItem(key, value) { try { localStorage.setItem(key, String(value)); } catch (_) {} },
    removeItem(key) { try { localStorage.removeItem(key); } catch (_) {} }
  };

  async function persistToYt() {
    if (!ytStorageReady) return;
    const obj = {};
    for (const k of ALL_STORAGE_KEYS) {
      const v = cache.get(k);
      if (v !== undefined) obj[k] = v;
    }
    try { await ytgame.game.saveData(JSON.stringify(obj)); } catch (_) {}
  }

  const storage = {
    getItem(key) { return cache.has(key) ? cache.get(key) : null; },
    setItem(key, value) {
      const text = String(value);
      cache.set(key, text);
      ls.setItem(key, text);
      persistToYt();
    },
    removeItem(key) {
      cache.delete(key);
      ls.removeItem(key);
      persistToYt();
    }
  };

  async function initYtStorage() {
    try {
      const raw = await ytgame.game.loadData();
      if (raw) {
        const parsed = JSON.parse(raw);
        for (const [k, v] of Object.entries(parsed)) {
          if (v !== null && v !== undefined) cache.set(k, String(v));
        }
      }
    } catch (_) {}
    for (const k of ALL_STORAGE_KEYS) {
      if (!cache.has(k)) {
        const lv = ls.getItem(k);
        if (lv !== null) cache.set(k, lv);
      }
    }
    const pushKeys = [], pushVals = [];
    for (const k of ALL_STORAGE_KEYS) {
      const cv = cache.get(k);
      if (cv !== undefined) { pushKeys.push(k); pushVals.push(cv); }
    }
    if (pushKeys.length) {
      const obj = {};
      for (let i = 0; i < pushKeys.length; i++) obj[pushKeys[i]] = pushVals[i];
      try { await ytgame.game.saveData(JSON.stringify(obj)); } catch (_) {}
    }
    ytStorageReady = true;
  }

  const language = () => {
    const saved = storage.getItem(LANGUAGE_KEY);
    if (saved === 'ru' || saved === 'en') return saved;
    return 'en';
  };

  let callbacks = {};

  window.PaperFlightGamePix = {
    storage,
    language,
    initBridgeStorage: initYtStorage,
    loading() {},
    loaded() {},
    updateScore(score) {
      try { ytgame.engagement.sendScore({ value: Math.floor(Number(score) || 0) }); } catch (_) {}
    },
    registerCallbacks(nextCallbacks = {}) {
      callbacks = nextCallbacks;
    },
    happyMoment() {},
    gameOver(_score, extraCallbacks) {
      if (extraCallbacks) callbacks = { ...callbacks, ...extraCallbacks };
      return Promise.resolve();
    }
  };

  try { ytgame.game.firstFrameReady(); } catch (_) {}

  try {
    ytgame.system.onPause(() => callbacks.pause?.());
  } catch (_) {}
  try {
    ytgame.system.onResume(() => callbacks.resume?.());
  } catch (_) {}
  try {
    ytgame.system.onAudioEnabledChange(isEnabled => {
      if (isEnabled) callbacks.soundOn?.();
      else callbacks.soundOff?.();
    });
  } catch (_) {}

  if (!storage.getItem(LANGUAGE_KEY)) {
    ytgame.system.getLanguage().then(tag => {
      const short = String(tag || '').split('-')[0].toLowerCase();
      if (short === 'ru' || short === 'en') {
        storage.setItem(LANGUAGE_KEY, short);
      }
    }).catch(() => {});
  }

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
