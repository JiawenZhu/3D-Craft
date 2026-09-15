import importlib.util
import io
import json
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
spec=importlib.util.spec_from_file_location('phone_gateway',Path(__file__).resolve().parents[1]/'ios/scripts/phone-review-gateway.py')
gateway=importlib.util.module_from_spec(spec);spec.loader.exec_module(gateway)

class PhoneGatewayTests(unittest.TestCase):
    def handler(self,path='/private-test-token/api/mobile/bootstrap'):
        klass=gateway.handler({'token':'private-test-token'})
        h=klass.__new__(klass);h.path=path;h.command='GET';h.headers={'Authorization':'Bearer example-test-token'}
        h.rfile=io.BytesIO();h.wfile=io.BytesIO()
        h.send_response=Mock();h.send_header=Mock();h.end_headers=Mock();h.send_error=Mock()
        return h
    def test_stopped_studio_returns_actionable_503(self):
        h=self.handler()
        with patch.object(gateway.http.client,'HTTPConnection') as connection:
            connection.return_value.request.side_effect=ConnectionRefusedError()
            h.forward()
            h.send_response.assert_called_once_with(503)
            self.assertIn('Studio server unavailable',json.loads(h.wfile.getvalue())['detail'])
            connection.return_value.close.assert_called_once()
    def test_wrong_private_path_never_reaches_studio(self):
        h=self.handler('/wrong/api/mobile/bootstrap')
        with patch.object(gateway.http.client,'HTTPConnection') as connection:
            h.forward();connection.assert_not_called();h.send_error.assert_called_once_with(404)
    def test_account_authorization_survives_gateway(self):
        h=self.handler()
        with patch.object(gateway.http.client,'HTTPConnection') as connection:
            response=connection.return_value.getresponse.return_value
            response.status=200;response.getheaders.return_value=[];response.read.return_value=b''
            h.forward()
            self.assertEqual(connection.return_value.request.call_args.args[3]['Authorization'],'Bearer example-test-token')
            self.assertEqual(connection.return_value.request.call_args.args[1],'/api/mobile/bootstrap')
    def test_put_and_delete_methods_forwarded(self):
        klass = gateway.handler({'token': 'private-test-token'})
        self.assertTrue(hasattr(klass, 'do_PUT'))
        self.assertTrue(hasattr(klass, 'do_DELETE'))
        self.assertEqual(klass.do_PUT, klass.forward)
        self.assertEqual(klass.do_DELETE, klass.forward)

