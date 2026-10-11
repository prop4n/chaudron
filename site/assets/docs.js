// The menu on small screens, the table of contents following the reading,
// and the search (Ctrl K or /).
(function () {
  // Menu
  var menuButton = document.querySelector(".menu-button");
  if (menuButton) {
    menuButton.addEventListener("click", function () {
      var open = document.body.classList.toggle("menu-open");
      menuButton.setAttribute("aria-expanded", String(open));
    });
  }

  // On this page: mark the section being read
  var tocLinks = document.querySelectorAll(".docs-toc a, .toc-mobile a");
  var headings = document.querySelectorAll(".prose h2[id], .prose h3[id]");

  if (tocLinks.length && headings.length) {
    var marked = null;
    var update = function () {
      var id = null;
      headings.forEach(function (h) {
        if (h.getBoundingClientRect().top < 120) id = h.id;
      });
      if (id === marked) return;
      marked = id;
      tocLinks.forEach(function (a) {
        if (a.getAttribute("href") === "#" + id) a.setAttribute("aria-current", "true");
        else a.removeAttribute("aria-current");
      });
    };
    var scheduled = false;
    window.addEventListener("scroll", function () {
      if (scheduled) return;
      scheduled = true;
      requestAnimationFrame(function () { scheduled = false; update(); });
    }, { passive: true });
    update();
  }

  // Search
  var dialog = document.getElementById("search");
  var input = document.getElementById("search-input");
  var list = document.getElementById("search-results");
  if (!dialog || !input || !list) return;

  var index = null;
  var loading = null;

  function normalize(s) {
    return s.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  }

  function load() {
    if (!loading) {
      loading = fetch("/docs/search.json")
        .then(function (r) { return r.json(); })
        .then(function (entries) {
          index = entries.map(function (e) {
            e.nTitle = normalize(e.title);
            e.nText = normalize(e.text);
            return e;
          });
        });
    }
    return loading;
  }

  // Append TEXT to EL, with the occurrences of TERMS in <mark>.
  function highlight(el, text, terms) {
    var n = normalize(text);
    var spans = [];
    terms.forEach(function (t) {
      var i = n.indexOf(t);
      while (t && i !== -1) {
        spans.push([i, i + t.length]);
        i = n.indexOf(t, i + t.length);
      }
    });
    spans.sort(function (a, b) { return a[0] - b[0]; });
    var pos = 0;
    spans.forEach(function (s) {
      if (s[0] < pos) return;
      el.appendChild(document.createTextNode(text.slice(pos, s[0])));
      var m = document.createElement("mark");
      m.textContent = text.slice(s[0], s[1]);
      el.appendChild(m);
      pos = s[1];
    });
    el.appendChild(document.createTextNode(text.slice(pos)));
  }

  function excerpt(e, terms) {
    var i = -1;
    terms.forEach(function (t) {
      var j = e.nText.indexOf(t);
      if (j !== -1 && (i === -1 || j < i)) i = j;
    });
    if (i === -1) return e.text.slice(0, 150) + (e.text.length > 150 ? "…" : "");
    var start = Math.max(0, i - 60);
    return (start > 0 ? "…" : "") + e.text.slice(start, start + 170) +
      (start + 170 < e.text.length ? "…" : "");
  }

  function show() {
    list.textContent = "";
    var q = normalize(input.value.trim());
    if (!q || !index) return;
    var terms = q.split(/\s+/);

    var results = index
      .filter(function (e) {
        return terms.every(function (t) {
          return e.nTitle.indexOf(t) !== -1 || e.nText.indexOf(t) !== -1;
        });
      })
      .map(function (e) {
        var score = 0;
        terms.forEach(function (t) { if (e.nTitle.indexOf(t) !== -1) score += 10; });
        return { e: e, score: score };
      })
      .sort(function (a, b) { return b.score - a.score; })
      .slice(0, 20);

    if (!results.length) {
      var empty = document.createElement("li");
      empty.className = "empty";
      empty.textContent = "Nothing found for “" + input.value.trim() + "”.";
      list.appendChild(empty);
      return;
    }

    results.forEach(function (r, i) {
      var li = document.createElement("li");
      var a = document.createElement("a");
      a.href = r.e.url;
      if (i === 0) a.className = "active";
      var section = document.createElement("span");
      section.className = "result-section";
      section.textContent = r.e.section;
      var title = document.createElement("span");
      title.className = "result-title";
      highlight(title, r.e.title, terms);
      var text = document.createElement("span");
      text.className = "result-text";
      highlight(text, excerpt(r.e, terms), terms);
      a.appendChild(section);
      a.appendChild(title);
      a.appendChild(text);
      li.appendChild(a);
      list.appendChild(li);
    });
  }

  function open() {
    if (dialog.open) return;
    dialog.showModal();
    input.focus();
    input.select();
    load().then(show);
  }

  document.querySelectorAll(".search-button").forEach(function (b) {
    b.addEventListener("click", open);
  });

  document.addEventListener("keydown", function (e) {
    var typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName);
    if ((e.key === "k" && (e.ctrlKey || e.metaKey)) || (e.key === "/" && !typing)) {
      e.preventDefault();
      open();
    }
  });

  input.addEventListener("input", function () { load().then(show); });

  // Up and down to choose, Enter to open.
  input.addEventListener("keydown", function (e) {
    var links = Array.prototype.slice.call(list.querySelectorAll("a"));
    if (!links.length) return;
    var i = links.findIndex(function (a) { return a.classList.contains("active"); });
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      if (i !== -1) links[i].classList.remove("active");
      i = e.key === "ArrowDown" ? Math.min(i + 1, links.length - 1) : Math.max(i - 1, 0);
      links[i].classList.add("active");
      links[i].scrollIntoView({ block: "nearest" });
    } else if (e.key === "Enter") {
      e.preventDefault();
      location.href = links[Math.max(i, 0)].href;
    }
  });

  // A click outside the box closes it.
  dialog.addEventListener("click", function (e) {
    if (e.target === dialog) dialog.close();
  });
})();
