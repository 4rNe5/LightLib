// Takes the opening picture away when the app has drawn its first frame
// (a file of its own: the page's content policy allows no inline script).
window.addEventListener('flutter-first-frame', function () {
  var splash = document.getElementById('splash');
  if (!splash) return;
  splash.classList.add('gone');
  setTimeout(function () { splash.remove(); }, 260);
}, { once: true });
