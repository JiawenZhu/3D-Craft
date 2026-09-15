import unittest
from server.commerce import usage_quote, policy, plan_economics

class CommerceTests(unittest.TestCase):
 def test_all_stages_one_markup(self):
  q=usage_quote([{'id':'chat','providerUsd':'.002'},{'id':'image','providerUsd':'.134'},{'id':'shape','providerUsd':'.16'},{'id':'texture','providerUsd':'.32'}])
  self.assertEqual(q['providerUsd'],'0.616')
  self.assertEqual(q['serviceFeeUsd'],'0.09240')
  self.assertEqual(q['totalUsageUsd'],'0.70840')
  self.assertEqual(q['credits'],71)
 def test_unknown_cannot_be_free(self):
  q=usage_quote([{'id':'future','providerUsd':None},{'id':'shape','providerUsd':'.4'}])
  self.assertFalse(q['complete']);self.assertIsNone(q['credits']);self.assertIsNone(q['serviceFeeUsd'])
 def test_account_included_is_explicit_zero(self):
  self.assertEqual(usage_quote([{'id':'account','providerUsd':0}])['credits'],0)
 def test_reject_duplicate_or_invalid_cost(self):
  for value in [-1,'NaN','Infinity',True]:
   with self.assertRaises(ValueError):usage_quote([{'id':'x','providerUsd':value}])
  with self.assertRaises(ValueError):usage_quote([{'id':'x','providerUsd':1}]*2)
 def test_plan_budget_covers_full_usage_at_30_plus_1_percent(self):
  from decimal import Decimal
  for plan in policy()['plans']+policy()['topups']:
   self.assertGreaterEqual(Decimal(plan_economics(plan)['reserveAfterUsageBudgetUsd']),0)
 def test_only_weekly_monthly_and_consistent_credit_value(self):
  p=policy();self.assertEqual([x['period'] for x in p['plans']],['week','month']);self.assertEqual(p['creditUsageUsd'],'0.01')
 def test_complete_creation_examples_and_allowances(self):
  for images,expected in [(1,62),(4,108)]:
   q=usage_quote([{'id':'planning','providerUsd':'.0013'},{'id':'images','providerUsd':str(images*.134)},{'id':'rodin','providerUsd':'.40'}])
   self.assertEqual(q['credits'],expected)
  self.assertEqual([p['credits']//62 for p in policy()['plans']],[4,13])
