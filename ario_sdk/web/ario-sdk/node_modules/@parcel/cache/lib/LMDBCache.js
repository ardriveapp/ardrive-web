"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.LMDBCache = void 0;
function _stream() {
  const data = _interopRequireDefault(require("stream"));
  _stream = function () {
    return data;
  };
  return data;
}
function _path() {
  const data = _interopRequireDefault(require("path"));
  _path = function () {
    return data;
  };
  return data;
}
function _util() {
  const data = require("util");
  _util = function () {
    return data;
  };
  return data;
}
function _core() {
  const data = require("@parcel/core");
  _core = function () {
    return data;
  };
  return data;
}
function _fs() {
  const data = require("@parcel/fs");
  _fs = function () {
    return data;
  };
  return data;
}
var _package = _interopRequireDefault(require("../package.json"));
function _lmdb() {
  const data = _interopRequireDefault(require("lmdb"));
  _lmdb = function () {
    return data;
  };
  return data;
}
var _FSCache = require("./FSCache");
function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { default: obj }; }
function _classPrivateMethodInitSpec(obj, privateSet) { _checkPrivateRedeclaration(obj, privateSet); privateSet.add(obj); }
function _checkPrivateRedeclaration(obj, privateCollection) { if (privateCollection.has(obj)) { throw new TypeError("Cannot initialize the same private elements twice on an object"); } }
function _classPrivateMethodGet(receiver, privateSet, fn) { if (!privateSet.has(receiver)) { throw new TypeError("attempted to get private field on non-instance"); } return fn; } // flowlint-next-line untyped-import:off
// $FlowFixMe
const pipeline = (0, _util().promisify)(_stream().default.pipeline);
var _getFilePath = /*#__PURE__*/new WeakSet();
class LMDBCache {
  // $FlowFixMe

  constructor(cacheDir) {
    _classPrivateMethodInitSpec(this, _getFilePath);
    this.fs = new (_fs().NodeFS)();
    this.dir = cacheDir;
    this.fsCache = new _FSCache.FSCache(this.fs, cacheDir);
    this.store = _lmdb().default.open(cacheDir, {
      name: 'parcel-cache',
      encoding: 'binary',
      compression: true
    });
  }
  ensure() {
    return Promise.resolve();
  }
  serialize() {
    return {
      dir: this.dir
    };
  }
  static deserialize(opts) {
    return new LMDBCache(opts.dir);
  }
  has(key) {
    return Promise.resolve(this.store.get(key) != null);
  }
  get(key) {
    let data = this.store.get(key);
    if (data == null) {
      return Promise.resolve(null);
    }
    return Promise.resolve((0, _core().deserialize)(data));
  }
  async set(key, value) {
    await this.setBlob(key, (0, _core().serialize)(value));
  }
  getStream(key) {
    return this.fs.createReadStream(_path().default.join(this.dir, key));
  }
  setStream(key, stream) {
    return pipeline(stream, this.fs.createWriteStream(_path().default.join(this.dir, key)));
  }
  getBlob(key) {
    let buffer = this.store.get(key);
    return buffer != null ? Promise.resolve(buffer) : Promise.reject(new Error(`Key ${key} not found in cache`));
  }
  async setBlob(key, contents) {
    await this.store.put(key, contents);
  }
  getBuffer(key) {
    return Promise.resolve(this.store.get(key));
  }
  hasLargeBlob(key) {
    return this.fs.exists(_classPrivateMethodGet(this, _getFilePath, _getFilePath2).call(this, key, 0));
  }

  // eslint-disable-next-line require-await
  async getLargeBlob(key) {
    return this.fsCache.getLargeBlob(key);
  }

  // eslint-disable-next-line require-await
  async setLargeBlob(key, contents, options) {
    return this.fsCache.setLargeBlob(key, contents, options);
  }
  refresh() {
    // Reset the read transaction for the store. This guarantees that
    // the next read will see the latest changes to the store.
    // Useful in scenarios where reads and writes are multi-threaded.
    // See https://github.com/kriszyp/lmdb-js#resetreadtxn-void
    this.store.resetReadTxn();
  }
}
exports.LMDBCache = LMDBCache;
function _getFilePath2(key, index) {
  return _path().default.join(this.dir, `${key}-${index}`);
}
(0, _core().registerSerializableClass)(`${_package.default.version}:LMDBCache`, LMDBCache);