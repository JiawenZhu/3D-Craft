"""Offline regression tests for references actually delivered to the providers."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from PIL import Image
from server.engines.base import GenRequest
from server.engines.trellis import TrellisEngine
from server.engines.hunyuan import HunyuanEngine, HunyuanWhiteEngine
from server.engines.rodin import RodinEngine
from server import gemini, pipelines


class ReferenceContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.images = []
        for i in range(4):
            p = self.root / f'view{i}.png'
            Image.new('RGB', (16, 16), (i * 60, 0, 0)).save(p)
            self.images.append(p)

    def invoke(self, engine, req):
        with patch('server.engines.fal_api.available', return_value=(True, 'test')), \
             patch('server.engines.fal_api.upload', side_effect=lambda p: str(p)), \
             patch('server.engines.fal_api.run', return_value={'model_mesh': {'url': 'https://test/model.glb'}, 'model_glb': {'url': 'https://test/model.glb'}}) as call, \
             patch('server.engines.fal_api.download', return_value=self.root / 'model.glb'):
            fn = engine.generate if isinstance(engine, RodinEngine) else engine._generate_fal
            fn(req, self.root / 'out', lambda *_: None)
            return call.call_args.args[:2]

    def test_trellis_preserves_every_reference(self):
        endpoint, args = self.invoke(TrellisEngine(), GenRequest(images=self.images))
        self.assertTrue(endpoint.endswith('/multi'))
        self.assertEqual(len(set(args['image_urls'])), 4)
        self.assertNotIn('image_url', args)
        self.assertEqual(endpoint, 'fal-ai/trellis-2/multi')
        self.assertNotIn('multiimage_algo', args)
        self.assertEqual(args['resolution'],1024)

    def test_single_image_contract_unchanged(self):
        endpoint, args = self.invoke(TrellisEngine(), GenRequest(images=self.images[:1]))
        self.assertNotIn('image_urls', args)
        self.assertIn('image_url', args)

    def test_trellis2_parameters_match_priced_resolution(self):
        from server import pricing
        for effort, resolution, usd in [('low',512,.25),('high',1024,.30),('extreme-high',1536,.35)]:
            endpoint, args = self.invoke(TrellisEngine(), GenRequest(images=self.images[:1],effort=effort))
            self.assertEqual(endpoint,'fal-ai/trellis-2')
            self.assertEqual(args['resolution'],resolution)
            self.assertIn('shape_slat_sampling_steps',args)
            self.assertIn('tex_slat_sampling_steps',args)
            self.assertNotIn('slat_sampling_steps',args)
            self.assertNotIn('mesh_simplify',args)
            self.assertEqual(pricing.model_quote('trellis-2',effort=effort)['totalUsd'],usd)

    def test_hunyuan_uses_labels_even_when_order_changes(self):
        endpoint, args = self.invoke(HunyuanEngine(), GenRequest(images=self.images[:3], directions=['left','front','back']))
        self.assertIn('/multi-view', endpoint)
        self.assertIn('view0', args['left_image_url'])
        self.assertIn('view1', args['front_image_url'])
        self.assertIn('view2', args['back_image_url'])

    def test_white_mesh_forces_texture_off_without_losing_views(self):
        base = HunyuanEngine()
        req = GenRequest(images=self.images[:3], directions=['left','front','back'], texture=True)
        with patch.object(base, 'generate') as generate:
            HunyuanWhiteEngine(base).generate(req, self.root, lambda *_:None)
        actual = generate.call_args.args[0]
        self.assertFalse(actual.texture)
        self.assertTrue(req.texture)
        self.assertEqual(actual.images,req.images)
        self.assertEqual(actual.directions,req.directions)

    def test_hunyuan_never_invents_missing_views(self):
        for dirs in [['front','front','left'], ['front','right','left'], ['front','front-left','back'], ['front','back']]:
            with self.subTest(dirs=dirs), patch('server.engines.fal_api.upload') as upload:
                with self.assertRaises(ValueError):
                    HunyuanEngine()._generate_fal(GenRequest(images=self.images[:len(dirs)], directions=dirs),self.root,lambda *_:None)
                upload.assert_not_called()

    def test_rodin_uses_concat_for_turnaround(self):
        _, args = self.invoke(RodinEngine(), GenRequest(images=self.images, prompt="Preserve the glasses and face shape"))
        self.assertEqual(args['condition_mode'], 'concat')
        self.assertEqual(len(args['input_image_urls']),4)
        self.assertEqual(args['prompt'], "Preserve the glasses and face shape")

    def test_failed_generated_view_does_not_shift_directions(self):
        references=[]
        def render(prompt, refs):
            references.append([p.read_bytes() for p in refs])
            if '180 degree' in prompt:
                raise gemini.GeminiError('failed back')
            return {'bytes': self.images[1].read_bytes(), 'mime':'image/png','ms':1}
        with patch.object(gemini,'make_image',side_effect=render), patch.object(gemini,'assess_turnaround',return_value={'usable':True,'issues':[]}):
            result=gemini.make_concept_set('',self.images[0],4,base_prompt='a toy')
        self.assertEqual([i['direction'] for i in result['images']],['front','left','right'])
        self.assertEqual(len(result['warnings']),1)
        self.assertEqual(references[0],[self.images[0].read_bytes()])
        for refs in references[1:]:
            self.assertEqual(refs,[self.images[1].read_bytes()])

    def test_pipeline_without_source_selects_first_generated_view(self):
        doc={'id':'test','input':{'prompt':'toy'},'nodes':[{'kind':'source'},{'kind':'prompt','text':'toy'},{'kind':'concept'}]}
        result={'images':[{'label':d,'direction':d,'bytes':self.images[0].read_bytes(),'mime':'image/png'} for d in ['front','back']], 'total_ms':1,'validation':{'usable':True,'issues':[]}}
        with patch.object(pipelines,'_set',side_effect=lambda doc,kind,**kw:pipelines._node(doc,kind).update(kw)), \
             patch.object(pipelines,'_run_dir',return_value=self.root), \
             patch.object(gemini,'make_concept_set',return_value=result):
            pipelines._stage_concept(doc)
        self.assertTrue(pipelines._node(doc,'concept')['imageUrl'].endswith('concept_0.png'))
        self.assertEqual(pipelines._node(doc,'concept')['reconstructionMode'],'multi')

    def test_pipeline_sends_all_checked_views_but_single_when_rejected(self):
        for usable in [True, False]:
            with self.subTest(usable=usable):
                doc={'id':'test','title':'toy','input':{'prompt':'toy'},'settings':{'engine':'trellis-2'},
                     'nodes':[{'kind':'prompt'},{'kind':'concept','imageUrl':'/runs/test/view0.png',
                               'reconstructionMode':'multi' if usable else 'single',
                               'images':[{'url':f'/runs/test/view{i}.png','direction':d} for i,d in enumerate(['front','back','left','right'])]},
                              {'kind':'model3d'}]}
                with patch.object(pipelines,'_set',side_effect=lambda doc,kind,**kw:pipelines._node(doc,kind).update(kw)), \
                     patch.object(pipelines,'_run_dir',return_value=self.root), \
                     patch.object(pipelines.time,'sleep'), \
                     patch.object(pipelines.jobs,'submit',return_value='test-job') as submit, \
                     patch.object(pipelines.jobs,'get_job',return_value={'stage':'done','progress':100,'message':'done','assetIds':[]}):
                    pipelines._stage_model(doc)
                req=submit.call_args.args[1]
                self.assertEqual(len(req.images),4 if usable else 1)
                self.assertEqual(req.directions,['front','back','left','right'] if usable else ['unknown'])

    def test_failed_consistency_check_fails_closed(self):
        with patch.object(gemini,'make_image',return_value={'bytes':self.images[0].read_bytes(),'mime':'image/png','ms':1}), \
             patch.object(gemini,'assess_turnaround',side_effect=RuntimeError('service unavailable')):
            result=gemini.make_concept_set('',self.images[0],count=2,base_prompt='toy')
        self.assertFalse(result['validation']['usable'])
        self.assertTrue(result['warnings'])

    def test_viewset_fallback_clears_previous_multiview_state(self):
        doc={'id':'test','input':{'prompt':'toy'},'nodes':[{'kind':'source'},{'kind':'prompt','text':'toy'},
             {'kind':'concept','reconstructionMode':'multi','validation':{'usable':True},'warnings':['old warning']}]}
        with patch.object(pipelines,'_set',side_effect=lambda doc,kind,**kw:pipelines._node(doc,kind).update(kw)), \
             patch.object(pipelines,'_run_dir',return_value=self.root), \
             patch.object(gemini,'make_concept_set',side_effect=RuntimeError('view generation failed')), \
             patch.object(gemini,'make_image',return_value={'bytes':self.images[0].read_bytes(),'mime':'image/png','ms':1}):
            pipelines._stage_concept(doc)
        node=pipelines._node(doc,'concept')
        self.assertEqual(node['reconstructionMode'],'single')
        self.assertIsNone(node['validation'])
        self.assertEqual(len(node['images']),1)
        self.assertNotIn('old warning',node['warnings'])

if __name__ == '__main__': unittest.main()
