/**
 * Lazy Script Loader
 *
 * Loads JS scripts on-demand instead of at page load.
 * Scripts are loaded once and cached — subsequent calls return immediately.
 */
(function() {
  'use strict';

  const _loaded = {};
  const _loading = {};

  /**
   * Load a script by URL. Returns a Promise that resolves when loaded.
   * Subsequent calls for the same URL return immediately.
   */
  function loadScript(url) {
    if (_loaded[url]) return Promise.resolve();
    if (_loading[url]) return _loading[url];

    _loading[url] = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = url;
      script.onload = () => {
        _loaded[url] = true;
        delete _loading[url];
        resolve();
      };
      script.onerror = () => {
        delete _loading[url];
        reject(new Error('Failed to load: ' + url));
      };
      document.head.appendChild(script);
    });

    return _loading[url];
  }

  /**
   * Load an ES module by URL and expose its exports on window.
   */
  function loadModule(url, exportMap) {
    if (_loaded[url]) return Promise.resolve();
    if (_loading[url]) return _loading[url];

    _loading[url] = import(url).then((module) => {
      if (exportMap) {
        for (const [windowKey, moduleKey] of Object.entries(exportMap)) {
          const value = module[moduleKey] || module.default?.[moduleKey];
          if (value === undefined) {
            throw new Error('Missing export: ' + moduleKey + ' from ' + url);
          }
          window[windowKey] = value;
        }
      }
      _loaded[url] = true;
    }).catch((error) => {
      // Allow retry on next call
      throw error;
    }).finally(() => {
      delete _loading[url];
    });

    return _loading[url];
  }

  /**
   * Load Turbo SDK (17 MB) — only when uploads/payments are needed.
   */
  async function loadTurboSDK() {
    if (window.TurboSDKLoaded) return;

    await loadModule('./js/turbo-sdk.bundle.min.js', {
      'TurboFactory': 'TurboFactory',
      'ARToTokenAmount': 'ARToTokenAmount',
      'ARIOToTokenAmount': 'ARIOToTokenAmount',
      'ETHToTokenAmount': 'ETHToTokenAmount',
      'SOLToTokenAmount': 'SOLToTokenAmount',
      'POLToTokenAmount': 'POLToTokenAmount',
      'ArconnectSigner': 'ArconnectSigner',
      'InjectedEthereumSigner': 'InjectedEthereumSigner',
      'tokenToBaseMap': 'tokenToBaseMap',
    });

    window.TurboSDKLoaded = true;
    console.log('Turbo SDK lazy-loaded successfully');
  }

  /**
   * Load ARIO SDK (435 KB) — only when token balance/ARIO features needed.
   */
  async function loadArioSDK() {
    await loadScript('./js/ario_sdk.min.js');
    console.log('ARIO SDK lazy-loaded');
  }

  /**
   * Load EML parser (704 KB) — only when viewing .eml files.
   */
  async function loadEmlParser() {
    await loadScript('./js/js-base64.min.js');
    await loadScript('./js/eml-parse-js.min.js');
    await loadScript('./js/eml_parser.js');
    console.log('EML parser lazy-loaded');
  }

  /**
   * Load PST library (319 KB) — only when PST features accessed.
   */
  async function loadPst() {
    await loadScript('./js/pst.min.js');
    console.log('PST library lazy-loaded');
  }

  /**
   * Load Arweave wallet generator (693 KB) — only for wallet generation.
   * Must temporarily unset define/require to prevent CommonJS detection
   * conflict with dart2js/requirejs.
   */
  async function loadArweaveWallet() {
    if (window.ArweaveWallet) {
      console.log('Arweave wallet already loaded');
      return;
    }

    console.log('[LazyLoader] Loading arweave-wallet.js...');
    console.log('[LazyLoader] window.define exists:', typeof window.define !== 'undefined');
    console.log('[LazyLoader] window.require exists:', typeof window.require !== 'undefined');

    const savedDefine = window.define;
    const savedRequire = window.require;
    window.define = undefined;
    window.require = undefined;
    try {
      await loadScript('./js/arweave-wallet.js');
    } finally {
      window.define = savedDefine;
      window.require = savedRequire;
    }

    if (window.ArweaveWallet) {
      console.log('[LazyLoader] ArweaveWallet loaded successfully, has generateJWKStringFromMnemonic:', typeof window.ArweaveWallet.generateJWKStringFromMnemonic);
    } else {
      console.error('[LazyLoader] FAILED: arweave-wallet.js loaded but window.ArweaveWallet is', typeof window.ArweaveWallet);
    }
  }

  window.LazyLoader = {
    loadScript,
    loadModule,
    loadTurboSDK,
    loadArioSDK,
    loadEmlParser,
    loadPst,
    loadArweaveWallet,
  };
})();
