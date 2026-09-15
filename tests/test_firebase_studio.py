import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from google.api_core.exceptions import PreconditionFailed
from server.firebase_studio import FirebaseStudio, uid_for, local_file

class FirebaseStudioTests(unittest.TestCase):
    def test_only_verified_owners_and_contained_files(self):
        for value in ('device-id','firebase:','firebase:../b','firebase:a/b'):
            with self.assertRaises(ValueError): uid_for(value)
        with self.assertRaises(ValueError): local_file('/files/../../secret.png')
        self.assertIsNone(local_file('https://example.com/picture.png'))

    def test_immutable_objects_are_private_and_account_scoped(self):
        with tempfile.TemporaryDirectory() as temp:
            image=Path(temp)/'ref.png'; image.write_bytes(b'example-image')
            bucket=Mock(); cloud=FirebaseStudio(db=Mock(),bucket=bucket)
            name=cloud.file('firebase:alice',image,'images')
            self.assertTrue(name.startswith('users/alice/images/'))
            blob=bucket.blob.return_value
            self.assertEqual(blob.upload_from_filename.call_args.kwargs['if_generation_match'],0)
            self.assertEqual(blob.metadata['ownerId'],'alice')
            self.assertIn('private',blob.cache_control)
            self.assertNotIn('firebaseStorageDownloadTokens',blob.metadata)
            blob.upload_from_filename.side_effect=PreconditionFailed('already exists')
            blob.size=image.stat().st_size
            self.assertEqual(cloud.file('firebase:alice',image,'images'),name)
            blob.size=999
            with self.assertRaises(ValueError): cloud.file('firebase:alice',image,'images')

    def test_failed_upload_does_not_publish_broken_gallery_record(self):
        db=Mock(); cloud=FirebaseStudio(db=db,bucket=Mock())
        with patch('server.firebase_studio.local_file',return_value=Path('/tmp/ref.png')),patch.object(cloud,'file',side_effect=RuntimeError('upload failed')):
            with self.assertRaises(RuntimeError): cloud.save_creation('firebase:alice',{'id':'concept:1','name':'Cat','image':'/files/cat.png'})
        db.collection.assert_not_called()

    def test_storage_failure_does_not_publish_project_and_no_credentials_in_records(self):
        db=Mock(); cloud=FirebaseStudio(db=db,bucket=Mock())
        result=cloud.rewrite_files('firebase:alice',{'token':'secret','authorization':'secret','name':'Cat'})
        self.assertEqual(result,{'name':'Cat'})
        with self.assertRaises(ValueError): cloud.save_record('firebase:alice','wallets','balance',{})
        with patch.object(cloud,'file',side_effect=RuntimeError('offline')),patch('server.firebase_studio.local_file',return_value=Path('/tmp/ref.png')):
            with self.assertRaises(RuntimeError): cloud.save_record('firebase:alice','studioConcepts','one',{'imageUrl':'/files/one.png'})
        db.collection.assert_not_called()

if __name__ == '__main__': unittest.main()
