// The landing page: smooth scrolling (Lenis), scroll-driven motion (GSAP
// ScrollTrigger and SplitText), and the 3D avatar in the hero (three.js).
//
// With reduced motion, the page skips the loader, smooth scrolling, pinning
// and scrubbing, and shows everything at once. The avatar stays still.

import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { SplitText } from "gsap/SplitText";
import Lenis from "lenis";
import { startPresence } from "./presence.js";
import { startContours } from "./contours.js";

gsap.registerPlugin(ScrollTrigger, SplitText);

const root = document.documentElement;
const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const canHover = window.matchMedia("(hover: hover) and (pointer: fine)").matches;
const $ = (selector, scope = document) => scope.querySelector(selector);
const $$ = (selector, scope = document) => [...scope.querySelectorAll(selector)];

const THEMES = {
  paper: { "--bg": "#f3f2ec", "--fg": "#10120e" },
  ink: { "--bg": "#10120e", "--fg": "#e8e9de" },
};

const PULSE_DEMO_SECONDS = 4.5; // the app's 45 seconds, ten times faster
const PULSE_REAL_SECONDS = 45;

let lenis = null;

main();

async function main() {
  track("$pageview");
  document.addEventListener("click", (event) => {
    const link = event.target.closest?.("[data-outbound]");
    if (link) track("outbound_click", link.dataset.outbound);
  });

  setupSmoothScroll();
  gsap.set(root, THEMES.paper);

  // SplitText measures lines, so the fonts must be in first
  await Promise.race([document.fonts.ready, wait(2500)]);

  const hero = setupHero();
  setupTopbar();
  setupMenu();
  setupAnchors();
  setupManifesto();
  setupReel();
  setupHeadings();
  setupInputs();
  setupApps();
  setupStack();
  setupTerminal();
  setupMarquee();
  setupMagnetic();
  setupFooter();
  setupThemes();
  loadLatest();

  window.addEventListener("load", () => ScrollTrigger.refresh());

  // A link to a section, such as /download sending browsers to /#download,
  // skips the loader and lands on that section
  const arrival = sectionFromHash();
  if (arrival) {
    $("[data-loader]")?.remove();
    root.classList.remove("is-loading");
    hero.intro();
    // Jump now, and again once images and fonts have loaded, since the pinned
    // reel's spacing changes the section's position when the layout settles
    const land = () => {
      ScrollTrigger.refresh();
      if (lenis) lenis.scrollTo(arrival, { immediate: true, force: true });
      else arrival.scrollIntoView();
    };
    land();
    if (document.readyState !== "complete") window.addEventListener("load", () => requestAnimationFrame(land), { once: true });
    if (arrival.id === "download") startDownload();
    return;
  }

  await runLoader();
  hero.intro();
}

// /download sends browsers here, so the download starts the way it does from
// the button. GitHub serves the DMG as an attachment, so the page stays put.
function startDownload() {
  const link = document.createElement("a");
  link.href = "/download/dmg";
  document.body.append(link);
  link.click();
  link.remove();
  const meta = $("[data-version]");
  meta.dataset.started = "true";
  meta.textContent = "Your download has started";
  history.replaceState(null, "", location.pathname); // a reload shouldn't download again
}

function sectionFromHash() {
  const id = decodeURIComponent(location.hash.slice(1));
  if (!id || id === "top") return null;
  return document.getElementById(id);
}

// Smooth scroll ------------------------------------------------------------

function setupSmoothScroll() {
  if (reduce) return;
  lenis = new Lenis({ lerp: 0.1, wheelMultiplier: 0.95 });
  lenis.on("scroll", ScrollTrigger.update);
  gsap.ticker.add((time) => lenis.raf(time * 1000));
  gsap.ticker.lagSmoothing(0);
}

function goTo(target) {
  if (lenis) {
    lenis.scrollTo(target, { duration: 1.6, easing: (t) => 1 - Math.pow(1 - t, 4) });
  } else if (typeof target === "number") {
    window.scrollTo({ top: target });
  } else {
    target.scrollIntoView();
  }
}

// Loader -------------------------------------------------------------------

function runLoader() {
  const loader = $("[data-loader]");
  if (reduce || !loader) {
    loader?.remove();
    root.classList.remove("is-loading");
    return Promise.resolve();
  }

  lenis?.stop();
  const count = $("[data-count]", loader);
  const bands = $$(".loader-band", loader);
  const progress = { value: 0 };
  gsap.set(bands, { yPercent: 110, skewY: -7 });

  return new Promise((resolve) => {
    gsap
      .timeline({ onComplete: () => loader.remove() })
      .to(progress, {
        value: 100,
        duration: 1.6,
        ease: "power3.inOut",
        onUpdate: () => (count.textContent = String(Math.round(progress.value)).padStart(2, "0")),
      })
      .add(() => loader.classList.add("is-on"), 0.85)
      .to(bands, { yPercent: -5, duration: 0.85, ease: "expo.inOut", stagger: 0.08 }, "+=0.1")
      .set($(".loader-panel", loader), { autoAlpha: 0 })
      .add(() => {
        root.classList.remove("is-loading");
        lenis?.start();
        resolve();
      })
      .to(bands, { yPercent: -135, duration: 1, ease: "expo.inOut", stagger: { each: 0.08, from: "end" } });
  });
}

// Hero -----------------------------------------------------------------------

function setupHero() {
  const hero = $(".hero");
  const stage = $("[data-stage]");
  const card = $("[data-status-card]");
  const countdown = $("[data-countdown]");
  const pulseCount = $("[data-pulse-count]");
  const contours = startContours($("[data-contours]"), { reduce });

  let pulses = 0;
  let nextPulseAt = performance.now() + PULSE_DEMO_SECONDS * 1000;

  const onPress = ({ origin }) => {
    contours.pulse(origin.x, origin.y);
    pulses += 1;
    pulseCount.textContent = pulses;
    nextPulseAt = performance.now() + PULSE_DEMO_SECONDS * 1000;
    card.classList.remove("is-flash");
    void card.offsetWidth;
    card.classList.add("is-flash");
  };

  const avatar = startPresence(stage, { onPress, reduce });
  if (!avatar) stage.classList.add("is-fallback");
  const press = () => {
    if (avatar) avatar.press();
    else {
      const r = stage.getBoundingClientRect();
      onPress({ origin: { x: r.left + r.width / 2, y: r.top + r.height * 0.44 } });
    }
  };

  // The countdown shows the app's real 45 seconds while the demo runs fast
  gsap.ticker.add(() => {
    const left = nextPulseAt - performance.now();
    avatar?.setIdle(1 - left / (PULSE_DEMO_SECONDS * 1000));
    if (left <= 0) {
      if (!document.hidden && ScrollTrigger.isInViewport(hero)) press();
      else nextPulseAt = performance.now() + PULSE_DEMO_SECONDS * 1000;
      return;
    }
    const seconds = Math.ceil((left / 1000 / PULSE_DEMO_SECONDS) * PULSE_REAL_SECONDS);
    const text = `0:${String(Math.min(seconds, PULSE_REAL_SECONDS)).padStart(2, "0")}`;
    if (countdown.textContent !== text) countdown.textContent = text;
  });

  if (!reduce) {
    ScrollTrigger.create({
      trigger: hero,
      start: "top top",
      end: "bottom top",
      scrub: true,
      onUpdate: (self) => avatar?.setScroll(self.progress),
    });
    gsap.to(".hero-title", {
      yPercent: -40,
      ease: "none",
      scrollTrigger: { trigger: hero, start: "top top", end: "bottom top", scrub: true },
    });
  }

  const lines = $$("[data-hero-line]");
  const corners = [card, $(".hero-meta"), $(".hero-scroll"), $("[data-topbar]")];
  if (!reduce) {
    gsap.set(lines, { yPercent: 110 });
    gsap.set(corners, { autoAlpha: 0, y: 16 });
  }

  return {
    intro() {
      avatar?.intro();
      if (reduce) return;
      gsap.to(lines, { yPercent: 0, duration: 1.4, ease: "expo.out", stagger: 0.1, delay: 0.15 });
      gsap.to(corners, { autoAlpha: 1, y: 0, duration: 1, ease: "expo.out", stagger: 0.06, delay: 0.5 });
      nextPulseAt = performance.now() + 1600; // first pulse soon after landing
    },
  };
}

// Top bar: hides while scrolling down, comes back on the way up -------------

function setupTopbar() {
  const bar = $("[data-topbar]");
  let lastY = 0;
  const update = (y) => {
    const down = y > lastY + 2;
    const up = y < lastY - 2;
    if (down && y > 240 && !root.classList.contains("menu-open")) bar.classList.add("is-hidden");
    else if (up || y < 240) bar.classList.remove("is-hidden");
    lastY = y;
  };
  if (lenis) lenis.on("scroll", ({ scroll }) => update(scroll));
  else window.addEventListener("scroll", () => update(window.scrollY), { passive: true });
}

// Menu --------------------------------------------------------------------

let closeMenu = () => {};

function setupMenu() {
  const toggle = $("[data-menu-toggle]");
  const menu = $("[data-menu]");
  const preview = $("[data-menu-preview]");
  const main = $("#main");
  const links = $$(".menu-links a", menu);
  let timeline = null;

  const origin = () => {
    const r = toggle.getBoundingClientRect();
    const x = r.left + r.width / 2;
    const y = r.top + r.height / 2;
    const radius = Math.hypot(Math.max(x, innerWidth - x), Math.max(y, innerHeight - y));
    return { x, y, radius };
  };

  function setOpen(open) {
    const { x, y, radius } = origin();
    const closed = `circle(0px at ${x}px ${y}px)`;
    const full = `circle(${radius}px at ${x}px ${y}px)`;
    timeline?.kill();
    toggle.setAttribute("aria-expanded", String(open));
    root.classList.toggle("menu-open", open);
    main.inert = open;

    if (open) {
      menu.hidden = false;
      lenis?.stop();
      timeline = gsap
        .timeline()
        .fromTo(menu, { clipPath: closed }, { clipPath: full, duration: reduce ? 0 : 0.9, ease: "expo.inOut" })
        .fromTo(
          links,
          { yPercent: reduce ? 0 : 100, autoAlpha: 0 },
          { yPercent: 0, autoAlpha: 1, duration: reduce ? 0 : 0.8, ease: "expo.out", stagger: 0.05 },
          reduce ? 0 : "-=0.45",
        );
      links[0].focus({ preventScroll: true });
    } else {
      lenis?.start();
      timeline = gsap
        .timeline({ onComplete: () => (menu.hidden = true) })
        .to(menu, { clipPath: closed, duration: reduce ? 0 : 0.75, ease: "expo.inOut" });
    }
  }

  closeMenu = () => {
    if (toggle.getAttribute("aria-expanded") === "true") setOpen(false);
  };

  toggle.addEventListener("click", () => setOpen(toggle.getAttribute("aria-expanded") !== "true"));
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && toggle.getAttribute("aria-expanded") === "true") {
      setOpen(false);
      toggle.focus();
    }
  });

  for (const link of links) {
    link.addEventListener("pointerenter", () => {
      const src = link.dataset.preview;
      if (!src || preview.getAttribute("src") === src) return;
      gsap.to(preview, {
        autoAlpha: 0,
        scale: 0.96,
        duration: 0.15,
        onComplete: () => {
          preview.src = src;
          gsap.to(preview, { autoAlpha: 1, scale: 1, duration: 0.5, ease: "expo.out" });
        },
      });
    });
  }
}

// In-page links scroll smoothly and close the menu first
function setupAnchors() {
  document.addEventListener("click", (event) => {
    const link = event.target.closest?.("a[data-scroll-to]");
    if (!link) return;
    const id = link.getAttribute("href");
    const target = id === "#top" ? 0 : $(id);
    if (target === null) return;
    event.preventDefault();
    closeMenu();
    goTo(target);
  });
}

// Manifesto: words light up as you scroll through ---------------------------

function setupManifesto() {
  const text = $("[data-manifesto]");
  const split = SplitText.create(text, { type: "words", aria: "auto" });
  if (reduce) return;
  gsap.fromTo(
    split.words,
    { opacity: 0.12 },
    {
      opacity: 1,
      ease: "none",
      stagger: 0.1,
      scrollTrigger: { trigger: text, start: "top 78%", end: "bottom 42%", scrub: true },
    },
  );
  gsap.from(".manifesto .eyebrow", {
    autoAlpha: 0,
    y: 20,
    duration: 1,
    ease: "expo.out",
    scrollTrigger: { trigger: ".manifesto", start: "top 70%" },
  });
}

// Reel: a pinned section that scrolls sideways --------------------------------

function setupReel() {
  if (reduce) return;
  const section = $("#reel");
  const track = $("[data-reel-track]");
  const distance = () => Math.max(0, track.scrollWidth - window.innerWidth);

  const tween = gsap.to(track, {
    x: () => -distance(),
    ease: "none",
    scrollTrigger: {
      trigger: section,
      start: "top top",
      end: () => `+=${distance()}`,
      pin: true,
      scrub: 0.6,
      invalidateOnRefresh: true,
      anticipatePin: 1,
    },
  });

  $$("[data-shot]").forEach((shot, index) => {
    const image = $("img", shot);
    gsap.fromTo(
      image,
      { xPercent: -3 },
      {
        xPercent: 3,
        ease: "none",
        scrollTrigger: { trigger: shot, containerAnimation: tween, start: "left right", end: "right left", scrub: true },
      },
    );
    gsap.from(shot, {
      rotate: index % 2 ? 4 : -4,
      yPercent: index % 2 ? -10 : 10,
      ease: "none",
      scrollTrigger: { trigger: shot, containerAnimation: tween, start: "left right", end: "center center", scrub: true },
    });
  });

  gsap.fromTo(
    ".reel-big",
    { xPercent: 40 },
    {
      xPercent: -20,
      ease: "none",
      scrollTrigger: { trigger: ".reel-quote", containerAnimation: tween, start: "left right", end: "right left", scrub: true },
    },
  );
}

// Headings and ledes rise line by line as they come into view -----------------

function setupHeadings() {
  if (reduce) return;
  for (const element of $$(".display, .section-lede, .reel-intro p, .cli-copy p, .inputs-note")) {
    SplitText.create(element, {
      type: "lines",
      mask: "lines",
      aria: "auto",
      autoSplit: true,
      onSplit: (self) =>
        gsap.from(self.lines, {
          yPercent: 110,
          duration: 1.2,
          ease: "expo.out",
          stagger: 0.08,
          scrollTrigger: { trigger: element, start: "top 85%", once: true },
        }),
    });
  }
  for (const eyebrow of $$(".section-head .eyebrow, .reel-intro .eyebrow, .cli-copy .eyebrow")) {
    gsap.from(eyebrow, {
      autoAlpha: 0,
      x: -16,
      duration: 1,
      ease: "expo.out",
      scrollTrigger: { trigger: eyebrow, start: "top 88%", once: true },
    });
  }
}

// Split cards -----------------------------------------------------------------

function setupInputs() {
  if (reduce) return;
  gsap.from("[data-split]", {
    y: 90,
    autoAlpha: 0,
    duration: 1.3,
    ease: "expo.out",
    stagger: 0.12,
    scrollTrigger: { trigger: ".split", start: "top 82%", once: true },
  });
}

// App cards: hover flips Away to Available. Without hover, they flip in turn ---

function setupApps() {
  const cards = $$(".app-card");
  if (!reduce) {
    gsap.from(cards, {
      y: 70,
      autoAlpha: 0,
      duration: 1.1,
      ease: "expo.out",
      stagger: { each: 0.07, grid: "auto", from: "start" },
      scrollTrigger: { trigger: ".app-grid", start: "top 85%", once: true },
    });
  }
  if (canHover) return;
  ScrollTrigger.create({
    trigger: ".app-grid",
    start: "top 60%",
    once: true,
    onEnter: () => cards.forEach((card, index) => setTimeout(() => card.classList.add("is-on"), 350 + index * 220)),
  });
}

// Feature cards stack up; the ones underneath sink back ------------------------

function setupStack() {
  const cards = $$("[data-stack]");
  cards.forEach((card, index) => card.style.setProperty("--i", index));
  if (reduce) return;
  // Each card sticks 90px from the top, plus 18px for each card above it (see .stack-card)
  const stickyTop = (index) => 90 + index * 18;
  cards.forEach((card, index) => {
    const next = cards[index + 1];
    if (!next) return;
    // Starts when the next card reaches this card's bottom edge and ends when it
    // covers it, so the card you're reading is never dimmed
    // fromTo, not to: tweening a filter from "none" starts at brightness(0),
    // which turned the cards black
    gsap.fromTo(card, { scale: 1, filter: "brightness(1)" }, {
      scale: 0.92,
      filter: "brightness(0.7)",
      ease: "none",
      scrollTrigger: {
        trigger: next,
        start: () => `top ${stickyTop(index) + card.offsetHeight}px`,
        end: () => `top ${stickyTop(index + 1)}px`,
        scrub: true,
        invalidateOnRefresh: true,
      },
    });
  });
}

// Terminal: types itself the first time it shows -----------------------------

function setupTerminal() {
  const body = $("[data-term-body]");
  const script = [
    { type: "cmd", text: "alwayson run -- make test" },
    { type: "note", text: "# AlwaysOn starts a session. Your status is Available." },
    { type: "out", text: "Running 214 tests..." },
    { type: "out", text: "...................................." },
    { type: "ok", text: "214 passed in 3m 12s" },
    { type: "note", text: "# make exits with status 0, and the session ends." },
    { type: "cmd", text: "" },
  ];

  const lineHTML = (line, text) => {
    const safe = escapeHTML(text);
    if (line.type === "cmd") return `<span class="p">$</span> ${safe}`;
    if (line.type === "note") return `<span class="d">${safe}</span>`;
    if (line.type === "ok") return `<span class="ok">${safe}</span>`;
    return safe;
  };

  if (reduce) {
    body.innerHTML = script.map((line) => lineHTML(line, line.text)).join("\n") + '<span class="caret"></span>';
    return;
  }

  ScrollTrigger.create({
    trigger: "[data-term]",
    start: "top 75%",
    once: true,
    onEnter: async () => {
      const done = [];
      for (const line of script) {
        if (line.type === "cmd") {
          for (let index = 0; index <= line.text.length; index += 1) {
            body.innerHTML = [...done, lineHTML(line, line.text.slice(0, index))].join("\n") + '<span class="caret"></span>';
            await wait(28 + Math.random() * 50);
          }
          await wait(380);
        } else {
          await wait(line.type === "ok" ? 900 : 260);
        }
        done.push(lineHTML(line, line.text));
        body.innerHTML = done.join("\n") + '<span class="caret"></span>';
      }
    },
  });
}

// Marquee bands: drift on their own, speed up with the scroll ------------------

function setupMarquee() {
  const words = ["Microsoft Teams", "Slack", "Zoom", "Discord", "Free and open source", "macOS 13 or later"];
  const rows = $$("[data-marquee]");
  for (const row of rows) {
    const content = words.map((word) => `<span>${escapeHTML(word)}</span>`).join("");
    row.innerHTML = content.repeat(4);
  }
  if (reduce) return;

  const loops = rows.map((row) => {
    const direction = Number(row.dataset.marquee);
    return gsap.fromTo(
      row,
      { xPercent: direction > 0 ? 0 : -50 },
      { xPercent: direction > 0 ? -50 : 0, duration: 38, ease: "none", repeat: -1 },
    );
  });

  if (lenis) {
    let boost = 1;
    gsap.ticker.add(() => {
      const target = 1 + Math.min(Math.abs(lenis.velocity) / 6, 6);
      boost += (target - boost) * 0.08;
      loops.forEach((loop) => loop.timeScale(boost));
    });
  }

  gsap.fromTo(
    ".marquee-band--signal",
    { rotate: -8 },
    { rotate: -2, ease: "none", scrollTrigger: { trigger: ".marquee", start: "top bottom", end: "bottom top", scrub: true } },
  );
  gsap.fromTo(
    ".marquee-band--paper",
    { rotate: 7 },
    { rotate: 1, ease: "none", scrollTrigger: { trigger: ".marquee", start: "top bottom", end: "bottom top", scrub: true } },
  );
}

// Buttons lean toward the pointer ---------------------------------------------

function setupMagnetic() {
  if (reduce || !canHover) return;
  for (const element of $$("[data-magnetic]")) {
    const toX = gsap.quickTo(element, "x", { duration: 0.6, ease: "power3.out" });
    const toY = gsap.quickTo(element, "y", { duration: 0.6, ease: "power3.out" });
    const pull = element.classList.contains("cta-button") ? 0.35 : 0.25;
    element.addEventListener("pointermove", (event) => {
      const r = element.getBoundingClientRect();
      toX((event.clientX - (r.left + r.width / 2)) * pull);
      toY((event.clientY - (r.top + r.height / 2)) * pull);
    });
    element.addEventListener("pointerleave", () => {
      gsap.to(element, { x: 0, y: 0, duration: 1, ease: "elastic.out(1, 0.4)" });
    });
  }
}

function setupFooter() {
  const mark = $("[data-footer-mark]");
  const split = SplitText.create(mark, { type: "chars" });

  // Size the wordmark so it spans the footer's content width exactly
  const footer = mark.parentElement;
  const fit = () => {
    const style = getComputedStyle(footer);
    const available = footer.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
    mark.style.fontSize = "100px";
    const natural = mark.scrollWidth;
    if (natural > 0) mark.style.fontSize = `${Math.floor((100 * available) / natural)}px`;
  };
  fit();
  new ResizeObserver(fit).observe(footer);

  if (reduce) return;
  gsap.from(split.chars, {
    yPercent: 40,
    autoAlpha: 0,
    duration: 1.2,
    ease: "expo.out",
    stagger: 0.05,
    scrollTrigger: { trigger: ".footer", start: "top 75%", once: true },
  });
}

// Ground colour follows whichever section is in the middle of the screen -------

function setupThemes() {
  const meta = $('meta[name="theme-color"]');
  let current = "paper";
  const apply = (name) => {
    if (!THEMES[name] || name === current) return;
    current = name;
    meta.content = THEMES[name]["--bg"];
    gsap.to(root, { ...THEMES[name], duration: reduce ? 0 : 0.7, ease: "power2.out", overwrite: true });
  };
  for (const section of $$("[data-theme]")) {
    ScrollTrigger.create({
      trigger: section,
      start: "top 50%",
      end: "bottom 50%",
      onEnter: () => apply(section.dataset.theme),
      onEnterBack: () => apply(section.dataset.theme),
    });
  }
}

// Latest version and star count, from the Worker -------------------------------

async function loadLatest() {
  try {
    const response = await fetch("/latest.json");
    if (!response.ok) return;
    const { version, stars } = await response.json();
    const meta = $("[data-version]");
    if (version && !meta.dataset.started) meta.textContent = `Version ${version}, a DMG from GitHub Releases`;
    if (Number.isInteger(stars)) $("[data-stars]").textContent = `(${stars.toLocaleString()})`;
  } catch {}
}

// Visit counts: the same anonymous events as the classic page. src/worker.js
// explains what is sent on; nothing is stored in the browser.

const visit = uuidv7();

function track(event, name) {
  try {
    navigator.sendBeacon?.(
      "/e",
      JSON.stringify({
        event,
        name,
        session: visit,
        url: location.href,
        referrer: document.referrer,
        width: window.innerWidth,
        height: window.innerHeight,
      }),
    );
  } catch {}
}

function uuidv7() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  const time = Date.now();
  for (let index = 0; index < 6; index += 1) bytes[index] = Math.floor(time / 2 ** (8 * (5 - index))) % 256;
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function escapeHTML(text) {
  return text.replace(/[&<>"]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[char]);
}
