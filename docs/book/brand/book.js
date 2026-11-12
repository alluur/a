/* Aytict book: theme switch, menu, search (works from file:// too), copy buttons, "on this page" highlight. */
(function () {
  var doc = document, root = doc.documentElement;
  function store(k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) { return null; } }

  // theme
  var tb = doc.getElementById("theme");
  if (tb) tb.addEventListener("click", function () {
    var cur = root.getAttribute("data-theme") || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    var next = cur === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next); store("ayt-theme", next);
  });

  // menu on small screens
  var mb = doc.getElementById("menu");
  if (mb) {
    mb.addEventListener("click", function () {
      var open = doc.body.classList.toggle("menu-open"); mb.setAttribute("aria-expanded", open ? "true" : "false");
    });
    doc.getElementById("main").addEventListener("click", function () { doc.body.classList.remove("menu-open"); mb.setAttribute("aria-expanded", "false"); });
  }
  var cur = doc.querySelector(".side li.cur"); if (cur && cur.scrollIntoView) { var s = doc.getElementById("side"); if (s) s.scrollTop = Math.max(0, cur.offsetTop - 120); }

  // copy buttons
  Array.prototype.forEach.call(doc.querySelectorAll(".listing pre, .output pre, pre.language-a, pre.language-sh, pre.language-c"), function (pre) {
    var b = doc.createElement("button"); b.className = "copy"; b.type = "button"; b.textContent = "Copy"; b.setAttribute("aria-label", "Copy the code");
    b.addEventListener("click", function () {
      var text = pre.querySelector("code").innerText;
      function done() { b.textContent = "Copied"; setTimeout(function () { b.textContent = "Copy"; }, 1400); }
      if (navigator.clipboard && window.isSecureContext) { navigator.clipboard.writeText(text).then(done, function () {}); return; }
      var ta = doc.createElement("textarea"); ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0"; doc.body.appendChild(ta); ta.select();
      try { doc.execCommand("copy"); done(); } catch (e) {} doc.body.removeChild(ta);
    });
    pre.appendChild(b);
  });

  // search
  var q = doc.getElementById("q"), res = doc.getElementById("results"), idx = window.BOOK_INDEX || [], sel = -1;
  function esc(s) { return s.replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
  function run() {
    var terms = q.value.toLowerCase().split(/\s+/).filter(Boolean);
    if (!terms.length) { res.hidden = true; return; }
    var scored = [];
    for (var i = 0; i < idx.length; i++) {
      var e = idx[i], t = e.t.toLowerCase(), x = (e.x || "").toLowerCase(), sc = 0, ok = true;
      for (var j = 0; j < terms.length; j++) {
        var w = terms[j];
        if (t === w) sc += 12; else if (t.indexOf(w) === 0) sc += 8; else if (t.indexOf(w) >= 0) sc += 5; else if (x.indexOf(w) >= 0) sc += 1; else { ok = false; break; }
      }
      if (ok) scored.push([sc, e]);
    }
    scored.sort(function (a, b) { return b[0] - a[0]; });
    var html = scored.slice(0, 14).map(function (p) {
      var e = p[1], snip = e.x ? e.x.slice(0, 110) : "";
      return '<li><a href="' + e.u + '"><b>' + esc(e.t) + '</b><small>' + esc(e.c) + (snip ? " · " + esc(snip) : "") + "</small></a></li>";
    }).join("");
    res.innerHTML = html || '<li class="none">Nothing found</li>'; res.hidden = false; sel = -1;
  }
  if (q) {
    q.addEventListener("input", run);
    q.addEventListener("keydown", function (ev) {
      var links = res.querySelectorAll("a");
      if (ev.key === "ArrowDown" || ev.key === "ArrowUp") {
        ev.preventDefault(); if (!links.length) return; sel = (sel + (ev.key === "ArrowDown" ? 1 : -1) + links.length) % links.length;
        Array.prototype.forEach.call(links, function (a, i) { a.classList.toggle("sel", i === sel); }); links[sel].scrollIntoView({ block: "nearest" });
      } else if (ev.key === "Enter" && links.length) { location.href = links[sel >= 0 ? sel : 0].getAttribute("href"); }
      else if (ev.key === "Escape") { res.hidden = true; q.blur(); }
    });
    doc.addEventListener("click", function (ev) { if (!res.contains(ev.target) && ev.target !== q) res.hidden = true; });
    doc.addEventListener("keydown", function (ev) { if (ev.key === "/" && doc.activeElement !== q && !/input|textarea/i.test(doc.activeElement.tagName)) { ev.preventDefault(); q.focus(); } });
  }

  // "on this page": mark the section that is in view
  var links = doc.querySelectorAll(".toc a");
  if (links.length && "IntersectionObserver" in window) {
    var map = {}; Array.prototype.forEach.call(links, function (a) { map[a.getAttribute("href").slice(1)] = a; });
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting && map[e.target.id]) { Array.prototype.forEach.call(links, function (a) { a.classList.remove("on"); }); map[e.target.id].classList.add("on"); } });
    }, { rootMargin: "-70px 0px -75% 0px" });
    Object.keys(map).forEach(function (id) { var h = doc.getElementById(id); if (h) io.observe(h); });
  }
})();
