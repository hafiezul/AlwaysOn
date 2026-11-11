// The landing page's working demo. A copy of the AlwaysOn menu runs on a
// simulated clock, 20 times faster than real time. Your own mouse and keyboard
// count as using the Mac. Every 45 simulated seconds an active session posts a
// tiny input, or skips it if you were active, and a copy of the Pulse Log
// window records each attempt in the app's own words. With no input for 5
// simulated minutes, the headline's second dot turns Away yellow. hero3d.js
// draws the hero's pixel field when WebGL is available and motion is allowed.
//
// Around the demo, the page behaves like a Mac: windows open from the Dock
// and the desktop, drag, resize, zoom and minimize; the app's name opens a
// menu; notifications slide in under the menu bar; and the screen can lock,
// which pauses AlwaysOn the way a locked Mac does.

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
const dateFormat = new Intl.DateTimeFormat(undefined, { weekday: "long", month: "long", day: "numeric" });
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

// Visit counts. They're anonymous and nothing is stored in the browser;
// src/worker.js explains what is sent on. The ID below only ties this page
// load's events together and is gone when the page closes.

const visit = uuidv7();

function uuidv7() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  const time = Date.now();
  for (let index = 0; index < 6; index += 1) bytes[index] = Math.floor(time / 2 ** (8 * (5 - index))) % 256;
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

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

track("$pageview");
document.addEventListener("click", (event) => {
  const link = event.target.closest?.("[data-outbound]");
  if (link) track("outbound_click", link.dataset.outbound);
});

// Latest version and star count

const latest = { version: null, stars: null };
const compact = new Intl.NumberFormat("en", { notation: "compact", maximumFractionDigits: 1 });

fetch("/latest.json")
  .then((response) => response.json())
  .then((data) => {
    Object.assign(latest, data);
    if (latest.version) {
      setText($("[data-version]"), `Latest version ${latest.version}.`);
      setText($("[data-about-version]"), `Version ${latest.version}`);
    }
    if (Number.isInteger(latest.stars)) {
      const count = compact.format(latest.stars);
      const slot = $("[data-stars]");
      setText(slot, count);
      slot.hidden = false;
      slot.parentElement.setAttribute("aria-label", `Star AlwaysOn on GitHub. ${count} so far.`);
      setText(
        $("[data-about-stars]"),
        latest.stars === 0 ? "Be the first to star it on GitHub" : `${count} ${latest.stars === 1 ? "star" : "stars"} on GitHub`,
      );
    }
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
  // Today's online time by what started it, as the app's Activity keeps it
  todayByKind: { schedule: 2 * 3600, timer: 3600 },
  idle: 0, // how long the Mac has had no input, from you or AlwaysOn
  sinceYou: 999, // how long since your own input
  nextPulse: PULSE_EVERY,
  method: "alternate",
  nextAlternate: "mouse",
  status: "available",
  locked: false, // the page's lock screen is up
  lowPower: false, // Low Power Mode doubles the time between inputs
  profile: "Work",
  pendingProfile: null, // applies when the running session ends
  focusSession: false, // the running session was started by a Focus
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
    focusSession: false,
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
    focusSession: false,
  });
  render();
}

function keepOnline() {
  Object.assign(state, { phase: "active", timed: false, absolute: false, elapsed: 0, label: null, resumesAt: null, focusSession: false });
  render();
}

// Pausing or resuming a session a Focus started makes it yours
function pause(minutes = null) {
  state.phase = "paused";
  state.focusSession = false;
  state.resumesAt = minutes ? state.now + minutes * 60 * 1000 : null;
  render();
}

function resume() {
  state.phase = "active";
  state.focusSession = false;
  state.resumesAt = null;
  render();
}

function stop() {
  state.phase = "off";
  state.resumesAt = null;
  state.focusSession = false;
  // A profile that was waiting for the session to end applies now
  if (state.pendingProfile) {
    state.profile = state.pendingProfile;
    state.pendingProfile = null;
  }
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

  // A locked Mac takes no input, so the app waits and says so
  if (state.locked) {
    heldBack += 1;
    record("systemPaused", state.now, true);
    return;
  }

  let kind = "posted";
  if (state.sinceYou < PULSE_EVERY) {
    kind = "skipped";
    emit("skip");
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
    const kind = sessionKind();
    state.todayByKind[kind] = (state.todayByKind[kind] ?? 0) + dt;
    if (state.timed) state.remaining -= dt;
    else state.elapsed += dt;
  } else if (state.phase === "paused" && state.absolute) {
    state.remaining -= dt;
  }

  if (state.timed && state.phase !== "off" && state.remaining <= 0) {
    stop();
    notify({
      title: "Session ended",
      body: "The timer ran out, so AlwaysOn stopped keeping you online. Click to start another hour.",
      onClick: () => startTimer(60),
    });
  }

  state.nextPulse -= dt;
  if (state.nextPulse <= 0) {
    state.nextPulse += PULSE_EVERY * (state.lowPower ? 2 : 1);
    pulse();
  }

  const status = state.idle >= AWAY_AFTER ? "away" : "available";
  if (status !== state.status) {
    state.status = status;
    emit("status", { status });
  }

  render();
}

// What started the running session, in the app's own kinds
function sessionKind() {
  const label = state.label ?? "";
  if (state.focusSession || label.includes("Focus")) return "focus";
  if (label.startsWith("Until")) return "until";
  if (label === "via Quick Timer") return "timer";
  return "manual";
}

// Your own input counts as using the Mac
let lastInput = 0;
let lastTouched = Date.now(); // in real time, not the demo's
const TEAMS_AWAY = 5 * 60; // seconds of no input before Teams shows Away

function onInput() {
  const now = performance.now();
  if (state.locked || now - lastInput < 100) return;
  lastInput = now;
  state.sinceYou = 0;
  state.idle = 0;
  welcomeBack();
}

// Leave the page alone for a real minute and it tells you what your status
// would have done in the meantime
function welcomeBack() {
  const away = (Date.now() - lastTouched) / 1000;
  lastTouched = Date.now();
  if (away < 60) return;
  notify({
    title: `You were away for ${duration(away)}`,
    body:
      away < TEAMS_AWAY
        ? `Teams turns you yellow after 5 minutes without input. You had ${duration(TEAMS_AWAY - away)} left.`
        : away < TEAMS_AWAY + 60
          ? "Teams turns you yellow after 5 minutes without input, so you had just gone Away."
          : `Teams would have turned you yellow ${duration(away - TEAMS_AWAY)} ago. AlwaysOn would have kept you green.`,
  });
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
  profile: $("[data-profile]"),
  lockTime: $("[data-lock-time]"),
  lockDate: $("[data-lock-date]"),
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
  renderActivity();
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

  setText(el.profile, state.pendingProfile ? `${state.profile}, then ${state.pendingProfile} ›` : `${state.profile} ›`);
  setText(el.clock, clockFormat.format(state.now));
  if (state.locked) {
    setText(el.lockTime, timeFormat.format(state.now));
    setText(el.lockDate, dateFormat.format(state.now));
  }

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

let coachSeen = false;
try {
  coachSeen = localStorage.getItem(COACH_KEY) === "1";
} catch {}

function setMenuOpen(open) {
  if (!menu) return;
  menu.hidden = !open;
  menuToggle.setAttribute("aria-expanded", String(open));
  if (open) dismissCoach();
  // The first time it closes, a note shows where it went
  else if (!coachSeen && coach && !state.locked && !stacked.matches) {
    coach.hidden = false;
    menuToggle.classList.add("is-beckoning");
  }
}

function dismissCoach() {
  coachSeen = true;
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

// Windows: open from the Dock, the desktop icons, the menu bar, and the
// AlwaysOn menu. Drag them by the title bar, resize them from the corner,
// and close, minimize, or zoom them with the lights. On narrow or short
// screens they stack as a normal scrolling page instead.

const BAR = 32;
const stacked = window.matchMedia("(max-width: 900px), (max-height: 600px)");
const windows = Object.fromEntries($$("[data-window]").map((win) => [win.dataset.window, win]));
// Height 0 means as tall as the content
const sizes = { settings: [800, 600], until: [440, 620], terminal: [880, 470], activity: [600, 560], install: [600, 640], about: [300, 0] };
const clamp = (value, min, max) => Math.min(Math.max(value, min), max);
const dock = $("[data-dock]");
const minimizedSlot = $("[data-dock-minimized]");
// The room the Dock takes at the bottom of the desktop
const dockSpace = () => (dock?.offsetParent ? dock.offsetHeight + 14 : 0);
let order = [];

function bringToFront(win) {
  order = order.filter((other) => other !== win);
  order.push(win);
  order.forEach((other, index) => {
    other.style.zIndex = String(10 + index);
    other.classList.toggle("is-front", other === win);
  });
}

function frontNext() {
  const next = order.filter((other) => !other.hidden).pop();
  if (next) bringToFront(next);
}

// A dot under each Dock icon whose window is open or minimized
function syncDock() {
  for (const item of $$(".dock-item[data-open]")) {
    const win = windows[item.dataset.open];
    item.classList.toggle("is-running", Boolean(win && (!win.hidden || win.dataset.minimized)));
  }
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
// the icons and the Dock
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
    place(readme, left + (room - width) * 0.4, BAR + 14, width, H - BAR - 22 - dockSpace());
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
  win.style.maxHeight = `${Math.max(240, window.innerHeight - y - 8 - dockSpace())}px`;
  win.dataset.placed = "1";
}

function cascade(win, name) {
  const [width, height] = sizes[name] ?? [600, 500];
  const W = window.innerWidth;
  const H = window.innerHeight;
  const open = $$("[data-window]:not([hidden])").length;
  const w = Math.min(width, W - 140);
  const h = Math.min(height, H - BAR - 24 - dockSpace());
  const left = ($(".icons")?.offsetWidth ?? 98) + 18;
  const x = clamp(left + (W - left - w) * 0.3 + open * 26, left, W - w - 12);
  const y = clamp(BAR + 30 + open * 24, BAR + 8, Math.max(BAR + 8, H - dockSpace() - (h || 420) - 8));
  place(win, x, y, w, h);
  win.dataset.placed = "1";
}

// Minimizing: the window shrinks into a tile at the right of the Dock, and
// comes back out of it

function titleOf(win) {
  return $(".titlebar-title", win)?.textContent || "About AlwaysOn";
}

function fly(win, tile, back) {
  if (reduceMotion || !win.animate) return Promise.resolve();
  const from = win.getBoundingClientRect();
  const to = tile.getBoundingClientRect();
  const x = to.left + to.width / 2 - (from.left + from.width / 2);
  const y = to.top + to.height / 2 - (from.top + from.height / 2);
  const small = `translate(${x}px, ${y}px) scale(${to.width / from.width}, ${to.height / from.height})`;
  const frames = [
    { transform: "none", opacity: 1 },
    { transform: small, opacity: 0.3 },
  ];
  return win
    .animate(back ? frames.reverse() : frames, { duration: 300, easing: "cubic-bezier(0.32, 0.72, 0, 1)" })
    .finished.catch(() => {});
}

function minimize(win) {
  if (stacked.matches || win.dataset.minimized) return;
  const name = win.dataset.window;
  const tile = document.createElement("button");
  tile.type = "button";
  tile.className = "dock-item dock-tile";
  tile.dataset.restore = name;
  tile.innerHTML =
    '<svg viewBox="0 0 48 48" aria-hidden="true"><rect x="4" y="8" width="40" height="32" rx="5" fill="#1c1c1e" stroke="#48484a"/><path d="M4 16.5h40" stroke="#48484a"/><circle cx="9.5" cy="12.3" r="1.6" fill="#ff5f57"/><circle cx="14.5" cy="12.3" r="1.6" fill="#febc2e"/><circle cx="19.5" cy="12.3" r="1.6" fill="#28c840"/><path d="M11 23.5h20M11 29.5h26M11 35.5h14" stroke="#636366" stroke-width="2" stroke-linecap="round"/></svg><span class="dock-label"></span>';
  tile.lastChild.textContent = titleOf(win);
  tile.setAttribute("aria-label", `Restore ${titleOf(win)}`);
  tile.addEventListener("click", () => openWindow(name));
  minimizedSlot.append(tile);

  win.dataset.minimized = "1";
  win.classList.toggle("is-zoomed", false);
  fly(win, tile, false).then(() => {
    // It may have been restored while it was still shrinking
    if (!win.dataset.minimized) return;
    win.hidden = true;
    win.classList.toggle("is-front", false);
    frontNext();
    syncDock();
  });
}

function scrollWithin(body, target) {
  body.scrollTo({
    top: target.getBoundingClientRect().top - body.getBoundingClientRect().top + body.scrollTop - 20,
    behavior: reduceMotion ? "auto" : "smooth",
  });
}

// Parts of the Read Me that the menu bar links to
const sections = { features: "#features-title" };

function openWindow(name) {
  if (sections[name]) {
    openWindow("readme");
    const title = $(sections[name]);
    if (stacked.matches) title.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" });
    else scrollWithin($(".window-body", windows.readme), title);
    // The heading flashes, so the link visibly lands even with nothing to scroll
    title.classList.toggle("is-flash", false);
    void title.offsetWidth;
    title.classList.add("is-flash");
    return;
  }
  const win = windows[name];
  if (!win) return;
  if (stacked.matches) {
    win.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" });
    return;
  }
  const tile = $(`[data-restore="${name}"]`);
  if (tile) {
    delete win.dataset.minimized;
    win.hidden = false;
    fly(win, tile, true);
    tile.remove();
  } else if (win.hidden) {
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
  syncDock();
  if (name === "activity") renderActivity();
  win.focus({ preventScroll: true });
}

function closeWindow(win) {
  const name = win.dataset.window;
  win.hidden = true;
  win.classList.toggle("is-zoomed", false);
  win.classList.toggle("is-front", false);
  $(`.dock-item[data-open="${name}"], .icon[data-open="${name}"]`)?.focus({ preventScroll: true });
  frontNext();
  syncDock();
}

// Follows a pointer from a press to its release
function dragFrom(handle, event, onMove, onEnd) {
  handle.setPointerCapture(event.pointerId);
  const move = (moveEvent) => onMove(moveEvent.clientX - event.clientX, moveEvent.clientY - event.clientY);
  const end = () => {
    handle.removeEventListener("pointermove", move);
    handle.removeEventListener("pointerup", end);
    handle.removeEventListener("pointercancel", end);
    onEnd?.();
  };
  handle.addEventListener("pointermove", move);
  handle.addEventListener("pointerup", end);
  handle.addEventListener("pointercancel", end);
}

for (const win of Object.values(windows)) {
  win.addEventListener("pointerdown", () => {
    if (!win.classList.contains("is-front")) bringToFront(win);
  });
  $("[data-close]", win)?.addEventListener("click", () => closeWindow(win));
  $("[data-min]", win)?.addEventListener("click", () => minimize(win));
  $("[data-zoom]", win)?.addEventListener("click", () => win.classList.toggle("is-zoomed"));

  const bar = $("[data-drag]", win);
  bar.addEventListener("dblclick", (event) => {
    if (!event.target.closest("button") && !stacked.matches && $("[data-zoom]", win)) win.classList.toggle("is-zoomed");
  });
  bar.addEventListener("pointerdown", (event) => {
    if (stacked.matches || event.button !== 0 || event.target.closest("button") || win.classList.contains("is-zoomed")) return;
    const originX = win.offsetLeft;
    const originY = win.offsetTop;
    dragFrom(bar, event, (dx, dy) => {
      win.style.left = `${clamp(originX + dx, 120 - win.offsetWidth, window.innerWidth - 120)}px`;
      win.style.top = `${clamp(originY + dy, BAR, window.innerHeight - 44)}px`;
      win.dataset.moved = "1";
      win.dataset.placed = "1";
    });
  });

  // The bottom right corner resizes, except on the fixed-size About box
  if (!$("[data-zoom]", win)) continue;
  const grip = document.createElement("span");
  grip.className = "grip";
  grip.setAttribute("aria-hidden", "true");
  win.append(grip);
  grip.addEventListener("pointerdown", (event) => {
    if (stacked.matches || event.button !== 0 || win.classList.contains("is-zoomed")) return;
    event.preventDefault();
    const width = win.offsetWidth;
    const height = win.offsetHeight;
    win.style.maxHeight = "none";
    dragFrom(grip, event, (dx, dy) => {
      win.style.width = `${clamp(width + dx, 320, window.innerWidth - win.offsetLeft - 4)}px`;
      win.style.height = `${clamp(height + dy, 220, window.innerHeight - win.offsetTop - 4)}px`;
      win.dataset.moved = "1";
      win.dataset.placed = "1";
    });
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
    track("window_opened", name);
  });
}

// What the address asks for: a window, a part of the Read Me, or the download
function route() {
  const name = location.hash.slice(1);
  if (name === "download") {
    // Reloading the page shouldn't download it twice
    history.replaceState(null, "", "#install");
    startDownload();
  } else if (windows[name] || sections[name]) {
    openWindow(name);
  }
}

// The Dock's icons grow under the pointer
if (dock && !reduceMotion && window.matchMedia("(hover: hover) and (pointer: fine)").matches) {
  const PEAK = 1.42; // times the resting size
  const REACH = 120;
  const short = window.matchMedia("(max-height: 720px)");
  dock.addEventListener("pointermove", (event) => {
    const base = short.matches ? 38 : 48;
    // Measure every icon before resizing any, so the Dock is laid out once
    const items = $$(".dock-item", dock);
    const centers = items.map((item) => {
      const rect = item.getBoundingClientRect();
      return rect.left + rect.width / 2;
    });
    items.forEach((item, index) => {
      const lift = Math.cos((Math.min(Math.abs(event.clientX - centers[index]) / REACH, 1) * Math.PI) / 2);
      item.style.setProperty("--size", `${(base * (1 + (PEAK - 1) * lift)).toFixed(1)}px`);
    });
  });
  dock.addEventListener("pointerleave", () => {
    for (const item of $$(".dock-item", dock)) item.style.removeProperty("--size");
  });
}

// Pressing the empty desktop clears the icon selection. Dragging from there
// draws a selection box that picks up the icons it touches.
const desk = $(".desktop");
// The wallpaper, or the gaps in the column the icons sit in
const isEmptyDesktop = (target) => target === desk || target.classList.contains("field-canvas") || target.classList.contains("icons");
desk?.addEventListener("pointerdown", (event) => {
  if (!isEmptyDesktop(event.target)) return;
  const icons = $$(".icon");
  for (const icon of icons) icon.classList.toggle("is-selected", false);
  if (stacked.matches || event.pointerType !== "mouse" || event.button !== 0) return;

  const box = document.createElement("div");
  box.className = "marquee";
  desk.append(box);
  dragFrom(
    desk,
    event,
    (dx, dy) => {
      const left = Math.min(event.clientX, event.clientX + dx);
      const top = Math.max(BAR, Math.min(event.clientY, event.clientY + dy));
      const right = Math.max(event.clientX, event.clientX + dx);
      const bottom = Math.max(event.clientY, event.clientY + dy);
      Object.assign(box.style, { left: `${left}px`, top: `${top}px`, width: `${right - left}px`, height: `${bottom - top}px` });
      for (const icon of icons) {
        const rect = icon.getBoundingClientRect();
        icon.classList.toggle("is-selected", rect.left < right && rect.right > left && rect.top < bottom && rect.bottom > top);
      }
    },
    () => box.remove(),
  );
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
// Visitors arrive to the AlwaysOn menu, open under its icon
if (menu && !stacked.matches && !location.hash.slice(1)) {
  menu.hidden = false;
  menuToggle.setAttribute("aria-expanded", "true");
}

// The app menu, under the app's name in the menu bar

const appToggle = $("[data-app-menu-toggle]");
const appMenu = $("[data-app-menu]");

function setAppMenuOpen(open) {
  if (!appMenu) return;
  appMenu.hidden = !open;
  appToggle.setAttribute("aria-expanded", String(open));
}

if (appMenu) {
  const items = () => $$('[role="menuitem"]', appMenu).filter((item) => item.offsetParent);
  appToggle.addEventListener("click", (event) => {
    setAppMenuOpen(appMenu.hidden);
    // Opened from the keyboard, so start on the first item
    if (!appMenu.hidden && event.detail === 0) items()[0]?.focus();
  });
  appMenu.addEventListener("click", (event) => {
    if (event.target.closest('[role="menuitem"]')) setAppMenuOpen(false);
  });
  appMenu.addEventListener("keydown", (event) => {
    const step = { ArrowDown: 1, ArrowUp: -1 }[event.key];
    if (!step) return;
    event.preventDefault();
    const all = items();
    all[(all.indexOf(document.activeElement) + step + all.length) % all.length]?.focus();
  });
  document.addEventListener("pointerdown", (event) => {
    if (!appMenu.hidden && !appMenu.contains(event.target) && !appToggle.contains(event.target)) setAppMenuOpen(false);
  });
  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape" || appMenu.hidden) return;
    setAppMenuOpen(false);
    appToggle.focus();
  });

  $("[data-check-updates]")?.addEventListener("click", () => {
    notify(
      latest.version
        ? {
            title: `AlwaysOn ${latest.version} is the latest version`,
            body: "The app checks for itself and installs signed updates from GitHub Releases. Click to download.",
            onClick: () => startDownload(),
          }
        : { title: "Couldn't check for updates", body: "GitHub didn't answer. Click to open the Releases page.", onClick: () => window.open("https://github.com/hafiezul/AlwaysOn/releases", "_blank", "noopener") },
    );
  });
}

// Notifications slide in under the menu bar and leave on their own

const notes = $("[data-notes]");

function notify({ title, body, onClick }) {
  if (!notes) return;
  const note = document.createElement("button");
  note.type = "button";
  note.className = "note";
  note.innerHTML = '<img src="/images/icon-64.png" width="34" height="34" alt=""><span><strong></strong><small></small></span>';
  note.querySelector("strong").textContent = title;
  note.querySelector("small").textContent = body;
  const dismiss = () => {
    if (note.classList.contains("is-leaving")) return;
    note.classList.add("is-leaving");
    setTimeout(() => note.remove(), 220);
  };
  note.addEventListener("click", () => {
    dismiss();
    onClick?.();
  });
  notes.prepend(note);
  // The note about the menu sits in the same corner, so it steps aside
  if (coach) coach.hidden = true;
  while (notes.children.length > 3) notes.lastChild.remove();
  setTimeout(dismiss, 8000);
}

// Lock Screen: the app waits while the Mac is locked, and the Pulse Log says so

const lockScreen = $("[data-lock-screen]");
let heldBack = 0;
let lockedAt = 0;

function lock() {
  if (!lockScreen || state.locked) return;
  state.locked = true;
  heldBack = 0;
  lockedAt = performance.now();
  setMenuOpen(false);
  for (const part of [desk, $(".menubar"), notes]) if (part) part.inert = true;
  lockScreen.hidden = false;
  render();
  $("[data-unlock]", lockScreen)?.focus({ preventScroll: true });
}

function unlock() {
  // The click or key press that locked the screen shouldn't also unlock it
  if (!state.locked || performance.now() - lockedAt < 400) return;
  state.locked = false;
  state.sinceYou = 0;
  state.idle = 0;
  for (const part of [desk, $(".menubar"), notes]) if (part) part.inert = false;
  lockScreen.hidden = true;
  lastTouched = Date.now();
  notify({
    title: "Welcome back",
    body:
      state.phase !== "active"
        ? "AlwaysOn wasn't running, so there was nothing to hold back."
        : heldBack
          ? `AlwaysOn held back ${heldBack} ${heldBack === 1 ? "attempt" : "attempts"} while the Mac was locked. Click to see them in the Pulse Log.`
          : "That was quick. AlwaysOn had no attempt to hold back.",
    onClick: () => openWindow("pulse"),
  });
}

for (const button of $$("[data-lock]")) {
  button.addEventListener("click", () => {
    setPanel(null);
    lock();
  });
}
lockScreen?.addEventListener("click", unlock);
document.addEventListener("keydown", (event) => {
  if (!state.locked) return;
  event.preventDefault();
  unlock();
});

// Appearance: dark unless the visitor picks light, which is remembered

const THEME_KEY = "alwayson-theme";
const isLight = () => document.documentElement.dataset.theme === "light";

function setTheme(light) {
  if (light) document.documentElement.dataset.theme = "light";
  else delete document.documentElement.dataset.theme;
  try {
    localStorage.setItem(THEME_KEY, light ? "light" : "dark");
  } catch {}
  showTheme();
  document.dispatchEvent(new CustomEvent("themechange"));
}

function showTheme() {
  const light = isLight();
  $('meta[name="theme-color"]')?.setAttribute("content", light ? "#f5f5f7" : "#000000");
  $('meta[name="color-scheme"]')?.setAttribute("content", light ? "light" : "dark");
  // The app's screenshots come in both appearances
  for (const shot of $$('img[src*="/screenshots/"]')) {
    const name = shot.getAttribute("src").replace(/(-dark)?\.png$/, "");
    const src = `${name}${light ? "" : "-dark"}.png`;
    if (shot.getAttribute("src") !== src) shot.setAttribute("src", src);
  }
  showSystem();
}


// The menu bar's right-hand side: Wi-Fi, the battery, and Control Center.
// Each one changes something the app reacts to. Joining a network switches
// profiles, Low Power Mode halves how often input is sent, and a Focus starts
// a session of its own.

const sys = { wifi: true, network: "Office", focus: false, battery: 0.82, charging: false };
const networks = [
  { name: "Office", profile: "Work" },
  { name: "Home", profile: "Home" },
  { name: "Cafe Guest", profile: null },
];
const WIFI_ICON =
  '<svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true"><path d="M2.5 9a14 14 0 0 1 19 0M5.8 12.4a9.2 9.2 0 0 1 12.4 0M9.1 15.8a4.4 4.4 0 0 1 5.8 0" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><circle cx="12" cy="19" r="1.6" fill="currentColor"/></svg>';

const networkList = $("[data-networks]");
networkList?.replaceChildren(
  ...networks.map(({ name, profile }) => {
    const row = document.createElement("button");
    row.type = "button";
    row.className = "panel-row";
    row.setAttribute("role", "radio");
    row.dataset.network = name;
    row.innerHTML = `<i>${WIFI_ICON}</i><span></span><small></small>`;
    row.querySelector("span").textContent = name;
    row.querySelector("small").textContent = profile ? `${profile} profile` : "";
    row.addEventListener("click", () => joinNetwork(name));
    return row;
  }),
);

function showSystem() {
  const body = document.body;
  body.dataset.wifi = sys.wifi ? "on" : "off";
  body.toggleAttribute("data-low-power", state.lowPower);

  const on = { wifi: sys.wifi, lowPower: state.lowPower, focus: sys.focus, dark: !isLight() };
  for (const control of $$("[data-sys]")) {
    control.setAttribute(control.matches(".switch") ? "aria-checked" : "aria-pressed", String(on[control.dataset.sys]));
  }
  for (const row of $$("[data-network]")) row.setAttribute("aria-checked", String(sys.wifi && row.dataset.network === sys.network));

  setText($("[data-tile-wifi]"), sys.wifi ? sys.network : "Off");
  setText($("[data-tile-focus]"), sys.focus ? "Work" : "Off");
  setText($("[data-tile-power]"), state.lowPower ? "On" : "Off");
  setText($("[data-tile-dark]"), isLight() ? "Off" : "On");

  const percent = Math.round(sys.battery * 100);
  setText($("[data-battery-text]"), `${percent}%`);
  setText($("[data-battery-source]"), `Power Source: ${sys.charging ? "Power Adapter" : "Battery"}`);
  $("[data-battery-level]")?.setAttribute("width", String(Math.max(2, Math.round(18 * sys.battery))));
  $('[data-panel-toggle="battery"]')?.setAttribute("aria-label", `Battery, ${percent}%`);
}

// Joining a network applies its profile, but never in the middle of a session
function joinNetwork(name) {
  sys.wifi = true;
  sys.network = name;
  const profile = networks.find((network) => network.name === name)?.profile;
  state.pendingProfile = null;
  if (profile && profile !== state.profile) {
    if (state.phase === "off") {
      state.profile = profile;
      notify({ title: `Switched to the ${profile} profile`, body: `You joined ${name}, and that network belongs to the ${profile} profile.` });
    } else {
      state.pendingProfile = profile;
      notify({ title: `Joined ${name}`, body: `A session always finishes first. The ${profile} profile applies when this one ends.` });
    }
  }
  showSystem();
  render();
}

function setLowPower(enabled) {
  state.lowPower = enabled;
  if (enabled) {
    notify({ title: "Low Power Mode is on", body: `AlwaysOn now sends input every ${PULSE_EVERY * 2} seconds instead of every ${PULSE_EVERY}.` });
  }
  showSystem();
}

// A Focus with the Keep Me Online filter starts a session, and ends that
// session when it turns off, unless you made the session yours in between
function setFocus(enabled) {
  sys.focus = enabled;
  if (enabled && state.phase === "off") {
    keepOnline();
    Object.assign(state, { label: "via Work Focus", focusSession: true });
    notify({ title: "Work Focus is on", body: "Its Keep Me Online filter started a session. It ends when the Focus turns off." });
  } else if (enabled) {
    notify({ title: "Work Focus is on", body: "A session was already running, so AlwaysOn left it as it is." });
  } else if (state.focusSession && state.phase !== "off") {
    stop();
    notify({ title: "Work Focus is off", body: "AlwaysOn stopped the session the Focus started." });
  }
  showSystem();
  render();
}

for (const control of $$("[data-sys]")) {
  control.addEventListener("click", () => {
    const name = control.dataset.sys;
    if (name === "wifi" && sys.wifi) {
      sys.wifi = false;
      showSystem();
    } else if (name === "wifi") joinNetwork(sys.network);
    else if (name === "lowPower") setLowPower(!state.lowPower);
    else if (name === "focus") setFocus(!sys.focus);
    else if (name === "dark") setTheme(!isLight());
  });
}

// The visitor's own battery, where the browser reports it
navigator.getBattery?.()
  .then((battery) => {
    const read = () => {
      sys.battery = battery.level;
      sys.charging = battery.charging;
      showSystem();
    };
    battery.addEventListener("levelchange", read);
    battery.addEventListener("chargingchange", read);
    read();
  })
  .catch(() => {});

// One panel open at a time, under the icon that opened it
const panelToggles = $$("[data-panel-toggle]");
const panelFor = (toggle) => $(`[data-panel="${toggle.dataset.panelToggle}"]`);

function setPanel(name) {
  // Going from one panel straight to another skips the opening animation
  const switching = Boolean(name) && panelToggles.some((toggle) => !panelFor(toggle).hidden);
  for (const toggle of panelToggles) {
    const open = toggle.dataset.panelToggle === name;
    const panel = panelFor(toggle);
    panel.classList.toggle("is-instant", switching);
    if (open) panel.style.right = `${Math.max(8, window.innerWidth - toggle.getBoundingClientRect().right - 6)}px`;
    panel.hidden = !open;
    toggle.setAttribute("aria-expanded", String(open));
  }
}

for (const toggle of panelToggles) {
  toggle.addEventListener("click", () => setPanel(panelFor(toggle).hidden ? toggle.dataset.panelToggle : null));
}
document.addEventListener("pointerdown", (event) => {
  if (!event.target.closest("[data-panel], [data-panel-toggle]")) setPanel(null);
});
document.addEventListener("keydown", (event) => {
  const open = panelToggles.find((toggle) => !panelFor(toggle).hidden);
  if (event.key !== "Escape" || !open) return;
  setPanel(null);
  open.focus();
});
window.addEventListener("resize", () => setPanel(null));

showTheme();

// Desktop icons can be dragged, alone or as a selection. A drag isn't a click.

const iconLayer = $(".icons");
let draggedIcon = false;

iconLayer?.addEventListener("dragstart", (event) => event.preventDefault());
iconLayer?.addEventListener("pointerdown", (event) => {
  const icon = event.target.closest(".icon");
  if (!icon || stacked.matches || event.button !== 0 || event.pointerType === "touch") return;
  const group = icon.classList.contains("is-selected") ? $$(".icon.is-selected") : [icon];
  const origins = group.map((item) => ({ item, x: Number(item.dataset.x ?? 0), y: Number(item.dataset.y ?? 0), rect: item.getBoundingClientRect() }));
  let moved = false;
  dragFrom(
    icon,
    event,
    (dx, dy) => {
      if (!moved && Math.hypot(dx, dy) < 4) return;
      moved = true;
      for (const { item, x, y, rect } of origins) {
        // Keep every icon on the desktop: under the menu bar, above the Dock
        const moveX = clamp(dx, 4 - rect.left, window.innerWidth - 4 - rect.right);
        const moveY = clamp(dy, BAR + 4 - rect.top, window.innerHeight - dockSpace() - rect.bottom);
        item.dataset.x = String(x + moveX);
        item.dataset.y = String(y + moveY);
        item.style.transform = `translate(${x + moveX}px, ${y + moveY}px)`;
        item.classList.add("is-dragging");
      }
    },
    () => {
      for (const { item } of origins) item.classList.toggle("is-dragging", false);
      draggedIcon = moved;
    },
  );
});
// Capturing here runs before the icon's own click handlers
iconLayer?.addEventListener(
  "click",
  (event) => {
    if (!draggedIcon) return;
    draggedIcon = false;
    event.preventDefault();
    event.stopPropagation();
  },
  true,
);

function cleanUp() {
  for (const icon of $$(".icon")) {
    icon.style.transform = "";
    delete icon.dataset.x;
    delete icon.dataset.y;
  }
}

const FOLDER_ICON =
  '<svg viewBox="0 0 48 48" aria-hidden="true"><path d="M4 12a3 3 0 0 1 3-3h12l4 4h18a3 3 0 0 1 3 3v22a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3z" fill="#1d7ee0"/><path d="M4 18h40v20a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3z" fill="#47a8ff"/></svg>';
const MAX_FOLDERS = 8;

function newFolder() {
  const count = $$(".icon[data-folder]").length;
  const folder = document.createElement("button");
  folder.type = "button";
  folder.className = "icon is-selected";
  folder.dataset.folder = "1";
  folder.innerHTML = `${FOLDER_ICON}<span></span>`;
  folder.lastChild.textContent = count ? `untitled folder ${count + 1}` : "untitled folder";
  folder.addEventListener("click", () => {
    for (const icon of $$(".icon")) icon.classList.toggle("is-selected", icon === folder);
  });
  for (const icon of $$(".icon")) icon.classList.toggle("is-selected", false);
  iconLayer.append(folder);
}

// The menu that opens on a right-click: one for the desktop, one for an icon

const context = $("[data-context]");

function openContext(event, items) {
  context.replaceChildren(
    ...items.map((item) => {
      if (!item) return document.createElement("hr");
      const button = document.createElement("button");
      button.type = "button";
      button.setAttribute("role", "menuitem");
      button.textContent = item.title;
      button.disabled = Boolean(item.disabled);
      button.addEventListener("click", () => {
        closeContext();
        item.run();
      });
      return button;
    }),
  );
  context.hidden = false;
  context.style.left = `${Math.min(event.clientX, window.innerWidth - context.offsetWidth - 8)}px`;
  context.style.top = `${Math.min(event.clientY, window.innerHeight - context.offsetHeight - 8)}px`;
}

function closeContext() {
  if (context) context.hidden = true;
}

desk?.addEventListener("contextmenu", (event) => {
  if (stacked.matches || !context) return;
  const icon = event.target.closest(".icon");
  const empty = isEmptyDesktop(event.target);
  // Windows, the Dock and the menus keep the browser's own menu
  if (!icon && !empty) return;
  event.preventDefault();

  if (icon) {
    for (const other of $$(".icon")) other.classList.toggle("is-selected", other === icon);
    openContext(event, [
      { title: "Open", run: () => icon.click(), disabled: Boolean(icon.dataset.folder) },
      ...(icon.dataset.folder ? [null, { title: "Move to Trash", run: () => icon.remove() }] : []),
    ]);
    return;
  }
  openContext(event, [
    { title: "New Folder", run: newFolder, disabled: $$(".icon[data-folder]").length >= MAX_FOLDERS },
    null,
    { title: "Clean Up", run: cleanUp },
  ]);
});
document.addEventListener("pointerdown", (event) => {
  if (context && !context.hidden && !context.contains(event.target)) closeContext();
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeContext();
});
window.addEventListener("resize", closeContext);

// Installing: the Download buttons and the installer window. The window is
// the DMG's own, and dragging the app into Applications starts the download.

const isMac = /Mac/i.test(navigator.userAgentData?.platform ?? navigator.platform ?? "") && navigator.maxTouchPoints < 2;
let downloadStarted = 0;

function startDownload({ navigate = true } = {}) {
  openWindow("install");
  const name = latest.version ? `AlwaysOn ${latest.version}` : "AlwaysOn";
  setText(
    $("[data-install-status]"),
    isMac
      ? `Downloading ${name}. Open the DMG from your Downloads folder, then follow the steps below.`
      : `Downloading ${name}. It only runs on a Mac, so move the DMG to one, then follow the steps below.`,
  );
  setText($("[data-install-button]"), "Download Again");
  notify({ title: `Downloading ${name}`, body: "Open the DMG, drag AlwaysOn into Applications, then open it once." });

  const item = $("[data-dock-download]");
  if (item && !reduceMotion) {
    item.classList.toggle("is-bouncing", false);
    void item.offsetWidth;
    item.classList.add("is-bouncing");
  }

  // A link that was clicked downloads by itself. Anything else, such as the
  // drag below or arriving at /download, has to ask for the file.
  const now = performance.now();
  if (navigate && (!downloadStarted || now - downloadStarted > 3000)) location.assign("/download/dmg");
  downloadStarted = now;
}

for (const link of $$("[data-download]")) {
  link.addEventListener("click", () => startDownload({ navigate: false }));
}

const dmgApp = $("[data-dmg-app]");
const dmgTarget = $("[data-dmg-target]");
if (dmgApp && dmgTarget) {
  const overTarget = () => {
    const app = dmgApp.getBoundingClientRect();
    const target = dmgTarget.getBoundingClientRect();
    const x = app.left + app.width / 2;
    const y = app.top + app.height / 2;
    return x > target.left - 12 && x < target.right + 12 && y > target.top - 12 && y < target.bottom + 12;
  };
  dmgApp.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    event.preventDefault();
    dmgApp.classList.add("is-dragging");
    dragFrom(
      dmgApp,
      event,
      (dx, dy) => {
        dmgApp.style.transform = `translate(${dx}px, ${dy}px)`;
        dmgTarget.classList.toggle("is-over", overTarget());
      },
      () => {
        const dropped = overTarget();
        dmgApp.classList.toggle("is-dragging", false);
        dmgTarget.classList.toggle("is-over", false);
        if (!dropped) {
          dmgApp.style.transform = "";
          return;
        }
        // It drops into the folder, then a copy reappears where it started
        dmgApp.classList.add("is-dropped");
        dmgTarget.classList.add("is-filled");
        startDownload();
        setTimeout(() => {
          dmgApp.style.transform = "";
          dmgApp.classList.toggle("is-dropped", false);
          dmgTarget.classList.toggle("is-filled", false);
        }, 700);
      },
    );
  });
}

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

// The cheat code every desktop needs: up up down down left right left right B A

const CHEAT = ["ArrowUp", "ArrowUp", "ArrowDown", "ArrowDown", "ArrowLeft", "ArrowRight", "ArrowLeft", "ArrowRight", "b", "a"];
let cheatAt = 0;
document.addEventListener("keydown", (event) => {
  if (state.locked) return;
  const key = event.key.length === 1 ? event.key.toLowerCase() : event.key;
  cheatAt = key === CHEAT[cheatAt] ? cheatAt + 1 : key === CHEAT[0] ? 1 : 0;
  if (cheatAt < CHEAT.length) return;
  cheatAt = 0;
  document.dispatchEvent(new CustomEvent("alwayson:party"));
  notify({ title: "Cheat code accepted", body: "Status: Available, forever. AlwaysOn gets you there without the cheat." });
});

// Activity: online time per day for the last week. The days before today
// are a believable week; today grows as the demo keeps you online.

const KINDS = [
  ["schedule", "Work hours"],
  ["timer", "Timer"],
  ["until", "Until"],
  ["manual", "Manual"],
  ["command", "Command"],
  ["focus", "Focus"],
];
const weekdayFormat = new Intl.DateTimeFormat(undefined, { weekday: "short" });
const longDayFormat = new Intl.DateTimeFormat(undefined, { weekday: "long" });
// Six days before today, oldest first, in hours. Weekends are quiet.
const pastWeek = (() => {
  const weekday = { schedule: 7.3, until: 0.6 };
  const shapes = [weekday, { schedule: 7.2, focus: 0.6 }, { schedule: 7.4, command: 0.7 }, { schedule: 7.1, until: 0.5 }, weekday];
  return Array.from({ length: 6 }, (_, index) => {
    const day = new Date(state.now - (6 - index) * 86400000);
    const weekend = day.getDay() === 0 || day.getDay() === 6;
    const hours = weekend ? (day.getDay() === 6 ? { timer: 0.6 } : {}) : shapes[index % shapes.length];
    return { day, byKind: Object.fromEntries(Object.entries(hours).map(([kind, h]) => [kind, h * 3600])) };
  });
})();

const activityUi = (() => {
  const root = $("[data-activity]");
  if (!root) return null;
  return {
    root,
    win: root.closest("[data-window]"),
    today: $("[data-act-today]", root),
    week: $("[data-act-week]", root),
    average: $("[data-act-average]", root),
    chart: $("[data-act-chart]", root),
    grid: $("[data-act-grid]", root),
    bars: $("[data-act-bars]", root),
    empty: $("[data-act-empty]", root),
    legend: $("[data-act-legend]", root),
    clear: $("[data-act-clear]", root),
    sheet: $("[data-act-sheet]", root),
  };
})();
let activityKey = "";
let activityShape = "";

function renderActivity() {
  const ui = activityUi;
  if (!ui || ui.win.hidden) return;
  const days = [...pastWeek, { day: new Date(state.now), byKind: state.todayByKind, today: true }];
  const totals = days.map((day) => Object.values(day.byKind).reduce((sum, seconds) => sum + seconds, 0));
  // Redraw once a demo minute, which is every 3 real seconds
  const key = totals.map((total) => Math.floor(total / 60)).join(",");
  if (key === activityKey) return;
  activityKey = key;

  const week = totals.reduce((sum, total) => sum + total, 0);
  const active = totals.filter(Boolean).length;
  setText(ui.today, duration(totals[6]));
  setText(ui.week, duration(week));
  setText(ui.average, duration(active ? week / active : 0));

  ui.chart.hidden = week === 0;
  ui.legend.hidden = week === 0;
  ui.empty.hidden = week > 0;
  if (!week) return;

  // The scale goes up in 5 hour steps, past the longest day
  const top = Math.max(5, Math.ceil((Math.max(...totals) / 3600 + 0.5) / 5) * 5);

  // Rebuild only when the chart's shape changes, so a bar being pointed at or
  // focused keeps its place while today's numbers tick up
  const present = KINDS.filter(([kind]) => days.some((day) => day.byKind[kind] > 0));
  const partsOf = (day) => present.filter(([kind]) => day.byKind[kind] > 0);
  const shape = `${top}|${days.map((day) => partsOf(day).map(([kind]) => kind).join("+")).join("/")}`;
  if (shape !== activityShape) {
    activityShape = shape;
    ui.grid.replaceChildren(
      ...Array.from({ length: top / 5 + 1 }, (_, index) => {
        const line = document.createElement("i");
        line.style.bottom = `${(index * 5 * 100) / top}%`;
        line.dataset.h = `${index * 5}h`;
        return line;
      }),
    );
    ui.bars.replaceChildren(
      ...days.map((day) => {
        const column = document.createElement("div");
        column.className = `act-day${day.today ? " is-today" : ""}`;
        column.tabIndex = 0;
        for (const [kind] of partsOf(day)) {
          const segment = document.createElement("b");
          segment.style.setProperty("--tint", `var(--k-${kind})`);
          column.append(segment);
        }
        const label = document.createElement("span");
        label.textContent = weekdayFormat.format(day.day);
        const tip = document.createElement("div");
        tip.className = "act-tip";
        tip.setAttribute("aria-hidden", "true");
        tip.append(document.createElement("strong"));
        for (const [kind, title] of partsOf(day)) {
          const row = document.createElement("span");
          row.style.setProperty("--tint", `var(--k-${kind})`);
          row.innerHTML = "<em></em><i></i>";
          row.firstChild.textContent = title;
          tip.append(row);
        }
        column.append(label, tip);
        return column;
      }),
    );
    ui.legend.replaceChildren(
      ...present.map(([kind, title]) => {
        const item = document.createElement("li");
        item.style.setProperty("--tint", `var(--k-${kind})`);
        item.textContent = title;
        return item;
      }),
    );
  }

  [...ui.bars.children].forEach((column, index) => {
    const day = days[index];
    const parts = partsOf(day);
    const name = day.today ? "Today" : longDayFormat.format(day.day);
    column.setAttribute(
      "aria-label",
      `${name}: ${duration(totals[index])}${parts.length ? `, ${parts.map(([kind, title]) => `${title} ${duration(day.byKind[kind])}`).join(", ")}` : ""}`,
    );
    $$("b", column).forEach((segment, part) => {
      segment.style.height = `${(day.byKind[parts[part][0]] / 3600 / top) * 100}%`;
    });
    const tip = $(".act-tip", column);
    tip.style.setProperty("--top", `${(totals[index] / 3600 / top) * 100}%`);
    setText($("strong", tip), `${name} · ${totals[index] ? duration(totals[index]) : "No sessions"}`);
    $$("i", tip).forEach((cell, part) => setText(cell, duration(day.byKind[parts[part][0]])));
  });
}

if (activityUi) {
  const { clear, sheet } = activityUi;
  const closeSheet = () => {
    sheet.hidden = true;
    clear.focus({ preventScroll: true });
  };
  clear.addEventListener("click", () => {
    sheet.hidden = false;
    $("[data-act-cancel]", sheet).focus({ preventScroll: true });
  });
  $("[data-act-cancel]", sheet).addEventListener("click", closeSheet);
  $("[data-act-confirm]", sheet).addEventListener("click", () => {
    for (const day of pastWeek) day.byKind = {};
    state.todayByKind = {};
    activityKey = "";
    activityShape = "";
    closeSheet();
    renderActivity();
  });
  sheet.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    event.stopPropagation();
    closeSheet();
  });
}

// Start

render();
if (document.readyState === "complete") route();
else window.addEventListener("load", route, { once: true });
window.addEventListener("hashchange", route);
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
