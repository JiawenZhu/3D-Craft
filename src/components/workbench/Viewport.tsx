import React, { Suspense, forwardRef, useImperativeHandle, useMemo, useRef } from 'react';
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import {
  Bounds, Center, ContactShadows, Environment, GizmoHelper, GizmoViewport, Grid, Html,
  Lightformer, OrbitControls, useGLTF,
} from '@react-three/drei';
import * as THREE from 'three';
import type { Asset, LightTrim, StudioLight, ViewportShading } from '../../types';
import { absolute } from '../../lib/api';

/* ---------------------------------------------------------------- lighting */
/*
 * Generated meshes carry albedo baked from the source image — they are already
 * "lit" art. Dramatic key/rim lighting fights that and crushes them to
 * silhouettes, which is why the first pass rendered near-black. What they want
 * is bright, even image-based lighting, the way the reference viewer does it.
 *
 * The environment is built in-scene from Lightformer panels rather than a
 * downloaded HDRI, so it stays local and offline.
 */
interface Rig {
  /** IBL contribution — the main source of light. */
  env: number;
  ambient: number;
  key: number;
  keyColor: string;
  rim: number;
  rimColor: string;
  /** Renderer exposure; the lever that actually fixes "too dark". */
  exposure: number;
  bg: string;
  /** Colour of the big softbox above the subject. */
  softbox: string;
  floor: string;
}

const RIGS: Record<StudioLight, Rig> = {
  studio: { env: 1.8, ambient: 1.35, key: 1.6, keyColor: '#ffffff', rim: 0.8, rimColor: '#dce4ff',
            exposure: 1.6, bg: '#1e1f25', softbox: '#ffffff', floor: '#b6bcc7' },
  rim:    { env: 0.95, ambient: 0.7, key: 1.1, keyColor: '#ffd9bd', rim: 2.6, rimColor: '#8fd8ff',
            exposure: 1.45, bg: '#121319', softbox: '#e8f0ff', floor: '#6b7381' },
  sunset: { env: 1.35, ambient: 0.95, key: 2.0, keyColor: '#ffb877', rim: 1.2, rimColor: '#a887ff',
            exposure: 1.5, bg: '#201815', softbox: '#ffd2a1', floor: '#9c7d68' },
  night:  { env: 1.0, ambient: 0.75, key: 1.0, keyColor: '#9fb4ff', rim: 2.0, rimColor: '#d8a1f1',
            exposure: 1.4, bg: '#0f1017', softbox: '#b9c7ff', floor: '#6a7086' },
  flat:   { env: 2.2, ambient: 2.0, key: 0.6, keyColor: '#ffffff', rim: 0.4, rimColor: '#ffffff',
            exposure: 1.5, bg: '#212228', softbox: '#ffffff', floor: '#d4d8de' },
};

export interface ViewportHandle {
  zoom: (factor: number) => void;
  fit: () => void;
  screenshot: (name: string) => void;
}

/** Bridges the toolbar to the camera without lifting r3f state out of the Canvas. */
const CameraRig = forwardRef<ViewportHandle, {}>((_, ref) => {
  const { camera, controls, gl, scene } = useThree() as any;

  useImperativeHandle(ref, () => ({
    zoom: (factor: number) => {
      if (!controls) return;
      const dir = camera.position.clone().sub(controls.target);
      const len = dir.length() * factor;
      if (len < 0.5 || len > 50) return;
      camera.position.copy(controls.target.clone().add(dir.setLength(len)));
      controls.update();
    },
    fit: () => {
      if (!controls) return;
      controls.target.set(0, 0, 0);
      camera.position.set(2.6, 1.7, 3.4);
      controls.update();
    },
    screenshot: (name: string) => {
      // the drawing buffer is cleared after each frame, so render on demand
      gl.render(scene, camera);
      const link = document.createElement('a');
      link.download = `${name}.png`;
      link.href = gl.domElement.toDataURL('image/png');
      link.click();
    },
  }), [camera, controls, gl, scene]);

  return null;
});
CameraRig.displayName = 'CameraRig';

/** Exposure has to follow the preset, so it cannot live in onCreated. */
const Exposure: React.FC<{ value: number }> = ({ value }) => {
  const gl = useThree((s) => s.gl);
  React.useEffect(() => { gl.toneMappingExposure = value; }, [gl, value]);
  return null;
};

/** A four-panel softbox rig baked into an env map — no CDN, no HDRI download. */
const StudioEnvironment: React.FC<{ rig: Rig }> = ({ rig }) => (
  <Environment resolution={256} frames={1}>
    {/* broad top light: the one doing most of the work */}
    <Lightformer form="rect" intensity={rig.env * 3.2} color={rig.softbox}
                 position={[0, 5, 0]} rotation={[Math.PI / 2, 0, 0]} scale={[12, 12, 1]} />
    {/* front fill so faces pointed at camera are never black */}
    <Lightformer form="rect" intensity={rig.env * 1.7} color={rig.softbox}
                 position={[0, 1, 6]} rotation={[0, 0, 0]} scale={[10, 8, 1]} />
    {/* side wraps */}
    <Lightformer form="rect" intensity={rig.env * 1.3} color={rig.softbox}
                 position={[-6, 1.5, 1]} rotation={[0, Math.PI / 2, 0]} scale={[8, 8, 1]} />
    <Lightformer form="rect" intensity={rig.env * 1.3} color={rig.rimColor}
                 position={[6, 1.5, 1]} rotation={[0, -Math.PI / 2, 0]} scale={[8, 8, 1]} />
    {/* bounce off the floor, so undersides read instead of going to black */}
    <Lightformer form="rect" intensity={rig.env * 0.9} color={rig.floor}
                 position={[0, -4, 0]} rotation={[-Math.PI / 2, 0, 0]} scale={[12, 12, 1]} />
  </Environment>
);

/* -------------------------------------------------- procedural stand-in mesh */
const Placeholder: React.FC<{ asset: Asset }> = ({ asset }) => {
  const parts = useMemo(() => {
    switch (asset.seedShape) {
      case 'figure': return [
        { g: 'capsule' as const, a: [0.34, 0.9, 8, 16], p: [0, 0.55, 0] },
        { g: 'sphere' as const, a: [0.3, 32, 32], p: [0, 1.32, 0] },
        { g: 'capsule' as const, a: [0.11, 0.62, 6, 12], p: [-0.46, 0.62, 0], r: [0, 0, 0.35] },
        { g: 'capsule' as const, a: [0.11, 0.62, 6, 12], p: [0.46, 0.62, 0], r: [0, 0, -0.35] },
        { g: 'capsule' as const, a: [0.14, 0.6, 6, 12], p: [-0.18, -0.36, 0] },
        { g: 'capsule' as const, a: [0.14, 0.6, 6, 12], p: [0.18, -0.36, 0] },
      ];
      case 'mech': return [
        { g: 'box' as const, a: [1.15, 0.95, 0.8], p: [0, 0.62, 0] },
        { g: 'box' as const, a: [0.8, 0.5, 0.62], p: [0, 1.36, 0.02] },
        { g: 'box' as const, a: [0.34, 1.0, 0.42], p: [-0.78, 0.55, 0] },
        { g: 'box' as const, a: [0.34, 1.0, 0.42], p: [0.78, 0.55, 0] },
        { g: 'cyl' as const, a: [0.2, 0.24, 1.1, 12], p: [-0.32, -0.44, 0] },
        { g: 'cyl' as const, a: [0.2, 0.24, 1.1, 12], p: [0.32, -0.44, 0] },
      ];
      case 'creature': return [
        { g: 'sphere' as const, a: [0.78, 32, 32], p: [0, 0.42, 0], s: [1.25, 0.92, 1] },
        { g: 'sphere' as const, a: [0.42, 24, 24], p: [0, 1.14, 0.25] },
        { g: 'cone' as const, a: [0.16, 0.42, 12], p: [-0.26, 1.5, 0.16] },
        { g: 'cone' as const, a: [0.16, 0.42, 12], p: [0.26, 1.5, 0.16] },
        { g: 'cyl' as const, a: [0.12, 0.16, 0.7, 10], p: [-0.4, -0.34, 0.28] },
        { g: 'cyl' as const, a: [0.12, 0.16, 0.7, 10], p: [0.4, -0.34, 0.28] },
      ];
      case 'vehicle': return [
        { g: 'box' as const, a: [2.0, 0.5, 0.95], p: [0, 0.1, 0] },
        { g: 'box' as const, a: [1.1, 0.46, 0.85], p: [-0.1, 0.55, 0] },
        { g: 'cyl' as const, a: [0.3, 0.3, 0.22, 20], p: [-0.65, -0.28, 0.5], r: [Math.PI / 2, 0, 0] },
        { g: 'cyl' as const, a: [0.3, 0.3, 0.22, 20], p: [0.65, -0.28, 0.5], r: [Math.PI / 2, 0, 0] },
        { g: 'cyl' as const, a: [0.3, 0.3, 0.22, 20], p: [-0.65, -0.28, -0.5], r: [Math.PI / 2, 0, 0] },
        { g: 'cyl' as const, a: [0.3, 0.3, 0.22, 20], p: [0.65, -0.28, -0.5], r: [Math.PI / 2, 0, 0] },
      ];
      default: return [
        { g: 'ico' as const, a: [0.95, 0], p: [0, 0.45, 0] },
        { g: 'torus' as const, a: [0.95, 0.09, 12, 48], p: [0, 0.45, 0], r: [Math.PI / 2.4, 0, 0.3] },
        { g: 'cyl' as const, a: [0.55, 0.7, 0.28, 6], p: [0, -0.52, 0] },
      ];
    }
  }, [asset.seedShape]);

  return (
    <group>
      {parts.map((p, i) => (
        <mesh key={i} position={p.p as any} rotation={(p as any).r ?? [0, 0, 0]} scale={(p as any).s ?? 1} castShadow receiveShadow>
          {p.g === 'box' && <boxGeometry args={p.a as any} />}
          {p.g === 'sphere' && <sphereGeometry args={p.a as any} />}
          {p.g === 'capsule' && <capsuleGeometry args={p.a as any} />}
          {p.g === 'cyl' && <cylinderGeometry args={p.a as any} />}
          {p.g === 'cone' && <coneGeometry args={p.a as any} />}
          {p.g === 'ico' && <icosahedronGeometry args={p.a as any} />}
          {p.g === 'torus' && <torusGeometry args={p.a as any} />}
          <meshStandardMaterial color={asset.tint} metalness={0.35} roughness={0.42} />
        </mesh>
      ))}
    </group>
  );
};

/* --------------------------------------------------------------- glb loader */
const LoadedModel: React.FC<{ url: string }> = ({ url }) => {
  const { scene } = useGLTF(url);
  const clone = useMemo(() => scene.clone(true), [scene]);

  // drei caches every GLTF it loads, so browsing a few assets would otherwise
  // pin several 5 MB meshes and their 2048² textures in GPU memory for the rest
  // of the session. Drop this one when the viewer closes.
  React.useEffect(() => () => {
    clone.traverse((o) => {
      const m = o as THREE.Mesh;
      if (!m.isMesh) return;
      m.geometry?.dispose();
      const mats = Array.isArray(m.material) ? m.material : [m.material];
      mats.forEach((mat: any) => {
        if (!mat) return;
        Object.values(mat).forEach((v: any) => v?.isTexture && v.dispose());
        mat.dispose?.();
      });
    });
    useGLTF.clear(url);
  }, [clone, url]);

  return <primitive object={clone} />;
};

/* ------------------------------------------------------- shading overrides */
const Shaded: React.FC<{ shading: ViewportShading; children: React.ReactNode }> = ({ shading, children }) => {
  const ref = useRef<THREE.Group>(null);
  const originals = useRef(new Map<THREE.Mesh, THREE.Material | THREE.Material[]>());

  useFrame(() => {
    const root = ref.current;
    if (!root) return;
    root.traverse((o) => {
      const m = o as THREE.Mesh;
      if (!m.isMesh) return;
      if (!originals.current.has(m)) originals.current.set(m, m.material);
      const base = originals.current.get(m)!;
      const want = shading;
      const tag = (m.userData.__shading as string) ?? '';
      if (tag === want) return;
      m.userData.__shading = want;
      if (want === 'material') { m.material = base; return; }
      if (want === 'normal') { m.material = new THREE.MeshNormalMaterial({ flatShading: false }); return; }
      if (want === 'wireframe') { m.material = new THREE.MeshBasicMaterial({ color: '#d8a1f1', wireframe: true }); return; }
      if (want === 'solid') { m.material = new THREE.MeshStandardMaterial({ color: '#b9bcc4', metalness: 0.05, roughness: 0.85 }); return; }
      if (want === 'uv') { m.material = new THREE.MeshBasicMaterial({ color: '#8ea2ff', wireframe: true, transparent: true, opacity: 0.55 }); return; }
      m.material = base;
    });
  });

  return <group ref={ref}>{children}</group>;
};

export const Viewport = forwardRef<ViewportHandle, {
  asset: Asset;
  shading: ViewportShading;
  light: StudioLight;
  autoRotate: boolean;
  showGrid: boolean;
  showGizmo?: boolean;
  /** Multipliers layered over the preset, driven by the light sliders. */
  trim?: LightTrim;
}>(({ asset, shading, light, autoRotate, showGrid, showGizmo = true, trim }, ref) => {
  const base = RIGS[light];
  // sliders scale the preset rather than replacing it, so presets stay meaningful
  const rig: Rig = trim
    ? { ...base,
        key: base.key * trim.directional,
        rim: base.rim * trim.directional,
        ambient: base.ambient * trim.ambient,
        env: base.env * trim.environment,
        exposure: base.exposure * trim.exposure }
    : base;
  const url = absolute(asset.modelUrl);

  return (
    <Canvas
      shadows
      dpr={[1, 2]}
      camera={{ position: [2.6, 1.7, 3.4], fov: 42 }}
      gl={{ antialias: true, preserveDrawingBuffer: true }}
    >
      <color attach="background" args={[rig.bg]} />
      {/* fog was pulling everything toward the background colour — push it back */}
      <fog attach="fog" args={[rig.bg, 18, 46]} />

      <Exposure value={rig.exposure} />
      <StudioEnvironment rig={rig} />
      <ambientLight intensity={rig.ambient} />
      <directionalLight position={[4, 6, 4]} intensity={rig.key} color={rig.keyColor} castShadow shadow-mapSize={[2048, 2048]} />
      <directionalLight position={[-5, 2, -3]} intensity={rig.rim} color={rig.rimColor} />

      <Suspense fallback={<Html center><span className="rounded-full bg-black/60 px-3 py-1.5 text-[11px] text-chalk backdrop-blur">loading mesh…</span></Html>}>
        {/* Generated meshes arrive at wildly different scales, so frame to the
            bounding box rather than trusting a fixed camera distance. */}
        {/* Turntable is done by orbiting the camera (see OrbitControls
            autoRotate) so the bounding box stays still and Bounds fits once. */}
        <Bounds fit clip observe margin={1.05} key={url ?? asset.id}>
          <Center>
            <Shaded shading={shading}>
              {url ? <LoadedModel url={url} /> : <Placeholder asset={asset} />}
            </Shaded>
          </Center>
        </Bounds>
      </Suspense>

      <ContactShadows position={[0, -1.15, 0]} opacity={0.4} scale={11} blur={2.8} far={4.5} />
      {showGrid && (
        <Grid
          position={[0, -1.16, 0]} args={[22, 22]}
          cellSize={0.4} cellThickness={0.5} cellColor="#2a2c33"
          sectionSize={2} sectionThickness={0.9} sectionColor="#3a3d47"
          fadeDistance={17} fadeStrength={1.4} infiniteGrid followCamera={false}
        />
      )}

      <CameraRig ref={ref} />

      {showGizmo && (
        <GizmoHelper alignment="bottom-right" margin={[62, 62]}>
          <GizmoViewport axisColors={['#e6765d', '#6fcf8f', '#5aa6c0']} labelColor="#121317" />
        </GizmoHelper>
      )}

      <OrbitControls
        makeDefault enablePan enableDamping dampingFactor={0.08}
        autoRotate={autoRotate} autoRotateSpeed={1.1}
        minDistance={0.6} maxDistance={40} target={[0, 0, 0]}
      />
    </Canvas>
  );
});
Viewport.displayName = 'Viewport';
