import { CharacterPreset } from '../types';

export const SAMPLE_CHARACTERS: CharacterPreset[] = [
  {
    id: 'char-cyberpunk-mercenary',
    title: 'Neon Cyberpunk Samurai',
    style: 'cyberpunk',
    prompt: 'Full body cyberpunk samurai warrior, glowing cybernetic visor, carbon fiber tactical armor, katana on back, hyper-detailed hard surfaces, unreal engine 5 game asset',
    thumbnail: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=400&q=80',
    modelType: 'trellis-2.0',
    polyCount: 42800,
    textureRes: '4096 x 4096',
    geometryColor: '#06B6D4',
    metallic: 0.85,
    roughness: 0.25
  },
  {
    id: 'char-stylized-sorceress',
    title: 'Astral Crystal Sorceress',
    style: 'stylized-anime',
    prompt: 'Anime stylized sorceress in flowing celestial robes, crystal staff, glowing magical orbs, vibrant color palette, Genshin Impact style 3D character model',
    thumbnail: 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=400&q=80',
    modelType: 'hunyuan3d-2.1',
    polyCount: 38400,
    textureRes: '4096 x 4096',
    geometryColor: '#8B5CF6',
    metallic: 0.3,
    roughness: 0.4
  },
  {
    id: 'char-scifi-titan-mech',
    title: 'Aegis Vanguard Heavy Mech',
    style: 'scifi-mech',
    prompt: 'Heavy bipedal titan mech suit, hydraulic pistons, energy shield emitter on left arm, shoulder rocket pod, weathered battle damage and hazard stripes',
    thumbnail: 'https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=400&q=80',
    modelType: 'trellis-2.0',
    polyCount: 65200,
    textureRes: '4096 x 4096',
    geometryColor: '#F59E0B',
    metallic: 0.9,
    roughness: 0.35
  },
  {
    id: 'char-fantasy-paladin',
    title: 'Sunforged High Paladin',
    style: 'fantasy-rpg',
    prompt: 'Noble knight paladin in gold and silver plate armor, lion crest shield, glowing divine broadsword, intricate filigree engraving, AAA dark fantasy character',
    thumbnail: 'https://images.unsplash.com/photo-1563089145-599997674d42?w=400&q=80',
    modelType: 'hunyuan3d-2.1',
    polyCount: 51200,
    textureRes: '4096 x 4096',
    geometryColor: '#EC4899',
    metallic: 0.95,
    roughness: 0.15
  },
  {
    id: 'char-cyber-beast',
    title: 'Bionic Shadow Stalker',
    style: 'cyberpunk',
    prompt: 'Sleek biomechanical panther assassin with neon green fiber optics, titanium claws, stealth cloak emitters, dynamic stalking pose',
    thumbnail: 'https://images.unsplash.com/photo-1634017839464-5c339ebe3cb4?w=400&q=80',
    modelType: 'hybrid-pipeline',
    polyCount: 48900,
    textureRes: '4096 x 4096',
    geometryColor: '#10B981',
    metallic: 0.75,
    roughness: 0.2
  }
];
