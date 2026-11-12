// The hero's 3D avatar: a profile picture with a status badge, the way Teams
// and Slack show presence. The badge fades from green toward the Away yellow
// as the demo countdown runs out, and each input turns it green again with a
// ring. The avatar leans toward the pointer and can be spun by dragging.
// Clicking it sends an input. Returns null when WebGL isn't available, and the
// page shows a flat CSS avatar instead.

import {
  CanvasTexture,
  Color,
  Group,
  LatheGeometry,
  Mesh,
  MeshBasicMaterial,
  MeshPhysicalMaterial,
  NeutralToneMapping,
  PerspectiveCamera,
  PlaneGeometry,
  PMREMGenerator,
  Raycaster,
  Scene,
  SphereGeometry,
  SRGBColorSpace,
  TorusGeometry,
  Vector2,
  Vector3,
  WebGLRenderer,
} from "three";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import gsap from "gsap";

const RADIUS = 1.7;
const DEPTH = 0.36;
const BADGE = { x: RADIUS * 0.72, y: -RADIUS * 0.72, r: 0.42 };
const BASE_TILT = { x: 0.14, y: -0.42, z: 0.04 };
const GREEN = new Color("#3cf07a");
const YELLOW = new Color("#ffc531");

export function startPresence(stage, { onPress = () => {}, reduce = false } = {}) {
  let renderer;
  try {
    renderer = new WebGLRenderer({ antialias: true, alpha: true, powerPreference: "high-performance" });
  } catch {
    return null;
  }
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.outputColorSpace = SRGBColorSpace;
  renderer.toneMapping = NeutralToneMapping;
  renderer.toneMappingExposure = 0.95;
  renderer.domElement.setAttribute("aria-hidden", "true");
  stage.append(renderer.domElement);

  const scene = new Scene();
  const pmrem = new PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.03).texture;
  pmrem.dispose();

  const camera = new PerspectiveCamera(30, 1, 0.1, 100);
  camera.position.set(0, 0, 11);

  // rig: pointer lean, drag spin, scroll. avatar: the part that bounces
  const rig = new Group();
  const avatar = new Group();
  rig.add(avatar);
  scene.add(rig);

  // The picture: a bevelled puck facing the camera
  const puck = new Mesh(
    puckGeometry(),
    new MeshPhysicalMaterial({ color: "#1b1f19", roughness: 0.45, clearcoat: 0.9, clearcoatRoughness: 0.2, envMapIntensity: 0.7 }),
  );
  puck.rotation.x = Math.PI / 2;
  avatar.add(puck);

  // The default person glyph, raised off the face of the puck
  const glyphMaterial = new MeshPhysicalMaterial({ color: "#e8e9de", roughness: 0.5, clearcoat: 0.4, envMapIntensity: 0.6 });
  const head = new Mesh(new SphereGeometry(0.5, 64, 32), glyphMaterial);
  head.scale.set(1, 1, 0.42);
  head.position.set(0, 0.36, DEPTH / 2);
  avatar.add(head);
  const shoulders = new Mesh(new SphereGeometry(1, 64, 32, 0, Math.PI * 2, 0, Math.PI / 2), glyphMaterial);
  shoulders.scale.set(0.98, 0.66, 0.36);
  shoulders.position.set(0, -1.02, DEPTH / 2);
  avatar.add(shoulders);

  // The status badge, with a paper-coloured ring cut around it like the apps draw it
  const badgeGroup = new Group();
  badgeGroup.position.set(BADGE.x, BADGE.y, DEPTH / 2 + 0.06);
  avatar.add(badgeGroup);
  const cutout = new Mesh(
    new TorusGeometry(BADGE.r + 0.06, 0.11, 24, 96),
    new MeshPhysicalMaterial({ color: "#f3f2ec", roughness: 0.35, clearcoat: 0.6 }),
  );
  badgeGroup.add(cutout);
  const badgeMaterial = new MeshPhysicalMaterial({
    color: GREEN.clone(),
    emissive: GREEN.clone(),
    emissiveIntensity: 0.28,
    roughness: 0.3,
    clearcoat: 1,
    clearcoatRoughness: 0.12,
    envMapIntensity: 0.6,
  });
  const badge = new Mesh(new SphereGeometry(BADGE.r, 64, 32), badgeMaterial);
  badge.scale.z = 0.72;
  badgeGroup.add(badge);

  // Rings that spread from the badge on each input
  const rings = Array.from({ length: 3 }, () => {
    const ring = new Mesh(
      new TorusGeometry(BADGE.r + 0.1, 0.022, 12, 96),
      new MeshBasicMaterial({ color: GREEN, transparent: true, opacity: 0, depthWrite: false }),
    );
    badgeGroup.add(ring);
    return ring;
  });
  let nextRing = 0;

  // A soft shadow behind and below, so it floats over the paper
  const shadow = new Mesh(
    new PlaneGeometry(5.4, 5.4),
    new MeshBasicMaterial({ map: shadowTexture(), transparent: true, depthWrite: false, opacity: 0.42 }),
  );
  shadow.position.set(0.35, -0.55, -0.6);
  rig.add(shadow);

  // State
  const pointer = new Vector2(0, 0);
  const ndc = new Vector2();
  const lean = { x: 0, y: 0 };
  const drag = { active: false, lastX: 0, spin: 0, velocity: 0 };
  const pop = { scale: 1 };
  let idle = 0; // 0 when an input was just sent, 1 when the next one is due
  let scrollProgress = 0;
  let fit = 1;
  let lift = 0;
  let visible = true;
  let hot = false;
  const raycaster = new Raycaster();
  const targets = [puck, head, shoulders, badge, cutout];

  function resize() {
    const { clientWidth: w, clientHeight: h } = stage;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    const viewH = 2 * camera.position.z * Math.tan((camera.fov * Math.PI) / 360);
    const viewW = viewH * camera.aspect;
    const span = RADIUS * 2 + 0.4;
    fit = Math.min((viewW * (w < 700 ? 0.62 : 0.3)) / span, (viewH * 0.46) / span);
    lift = viewH * (w < 700 ? 0.13 : 0.11);
  }
  resize();
  new ResizeObserver(resize).observe(stage);

  // Pointer: lean toward it, show a hand over the avatar, drag to spin
  const canvas = renderer.domElement;
  function updateNDC(event) {
    const r = canvas.getBoundingClientRect();
    ndc.set(((event.clientX - r.left) / r.width) * 2 - 1, -((event.clientY - r.top) / r.height) * 2 + 1);
    pointer.copy(ndc);
  }
  function overAvatar() {
    raycaster.setFromCamera(ndc, camera);
    return raycaster.intersectObjects(targets, false).length > 0;
  }
  window.addEventListener(
    "pointermove",
    (event) => {
      updateNDC(event);
      if (drag.active) {
        const dx = event.clientX - drag.lastX;
        drag.lastX = event.clientX;
        if (Math.abs(dx) > 2) drag.moved = true;
        drag.velocity = dx * 0.008;
        drag.spin += drag.velocity;
        return;
      }
      if (event.target === canvas) {
        const isHot = overAvatar();
        if (isHot !== hot) stage.classList.toggle("is-hot", (hot = isHot));
      }
    },
    { passive: true },
  );
  canvas.addEventListener("pointerdown", (event) => {
    updateNDC(event);
    drag.active = true;
    drag.moved = false;
    drag.startedOnAvatar = overAvatar();
    drag.lastX = event.clientX;
    canvas.setPointerCapture(event.pointerId);
  });
  canvas.addEventListener("pointerup", () => {
    // A click on the avatar sends an input; a drag only spins it
    if (drag.active && drag.startedOnAvatar && !drag.moved) press(true);
    drag.active = false;
  });
  canvas.addEventListener("pointercancel", () => (drag.active = false));

  // Send an input: the badge turns green, a ring spreads, the avatar bounces
  let popTween = null;
  function press(manual = false) {
    idle = 0;
    onPress({ manual, origin: screenPosition() });
    if (reduce) return;
    popTween?.kill();
    popTween = gsap
      .timeline()
      .to(pop, { scale: 1.05, duration: 0.12, ease: "power2.out" })
      .to(pop, { scale: 1, duration: 1.1, ease: "elastic.out(1, 0.35)" });
    gsap.fromTo(badge.scale, { x: 0.7, y: 0.7 }, { x: 1, y: 1, duration: 0.9, ease: "elastic.out(1, 0.4)" });
    const ring = rings[nextRing];
    nextRing = (nextRing + 1) % rings.length;
    gsap.killTweensOf([ring.scale, ring.material]);
    gsap.fromTo(ring.scale, { x: 1, y: 1, z: 1 }, { x: 4.2, y: 4.2, z: 1, duration: 1.6, ease: "expo.out" });
    gsap.fromTo(ring.material, { opacity: 0.85 }, { opacity: 0, duration: 1.6, ease: "power2.out" });
  }

  // Where the badge sits on screen, for the contour rings
  const projected = new Vector3();
  function screenPosition() {
    badge.getWorldPosition(projected);
    projected.project(camera);
    const r = canvas.getBoundingClientRect();
    return { x: r.left + ((projected.x + 1) / 2) * r.width, y: r.top + ((1 - projected.y) / 2) * r.height };
  }

  // Loop
  let last = performance.now();
  const intro = { scale: reduce ? 1 : 0.001, spin: reduce ? 0 : -Math.PI * 1.2 };
  const tint = new Color();
  function frame(now) {
    const dt = Math.min((now - last) / 1000, 0.05);
    last = now;
    const t = now / 1000;

    const targetX = BASE_TILT.x - pointer.y * 0.25 + scrollProgress * 0.6;
    const targetY = BASE_TILT.y + pointer.x * 0.5;
    const ease = 1 - Math.pow(0.002, dt);
    lean.x += (targetX - lean.x) * ease;
    lean.y += (targetY - lean.y) * ease;

    if (!drag.active) {
      drag.velocity *= Math.pow(0.04, dt);
      drag.spin += drag.velocity;
      drag.spin += (0 - drag.spin) * (1 - Math.pow(0.25, dt)); // drift back home
    }

    // Green while recent, turning toward Away in the last part of the wait
    const away = smoothstep(0.55, 1, idle);
    tint.copy(GREEN).lerp(YELLOW, away * 0.8); // close to Away, never all the way
    badgeMaterial.color.copy(tint);
    badgeMaterial.emissive.copy(tint);

    const float = reduce ? 0 : Math.sin(t * 1.1) * 0.08;
    rig.rotation.set(lean.x, lean.y + drag.spin + intro.spin, BASE_TILT.z + (reduce ? 0 : Math.sin(t * 0.7) * 0.03));
    rig.position.y = lift + float + scrollProgress * 2.4;
    rig.scale.setScalar(fit * intro.scale * pop.scale * (1 - scrollProgress * 0.25));

    renderer.render(scene, camera);
    if (visible) requestAnimationFrame(frame);
  }

  new IntersectionObserver(([entry]) => {
    const was = visible;
    visible = entry.isIntersecting;
    if (visible && !was) {
      last = performance.now();
      requestAnimationFrame(frame);
    }
  }).observe(stage);
  requestAnimationFrame(frame);

  return {
    press,
    intro() {
      return gsap.to(intro, { scale: 1, spin: 0, duration: reduce ? 0 : 1.8, ease: "expo.out" });
    },
    setIdle(progress) {
      idle = Math.min(Math.max(progress, 0), 1);
    },
    setScroll(progress) {
      scrollProgress = progress;
    },
    screenPosition,
  };
}

// A flat disc with rounded edges, turned on a lathe around the Y axis
function puckGeometry() {
  const points = [new Vector2(0, -DEPTH / 2)];
  const bevel = DEPTH / 2;
  const inner = RADIUS - bevel;
  for (let step = 0; step <= 16; step += 1) {
    const angle = -Math.PI / 2 + (step / 16) * Math.PI;
    points.push(new Vector2(inner + Math.cos(angle) * bevel, Math.sin(angle) * bevel));
  }
  points.push(new Vector2(0, DEPTH / 2));
  return new LatheGeometry(points, 128);
}

function shadowTexture() {
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 256;
  const ctx = canvas.getContext("2d");
  const gradient = ctx.createRadialGradient(128, 128, 10, 128, 128, 128);
  gradient.addColorStop(0, "rgba(16,18,14,0.7)");
  gradient.addColorStop(0.5, "rgba(16,18,14,0.25)");
  gradient.addColorStop(1, "rgba(16,18,14,0)");
  ctx.fillStyle = gradient;
  ctx.fillRect(0, 0, 256, 256);
  return new CanvasTexture(canvas);
}

function smoothstep(edge0, edge1, x) {
  const t = Math.min(Math.max((x - edge0) / (edge1 - edge0), 0), 1);
  return t * t * (3 - 2 * t);
}
