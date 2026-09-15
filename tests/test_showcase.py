import json
from unittest.mock import patch
from tests.test_paid_access import PaidAccessTests
from server import mobile, showcase
from fastapi import FastAPI
from fastapi.testclient import TestClient

class ShowcaseTests(PaidAccessTests):
    def test_library_only_returns_signed_in_owners_creations_without_purchase(self):
        app=FastAPI();app.include_router(showcase.router);client=TestClient(app)
        self.assertEqual(client.get('/api/showcase/library').status_code,401)
        with mobile.connect() as c:
            for owner in ['alice','bob']:
                item={'id':owner,'name':owner+' creation','imageUrl':'/files/mobile/'+owner+'.png','createdAt':1}
                c.execute('INSERT INTO concepts VALUES(?,?,?,?)',(owner,'firebase:'+owner,'project',json.dumps(item)))
            original={'id':'original','isOriginal':True,'imageUrl':'/files/mobile/photo.png'}
            c.execute('INSERT INTO concepts VALUES(?,?,?,?)',('original','firebase:alice','project',json.dumps(original)))
        with self.claims():
            response=client.get('/api/showcase/library',headers=self.headers)
            self.assertEqual(response.status_code,200)
            self.assertEqual([x['id'] for x in response.json()],['concept:alice'])
            self.assertEqual(mobile.wallet('firebase:alice')['available'],0)
            self.assertEqual(client.get('/api/showcase/library/concept:bob/image',headers=self.headers).status_code,404)
    def test_media_cannot_escape_storage(self):
        app=FastAPI();app.include_router(showcase.router);client=TestClient(app)
        with self.claims(),patch.object(showcase,'items',return_value=[{'id':'bad','image':'/files/../../secrets.png'}]):
            self.assertEqual(client.get('/api/showcase/library/bad/image',headers=self.headers).status_code,404)
    def test_device_claim_requires_credential_and_never_moves_demo_money(self):
        import hashlib
        from server import cloud_library
        app=FastAPI();app.include_router(cloud_library.router);client=TestClient(app)
        token='x'*40
        with mobile.connect() as c:
            c.execute('INSERT INTO users VALUES(?,?,?,?)',('old-device',hashlib.sha256(token.encode()).hexdigest(),999,45))
            c.execute('INSERT INTO concepts VALUES(?,?,?,?)',('old-concept','old-device','project',json.dumps({'id':'old-concept'})))
        with self.claims():
            self.assertEqual(client.post('/api/mobile/cloud-library/claim-device',headers=self.headers,json={'deviceToken':'wrong'*8}).status_code,404)
            for _ in range(2):
                self.assertEqual(client.post('/api/mobile/cloud-library/claim-device',headers=self.headers,json={'deviceToken':token}).status_code,200)
        self.assertEqual(mobile.wallet('firebase:alice')['available'],0)
        self.assertEqual([x['id'] for x in showcase.items('firebase:alice')],['concept:old-concept'])
        with self.claims('bob'):
            self.assertEqual(client.post('/api/mobile/cloud-library/claim-device',headers=self.headers,json={'deviceToken':token}).status_code,409)
    def test_sync_uses_verified_user_token_and_deduplicates_cloud_writes(self):
        from server import cloud_library
        app=FastAPI();app.include_router(cloud_library.router);client=TestClient(app)
        asset={'id':'concept:a','name':'Cat','kind':'Concept image','createdAt':1,'image':None}
        with self.claims(),patch.object(cloud_library,'items',return_value=[asset]),patch.object(cloud_library.requests,'get') as read,patch.object(cloud_library.requests,'patch') as write:
            read.return_value.status_code=404
            write.return_value.status_code=200
            self.assertEqual(client.post('/api/mobile/cloud-library/sync',headers=self.headers).status_code,200)
            self.assertEqual(client.post('/api/mobile/cloud-library/sync',headers=self.headers).json()['synced'],0)
            write.assert_called_once()
            self.assertIn('/users/alice/mobileCreations/',write.call_args.args[0])
            self.assertEqual(write.call_args.kwargs['headers']['Authorization'],self.headers['Authorization'])
    def test_models_link_only_owned_selected_concepts(self):
        with mobile.connect() as c:
            for cid,owner in [('front','alice'),('back','alice'),('foreign','bob')]:
                data={'id':cid,'imageUrl':'/files/'+cid+'.png','createdAt':1}
                c.execute('INSERT INTO concepts VALUES(?,?,?,?)',(cid,'firebase:'+owner,'p',json.dumps(data)))
            job={'id':'job','projectId':'p','selectedConceptIds':['front','foreign','back'],'assets':[{'id':'mesh','modelUrl':'/files/model.glb'}]}
            c.execute('INSERT INTO work VALUES(?,?,?,?,?)',('job','firebase:alice','job','signature',json.dumps(job)))
        model=next(x for x in showcase.items('firebase:alice') if x['kind']=='3D object')
        self.assertEqual(model['conceptIds'],['concept:front','concept:back'])
        self.assertEqual(model['projectId'],'p')
        self.assertTrue(model['selectionKnown'])
    def test_public_catalog_is_complete_and_contains_only_reviewed_assets(self):
        from pathlib import Path
        root=Path(__file__).resolve().parents[1]
        catalog=json.loads((root/'public/gallery/catalog.json').read_text())
        registry=json.loads((root/'server/storage/assets.json').read_text())
        reviewed={x['id'] for x in registry if x.get('galleryExample') and x.get('visibility')=='public'}
        self.assertEqual(len(catalog),20)
        self.assertEqual(len({x['id'] for x in catalog}),20)
        for item in catalog:
            self.assertIn(item['id'],reviewed)
            self.assertTrue((root/'public'/item['modelUrl'].lstrip('/')).is_file())
            self.assertTrue((root/'public'/item['thumbUrl'].lstrip('/')).is_file())
