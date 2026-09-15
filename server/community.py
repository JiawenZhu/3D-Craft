"""Public user game directory with authenticated, persistent category votes."""
import time
import uuid
from contextlib import contextmanager
from fastapi import APIRouter, Depends, Header, HTTPException, Request, Query
from pydantic import BaseModel, Field
from . import mobile, community_firestore
from .game_links import verify_game_url, normalize_url, LinkError

router = APIRouter(prefix='/api/mobile/community', tags=['Community games'])
CATEGORIES = ('fun', 'animation', 'visuals', 'creativity')

@contextmanager
def database():
    with mobile.connect() as c:
        c.executescript('''
        CREATE TABLE IF NOT EXISTS community_games (
            id TEXT PRIMARY KEY, owner TEXT NOT NULL, title TEXT NOT NULL, creator TEXT NOT NULL,
            description TEXT NOT NULL, url TEXT NOT NULL UNIQUE, created REAL NOT NULL,
            checked REAL NOT NULL, reachable INTEGER NOT NULL DEFAULT 1, removed INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS community_votes (
            owner TEXT NOT NULL, game TEXT NOT NULL, category TEXT NOT NULL,
            PRIMARY KEY(owner, game, category));
        CREATE TABLE IF NOT EXISTS community_reports (
            owner TEXT NOT NULL, game TEXT NOT NULL, reason TEXT NOT NULL, created REAL NOT NULL,
            PRIMARY KEY(owner,game));
        CREATE TABLE IF NOT EXISTS community_checks (owner TEXT NOT NULL, created REAL NOT NULL);
        ''')
        yield c

def viewer(request: Request, authorization: str = Header(default='')):
    return mobile.account(request, authorization) if authorization else ''

def check_budget(owner):
    with database() as c:
        c.execute('BEGIN IMMEDIATE')
        c.execute('DELETE FROM community_checks WHERE created < ?', (time.time()-600,))
        count = c.execute('SELECT count(*) FROM community_checks WHERE owner=?', (owner,)).fetchone()[0]
        if count >= 12:
            raise HTTPException(429, 'Too many link checks. Please try again in a few minutes.')
        c.execute('INSERT INTO community_checks VALUES(?,?)', (owner,time.time()))

def checked(value):
    try:
        return verify_game_url(value)['url']
    except LinkError as error:
        raise HTTPException(422, str(error))

class Submission(BaseModel):
    title: str = Field(min_length=1,max_length=80)
    creator: str = Field(min_length=1,max_length=40)
    description: str = Field(default='',max_length=500)
    url: str = Field(min_length=1,max_length=2048)
    played: bool = False

class LinkInput(BaseModel):
    url: str = Field(min_length=1,max_length=2048)

class Vote(BaseModel):
    category: str
    liked: bool

class Report(BaseModel):
    reason: str = Field(min_length=1,max_length=500)


def present(c, row, owner):
    row_dict = dict(row) if not isinstance(row, dict) else row
    counts = dict.fromkeys(CATEGORIES, 0)
    for vote in c.execute('SELECT category,count(*) AS n FROM community_votes WHERE game=? GROUP BY category', (row_dict['id'],)):
        if vote['category'] in counts:
            counts[vote['category']] = vote['n']
    mine = [v[0] for v in c.execute('SELECT category FROM community_votes WHERE owner=? AND game=?', (owner, row_dict['id']))] if owner else []
    row_owner = str(row_dict.get('owner', row_dict.get('ownerId', '')))
    owner_uid = owner.removeprefix('firebase:') if owner else ''
    row_owner_uid = row_owner.removeprefix('firebase:')
    is_mine = bool(owner) and ((owner == row_owner) or (bool(owner_uid) and owner_uid == row_owner_uid))
    created_val = row_dict.get('created', row_dict.get('createdAt', 0.0))
    checked_val = row_dict.get('checked', row_dict.get('checkedAt', 0.0))
    return dict(id=row_dict['id'], title=row_dict['title'], creator=row_dict['creator'], description=row_dict.get('description', ''),
                url=row_dict['url'], createdAt=created_val, checkedAt=checked_val, reachable=bool(row_dict.get('reachable', 1)),
                votes=counts, myVotes=mine, isMine=is_mine)


@router.get('/games')
def games(category: str='fun', offset: int=Query(0,ge=0), owner: str=Depends(viewer)):
    if category not in CATEGORIES:
        raise HTTPException(422, 'Choose a valid leaderboard category.')
    with database() as c:
        # Sync newly created games from Firestore if any were added externally
        try:
            fs_games = community_firestore.list_games_from_firestore()
            for fg in fs_games:
                if not c.execute('SELECT 1 FROM community_games WHERE id=?', (fg['id'],)).fetchone():
                    c.execute('INSERT OR IGNORE INTO community_games VALUES(?,?,?,?,?,?,?,?,?,?)',
                              (fg['id'], fg.get('owner', 'firebase:'+fg.get('ownerId', '')), fg['title'], fg['creator'],
                               fg.get('description', ''), fg['url'], fg.get('createdAt', time.time()),
                               fg.get('checkedAt', time.time()), int(fg.get('reachable', 1)), int(fg.get('removed', 0))))
        except Exception:
            pass
        rows = c.execute('''SELECT g.*, count(v.owner) AS score FROM community_games g
            LEFT JOIN community_votes v ON v.game=g.id AND v.category=?
            WHERE g.removed=0 AND g.reachable=1 AND NOT EXISTS
                (SELECT 1 FROM community_reports r WHERE r.game=g.id AND r.owner=?)
            GROUP BY g.id ORDER BY score DESC,g.created DESC,g.id LIMIT 51 OFFSET ?''', (category,owner,offset)).fetchall()
        return {'games':[present(c,r,owner) for r in rows[:50]],'hasMore':len(rows)>50,'categories':CATEGORIES}

@router.post('/check-link')
def check_link(body: LinkInput, owner: str=Depends(mobile.account)):
    check_budget(owner)
    return {'url':checked(body.url),'checkedAt':time.time(),'message':'Page opens publicly. Play-test your game before posting.'}

@router.post('/games', status_code=201)
def submit(body: Submission, owner: str=Depends(mobile.account), authorization: str=Header(default='')):
    if not body.title.strip() or not body.creator.strip() or not body.played:
        raise HTTPException(422, 'Add a title and creator name, then confirm you have opened and played this game.')
    check_budget(owner)
    url=checked(body.url)
    with database() as c:
        c.execute('BEGIN IMMEDIATE')
        if c.execute('SELECT id FROM community_games WHERE url=? AND removed=0',(url,)).fetchone():
            raise HTTPException(409, 'This game link is already in the community.')
        game_id=uuid.uuid4().hex
        now=time.time()
        c.execute('INSERT INTO community_games VALUES(?,?,?,?,?,?,?,?,1,0)', (game_id,owner,body.title.strip(),body.creator.strip(),body.description.strip(),url,now,now))
        # Persist game document to Firestore
        game_doc = {
            'id': game_id,
            'title': body.title.strip(),
            'creator': body.creator.strip(),
            'description': body.description.strip(),
            'url': url,
            'owner': owner,
            'ownerId': owner.removeprefix('firebase:'),
            'createdAt': now,
            'checkedAt': now,
            'reachable': True,
            'removed': False,
            'likes': 0,
            'votes': {cat: 0 for cat in CATEGORIES}
        }
        community_firestore.save_game_to_firestore(game_doc, auth_token=authorization)
        return present(c,c.execute('SELECT * FROM community_games WHERE id=?',(game_id,)).fetchone(),owner)

@router.put('/games/{game_id}/vote')
def vote(game_id: str, body: Vote, owner: str=Depends(mobile.account), authorization: str=Header(default='')):
    if body.category not in CATEGORIES:
        raise HTTPException(422,'Choose a valid leaderboard category.')
    with database() as c:
        c.execute('BEGIN IMMEDIATE')
        row=c.execute('SELECT * FROM community_games WHERE id=? AND removed=0 AND reachable=1',(game_id,)).fetchone()
        if not row: raise HTTPException(404,'This game is not available.')
        if body.liked:
            c.execute('INSERT OR IGNORE INTO community_votes VALUES(?,?,?)',(owner,game_id,body.category))
        else:
            c.execute('DELETE FROM community_votes WHERE owner=? AND game=? AND category=?',(owner,game_id,body.category))
        # Sync vote and updated like counts to Firestore
        user_uid = owner.removeprefix('firebase:')
        community_firestore.record_vote_in_firestore(game_id, user_uid, body.category, body.liked, auth_token=authorization)
        return present(c,row,owner)

@router.get('/games/{game_id}/play')
def play(game_id: str):
    with database() as c:
        row=c.execute('SELECT * FROM community_games WHERE id=? AND removed=0',(game_id,)).fetchone()
        if not row: raise HTTPException(404,'This game is no longer available.')
        # Recheck stale public pages. Recently failed checks are cached too.
        if time.time()-row['checked'] < 3600:
            if not row['reachable']: raise HTTPException(422,'The game link is currently unavailable. Please try later.')
            return {'url':row['url']}
    try:
        url=checked(row['url'])
    except HTTPException:
        with database() as c:
            c.execute('UPDATE community_games SET reachable=0,checked=? WHERE id=?',(time.time(),game_id))
        raise
    with database() as c:
        c.execute('UPDATE community_games SET url=?,reachable=1,checked=? WHERE id=?',(url,time.time(),game_id))
    return {'url':url}

@router.get('/mine')
def mine(owner: str=Depends(mobile.account)):
    owner_uid = owner.removeprefix('firebase:')
    with database() as c:
        return [present(c,r,owner) for r in c.execute('SELECT * FROM community_games WHERE (owner=? OR owner=?) AND removed=0 ORDER BY created DESC',(owner,owner_uid)).fetchall()]

@router.post('/games/{game_id}/recheck')
def recheck(game_id: str, owner: str=Depends(mobile.account), authorization: str=Header(default='')):
    check_budget(owner)
    owner_uid = owner.removeprefix('firebase:')
    with database() as c:
        row=c.execute('SELECT * FROM community_games WHERE id=? AND (owner=? OR owner=?) AND removed=0',(game_id,owner,owner_uid)).fetchone()
        if not row: raise HTTPException(404,'Game not found.')
    url=checked(row['url'])
    now = time.time()
    with database() as c:
        c.execute('UPDATE community_games SET url=?,reachable=1,checked=? WHERE id=?',(url,now,game_id))
    game_fs = community_firestore.get_game_from_firestore(game_id)
    if game_fs:
        game_fs['url'] = url
        game_fs['reachable'] = True
        game_fs['checkedAt'] = now
        community_firestore.save_game_to_firestore(game_fs, auth_token=authorization)
    return {'url':url}

@router.post('/games/{game_id}/report')
def report(game_id: str, body: Report, owner: str=Depends(mobile.account)):
    if not body.reason.strip(): raise HTTPException(422,'Add a reason.')
    with database() as c:
        if not c.execute('SELECT id FROM community_games WHERE id=? AND removed=0',(game_id,)).fetchone(): raise HTTPException(404,'Game not found.')
        c.execute('INSERT OR REPLACE INTO community_reports VALUES(?,?,?,?)',(owner,game_id,body.reason.strip(),time.time()))
    return {'reported':True}

@router.delete('/games/{game_id}')
def remove(game_id: str, owner: str=Depends(mobile.account), authorization: str=Header(default='')):
    owner_uid = owner.removeprefix('firebase:')
    with database() as c:
        row = c.execute('SELECT * FROM community_games WHERE id=? AND removed=0', (game_id,)).fetchone()
        if not row:
            raise HTTPException(404, 'Game not found.')
        if row['owner'] != owner and row['owner'].removeprefix('firebase:') != owner_uid:
            raise HTTPException(403, 'Only the user who created this game can remove it.')
        c.execute('UPDATE community_games SET removed=1 WHERE id=?', (game_id,))
        # Update Firestore
        community_firestore.delete_game_from_firestore(game_id, owner_uid, auth_token=authorization)
    return {'removed':True}
