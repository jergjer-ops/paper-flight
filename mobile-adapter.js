(() => {
  const LANGUAGE_KEY = 'paper-flight-language';
  const memoryStorage = new Map();

  const storage = {
    getItem(key) {
      try {
        return localStorage.getItem(key);
      } catch (_) {
        return memoryStorage.has(key) ? memoryStorage.get(key) : null;
      }
    },
    setItem(key, value) {
      const text = String(value);
      try {
        localStorage.setItem(key, text);
      } catch (_) {
        memoryStorage.set(key, text);
      }
    },
    removeItem(key) {
      try {
        localStorage.removeItem(key);
      } catch (_) {
        memoryStorage.delete(key);
      }
    }
  };

  let callbacks = {};
  const language = () => {
    const saved = storage.getItem(LANGUAGE_KEY);
    if (saved === 'ru' || saved === 'en') return saved;
    return 'en';
  };

  // Compatibility layer for the latest web version. Mobile builds do not
  // contact GamePix and do not insert advertising pauses.
  window.PaperFlightGamePix = {
    storage,
    language,
    loading() {},
    loaded() {},
    updateScore() {},
    registerCallbacks(nextCallbacks = {}) {
      callbacks = nextCallbacks;
    },
    happyMoment() {
      try {
        navigator.vibrate?.(25);
      } catch (_) {}
    },
    gameOver() {
      return Promise.resolve();
    }
  };

  try {
    if (!storage.getItem(LANGUAGE_KEY)) {
      storage.setItem(LANGUAGE_KEY, 'en');
    }
  } catch (_) {
    // The game remains usable when storage is unavailable.
  }

  // The mobile launch screen and full-bleed styles are for touch devices
  // (APK WebView and mobile web). On desktop (GamePix iframe, mouse) the
  // game uses its own web UI and the canvas resizes to fit the frame.
  const touchDevice =
    matchMedia('(pointer: coarse)').matches ||
    navigator.maxTouchPoints > 0 ||
    'ontouchstart' in window;

  if (touchDevice) {
    document.documentElement.classList.add('mobile-app');
  }

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
        <span class="mobile-launch__plane">➤</span>
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
      launch.querySelector('.mobile-launch__privacy').textContent = copy.privacy;
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

    // The instruction says "tap the screen" — so any tap on the launch screen
    // (outside the language switch and the privacy link) starts the game.
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

  document.addEventListener('visibilitychange', () => {
    const callback = document.hidden ? callbacks.pause : callbacks.resume;
    if (typeof callback === 'function') callback();
  });
  window.addEventListener('pagehide', () => callbacks.pause?.());
  window.addEventListener('pageshow', () => callbacks.resume?.());
})();
