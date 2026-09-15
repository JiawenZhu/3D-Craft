import io
import unittest
from unittest.mock import patch, Mock
from decimal import Decimal
from PIL import Image
from fastapi import HTTPException
from fastapi.testclient import TestClient
from pydantic import ValidationError
from server import cloud_planner_provider as p, firebase_api as api
from server.firebase_planning import PromptRequest, CloudPlanning


class ProviderTests(unittest.TestCase):
    def test_quote_and_settlement_use_thinking_tokens_and_price_boundary(self):
        now=p.PRICE_CHANGE-1
        self.assertEqual(p.quote(now)['maxTokens'],2)
        self.assertEqual(p.quote(now)['expiresAt'],p.PRICE_CHANGE)
        self.assertEqual(p.quote(p.PRICE_CHANGE)['maxTokens'],4)
        raw={'candidates':[{'finishReason':'STOP','content':{'parts':[{'thought':True,'text':'hidden'},
            {'text':'{"prompt":"Keep the swing canopy."}','thoughtSignature':'never persist'}]}}],
            'usageMetadata':{'promptTokenCount':1000,'candidatesTokenCount':50,'thoughtsTokenCount':500}}
        with patch.object(p,'call',return_value=raw):result=p.generate({},p.rates(now))
        self.assertEqual(result['usage'],{'input':1000,'output':550,'cachedInput':0})
        self.assertEqual(Decimal(result['providerUsd']),Decimal('.0028125'))
        self.assertNotIn('thoughtSignature',str(result));self.assertEqual(result['tokens'],1)
        self.assertLess(Decimal(p.cost(1000,550,p.rates(now),500)['providerUsd']),Decimal(result['providerUsd']))

    def test_no_automatic_paid_request_retry_or_raw_provider_error(self):
        credentials=Mock()
        with patch.object(p.google.auth,'default',return_value=(credentials,None)),patch.object(p.requests,'post',return_value=Mock(status_code=503,text='sensitive raw body')) as post:
            with self.assertRaises(p.PlannerError) as exc:p.call('generateContent',{})
            post.assert_called_once();self.assertNotIn('sensitive',str(exc.exception))

    def test_bound_input_output_and_validate_suggestion_before_charge(self):
        with patch.object(p,'call',return_value={'totalTokens':p.MAX_INPUT+1}):
            with self.assertRaises(p.PlannerError):p.preflight({})
        for candidate in ({'finishReason':'MAX_TOKENS'}, {'finishReason':'STOP','content':{'parts':[{'text':'{"prompt":""}'}]}}):
            with patch.object(p,'call',return_value={'candidates':[candidate]}):
                with self.assertRaises(p.PlannerError):p.generate({},p.rates(0))
        image=io.BytesIO();Image.new('RGB',(1200,1200)).save(image,format='PNG')
        body=p.body('Use this swing',image.getvalue())
        self.assertEqual(body['generationConfig']['maxOutputTokens'],p.MAX_OUTPUT)
        self.assertIn('not a swimming pool',body['systemInstruction']['parts'][0]['text'])

    def test_request_requires_explicit_spending_cap_and_supported_model(self):
        valid={'idempotencyKey':'request-1','maxTokens':2}
        self.assertEqual(PromptRequest(**valid).plannerModel,p.MODEL)
        for changes in ({'maxTokens':True},{'maxTokens':0},{'plannerModel':'own-account-model'}):
            with self.assertRaises(ValidationError):PromptRequest(**{**valid,**changes})
        with self.assertRaises(ValidationError):PromptRequest(idempotencyKey='request-1')

    def test_private_jobs_and_worker_require_identity(self):
        client=TestClient(api.app)
        self.assertEqual(client.get('/api/mobile/planning/quote').status_code,401)
        self.assertEqual(client.get('/api/mobile/planning/pj-'+'a'*64).status_code,401)
        self.assertEqual(client.post('/api/mobile/concepts/example/model-prompt',json={'idempotencyKey':'request-1','maxTokens':2}).status_code,401)
        with patch.object(api,'verify_worker',side_effect=HTTPException(401,'Required')):
            self.assertEqual(client.post('/internal/planning/alice/pj-'+'a'*64).status_code,401)
        with self.assertRaises(HTTPException):CloudPlanning(Mock()).ref('alice','../other')


if __name__=='__main__':unittest.main()
