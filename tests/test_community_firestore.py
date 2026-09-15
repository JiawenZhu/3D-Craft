import unittest
from unittest.mock import patch, MagicMock
from server import community_firestore

class FirestoreCommunityTests(unittest.TestCase):
    def test_value_conversion(self):
        self.assertEqual(community_firestore.to_firestore_value(True), {"booleanValue": True})
        self.assertEqual(community_firestore.to_firestore_value(42), {"integerValue": "42"})
        self.assertEqual(community_firestore.to_firestore_value(3.14), {"doubleValue": 3.14})
        self.assertEqual(community_firestore.to_firestore_value("hello"), {"stringValue": "hello"})
        self.assertEqual(community_firestore.to_firestore_value(["a", "b"]), {
            "arrayValue": {"values": [{"stringValue": "a"}, {"stringValue": "b"}]}
        })
        self.assertEqual(community_firestore.to_firestore_value({"k": "v"}), {
            "mapValue": {"fields": {"k": {"stringValue": "v"}}}
        })
        self.assertEqual(community_firestore.to_firestore_value(None), {"nullValue": None})

        # Roundtrip
        self.assertEqual(community_firestore.from_firestore_value({"booleanValue": False}), False)
        self.assertEqual(community_firestore.from_firestore_value({"integerValue": "10"}), 10)
        self.assertEqual(community_firestore.from_firestore_value({"doubleValue": 1.5}), 1.5)
        self.assertEqual(community_firestore.from_firestore_value({"stringValue": "test"}), "test")
        self.assertEqual(community_firestore.from_firestore_value({"nullValue": None}), None)

    def test_game_to_fields_and_doc_to_game(self):
        sample_game = {
            "id": "game-123",
            "title": "Pixel Runner",
            "creator": "Player1",
            "description": "Fun runner game",
            "url": "https://example.com/runner",
            "ownerId": "uid-abc",
            "owner": "firebase:uid-abc",
            "createdAt": 1700000000.0,
            "checkedAt": 1700000100.0,
            "reachable": True,
            "removed": False,
            "likes": 5,
            "votes": {"fun": 3, "animation": 1, "visuals": 1, "creativity": 0},
        }
        fields = community_firestore.game_to_fields(sample_game)
        self.assertEqual(fields["id"]["stringValue"], "game-123")
        self.assertEqual(fields["title"]["stringValue"], "Pixel Runner")
        self.assertEqual(fields["ownerId"]["stringValue"], "uid-abc")
        self.assertEqual(fields["likes"]["integerValue"], "5")

        doc = {"name": "projects/p/databases/(default)/documents/communityGames/game-123", "fields": fields}
        reconstructed = community_firestore.doc_to_game(doc)
        self.assertEqual(reconstructed["id"], "game-123")
        self.assertEqual(reconstructed["title"], "Pixel Runner")
        self.assertEqual(reconstructed["creator"], "Player1")
        self.assertEqual(reconstructed["ownerId"], "uid-abc")
        self.assertEqual(reconstructed["likes"], 5)
        self.assertEqual(reconstructed["votes"]["fun"], 3)
        self.assertEqual(reconstructed["reachable"], True)
        self.assertEqual(reconstructed["removed"], False)

    @patch("server.community_firestore.requests.patch")
    def test_save_game_to_firestore(self, mock_patch):
        mock_patch.return_value.status_code = 200
        game = {
            "id": "game-test",
            "title": "Test Title",
            "creator": "Tester",
            "url": "https://test.com",
            "ownerId": "uid-xyz",
            "likes": 0,
            "votes": {"fun": 0, "animation": 0, "visuals": 0, "creativity": 0},
        }
        success = community_firestore.save_game_to_firestore(game)
        self.assertTrue(success)
        mock_patch.assert_called_once()
        call_url = mock_patch.call_args[0][0]
        self.assertIn("communityGames/game-test", call_url)

    @patch("server.community_firestore.requests.get")
    def test_list_games_filters_removed(self, mock_get):
        doc_active = {
            "name": "projects/p/databases/(default)/documents/communityGames/game-1",
            "fields": {
                "id": {"stringValue": "game-1"},
                "title": {"stringValue": "Active Game"},
                "creator": {"stringValue": "C1"},
                "url": {"stringValue": "https://c1.com"},
                "removed": {"booleanValue": False},
                "likes": {"integerValue": "2"},
                "votes": {"mapValue": {"fields": {"fun": {"integerValue": "2"}}}},
            }
        }
        doc_removed = {
            "name": "projects/p/databases/(default)/documents/communityGames/game-2",
            "fields": {
                "id": {"stringValue": "game-2"},
                "title": {"stringValue": "Deleted Game"},
                "creator": {"stringValue": "C2"},
                "url": {"stringValue": "https://c2.com"},
                "removed": {"booleanValue": True},
                "likes": {"integerValue": "0"},
            }
        }
        mock_get.return_value.status_code = 200
        mock_get.return_value.json.return_value = {"documents": [doc_active, doc_removed]}

        games = community_firestore.list_games_from_firestore()
        self.assertEqual(len(games), 1)
        self.assertEqual(games[0]["id"], "game-1")
        self.assertEqual(games[0]["title"], "Active Game")

    @patch("server.community_firestore.requests.patch")
    def test_delete_game_sets_removed(self, mock_patch):
        mock_patch.return_value.status_code = 200
        success = community_firestore.delete_game_from_firestore("game-1", "user-1")
        self.assertTrue(success)
        mock_patch.assert_called_once()
        patch_kwargs = mock_patch.call_args[1]
        self.assertTrue(patch_kwargs["json"]["fields"]["removed"]["booleanValue"])

if __name__ == "__main__":
    unittest.main()
