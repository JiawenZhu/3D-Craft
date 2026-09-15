"""Server-owned community publication, votes and private safety controls.

Reachability is not moderation. A submission stays private until a moderator
reviews the playable content, its metadata and the creator's rights statement.
"""
import hashlib
import json
import re
import random
import time
from typing import Literal

from fastapi import HTTPException
from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from google.api_core.exceptions import Aborted
from pydantic import BaseModel, ConfigDict, Field, StrictBool, field_validator

from .game_links import LinkError, normalize_url, verify_game_url

CATEGORIES = ('fun', 'animation', 'visuals', 'creativity')
Category = Literal['fun', 'animation', 'visuals', 'creativity']


class Submission(BaseModel):
    model_config = ConfigDict(extra='forbid')
    title: str = Field(min_length=1, max_length=100)
    creator: str = Field(min_length=1, max_length=60)
    description: str = Field(default='', max_length=500)
    url: str = Field(min_length=1, max_length=2048)
    played: StrictBool
    rightsConfirmed: StrictBool
    clientId: str = Field(pattern=r'^[A-Za-z0-9_-]{8,120}$')

    @field_validator('title', 'creator', 'description', 'url', mode='before')
    @classmethod
    def trim(cls, value):
        return value.strip() if isinstance(value, str) else value

    @field_validator('played', 'rightsConfirmed')
    @classmethod
    def confirmed(cls, value):
        if not value: raise ValueError('Confirm play-testing and content rights before submitting.')
        return value


class Vote(BaseModel):
    category: Category
    liked: StrictBool


class Report(BaseModel):
    reason: str = Field(min_length=1, max_length=500)

    @field_validator('reason', mode='before')
    @classmethod
    def trim(cls, value): return value.strip() if isinstance(value, str) else value


class GameLink(BaseModel):
    url: str = Field(min_length=1, max_length=2048)


def key(value): return hashlib.sha256(value.encode()).hexdigest()


def valid_id(value):
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', value):
        raise HTTPException(404, 'Game not found.')
    return value


def visible(game, uid=None, blocked=(), hidden=()):
    return bool(game and not game.get('removed') and game.get('moderationStatus') == 'approved'
                and game.get('reachable') is True
                and game.get('ownerId') not in blocked and game.get('id') not in hidden)


def public_game(game, uid=None, categories=()):
    return {**{k: game.get(k, '') for k in ('id', 'title', 'creator', 'description', 'url')},
            'coverUrl': game.get('coverUrl', ''),
            'votes': {c: max(0, int(game.get('votes', {}).get(c, 0))) for c in CATEGORIES},
            'myVotes': sorted(c for c in categories if c in CATEGORIES),
            'isMine': bool(uid and game.get('ownerId') == uid),
            'reachable': game.get('reachable') is True,
            'moderationStatus': game.get('moderationStatus', 'pending'),
            'reviewNote': game.get('reviewNote', '') if game.get('ownerId') == uid else ''}


def apply_vote(game, existing, category, liked):
    votes = {c: max(0, int(game.get('votes', {}).get(c, 0))) for c in CATEGORIES}
    mine = set(existing).intersection(CATEGORIES)
    before = category in mine
    if liked: mine.add(category)
    else: mine.discard(category)
    votes[category] = max(0, votes[category] + int(liked) - int(before))
    return votes, sorted(mine)


class CloudCommunity:
    def __init__(self, db, clock=None, checker=None):
        self.db = db
        self.now = clock or time.time
        self.checker = checker or verify_game_url

    def transact(self, operation):
        # Firestore's decorator retries commit conflicts, but its read phase can
        # also abort under contention. Retry only explicit aborted transactions;
        # never turn a failed write into a success response.
        for attempt in range(4):
            try: return operation(self.db.transaction())
            except (Aborted, ValueError) as exc:
                if not isinstance(exc, Aborted) and not isinstance(exc.__cause__, Aborted): raise
                if attempt == 3:
                    raise HTTPException(503, 'The community is busy. Your change could not be confirmed; please retry.') from None
                time.sleep(random.uniform(0.05, 0.15) * (2 ** attempt))

    def game(self, ident): return self.db.collection('communityGames').document(valid_id(ident))

    def private(self, uid):
        return self.db.collection('users').document(uid).collection('private').document('community')

    def active(self, uid, tx=None, posting=False):
        if self.db.collection('accountDeletions').document(uid).get(transaction=tx).exists:
            raise HTTPException(403, 'This account is being deleted.')
        if posting:
            state = self.private(uid).get(transaction=tx).to_dict() or {}
            if state.get('postingBlocked'):
                raise HTTPException(403, 'Community posting is unavailable for this account. Contact support to appeal.')

    def budget(self, uid, kind, maximum):
        ref = self.private(uid).collection('limits').document(kind)
        @firestore.transactional
        def spend(tx):
            self.active(uid, tx, posting=True)
            data = ref.get(transaction=tx).to_dict() or {}
            now = self.now()
            window = int(now // 600)
            count = data.get('count', 0) if data.get('window') == window else 0
            if count >= maximum: raise HTTPException(429, 'Please wait a few minutes before trying again.')
            tx.set(ref, {'window': window, 'count': count + 1})
        self.transact(spend)

    def check_link(self, uid, url):
        self.budget(uid, 'link-checks', 12)
        try: return self.checker(url)
        except LinkError as exc: raise HTTPException(422, str(exc)) from None

    def submit(self, uid, body: Submission):
        ident = 'cg-' + key(uid + ':' + body.clientId)
        ref = self.game(ident)
        signature = key(json.dumps(body.model_dump(exclude={'clientId'}), sort_keys=True))
        self.active(uid, posting=True)
        prior = ref.get().to_dict()
        if prior:
            if prior.get('requestSignature') != signature:
                raise HTTPException(409, 'This submission was already saved with different details. Start a new submission.')
            return public_game(prior, uid)
        checked = self.check_link(uid, body.url)
        game = dict(id=ident, ownerId=uid, title=body.title, creator=body.creator,
                    description=body.description, url=checked['url'], reachable=True,
                    createdAt=self.now(), updatedAt=self.now(), removed=False,
                    moderationStatus='pending', votes={c: 0 for c in CATEGORIES},
                    rightsConfirmed=True, played=True, termsVersion='2026-09-14',
                    rightsConfirmedAt=self.now(), requestSignature=signature)
        @firestore.transactional
        def save(tx):
            self.active(uid, tx, posting=True)
            existing = ref.get(transaction=tx).to_dict()
            if existing:
                if existing.get('requestSignature') != signature:
                    raise HTTPException(409, 'This submission was already saved with different details.')
                return public_game(existing, uid)
            tx.create(ref, game)
            return public_game(game, uid)
        return self.transact(save)

    def filters(self, uid):
        if not uid: return set(), set()
        self.active(uid)
        ref = self.private(uid)
        blocked = {d.to_dict()['ownerId'] for d in ref.collection('blocks').stream()}
        hidden = {d.id for d in ref.collection('hidden').stream()}
        return blocked, hidden

    def present(self, data, uid):
        cats = []
        if uid:
            cats = (self.game(data['id']).collection('votes').document(uid).get().to_dict() or {}).get('categories', [])
        return public_game(data, uid, cats)

    def feed(self, category='fun', offset=0, uid=None):
        blocked, hidden = self.filters(uid)
        query = (self.db.collection('communityGames')
                 .where(filter=FieldFilter('moderationStatus', '==', 'approved'))
                 .where(filter=FieldFilter('removed', '==', False))
                 .order_by('votes.' + category, direction=firestore.Query.DESCENDING)
                 .order_by('createdAt', direction=firestore.Query.DESCENDING))
        # Offset counts database rows, not visible rows; blocked games cannot
        # repeat or prematurely end pagination. Bound the work for each request.
        rows, scanned, exhausted = [], 0, False
        while len(rows) < 30 and scanned < 300:
            batch = list(query.offset(offset + scanned).limit(30).stream())
            if not batch:
                exhausted = True
                break
            consumed = 0
            for doc in batch:
                consumed += 1
                scanned += 1
                data = doc.to_dict()
                if visible(data, uid, blocked, hidden): rows.append(self.present(data, uid))
                if len(rows) == 30: break
            if len(batch) < 30 and consumed == len(batch):
                exhausted = True
                break
        return dict(games=rows, hasMore=not exhausted, nextOffset=offset + scanned)

    def mine(self, uid):
        self.active(uid)
        query = self.db.collection('communityGames').where(filter=FieldFilter('ownerId', '==', uid))
        return [self.present(d, uid) for d in sorted((s.to_dict() for s in query.stream()),
                key=lambda d: d.get('createdAt', 0), reverse=True) if not d.get('removed')]

    def allowed(self, tx, ref, uid):
        if uid: self.active(uid, tx)
        data = ref.get(transaction=tx).to_dict()
        blocked = hidden = False
        if uid and data:
            blocked = self.private(uid).collection('blocks').document(key(data['ownerId'])).get(transaction=tx).exists
            hidden = self.private(uid).collection('hidden').document(ref.id).get(transaction=tx).exists
        if not visible(data) or blocked or hidden:
            raise HTTPException(404, 'This game is no longer available in your community.')
        return data

    def play(self, ident, uid=None):
        @firestore.transactional
        def read(tx): return self.allowed(tx, self.game(ident), uid)
        data = self.transact(read)
        try: url = normalize_url(data['url'])
        except LinkError: raise HTTPException(404, 'This game link is unavailable.') from None
        return {'url': url}

    def vote(self, uid, ident, body: Vote):
        ref = self.game(ident)
        vote = ref.collection('votes').document(uid)
        @firestore.transactional
        def save(tx):
            data = self.allowed(tx, ref, uid)
            before = (vote.get(transaction=tx).to_dict() or {}).get('categories', [])
            counts, cats = apply_vote(data, before, body.category, body.liked)
            tx.set(vote, {'userId': uid, 'categories': cats, 'updatedAt': self.now()})
            tx.update(ref, {'votes': counts, 'updatedAt': self.now()})
            return dict(votes=counts, myVotes=cats)
        return self.transact(save)

    def remove(self, uid, ident):
        ref = self.game(ident)
        @firestore.transactional
        def save(tx):
            self.active(uid, tx)
            data = ref.get(transaction=tx).to_dict() or {}
            if data.get('ownerId') != uid: raise HTTPException(404, 'Your submission was not found.')
            tx.update(ref, {'removed': True, 'updatedAt': self.now()})
        self.transact(save)
        return {'removed': True}

    def recheck(self, uid, ident):
        ref = self.game(ident)
        data = ref.get().to_dict() or {}
        if data.get('ownerId') != uid or data.get('removed'):
            raise HTTPException(404, 'Your submission was not found.')
        failure = None
        try: checked = self.check_link(uid, data['url'])
        except HTTPException as exc:
            if exc.status_code != 422: raise
            failure, checked = exc, {'url': data['url']}
        @firestore.transactional
        def save(tx):
            self.active(uid, tx, posting=True)
            current = ref.get(transaction=tx).to_dict() or {}
            if current.get('ownerId') != uid or current.get('removed'):
                raise HTTPException(404, 'Your submission was not found.')
            # A changed redirect target needs another review before publication.
            changes = {'reachable': failure is None, 'updatedAt': self.now()}
            if current.get('url') != checked['url']:
                changes.update(url=checked['url'], moderationStatus='pending')
            tx.update(ref, changes)
        self.transact(save)
        if failure: raise failure
        return {'status': 'rechecked'}

    def report(self, uid, ident, body: Report):
        ref = self.game(ident)
        report = self.db.collection('communityReports').document(key(uid + ':' + ident))
        hidden = self.private(uid).collection('hidden').document(ident)
        @firestore.transactional
        def save(tx):
            self.active(uid, tx)
            data = ref.get(transaction=tx).to_dict() or {}
            prior = report.get(transaction=tx).to_dict()
            if prior: return {'reported': True}
            if not visible(data): raise HTTPException(404, 'This game is no longer available.')
            tx.create(report, dict(gameId=ident, reporterId=uid, ownerId=data['ownerId'],
                                  reason=body.reason, status='open', createdAt=self.now()))
            tx.set(hidden, {'createdAt': self.now()})
            return {'reported': True}
        return self.transact(save)

    def block(self, uid, ident):
        ref = self.game(ident)
        @firestore.transactional
        def save(tx):
            self.active(uid, tx)
            data = ref.get(transaction=tx).to_dict() or {}
            if not visible(data): raise HTTPException(404, 'This game is no longer available.')
            if data['ownerId'] == uid: raise HTTPException(422, 'You cannot block your own account.')
            target = self.private(uid).collection('blocks').document(key(data['ownerId']))
            tx.set(target, dict(ownerId=data['ownerId'], creator=data['creator'], createdAt=self.now()))
        self.transact(save)
        return {'blocked': True}

    def blocks(self, uid):
        self.active(uid)
        return [dict(id=d.id, creator=d.to_dict().get('creator', 'Creator'))
                for d in self.private(uid).collection('blocks').stream()]

    def unblock(self, uid, ident):
        valid_id(ident)
        @firestore.transactional
        def save(tx):
            self.active(uid, tx)
            tx.delete(self.private(uid).collection('blocks').document(ident))
        self.transact(save)
        return {'blocked': False}

    def moderate(self, ident, decision, reason, actor):
        """Operator CLI only; no client-controlled administrator endpoint."""
        if decision not in ('approved', 'rejected') or not reason.strip() or not actor.strip():
            raise ValueError('A decision, review reason and operator identity are required.')
        ref = self.game(ident)
        audit = self.db.collection('communityModeration').document()
        @firestore.transactional
        def save(tx):
            data = ref.get(transaction=tx).to_dict() or {}
            if not data: raise ValueError('Game not found.')
            if decision == 'approved': self.active(data['ownerId'], tx, posting=True)
            if decision == 'approved' and not (data.get('rightsConfirmed') and data.get('played') and data.get('reachable')):
                raise ValueError('Creator rights, play-test confirmation and reachability are required.')
            tx.update(ref, {'moderationStatus': decision, 'reviewNote': reason,
                            'moderatedAt': self.now(), 'updatedAt': self.now()})
            tx.create(audit, dict(gameId=ident, ownerId=data['ownerId'], decision=decision,
                                 reason=reason, operator=actor, createdAt=self.now()))
        self.transact(save)

    def resolve_report(self, ident, reason, actor):
        if not reason.strip() or not actor.strip(): raise ValueError('An outcome and operator identity are required.')
        ref = self.db.collection('communityReports').document(valid_id(ident))
        @firestore.transactional
        def save(tx):
            if not ref.get(transaction=tx).exists: raise ValueError('Report not found.')
            tx.update(ref, dict(status='resolved', resolution=reason, operator=actor, resolvedAt=self.now()))
        self.transact(save)

    def restrict_posting(self, uid, restricted, reason, actor):
        if not reason.strip() or not actor.strip(): raise ValueError('A reason and operator identity are required.')
        # Blocking submissions and removing existing publications are separate
        # recorded operations, so an appeal does not republish removed content.
        self.private(uid).set(dict(postingBlocked=bool(restricted), restrictionReason=reason,
                                   restrictionOperator=actor, restrictionUpdatedAt=self.now()), merge=True)
