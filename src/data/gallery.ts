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
    textureRes: 2048,
    fileSizeMb: Math.round((faces / 9000) * 10) / 10,
    liked: false,
    likes: 3 + ((n * 13) % 28),
    author: ['velozetetic', 'Tiffany Hood', 'David Austin', 'mynameisn', 'kaz_studio', 'Ivo R.'][n % 6],
    visibility: 'public',
    local: false,
    ...a,
  };
};

/** The EXPLORE feed — community-style cards, same shape as locally generated ones. */
export const EXPLORE_ASSETS: Asset[] = [
  make({ name: 'Ember Fox Totem', prompt: 'a stylized orange fox totem carved from warm stone, game asset', seedShape: 'creature', tint: '#e0864b', engine: 'hunyuan3d-2.1' }),
  make({ name: 'Wanderer Diorama', prompt: 'tiny diorama of a lone traveller on a floating island, painterly', seedShape: 'prop', tint: '#c09a6b' }),
  make({ name: 'Aurora Cube', prompt: 'glowing translucent cube with volumetric aurora trapped inside', seedShape: 'prop', tint: '#8771ff' }),
  make({ name: 'Kitbash Rover', prompt: 'six wheeled exploration rover, kitbashed panels, weathered', seedShape: 'vehicle', tint: '#7cb5df', engine: 'trellis-2' }),
  make({ name: 'Hollow Knight Idol', prompt: 'small porcelain knight idol with a cracked mask, subsurface', seedShape: 'figure', tint: '#d9d2c5' }),
  make({ name: 'Reliquary Mech', prompt: 'gothic reliquary mech, brass filigree over black carbon', seedShape: 'mech', tint: '#caa14e', engine: 'hunyuan3d-2.1' }),
  make({ name: 'Moss Golem', prompt: 'mossy stone golem with glowing lichen veins, hand painted', seedShape: 'creature', tint: '#6f9a63' }),
  make({ name: 'Deco Lamp 04', prompt: 'art deco table lamp, fluted brass and opal glass shade', seedShape: 'prop', tint: '#b98d5f' }),
  make({ name: 'Sable Courier', prompt: 'lightweight courier drone with folded rotor arms, matte black', seedShape: 'vehicle', tint: '#5f6470' }),
  make({ name: 'Tide Priestess', prompt: 'ocean priestess in flowing coral robes, stylized proportions', seedShape: 'figure', tint: '#5aa6c0', engine: 'hybrid' }),
  make({ name: 'Cinder Beetle', prompt: 'armored beetle with cracked obsidian shell and ember glow', seedShape: 'creature', tint: '#c4553a' }),
  make({ name: 'Atlas Frame', prompt: 'heavy industrial exo-frame, hydraulic legs, hazard stripes', seedShape: 'mech', tint: '#d18b2f', engine: 'trellis-2' }),
];

export const FILTERS = ['Featured', 'Newest', 'Most liked', 'Image to 3D', 'Text to 3D', 'Hunyuan3D', 'TRELLIS.2'] as const;
