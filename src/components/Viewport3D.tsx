import React, { useRef, useMemo } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { OrbitControls, Grid, Center, Float, ContactShadows, Environment } from '@react-three/drei';
import * as THREE from 'three';
import { RenderMode, LightingPreset, CharacterPreset } from '../types';

interface Viewport3DProps {
  character: CharacterPreset;
  renderMode: RenderMode;
  lighting: LightingPreset;
  autoRotate: boolean;
  wireframe: boolean;
}

// Interactive 3D Character Mesh with PBR Shader visualization
const CharacterMesh: React.FC<{
  character: CharacterPreset;
  renderMode: RenderMode;
  wireframe: boolean;
  autoRotate: boolean;
}> = ({ character, renderMode, wireframe, autoRotate }) => {
  const meshRef = useRef<THREE.Group>(null);

  useFrame((_, delta) => {
    if (autoRotate && meshRef.current) {
      meshRef.current.rotation.y += delta * 0.4;
    }
  });

  // Dynamic PBR Materials based on the selected render mode
  const material = useMemo(() => {
    const baseColor = new THREE.Color(character.geometryColor);

    switch (renderMode) {
      case 'wireframe':
        return (
          <meshStandardMaterial
            color="#06B6D4"
            wireframe
            emissive="#0891B2"
            emissiveIntensity={0.3}
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
      case 'matcap':
        return (
          <meshStandardMaterial
            color={baseColor}
            metalness={0.9}
            roughness={0.1}
            wireframe={wireframe}
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

  return (
    <group ref={meshRef} position={[0, 0, 0]}>
      {/* Head / Helmet */}
      <mesh position={[0, 1.7, 0]} castShadow receiveShadow>
        <sphereGeometry args={[0.32, 32, 32]} />
        {material}
      </mesh>

      {/* Cybernetic Visor / Eyes */}
      <mesh position={[0, 1.72, 0.26]} castShadow>
        <boxGeometry args={[0.34, 0.1, 0.16]} />
        <meshStandardMaterial color="#06B6D4" emissive="#06B6D4" emissiveIntensity={2.5} />
      </mesh>

      {/* Torso / Armor Chestplate */}
      <mesh position={[0, 1.05, 0]} castShadow receiveShadow>
        <cylinderGeometry args={[0.42, 0.32, 0.95, 32]} />
        {material}
      </mesh>

      {/* Core Energy Conduit */}
      <mesh position={[0, 1.1, 0.32]} castShadow>
        <cylinderGeometry args={[0.08, 0.08, 0.04, 32]} />
        <meshStandardMaterial color="#3B82F6" emissive="#3B82F6" emissiveIntensity={3} />
      </mesh>

      {/* Shoulder Armor Pauldrons */}
      <mesh position={[-0.55, 1.35, 0]} castShadow receiveShadow>
        <boxGeometry args={[0.26, 0.22, 0.32]} />
        {material}
      </mesh>
      <mesh position={[0.55, 1.35, 0]} castShadow receiveShadow>
        <boxGeometry args={[0.26, 0.22, 0.32]} />
        {material}
      </mesh>

      {/* Arms */}
      <mesh position={[-0.55, 0.85, 0]} castShadow receiveShadow>
        <capsuleGeometry args={[0.1, 0.65, 16, 16]} />
        {material}
      </mesh>
      <mesh position={[0.55, 0.85, 0]} castShadow receiveShadow>
        <capsuleGeometry args={[0.1, 0.65, 16, 16]} />
        {material}
      </mesh>

      {/* Legs & Sabatons */}
      <mesh position={[-0.22, -0.05, 0]} castShadow receiveShadow>
        <capsuleGeometry args={[0.13, 0.95, 16, 16]} />
        {material}
      </mesh>
      <mesh position={[0.22, -0.05, 0]} castShadow receiveShadow>
        <capsuleGeometry args={[0.13, 0.95, 16, 16]} />
        {material}
      </mesh>

      {/* Back Mount / Katana / Jet Thruster */}
      <mesh position={[0, 1.15, -0.28]} rotation={[0.4, 0.3, 0]} castShadow>
        <boxGeometry args={[0.08, 1.6, 0.08]} />
        <meshStandardMaterial color="#0F172A" metalness={0.9} roughness={0.1} />
      </mesh>
    </group>
  );
};

export const Viewport3D: React.FC<Viewport3DProps> = ({
  character,
  renderMode,
  lighting,
  autoRotate,
  wireframe
}) => {
  return (
    <div className="w-full h-full relative bg-gradient-to-b from-[#0B0F19] to-[#04060A]">
      <Canvas
        camera={{ position: [0, 1.5, 4.5], fov: 42 }}
        shadows
        gl={{ antialias: true, alpha: false, preserveDrawingBuffer: true }}
      >
        {/* Dynamic Studio Lighting based on Preset */}
        {lighting === 'studio' && (
          <>
            <ambientLight intensity={0.7} />
            <directionalLight position={[5, 8, 5]} intensity={1.8} castShadow />
            <directionalLight position={[-5, 3, -2]} intensity={0.8} color="#93C5FD" />
            <pointLight position={[0, 4, 3]} intensity={0.6} />
          </>
        )}

        {lighting === 'cyberpunk' && (
          <>
            <ambientLight intensity={0.3} />
            <directionalLight position={[4, 6, 4]} intensity={2.2} color="#06B6D4" castShadow />
            <directionalLight position={[-4, 2, -4]} intensity={2.5} color="#EC4899" />
            <pointLight position={[0, 1, 2]} intensity={1.2} color="#8B5CF6" />
          </>
        )}

        {lighting === 'sunset' && (
          <>
            <ambientLight intensity={0.5} />
            <directionalLight position={[6, 3, 2]} intensity={2.4} color="#F59E0B" castShadow />
            <directionalLight position={[-4, 2, -3]} intensity={0.6} color="#3B82F6" />
          </>
        )}

        {lighting === 'dramatic' && (
          <>
            <ambientLight intensity={0.15} />
            <directionalLight position={[0, 8, 2]} intensity={3.5} color="#FFFFFF" castShadow />
            <pointLight position={[-3, -1, 2]} intensity={0.8} color="#06B6D4" />
          </>
        )}

        {lighting === 'dawn' && (
          <>
            <ambientLight intensity={0.6} />
            <directionalLight position={[4, 5, 4]} intensity={1.5} color="#E0E7FF" castShadow />
            <directionalLight position={[-3, 1, -2]} intensity={0.9} color="#FDE047" />
          </>
        )}

        {/* 3D Character Mesh */}
        <Center top>
          <Float speed={1.2} rotationIntensity={0.1} floatIntensity={0.15}>
            <CharacterMesh
              character={character}
              renderMode={renderMode}
              wireframe={wireframe}
              autoRotate={autoRotate}
            />
          </Float>
        </Center>

        {/* Studio Floor Grid & Contact Shadows */}
        <Grid
          position={[0, -0.6, 0]}
          args={[20, 20]}
          cellSize={0.4}
          cellThickness={0.8}
          cellColor="#1E293B"
          sectionSize={2.0}
          sectionThickness={1.2}
          sectionColor="#06B6D4"
          fadeDistance={12}
          fadeStrength={1.5}
        />
        <ContactShadows position={[0, -0.59, 0]} opacity={0.65} scale={6} blur={1.5} far={4} />

        {/* Camera Orbit Controls */}
        <OrbitControls
          enablePan={true}
          enableZoom={true}
          enableRotate={true}
          minDistance={1.8}
          maxDistance={8.5}
          maxPolarAngle={Math.PI / 2 + 0.05}
          target={[0, 0.8, 0]}
        />
      </Canvas>
    </div>
  );
};
