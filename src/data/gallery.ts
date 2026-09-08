import type { Asset } from '../types';

let n = 0;
const make = (a: Partial<Asset> & Pick<Asset, 'name' | 'prompt' | 'seedShape' | 'tint'>): Asset => {
  n += 1;
  const faces = a.faces ?? 24_000 + ((n * 7919) % 60_000);
  return {
    id: `seed-${n}`,
    engine: 'trellis-2',
    createdAt: Date.now() - n * 1000 * 60 * 37,
    faces,
    vertices: Math.round(faces * 0.52),
    textureRes: 4096,
    fileSizeMb: Math.round((faces / 9000) * 10) / 10,
    liked: false,
    likes: 15 + ((n * 23) % 95),
    author: ['velozetetic', 'David Austin', 'Tiffany Hood', 'mynameisn', 'Muslim', 'plgasc', 'anoliss', 'Flix Mohanad', 'Zonafarm'][n % 9],
    visibility: 'public',
    local: false,
    ...a,
  };
};

/**
 * The EXPLORE feed — High-quality 3D assets with their own matching 3D GLB models.
 */
export const EXPLORE_ASSETS: Asset[] = [
  make({
    name: 'Fairytale Wooden Cottage',
    prompt: 'A clean isolated 3D model render of a cute stylized fairytale wooden cottage house with warm glowing windows on a round mossy stone base, pure solid black studio background, no background elements, soft cinematic studio rim lighting, 3D game asset render, octane render 8k',
    seedShape: 'prop',
    tint: '#EF4444',
    thumbUrl: '/images/explore/rodin_clean_cottage_1788235864897.jpg',
    modelUrl: '/models/fairytale_cottage.glb',
    engine: 'hybrid',
    likes: 112,
    faces: 36000
  }),
  make({
    name: 'Bright Yellow Mini Vintage Car',
    prompt: 'A clean isolated 3D model render of an adorable retro bright yellow mini vintage car with rounded curves, shiny chrome headlights, isolated on pure solid black studio background, no background elements, cinematic rim lighting, 3D asset render 8k',
    seedShape: 'vehicle',
    tint: '#EAB308',
    thumbUrl: '/images/explore/rodin_clean_taxi_1788235881061.jpg',
    modelUrl: '/models/yellow_mini_car.glb',
    engine: 'trellis-2',
    likes: 98,
    faces: 42000
  }),
  make({
    name: 'Baby Emerald Dragon',
    prompt: 'A clean isolated 3D character model render of an adorable cute baby green dragon with golden belly scales, tiny bat wings, glossy big emerald eyes, sitting pose, isolated on pure solid black studio background, no background clutter, soft rim lighting, Pixar 3D animated style 8k',
    seedShape: 'creature',
    tint: '#22C55E',
    thumbUrl: '/images/explore/rodin_clean_dragon_1788235904609.jpg',
    modelUrl: '/models/baby_emerald_dragon.glb',
    engine: 'hunyuan3d-2.1',
    likes: 145,
    faces: 48000
  }),
  make({
    name: 'Chibi Wizard Apprentice',
    prompt: 'A clean isolated 3D character model render of a cute chibi wizard apprentice child wearing deep indigo robes with golden starry embroidery and a tall wizard hat, holding a wooden staff with a glowing cyan crystal orb, isolated on pure solid black studio background, no background clutter, soft rim lighting, Pixar 3D style 8k',
    seedShape: 'figure',
    tint: '#6366F1',
    thumbUrl: '/images/explore/rodin_clean_wizard.jpg',
    modelUrl: '/models/chibi_wizard.glb',
    engine: 'hybrid',
    likes: 128,
    faces: 38000
  }),
  make({
    name: 'Spherical Robot Companion',
    prompt: 'A clean isolated 3D character model render of a cute spherical white robot companion with glowing cyan digital eye screen, brass antenna, magnetic floating hands, isolated on pure solid black studio background, no background elements, studio rim lighting, 3D asset render 8k',
    seedShape: 'mech',
    tint: '#06B6D4',
    thumbUrl: '/images/explore/rodin_clean_mech.jpg',
    modelUrl: '/models/spherical_robot.glb',
    engine: 'trellis-2',
    likes: 89,
    faces: 32000
  }),
  make({
    name: 'Japanese Ramen Stall Counter',
    prompt: 'A clean isolated 3D diorama model render of a miniature Japanese ramen counter food stall with red lanterns and steaming bowls on round wooden base, isolated on pure solid black studio background, no background clutter, octane render 8k',
    seedShape: 'prop',
    tint: '#E11D48',
    thumbUrl: '/images/explore/rodin_clean_ramen.jpg',
    modelUrl: '/models/ramen_stall.glb',
    engine: 'hybrid',
    likes: 104,
    faces: 54000
  }),
  make({
    name: 'Calico Boba Milk Tea Cat',
    prompt: 'A cute 3D character model render of a chubby calico cat mascot wearing a miniature straw hat, drinking from a giant boba milk tea cup with tapioca pearls and a pink straw, glossy eyes, Pixar 3D animated style, dark reflective studio floor, soft studio lighting, 8k',
    seedShape: 'creature',
    tint: '#F59E0B',
    thumbUrl: '/images/explore/rodin_boba_cat_1788235650982.jpg',
    modelUrl: '/models/boba_cat.glb',
    engine: 'hunyuan3d-2.1',
    likes: 136,
    faces: 44000
  }),
  make({
    name: 'Chibi Lunar Explorer Astronaut',
    prompt: 'A 3D character model render of an adorable chibi astronaut child in a glossy white space suit with a clear bubble helmet, floating gently while holding a glowing miniature yellow moon on a ribbon like a balloon, dark space studio backdrop with soft starry bokeh, 8k Pixar style',
    seedShape: 'figure',
    tint: '#3B82F6',
    thumbUrl: '/images/explore/rodin_chibi_astronaut_1788235666098.jpg',
    modelUrl: '/models/chibi_astronaut.glb',
    engine: 'trellis-2',
    likes: 76,
    faces: 46000
  }),
  make({
    name: 'Retro Surf Camper Van',
    prompt: 'A 3D model render of a cute retro pastel teal and cream vintage camper van with surfboards mounted on roof rack, rounded stylized curves, shiny chrome bumper, dark reflective studio floor, cinematic studio lighting, Pixar style 3D vehicle asset, 8k',
    seedShape: 'vehicle',
    tint: '#14B8A6',
    thumbUrl: '/images/explore/rodin_retro_van_1788235619578.jpg',
    modelUrl: '/models/retro_camper_van.glb',
    engine: 'trellis-2',
    likes: 92,
    faces: 52000
  }),
  make({
    name: 'Glowing Magma Volcanic Cube',
    prompt: 'Floating volcanic magma obsidian stone cube with glowing fiery yellow energy cracks, dark reflective floor, cinematic rim lighting, 3D game asset, octane render, 8k',
    seedShape: 'prop',
    tint: '#EAB308',
    thumbUrl: '/images/explore/rodin_magma_cube_1788231853691.jpg',
    modelUrl: '/models/magma_cube.glb',
    engine: 'trellis-2',
    likes: 67,
    faces: 28000
  }),
  make({
    name: 'Celestial Paladin Knight',
    prompt: 'Chibi gold knight paladin in glowing royal blue and gold armor, holding radiant energy broadsword and lion crest shield, dark reflective floor, 3D character asset, 8k',
    seedShape: 'figure',
    tint: '#3B82F6',
    thumbUrl: '/images/explore/rodin_gold_knight_1788231866815.jpg',
    modelUrl: '/models/gold_paladin.glb',
    engine: 'hybrid',
    likes: 71,
    faces: 58000
  }),
  make({
    name: 'Fantasy Castle Watchtower',
    prompt: 'Stylized fantasy stone castle watchtower with glowing crystal torches, blue banner crests, wooden door, isometric 3D game diorama, dark studio background, 8k',
    seedShape: 'prop',
    tint: '#64748B',
    thumbUrl: '/images/explore/rodin_castle_tower_1788231881399.jpg',
    modelUrl: '/models/castle_tower.glb',
    engine: 'hybrid',
    likes: 96,
    faces: 64000
  })
];

export const FILTERS = ['Featured', 'Newest', 'Most liked', 'Image to 3D', 'Text to 3D', 'Hunyuan3D', 'TRELLIS.2'] as const;
