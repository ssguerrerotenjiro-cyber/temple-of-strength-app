// Compiles a dart2wasm-generated main module from `source` which can then
// be instantiated via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = {builtins: ['js-string'], importedStringConstants: ''};
  return new CompiledApp(
      await _compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm module from `bytes` which is then
// instantiable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = {builtins: ['js-string'], importedStringConstants: ''};
  return new CompiledApp(await WebAssembly.compile(bytes, builtins), builtins);
}

let _isCompileStreamingSupported;
async function _compileStreaming(source, builtins) {
  _isCompileStreamingSupported ??= WebAssembly.compileStreaming(
    new Response(
      new Uint8Array([0,97,115,109,1,0,0,0,1,4,1,96,0,0,2,23,1,14,119,97,115,109,58,106,115,45,115,116,114,105,110,103,4,99,97,115,116,0,0]),
      {headers: {'Content-Type': 'application/wasm'}},
    ),
    builtins,
  ).then(() => false, (e) => e instanceof WebAssembly.CompileError);
  if (await _isCompileStreamingSupported) {
    return WebAssembly.compileStreaming(source, builtins);
  }
  return WebAssembly.compile(await (await source).arrayBuffer(), builtins);
}

class CompiledApp {
  constructor(module, builtins) {
    this.module = module;
    this.builtins = builtins;
  }

  // The second argument is an options object containing:
  // `loadDeferredModules` is a JS function that takes an array of module names
  //   matching wasm files produced by the dart2wasm compiler. It also takes a
  //   callback that should be invoked for each loaded module with 2 arguments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDeferredId` is a JS function that takes load ID produced by the
  //   compiler when the `use-load-ids` option is passed. Each load ID maps to
  //   one or more wasm files as specified in the emitted JSON file. It also
  //   takes a callback that should be invoked for each loaded module with 2
  //   arguments: (1) the module name, (2) the loaded module in a format
  //   supported by `WebAssembly.compile` or `WebAssembly.compileStreaming`.
  //   The callback returns a Promise that resolves when the module is
  //   instantiated.
  //   loadDeferredId should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  async instantiate(additionalImports, {loadDeferredModules, loadDeferredId} = {}) {
    let dartInstance;

    // Prints to the console
    function printToConsole(value) {
      if (typeof dartPrint == "function") {
        dartPrint(value);
        return;
      }
      if (typeof console == "object" && typeof console.log != "undefined") {
        console.log(value);
        return;
      }
      if (typeof print == "function") {
        print(value);
        return;
      }

      throw "Unable to print message: " + value;
    }

    // A special symbol attached to functions that wrap Dart functions.
    const jsWrappedDartFunctionSymbol = Symbol("JSWrappedDartFunction");

    function finalizeWrapper(dartFunction, wrapped) {
      wrapped.dartFunction = dartFunction;
      wrapped[jsWrappedDartFunctionSymbol] = true;
      return wrapped;
    }

    // Imports
    const dart2wasm = {
            AB: x0 => new Int16Array(x0),
      AC: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      AD: (x0,x1,x2) => x0.addEventListener(x1,x2),
      AE: (o, i) => o[i],
      AF: x0 => x0.tiltY,
      AG: (x0,x1) => x0.requestAnimationFrame(x1),
      AH: x0 => x0.unlock(),
      AI: x0 => x0.deref(),
      AJ: (x0,x1) => { x0.src = x1 },
      AK: x0 => x0.readyState,
      AL: x0 => x0.close(),
      AM: x0 => x0.permissions,
      AN: (x0,x1) => { x0.preload = x1 },
      B: s => printToConsole(s),
      BB: x0 => new Uint16Array(x0),
      BC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      BD: (x0,x1,x2) => x0.setAttribute(x1,x2),
      BE: o => o.length,
      BF: x0 => x0.tiltX,
      BG: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      BH: (x0,x1) => x0.lock(x1),
      BI: () => globalThis.WeakRef,
      BJ: () => globalThis.document,
      BK: (x0,x1) => { x0.binaryType = x1 },
      BL: (x0,x1) => x0.postMessage(x1),
      BM: x0 => x0.geolocation,
      BN: x0 => x0.extraAssets,
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: x0 => new Int32Array(x0),
      CC: (x0,x1) => x0.querySelector(x1),
      CD: (x0,x1) => x0.closest(x1),
      CE: o => {
        if (o === undefined) return 1;
        var type = typeof o;
        if (type === 'boolean') return 2;
        if (type === 'number') return 3;
        if (type === 'string') return 4;
        if (o instanceof Array) return 5;
        if (ArrayBuffer.isView(o)) {
          if (o instanceof Int8Array) return 6;
          if (o instanceof Uint8Array) return 7;
          if (o instanceof Uint8ClampedArray) return 8;
          if (o instanceof Int16Array) return 9;
          if (o instanceof Uint16Array) return 10;
          if (o instanceof Int32Array) return 11;
          if (o instanceof Uint32Array) return 12;
          if (o instanceof Float32Array) return 13;
          if (o instanceof Float64Array) return 14;
          if (o instanceof DataView) return 15;
        }
        if (o instanceof ArrayBuffer) return 16;
        // Feature check for `SharedArrayBuffer` before doing a type-check.
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
            return 17;
        }
        if (o instanceof Promise) return 18;
        return 19;
      },
      CF: x0 => x0.pointerType,
      CG: x0 => x0.now(),
      CH: x0 => x0.orientation,
      CI: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      CJ: x0 => x0.src,
      CK: (a, l) => a.length = l,
      CL: (x0,x1) => { x0.onmessage = x1 },
      CM: x0 => x0.mediaDevices,
      CN: x0 => x0.fontManifest,
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      DC: (x0,x1) => x0.item(x1),
      DD: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      DE: x0 => x0.language,
      DF: x0 => x0.pointerId,
      DG: x0 => x0.performance,
      DH: (x0,x1) => x0.querySelector(x1),
      DI: (a, s, e) => a.slice(s, e),
      DJ: x0 => x0.close(),
      DK: (a, i) => a.splice(i, 1)[0],
      DL: x0 => x0.canvasKitMaximumSurfaces,
      DM: (x0,x1) => x0.querySelector(x1),
      DN: x0 => x0.assetManifest,
      E: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      EB: x0 => new Uint32Array(x0),
      EC: x0 => x0.length,
      ED: (handle) => clearTimeout(handle),
      EE: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      EF: x0 => x0.getCoalescedEvents(),
      EG: (d, digits) => d.toFixed(digits),
      EH: (x0,x1) => { x0.title = x1 },
      EI: x0 => x0.pop(),
      EJ: x0 => x0.height,
      EK: x0 => globalThis.URL.createObjectURL(x0),
      EL: x0 => x0.nextSibling,
      EM: (x0,x1) => x0.append(x1),
      EN: x0 => x0.buildConfig,
      F: () => new Error().stack,
      FB: x0 => new Float32Array(x0),
      FC: (x0,x1) => x0.querySelectorAll(x1),
      FD: x0 => x0.maxTouchPoints,
      FE: () => globalThis.window.FinalizationRegistry,
      FF: s => s.trimLeft(),
      FG: x0 => x0.maxHeight,
      FH: (x0,x1) => x0.vibrate(x1),
      FI: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      FJ: x0 => x0.width,
      FK: x0 => ({type: x0}),
      FL: (x0,x1) => x0.debug(x1),
      FM: x0 => x0.body,
      FN: x0 => x0.length,
      G: s => JSON.stringify(s),
      GB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      GC: (x0,x1) => x0.getAttribute(x1),
      GD: x0 => x0.platform,
      GE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      GF: (x0,x1) => x0[x1],
      GG: x0 => x0.maxWidth,
      GH: x0 => x0.arrayBuffer(),
      GI: () => {
        // On browsers return `globalThis.location.href`
        if (globalThis.location != null) {
          return globalThis.location.href;
        }
        return null;
      },
      GJ: (x0,x1,x2,x3,x4,x5) => x0.createImageBitmap(x1,x2,x3,x4,x5),
      GK: (x0,x1) => new Blob(x0,x1),
      GL: x0 => x0.hostElement,
      GM: x0 => globalThis.URL.revokeObjectURL(x0),
      GN: x0 => x0.getReader(),
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: x0 => new Float64Array(x0),
      HC: x0 => x0.remove(),
      HD: s => new Date(s * 1000).getTimezoneOffset() * 60,
      HE: x0 => new window.FinalizationRegistry(x0),
      HF: x0 => x0.index,
      HG: x0 => x0.minHeight,
      HH: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      HI: () => new AbortController(),
      HJ: (x0,x1) => x0.createImageBitmap(x1),
      HK: (x0,x1,x2,x3) => x0.putImageData(x1,x2,x3),
      HL: x0 => x0.location,
      HM: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      HN: x0 => x0.value,
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      IC: (x0,x1) => x0.appendChild(x1),
      ID: Date.now,
      IE: (x0,x1) => x0.unregister(x1),
      IF: (x0,x1) => x0.exec(x1),
      IG: x0 => x0.minWidth,
      IH: x0 => x0.status,
      II: (x0,x1,x2,x3,x4,x5) => ({method: x0,headers: x1,body: x2,credentials: x3,redirect: x4,signal: x5}),
      IJ: x0 => new Blob(x0),
      IK: x0 => x0.arrayBuffer(),
      IL: (x0,x1) => x0.getModifierState(x1),
      IM: (x0,x1,x2,x3) => x0.toBlob(x1,x2,x3),
      IN: x0 => x0.done,
      J: (s, p, i) => s.lastIndexOf(p, i),
      JB: x0 => new ArrayBuffer(x0),
      JC: (x0,x1) => x0.append(x1),
      JD: (x0,x1) => x0.contains(x1),
      JE: x0 => x0.preventDefault(),
      JF: s => s.toUpperCase(),
      JG: (x0,x1) => x0.removeProperty(x1),
      JH: (x0,x1) => x0.fetch(x1),
      JI: (x0,x1) => globalThis.fetch(x0,x1),
      JJ: x0 => x0.close(),
      JK: (x0,x1) => x0.transferFromImageBitmap(x1),
      JL: x0 => x0.metaKey,
      JM: (x0,x1,x2,x3) => x0.drawImage(x1,x2,x3),
      JN: x0 => x0.read(),
      K: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      KB: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      KC: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      KD: (decoder, codeUnits) => decoder.decode(codeUnits),
      KE: x0 => x0.parent,
      KF: x0 => x0.length,
      KG: (x0,x1) => x0.add(x1),
      KH: x0 => x0.content,
      KI: (x0,x1) => x0.get(x1),
      KJ: x0 => x0.naturalHeight,
      KK: x0 => x0.rasterEndMilliseconds,
      KL: x0 => x0.altKey,
      KM: (x0,x1,x2,x3,x4,x5) => x0.drawImage(x1,x2,x3,x4,x5),
      KN: x0 => x0.body,
      L: o => o === undefined,
      LB: (x0,x1,x2) => new DataView(x0,x1,x2),
      LC: x0 => x0.style,
      LD: () => new TextDecoder("utf-8", {fatal: true}),
      LE: x0 => x0.timeStamp,
      LF: x0 => x0.flags,
      LG: x0 => x0.data,
      LH: x0 => x0.document,
      LI: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2) { return wasmFunction(f,arguments.length,x0,x1,x2) }),
      LJ: x0 => x0.naturalWidth,
      LK: x0 => x0.rasterStartMilliseconds,
      LL: x0 => x0.ctrlKey,
      LM: x0 => x0.height,
      LN: x0 => x0.assetBase,
      M: o => String(o),
      MB: (o, p) => o[p],
      MC: x0 => x0.debugShowSemanticsNodes,
      MD: () => new TextDecoder("utf-8", {fatal: false}),
      ME: (x0,x1) => x0.hasAttribute(x1),
      MF: (a, s) => a.join(s),
      MG: (x0,x1) => x0.removeAttribute(x1),
      MH: () => typeof dartUseDateNowForTicks !== "undefined",
      MI: (x0,x1) => x0.forEach(x1),
      MJ: (x0,x1) => { x0.src = x1 },
      MK: x0 => x0.imageBitmaps,
      ML: x0 => x0.isComposing,
      MM: x0 => x0.width,
      MN: x0 => x0.loader,
      N: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      NB: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      NC: o => o,
      ND: (a, i, v) => a[i] = v,
      NE: x0 => x0.type,
      NF: (x0,x1) => x0.error(x1),
      NG: (x0,x1) => { x0.value = x1 },
      NH: () => Date.now(),
      NI: x0 => x0.name,
      NJ: x0 => x0.displayHeight,
      NK: (x0,x1) => { x0.height = x1 },
      NL: x0 => x0.code,
      NM: (x0,x1) => x0.getContext(x1),
      NN: () => globalThis._flutter,
      O: (x0,x1) => x0.didCreateEngineInitializer(x1),
      OB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      OC: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      OD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      OE: (x0,x1) => x0.getModifierState(x1),
      OF: () => globalThis.console,
      OG: (x0,x1) => { x0.value = x1 },
      OH: () => 1000 * performance.now(),
      OI: x0 => x0.statusText,
      OJ: x0 => x0.displayWidth,
      OK: (x0,x1) => { x0.width = x1 },
      OL: x0 => x0.repeat,
      OM: (x0,x1) => { x0.height = x1 },
      P: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      PB: o => o.byteOffset,
      PC: (x0,x1) => x0.warn(x1),
      PD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      PE: x0 => x0.buttons,
      PF: s => s.trimRight(),
      PG: x0 => x0.value,
      PH: x0 => new Uint8Array(x0),
      PI: x0 => x0.url,
      PJ: x0 => x0.duration,
      PK: x0 => x0.convertToBlob(),
      PL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      PM: (x0,x1) => { x0.width = x1 },
      Q: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      QB: o => o.buffer,
      QC: x0 => x0.console,
      QD: (s) => +s,
      QE: x0 => x0.ctrlKey,
      QF: x0 => x0.blur(),
      QG: x0 => x0.selectionDirection,
      QH: (x0,x1,x2) => x0.slice(x1,x2),
      QI: x0 => x0.status,
      QJ: (x0,x1) => ({frameIndex: x0,completeFramesOnly: x1}),
      QK: (x0,x1,x2) => new ImageData(x0,x1,x2),
      QL: x0 => x0.load(),
      QM: x0 => x0.height,
      R: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      RB: Function.prototype.call.bind(DataView.prototype.getUint8),
      RC: () => globalThis.window,
      RD: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      RE: x0 => x0.getBoundingClientRect(),
      RF: x0 => x0.button,
      RG: x0 => x0.selectionStart,
      RH: (x0,x1) => x0.decode(x1),
      RI: x0 => x0.getReader(),
      RJ: (x0,x1) => x0.decode(x1),
      RK: (x0,x1) => x0.getContext(x1),
      RL: (x0,x1) => { x0.src = x1 },
      RM: x0 => x0.width,
      S: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      SB: (b, o) => new DataView(b, o),
      SC: (o, c) => o instanceof c,
      SD: s => s.trim(),
      SE: x0 => x0.y,
      SF: (x0,x1) => x0.prepend(x1),
      SG: x0 => x0.selectionEnd,
      SH: (x0,x1) => x0.adoptText(x1),
      SI: x0 => x0.read(),
      SJ: x0 => x0.image,
      SK: (x0,x1) => new OffscreenCanvas(x0,x1),
      SL: x0 => x0.message,
      SM: x0 => x0.remove(),
      T: x0 => new Promise(x0),
      TB: (b, o, l) => new DataView(b, o, l),
      TC: (string, token) => string.split(token),
      TD: x0 => x0.classList,
      TE: x0 => x0.x,
      TF: x0 => x0.parentElement,
      TG: x0 => x0.value,
      TH: x0 => x0.first(),
      TI: x0 => x0.value,
      TJ: x0 => x0.close(),
      TK: x0 => x0.allocationSize(),
      TL: x0 => x0.code,
      TM: (x0,x1) => { x0.src = x1 },
      U: (x0,x1,x2) => x0.call(x1,x2),
      UB: Function.prototype.call.bind(DataView.prototype.getFloat64),
      UC: o => o instanceof Array,
      UD: x0 => x0.relatedTarget,
      UE: x0 => x0.top,
      UF: x0 => x0.innerHeight,
      UG: x0 => x0.selectionDirection,
      UH: x0 => x0.next(),
      UI: x0 => x0.done,
      UJ: (x0,x1,x2,x3,x4) => ({type: x0,data: x1,premultiplyAlpha: x2,colorSpaceConversion: x3,preferAnimation: x4}),
      UK: (x0,x1) => x0.copyTo(x1),
      UL: x0 => x0.error,
      UM: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      V: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      VB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      VC: (a, i) => a[i],
      VD: x0 => x0.hasFocus(),
      VE: x0 => x0.left,
      VF: x0 => x0.innerWidth,
      VG: x0 => x0.selectionStart,
      VH: x0 => x0.current(),
      VI: x0 => x0.cancel(),
      VJ: x0 => new window.ImageDecoder(x0),
      VK: (x0,x1) => { x0.height = x1 },
      VL: (x0,x1) => x0.start(x1),
      VM: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      W: x0 => new Array(x0),
      WB: Function.prototype.call.bind(DataView.prototype.setFloat64),
      WC: a => a.length,
      WD: x0 => x0.shiftKey,
      WE: x0 => x0.scrollTop,
      WF: x0 => x0.height,
      WG: x0 => x0.selectionEnd,
      WH: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      WI: x0 => x0.body,
      WJ: x0 => x0.name,
      WK: (x0,x1) => { x0.width = x1 },
      WL: (x0,x1) => x0.end(x1),
      WM: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      X: o => [o],
      XB: (t, s) => t.set(s),
      XC: (x0,x1) => x0.test(x1),
      XD: x0 => x0.body,
      XE: x0 => x0.offsetTop,
      XF: x0 => x0.width,
      XG: (x0,x1) => { x0.name = x1 },
      XH: x0 => x0.v8BreakIterator,
      XI: x0 => x0.headers,
      XJ: x0 => x0.repetitionCount,
      XK: (x0,x1) => x0.toDataURL(x1),
      XL: x0 => x0.length,
      XM: (x0,x1) => { x0.onerror = x1 },
      Y: (o0, o1) => [o0, o1],
      YB: Function.prototype.call.bind(DataView.prototype.setFloat32),
      YC: x0 => x0.userAgent,
      YD: x0 => x0.visibilityState,
      YE: x0 => x0.scrollLeft,
      YF: x0 => x0.clientHeight,
      YG: (x0,x1) => { x0.placeholder = x1 },
      YH: () => globalThis.Intl,
      YI: x0 => x0.signal,
      YJ: x0 => x0.frameCount,
      YK: (x0,x1,x2,x3) => x0.drawImage(x1,x2,x3),
      YL: x0 => x0.buffered,
      YM: (x0,x1) => { x0.oncancel = x1 },
      Z: (o0, o1, o2) => [o0, o1, o2],
      ZB: Function.prototype.call.bind(DataView.prototype.getFloat32),
      ZC: x0 => x0.navigator,
      ZD: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      ZE: x0 => x0.offsetLeft,
      ZF: x0 => x0.clientWidth,
      ZG: (x0,x1) => { x0.autocomplete = x1 },
      ZH: (x0,x1) => x0.segment(x1),
      ZI: x0 => x0.abort(),
      ZJ: x0 => x0.selectedTrack,
      ZK: (x0,x1,x2,x3,x4,x5,x6,x7,x8,x9) => x0.drawImage(x1,x2,x3,x4,x5,x6,x7,x8,x9),
      ZL: x0 => x0.videoWidth,
      ZM: (x0,x1) => { x0.onchange = x1 },
      a: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      aB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      aC: Function.prototype.call.bind(String.prototype.toLowerCase),
      aD: x0 => x0.disconnect(),
      aE: x0 => x0.offsetParent,
      aF: x0 => x0.isConnected,
      aG: (x0,x1) => { x0.type = x1 },
      aH: x0 => x0.index,
      aI: (x0,x1) => x0.getRandomValues(x1),
      aJ: x0 => x0.completed,
      aK: (x0,x1) => x0.getContext(x1),
      aL: x0 => x0.videoHeight,
      aM: x0 => x0.type,
      b: (x0,x1,x2) => { x0[x1] = x2 },
      bB: Function.prototype.call.bind(DataView.prototype.getUint32),
      bC: Object.is,
      bD: x0 => new Intl.Locale(x0),
      bE: x0 => x0.offsetY,
      bF: x0 => x0.head,
      bG: (x0,x1) => { x0.name = x1 },
      bH: x0 => x0.next(),
      bI: () => globalThis.crypto,
      bJ: x0 => x0.ready,
      bK: x0 => x0.format,
      bL: x0 => x0.duration,
      bM: x0 => x0.lastModified,
      c: o => o,
      cB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      cC: x0 => x0.vendor,
      cD: x0 => x0.region,
      cE: x0 => x0.offsetX,
      cF: (x0,x1) => { x0.content = x1 },
      cG: (x0,x1) => { x0.placeholder = x1 },
      cH: x0 => x0.value,
      cI: l => new DataView(new ArrayBuffer(l)),
      cJ: x0 => x0.tracks,
      cK: (x0,x1,x2,x3,x4) => x0.getImageData(x1,x2,x3,x4),
      cL: (x0,x1) => { x0.playsInline = x1 },
      cM: x0 => x0.name,
      d: (o, p) => o[p],
      dB: Function.prototype.call.bind(DataView.prototype.getInt32),
      dC: (x0,x1) => x0.createTextNode(x1),
      dD: x0 => x0.script,
      dE: (o, p, r) => o.replace(p, () => r),
      dF: (x0,x1) => { x0.name = x1 },
      dG: (x0,x1) => { x0.scrollTop = x1 },
      dH: x0 => x0.done,
      dI: () => new FileReader(),
      dJ: () => globalThis.window.ImageDecoder,
      dK: x0 => x0.data,
      dL: (x0,x1) => { x0.controls = x1 },
      dM: (x0,x1) => x0.item(x1),
      e: () => globalThis,
      eB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      eC: (x0,x1) => { x0.id = x1 },
      eD: x0 => x0.language,
      eE: (x0,x1) => { x0.lastIndex = x1 },
      eF: (x0,x1) => x0.removeChild(x1),
      eG: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      eH: (o, m, a) => o[m].apply(o, a),
      eI: (x0,x1) => x0.readAsArrayBuffer(x1),
      eJ: x0 => x0.decode(),
      eK: (x0,x1,x2) => x0.insertBefore(x1,x2),
      eL: (x0,x1) => { x0.autoplay = x1 },
      eM: x0 => x0.length,
      f: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fB: o => o instanceof Uint16Array,
      fC: (x0,x1) => { x0.nonce = x1 },
      fD: x0 => x0.languages,
      fE: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      fF: x0 => x0.firstChild,
      fG: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      fH: x0 => x0.iterator,
      fI: x0 => x0.result,
      fJ: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      fK: x0 => x0.id,
      fL: (x0,x1) => { x0.width = x1 },
      fM: x0 => x0.files,
      g: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      gB: Function.prototype.call.bind(DataView.prototype.getUint16),
      gC: x0 => x0.nonce,
      gD: (x0,x1) => x0.observe(x1),
      gE: o => o instanceof RegExp,
      gF: x0 => x0.viewConstraints,
      gG: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      gH: () => globalThis.Symbol,
      gI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      gJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      gK: x0 => x0.offsetHeight,
      gL: (x0,x1) => { x0.height = x1 },
      gM: x0 => x0.target,
      h: (x0,x1) => ({addView: x0,removeView: x1}),
      hB: o => o instanceof Int16Array,
      hC: () => globalThis.window.flutterConfiguration,
      hD: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      hE: x0 => x0.dotAll,
      hF: x0 => x0.hostElement,
      hG: x0 => x0.keyCode,
      hH: (x0,x1) => new Intl.Segmenter(x0,x1),
      hI: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      hJ: (x0,x1,x2) => x0.addEventListener(x1,x2),
      hK: x0 => x0.offsetWidth,
      hL: (x0,x1) => { x0.border = x1 },
      hM: (x0,x1) => x0.replaceChildren(x1),
      i: (l, r) => l === r,
      iB: Function.prototype.call.bind(DataView.prototype.getInt16),
      iC: (x0,x1) => x0.attachShadow(x1),
      iD: x0 => new ResizeObserver(x0),
      iE: x0 => x0.unicode,
      iF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      iG: (x0,x1) => x0.scrollIntoView(x1),
      iH: x0 => x0.Segmenter,
      iI: (x0,x1,x2,x3) => x0.removeEventListener(x1,x2,x3),
      iJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      iK: x0 => x0.stopPropagation(),
      iL: x0 => x0.style,
      iM: x0 => x0.click(),
      j: x0 => x0.random(),
      jB: o => o instanceof Uint8ClampedArray,
      jC: (x0,x1) => x0.createElement(x1),
      jD: (x0,x1) => x0.getPropertyValue(x1),
      jE: x0 => x0.ignoreCase,
      jF: x0 => ({runApp: x0}),
      jG: x0 => x0.multiViewEnabled,
      jH: x0 => x0.buffer,
      jI: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      jJ: x0 => x0.send(),
      jK: x0 => x0.disabled,
      jL: (x0,x1) => { x0.id = x1 },
      jM: (x0,x1,x2) => x0.setAttribute(x1,x2),
      k: o => o,
      kB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      kC: x0 => x0.scale,
      kD: x0 => globalThis.parseFloat(x0),
      kE: x0 => x0.multiline,
      kF: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      kG: (x0,x1) => x0.replaceWith(x1),
      kH: x0 => x0.wasmMemory,
      kI: () => new XMLHttpRequest(),
      kJ: x0 => x0.status,
      kK: (x0,x1) => { x0.min = x1 },
      kL: (x0,x1) => x0.createElement(x1),
      kM: (x0,x1) => { x0.accept = x1 },
      l: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      lB: Function.prototype.call.bind(DataView.prototype.setInt32),
      lC: x0 => x0.visualViewport,
      lD: (x0,x1) => x0.getComputedStyle(x1),
      lE: (o, p, r) => o.replaceAll(p, () => r),
      lF: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      lG: (x0,x1) => { x0.className = x1 },
      lH: () => globalThis.window._flutter_skwasmInstance,
      lI: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      lJ: x0 => x0.response,
      lK: (x0,x1) => { x0.max = x1 },
      lL: () => globalThis.document,
      lM: (x0,x1) => { x0.multiple = x1 },
      m: () => globalThis.Math,
      mB: Function.prototype.call.bind(DataView.prototype.setUint32),
      mC: x0 => x0.devicePixelRatio,
      mD: x0 => x0.documentElement,
      mE: x0 => x0.deltaMode,
      mF: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      mG: (x0,x1) => { x0.tabIndex = x1 },
      mH: () => new TextDecoder(),
      mI: x0 => x0.send(),
      mJ: (x0,x1,x2) => x0.setRequestHeader(x1,x2),
      mK: (x0,x1) => { x0.disabled = x1 },
      mL: (x0,x1) => { x0.loop = x1 },
      mM: (x0,x1) => { x0.type = x1 },
      n: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      nB: Function.prototype.call.bind(DataView.prototype.setInt16),
      nC: x0 => x0.height,
      nD: x0 => x0.computedStyleMap(),
      nE: x0 => x0.deltaY,
      nF: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      nG: (x0,x1) => { x0.action = x1 },
      nH: (map, o, v) => map.set(o, v),
      nI: x0 => x0.type,
      nJ: (x0,x1) => { x0.responseType = x1 },
      nK: (x0,x1) => { x0.scrollLeft = x1 },
      nL: (x0,x1) => x0.removeAttribute(x1),
      nM: x0 => x0.close(),
      o: b => !!b,
      oB: Function.prototype.call.bind(DataView.prototype.setUint16),
      oC: x0 => x0.width,
      oD: (x0,x1) => x0.get(x1),
      oE: x0 => x0.deltaX,
      oF: x0 => x0.history,
      oG: (x0,x1) => { x0.method = x1 },
      oH: (map, o) => map.get(o),
      oI: x0 => x0.response,
      oJ: () => new XMLHttpRequest(),
      oK: (x0,x1) => { x0.spellcheck = x1 },
      oL: (x0,x1) => { x0.currentTime = x1 },
      oM: x0 => x0.disconnect(),
      p: () => globalThis.document,
      pB: Function.prototype.call.bind(DataView.prototype.setUint8),
      pC: x0 => x0.screen,
      pD: (o, p) => p in o,
      pE: x0 => x0.wheelDeltaY,
      pF: x0 => x0.search,
      pG: (x0,x1) => { x0.noValidate = x1 },
      pH: () => new WeakMap(),
      pI: (x0,x1) => { x0.responseType = x1 },
      pJ: x0 => x0.size,
      pK: (x0,x1) => { x0.disabled = x1 },
      pL: x0 => x0.currentTime,
      pM: (x0,x1) => { x0.value = x1 },
      q: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      qB: Function.prototype.call.bind(DataView.prototype.setInt8),
      qC: (string, times) => string.repeat(times),
      qD: (x0,x1) => { x0.textContent = x1 },
      qE: x0 => x0.wheelDeltaX,
      qF: x0 => x0.location,
      qG: x0 => x0.click(),
      qH: x0 => x0.debugSkipFontRetryDelay,
      qI: x0 => x0.vendor,
      qJ: () => new Array(),
      qK: (x0,x1) => x0.getItem(x1),
      qL: (x0,x1) => { x0.playbackRate = x1 },
      qM: x0 => x0.gain,
      r: (x0,x1) => x0.focus(x1),
      rB: Function.prototype.call.bind(DataView.prototype.getInt8),
      rC: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      rD: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      rE: x0 => x0.bottom,
      rF: x0 => x0.pathname,
      rG: (x0,x1) => x0.getElementsByClassName(x1),
      rH: (a, l) => a.length = l,
      rI: x0 => x0.navigator,
      rJ: (x0,x1) => new WebSocket(x0,x1),
      rK: x0 => x0.localStorage,
      rL: x0 => x0.pause(),
      rM: x0 => x0.resume(),
      s: () => ({}),
      sB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      sC: x0 => x0.tabIndex,
      sD: x0 => x0.matches,
      sE: x0 => x0.right,
      sF: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      sG: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      sH: (x0,x1,x2) => x0.set(x1,x2),
      sI: () => globalThis.window,
      sJ: x0 => x0.reason,
      sK: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      sL: x0 => x0.play(),
      sM: x0 => x0.state,
      t: (o, p, v) => o[p] = v,
      tB: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      tC: (x0,x1) => x0.contains(x1),
      tD: (x0,x1) => x0.matchMedia(x1),
      tE: x0 => x0.clientY,
      tF: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      tG: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      tH: x0 => x0.fontFallbackBaseUrl,
      tI: x0 => x0.naturalHeight,
      tJ: x0 => x0.code,
      tK: x0 => x0.history,
      tL: x0 => x0.message,
      tM: () => new AudioContext(),
      u: () => [],
      uB: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      uC: x0 => x0.activeElement,
      uD: x0 => x0.matches,
      uE: x0 => x0.clientX,
      uF: o => Object.keys(o),
      uG: (x0,x1) => x0.dispatchEvent(x1),
      uH: (handle) => clearInterval(handle),
      uI: x0 => x0.naturalWidth,
      uJ: (o, t) => typeof o === t,
      uK: x0 => x0.href,
      uL: (x0,x1) => { x0.volume = x1 },
      uM: (x0,x1) => x0.createMediaElementSource(x1),
      v: (a, i) => a.push(i),
      vB: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      vC: x0 => x0.parentNode,
      vD: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      vE: x0 => x0.changedTouches,
      vF: x0 => x0.state,
      vG: (x0,x1) => x0.createEvent(x1),
      vH: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      vI: (x0,x1) => x0.createElement(x1),
      vJ: x0 => x0.data,
      vK: x0 => x0.location,
      vL: (x0,x1) => { x0.muted = x1 },
      vM: x0 => x0.createGain(),
      w: x0 => new Int8Array(x0),
      wB: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      wC: x0 => x0.tagName,
      wD: f => f.dartFunction,
      wE: x0 => x0.key,
      wF: x0 => x0.hash,
      wG: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      wH: () => Date.now(),
      wI: (x0,x1) => { x0.pointerEvents = x1 },
      wJ: (x0,x1,x2) => x0.close(x1,x2),
      wK: (x0,x1) => x0.removeItem(x1),
      wL: x0 => x0.userAgent,
      wM: x0 => x0.createStereoPanner(),
      x: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      xB: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      xC: x0 => x0.target,
      xD: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      xE: x0 => x0.identifier,
      xF: x0 => x0.state,
      xG: x0 => x0.readText(),
      xH: (a, i) => a.splice(i, 1),
      xI: (x0,x1) => { x0.height = x1 },
      xJ: (x0,x1) => x0.close(x1),
      xK: (x0,x1,x2) => x0.setItem(x1,x2),
      xL: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      xM: (x0,x1) => x0.connect(x1),
      y: x0 => new Uint8Array(x0),
      yB: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      yC: x0 => x0.clientY,
      yD: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      yE: x0 => x0.touches,
      yF: (x0,x1) => x0.go(x1),
      yG: x0 => x0.clipboard,
      yH: a => a.pop(),
      yI: (x0,x1) => { x0.width = x1 },
      yJ: x0 => x0.close(),
      yK: x0 => new BroadcastChannel(x0),
      yL: (x0,x1) => x0.key(x1),
      yM: x0 => x0.destination,
      z: x0 => new Uint8ClampedArray(x0),
      zB: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      zC: x0 => x0.clientX,
      zD: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      zE: x0 => x0.pressure,
      zF: (x0,x1) => x0.querySelectorAll(x1),
      zG: (x0,x1) => x0.writeText(x1),
      zH: x0 => new WeakRef(x0),
      zI: x0 => x0.style,
      zJ: (x0,x1) => x0.send(x1),
      zK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      zL: x0 => x0.length,
      zM: (x0,x1) => { x0.crossOrigin = x1 },

    };

    const baseImports = {
      _: dart2wasm,
      Math: Math,
      Date: Date,
      Object: Object,
      Array: Array,
      Reflect: Reflect,
      WebAssembly: {
        JSTag: WebAssembly.JSTag,
      },
      "": new Proxy({}, { get(_, prop) { return prop; } }),

    };

    

    dartInstance = await WebAssembly.instantiate(this.module, {
      ...baseImports,
      ...additionalImports,
      
    });

    return new InstantiatedApp(this, dartInstance);
  }
}

class InstantiatedApp {
  constructor(compiledApp, instantiatedModule) {
    this.compiledApp = compiledApp;
    this.instantiatedModule = instantiatedModule;
  }

  // Call the main function with the given arguments.
  invokeMain(...args) {
    this.instantiatedModule.exports.$invokeMain(args);
  }
}
