// The desktop wallpaper: a 3D grid of graphite pixel blocks. Blocks
// rise and brighten around the pointer. Each time the demo posts an input, a
// green ripple spreads from the headline's status dot. When your demo status
// goes Away, the field warms toward the Away yellow.

import {
  AmbientLight,
  BoxGeometry,
  Color,
  DirectionalLight,
  DynamicDrawUsage,
  InstancedMesh,
  MeshLambertMaterial,
  Object3D,
  OrthographicCamera,
  Plane,
  Raycaster,
  Scene,
  Vector2,
  Vector3,
  WebGLRenderer,
} from "three";

const TILT = 0.42; // camera tilt in radians, so raised blocks show their sides
const BASE_HEIGHT = 0.12;
const BUMP_RADIUS = 5;
const BUMP_HEIGHT = 2.2;
const RIPPLE_SPEED = 18; // blocks per second
const RIPPLE_LIFE = 2.6; // seconds

const COLORS = {
  block: new Color("#09090a"),
  lift: new Color("#6e6e76"),
  ripple: new Color("#30d158"),
  away: new Color("#3a2608"),
  gap: new Color("#000000"),
};

export function start({ demo, hero }) {
  const canvas = document.createElement("canvas");
  canvas.className = "field-canvas";
  canvas.setAttribute("aria-hidden", "true");
  hero.prepend(canvas);

  const renderer = new WebGLRenderer({ canvas, antialias: true, powerPreference: "low-power" });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setClearColor(COLORS.gap);

  const scene = new Scene();
  scene.add(new AmbientLight(0xffffff, 0.45 * Math.PI));
  const sun = new DirectionalLight(0xffffff, 0.75 * Math.PI);
  sun.position.set(-0.3, -0.6, 1);
  scene.add(sun);

  const camera = new OrthographicCamera(-1, 1, 1, -1, 0.1, 400);
  camera.position.set(0, -100 * Math.sin(TILT), 100 * Math.cos(TILT));
  camera.lookAt(0, 0, 0);
  camera.updateMatrixWorld();

  const geometry = new BoxGeometry(0.88, 0.88, 1);
  geometry.translate(0, 0, 0.5);
  const material = new MeshLambertMaterial();

  let mesh = null;
  let cols = 0;
  let rows = 0;
  let heights = new Float32Array(0);

  const raycaster = new Raycaster();
  const ground = new Plane(new Vector3(0, 0, 1), 0);
  const hit = new Vector3();
  const ndc = new Vector2();

  function toWorld(x, y) {
    const rect = canvas.getBoundingClientRect();
    if (!rect.width || !rect.height) return null;
    ndc.set(((x - rect.left) / rect.width) * 2 - 1, -((y - rect.top) / rect.height) * 2 + 1);
    raycaster.setFromCamera(ndc, camera);
    return raycaster.ray.intersectPlane(ground, hit) ? hit.clone() : null;
  }

  const cellX = (i) => i - cols / 2 + 0.5;
  const cellY = (j) => rows / 2 - j - 0.5;

  function layout() {
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;
    if (!width || !height) return;
    const cellPx = width < 560 ? 18 : width < 1000 ? 22 : 28;

    renderer.setSize(width, height, false);
    camera.left = -width / cellPx / 2;
    camera.right = width / cellPx / 2;
    camera.top = height / cellPx / 2;
    camera.bottom = -height / cellPx / 2;
    camera.updateProjectionMatrix();
    camera.updateMatrixWorld();

    const nextCols = Math.ceil(width / cellPx) + 6;
    const nextRows = Math.ceil(height / (cellPx * Math.cos(TILT))) + 10;
    if (nextCols === cols && nextRows === rows) return;

    cols = nextCols;
    rows = nextRows;
    if (mesh) {
      scene.remove(mesh);
      mesh.dispose();
    }
    mesh = new InstancedMesh(geometry, material, cols * rows);
    mesh.instanceMatrix.setUsage(DynamicDrawUsage);
    mesh.setColorAt(0, COLORS.block);
    mesh.instanceColor.setUsage(DynamicDrawUsage);
    scene.add(mesh);
    heights = new Float32Array(cols * rows).fill(BASE_HEIGHT);
  }

  // Pointer
  let pointer = null;
  window.addEventListener(
    "pointermove",
    (event) => {
      if (event.pointerType === "touch") return;
      const rect = canvas.getBoundingClientRect();
      const inside =
        event.clientX >= rect.left && event.clientX <= rect.right && event.clientY >= rect.top && event.clientY <= rect.bottom;
      pointer = inside ? toWorld(event.clientX, event.clientY) : null;
    },
    { passive: true },
  );
  document.addEventListener("pointerleave", () => (pointer = null));

  // Ripples start at the headline's status dot, the period after "Stay green"
  const ripples = [];
  demo.subscribe((type) => {
    if (type !== "nudge") return;
    // With the Read Me window closed, ripples start at the menu bar icon
    const dot = hero.querySelector("[data-headline-dot]");
    const view = dot?.closest(".window-body")?.getBoundingClientRect();
    let rect = dot?.getBoundingClientRect();
    const visible = rect && rect.width && (!view || (rect.top >= view.top && rect.bottom <= view.bottom));
    if (!visible) rect = document.querySelector("[data-menu-toggle]").getBoundingClientRect();
    const origin = toWorld(rect.left + rect.width / 2, rect.top + rect.height / 2);
    if (!origin) return;
    ripples.push({ x: origin.x, y: origin.y, t0: performance.now() });
    if (ripples.length > 4) ripples.shift();
  });

  // Frame loop
  const dummy = new Object3D();
  const color = new Color();
  const base = new Color();
  let awayMix = demo.status === "away" ? 1 : 0;

  function frame(now) {
    if (!mesh) return;
    awayMix += ((demo.status === "away" ? 1 : 0) - awayMix) * 0.04;
    base.copy(COLORS.block).lerp(COLORS.away, awayMix);

    while (ripples.length && (now - ripples[0].t0) / 1000 > RIPPLE_LIFE) ripples.shift();

    let index = 0;
    for (let j = 0; j < rows; j += 1) {
      const y = cellY(j);
      for (let i = 0; i < cols; i += 1, index += 1) {
        const x = cellX(i);
        let target = BASE_HEIGHT;
        let lift = 0;
        let wave = 0;

        if (pointer) {
          const d = Math.hypot(x - pointer.x, y - pointer.y);
          if (d < BUMP_RADIUS) {
            lift = (1 - d / BUMP_RADIUS) ** 2;
            target += lift * BUMP_HEIGHT;
          }
        }

        for (const ripple of ripples) {
          const age = (now - ripple.t0) / 1000;
          const d = Math.hypot(x - ripple.x, y - ripple.y);
          const band = Math.exp(-((d - age * RIPPLE_SPEED) ** 2) / 3) * (1 - age / RIPPLE_LIFE);
          target += band * 1.1;
          wave = Math.max(wave, band);
        }

        color.copy(base).lerp(COLORS.lift, lift * 0.7).lerp(COLORS.ripple, Math.min(wave, 1) * 0.8);

        heights[index] += (target - heights[index]) * 0.14;
        dummy.position.set(x, y, 0);
        dummy.scale.set(1, 1, heights[index]);
        dummy.updateMatrix();
        mesh.setMatrixAt(index, dummy.matrix);
        mesh.setColorAt(index, color);
      }
    }

    mesh.instanceMatrix.needsUpdate = true;
    mesh.instanceColor.needsUpdate = true;
    renderer.render(scene, camera);
  }

  // Run only while the hero is on screen and the tab is visible
  let visible = true;
  let raf = 0;
  const loop = (now) => {
    frame(now);
    raf = requestAnimationFrame(loop);
  };
  const run = () => {
    if (!raf && visible && !document.hidden) raf = requestAnimationFrame(loop);
  };
  const pause = () => {
    cancelAnimationFrame(raf);
    raf = 0;
  };

  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    visible ? run() : pause();
  }).observe(canvas);
  document.addEventListener("visibilitychange", () => (document.hidden ? pause() : run()));

  let queued = false;
  window.addEventListener(
    "resize",
    () => {
      if (queued) return;
      queued = true;
      requestAnimationFrame(() => {
        queued = false;
        layout();
      });
    },
    { passive: true },
  );

  layout();
  frame(performance.now());
  hero.classList.add("is-3d");
  run();
}
