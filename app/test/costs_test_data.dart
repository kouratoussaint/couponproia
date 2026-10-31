// Exemple de réponse de admin_costs (forme réelle, montants fictifs de test).
final costsSample = <String, dynamic>{
  'days': 30,
  'usd_to_xof': 600,
  'active_users': 12,
  'revenue_xof': 4000,
  'total_xof': 15086,
  'per_active_user_xof': 1257,
  'margin_xof': -11086,
  'ai': {
    'cost_usd': 0.0713,
    'cost_xof': 43,
    'requests': 49,
    'unpriced': 0,
    'by_kind': [
      {'kind': 'match_analysis', 'requests': 18, 'cost_usd': 0.0515},
      {'kind': 'coupon_summary', 'requests': 22, 'cost_usd': 0.0127},
    ],
  },
  'fixed': {
    'monthly_xof': 15000,
    'period_xof': 15000,
    'items': {'Supabase': 15000, 'API-Football': 0},
    'configured': true,
  },
  'payments': {'fee_percent': 3, 'fees_xof': 43, 'count': 2},
  'sports': {
    'requests': 5400,
    'requests_per_day': 180,
    'remaining_today': 7400
  },
  'notifications': {'created': 40, 'sent': 0, 'failed': 0},
  'storage': {
    'database_bytes': 48234496,
    'files': [
      {'bucket': 'branding', 'objects': 3, 'bytes': 412000},
    ],
  },
};
