"""No paid generation: verify durable submission and scoped gallery metadata."""
import importlib.util
import json
import hashlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
import httpx
from PIL import Image
from fastapi import FastAPI
from fastapi.testclient import TestClient
from server import gallery

spec=importlib.util.spec_from_file_location('gallery_samples',Path(__file__).resolve().parents[1]/'scripts/generate_gallery_samples.py')
script=importlib.util.module_from_spec(spec);spec.loader.exec_module(script)


class GalleryTests(unittest.TestCase):
    def test_uncertain_submission_is_saved_before_request_and_never_repeated(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'docs/design/gallery-samples/cat.png';source.parent.mkdir(parents=True)
            Image.new('RGB',(512,512),'white').save(source)
            entry={'slug':'test-cat','name':'Cat','kind':'character','description':'A test cat','conceptPath':str(source),'status':'ready'}
            manifest={'batchId':'test-batch','samples':[entry]};path=root/'manifest.json'
            client=Mock()
            def submit(*a,**kw):
                saved=json.loads(path.read_text())['samples'][0]
                self.assertEqual(saved['status'],'submitting')
                self.assertIn('submissionAttemptedAt',saved)
                raise httpx.ReadTimeout('Ambiguous connection')
            client.post.side_effect=submit
            with patch.object(script,'ROOT',root):
                script.submit(client,'http://127.0.0.1:8001',entry,manifest,path)
                script.submit(client,'http://127.0.0.1:8001',entry,manifest,path)
            self.assertEqual(entry['status'],'uncertain')
            self.assertEqual(client.post.call_count,1)

    def test_existing_asset_reconciles_without_a_new_generation(self):
        entry={'slug':'test-cat','sourceRef':'gallery:test:test-cat','status':'uncertain'}
        asset={'id':'a-existing','sourceRef':entry['sourceRef']}
        with patch.object(script,'annotate') as annotate:
            script.reconcile(Mock(),'http://127.0.0.1:8001',entry,{},Path('/tmp/not-written'),[asset])
            annotate.assert_called_once()

    def test_a_thumbnail_or_invalid_mesh_is_not_marked_as_a_completed_model(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);path=root/'manifest.json';entry={'slug':'test-cat'};manifest={'samples':[entry]}
            client=Mock()
            with patch.object(script,'ROOT',root):
                script.annotate(client,'http://127.0.0.1:8001',entry,{'id':'a-test','engine':'rodin','modelUrl':'/files/a-test/model.glb','faces':100},manifest,path)
            self.assertEqual(entry['status'],'needs-review')
            client.post.assert_not_called()

    def test_mobile_examples_include_only_public_curated_assets_and_preserve_owned(self):
        from server import mobile
        curated=[{'id':f'gallery-{i}','galleryExample':{'slug':str(i)}} for i in range(20)]
        older=[{'id':f'other-user-{i}'} for i in range(30)]
        private={'id':'private-curated','galleryExample':{'slug':'private'},'visibility':'private'}
        owned={'id':'my-dog','name':'My dog','modelUrl':'/files/my-dog/model.glb'}
        with patch.object(mobile,'list_work',return_value=[{'assets':[owned]}]),patch.object(mobile.jobs,'list_assets',return_value=older+curated+[owned,private]),patch.object(mobile.thumbnails,'decorate',side_effect=lambda asset:asset):
            result=mobile.assets('owner')
        self.assertEqual([a['id'] for a in result['examples']],[a['id'] for a in curated])
        self.assertEqual(len(result['examples']),20)
        self.assertEqual(result['owned'],[owned])
        self.assertTrue(all(a['ownership']=='example' for a in result['examples']))

    def test_annotation_requires_exact_submission_and_original_concept_hash(self):
        app=FastAPI();app.include_router(gallery.router);client=TestClient(app)
        with tempfile.TemporaryDirectory() as directory:
            source=Path(directory)/'gallery-samples/test-cat.png';source.parent.mkdir()
            source.write_bytes(b'concept')
            body={'name':'Test Cat','kind':'character','description':'Test description','sourceImageUrl':'/files/gallery-samples/test-cat.png',
                  'galleryExample':{'batchId':'test-batch','slug':'test-cat','conceptSha256':hashlib.sha256(b'concept').hexdigest(),'description':'Test description'}}
            with patch.object(gallery,'STORAGE',Path(directory)),patch.object(gallery.jobs,'list_assets',return_value=[{'id':'a-test','sourceRef':'gallery:test-batch:test-cat'}]),patch.object(gallery.jobs,'annotate_asset') as annotate:
                self.assertEqual(client.post('/api/assets/a-test/gallery-example',json=body).status_code,200)
                self.assertEqual(annotate.call_args.args[1]['sourceImageUrl'],body['sourceImageUrl'])
                body['galleryExample']['slug']='other-cat'
                self.assertEqual(client.post('/api/assets/a-test/gallery-example',json=body).status_code,409)
                self.assertEqual(annotate.call_count,1)


if __name__=='__main__':unittest.main()
