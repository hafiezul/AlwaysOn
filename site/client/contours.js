// The hero's background: contour lines of a slowly drifting field, traced
// with marching squares on a 2D canvas. The pointer raises a soft hill, and
// each pulse sends a ring outward from the key that the lines ripple over.

const STEP = 18; // grid spacing in CSS pixels
const LEVELS = [-0.9, -0.55, -0.2, 0.15, 0.5, 0.85];
const ACCENT_LEVEL = 3;
const RING_SPEED = 520; // px per second
const RING_LIFE = 2.4; // seconds

export function startContours(canvas, { reduce = false } = {}) {
  const ctx = canvas.getContext("2d");
  let width = 0;
  let height = 0;
  let cols = 0;
  let rows = 0;
  let values = new Float32Array(0);
  const rings = [];
  const pointer = { x: -9999, y: -9999, tx: -9999, ty: -9999 };
  let visible = true;
  let lastDraw = 0;

  function resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    width = canvas.clientWidth;
    height = canvas.clientHeight;
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    cols = Math.ceil(width / STEP) + 1;
    rows = Math.ceil(height / STEP) + 1;
    values = new Float32Array(cols * rows);
    draw(performance.now());
  }

  window.addEventListener(
    "pointermove",
    (event) => {
      const r = canvas.getBoundingClientRect();
      pointer.tx = event.clientX - r.left;
      pointer.ty = event.clientY - r.top;
    },
    { passive: true },
  );

  function field(time) {
    const t = time / 1000;
    const scale = Math.max(width, height) / 3.2;
    const now = performance.now();
    pointer.x += (pointer.tx - pointer.x) * 0.08;
    pointer.y += (pointer.ty - pointer.y) * 0.08;

    for (let ring = rings.length - 1; ring >= 0; ring -= 1) {
      if ((now - rings[ring].born) / 1000 > RING_LIFE) rings.splice(ring, 1);
    }

    for (let j = 0; j < rows; j += 1) {
      const y = j * STEP;
      const v = y / scale;
      for (let i = 0; i < cols; i += 1) {
        const x = i * STEP;
        const u = x / scale;
        let f =
          Math.sin(u * 1.35 + Math.sin(v * 0.9 + t * 0.12) * 1.7) * Math.cos(v * 1.15 - Math.sin(u * 0.75 - t * 0.09) * 1.5) +
          0.38 * Math.sin((u + v) * 2.3 + t * 0.17) +
          0.22 * Math.cos(u * 3.1 - v * 1.7 - t * 0.21);

        const px = x - pointer.x;
        const py = y - pointer.y;
        f += 0.75 * Math.exp(-(px * px + py * py) / (2 * 140 * 140));

        for (const ring of rings) {
          const age = (now - ring.born) / 1000;
          const dx = x - ring.x;
          const dy = y - ring.y;
          const d = Math.sqrt(dx * dx + dy * dy) - age * RING_SPEED;
          f += ring.strength * (1 - age / RING_LIFE) * Math.exp(-(d * d) / (2 * 46 * 46));
        }
        values[j * cols + i] = f;
      }
    }
  }

  // Marching squares: one path per level
  function trace(level) {
    ctx.beginPath();
    for (let j = 0; j < rows - 1; j += 1) {
      for (let i = 0; i < cols - 1; i += 1) {
        const a = values[j * cols + i];
        const b = values[j * cols + i + 1];
        const c = values[(j + 1) * cols + i + 1];
        const d = values[(j + 1) * cols + i];
        const index = (a > level ? 8 : 0) | (b > level ? 4 : 0) | (c > level ? 2 : 0) | (d > level ? 1 : 0);
        if (index === 0 || index === 15) continue;

        const x = i * STEP;
        const y = j * STEP;
        const top = [x + STEP * lerp(a, b, level), y];
        const right = [x + STEP, y + STEP * lerp(b, c, level)];
        const bottom = [x + STEP * lerp(d, c, level), y + STEP];
        const left = [x, y + STEP * lerp(a, d, level)];

        switch (index) {
          case 1: case 14: segment(left, bottom); break;
          case 2: case 13: segment(bottom, right); break;
          case 3: case 12: segment(left, right); break;
          case 4: case 11: segment(top, right); break;
          case 6: case 9: segment(top, bottom); break;
          case 7: case 8: segment(left, top); break;
          case 5: segment(left, top); segment(bottom, right); break;
          case 10: segment(top, right); segment(left, bottom); break;
        }
      }
    }
  }

  function segment(p, q) {
    ctx.moveTo(p[0], p[1]);
    ctx.lineTo(q[0], q[1]);
  }

  function draw(now) {
    if (!width) return;
    field(now);
    ctx.clearRect(0, 0, width, height);
    ctx.lineCap = "round";
    LEVELS.forEach((level, index) => {
      trace(level);
      if (index === ACCENT_LEVEL) {
        ctx.strokeStyle = "rgba(31, 184, 85, 0.55)";
        ctx.lineWidth = 1.6;
      } else {
        ctx.strokeStyle = "rgba(16, 18, 14, 0.13)";
        ctx.lineWidth = 1.1;
      }
      ctx.stroke();
    });
  }

  function loop(now) {
    if (!visible) return;
    // ~30 fps is plenty for lines this slow, and halves the work
    if (now - lastDraw > 32) {
      lastDraw = now;
      draw(now);
    }
    requestAnimationFrame(loop);
  }

  resize();
  new ResizeObserver(resize).observe(canvas);
  new IntersectionObserver(([entry]) => {
    const was = visible;
    visible = entry.isIntersecting;
    if (visible && !was && !reduce) requestAnimationFrame(loop);
  }).observe(canvas);
  if (!reduce) requestAnimationFrame(loop);

  return {
    pulse(clientX, clientY, strength = 0.9) {
      if (reduce) return;
      const r = canvas.getBoundingClientRect();
      rings.push({ x: clientX - r.left, y: clientY - r.top, born: performance.now(), strength });
    },
  };
}

function lerp(from, to, level) {
  const span = to - from;
  return span === 0 ? 0.5 : (level - from) / span;
}
