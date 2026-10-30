// Анимации главной страницы: появление блоков, телефон при прокрутке, слова по очереди, выбор срока
(function () {
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  function clamp(v) { return Math.max(0, Math.min(1, v)); }

  // Блоки плавно проявляются, когда до них докрутили
  var reveal = 'IntersectionObserver' in window ? new IntersectionObserver(function (entries) {
    entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); reveal.unobserve(e.target); } });
  }, { threshold: 0.12, rootMargin: '0px 0px -6% 0px' }) : null;
  document.querySelectorAll('.rv').forEach(function (el) { if (reduce || !reveal) el.classList.add('in'); else reveal.observe(el); });

  // Фраза разбивается на слова — они загораются по мере прокрутки
  var wordBlocks = Array.prototype.map.call(document.querySelectorAll('[data-words]'), function (el) {
    var words = el.textContent.trim().split(/\s+/);
    el.textContent = '';
    var spans = words.map(function (w) {
      var s = document.createElement('span'); s.className = 'w'; s.textContent = w;
      el.appendChild(s); el.appendChild(document.createTextNode(' '));
      return s;
    });
    return { el: el, spans: spans };
  });

  // Экран приложения в телефоне сам «подключается», когда телефон доезжает до середины экрана
  var demo = document.querySelector('[data-demo]');
  var demoState = 'off', demoTimer = null, clockTimer = null;
  function demoSet(state) {
    if (!demo) return;
    demoState = state;
    demo.classList.toggle('connecting', state === 'connecting');
    demo.classList.toggle('on', state === 'on');
    var off = state === 'off';
    demo.querySelector('[data-status]').textContent = off ? 'Не защищено' : state === 'connecting' ? 'Подключение…' : 'Защищено';
    demo.querySelector('[data-sub]').textContent = off ? 'Все видят ваш настоящий IP' : state === 'connecting' ? 'Соединяемся: Нидерланды, Амстердам' : 'Нидерланды · 00:00:00';
    demo.querySelector('[data-flag]').textContent = off ? '🌍' : '🇳🇱';
    demo.querySelector('[data-server]').textContent = off ? 'Вся планета' : 'Нидерланды';
    demo.querySelector('[data-btn]').textContent = off ? 'Включить VPN' : state === 'connecting' ? 'Отменить' : 'Отключить';
  }
  function demoClock() {
    var t0 = Date.now(), sub = demo.querySelector('[data-sub]');
    clearInterval(clockTimer);
    clockTimer = setInterval(function () {
      var s = Math.floor((Date.now() - t0) / 1000);
      var hh = String(Math.floor(s / 3600)).padStart(2, '0'), mm = String(Math.floor(s / 60) % 60).padStart(2, '0'), ss = String(s % 60).padStart(2, '0');
      sub.textContent = 'Нидерланды · ' + hh + ':' + mm + ':' + ss;
    }, 1000);
  }
  function demoFollow(p) {
    if (!demo) return;
    if (p > 0.92 && demoState === 'off') {
      demoSet('connecting');
      demoTimer = setTimeout(function () { demoSet('on'); demoClock(); }, 1300);
    } else if (p < 0.45 && demoState !== 'off') {
      clearTimeout(demoTimer); clearInterval(clockTimer);
      demoSet('off');
    }
  }
  if (reduce && demo) { demoSet('on'); demo.querySelector('[data-sub]').textContent = 'Нидерланды · 00:12:41'; }

  var phones = Array.prototype.slice.call(document.querySelectorAll('[data-scrub]'));
  var pending = false;
  function update() {
    pending = false;
    var vh = window.innerHeight;
    phones.forEach(function (el) {
      var r = el.getBoundingClientRect();
      // 0 — телефон у нижнего края экрана, 1 — в середине
      var p = reduce ? 1 : clamp((vh - r.top) / (vh / 2 + r.height / 2));
      el.style.setProperty('--p', p.toFixed(3));
      if (!reduce) demoFollow(p);
    });
    wordBlocks.forEach(function (b) {
      var r = b.el.getBoundingClientRect();
      var n = Math.round((reduce ? 1 : clamp((vh * 0.88 - r.top) / (vh * 0.55))) * b.spans.length);
      b.spans.forEach(function (s, i) { s.classList.toggle('on', i < n); });
    });
  }
  function tick() { if (!pending) { pending = true; requestAnimationFrame(update); } }
  window.addEventListener('scroll', tick, { passive: true });
  window.addEventListener('resize', function () { placeKnobs(); tick(); });
  tick();

  // Выбор срока: ползунок переезжает, цена плавно пересчитывается (цены — как в приложении, api.plan_price)
  var PLANS = { 1: [50, 50, 0], 3: [144, 48, 4], 6: [270, 45, 10], 9: [378, 42, 16], 12: [468, 39, 22] };
  function termText(m) { return 'за ' + m + ' ' + (m === 1 ? 'месяц' : m < 5 ? 'месяца' : 'месяцев'); }
  var knobs = Array.prototype.map.call(document.querySelectorAll('[data-seg]'), function (seg) {
    var root = seg.closest('[data-plan]');
    var buttons = Array.prototype.slice.call(seg.querySelectorAll('button'));
    var knob = seg.querySelector('.knob');
    var priceEl = root.querySelector('[data-price]');
    var anim = null;
    function moveKnob() {
      var b = buttons.filter(function (x) { return x.getAttribute('aria-checked') === 'true'; })[0];
      if (!b || !b.offsetWidth) return;
      knob.style.width = b.offsetWidth + 'px';
      knob.style.transform = 'translateX(' + b.offsetLeft + 'px)';
    }
    function countTo(to) {
      var from = parseInt(priceEl.textContent, 10) || to;
      if (anim) cancelAnimationFrame(anim);
      if (reduce || from === to) { priceEl.textContent = to; return; }
      var t0 = performance.now(), dur = 520;
      (function step(now) {
        var k = Math.min(1, (now - t0) / dur), e = 1 - Math.pow(1 - k, 3);
        priceEl.textContent = Math.round(from + (to - from) * e);
        if (k < 1) anim = requestAnimationFrame(step);
      })(t0);
    }
    function pick(b) {
      buttons.forEach(function (x) { x.setAttribute('aria-checked', x === b ? 'true' : 'false'); });
      var m = +b.getAttribute('data-m'), plan = PLANS[m];
      countTo(plan[0]);
      root.querySelector('[data-per]').textContent = plan[1];
      root.querySelector('[data-off]').textContent = plan[2] ? 'скидка ' + plan[2] + ' %' : 'без скидки';
      root.querySelector('[data-term]').textContent = termText(m);
      moveKnob();
    }
    buttons.forEach(function (b) { b.addEventListener('click', function () { pick(b); }); });
    seg.addEventListener('keydown', function (ev) {
      if (ev.key !== 'ArrowRight' && ev.key !== 'ArrowLeft') return;
      ev.preventDefault();
      var i = buttons.findIndex(function (x) { return x.getAttribute('aria-checked') === 'true'; });
      var j = Math.max(0, Math.min(buttons.length - 1, i + (ev.key === 'ArrowRight' ? 1 : -1)));
      pick(buttons[j]); buttons[j].focus();
    });
    return moveKnob;
  });
  function placeKnobs() { knobs.forEach(function (f) { f(); }); }
  placeKnobs();
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(placeKnobs);
})();
