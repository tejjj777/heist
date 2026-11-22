// The original HEIST OCR engine and language model remain local and offline.
(() => {
  let ready;
  function script(path) {
    return new Promise((resolve, reject) => {
      const element = document.createElement('script');
      element.src = new URL(path, document.baseURI).href;
      element.onload = resolve; element.onerror = reject;
      document.head.append(element);
    });
  }
  window.heistRecognize = async dataUrl => {
    ready ||= script('ocr/tesseract.min.js').then(() => script('ocr/eng-data.js'));
    await ready;
    const bytes = Uint8Array.from(atob(window.HEIST_OCR_ENG), c => c.charCodeAt(0));
    let uses = 0;
    const language = {code: 'eng', get data() { return uses++ === 0 ? bytes : 'eng'; }};
    const worker = await window.Tesseract.createWorker([language], 1, {
      workerPath: new URL('ocr/worker.min.js', document.baseURI).href,
      corePath: new URL('ocr/', document.baseURI).href,
      cacheMethod: 'none',
    });
    try { return (await worker.recognize(dataUrl)).data.text; }
    finally { await worker.terminate(); }
  };
})();
