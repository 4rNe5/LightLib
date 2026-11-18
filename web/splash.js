// Takes the opening picture away when the app has drawn its first frame
// (a file of its own: the page's content policy allows no inline script).
window.addEventListener('flutter-first-frame', function () {
  var splash = document.getElementById('splash');
  if (!splash) return;
  splash.classList.add('gone');
  setTimeout(function () { splash.remove(); }, 260);
}, { once: true });

// The app draws its own screens (the library, the reader's bars) at no
// more than two device pixels per CSS pixel. A phone has three or more,
// and every frame is drawn, then copied to the page, at that size: at two
// it is less than half the pixels, for text a little softer. The book's
// page is the browser's own and stays as sharp as the screen.
(function () {
  var cap = 2;
  var own = Object.getOwnPropertyDescriptor(window, 'devicePixelRatio') ||
      Object.getOwnPropertyDescriptor(Window.prototype, 'devicePixelRatio');
  if (!own || !own.get) return;
  try {
    Object.defineProperty(window, 'devicePixelRatio', {
      configurable: true,
      enumerable: true,
      get: function () { var real = own.get.call(window); return real > cap ? cap : real; }
    });
  } catch (e) {}
})();
