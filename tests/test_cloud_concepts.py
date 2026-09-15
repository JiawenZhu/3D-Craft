import base64,io,unittest
from unittest.mock import patch
from decimal import Decimal
from PIL import Image
from fastapi.testclient import TestClient
from pydantic import ValidationError
from server import cloud_concept_provider as p, firebase_api as api
from server.firebase_concepts import ConceptRequest

class ConceptTests(unittest.TestCase):
    def test_usage_separates_image_and_thinking_and_caps_quote(self):
        raw=io.BytesIO();Image.new('RGB',(2048,2048)).save(raw,format='PNG')
        result={'candidates':[{'finishReason':'STOP','content':{'parts':[{'inlineData':{'mimeType':'image/png','data':base64.b64encode(raw.getvalue()).decode()}}]}}],
                'usageMetadata':{'promptTokenCount':33,'candidatesTokenCount':1120,'thoughtsTokenCount':262,'candidatesTokensDetails':[{'modality':'IMAGE','tokenCount':1120}]}}
        ref=p.body('Preserve this reference',raw.getvalue())['contents'][0]['parts'][0]['inlineData']['data']
        with Image.open(io.BytesIO(base64.b64decode(ref))) as preserved:self.assertEqual(preserved.size,(2048,2048))
        decoded=p.decode(result,p.RATES)
        self.assertEqual(decoded['tokens'],16);self.assertEqual(Decimal(decoded['providerUsd']),Decimal('.137610'))
        self.assertEqual(p.quote(0)['maxTokens'],33)
        self.assertEqual(p.quote(0,4)['maxTokens'],128)
        result['usageMetadata']['candidatesTokensDetails']=[]
        with self.assertRaises(p.planner.PlannerError):p.decode(result,p.RATES)
        result['candidates'][0]['finishReason']='MAX_TOKENS'
        with self.assertRaises(p.planner.PlannerError):p.decode(result,p.RATES)

    def test_spending_consent_model_and_view_contract(self):
        for body in ({'idempotencyKey':'request-1'}, {'idempotencyKey':'request-1','maxTokens':33,'count':True},
                     {'idempotencyKey':'request-1','maxTokens':33,'imageModel':'codex-gpt-image-2'}):
            with self.assertRaises(ValidationError):ConceptRequest(**body)
        self.assertIn('directly behind',p.view_prompt('red frame',1,'angles','Realistic'))
        self.assertIn('preserve all unmentioned identity',p.view_prompt('yellow canopy',0,'refine','Realistic'))
        with patch.object(p,'call',return_value={'totalTokens':p.MAX_INPUT+1}):
            with self.assertRaises(p.planner.PlannerError):p.preflight(p.body('x'))

    def test_routes_require_auth(self):
        client=TestClient(api.app)
        self.assertEqual(client.get('/api/mobile/image-models').status_code,401)
        body={'idempotencyKey':'request-1','maxTokens':33}
        self.assertEqual(client.post('/api/mobile/projects/test/concepts',json=body).status_code,401)
        self.assertEqual(client.post('/api/mobile/concepts/test/refine',json=body).status_code,401)
        with patch.dict('os.environ',{'CRAFT_TASK_ORIGIN':'https://example.run.app','CRAFT_TASK_IDENTITY':'worker@example.com'}):
            self.assertEqual(client.post('/internal/concepts/test/cj-test').status_code,401)

if __name__=='__main__':unittest.main()
