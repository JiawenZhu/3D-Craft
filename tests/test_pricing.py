import unittest
from datetime import date
from unittest.mock import patch
from server import pricing


class PricingTests(unittest.TestCase):
    def test_trellis2_resolution_pricing_matches_rodin_ratio(self):
        models = pricing.catalog()['models']
        for effort, usd, tokens in [('low',.25,29),('high',.30,35),('extreme-high',.35,41)]:
            quote = pricing.model_quote('trellis-2', effort=effort)
            self.assertEqual(quote['totalUsd'],usd)
            self.assertEqual(quote['usageWithServiceFee']['credits'],tokens)
            self.assertEqual(models['trellis-2']['effortCredits'][effort],tokens)
        self.assertEqual(pricing.model_quote('rodin',effort='extreme-high')['usageWithServiceFee']['credits'],46)
        self.assertEqual(pricing.model_quote('hunyuan3d-2.1',texture=False)['usageWithServiceFee']['credits'],19)

    def test_app_token_catalog_matches_quotes_and_rounds_up(self):
        models=pricing.catalog()["models"]
        for engine, expected in [("rodin",46),("trellis-2",35),("hunyuan3d-2.1",56),("hybrid",90)]:
            self.assertEqual(models[engine]["texturedCredits"],expected)
            self.assertEqual(pricing.model_quote(engine)["usageWithServiceFee"]["credits"],expected)
        self.assertEqual(models["rodin"]["multiTexturedCredits"],46)
        self.assertEqual(models["trellis-2"]["multiTexturedCredits"],35)

    def test_rodin_batch_and_known_addon(self):
        quote = pricing.model_quote('rodin', count=3, views=4)
        self.assertEqual(quote['totalUsd'], 1.20)
        self.assertEqual(quote['optionsUsd'], 0)
        pack = pricing.model_quote('rodin', count=2, high_pack=True)
        self.assertEqual(pack['totalUsd'], 2.40)
        self.assertEqual(pack['optionsUsd'], .80)

    def test_texture_surcharge_and_hybrid_stages(self):
        self.assertEqual(pricing.model_quote('hunyuan3d-2.1', texture=False)['totalUsd'], .16)
        self.assertEqual(pricing.model_quote('hunyuan3d-2.1')['optionsUsd'], .32)
        self.assertEqual(pricing.model_quote('hybrid')['totalUsd'], .78)
        self.assertEqual(pricing.model_quote('hybrid', texture=False)['totalUsd'], .30)

    def test_unknown_is_not_free(self):
        for engine in ['future-model','gemini-3-pro-image','codex-gpt-image-2']:
            self.assertIsNone(pricing.model_quote(engine)['totalUsd'])
        self.assertIsNone(pricing.model_quote('rodin', addons=['unknown'])['totalUsd'])
        self.assertEqual(pricing.model_quote('hunyuan3d-2.1', views=3)['totalUsd'], .051)
        self.assertIsNone(pricing.model_quote('trellis-2', high_pack=True)['totalUsd'])

    def test_endpoint_override_invalidates_quote(self):
        with patch.dict(pricing.FAL_ENDPOINTS, {'trellis-2':'fal-ai/trellis'}):
            self.assertIsNone(pricing.model_quote('trellis-2')['totalUsd'])
            self.assertIsNone(pricing.model_quote('hybrid')['totalUsd'])
        with patch.object(pricing, 'GEMINI_IMAGE_MODEL', 'future-image'):
            self.assertEqual(pricing.catalog()['models']['gemini-3-pro-image']['unit'], 'unknown')

    def test_introductory_rate_expiry_and_image_output(self):
        current=pricing.catalog(date(2026,12,31))['models']
        later=pricing.catalog(date(2027,1,1))['models']
        self.assertEqual(current['gemini-3.8-flash']['inputPerMillion'], .75)
        self.assertEqual(later['gemini-3.8-flash']['inputPerMillion'], 1.50)
        self.assertEqual(later['gemini-3.8-flash']['outputPerMillion'], 7.50)
        self.assertEqual(current['gemini-3-pro-image']['unitUsd'], .134)
        self.assertEqual(current['gemini-3-pro-image']['fourKUsd'], .24)
        self.assertEqual(current['codex-gpt-image-2']['unitUsd'], 0)

    def test_white_mesh_is_separately_priced_and_multiview_is_verified(self):
        for engine, single, multi in [("hunyuan3d-2-white",19,2),("hunyuan3d-2.1",56,6)]:
            self.assertEqual(pricing.model_quote(engine)["usageWithServiceFee"]["credits"],single)
            self.assertEqual(pricing.model_quote(engine,views=3)["usageWithServiceFee"]["credits"],multi)
        with patch.dict(pricing.FAL_ENDPOINTS,{"hunyuan3d-2.1-mv":"unknown"}):
            self.assertIsNone(pricing.model_quote("hunyuan3d-2-white",views=3)["totalUsd"])
            self.assertEqual(pricing.model_quote("hunyuan3d-2-white")["totalUsd"],.16)

    def test_multiview_fixed_resolution_cost_and_override(self):
        for effort in ['low','high','extreme-high']:
            self.assertEqual(pricing.model_quote('trellis-2',views=3,effort=effort)['totalUsd'],.30)
            self.assertEqual(pricing.model_quote('hybrid',views=3,effort=effort)['totalUsd'],.351)
        with patch.dict(pricing.FAL_ENDPOINTS,{'trellis-multi':'unknown'}):
            self.assertIsNone(pricing.model_quote('trellis-2',views=3)['totalUsd'])
            self.assertIsNone(pricing.model_quote('hybrid',views=3)['totalUsd'])

    def test_invalid_quantity(self):
        for count in [0,-1,1.5]:
            with self.assertRaises(ValueError): pricing.model_quote('rodin',count=count)
