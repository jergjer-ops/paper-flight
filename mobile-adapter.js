(() => {
  if (typeof ytgame !== 'undefined') return;
  const LANGUAGE_KEY = 'paper-flight-language';
  const memoryStorage = new Map();

  const B = () => window.bridge || null;

  // ── Storage layer ────────────────────────────────────────────────────
  // Bridge storage is async; we cache everything in a Map for synchronous
  // reads (matching the existing game's localStorage-style access pattern).
  const cache = new Map();
  let bridgeStorageReady = false;

  const ls = {
    getItem(key) {
      try { return localStorage.getItem(key); } catch (_) { return null; }
    },
    setItem(key, value) {
      try { localStorage.setItem(key, String(value)); } catch (_) {}
    },
    removeItem(key) {
      try { localStorage.removeItem(key); } catch (_) {}
    }
  };

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

  function writeCache(key, value) {
    if (value === null || value === undefined) cache.delete(key);
    else cache.set(key, String(value));
  }

  const storage = {
    getItem(key) {
      // Cache may not be populated yet (initBridgeStorage is async and runs
      // after the game reads profiles on startup). Fall back to localStorage
      // so saved players/settings survive between app launches.
      if (cache.has(key)) return cache.get(key);
      return ls.getItem(key);
    },
    setItem(key, value) {
      const text = String(value);
      writeCache(key, text);
      ls.setItem(key, text);
      const b = B();
      if (b && bridgeStorageReady) {
        b.storage.set([key], [text]).catch(() => {});
      }
    },
    removeItem(key) {
      cache.delete(key);
      ls.removeItem(key);
      const b = B();
      if (b && bridgeStorageReady) {
        b.storage.delete([key]).catch(() => {});
      }
    }
  };

  // Load all known keys into cache from Bridge storage, falling back to
  // localStorage for any key Bridge doesn't have.
  async function initBridgeStorage() {
    const b = B();
    if (!b) {
      // No Bridge — populate cache from localStorage.
      for (const k of ALL_STORAGE_KEYS) {
        const v = ls.getItem(k);
        if (v !== null) cache.set(k, v);
      }
      bridgeStorageReady = true;
      return;
    }
    try {
      const values = await b.storage.get(ALL_STORAGE_KEYS);
      let fallbackNeeded = false;
      for (let i = 0; i < ALL_STORAGE_KEYS.length; i++) {
        const k = ALL_STORAGE_KEYS[i];
        const v = values[i];
        if (v !== null && v !== undefined) {
          cache.set(k, String(v));
        } else {
          // Bridge has no value — try localStorage as fallback.
          const lv = ls.getItem(k);
          if (lv !== null) {
            cache.set(k, lv);
            fallbackNeeded = true;
          }
        }
      }
      // Push localStorage fallbacks into Bridge so future sessions get them.
      if (fallbackNeeded) {
        const pushKeys = [], pushVals = [];
        for (const k of ALL_STORAGE_KEYS) {
          const cv = cache.get(k);
          if (cv !== undefined) { pushKeys.push(k); pushVals.push(cv); }
        }
        if (pushKeys.length) b.storage.set(pushKeys, pushVals).catch(() => {});
      }
      bridgeStorageReady = true;
    } catch (_) {
      // Bridge storage failed — fall back to localStorage.
      for (const k of ALL_STORAGE_KEYS) {
        const v = ls.getItem(k);
        if (v !== null) cache.set(k, v);
      }
      bridgeStorageReady = true;
    }
  }

  // ── Language ─────────────────────────────────────────────────────────
  const language = () => {
    const saved = storage.getItem(LANGUAGE_KEY);
    if (saved === 'ru' || saved === 'en') return saved;
    return 'en';
  };

  // ── Callbacks (pause / resume / audio) ──────────────────────────────
  let callbacks = {};

  // ── PaperFlightGamePix adapter ──────────────────────────────────────
  window.PaperFlightGamePix = {
    storage,
    language,
    initBridgeStorage,
    loading() {},
    loaded() {},
    updateScore() {},
    registerCallbacks(nextCallbacks = {}) {
      callbacks = nextCallbacks;
    },
    happyMoment() {},
    gameOver(_score, extraCallbacks) {
      if (extraCallbacks) {
        callbacks = { ...callbacks, ...extraCallbacks };
      }
      return Promise.resolve();
    }
  };

  // Wire Bridge pause / audio events into the adapter callbacks.
  function wireBridgeEvents() {
    const b = B();
    if (!b || !b.platform) return;

    b.platform.on(b.EVENT_NAME.PAUSE_STATE_CHANGED, isPaused => {
      if (isPaused) callbacks.pause?.();
      else callbacks.resume?.();
    });
    b.platform.on(b.EVENT_NAME.AUDIO_STATE_CHANGED, isEnabled => {
      if (isEnabled) callbacks.soundOn?.();
      else callbacks.soundOff?.();
    });
  }

  // ── Language init ───────────────────────────────────────────────────
  try {
    if (!storage.getItem(LANGUAGE_KEY)) {
      storage.setItem(LANGUAGE_KEY, 'en');
    }
  } catch (_) {}

  // ── Touch / mobile detection ────────────────────────────────────────
  const touchDevice =
    matchMedia('(pointer: coarse)').matches ||
    navigator.maxTouchPoints > 0 ||
    'ontouchstart' in window;

  if (touchDevice) {
    document.documentElement.classList.add('mobile-app');
  }

  // ── Launch screen (touch devices only) ──────────────────────────────
  const launchCopy = {
    ru: {
      eyebrow: 'МОБИЛЬНАЯ АРКАДА',
      title: 'БУМАЖНЫЙ ПОЛЁТ',
      tagline: 'Запускай. Лети. Не сдавайся.',
      instruction: 'Нажимай на экран, чтобы самолётик набирал высоту.',
      play: 'ИГРАТЬ',
      privacy: 'Политика конфиденциальности',
      language: 'EN'
    },
    en: {
      eyebrow: 'MOBILE ARCADE',
      title: 'PAPER FLIGHT',
      tagline: 'Launch. Fly. Never give up.',
      instruction: 'Tap the screen to lift the paper plane.',
      play: 'PLAY',
      privacy: 'Privacy policy',
      language: 'RU'
    }
  };

  function createLaunchScreen() {
    const launch = document.createElement('section');
    launch.className = 'mobile-launch';
    launch.setAttribute('role', 'dialog');
    launch.setAttribute('aria-modal', 'true');
    launch.innerHTML = `
      <button class="mobile-launch__language" type="button"></button>
      <div class="mobile-launch__sky" aria-hidden="true">
        <span class="mobile-launch__cloud mobile-launch__cloud--one"></span>
        <span class="mobile-launch__cloud mobile-launch__cloud--two"></span>
        <span class="mobile-launch__column mobile-launch__column--top"></span>
        <span class="mobile-launch__column mobile-launch__column--bottom"></span>
        <span class="mobile-launch__trail"></span>
        <span class="mobile-launch__plane">\u27A4</span>
      </div>
      <div class="mobile-launch__card">
        <p class="mobile-launch__eyebrow"></p>
        <h1 class="mobile-launch__title"></h1>
        <p class="mobile-launch__tagline"></p>
        <p class="mobile-launch__instruction"></p>
        <button class="mobile-launch__play" type="button"></button>
        <a class="mobile-launch__privacy" href="privacy.html"></a>
      </div>
    `;

    const render = () => {
      const currentLanguage = language();
      const copy = launchCopy[currentLanguage];
      launch.lang = currentLanguage;
      launch.querySelector('.mobile-launch__language').textContent = copy.language;
      launch.querySelector('.mobile-launch__eyebrow').textContent = copy.eyebrow;
      launch.querySelector('.mobile-launch__title').textContent = copy.title;
      launch.querySelector('.mobile-launch__tagline').textContent = copy.tagline;
      launch.querySelector('.mobile-launch__instruction').textContent = copy.instruction;
      launch.querySelector('.mobile-launch__play').textContent = copy.play;
      const privacyLink = launch.querySelector('.mobile-launch__privacy');
      privacyLink.textContent = copy.privacy;
      privacyLink.href = `privacy.html?lang=${currentLanguage}`;
    };

    launch.querySelector('.mobile-launch__language').addEventListener('click', () => {
      const nextLanguage = language() === 'ru' ? 'en' : 'ru';
      storage.setItem(LANGUAGE_KEY, nextLanguage);
      const gameLanguageButton = document.querySelector('#language-button');
      if (gameLanguageButton) gameLanguageButton.click();
      render();
    });

    launch.querySelector('.mobile-launch__play').addEventListener('click', () => {
      launch.classList.add('mobile-launch--closing');
      document.documentElement.classList.remove('mobile-launch-visible');
      window.setTimeout(() => launch.remove(), 280);
    });

    launch.addEventListener('click', (event) => {
      if (event.target.closest('.mobile-launch__language')) return;
      if (event.target.closest('.mobile-launch__privacy')) return;
      launch.querySelector('.mobile-launch__play').click();
    });

    render();
    document.documentElement.classList.add('mobile-launch-visible');
    document.body.appendChild(launch);
  }

  if (touchDevice) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', createLaunchScreen, { once: true });
    } else {
      createLaunchScreen();
    }
  }

  for (const eventName of ['contextmenu', 'dragstart', 'selectstart']) {
    document.addEventListener(eventName, (event) => event.preventDefault(), { passive: false });
  }

  // ── Lifecycle events ────────────────────────────────────────────────
  document.addEventListener('visibilitychange', () => {
    const callback = document.hidden ? callbacks.pause : callbacks.resume;
    if (typeof callback === 'function') callback();
  });
  window.addEventListener('pagehide', () => callbacks.pause?.());
  window.addEventListener('pageshow', () => callbacks.resume?.());

  // Bridge pause / audio events are wired from initPlatform() in index.html
  // AFTER registerCallbacks(), so callbacks are available when events fire.

})();
