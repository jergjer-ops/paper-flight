(() => {
  if (!/gamedistribution\.com$/i.test(location.hostname)) return;
  if (!window.GD_OPTIONS || !String(window.GD_OPTIONS.gameId || '').trim()) return;
  if (typeof ytgame !== 'undefined' || typeof window.CrazyGames !== 'undefined' || typeof window.bridge !== 'undefined') return;

  const LANGUAGE_KEY = 'paper-flight-language';

  const ls = {
    getItem(key) { try { return localStorage.getItem(key); } catch (_) { return null; } },
    setItem(key, value) { try { localStorage.setItem(key, String(value)); } catch (_) {} },
    removeItem(key) { try { localStorage.removeItem(key); } catch (_) {} }
  };

  const storage = {
    getItem: (key) => ls.getItem(key),
    setItem: (key, value) => ls.setItem(key, value),
    removeItem: (key) => ls.removeItem(key)
  };

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
    initBridgeStorage: () => Promise.resolve(),
    loading() {},
    loaded() {},
    updateScore() {},
    registerCallbacks(nextCallbacks = {}) {
      callbacks = nextCallbacks;
    },
    happyMoment() {},
    gameOver(_score, extraCallbacks) {
      if (extraCallbacks) callbacks = { ...callbacks, ...extraCallbacks };
      return Promise.resolve();
    }
  };

  window.__gdOnEvent = function (event) {
    const name = event && event.name;
    if (name === 'SDK_GAME_PAUSE') {
      callbacks.pause?.();
      callbacks.soundOff?.();
    } else if (name === 'SDK_GAME_START') {
      callbacks.resume?.();
      callbacks.soundOn?.();
    } else if (name === 'SDK_REWARDED_WATCH_COMPLETE') {
      if (typeof window.__gdRewardResolve === 'function') window.__gdRewardResolve(true);
    }
  };

  window._gdRequestRewarded = function () {
    return new Promise(resolve => {
      let settled = false;
      const finish = value => {
        if (settled) return;
        settled = true;
        window.__gdRewardResolve = null;
        resolve(value);
      };
      window.__gdRewardResolve = finish;
      try {
        const sdk = window.gdsdk;
        if (!sdk || typeof sdk.showAd !== 'function') { finish(false); return; }
        const pre = typeof sdk.preloadAd === 'function'
          ? Promise.resolve().then(() => sdk.preloadAd('rewarded'))
          : Promise.resolve();
        pre
          .then(() => sdk.showAd('rewarded'))
          .then(() => setTimeout(() => finish(false), 600))
          .catch(() => finish(false));
      } catch (_) {
        finish(false);
      }
    });
  };

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