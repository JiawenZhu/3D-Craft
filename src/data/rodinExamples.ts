export interface RodinShowcaseItem {
  id: string;
  title: string;
  author: string;
  authorAvatar?: string;
  likes: number;
  imageUrl: string;
  prompt: string;
  polyCount: number;
  category: 'character' | 'prop' | 'architecture' | 'creature' | 'scifi';
}

export type RodinExampleItem = RodinShowcaseItem;

export const RODIN_SHOWCASE_ITEMS: RodinShowcaseItem[] = [
  {
    id: 'showcase-1',
    title: 'Orange Furry Monster',
    author: 'velozetetic',
    likes: 20,
    imageUrl: '/images/gallery/orange_creature.jpg',
    prompt: 'Cute orange furry rabbit monster creature wearing beige overalls, standing pose, 3D character game asset, Pixar Disney style, dark reflective studio floor, soft rim lighting, octane render, 8k',
    polyCount: 42000,
    category: 'character'
  },
  {
    id: 'showcase-2',
    title: 'Glowing Magma Cube',
    author: 'David Austin',
    likes: 11,
    imageUrl: '/images/gallery/magma_cube.jpg',
    prompt: 'Floating volcanic magma obsidian stone cube with glowing fiery yellow energy cracks, dark reflective floor, cinematic rim lighting, 3D game asset, octane render, 8k',
    polyCount: 28400,
    category: 'scifi'
  },
  {
    id: 'showcase-3',
    title: 'Medieval Stone Cottage',
    author: 'mynameisn',
    likes: 10,
    imageUrl: '/images/gallery/stone_cottage.jpg',
    prompt: 'Stylized medieval stone cottage house on miniature grass round base, glowing warm windows, slate roof, 3D diorama game asset, dark studio backdrop, 8k',
    polyCount: 36000,
    category: 'architecture'
  },
  {
    id: 'showcase-4',
    title: 'Ancient Taiko Drum',
    author: 'xgx781117',
    likes: 8,
    imageUrl: '/images/gallery/taiko_drum.jpg',
    prompt: 'Traditional ancient Japanese wooden taiko drum on dark timber stand, weathered leather skin, brass rings, dark studio lighting, 3D asset render, 8k',
    polyCount: 24500,
    category: 'prop'
  },
  {
    id: 'showcase-5',
    title: 'Fluffy Beanbag Chair',
    author: 'cchhyy',
    likes: 14,
    imageUrl: '/images/gallery/beanbag_chair.jpg',
    prompt: 'Plush fluffy white puffy beanbag armchair, soft wrinkles, modern minimalist furniture, dark studio backdrop with soft shadows, 3D product render, 8k',
    polyCount: 19800,
    category: 'prop'
  },
  {
    id: 'showcase-6',
    title: 'Fruit Market Stall',
    author: '460373',
    likes: 5,
    imageUrl: '/images/gallery/market_stall.jpg',
    prompt: 'Stylized miniature wooden fruit market stall with orange and white striped canopy, crates of fresh apples, 3D diorama asset, dark reflective floor, 8k',
    polyCount: 31200,
    category: 'prop'
  },
  {
    id: 'showcase-7',
    title: 'Cherry Pudding Cake',
    author: '刘 佳康',
    likes: 5,
    imageUrl: '/images/gallery/pudding_cake.jpg',
    prompt: 'Cute glossy chocolate pudding cake dessert with whipped cream and red cherry on top, yellow polka dots, 3D stylized food asset, dark studio lighting, 8k',
    polyCount: 18200,
    category: 'prop'
  },
  {
    id: 'showcase-8',
    title: 'Celestial Paladin Knight',
    author: 'Muslim',
    likes: 71,
    imageUrl: '/images/gallery/gold_paladin.jpg',
    prompt: 'Chibi gold knight paladin in glowing royal blue and gold armor, holding radiant energy broadsword and lion crest shield, dark reflective floor, 3D character asset, 8k',
    polyCount: 54000,
    category: 'character'
  },
  {
    id: 'showcase-9',
    title: 'Castle Watchtower',
    author: 'plgasc',
    likes: 96,
    imageUrl: '/images/gallery/castle_tower.jpg',
    prompt: 'Stylized fantasy stone castle watchtower with glowing crystal torches, blue banner crests, wooden door, isometric 3D game diorama, dark studio background, 8k',
    polyCount: 62000,
    category: 'architecture'
  },
  {
    id: 'showcase-10',
    title: 'Gothic Bunny Plushie',
    author: 'anoliss',
    likes: 37,
    imageUrl: '/images/gallery/gothic_bunny.jpg',
    prompt: 'Dark gothic bunny plush doll in black and crimson hoodie, stitched details, button eyes, cute creepy aesthetic, dark studio lighting, 3D asset render, 8k',
    polyCount: 33400,
    category: 'character'
  },
  {
    id: 'showcase-11',
    title: 'Retro CRT Television',
    author: 'Flix Mohanad',
    likes: 27,
    imageUrl: '/images/gallery/retro_tv.jpg',
    prompt: 'Vintage 1980s retro CRT television set with glowing vibrant RGB color test bars screen, antenna on top, dark reflective floor, 3D prop asset, 8k',
    polyCount: 22400,
    category: 'prop'
  },
  {
    id: 'showcase-12',
    title: 'Horned Demon Skull Mask',
    author: 'Zonafarm',
    likes: 67,
    imageUrl: '/images/gallery/demon_mask.jpg',
    prompt: 'Menacing red horned demon skull mask with glowing fiery yellow eyes, curling mustache, white face paint, dark studio background, 3D sculpting asset, 8k',
    polyCount: 46500,
    category: 'creature'
  }
];
