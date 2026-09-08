/* Container CI guidance site — tool chooser, syntax colouring, copy, nav. */
(function () {
  "use strict";

  var TOOLS = ["azure-devops", "github", "gitlab"];
  var STORAGE_KEY = "container-ci.tool";
  var THEME_KEY = "container-ci.theme";

  /* ---------------------------------------------------------------- tool */

  function readStored(key) {
    try {
      return window.localStorage.getItem(key);
    } catch (err) {
      return null;
    }
  }

  function writeStored(key, value) {
    try {
      window.localStorage.setItem(key, value);
    } catch (err) {
      /* Private windows and blocked site data are fine; the page still works. */
    }
  }

  function normalise(value) {
    return TOOLS.indexOf(value) === -1 ? null : value;
  }

  function selectTool(tool, options) {
    document.body.setAttribute("data-active", tool);

    document.querySelectorAll(".chooser__option").forEach(function (button) {
      button.setAttribute(
        "aria-pressed",
        String(button.getAttribute("data-tool-select") === tool)
      );
    });

    writeStored(STORAGE_KEY, tool);

    if (options && options.updateHash) {
      var hash = "#" + tool;
      if (window.location.hash !== hash) {
        history.replaceState(null, "", hash);
      }
    }
  }

  var initialTool =
    normalise((window.location.hash || "").replace("#", "")) ||
    normalise(readStored(STORAGE_KEY)) ||
    "github";

  selectTool(initialTool, { updateHash: false });

  document.querySelectorAll(".chooser__option").forEach(function (button) {
    button.addEventListener("click", function () {
      selectTool(button.getAttribute("data-tool-select"), { updateHash: true });
    });
  });

  window.addEventListener("hashchange", function () {
    var fromHash = normalise((window.location.hash || "").replace("#", ""));
    if (fromHash) {
      selectTool(fromHash, { updateHash: false });
    }
  });

  /* --------------------------------------------------------------- theme */

  var toggle = document.querySelector(".theme-toggle");
  var storedTheme = readStored(THEME_KEY);

  if (storedTheme === "dark" || storedTheme === "light") {
    document.documentElement.setAttribute("data-theme", storedTheme);
  }

  function currentTheme() {
    var stamped = document.documentElement.getAttribute("data-theme");
    if (stamped) {
      return stamped;
    }
    return window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light";
  }

  function labelToggle() {
    if (toggle) {
      toggle.textContent = currentTheme() === "dark" ? "Light" : "Dark";
    }
  }

  labelToggle();

  if (toggle) {
    toggle.addEventListener("click", function () {
      var next = currentTheme() === "dark" ? "light" : "dark";
      document.documentElement.setAttribute("data-theme", next);
      writeStored(THEME_KEY, next);
      labelToggle();
    });
  }

  /* ------------------------------------------------------- syntax colour
     A deliberately small tokeniser: comments, quoted strings, mapping keys
     and CI variable expressions. It scans characters rather than running
     regexes over escaped HTML, so quotes inside comments cannot desync it. */

  function escapeHtml(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  var KEY_PATTERNS = {
    yaml: /^(\s*(?:-\s+)?)([A-Za-z_][\w.-]*)(\s*:)/,
    hcl: /^(\s*)([A-Za-z_][\w.-]*)(\s*=)/,
    dockerfile: /^(\s*)(FROM|RUN|COPY|ARG|ENV|WORKDIR|USER|EXPOSE|CMD|ENTRYPOINT|HEALTHCHECK|LABEL)(\s)/,
    shell: null
  };

  var VAR_PATTERN = /(\$\{\{[^}]*\}\}|\$\[\[[^\]]*\]\]|\$\{[^}]*\}|\$\(\w[\w.]*\)|\$[A-Z_][A-Z0-9_]*)/g;

  function markVariables(escaped) {
    return escaped.replace(VAR_PATTERN, function (match) {
      return '<span class="tok-var">' + match + "</span>";
    });
  }

  function highlightLine(line, lang) {
    var out = "";
    var index = 0;

    /* A comment runs to end of line, but only outside a string. */
    var plain = "";

    function flushPlain() {
      if (!plain) {
        return;
      }
      var escaped = escapeHtml(plain);
      var pattern = KEY_PATTERNS[lang];
      var matched = pattern && out === "" ? escaped.match(pattern) : null;
      if (matched) {
        escaped =
          matched[1] +
          '<span class="tok-key">' +
          matched[2] +
          "</span>" +
          matched[3] +
          markVariables(escaped.slice(matched[0].length));
      } else {
        escaped = markVariables(escaped);
      }
      out += escaped;
      plain = "";
    }

    while (index < line.length) {
      var ch = line[index];

      if (ch === "#") {
        flushPlain();
        out +=
          '<span class="tok-comment">' + escapeHtml(line.slice(index)) + "</span>";
        return out;
      }

      if (ch === '"' || ch === "'") {
        var quote = ch;
        var end = index + 1;
        while (end < line.length) {
          if (line[end] === "\\") {
            end += 2;
            continue;
          }
          if (line[end] === quote) {
            end += 1;
            break;
          }
          end += 1;
        }
        flushPlain();
        out +=
          '<span class="tok-string">' +
          markVariables(escapeHtml(line.slice(index, end))) +
          "</span>";
        index = end;
        continue;
      }

      plain += ch;
      index += 1;
    }

    flushPlain();
    return out;
  }

  document.querySelectorAll(".code code").forEach(function (block) {
    var lang = block.getAttribute("data-lang") || "yaml";
    var source = block.textContent;
    block.setAttribute("data-source", source);
    block.innerHTML = source
      .split("\n")
      .map(function (line) {
        return highlightLine(line, lang);
      })
      .join("\n");
  });

  /* ---------------------------------------------------------------- copy */

  document.querySelectorAll(".code__copy").forEach(function (button) {
    button.addEventListener("click", function () {
      var block = button.closest(".code").querySelector("code");
      var text = block.getAttribute("data-source") || block.textContent;

      var done = function () {
        button.setAttribute("data-copied", "true");
        button.textContent = "Copied";
        window.setTimeout(function () {
          button.removeAttribute("data-copied");
          button.textContent = "Copy";
        }, 1600);
      };

      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, function () {
          button.textContent = "Select and copy";
        });
      } else {
        button.textContent = "Select and copy";
      }
    });
  });

  /* ----------------------------------------------------------------- nav */

  var links = Array.prototype.slice.call(
    document.querySelectorAll(".rail nav a[href^='#']")
  );

  var sections = links
    .map(function (link) {
      return document.getElementById(link.getAttribute("href").slice(1));
    })
    .filter(Boolean);

  if (sections.length && "IntersectionObserver" in window) {
    var visible = new Set();

    var observer = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            visible.add(entry.target.id);
          } else {
            visible.delete(entry.target.id);
          }
        });

        var firstVisible = sections.find(function (section) {
          return visible.has(section.id);
        });

        links.forEach(function (link) {
          var isCurrent =
            firstVisible &&
            link.getAttribute("href") === "#" + firstVisible.id;
          if (isCurrent) {
            link.setAttribute("aria-current", "true");
          } else {
            link.removeAttribute("aria-current");
          }
        });
      },
      { rootMargin: "-10% 0px -70% 0px" }
    );

    sections.forEach(function (section) {
      observer.observe(section);
    });
  }
})();
