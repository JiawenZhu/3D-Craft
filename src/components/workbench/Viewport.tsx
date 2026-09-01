import React, { Suspense, useMemo, useRef } from 'react';
import { Canvas, useFrame, useLoader } from '@react-three/fiber';
import { Center, ContactShadows, Grid, Html, OrbitControls, useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import type { Asset, StudioLight, ViewportShading } from '../../types';
import { absolute } from '../../lib/api';

/* ---------------------------------------------------------------- lighting */
const RIGS: Record<StudioLight, { key: number; fill: number; rim: number; keyColor: string; rimColor: string; ambient: number; bg: string }> = {
  studio:  { key: 2.4, fill: 0.7, rim: 1.6, keyColor: '#ffffff', rimColor: '#cfd6ff', ambient: 0.55, bg: '#141519' },
  rim:     { key: 1.0, fill: 0.25, rim: 3.4, keyColor: '#ffd6b0', rimColor: '#7fd0ff', ambient: 0.22, bg: '#0d0e12' },
  sunset:  { key: 2.6, fill: 0.5, rim: 1.8, keyColor: '#ffb066', rimColor: '#8f6bff', ambient: 0.4, bg: '#17110f' },
  night:   { key: 0.9, fill: 0.3, rim: 2.6, keyColor: '#8ea2ff', rimColor: '#d8a1f1', ambient: 0.18, bg: '#0a0b10' },
  flat:    { key: 1.4, fill: 1.4, rim: 1.2, keyColor: '#ffffff', rimColor: '#ffffff', ambient: 1.1, bg: '#16171b' },
};

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

const Spin: React.FC<{ on: boolean; children: React.ReactNode }> = ({ on, children }) => {
  const ref = useRef<THREE.Group>(null);
  useFrame((_, d) => { if (on && ref.current) ref.current.rotation.y += d * 0.35; });
  return <group ref={ref}>{children}</group>;
};

export const Viewport: React.FC<{
  asset: Asset;
  shading: ViewportShading;
  light: StudioLight;
  autoRotate: boolean;
  showGrid: boolean;
}> = ({ asset, shading, light, autoRotate, showGrid }) => {
  const rig = RIGS[light];
  const url = absolute(asset.modelUrl);

  return (
    <Canvas
      shadows
      dpr={[1, 2]}
      camera={{ position: [2.6, 1.7, 3.4], fov: 42 }}
      gl={{ antialias: true, preserveDrawingBuffer: true }}
    >
      <color attach="background" args={[rig.bg]} />
      <fog attach="fog" args={[rig.bg, 9, 22]} />

      <ambientLight intensity={rig.ambient} />
      <directionalLight position={[4, 6, 4]} intensity={rig.key} color={rig.keyColor} castShadow shadow-mapSize={[1024, 1024]} />
      <directionalLight position={[-5, 2, -3]} intensity={rig.rim} color={rig.rimColor} />
      <directionalLight position={[0, -3, 5]} intensity={rig.fill} color="#ffffff" />

      <Suspense fallback={<Html center><span className="rounded-full bg-black/60 px-3 py-1.5 text-[11px] text-chalk backdrop-blur">loading mesh…</span></Html>}>
        <Spin on={autoRotate}>
          <Center>
            <Shaded shading={shading}>
              {url ? <LoadedModel url={url} /> : <Placeholder asset={asset} />}
            </Shaded>
          </Center>
        </Spin>
      </Suspense>

      <ContactShadows position={[0, -1.15, 0]} opacity={0.55} scale={11} blur={2.6} far={4.5} />
      {showGrid && (
        <Grid
          position={[0, -1.16, 0]} args={[22, 22]}
          cellSize={0.4} cellThickness={0.5} cellColor="#2a2c33"
          sectionSize={2} sectionThickness={0.9} sectionColor="#3a3d47"
          fadeDistance={17} fadeStrength={1.4} infiniteGrid followCamera={false}
        />
      )}

      <OrbitControls makeDefault enablePan enableDamping dampingFactor={0.08} minDistance={1.5} maxDistance={12} target={[0, 0, 0]} />
    </Canvas>
  );
};
