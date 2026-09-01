import React, { useRef, useMemo, useState, useEffect, Suspense } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { OrbitControls, Grid, Center, Float, ContactShadows, useGLTF } from '@react-three/drei';
import * as THREE from 'three';
import { 
  RenderMode, 
  LightingPreset, 
  CharacterPreset, 
  CameraOrientation,
  MeshSegment,
  AnimationPose 
} from '../types';
import { 
  RotateCw, 
  Layers, 
  Sun, 
  Maximize2, 
  Focus, 
  Box, 
  Activity, 
  Sparkles,
  Eye,
  Grid as GridIcon,
  Compass,
  Palette
} from 'lucide-react';

interface Viewport3DProps {
  character: CharacterPreset;
  renderMode: RenderMode;
  onSetRenderMode: (mode: RenderMode) => void;
  lighting: LightingPreset;
  onSetLighting: (preset: LightingPreset) => void;
  autoRotate: boolean;
  onToggleAutoRotate: () => void;
  wireframe: boolean;
  highlightSegment?: MeshSegment;
  activePose?: AnimationPose;
}

// Real GLB Model Mesh loader (loads fal.ai Trellis generated assets)
const LoadedGLBModel: React.FC<{
  url: string;
  renderMode: RenderMode;
  wireframe: boolean;
  autoRotate: boolean;
  character: CharacterPreset;
}> = ({ url, renderMode, wireframe, autoRotate, character }) => {
  const { scene } = useGLTF(url);
  const clone = useMemo(() => scene.clone(), [scene]);
  const groupRef = useRef<THREE.Group>(null);

  useFrame((_, delta) => {
    if (autoRotate && groupRef.current) {
      groupRef.current.rotation.y += delta * 0.4;
    }
  });

  useEffect(() => {
    clone.traverse((child) => {
      if ((child as THREE.Mesh).isMesh) {
        const m = child as THREE.Mesh;
        m.castShadow = true;
        m.receiveShadow = true;
        
        if (renderMode === 'wireframe') {
          m.material = new THREE.MeshStandardMaterial({
            color: '#06B6D4',
            wireframe: true,
            emissive: '#0891B2',
            emissiveIntensity: 0.4
          });
        } else if (renderMode === 'normal') {
          m.material = new THREE.MeshNormalMaterial({ wireframe });
        } else if (renderMode === 'matcap') {
          m.material = new THREE.MeshStandardMaterial({
            color: '#94A3B8',
            metalness: 0.1,
            roughness: 0.6,
            wireframe
          });
        } else if (renderMode === 'wire-on-shaded') {
          if (m.material && (m.material as THREE.MeshStandardMaterial).isMeshStandardMaterial) {
            (m.material as THREE.MeshStandardMaterial).wireframe = true;
          }
        }
      }
    });
  }, [clone, renderMode, wireframe]);

  return (
    <group ref={groupRef} scale={[1.9, 1.9, 1.9]} position={[0, 0.7, 0]}>
      <primitive object={clone} />
    </group>
  );
};

// Interactive Parametric 3D Character Mesh with High-Detail PBR Materials & Rigged Joints Simulation
const HyperCharacterMesh: React.FC<{
  character: CharacterPreset;
  renderMode: RenderMode;
  wireframe: boolean;
  autoRotate: boolean;
  highlightSegment?: MeshSegment;
  activePose?: AnimationPose;
}> = ({ character, renderMode, wireframe, autoRotate, highlightSegment, activePose }) => {
  const groupRef = useRef<THREE.Group>(null);
  const leftArmRef = useRef<THREE.Mesh>(null);
  const rightArmRef = useRef<THREE.Mesh>(null);
  const headRef = useRef<THREE.Mesh>(null);

  // Dynamic skeletal posing / animation tick
  useFrame(({ clock }, delta) => {
    if (autoRotate && groupRef.current) {
      groupRef.current.rotation.y += delta * 0.4;
    }

    const t = clock.getElapsedTime();

    if (activePose === 'idle') {
      if (leftArmRef.current) leftArmRef.current.rotation.z = Math.sin(t * 1.5) * 0.05 + 0.1;
      if (rightArmRef.current) rightArmRef.current.rotation.z = -Math.sin(t * 1.5) * 0.05 - 0.1;
      if (headRef.current) headRef.current.rotation.y = Math.sin(t * 0.8) * 0.08;
    } else if (activePose === 'walk') {
      if (leftArmRef.current) leftArmRef.current.rotation.x = Math.sin(t * 4) * 0.35;
      if (rightArmRef.current) rightArmRef.current.rotation.x = -Math.sin(t * 4) * 0.35;
      if (headRef.current) headRef.current.position.y = 1.7 + Math.abs(Math.sin(t * 4)) * 0.03;
    } else if (activePose === 'combat') {
      if (leftArmRef.current) {
        leftArmRef.current.rotation.x = 0.8;
        leftArmRef.current.rotation.z = 0.3;
      }
      if (rightArmRef.current) {
        rightArmRef.current.rotation.x = 1.2;
        rightArmRef.current.rotation.z = -0.4;
      }
      if (headRef.current) headRef.current.rotation.y = 0.2;
    } else if (activePose === 't-pose') {
      if (leftArmRef.current) {
        leftArmRef.current.rotation.set(0, 0, Math.PI / 2);
      }
      if (rightArmRef.current) {
        rightArmRef.current.rotation.set(0, 0, -Math.PI / 2);
      }
    }
  });

  // Dynamic Shader Channel Materials
  const baseMaterial = useMemo(() => {
    const baseColor = new THREE.Color(character.geometryColor);

    switch (renderMode) {
      case 'wireframe':
        return (
          <meshStandardMaterial
            color="#06B6D4"
            wireframe
            emissive="#0891B2"
            emissiveIntensity={0.4}
          />
        );
      case 'wire-on-shaded':
        return (
          <meshStandardMaterial
            color={baseColor}
            metalness={character.metallic}
            roughness={character.roughness}
            wireframe={true}
          />
        );
      case 'normal':
        return <meshNormalMaterial wireframe={wireframe} />;
      case 'roughness':
        return (
          <meshBasicMaterial
            color={new THREE.Color(character.roughness, character.roughness, character.roughness)}
            wireframe={wireframe}
          />
        );
      case 'metallic':
        return (
          <meshBasicMaterial
            color={new THREE.Color(character.metallic, character.metallic, character.metallic)}
            wireframe={wireframe}
          />
        );
      case 'ao':
        return (
          <meshBasicMaterial
            color={new THREE.Color(0.25, 0.25, 0.25)}
            wireframe={wireframe}
          />
        );
      case 'matcap':
        return (
          <meshStandardMaterial
            color="#94A3B8"
            metalness={0.1}
            roughness={0.6}
            wireframe={wireframe}
          />
        );
      case 'splats':
        return (
          <pointsMaterial
            size={0.035}
            color={baseColor}
            sizeAttenuation={true}
          />
        );
      case 'pbr':
      default:
        return (
          <meshStandardMaterial
            color={baseColor}
            metalness={character.metallic}
            roughness={character.roughness}
            wireframe={wireframe}
          />
        );
    }
  }, [character, renderMode, wireframe]);

  // Segment highlight helper
  const isPartHighlighted = (segment: MeshSegment) => {
    if (!highlightSegment || highlightSegment === 'all') return false;
    return highlightSegment === segment;
  };

  const getPartMaterial = (segment: MeshSegment) => {
    if (isPartHighlighted(segment)) {
      return (
        <meshStandardMaterial
          color="#F59E0B"
          emissive="#F59E0B"
          emissiveIntensity={0.8}
          wireframe={wireframe}
        />
      );
    }
    return baseMaterial;
  };

  return (
    <group ref={groupRef} position={[0, 0, 0]}>
      {/* Head / Helmet */}
      <mesh ref={headRef} position={[0, 1.7, 0]} castShadow receiveShadow>
        <sphereGeometry args={[0.32, 32, 32]} />
        {getPartMaterial('head')}
      </mesh>

      {/* Cybernetic Visor / Eyes */}
      <mesh position={[0, 1.72, 0.26]} castShadow>
        <boxGeometry args={[0.34, 0.1, 0.16]} />
        <meshStandardMaterial 
          color="#06B6D4" 
          emissive="#06B6D4" 
          emissiveIntensity={character.emissiveIntensity || 2.5} 
        />
      </mesh>

      {/* Torso / Armor Chestplate */}
      <mesh position={[0, 1.05, 0]} castShadow receiveShadow>
        <cylinderGeometry args={[0.42, 0.32, 0.95, 32]} />
        {getPartMaterial('torso')}
      </mesh>

      {/* Core Energy Arc Reactor */}
      <mesh position={[0, 1.1, 0.32]} castShadow>
        <cylinderGeometry args={[0.08, 0.08, 0.04, 32]} />
        <meshStandardMaterial color="#3B82F6" emissive="#3B82F6" emissiveIntensity={3.2} />
      </mesh>

      {/* Shoulder Pauldrons */}
      <mesh position={[-0.55, 1.35, 0]} castShadow receiveShadow>
        <boxGeometry args={[0.26, 0.22, 0.32]} />
        {getPartMaterial('accessories')}
      </mesh>
      <mesh position={[0.55, 1.35, 0]} castShadow receiveShadow>
        <boxGeometry args={[0.26, 0.22, 0.32]} />
        {getPartMaterial('accessories')}
      </mesh>

      {/* Arms */}
      <mesh ref={leftArmRef} position={[-0.55, 0.85, 0]} castShadow receiveShadow>
        <capsuleGeometry args={[0.1, 0.65, 16, 16]} />
        {getPartMaterial('arms')}
      </mesh>
      <mesh ref={rightArmRef} position={[0.55, 0.85, 0]} castShadow receiveShadow>
        <capsuleGeometry args={[0.1, 0.65, 16, 16]} />
        {getPartMaterial('arms')}
      </mesh>

      {/* Legs */}
      <mesh position={[-0.22, -0.05, 0]} castShadow receiveShadow>
        <capsuleGeometry args={[0.13, 0.95, 16, 16]} />
        {getPartMaterial('legs')}
      </mesh>
      <mesh position={[0.22, -0.05, 0]} castShadow receiveShadow>
        <capsuleGeometry args={[0.13, 0.95, 16, 16]} />
        {getPartMaterial('legs')}
      </mesh>

      {/* Back Mount / Katana Blade / Tech Gear */}
      <mesh position={[0, 1.15, -0.28]} rotation={[0.4, 0.3, 0]} castShadow>
        <boxGeometry args={[0.08, 1.6, 0.08]} />
        {getPartMaterial('weapon')}
      </mesh>
    </group>
  );
};

export const Viewport3D: React.FC<Viewport3DProps> = ({
  character,
  renderMode,
  onSetRenderMode,
  lighting,
  onSetLighting,
  autoRotate,
  onToggleAutoRotate,
  wireframe,
  highlightSegment,
  activePose
}) => {
  const [showGrid, setShowGrid] = useState<boolean>(true);
  const [cameraView, setCameraView] = useState<CameraOrientation>('free');
  const controlsRef = useRef<any>(null);

  const handleSetCameraView = (view: CameraOrientation) => {
    setCameraView(view);
    if (!controlsRef.current) return;

    const dist = 4.5;
    switch (view) {
      case 'front':
        controlsRef.current.object.position.set(0, 1.2, dist);
        break;
      case 'back':
        controlsRef.current.object.position.set(0, 1.2, -dist);
        break;
      case 'left':
        controlsRef.current.object.position.set(-dist, 1.2, 0);
        break;
      case 'right':
        controlsRef.current.object.position.set(dist, 1.2, 0);
        break;
      case 'top':
        controlsRef.current.object.position.set(0, dist + 1, 0.001);
        break;
      case 'isometric':
        controlsRef.current.object.position.set(dist * 0.7, dist * 0.7, dist * 0.7);
        break;
      case 'free':
      default:
        controlsRef.current.object.position.set(0, 1.5, dist);
        break;
    }
    controlsRef.current.target.set(0, 0.9, 0);
    controlsRef.current.update();
  };

  const handleResetCamera = () => {
    handleSetCameraView('free');
  };

  return (
    <div className="w-full h-full relative bg-gradient-to-b from-[#080C14] via-[#05070B] to-[#020306] select-none overflow-hidden">
      {/* Floating Top Left: Hyper3D Mesh Information Card */}
      <div className="absolute top-4 left-4 z-20 flex flex-col gap-2 pointer-events-auto">
        <div className="p-3 bg-[#0A0E18]/85 backdrop-blur-xl border border-[#1E293B] rounded-2xl text-xs text-slate-200 flex flex-col gap-1.5 shadow-2xl min-w-[210px]">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 font-bold text-white">
              <span
                className="w-2.5 h-2.5 rounded-full shadow-sm"
                style={{ backgroundColor: character.geometryColor }}
              />
              <span className="truncate max-w-[130px]">{character.title}</span>
            </div>
            <span className="text-[9px] uppercase font-mono px-1.5 py-0.5 rounded bg-cyan-500/10 text-cyan-400 border border-cyan-500/30">
              {character.modelType === 'hybrid-pipeline' ? 'Rodin Gen-2' : character.modelType === 'trellis-2.0' ? 'TRELLIS' : 'Hunyuan'}
            </span>
          </div>

          <div className="w-full h-px bg-[#1A2234]" />

          <div className="grid grid-cols-2 gap-2 text-[10px] font-mono">
            <div>
              <span className="text-slate-500 block">Triangles</span>
              <span className="text-cyan-300 font-bold">{character.polyCount.toLocaleString()}</span>
            </div>
            <div>
              <span className="text-slate-500 block">Vertices</span>
              <span className="text-slate-200 font-semibold">{character.vertexCount.toLocaleString()}</span>
            </div>
            <div>
              <span className="text-slate-500 block">Texture Res</span>
              <span className="text-slate-200 font-semibold">{character.textureRes}</span>
            </div>
            <div>
              <span className="text-slate-500 block">Topology</span>
              <span className="text-emerald-400 font-semibold">Clean Quads</span>
            </div>
          </div>
        </div>
      </div>

      {/* Floating Top Center: Shader Channel Passes Toolbar */}
      <div className="absolute top-4 left-1/2 -translate-x-1/2 z-20 hidden md:flex items-center gap-1 p-1 bg-[#0A0E18]/90 backdrop-blur-xl border border-[#1E293B] rounded-2xl shadow-2xl">
        {[
          { id: 'pbr', label: 'PBR Shaded' },
          { id: 'matcap', label: 'MatCap Clay' },
          { id: 'wire-on-shaded', label: 'Wireframe' },
          { id: 'normal', label: 'Normals' },
          { id: 'roughness', label: 'Roughness' },
          { id: 'metallic', label: 'Metallic' },
          { id: 'ao', label: 'AO' },
          { id: 'splats', label: '3D Splats' }
        ].map((mode) => (
          <button
            key={mode.id}
            onClick={() => onSetRenderMode(mode.id as RenderMode)}
            className={`
              px-2.5 py-1.5 text-[11px] font-semibold rounded-xl transition-all
              ${renderMode === mode.id
                ? 'bg-gradient-to-r from-cyan-500/25 to-blue-500/25 text-cyan-300 border border-cyan-500/50 shadow-sm'
                : 'text-slate-400 hover:text-slate-200 hover:bg-slate-900/60'
              }
            `}
          >
            {mode.label}
          </button>
        ))}
      </div>

      {/* Floating Top Right: Camera Orientation Cube & Controls */}
      <div className="absolute top-4 right-4 z-20 flex items-center gap-2 pointer-events-auto">
        {/* Camera Views Gizmo Switcher */}
        <div className="flex items-center gap-1 p-1 bg-[#0A0E18]/85 backdrop-blur-xl border border-[#1E293B] rounded-xl shadow-xl text-[10px] font-mono">
          {(['front', 'back', 'left', 'right', 'top', 'isometric'] as CameraOrientation[]).map((v) => (
            <button
              key={v}
              onClick={() => handleSetCameraView(v)}
              className={`px-2 py-1 rounded capitalize transition-all ${
                cameraView === v
                  ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/40 font-bold'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              {v === 'isometric' ? 'ISO' : v}
            </button>
          ))}
        </div>

        {/* Lighting Preset Picker */}
        <div className="flex items-center gap-1 p-1 bg-[#0A0E18]/85 backdrop-blur-xl border border-[#1E293B] rounded-xl shadow-xl">
          {(['studio', 'cyberpunk', 'sunset', 'dramatic'] as LightingPreset[]).map((lt) => (
            <button
              key={lt}
              onClick={() => onSetLighting(lt)}
              className={`px-2 py-1 text-[10px] font-bold capitalize rounded-lg transition-all ${
                lighting === lt
                  ? 'bg-gradient-to-r from-cyan-500/20 to-blue-500/20 text-cyan-300 border border-cyan-500/40'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
              title={`Lighting: ${lt}`}
            >
              {lt}
            </button>
          ))}
        </div>

        {/* Action Toggles */}
        <div className="flex items-center gap-1 p-1 bg-[#0A0E18]/85 backdrop-blur-xl border border-[#1E293B] rounded-xl shadow-xl">
          {/* Turntable Auto-Rotate */}
          <button
            onClick={onToggleAutoRotate}
            className={`p-1.5 rounded-lg text-xs transition-colors ${
              autoRotate ? 'bg-cyan-500/20 text-cyan-400 border border-cyan-500/40' : 'text-slate-400 hover:text-white'
            }`}
            title="Auto-Rotate Turntable"
          >
            <RotateCw className="w-3.5 h-3.5" />
          </button>

          {/* Grid Toggle */}
          <button
            onClick={() => setShowGrid(!showGrid)}
            className={`p-1.5 rounded-lg text-xs transition-colors ${
              showGrid ? 'bg-cyan-500/20 text-cyan-400 border border-cyan-500/40' : 'text-slate-400 hover:text-white'
            }`}
            title="Toggle Floor Grid"
          >
            <GridIcon className="w-3.5 h-3.5" />
          </button>

          {/* Reset Camera Focus */}
          <button
            onClick={handleResetCamera}
            className="p-1.5 rounded-lg text-xs text-slate-400 hover:text-white transition-colors"
            title="Reset Camera (F)"
          >
            <Focus className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      {/* 3D WebGL Canvas */}
      <div className="w-full h-full">
        <Canvas
          camera={{ position: [0, 1.5, 4.5], fov: 40 }}
          shadows
          gl={{ antialias: true, alpha: false, preserveDrawingBuffer: true }}
        >
          {/* Lighting Setups */}
          {lighting === 'studio' && (
            <>
              <ambientLight intensity={0.65} />
              <directionalLight position={[5, 8, 5]} intensity={1.8} castShadow shadow-mapSize={2048} />
              <directionalLight position={[-5, 3, -2]} intensity={0.9} color="#93C5FD" />
              <pointLight position={[0, 4, 3]} intensity={0.6} />
            </>
          )}

          {lighting === 'cyberpunk' && (
            <>
              <ambientLight intensity={0.25} />
              <directionalLight position={[4, 6, 4]} intensity={2.4} color="#06B6D4" castShadow shadow-mapSize={2048} />
              <directionalLight position={[-4, 2, -4]} intensity={2.8} color="#EC4899" />
              <pointLight position={[0, 1, 2]} intensity={1.5} color="#8B5CF6" />
            </>
          )}

          {lighting === 'sunset' && (
            <>
              <ambientLight intensity={0.4} />
              <directionalLight position={[6, 3, 2]} intensity={2.5} color="#F59E0B" castShadow shadow-mapSize={2048} />
              <directionalLight position={[-4, 2, -3]} intensity={0.8} color="#3B82F6" />
            </>
          )}

          {lighting === 'dramatic' && (
            <>
              <ambientLight intensity={0.12} />
              <directionalLight position={[0, 8, 2]} intensity={3.8} color="#FFFFFF" castShadow shadow-mapSize={2048} />
              <pointLight position={[-3, -1, 2]} intensity={0.9} color="#06B6D4" />
            </>
          )}

          {/* 3D Character Model Rendering */}
          <Suspense fallback={null}>
            <Center top>
              <Float speed={autoRotate ? 1.0 : 0} rotationIntensity={0.05} floatIntensity={0.08}>
                {character.glbUrl ? (
                  <LoadedGLBModel
                    url={character.glbUrl}
                    renderMode={renderMode}
                    wireframe={wireframe}
                    autoRotate={autoRotate}
                    character={character}
                  />
                ) : (
                  <HyperCharacterMesh
                    character={character}
                    renderMode={renderMode}
                    wireframe={wireframe}
                    autoRotate={autoRotate}
                    highlightSegment={highlightSegment}
                    activePose={activePose}
                  />
                )}
              </Float>
            </Center>
          </Suspense>

          {/* Floor Grid & Shadows */}
          {showGrid && (
            <Grid
              position={[0, -0.6, 0]}
              args={[24, 24]}
              cellSize={0.5}
              cellThickness={0.8}
              cellColor="#172236"
              sectionSize={2.5}
              sectionThickness={1.2}
              sectionColor="#06B6D4"
              fadeDistance={14}
              fadeStrength={1.4}
            />
          )}
          <ContactShadows position={[0, -0.59, 0]} opacity={0.7} scale={7} blur={1.6} far={4} />

          {/* Orbit Controls */}
          <OrbitControls
            ref={controlsRef}
            enablePan={true}
            enableZoom={true}
            enableRotate={true}
            minDistance={1.6}
            maxDistance={8.5}
            maxPolarAngle={Math.PI / 2 + 0.05}
            target={[0, 0.9, 0]}
          />
        </Canvas>
      </div>

      {/* Floating Bottom Viewport Navigation Legend */}
      <div className="absolute bottom-4 left-1/2 -translate-x-1/2 z-20 px-4 py-1.5 bg-[#0A0E18]/85 backdrop-blur-xl border border-[#1E293B] rounded-full text-[11px] text-slate-400 font-medium flex items-center gap-4 shadow-2xl">
        <span className="flex items-center gap-1">🖱️ <b>Left Click:</b> Orbit</span>
        <span className="text-slate-600">•</span>
        <span className="flex items-center gap-1"><b>Right Click / Shift:</b> Pan</span>
        <span className="text-slate-600">•</span>
        <span className="flex items-center gap-1"><b>Scroll:</b> Zoom</span>
        <span className="text-slate-600">•</span>
        <span className="text-cyan-400 font-mono"><b>F:</b> Focus</span>
      </div>
    </div>
  );
};
