// The menu on small screens, the table of contents following the reading,
// the search (Ctrl K or /), and the diagrams.
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

// Diagrams: ```mermaid blocks become <pre class="mermaid">
// (chaudron-site/markdown.scm).  Mermaid, loaded only where there are some,
// only lays them out: it places the boxes and draws the arrows.  The boxes,
// groups and labels are then made again in HTML, with the pixel frames of
// the site (see "Diagrams" in docs.css); only the arrows stay in SVG.
(function () {
  var diagrams = Array.prototype.slice.call(document.querySelectorAll("pre.mermaid"));
  if (!diagrams.length) return;

  document.documentElement.classList.add("js");
  diagrams.forEach(function (d) { d.dataset.source = d.textContent; });

  function loadMermaid() {
    return new Promise(function (resolve, reject) {
      var script = document.createElement("script");
      script.src = "/assets/vendor/mermaid-11.17.2.min.js";
      script.onload = function () { resolve(window.mermaid); };
      script.onerror = reject;
      document.head.appendChild(script);
    });
  }

  function element(tag, className, parent) {
    var el = document.createElement(tag);
    el.className = className;
    parent.appendChild(el);
    return el;
  }

  // The box of an element of the SVG, in pixels, relative to the SVG.
  function position(el, origin) {
    var r = el.getBoundingClientRect();
    return { x: r.left - origin.left, y: r.top - origin.top,
             width: r.width, height: r.height };
  }

  function place(el, p) {
    el.style.left = p.x + "px";
    el.style.top = p.y + "px";
    el.style.width = p.width + "px";
    el.style.height = p.height + "px";
  }

  // The lines of a label, as written, <br/> included.  Mermaid's texts are
  // HTML inside the SVG: read the HTML, which keeps the line breaks.
  function lines(label) {
    if (!label) return [];
    var html = label instanceof HTMLElement ? label
             : label.querySelector(".nodeLabel, .edgeLabel, div, span, p");
    var text = (html && html.innerText) || label.textContent || "";
    return text.split("\n").map(function (l) { return l.trim(); })
      .filter(function (l) { return l; });
  }

  function dress(pre) {
    var svg = pre.querySelector("svg");
    if (!svg) return;
    // A fixed size: the HTML elements are placed to the pixel.
    var view = svg.viewBox.baseVal;
    svg.style.maxWidth = "none";
    svg.setAttribute("width", view.width);
    svg.setAttribute("height", view.height);

    var drawing = document.createElement("div");
    drawing.className = "schema-drawing";
    drawing.style.width = view.width + "px";
    drawing.style.height = view.height + "px";
    pre.insertBefore(drawing, svg);
    drawing.appendChild(svg);
    var origin = svg.getBoundingClientRect();

    // Groups first, a provider each: they are under the boxes.
    svg.querySelectorAll("g.cluster").forEach(function (g) {
      var rect = g.querySelector("rect");
      if (!rect) return;
      var group = element("div", "schema-group", drawing);
      place(group, position(rect, origin));
      element("span", "schema-group-name", group).textContent =
        lines(g.querySelector(".cluster-label")).join(" ");
      g.style.visibility = "hidden";
    });

    // Boxes: the first line as a title, the others below.  Mermaid's
    // circles, ((…)), are what is outside the infrastructure: you, the
    // Internet.
    svg.querySelectorAll("g.node").forEach(function (g) {
      var shape = g.querySelector("rect, circle, polygon, path");
      if (!shape) return;
      var outside = !!g.querySelector("circle");
      var box = element("div", "schema-box" + (outside ? " schema-box-outside" : ""),
                        drawing);
      place(box, position(shape, origin));
      lines(g.querySelector(".nodeLabel") || g).forEach(function (text, i) {
        element("span", i === 0 ? "schema-title" : "schema-detail", box)
          .textContent = text;
      });
      g.style.visibility = "hidden";
    });

    // The labels of the arrows.
    svg.querySelectorAll("g.edgeLabel").forEach(function (g) {
      var text = lines(g).join(" ");
      if (!text) return;
      var p = position(g, origin);
      var label = element("span", "schema-label", drawing);
      label.textContent = text;
      label.style.left = (p.x + p.width / 2) + "px";
      label.style.top = (p.y + p.height / 2) + "px";
      g.style.visibility = "hidden";
    });
  }

  // A diagram wider than the column is scaled down to fit.
  function fit(pre) {
    var drawing = pre.querySelector(".schema-drawing");
    if (!drawing) return;
    var width = parseFloat(drawing.style.width);
    var height = parseFloat(drawing.style.height);
    var scale = Math.min(1, pre.parentNode.clientWidth / width);
    drawing.style.transform = scale < 1 ? "scale(" + scale + ")" : "";
    drawing.style.marginLeft = scale < 1 ? "0" : "";
    pre.style.height = (height * scale) + "px";
  }

  window.addEventListener("resize", function () { diagrams.forEach(fit); });

  loadMermaid().then(function (mermaid) {
    var font = '"Atkinson", system-ui, sans-serif';
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: "base",
      fontFamily: font,
      // Wide margins: the pixel frames take room.
      flowchart: { curve: "step", padding: 26, nodeSpacing: 46,
                   rankSpacing: 64, diagramPadding: 12 },
      themeVariables: { fontFamily: font, fontSize: "16px" },
      // Measured in bold, like the titles of the boxes: the rest is
      // smaller, so it fits.
      themeCSS: ".nodeLabel, .nodeLabel p { font-weight: 700; }"
    });
    // The font first: Mermaid measures the texts to place the boxes.
    var fonts = document.fonts
        ? Promise.all([document.fonts.load('16px "Atkinson"'),
                       document.fonts.load('700 16px "Atkinson"')])
        : Promise.resolve();
    return fonts.then(function () {
      return mermaid.run({ nodes: diagrams });
    }).then(function () {
      diagrams.forEach(dress);
      diagrams.forEach(fit);
    });
  }).catch(function (error) {
    // Leave the text of the diagram readable.
    diagrams.forEach(function (d) { d.classList.add("schema-error"); });
    if (window.console) console.error(error);
  });
})();
