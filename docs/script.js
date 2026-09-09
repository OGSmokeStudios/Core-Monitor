/* ==========================================================================
   Core-Monitor site behaviour — bench instrument edition

   Everything here is progressive enhancement. With this file blocked the
   page stays fully readable: the fan curve renders fully drawn, navigation and copy fall back
   to plain HTML behaviour. No libraries, no network requests.
   ========================================================================== */

(function () {
  "use strict";

  var doc = document;
  var reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  /* ---------- mobile menu ---------- */

  var menuBtn = doc.querySelector("[data-menu-btn]");
  var menu = doc.querySelector("[data-menu]");

  if (menuBtn && menu) {
    var setMenu = function (open) {
      menu.classList.toggle("is-open", open);
      menuBtn.setAttribute("aria-expanded", open ? "true" : "false");
      menuBtn.textContent = open ? "Close" : "Menu";
    };

    menuBtn.addEventListener("click", function () {
      setMenu(!menu.classList.contains("is-open"));
    });

    menu.addEventListener("click", function (event) {
      if (event.target.closest("a")) setMenu(false);
    });

    doc.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && menu.classList.contains("is-open")) {
        setMenu(false);
        menuBtn.focus();
      }
    });
  }

  /* ---------- copy-to-clipboard ---------- */

  var copyStatus = doc.getElementById("copy-status");

  doc.querySelectorAll("[data-copy]").forEach(function (button) {
    var resting = button.textContent;
    var timer = null;

    button.addEventListener("click", function () {
      var source = doc.getElementById(button.getAttribute("data-copy"));
      var text = source ? source.textContent.replace(/\s+$/, "") : "";

      var settle = function (ok) {
        button.textContent = ok ? "Copied" : "Copy failed";
        if (ok) button.setAttribute("data-state", "done");
        else button.setAttribute("data-state", "failed");
        if (copyStatus) {
          copyStatus.textContent = ok
            ? "Command copied to the clipboard."
            : "Copying failed. Select the command and copy it manually.";
        }
        window.clearTimeout(timer);
        timer = window.setTimeout(function () {
          button.textContent = resting;
          button.removeAttribute("data-state");
          if (copyStatus) copyStatus.textContent = "";
        }, 2200);
      };

      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(
          function () { settle(true); },
          function () { settle(false); }
        );
      } else {
        settle(false);
      }
    });
  });

  /* ---------- fan curve: draw when it scrolls into view ---------- */

  var curve = doc.querySelector("[data-curve]");

  if (curve) {
    if (reducedMotion.matches || !("IntersectionObserver" in window)) {
      curve.classList.add("is-drawn");
    } else {
      var drawWatch = new IntersectionObserver(
        function (entries) {
          entries.forEach(function (entry) {
            if (entry.isIntersecting) {
              curve.classList.add("is-drawn");
              drawWatch.disconnect();
            }
          });
        },
        { threshold: 0.45 }
      );
      drawWatch.observe(curve);
    }
  }

})();
