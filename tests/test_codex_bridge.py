"""Offline own-account protocol tests. No OAuth login or paid model turns."""
import base64
from concurrent.futures import ThreadPoolExecutor
import io
import os
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch

from PIL import Image
from fastapi import FastAPI
from fastapi.testclient import TestClient
from server import codex_bridge as bridge, mobile_ai


def png():
    out = io.BytesIO()
    Image.new('RGBA', (32, 32), (100, 40, 200, 255)).save(out, format='PNG')
    return out.getvalue()


def fake_server(home):
    server = bridge.AppServer.__new__(bridge.AppServer)
    server.home = Path(home)
    server.lock = threading.RLock()
    server.changed = threading.Condition(server.lock)
    server.operation = threading.Lock()
    server.watched, server.completed, server.items = set(), {}, {}
    server.default_model = 'gpt-live'
    server.login_id = server.login_status = None
    server.login_started = 0
    server.catalog = None
    server.catalog_time = 0
    server.image_capability = True
    server.process = Mock(poll=Mock(return_value=None))
    server.status = Mock(return_value={'connected': True, 'imageGenerationSupported': True,
        'models': [{'id': 'gpt-live', 'name': 'Live GPT', 'reasoningEfforts': ['low', 'high']}]})
    return server


class CodexBridgeTests(unittest.TestCase):
    def test_owner_homes_are_private_separate_and_outside_public_storage(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {'CRAFT_CODEX_ACCOUNTS_DIR': directory}):
            first, second = bridge._private_home('owner-a'), bridge._private_home('owner-b')
            self.assertNotEqual(first, second)
            self.assertEqual(first.stat().st_mode & 0o777, 0o700)
            self.assertEqual((first/'config.toml').stat().st_mode & 0o777, 0o600)
            config = (first/'config.toml').read_text()
            self.assertIn('cli_auth_credentials_store = "file"', config)
            self.assertIn('shell_tool = false', config)
        from server.config import STORAGE
        with patch.dict(os.environ, {'CRAFT_CODEX_ACCOUNTS_DIR': str(STORAGE/'unsafe')}):
            with self.assertRaises(bridge.BridgeError): bridge._private_home('a')

    def test_process_never_inherits_ambient_auth_or_provider_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            process = Mock(stdout=iter([]), poll=Mock(return_value=0))
            with patch.object(bridge, '_binary', return_value='/test/codex'), patch.object(bridge, '_private_home', return_value=Path(directory)), patch.object(bridge.subprocess, 'Popen', return_value=process) as spawn, patch.object(bridge.AppServer, 'call', return_value={}), patch.object(bridge.AppServer, '_write'), patch.dict(os.environ, {'OPENAI_API_KEY':'secret', 'CODEX_HOME':'/ambient', 'CODEX_API_KEY':'secret'}):
                bridge.AppServer('owner')
            env = spawn.call_args.kwargs['env']
            self.assertNotIn('OPENAI_API_KEY', env)
            self.assertNotIn('CODEX_API_KEY', env)
            self.assertEqual(env['CODEX_HOME'], directory)
            self.assertEqual(spawn.call_args.kwargs['umask'], 0o077)

    def test_disconnected_status_never_advertises_cached_models(self):
        with tempfile.TemporaryDirectory() as directory:
            server = fake_server(directory)
            server.call = Mock(return_value={'account': None})
            result = bridge.AppServer.status(server)
            self.assertFalse(result['connected'])
            self.assertFalse(result['imageGenerationSupported'])
            self.assertEqual(result['models'], [])
            server.call.assert_called_once_with('account/read', {'refreshToken': False})

    def test_cancel_cannot_cancel_another_owners_login(self):
        server = fake_server('/tmp')
        server.login_id = 'this-owner-login'
        server.call = Mock()
        with self.assertRaises(bridge.BridgeError): server.cancel('someone-else-login')
        server.call.assert_not_called()

    def test_planner_uses_exact_model_schema_and_no_environment(self):
        with tempfile.TemporaryDirectory() as directory:
            server = fake_server(directory)
            def call(method, params, **kwargs):
                if method == 'thread/start': return {'thread': {'id':'thread-1'}}
                if method == 'turn/start':
                    # Completion may arrive before the turn/start response.
                    server.completed['thread-1'] = {'status':'completed', 'items':[
                        {'type':'agentMessage','phase':'commentary','text':'Thinking'},
                        {'type':'agentMessage','phase':'final_answer','text':'{"prompt":"small cat"}'}]}
                    return {'turn': {'id':'turn-1'}}
                return {}
            server.call = Mock(side_effect=call)
            schema = {'type':'object','required':['prompt'],'properties':{'prompt':{'type':'string'}},'additionalProperties':False}
            result = server.plan('gpt-live', 'cat', [], schema)
            self.assertEqual(result['prompt'],'small cat')
            started = server.call.call_args_list[0].args[1]
            self.assertFalse(started['allowProviderModelFallback'])
            self.assertEqual(started['environments'], [])
            self.assertEqual(started['model'],'gpt-live')
            self.assertNotIn('turn/interrupt',[call.args[0] for call in server.call.call_args_list])
            with self.assertRaises(bridge.BridgeError): server.plan('unlisted-gpt', 'cat', [], schema)

    def test_timeout_interrupts_once_without_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            server = fake_server(directory)
            server.call = Mock(side_effect=lambda method, params, **kw: {'thread':{'id':'t'}} if method=='thread/start' else {'turn':{'id':'u'}})
            with patch.object(bridge,'PLAN_TIMEOUT',0.001):
                with self.assertRaises(bridge.BridgeError): server.plan('gpt-live','cat',[],{'type':'object'})
            methods = [call.args[0] for call in server.call.call_args_list]
            self.assertEqual(methods.count('turn/start'),1)
            self.assertEqual(methods.count('turn/interrupt'),1)
            self.assertFalse(server.operation.locked())

    def test_image_tool_result_is_verified_and_never_fetches_arbitrary_urls(self):
        with tempfile.TemporaryDirectory() as directory:
            server = fake_server(directory)
            content = png()
            def call(method, params, **kwargs):
                if method == 'thread/start': return {'thread':{'id':'img'}}
                if method == 'turn/start':
                    server.completed['img'] = {'status':'completed','items':[]}
                    server.items['img'] = {'image':{'type':'imageGeneration','status':'completed','result':base64.b64encode(content).decode()}}
                    return {'turn':{'id':'turn'}}
                return {}
            server.call = Mock(side_effect=call)
            result = server.generate_image('cat',[])
            self.assertEqual(result['bytes'],content)
            self.assertEqual((result['model'],result['provider'],result['mime']),('gpt-image-2','chatgpt','image/png'))
            self.assertEqual(server.call.call_args_list[0].args[1]['config'],{'features.image_generation':True})
            # The native image extension requires the default tool environment
            # and its host, even though planning disables environments entirely.
            self.assertNotIn('environments', server.call.call_args_list[0].args[1])
            self.assertNotIn('code_mode_host', bridge.DISABLED_FEATURES)
            with self.assertRaises(bridge.BridgeError): bridge._image_bytes({'result':'https://example.com/a.png'}, Path(directory))
            with self.assertRaises(bridge.BridgeError): bridge._image_bytes({'savedPath':'/etc/passwd'}, Path(directory))
            path=Path(directory)/'valid.png'; path.write_bytes(content)
            self.assertEqual(bridge._image_bytes({'savedPath':str(path)},Path(directory))[0],content)

    def test_parallel_reference_views_serialize_instead_of_failing_busy(self):
        with tempfile.TemporaryDirectory() as directory:
            server = fake_server(directory)
            content = png()
            active, maximum, count = 0, 0, 0
            def call(method, params, **kwargs):
                nonlocal active, maximum, count
                if method == 'thread/start':
                    count += 1
                    active += 1
                    maximum = max(maximum, active)
                    return {'thread':{'id':f'view-{count}'}}
                if method == 'turn/start':
                    time.sleep(0.025)
                    server.completed[params['threadId']] = {'status':'completed','items':[
                        {'type':'imageGeneration','status':'completed','result':base64.b64encode(content).decode()}]}
                    active -= 1
                    return {'turn':{'id':params['threadId']}}
                return {}
            server.call = Mock(side_effect=call)
            with ThreadPoolExecutor(max_workers=3) as pool:
                results = list(pool.map(lambda angle: server.generate_image(angle, []), ['left','back','right']))
            self.assertEqual(len(results),3)
            self.assertEqual(count,3)
            self.assertEqual(maximum,1)
            self.assertTrue(all(result['bytes']==content for result in results))

    def test_routes_require_local_owner_and_never_return_auth_tokens(self):
        app = FastAPI(); app.include_router(mobile_ai.router)
        client = TestClient(app)
        with patch.dict(os.environ,{'RODIN_MOBILE_DEVELOPMENT':'0'}):
            self.assertEqual(client.get('/api/mobile/ai/account').status_code,503)
        app.dependency_overrides[mobile_ai.account] = lambda: 'owner-a'
        with patch.object(bridge, 'account_status', return_value={'available':True, 'connected':True, 'imageGenerationSupported':True, 'models':[]}) as status:
            snapshot = client.get('/api/mobile/ai/account').json()
            status.assert_called_once_with('owner-a')
            self.assertTrue(snapshot['connected'])
            image = next(m for m in snapshot['imageModels'] if m['id']=='codex-gpt-image-2')
            self.assertTrue(image['available'])
            self.assertIsNone(image['unavailableReason'])
        with patch.object(bridge,'start_login', return_value={'type':'chatgptDeviceCode','loginId':'a','verificationUrl':'https://auth.openai.com/codex/device','userCode':'TEST'}) as login:
            response=client.post('/api/mobile/ai/login')
            self.assertEqual(response.status_code,200)
            login.assert_called_once_with('owner-a')
            self.assertEqual(set(response.json()),{'type','loginId','verificationUrl','userCode'})


if __name__ == '__main__': unittest.main()
