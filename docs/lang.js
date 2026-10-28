// Idioma del sitio. Va en el <head> de las paginas con version en los dos
// idiomas. Una pagina en espanol pasa a la inglesa si la persona ya eligio
// ingles con el interruptor o, en su primera visita, si el navegador esta en
// ingles. Nunca se pasa sola de ingles a espanol: si llego a /en/, lo pidio.
// Sin JS, el interruptor es un enlace normal.
(function () {
  var KEY = 'aura-lang';
  var page = document.documentElement.lang === 'en' ? 'en' : 'es';
  var saved = null;
  try { saved = localStorage.getItem(KEY); } catch (e) {}
  var browser = (navigator.language || '').toLowerCase().indexOf('en') === 0 ? 'en' : 'es';
  var bot = /bot|crawl|spider|slurp|google|bing|yandex|baidu|duckduck/i.test(navigator.userAgent);
  var alt = document.querySelector('link[rel="alternate"][hreflang="en"]');
  if (page === 'es' && !bot && (saved || browser) === 'en' && alt &&
      location.protocol !== 'file:') {
    // Relativa a la pagina (las espanolas estan en la raiz del sitio), para
    // que funcione igual en GitHub Pages y en un servidor local.
    var rel = alt.getAttribute('href').replace(/^https?:\/\/[^/]+\/Aura\//, '');
    location.replace(new URL(rel, location.href).href + location.hash);
    return;
  }

  document.addEventListener('DOMContentLoaded', function () {
    var sw = document.querySelector('.lang-switch');
    if (!sw) return;
    sw.addEventListener('click', function (ev) {
      var lang = sw.getAttribute('data-lang');
      try { localStorage.setItem(KEY, lang); } catch (e) {}
      // Ctrl/Cmd/Shift o boton del medio: nueva pestana, sin animacion.
      if (ev.ctrlKey || ev.metaKey || ev.shiftKey || ev.button !== 0) return;
      if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
      ev.preventDefault();
      sw.classList.toggle('is-en');
      setTimeout(function () { location.href = sw.href; }, 180);
    });
  });
})();
