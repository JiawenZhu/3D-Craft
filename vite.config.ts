import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';
import { copyFile, mkdir, readdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('.', import.meta.url));

// Publish only the optimized comparison media, not the 514 MB of raw 3D test outputs.
function comparisonMedia(): Plugin {
  let output = resolve(root, 'dist');
  const copy = async (source: string, destination: string) => {
    const target = resolve(output, destination);
    await mkdir(dirname(target), { recursive: true });
    await copyFile(resolve(root, source), target);
  };

  return {
    name: 'comparison-media',
    apply: 'build',
    configResolved(config) {
      output = resolve(config.root, config.build.outDir);
    },
    async closeBundle() {
      const imageRoot = 'docs/design/image-to-3d-comparison';
      const videoRoot = 'docs/design/video-provider-comparison';
      const models = ['rodin', 'seed3d', 'tripo', 'hunyuan-rapid', 'hunyuan-pro',
        'hi3d-fast', 'hi3d-pro', 'hi3d-quality', 'hi3d-master', 'meshy-single', 'meshy-multi'];
      const videos = ['mini', 'seedance-2.0', 'seedance-2.5', 'minimax-h3', 'wan-3.0-prime'];
      const thumbnails = (await readdir(resolve(root, imageRoot, 'media')))
        .filter(name => name.startsWith('thumb-') && name.endsWith('.png'));

      await Promise.all([
        copy(`${imageRoot}/results.json`, `${imageRoot}/results.json`),
        copy(`${videoRoot}/sample-results.json`, `${videoRoot}/sample-results.json`),
        copy('docs/design/gallery-samples/cloud-dragon.png', 'docs/design/gallery-samples/cloud-dragon.png'),
        copy('docs/design/mascot-animations/source/cloud-dragon-960.jpg', 'docs/design/mascot-animations/source/cloud-dragon-960.jpg'),
        copy('docs/design/mascot-animations/seedance-log.json', 'docs/design/mascot-animations/seedance-log.json'),
        copy('docs/design/mascot-animations/raw/dragon-thinking.mp4', `${videoRoot}/media/fal-seedance-2.5.mp4`),
        ...thumbnails.map(name => copy(`${imageRoot}/media/${name}`, `${imageRoot}/media/${name}`)),
        ...models.map(name => copy(`ios/CraftStudio/Resources/ModelComparisons/comparison-${name}.glb`, `${imageRoot}/media/${name}.glb`)),
        ...videos.map(name => copy(`${videoRoot}/media/${name}.mp4`, `${videoRoot}/media/${name}.mp4`)),
      ]);
    },
  };
}

export default defineConfig({
  plugins: [react(), comparisonMedia()],
  build: {
    rollupOptions: {
      input: {
        main: resolve(root, 'index.html'),
        imageTo3D: resolve(root, 'docs/design/image-to-3d-comparison/index.html'),
        video: resolve(root, 'docs/design/video-provider-comparison/index.html'),
      },
    },
  },
  server: {
    port: 3000,
    open: false,
  },
});
