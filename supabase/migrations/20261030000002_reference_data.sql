-- =============================================================================
-- Coupon Pro IA — LOT 1 — Données de référence
-- Rôles, permissions, feature flags (tous désactivés tant que leur lot n'est pas
-- livré) et réglages publics. Idempotent : peut être rejoué sans doublon.
-- =============================================================================

insert into public.roles (id, label, rank) values
  ('visitor',     'Visiteur',             0),
  ('user',        'Utilisateur',          10),
  ('subscriber',  'Abonné',               20),
  ('tipster',     'Tipster',              30),
  ('moderator',   'Modérateur',           40),
  ('admin',       'Administrateur',       50),
  ('super_admin', 'Super administrateur', 60)
on conflict (id) do update set label = excluded.label, rank = excluded.rank;

insert into public.permissions (id, description) values
  ('admin.access',       'Accéder à l''espace d''administration'),
  ('users.manage',       'Consulter les utilisateurs, gérer leurs rôles (hors administrateurs) et les suspendre'),
  ('admins.manage',      'Nommer, retirer ou suspendre des administrateurs'),
  ('flags.manage',       'Activer ou désactiver les modules (feature flags)'),
  ('settings.manage',    'Modifier les réglages de la plateforme'),
  ('audit.read',         'Consulter le journal d''audit'),
  ('sports.configure',   'Configurer le fournisseur de données sportives (LOT 2)'),
  ('ai.configure',       'Configurer les fournisseurs, modèles et prompts IA (LOT 3)'),
  ('generation.manage',  'Gérer les profils et horaires de génération automatique (LOT 4)'),
  ('coupons.publish',    'Valider, publier et dépublier les coupons de la plateforme (LOT 4)'),
  ('billing.manage',     'Gérer forfaits, crédits, paiements et promotions (LOT 9)'),
  ('moderation.manage',  'Modérer publications, commentaires et signalements (LOT 10)'),
  ('tipster.publish',    'Publier des coupons sur un profil Tipster public (LOT 10)')
on conflict (id) do update set description = excluded.description;

-- Affectation des permissions aux rôles
insert into public.role_permissions (role_id, permission_id) values
  ('tipster',   'tipster.publish'),
  ('moderator', 'moderation.manage'),
  ('admin',     'admin.access'),
  ('admin',     'users.manage'),
  ('admin',     'flags.manage'),
  ('admin',     'settings.manage'),
  ('admin',     'audit.read'),
  ('admin',     'sports.configure'),
  ('admin',     'ai.configure'),
  ('admin',     'generation.manage'),
  ('admin',     'coupons.publish'),
  ('admin',     'billing.manage'),
  ('admin',     'moderation.manage')
on conflict do nothing;

-- Le super administrateur possède toutes les permissions, présentes et futures
-- (une migration qui ajoute une permission doit aussi l'ajouter ici).
insert into public.role_permissions (role_id, permission_id)
select 'super_admin', id from public.permissions
on conflict do nothing;

-- Feature flags : un interrupteur par module, désactivé jusqu'à la livraison du lot
insert into public.feature_flags (key, enabled, description) values
  ('maintenance_mode',            false, 'Affiche un écran de maintenance à tous les utilisateurs'),
  ('match_analysis',              false, 'Matchs et analyse IA des rencontres (LOTS 2-3)'),
  ('auto_generation_scheduled',   false, 'Génération automatique programmée des coupons (LOT 4)'),
  ('auto_generation_continuous',  false, 'Génération automatique continue des coupons (LOT 4)'),
  ('assistant_ia',                false, 'Mon Assistant IA (LOT 5)'),
  ('ai_lab',                      false, 'Laboratoire IA et générateur manuel (LOT 6)'),
  ('results_tracking',            false, 'Suivi des résultats et performances (LOT 8)'),
  ('subscriptions',               false, 'Forfaits et crédits IA (LOT 9)'),
  ('payments',                    false, 'Paiements Mobile Money (LOT 9)'),
  ('graphic_studio',              false, 'Studio graphique (LOT 7)'),
  ('tipsters',                    false, 'Profils Tipsters (LOT 10)'),
  ('community',                   false, 'Communauté : publications, commentaires (LOT 10)'),
  ('notifications',               false, 'Notifications push (FCM)')
on conflict (key) do update set description = excluded.description;

-- Réglages. Les tarifs suivent la décision D6 (grille du prompt) ; ce sont des
-- valeurs de configuration, migrées vers les tables billing au LOT 9.
insert into public.app_settings (key, value, is_public, description) values
  ('app.timezone', '"Africa/Ouagadougou"'::jsonb, true,
   'Fuseau horaire de référence'),
  ('app.currency', '{"code": "XOF", "label": "FCFA"}'::jsonb, true,
   'Devise principale'),
  ('app.support_email', 'null'::jsonb, true,
   'Adresse de support affichée dans l''app (à renseigner)'),
  ('pricing.plans',
   '[
      {"code": "FREE",        "name": "FREE",        "monthly_xof": 0,     "ai_credits": 2},
      {"code": "STARTER",     "name": "STARTER",     "monthly_xof": 2000,  "ai_credits": 10},
      {"code": "PRO_TIPSTER", "name": "PRO TIPSTER", "monthly_xof": 5000,  "ai_credits": 50},
      {"code": "BUSINESS",    "name": "BUSINESS",    "monthly_xof": 10000, "ai_credits": 150}
    ]'::jsonb, true,
   'Grille tarifaire de lancement (décision D6 du 30/10/2026), configurable'),
  ('pricing.credit_pack', '{"credits": 10, "price_xof": 500}'::jsonb, true,
   'Pack de crédits IA supplémentaire (hypothèse à tester)'),
  ('legal.disclaimers',
   '[
      "Les pronostics sont des estimations, pas des certitudes.",
      "Les résultats sportifs sont incertains.",
      "Les performances passées ne garantissent pas les performances futures.",
      "Les probabilités affichées sont des estimations.",
      "Les cotes peuvent changer à tout moment.",
      "Les données peuvent être incomplètes.",
      "Aucun gain n''est garanti.",
      "Coupon Pro IA n''est pas un bookmaker : aucun pari n''est placé dans l''application.",
      "Service réservé aux personnes majeures."
    ]'::jsonb, true,
   'Mentions de responsabilité affichées dans l''application'),
  ('auth.min_password_length', '8'::jsonb, true,
   'Longueur minimale du mot de passe (doit correspondre au réglage Supabase Auth)')
on conflict (key) do nothing;
