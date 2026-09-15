"""Package only reviewed public examples; never include user-owned creations."""
import json, shutil
from pathlib import Path
from PIL import Image, ImageOps
ROOT = Path(__file__).resolve().parents[1]
def build():
    source = ROOT / 'server/storage'
    registry = json.loads((source / 'assets.json').read_text())
    catalog = json.loads((ROOT / 'docs/design/gallery-samples/catalog.json').read_text())
    dest = ROOT / 'public/gallery'; bundle = ROOT / 'ios/CraftStudio/Resources/PublicGallery'
    dest.mkdir(parents=True, exist_ok=True); bundle.mkdir(parents=True, exist_ok=True)
    records = []
    for order, entry in enumerate(catalog):
        slug = entry['slug']
        asset = next(a for a in registry if a.get('visibility') == 'public' and isinstance(a.get('galleryExample'),dict) and a['galleryExample'].get('slug') == slug)
        model = (source / asset['modelUrl'].removeprefix('/files/')).resolve()
        assert model.is_relative_to(source.resolve()) and model.is_file()
        with Image.open(source / 'gallery-samples' / (slug+'.png')) as im:
            im = ImageOps.exif_transpose(im).convert('RGB'); im.thumbnail((1000,1000))
            im.save(dest / (slug+'.jpg'), quality=88)
        shutil.copy2(dest / (slug+'.jpg'), bundle / (slug+'.jpg'))
        shutil.copy2(model, dest / (slug+'.glb'))
        records.append(dict(id=asset['id'],name=entry['name'],kind=entry['kind'],prompt=entry['description'],
            galleryExample=True,galleryOrder=order,isExample=True,
            modelUrl='/gallery/'+slug+'.glb',thumbUrl='/gallery/'+slug+'.jpg',sourceImageUrl='/gallery/'+slug+'.jpg',
            faces=asset.get('faces',0),fileSizeMb=round(model.stat().st_size/1e6,2)))
    text=json.dumps(records,indent=2)
    (dest / 'catalog.json').write_text(text)
    (bundle / 'public-gallery.json').write_text(text)
    print(f'Packaged {len(records)} reviewed public examples.')
if __name__=='__main__': build()
