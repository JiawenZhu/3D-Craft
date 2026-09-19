// Run: node --experimental-strip-types --test tests/ui/apiKeys.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CURL_EXAMPLE, DEFAULT_EXPIRY, EXPIRY_OPTIONS, describeScopes, displayPrefix, keyStatus, parseCreatedKey,
  parseKeyList, requestScopes, validateKeyName,
} from '../../src/lib/apiKeys.ts';

test('expiry defaults to 90 days with 30/90/365 choices', () => {
  assert.equal(DEFAULT_EXPIRY, 90);
  assert.deepEqual([...EXPIRY_OPTIONS], [30, 90, 365]);
});

test('scopes: full access sends *, custom keeps known scopes, empty is rejected', () => {
  assert.deepEqual(requestScopes(true, []), ['*']);
  assert.deepEqual(requestScopes(false, ['wallet:read', 'bogus', 'assets:read']), ['assets:read', 'wallet:read']);
  assert.equal(requestScopes(false, []), null);
  assert.equal(describeScopes(['*']), 'Full API access');
  assert.deepEqual(requestScopes(true, [], true), ['*', 'assets:delete']);
  assert.deepEqual(requestScopes(false, ['assets:read'], true), ['assets:read', 'assets:delete']);
  assert.equal(requestScopes(false, [], true), null);
  assert.equal(describeScopes(['*', 'assets:delete']), 'Full API access · Can delete');
});

test('names are trimmed and bounded', () => {
  assert.ok(validateKeyName('   '));
  assert.ok(validateKeyName('x'.repeat(65)));
  assert.equal(validateKeyName(' ChatGPT '), null);
});

test('status reflects revocation and expiry', () => {
  assert.equal(keyStatus({ revoked: true, expiresAt: null }), 'revoked');
  assert.equal(keyStatus({ revoked: false, expiresAt: 100 }, 200), 'expired');
  assert.equal(keyStatus({ revoked: false, expiresAt: null }, 200), 'active');
});

test('list parsing whitelists metadata and drops secrets/hashes', () => {
  const [k] = parseKeyList({ keys: [
    { id: 'key_1', name: 'A', prefix: 'craft_live_abc123...', scopes: ['*'], createdAt: 5, expiresAt: null,
      revoked: false, revokedAt: null, lastUsedAt: null, key: 'craft_live_SECRET', keyHash: 'deadbeef' },
    { name: 'no id' },
  ] });
  assert.equal(parseKeyList({ keys: [{ id: 'a' }, { name: 'no id' }] }).length, 1);
  assert.ok(!('key' in k) && !('keyHash' in k));
  assert.equal(displayPrefix(k.prefix), 'craft_live_abc123…');
});

test('created key requires a craft_live_ secret', () => {
  assert.equal(parseCreatedKey({ id: 'key_1', key: 'sk-other' }), null);
  assert.equal(parseCreatedKey({ id: 'key_1', key: 'craft_live_x', warning: 'w' })?.key, 'craft_live_x');
});

test('example request uses a placeholder, never a secret', () => {
  assert.match(CURL_EXAMPLE, /\$CRAFT_API_KEY/);
  assert.doesNotMatch(CURL_EXAMPLE, /craft_live_/);
});
