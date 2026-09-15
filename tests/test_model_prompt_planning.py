import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from server import planning

class ModelPromptPlanningTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.image = Path(self.tmp.name) / 'swing.png'; self.image.write_bytes(b'image')
    def test_gemini_uses_reference_and_returns_short_prompt(self):
        response={'candidates':[{'content':{'parts':[{'text':json.dumps({'prompt':'Keep the swing frame; size the seat for a character.'})}]}}]}
        with patch.object(planning,'require_available') as check,patch.object(planning.gemini,'_inline',return_value={'inlineData':{'data':'fixture'}}),patch.object(planning.gemini,'_call',return_value=response) as call:
            result=planning.improve_model_prompt('owner',planning.DEFAULT_MODEL,'A swing',self.image)
        check.assert_called_once_with('owner',planning.DEFAULT_MODEL,'low')
        self.assertIn('swing',result['prompt'])
        parts=call.call_args.args[1]['contents'][0]['parts']
        self.assertIn('inlineData',parts[0]); self.assertIn('A swing',parts[1]['text'])
    def test_selected_account_model_is_used_without_fallback(self):
        with patch.object(planning,'require_available'),patch('server.codex_bridge.plan',return_value={'prompt':'保留秋千的座椅和支架。'}) as call:
            result=planning.improve_model_prompt('firebase:alice','selected-model','秋千',self.image,effort='medium')
        self.assertEqual(call.call_args.args[0:2],('firebase:alice','selected-model'))
        self.assertEqual(call.call_args.args[3],[self.image])
        self.assertEqual(call.call_args.kwargs['effort'],'medium')
        self.assertEqual(result['model'],'selected-model')
    def test_invalid_output_and_unavailable_model_fail_without_switching_provider(self):
        for result in [{}, {'prompt':''}, {'prompt':'x'*801}, {'prompt':123}]:
            with patch.object(planning,'require_available'),patch('server.codex_bridge.plan',return_value=result):
                with self.assertRaises(RuntimeError):planning.improve_model_prompt('owner','selected-model','words',self.image)
        with patch.object(planning,'require_available',side_effect=RuntimeError('unavailable')),patch.object(planning.gemini,'_call') as call:
            with self.assertRaises(RuntimeError):planning.improve_model_prompt('owner','selected-model','words',self.image)
            call.assert_not_called()
