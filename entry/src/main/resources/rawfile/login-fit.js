(function () {
  // Presentation only: never inspect input values, credentials, cookies or page text.
  if (location.protocol !== 'https:' || !/^(c|v)\.nua\.edu\.cn$/.test(location.hostname)
      || !/\/cas\/login(?:\/|$)/.test(location.pathname)) return '';
  var input = Array.from(document.querySelectorAll('input[type=password]')).find(function (n) { return n.getClientRects().length && n.getBoundingClientRect().width > 40; });
  if (!input) return '';
  var panel = input, base = input.getBoundingClientRect().width;
  for (var parent = input.parentElement; parent && parent !== document.body; parent = parent.parentElement) {
    var box = parent.getBoundingClientRect();
    if (box.width >= base && box.width <= Math.max(620, base + 100) && box.height > 100 && box.height < 800) panel = parent;
  }
  window.__nuaLoginPanel = panel;
  var rect = panel.getBoundingClientRect(), viewport = window.visualViewport;
  return JSON.stringify({width: rect.width, scale: viewport ? viewport.scale : 1});
})();
