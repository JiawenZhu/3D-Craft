import tempfile
import unittest
import time
from pathlib import Path
from unittest.mock import patch
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from server import community, mobile, game_links

class CommunityTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.db=patch.object(mobile,'DB_PATH',Path(self.temp.name)/'test.sqlite');self.db.start()
        self.app=FastAPI();self.app.include_router(community.router)
        def identity(request,authorization=''):
            if authorization not in ('Bearer alice','Bearer bob'): raise HTTPException(401,'Sign in')
            return authorization.split()[1]
        self.auth=patch.object(mobile,'account',identity);self.auth.start()
        from fastapi import Header
        def authenticated(authorization: str=Header(default='')):return identity(None,authorization)
        # Dependency objects were captured when routes were defined.
        for route in community.router.routes:
            for dependency in route.dependant.dependencies:
                if dependency.call.__name__=='account':self.app.dependency_overrides[dependency.call]=authenticated
        self.client=TestClient(self.app)
        self.verify=patch.object(community,'verify_game_url',side_effect=lambda u:{'url':game_links.normalize_url(u),'status':'reachable'});self.verify.start()
        self.fs_list=patch.object(community.community_firestore,'list_games_from_firestore',return_value=[]);self.fs_list.start()
        self.fs_save=patch.object(community.community_firestore,'save_game_to_firestore',return_value=True);self.fs_save.start()
        self.fs_vote=patch.object(community.community_firestore,'record_vote_in_firestore',return_value={});self.fs_vote.start()
        self.fs_del=patch.object(community.community_firestore,'delete_game_from_firestore',return_value=True);self.fs_del.start()
        self.alice={'Authorization':'Bearer alice'};self.bob={'Authorization':'Bearer bob'}
    def tearDown(self):
        self.fs_del.stop();self.fs_vote.stop();self.fs_save.stop();self.fs_list.stop()
        self.verify.stop();self.auth.stop();self.db.stop();self.temp.cleanup()
    def submit(self,url='https://game.example/play',headers=None):
        return self.client.post('/api/mobile/community/games',headers=headers or self.alice,json={'title':'My game','creator':'Maker','url':url,'played':True})
    def test_auth_public_read_and_zero_votes(self):
        response=self.client.post('/api/mobile/community/games',json={'title':'a','creator':'a','url':'https://game.example','played':True})
        self.assertEqual(response.status_code,401)
        game=self.submit().json()
        self.assertEqual(game['votes'],dict.fromkeys(community.CATEGORIES,0))
        result=self.client.get('/api/mobile/community/games').json()['games'][0]
        self.assertNotIn('owner',result);self.assertEqual(result['myVotes'],[]);self.assertFalse(result['isMine'])
        self.assertEqual(self.client.put('/api/mobile/community/games/'+game['id']+'/vote',json={'category':'fun','liked':True}).status_code,401)
    def test_vote_idempotency_categories_undo_and_order(self):
        first=self.submit().json();second=self.submit('https://other.example').json()
        path='/api/mobile/community/games/'+first['id']+'/vote'
        for _ in range(3):
            result=self.client.put(path,headers=self.alice,json={'category':'fun','liked':True}).json()
            self.assertEqual(result['votes']['fun'],1)
        result=self.client.put(path,headers=self.bob,json={'category':'fun','liked':True}).json()
        self.assertEqual(result['votes']['fun'],2)
        self.client.put(path,headers=self.alice,json={'category':'animation','liked':True})
        rows=self.client.get('/api/mobile/community/games?category=fun',headers=self.alice).json()['games']
        self.assertEqual(rows[0]['id'],first['id']);self.assertEqual(set(rows[0]['myVotes']),{'fun','animation'})
        result=self.client.put(path,headers=self.alice,json={'category':'fun','liked':False}).json()
        self.assertEqual(result['votes']['fun'],1);self.assertEqual(result['votes']['animation'],1)
        self.assertEqual(self.client.put(path,headers=self.alice,json={'category':'bogus','liked':True}).status_code,422)
    def test_duplicate_link_and_removal_ownership(self):
        game=self.submit().json()
        self.assertEqual(self.submit(headers=self.bob).status_code,409)
        path='/api/mobile/community/games/'+game['id']
        self.assertEqual(self.client.delete(path,headers=self.bob).status_code,403)
        self.assertEqual(self.client.delete('/api/mobile/community/games/nonexistent',headers=self.alice).status_code,404)
        self.assertEqual(self.client.delete(path,headers=self.alice).status_code,200)
        self.assertEqual(self.client.get('/api/mobile/community/games').json()['games'],[])
        self.assertEqual(self.client.get(path+'/play').status_code,404)
    def test_failed_link_is_rejected_and_stale_play_rechecked(self):
        with patch.object(community,'verify_game_url',side_effect=game_links.LinkError('Unavailable')):
            self.assertEqual(self.submit().status_code,422)
        game=self.submit().json()
        with community.database() as c:c.execute('UPDATE community_games SET checked=0')
        with patch.object(community,'verify_game_url',side_effect=game_links.LinkError('Unavailable')):
            self.assertEqual(self.client.get('/api/mobile/community/games/'+game['id']+'/play').status_code,422)
        self.assertEqual(self.client.get('/api/mobile/community/games').json()['games'],[])
        self.assertFalse(self.client.get('/api/mobile/community/mine',headers=self.alice).json()[0]['reachable'])
        self.assertEqual(self.client.post('/api/mobile/community/games/'+game['id']+'/recheck',headers=self.alice).status_code,200)
        self.assertEqual(len(self.client.get('/api/mobile/community/games').json()['games']),1)
    def test_report_is_saved_and_hides_for_reporter_only(self):
        game=self.submit().json()
        self.client.post('/api/mobile/community/games/'+game['id']+'/report',headers=self.bob,json={'reason':'Broken content'})
        self.assertEqual(self.client.get('/api/mobile/community/games',headers=self.bob).json()['games'],[])
        self.assertEqual(len(self.client.get('/api/mobile/community/games',headers=self.alice).json()['games']),1)
    def test_rate_limit(self):
        with community.database() as c:
            for _ in range(12):c.execute('INSERT INTO community_checks VALUES(?,?)',('alice',time.time()))
        self.assertEqual(self.client.post('/api/mobile/community/check-link',headers=self.alice,json={'url':'https://game.example'}).status_code,429)

class GameLinkTests(unittest.TestCase):
    def test_private_and_invalid_urls_rejected(self):
        for url in ['http://game.example','file:///tmp/a','javascript:alert(1)','https://localhost/','https://127.0.0.1','https://169.254.169.254','https://[::1]/','https://name:pass@example.com','https://example.com:8000','https://example.com\\@127.0.0.1']:
            with self.subTest(url=url),self.assertRaises(game_links.LinkError):game_links.normalize_url(url)
    def test_dns_mixed_private_address_rejected(self):
        with patch.object(game_links.socket,'getaddrinfo',return_value=[(2,1,6,'',('1.1.1.1',443)),(2,1,6,'',('10.0.0.1',443))]),self.assertRaises(game_links.LinkError):
            game_links.public_addresses('example.com')
    def test_redirect_to_private_or_agent_page_rejected(self):
        for location in ['https://127.0.0.1/admin','https://claude.ai/share/test']:
            with patch.object(game_links,'fetch_page',return_value=(302,{'location':location},'')) as fetch,self.assertRaises(game_links.LinkError):
                game_links.verify_game_url('https://public.example')
            self.assertEqual(fetch.call_count,1)
    def test_reachable_html_and_failures(self):
        with patch.object(game_links,'fetch_page',return_value=(200,{'content-type':'text/html'},'<canvas>game</canvas>')):
            self.assertEqual(game_links.verify_game_url('https://EXAMPLE.com/#play')['url'],'https://example.com/#play')
        for page in [(404,{'content-type':'text/html'},''),(200,{'content-type':'application/octet-stream'},''),(200,{'content-type':'text/html'},'<title>Sign in</title>')]:
            with patch.object(game_links,'fetch_page',return_value=page),self.assertRaises(game_links.LinkError):game_links.verify_game_url('https://example.com')
    def test_known_agent_pages_are_not_game_links(self):
        with patch.object(game_links,'fetch_page') as fetch:
            for url in ['https://claude.ai/code','https://claude.ai/share/example','https://chatgpt.com/share/example']:
                with self.assertRaises(game_links.LinkError):game_links.verify_game_url(url)
            fetch.assert_not_called()
        with patch.object(game_links,'fetch_page',return_value=(200,{'content-type':'text/html'},'<iframe title="game"></iframe>')):
            self.assertEqual(game_links.verify_game_url('https://claude.ai/code/artifact/example')['status'],'reachable')
if __name__=='__main__':unittest.main()
