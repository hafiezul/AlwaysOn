// The landing page's working demo. A copy of the AlwaysOn menu runs on a
// simulated clock, 20 times faster than real time. Your own mouse and keyboard
// count as using the Mac. Every 45 simulated seconds an active session posts a
// tiny input, or skips it if you were active, and a copy of the Pulse Log
// window records each attempt in the app's own words. With no input for 5
// simulated minutes, the headline's second dot turns Away yellow. hero3d.js
// draws the hero's pixel field when WebGL is available and motion is allowed.

const SPEED = 20;
const TICK_MS = 100;
const PULSE_EVERY = 45;
const AWAY_AFTER = 5 * 60;
const BAR_COUNT = 26; // bars in the menu's strip
const LOG_COUNT = 60; // bars in the Pulse Log timeline, as in the app

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

const timeFormat = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" });
const clockFormat = new Intl.DateTimeFormat(undefined, { weekday: "short", hour: "numeric", minute: "2-digit" });
const secondsFormat = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit", second: "2-digit" });

function hms(seconds) {
  const s = Math.max(0, Math.floor(seconds));
  return `${Math.floor(s / 3600)}:${String(Math.floor((s % 3600) / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
}

function duration(seconds) {
  const m = Math.round(seconds / 60);
  const h = Math.floor(m / 60);
  if (h && m % 60) return `${h}h ${m % 60}m`;
  return h ? `${h}h` : `${m}m`;
}

// Latest version

fetch("/latest.json")
  .then((response) => (response.ok ? response.json() : null))
  .then((latest) => {
    const slot = $("[data-version]");
    if (slot && latest?.version) slot.textContent = `Latest version ${latest.version}.`;
  })
  .catch(() => {});

// Demo state

const listeners = new Set();
const emit = (type, detail = {}) => listeners.forEach((listener) => listener(type, detail));

const state = {
  now: Date.now(),
  phase: "active", // active, paused, off
  timed: true,
  absolute: false, // Until sessions end at a fixed time, even through a pause
  remaining: 73 * 60,
  total: 120 * 60,
  elapsed: 0,
  label: "via Quick Timer",
  resumesAt: null,
  today: 3 * 3600,
  idle: 0, // how long the Mac has had no input, from you or AlwaysOn
  sinceYou: 999, // how long since your own input
  nextPulse: PULSE_EVERY,
  method: "alternate",
  nextAlternate: "mouse",
  status: "available",
  pulses: [],
};

const demo = {
  subscribe(listener) {
    listeners.add(listener);
    return () => listeners.delete(listener);
  },
  get status() {
    return state.status;
  },
};

// The app's own wording for each outcome
const outcomes = {
  posted: ["posted", "Input posted", "Sent simulated input to keep you active."],
  userActive: ["skipped", "Skipped: user active", "You used the Mac recently, so no input was needed yet."],
  systemPaused: ["paused", "Paused: Mac asleep, locked, or switched user", "Waiting until the Mac is awake, unlocked, and back on your session."],
};
const counts = { posted: 0, skipped: 0, paused: 0, problem: 0 };

function record(outcome, at, fresh = false) {
  const [kind, summary, explanation] = outcomes[outcome];
  state.pulses.push({ kind, summary, explanation, at, fresh });
  if (state.pulses.length > LOG_COUNT) state.pulses.shift();
  counts[kind] += 1;
}

// Seed the log with a believable recent history: away, back at the desk,
// the Mac locked for a minute, then away again
const seed = "ppppppppsssspsssspssspzzzzzpppspppppsppppp";
[...seed].forEach((code, index) => {
  const outcome = code === "p" ? "posted" : code === "s" ? "userActive" : "systemPaused";
  record(outcome, state.now - (seed.length - index) * PULSE_EVERY * 1000);
});

// Session actions, named after the app's own

function startTimer(minutes, label = "via Quick Timer") {
  Object.assign(state, {
    phase: "active",
    timed: true,
    absolute: false,
    remaining: minutes * 60,
    total: minutes * 60,
    elapsed: 0,
    label,
    resumesAt: null,
  });
  render();
}

function startUntil(endAt, label) {
  const seconds = Math.max(60, (endAt - state.now) / 1000);
  Object.assign(state, {
    phase: "active",
    timed: true,
    absolute: true,
    remaining: seconds,
    total: seconds,
    elapsed: 0,
    label: label ? `Until · ${label}` : "Until",
    resumesAt: null,
  });
  render();
}

function keepOnline() {
  Object.assign(state, { phase: "active", timed: false, absolute: false, elapsed: 0, label: null, resumesAt: null });
  render();
}

function pause(minutes = null) {
  state.phase = "paused";
  state.resumesAt = minutes ? state.now + minutes * 60 * 1000 : null;
  render();
}

function resume() {
  state.phase = "active";
  state.resumesAt = null;
  render();
}

function stop() {
  state.phase = "off";
  state.resumesAt = null;
  render();
}

function addTime(minutes) {
  state.remaining += minutes * 60;
  state.total += minutes * 60;
  render();
}

function stopAfter(minutes) {
  Object.assign(state, { timed: true, absolute: false, remaining: minutes * 60, total: minutes * 60 });
  render();
}

// Clock

function pulse() {
  if (state.phase !== "active") return;

  let kind = "posted";
  if (state.sinceYou < PULSE_EVERY) {
    kind = "skipped";
  } else {
    state.idle = 0;
    const method = state.method === "alternate" ? state.nextAlternate : state.method;
    if (state.method === "alternate") state.nextAlternate = method === "mouse" ? "keyboard" : "mouse";
    emit("nudge", { method });
  }

  record(kind === "posted" ? "posted" : "userActive", state.now, true);
}

function tick() {
  const dt = (SPEED * TICK_MS) / 1000;
  state.now += dt * 1000;
  state.idle += dt;
  state.sinceYou += dt;

  if (state.phase === "paused" && state.resumesAt && state.now >= state.resumesAt) resume();

  if (state.phase === "active") {
    state.today += dt;
    if (state.timed) state.remaining -= dt;
    else state.elapsed += dt;
  } else if (state.phase === "paused" && state.absolute) {
    state.remaining -= dt;
  }

  if (state.timed && state.phase !== "off" && state.remaining <= 0) stop();

  state.nextPulse -= dt;
  if (state.nextPulse <= 0) {
    state.nextPulse += PULSE_EVERY;
    pulse();
  }

  const status = state.idle >= AWAY_AFTER ? "away" : "available";
  if (status !== state.status) {
    state.status = status;
    emit("status", { status });
  }

  render();
}

// Your own input counts as using the Mac
let lastInput = 0;
function onInput() {
  const now = performance.now();
  if (now - lastInput < 100) return;
  lastInput = now;
  state.sinceYou = 0;
  state.idle = 0;
}

for (const type of ["pointermove", "pointerdown", "keydown", "wheel", "touchstart"]) {
  window.addEventListener(type, onInput, { passive: true });
}

// Rendering

const desktop = $("[data-desktop]");
const menu = $("[data-menu]");
const el = {
  ring: $("[data-ring]"),
  title: $("[data-title]"),
  today: $("[data-today]"),
  countdown: $("[data-countdown]"),
  unit: $("[data-countdown-unit]"),
  clockLine: $("[data-clock-line]"),
  detail: $("[data-detail]"),
  primaryLabel: $("[data-primary-label]"),
  chipsHeading: $("[data-chips-heading]"),
  chips: $("[data-chips]"),
  bars: $("[data-pulse-bars]"),
  pulseTime: $("[data-pulse-time]"),
  clock: $("[data-clock]"),
  headlineDot: $("[data-headline-dot]"),
  logTallies: $("[data-log-tallies]"),
  logBars: $("[data-log-bars]"),
  logFirst: $("[data-log-first]"),
  logLatest: $("[data-log-latest]"),
  logList: $("[data-log-list]"),
  iconBars: $$("[data-icon-bars] path"),
  liveTitle: $("[data-live-title]"),
  liveLatest: $("[data-live-latest]"),
};

const RING = 2 * Math.PI * 22;
let chipKey = "";
let barKey = "";

function setText(node, text) {
  if (node && node.textContent !== text) node.textContent = text;
}

function detailLine() {
  if (state.phase === "off") return "";
  const parts = [];
  if (state.phase === "paused" && state.resumesAt) parts.push(`resumes ${timeFormat.format(state.resumesAt)}`);
  if (state.label) parts.push(state.label);
  if (state.timed) parts.push(`ends ${timeFormat.format(state.now + state.remaining * 1000)}`);
  const line = parts.join(" · ");
  return line.charAt(0).toUpperCase() + line.slice(1);
}

function renderChips() {
  let heading;
  let options;
  if (state.phase === "off") {
    heading = "Keep online for";
    options = [[30, "30m"], [60, "1h"], [120, "2h"], [240, "4h"]];
  } else if (state.timed) {
    heading = "Add time";
    options = [[15, "+15m"], [30, "+30m"], [60, "+1h"], [120, "+2h"]];
  } else {
    heading = "Stop after";
    options = [[30, "30m"], [60, "1h"], [120, "2h"], [240, "4h"]];
  }
  const key = heading;
  if (key === chipKey) return;
  chipKey = key;
  setText(el.chipsHeading, heading);
  el.chips.replaceChildren(
    ...options.map(([minutes, title]) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "chip";
      button.textContent = title;
      button.addEventListener("click", () => {
        if (state.phase === "off") startTimer(minutes);
        else if (state.timed) addTime(minutes);
        else stopAfter(minutes);
      });
      return button;
    }),
  );
}

const icons = {
  posted: '<circle cx="10" cy="10" r="8" fill="currentColor"/><path d="m6.4 10.2 2.5 2.5 4.8-5.2" fill="none" stroke="#000" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>',
  postedRow: '<circle cx="10" cy="10" r="7.6" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="m6.6 10.2 2.3 2.3 4.5-4.9" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>',
  skipped: '<path d="M6.2 11.2V6.4a1.2 1.2 0 0 1 2.4 0v3.4V4.6a1.2 1.2 0 0 1 2.4 0v5.2V5.4a1.2 1.2 0 0 1 2.4 0v5.4-2.2a1.2 1.2 0 0 1 2.4 0v3.8c0 3.3-2.3 5.6-5.4 5.6-2.2 0-3.5-1-4.6-2.8L4 12.2a1.2 1.2 0 0 1 2-1.3z" fill="currentColor"/>',
  paused: '<path d="M11.6 3.2a7.2 7.2 0 1 0 5.2 10.2 5.9 5.9 0 0 1-5.2-10.2z" fill="currentColor"/>',
  problem: '<path d="M10 2.8 18 16.8H2z" fill="currentColor" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M10 8v4" stroke="#000" stroke-width="1.8" stroke-linecap="round"/><circle cx="10" cy="14.4" r="1" fill="#000"/>',
};
const svg = (name) => `<svg viewBox="0 0 20 20" width="16" height="16" aria-hidden="true">${icons[name]}</svg>`;

function bar(entry) {
  const node = document.createElement("i");
  if (entry.kind !== "posted") node.className = entry.kind;
  if (entry.fresh) node.classList.add("is-new");
  return node;
}

function renderBars() {
  const last = state.pulses[state.pulses.length - 1];
  const key = `${state.pulses.length}:${last?.at}`;
  if (key === barKey) return;
  barKey = key;

  el.bars.replaceChildren(...state.pulses.slice(-BAR_COUNT).map(bar));
  setText(el.pulseTime, last ? timeFormat.format(last.at) : "");

  // The Pulse Log window
  if (el.logBars) {
    const empty = Array.from({ length: LOG_COUNT - state.pulses.length }, () => {
      const node = document.createElement("i");
      node.className = "empty";
      return node;
    });
    el.logBars.replaceChildren(...empty, ...state.pulses.map(bar));
    setText(el.logFirst, state.pulses.length ? timeFormat.format(state.pulses[0].at) : "");
    setText(el.logLatest, last ? `Latest ${timeFormat.format(last.at)}` : "No attempts yet");

    el.logTallies.replaceChildren(
      ...[["posted", "Posted"], ["skipped", "Skipped"], ["paused", "Paused"], ["problem", "Problems"]].map(([kind, title]) => {
        const tally = document.createElement("div");
        tally.className = `tally ${kind}`;
        tally.innerHTML = `${svg(kind)}<strong></strong><span></span>`;
        tally.querySelector("strong").textContent = String(counts[kind]);
        tally.querySelector("span").textContent = title;
        return tally;
      }),
    );

    // The desktop icon draws the last few attempts, so it reads as live
    const recent = state.pulses.slice(-el.iconBars.length);
    el.iconBars.forEach((path, index) => {
      const entry = recent[index - (el.iconBars.length - recent.length)];
      const x = 11 + index * 5.2;
      path.setAttribute("d", `M${x} 34V${!entry ? 33 : entry.kind === "posted" ? 14 + (index % 2) * 2 : 27}`);
      path.setAttribute("class", entry?.kind ?? "empty");
    });

    el.logList.replaceChildren(
      ...state.pulses.slice(-3).reverse().map((entry) => {
        const row = document.createElement("li");
        row.className = entry.kind;
        if (entry.fresh) row.classList.add("is-new");
        row.innerHTML = `${svg(entry.kind === "posted" ? "postedRow" : entry.kind)}<span><strong></strong><small></small></span><time></time>`;
        row.querySelector("strong").textContent = entry.summary;
        row.querySelector("small").textContent = entry.explanation;
        row.querySelector("time").textContent = secondsFormat.format(entry.at);
        return row;
      }),
    );
  }
  for (const entry of state.pulses) entry.fresh = false;
}

function render() {
  const { phase } = state;
  menu.dataset.phase = phase;
  desktop.dataset.phase = phase;

  const title = phase === "active" ? "Active" : phase === "paused" ? "Paused" : "Off";
  setText(el.title, title);

  // The status line in the Read Me: the phase and the latest attempt
  const latest = state.pulses[state.pulses.length - 1];
  setText(el.liveTitle, title);
  setText(
    el.liveLatest,
    phase === "off" ? "Not keeping you online" : latest ? `${latest.summary}, ${timeFormat.format(latest.at)}` : "No attempts yet",
  );
  setText(el.today, state.today >= 60 ? `${duration(state.today)} online today` : "");

  if (phase === "off") {
    setText(el.countdown, "Not keeping you online");
    setText(el.unit, "");
  } else {
    setText(el.countdown, hms(state.timed ? state.remaining : state.elapsed));
    setText(el.unit, state.timed ? "left" : "elapsed");
  }
  setText(el.detail, detailLine());
  el.detail.hidden = !el.detail.textContent;

  const fraction = phase === "off" ? 0 : state.timed ? Math.max(0, state.remaining / state.total) : 1;
  el.ring.style.strokeDashoffset = String(RING * (1 - fraction));

  setText(el.primaryLabel, phase === "active" ? "Pause" : phase === "paused" ? "Resume" : "Keep Online");
  renderChips();
  renderBars();

  setText(el.clock, clockFormat.format(state.now));

  el.headlineDot?.classList.toggle("is-away", state.status === "away");
}

// Menu controls

$("[data-log-clear]")?.addEventListener("click", () => {
  state.pulses.length = 0;
  for (const kind of Object.keys(counts)) counts[kind] = 0;
  render();
});

// The menu starts closed. Until someone opens it, a note under the menu bar
// icon points it out.
const menuToggle = $("[data-menu-toggle]");
const coach = $("[data-coach]");
const COACH_KEY = "alwayson-menu-opened";

function setMenuOpen(open) {
  if (!menu) return;
  menu.hidden = !open;
  menuToggle.setAttribute("aria-expanded", String(open));
  if (open) dismissCoach();
}

function dismissCoach() {
  menuToggle.classList.toggle("is-beckoning", false);
  if (coach) coach.hidden = true;
  try {
    localStorage.setItem(COACH_KEY, "1");
  } catch {}
}

// The note sits where the menu will drop down, with its arrow under the icon
function placeCoach() {
  if (!coach) return;
  const rect = menuToggle.getBoundingClientRect();
  const fromRight = window.innerWidth - 10 - (rect.left + rect.width / 2) - 5.5;
  coach.style.setProperty("--coach-arrow", `${Math.min(Math.max(fromRight, 12), 226)}px`);
}

// In the stacked page the menu moves into the Read Me, under the download
// button, so phones get the demo first
const menuSlot = $("[data-menu-slot]");
const menuHome = menu?.parentNode;
function seatMenu() {
  if (!menu || !menuSlot) return;
  const target = stacked.matches ? menuSlot : menuHome;
  if (menu.parentNode !== target) target.append(menu);
}

$("[data-live]")?.addEventListener("click", () => {
  setMenuOpen(true);
  $("[data-primary]")?.focus({ preventScroll: true });
});

if (menu) {
  $("[data-primary]").addEventListener("click", () => {
    if (state.phase === "active") pause();
    else if (state.phase === "paused") resume();
    else keepOnline();
  });
  $("[data-stop]").addEventListener("click", stop);

  const pauseToggle = $("[data-pause-for-toggle]");
  const pauseMenu = $("[data-pause-for-menu]");
  const closePauseMenu = () => {
    pauseMenu.hidden = true;
    pauseToggle.setAttribute("aria-expanded", "false");
  };
  pauseToggle.addEventListener("click", (event) => {
    event.stopPropagation();
    const open = pauseMenu.hidden;
    pauseMenu.hidden = !open;
    pauseToggle.setAttribute("aria-expanded", String(open));
    if (open) pauseMenu.querySelector("button")?.focus();
  });
  for (const option of $$("[data-pause-minutes]", pauseMenu)) {
    option.addEventListener("click", () => {
      pause(Number(option.dataset.pauseMinutes));
      closePauseMenu();
    });
  }
  document.addEventListener("click", (event) => {
    if (!pauseMenu.hidden && !pauseMenu.contains(event.target)) closePauseMenu();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !pauseMenu.hidden) {
      closePauseMenu();
      pauseToggle.focus();
    }
  });

  menuToggle.addEventListener("click", () => {
    // On a phone the menu sits in the page, so the icon just scrolls to it
    if (stacked.matches) menu.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "center" });
    else setMenuOpen(menu.hidden);
  });
  // Like a real menu, it closes when you click anywhere else on the desktop
  document.addEventListener("pointerdown", (event) => {
    if (menu.hidden || stacked.matches) return;
    if (menu.contains(event.target) || menuToggle.contains(event.target)) return;
    setMenuOpen(false);
  });
  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape" || menu.hidden || stacked.matches || !pauseMenu.hidden) return;
    setMenuOpen(false);
    menuToggle.focus();
  });
  $("[data-quit]").addEventListener("click", () => {
    stop();
    setMenuOpen(false);
    menuToggle.focus();
  });

}

// Windows: open from desktop icons, the menu bar, and the AlwaysOn menu.
// Drag them by the title bar, close them, or zoom them. On narrow or short
// screens they stack as a normal scrolling page instead.

const BAR = 32;
const stacked = window.matchMedia("(max-width: 900px), (max-height: 600px)");
const windows = Object.fromEntries($$("[data-window]").map((win) => [win.dataset.window, win]));
const sizes = { settings: [800, 600], until: [440, 620], terminal: [880, 470], activity: [560, 660] };
const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
let stack = 10;

function bringToFront(win) {
  for (const other of Object.values(windows)) other.classList.toggle("is-front", other === win);
  stack += 1;
  win.style.zIndex = String(stack);
}

function place(win, x, y, width, height) {
  Object.assign(win.style, {
    left: `${Math.round(x)}px`,
    top: `${Math.round(y)}px`,
    width: `${Math.round(width)}px`,
    height: height ? `${Math.round(height)}px` : "",
  });
}

// Only the Read Me is open on arrival, a little left of center and clear of
// the icons, which wrap into a second column on short screens
function arrange() {
  if (stacked.matches) return;
  const W = window.innerWidth;
  const H = window.innerHeight;
  const { readme, pulse } = windows;
  if (readme && !readme.dataset.moved) {
    // The right-hand column stays free for the menu and the Pulse Log
    const left = ($(".icons")?.offsetWidth ?? 98) + 18;
    const room = Math.max(420, W - rightColumn(W) - left);
    const width = Math.min(760, room);
    place(readme, left + (room - width) * 0.4, BAR + 14, width, H - BAR - 28);
  }
  if (pulse && pulse.dataset.placed && !pulse.dataset.moved) placePulse(pulse);
  placeCoach();
}

const pulseWidth = (W) => (W >= 1360 ? 400 : 360);
const rightColumn = (W) => (W >= 1200 ? pulseWidth(W) + 28 : 326);

// The Pulse Log opens in the right-hand column, where the menu drops down
function placePulse(win) {
  const W = window.innerWidth;
  const width = pulseWidth(W);
  const y = BAR + 14;
  place(win, W - 12 - width, y, width, null);
  win.style.maxHeight = `${Math.max(240, window.innerHeight - y - 12)}px`;
  win.dataset.placed = "1";
}

function cascade(win, name) {
  const [width, height] = sizes[name] ?? [600, 500];
  const W = window.innerWidth;
  const H = window.innerHeight;
  const open = $$("[data-window]:not([hidden])").length;
  const w = Math.min(width, W - 140);
  const h = Math.min(height, H - BAR - 32);
  const left = ($(".icons")?.offsetWidth ?? 98) + 18;
  const x = clamp(left + (W - left - w) * 0.3 + open * 26, left, W - w - 12);
  const y = clamp(BAR + 30 + open * 24, BAR + 8, H - h - 12);
  place(win, x, y, w, h);
  win.dataset.placed = "1";
}

function scrollWithin(body, target) {
  body.scrollTo({
    top: target.getBoundingClientRect().top - body.getBoundingClientRect().top + body.scrollTop - 20,
    behavior: reduceMotion ? "auto" : "smooth",
  });
}

// Parts of the Read Me that the menu bar links to
const sections = { features: "#features-title", install: "#install-title" };

function openWindow(name) {
  if (sections[name]) {
    openWindow("readme");
    const title = $(sections[name]);
    if (stacked.matches) title.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" });
    else scrollWithin($(".window-body", windows.readme), title);
    return;
  }
  const win = windows[name];
  if (!win) return;
  if (stacked.matches) {
    win.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" });
    return;
  }
  if (win.hidden) {
    win.hidden = false;
    if (!win.dataset.placed && name === "pulse") placePulse(win);
    else if (!win.dataset.placed && name !== "readme") cascade(win, name);
    if (!reduceMotion) {
      win.classList.toggle("is-opening", false);
      void win.offsetWidth;
      win.classList.add("is-opening");
    }
  }
  bringToFront(win);
  win.focus({ preventScroll: true });
}

function closeWindow(win) {
  win.hidden = true;
  win.classList.toggle("is-zoomed", false);
  win.classList.toggle("is-front", false);
  $(`.icon[data-open="${win.dataset.window}"]`)?.focus({ preventScroll: true });
  const next = Object.values(windows)
    .filter((other) => !other.hidden)
    .sort((a, b) => Number(b.style.zIndex) - Number(a.style.zIndex))[0];
  if (next) bringToFront(next);
}

for (const win of Object.values(windows)) {
  win.addEventListener("pointerdown", () => {
    if (!win.classList.contains("is-front")) bringToFront(win);
  });
  $("[data-close]", win)?.addEventListener("click", () => closeWindow(win));
  $("[data-zoom]", win)?.addEventListener("click", () => win.classList.toggle("is-zoomed"));

  const bar = $("[data-drag]", win);
  bar.addEventListener("dblclick", (event) => {
    if (!event.target.closest("button") && !stacked.matches) win.classList.toggle("is-zoomed");
  });
  bar.addEventListener("pointerdown", (event) => {
    if (stacked.matches || event.button !== 0 || event.target.closest("button") || win.classList.contains("is-zoomed")) return;
    const startX = event.clientX;
    const startY = event.clientY;
    const originX = win.offsetLeft;
    const originY = win.offsetTop;
    bar.setPointerCapture(event.pointerId);
    const move = (moveEvent) => {
      win.style.left = `${clamp(originX + moveEvent.clientX - startX, 120 - win.offsetWidth, window.innerWidth - 120)}px`;
      win.style.top = `${clamp(originY + moveEvent.clientY - startY, BAR, window.innerHeight - 44)}px`;
      win.dataset.moved = "1";
      win.dataset.placed = "1";
    };
    const end = () => {
      bar.removeEventListener("pointermove", move);
      bar.removeEventListener("pointerup", end);
      bar.removeEventListener("pointercancel", end);
    };
    bar.addEventListener("pointermove", move);
    bar.addEventListener("pointerup", end);
    bar.addEventListener("pointercancel", end);
  });
}

for (const opener of $$("[data-open]")) {
  opener.addEventListener("click", (event) => {
    event.preventDefault();
    const name = opener.dataset.open;
    for (const icon of $$(".icon")) icon.classList.toggle("is-selected", icon === opener);
    // Choosing a menu item closes the menu, as on a Mac
    if (menu?.contains(opener) && !stacked.matches) setMenuOpen(false);
    openWindow(name);
    history.replaceState(null, "", `#${name}`);
  });
}

// Clicking the empty desktop clears the icon selection
$(".desktop")?.addEventListener("pointerdown", (event) => {
  if (event.target === event.currentTarget || event.target.classList.contains("field-canvas")) {
    for (const icon of $$(".icon")) icon.classList.toggle("is-selected", false);
  }
});

let arrangeQueued = false;
window.addEventListener("resize", () => {
  if (arrangeQueued) return;
  arrangeQueued = true;
  requestAnimationFrame(() => {
    arrangeQueued = false;
    arrange();
    for (const win of Object.values(windows)) {
      if (!win.dataset.moved || stacked.matches) continue;
      win.style.left = `${clamp(win.offsetLeft, 120 - win.offsetWidth, window.innerWidth - 120)}px`;
      win.style.top = `${clamp(win.offsetTop, BAR, window.innerHeight - 44)}px`;
    }
  });
});
stacked.addEventListener("change", () => {
  seatMenu();
  arrange();
});

seatMenu();
arrange();
let coachSeen = false;
try {
  coachSeen = localStorage.getItem(COACH_KEY) === "1";
} catch {}
if (coach && menu && !coachSeen) {
  coach.hidden = false;
  menuToggle.classList.add("is-beckoning");
}
if (windows.readme) bringToFront(windows.readme);
const initial = location.hash.slice(1);
if (initial && (windows[initial] || sections[initial])) openWindow(initial);

// Input methods

const methods = $$("[data-method]");
function selectMethod(button) {
  state.method = button.dataset.method;
  state.nextAlternate = "mouse";
  for (const other of methods) {
    const on = other === button;
    other.setAttribute("aria-checked", String(on));
    other.tabIndex = on ? 0 : -1;
  }
}
methods.forEach((button, index) => {
  button.tabIndex = button.getAttribute("aria-checked") === "true" ? 0 : -1;
  button.addEventListener("click", () => selectMethod(button));
  button.addEventListener("keydown", (event) => {
    const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key];
    if (!step) return;
    event.preventDefault();
    const next = methods[(index + step + methods.length) % methods.length];
    selectMethod(next);
    next.focus();
  });
});

// The selected input card shows each input the demo sends

demo.subscribe((type, detail) => {
  if (type !== "nudge") return;
  const card = $('.method[aria-checked="true"]');
  if (!card) return;
  if (detail.method === "keyboard") {
    const key = $("[data-nudge-key]", card);
    key?.classList.add("is-pressed");
    setTimeout(() => key?.classList.remove("is-pressed"), 160);
  } else {
    const cursor = $("[data-nudge-cursor]", card);
    cursor?.classList.add("is-nudged");
    setTimeout(() => cursor?.classList.remove("is-nudged"), 420);
  }
});

// Keep Online Until card

const until = $("[data-until]");
if (until) {
  const ui = {
    end: $("[data-until-end]", until),
    rel: $("[data-until-rel]", until),
    picks: $$("[data-add]", until),
    label: $("[data-until-label]", until),
    events: $("[data-until-events]", until),
    start: $("[data-until-start]", until),
    done: $("[data-until-done]", until),
    tabs: $$("[data-until-tab]", until),
  };

  let mode = "time";
  let pickMinutes = 60;
  let endAt = state.now + pickMinutes * 60 * 1000;
  let eventIndex = 1;

  const round5 = (time) => Math.ceil(time / (5 * 60 * 1000)) * 5 * 60 * 1000;
  const startOfEvents = round5(state.now);
  const events = [
    { title: "Standup", start: startOfEvents + 20 * 60000, minutes: 15 },
    { title: "Planning", start: startOfEvents + 50 * 60000, minutes: 60 },
    { title: "1:1 with Priya", start: startOfEvents + 150 * 60000, minutes: 30 },
  ];

  ui.events.replaceChildren(
    ...events.map((event, index) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "event";
      button.setAttribute("role", "radio");
      button.innerHTML = `<i aria-hidden="true"></i><span><strong></strong><small></small></span>`;
      button.querySelector("strong").textContent = event.title;
      const end = event.start + event.minutes * 60000;
      button.querySelector("small").textContent = `${timeFormat.format(event.start)} to ${timeFormat.format(end)}`;
      button.addEventListener("click", () => {
        eventIndex = index;
        refresh();
      });
      return button;
    }),
  );

  const relative = (time) => {
    const minutes = Math.max(0, Math.round((time - state.now) / 60000));
    const sameDay = new Date(time).toDateString() === new Date(state.now).toDateString();
    return `${sameDay ? "Today" : "Tomorrow"}, in ${duration(minutes * 60)}`;
  };

  function target() {
    if (mode === "calendar") {
      const event = events[eventIndex];
      return { end: event.start + event.minutes * 60000, label: event.title };
    }
    return { end: endAt, label: ui.label.value.trim() };
  }

  function refresh() {
    if (endAt <= state.now + 60000) endAt = state.now + pickMinutes * 60 * 1000;
    ui.end.textContent = timeFormat.format(endAt);
    ui.rel.textContent = relative(endAt);
    ui.picks.forEach((pick) => pick.classList.toggle("is-selected", Number(pick.dataset.add) === pickMinutes));
    $$(".event", ui.events).forEach((button, index) => button.setAttribute("aria-checked", String(index === eventIndex)));
    ui.start.textContent = `Keep Online Until ${timeFormat.format(target().end)}`;
  }

  ui.picks.forEach((pick) =>
    pick.addEventListener("click", () => {
      pickMinutes = Number(pick.dataset.add);
      endAt = state.now + pickMinutes * 60 * 1000;
      ui.done.textContent = "";
      refresh();
    }),
  );

  ui.tabs.forEach((tab) =>
    tab.addEventListener("click", () => {
      mode = tab.dataset.untilTab;
      for (const other of ui.tabs) {
        const on = other === tab;
        other.setAttribute("aria-selected", String(on));
        $(`#${other.getAttribute("aria-controls")}`).hidden = !on;
      }
      ui.done.textContent = "";
      refresh();
    }),
  );

  ui.start.addEventListener("click", () => {
    const { end, label } = target();
    if (end <= state.now) {
      ui.done.textContent = "That time has passed. Pick a later one.";
      return;
    }
    startUntil(end, label);
    ui.done.textContent = `Started. The AlwaysOn menu now ends at ${timeFormat.format(end)}.`;
  });

  setInterval(refresh, 1000);
  refresh();
}

// Terminal: types its commands once it scrolls into view

const terminal = $("[data-terminal-code]");
if (terminal) {
  // Output lines are what the CLI prints
  const lines = [
    ["$", "alwayson install"],
    [">", "Installed /Users/you/.local/bin/alwayson"],
    ["$", "alwayson run -- swift test"],
    ["#", "online until the tests finish, even after Ctrl-C"],
    [">", "Executed 214 tests, with 0 failures (0 unexpected) in 41.208 seconds"],
    ["$", "alwayson timer 30"],
    [">", "Sent timer request to AlwaysOn; app acknowledgement is unavailable."],
    ["$", "alwayson until 17:30"],
    [">", "Sent until request to AlwaysOn; app acknowledgement is unavailable."],
  ];

  const caret = document.createElement("span");
  caret.className = "caret";

  function line(kind, text) {
    const span = document.createElement("span");
    if (kind === "$") {
      const prompt = document.createElement("span");
      prompt.className = "p";
      prompt.textContent = "$ ";
      span.append(prompt, document.createTextNode(text));
    } else if (kind === "#") {
      span.className = "c";
      span.textContent = `# ${text}`;
    } else {
      span.className = "o";
      span.textContent = text;
    }
    return span;
  }

  const showAll = () => {
    terminal.replaceChildren(...lines.flatMap(([kind, text]) => [line(kind, text), document.createTextNode("\n")]));
    terminal.append(line("$", ""), caret);
  };

  if (reduceMotion || !("IntersectionObserver" in window)) {
    showAll();
  } else {
    const observer = new IntersectionObserver(async ([entry]) => {
      if (!entry.isIntersecting) return;
      observer.disconnect();
      const wait = (delay) => new Promise((done) => setTimeout(done, delay));
      for (const [kind, text] of lines) {
        const node = line(kind, kind === "$" ? "" : text);
        terminal.append(node, caret);
        if (kind === "$") {
          for (const char of text) {
            node.lastChild.textContent += char;
            await wait(32);
          }
          await wait(260);
        } else {
          await wait(180);
        }
        caret.before(document.createTextNode("\n"));
      }
      terminal.append(line("$", ""), caret);
    }, { threshold: 0.4 });
    observer.observe(terminal);
  }
}

// Start

render();
let timer = setInterval(tick, TICK_MS);
document.addEventListener("visibilitychange", () => {
  clearInterval(timer);
  if (!document.hidden) timer = setInterval(tick, TICK_MS);
});

const hero = $("[data-hero]");
if (hero && !reduceMotion && supportsWebGL()) {
  import("/hero3d.js")
    .then((module) => module.start({ demo, hero }))
    .catch(() => {});
}

function supportsWebGL() {
  try {
    const canvas = document.createElement("canvas");
    return Boolean(canvas.getContext("webgl2") || canvas.getContext("webgl"));
  } catch {
    return false;
  }
}
