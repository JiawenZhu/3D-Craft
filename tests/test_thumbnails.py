"""Offline cache and path-boundary tests for display-only thumbnail derivatives."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from PIL import Image
from fastapi.testclient import TestClient
from server import thumbnails
from server.app import app


class ThumbnailTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.storage = self.root / "storage"; self.source = self.storage / "a-dog" / "thumb.png"
        self.source.parent.mkdir(parents=True)
        Image.new("RGB", (32,32), "black").save(self.source)
        self.asset = {"id":"a-dog", "thumbUrl":"/files/a-dog/thumb.png"}
        for item in [patch.object(thumbnails,"STORAGE",self.storage),patch.object(thumbnails,"CACHE",self.root/"cache")]:
            item.start(); self.addCleanup(item.stop)

    def segment(self, source, output):
        Image.new("RGBA", (32,32), (120,90,20,100)).save(output)
        return True

    def test_derivative_is_cached_and_source_is_immutable(self):
        original = self.source.read_bytes()
        with patch.object(thumbnails,"_segment",side_effect=self.segment) as segment:
            first, alpha = thumbnails.display_path(self.asset)
            second, _ = thumbnails.display_path(self.asset)
        self.assertTrue(alpha); self.assertEqual(first,second)
        self.assertEqual(segment.call_count,1)
        self.assertEqual(self.source.read_bytes(),original)
        self.assertNotEqual(first,self.source)
        self.assertEqual(thumbnails.decorate(self.asset)["thumbUrl"],self.asset["thumbUrl"])
        self.assertIn("thumbDisplayUrl",thumbnails.decorate(self.asset))

    def test_changed_source_gets_new_cache_and_display_url(self):
        before = thumbnails.decorate(self.asset)["thumbDisplayUrl"]
        with patch.object(thumbnails,"_segment",side_effect=self.segment) as segment:
            first,_ = thumbnails.display_path(self.asset)
            Image.new("RGB", (34,34), "orange").save(self.source)
            second,_ = thumbnails.display_path(self.asset)
        self.assertNotEqual(first,second)
        self.assertNotEqual(before,thumbnails.decorate(self.asset)["thumbDisplayUrl"])
        self.assertEqual(segment.call_count,2)

    def test_unsupported_segmentation_keeps_original_and_avoids_repeated_work(self):
        with patch.object(thumbnails,"_segment",return_value=False) as segment:
            self.assertEqual(thumbnails.display_path(self.asset),(self.source.resolve(),False))
            self.assertEqual(thumbnails.display_path(self.asset),(self.source.resolve(),False))
        self.assertEqual(segment.call_count,1)

    def test_arbitrary_urls_traversal_and_other_asset_paths_are_rejected(self):
        outside = self.storage / "outside.png"; Image.new("RGB",(2,2)).save(outside)
        for raw in ["https://example.com/image.png", "/files/a-dog/../outside.png", "/files/a-dog/%2e%2e/outside.png", "/files/another/thumb.png", "/files/a-dog/thumb.png?url=https://example.com"]:
            self.assertIsNone(thumbnails.source_path({**self.asset,"thumbUrl":raw}))
        (self.source.parent/"linked.png").symlink_to(outside)
        self.assertIsNone(thumbnails.source_path({**self.asset,"thumbUrl":"/files/a-dog/linked.png"}))

    def test_route_only_accepts_registered_asset_and_serves_png(self):
        with TestClient(app) as client, patch("server.app.jobs.list_assets",return_value=[self.asset]),patch.object(thumbnails,"_segment",side_effect=self.segment):
            response=client.get("/api/assets/a-dog/thumbnail-display")
            self.assertEqual(response.status_code,200)
            self.assertEqual(response.headers["content-type"],"image/png")
            self.assertEqual(response.headers["x-craft-thumbnail"],"transparent-display")
            self.assertEqual(client.get("/api/assets/not-registered/thumbnail-display").status_code,404)
            self.asset["visibility"] = "private"
            self.assertEqual(client.get("/api/assets/a-dog/thumbnail-display").status_code,404)
            self.assertNotIn("thumbDisplayUrl",thumbnails.decorate(self.asset))


if __name__ == "__main__": unittest.main()
