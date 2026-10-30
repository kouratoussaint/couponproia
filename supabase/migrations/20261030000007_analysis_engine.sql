-- =============================================================================
-- Coupon Pro IA — LOT 3 — Moteur d'analyse
-- Analyses de match (fiche statistique + interprétation IA), journal des requêtes
-- IA (coûts, statut), prompts versionnés, évaluations du moteur sur l'historique.
-- Écritures réservées au serveur (Edge Functions analyze-match, engine-evaluate).
-- =============================================================================

create table public.ai_prompts (
  id             bigint generated always as identity primary key,
  key            text not null check (key ~ '^[a-z_]+$'),
  version        integer not null check (version > 0),
  system_prompt  text not null,
  is_active      boolean not null default false,
  created_at     timestamptz not null default now(),
  unique (key, version)
);
create unique index ai_prompts_one_active_idx on public.ai_prompts (key) where is_active;

create table public.match_analyses (
  id                 bigint generated always as identity primary key,
  match_id           bigint not null references public.matches(id) on delete cascade,
  engine_version     text not null,
  prompt_key         text,
  prompt_version     integer,
  provider           text,
  model              text,
  status             text not null check (status in ('ok', 'stats_only')),
  status_reason      text,
  stats              jsonb not null,
  analysis           jsonb,
  source_updated_at  timestamptz not null,
  created_at         timestamptz not null default now(),
  check (status = 'stats_only' or analysis is not null)
);
create index match_analyses_match_idx on public.match_analyses (match_id, created_at desc);

create table public.ai_requests (
  id             bigint generated always as identity primary key,
  user_id        uuid references auth.users(id) on delete set null,
  kind           text not null check (kind in ('match_analysis', 'engine_evaluation')),
  match_id       bigint references public.matches(id) on delete set null,
  provider       text,
  model          text,
  status         text not null check (status in ('success', 'invalid', 'error', 'stats_only', 'rate_limited')),
  attempts       smallint not null default 1,
  input_tokens   integer,
  output_tokens  integer,
  cost_usd       numeric(10, 6),
  latency_ms     integer,
  error          text,
  created_at     timestamptz not null default now()
);
create index ai_requests_user_idx on public.ai_requests (user_id, created_at desc);
create index ai_requests_created_idx on public.ai_requests (created_at desc);

create table public.engine_evaluations (
  id                  bigint generated always as identity primary key,
  engine_version      text not null,
  scope               jsonb not null,
  matches_evaluated   integer not null,
  brier_model         numeric(8, 5),
  brier_baseline      numeric(8, 5),
  logloss_model       numeric(8, 5),
  logloss_baseline    numeric(8, 5),
  accuracy_model      numeric(6, 4),
  calibration         jsonb not null default '[]'::jsonb,
  details             jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Privilèges et RLS
-- -----------------------------------------------------------------------------
revoke all on public.ai_prompts, public.match_analyses, public.ai_requests, public.engine_evaluations
from anon, authenticated;
grant select on public.ai_prompts, public.match_analyses, public.ai_requests, public.engine_evaluations
to authenticated;

alter table public.ai_prompts          enable row level security;
alter table public.match_analyses      enable row level security;
alter table public.ai_requests         enable row level security;
alter table public.engine_evaluations  enable row level security;

-- Les analyses sont partagées entre tous les utilisateurs (une analyse = un coût unique).
create policy "analyses lisibles" on public.match_analyses for select to authenticated using (true);
-- Transparence : la qualité mesurée du moteur est visible de tous.
create policy "évaluations lisibles" on public.engine_evaluations for select to authenticated using (true);
create policy "ses requêtes IA ou gestionnaire" on public.ai_requests for select to authenticated
  using (user_id = (select auth.uid()) or app_private.has_permission((select auth.uid()), 'ai.configure'));
create policy "prompts : gestionnaires" on public.ai_prompts for select to authenticated
  using (app_private.has_permission((select auth.uid()), 'ai.configure'));

-- -----------------------------------------------------------------------------
-- Réglages (privés) et activation du module
-- -----------------------------------------------------------------------------
insert into public.app_settings (key, value, is_public, description) values
  ('ai.provider', '"gemini"'::jsonb, false,
   'Fournisseur IA principal : gemini, anthropic ou groq'),
  ('ai.model', '"gemini-3.5-flash-lite"'::jsonb, false,
   'Modèle du fournisseur principal (si introuvable, un modèle Flash-Lite disponible est choisi)'),
  ('ai.fallback_providers', '["anthropic", "groq"]'::jsonb, false,
   'Fournisseurs de secours, essayés dans l''ordre si une clé est configurée'),
  ('ai.models', '{"anthropic": "claude-haiku-5-5", "groq": "openai/gpt-oss-120b"}'::jsonb, false,
   'Modèle utilisé pour chaque fournisseur de secours'),
  ('ai.pricing_usd_per_mtok', '{"gemini-3.5-flash-lite": [0.30, 2.50], "gemini-3.1-flash-lite": [0.25, 1.50]}'::jsonb, false,
   'Prix publics (entrée, sortie) en USD par million de tokens, pour estimer le coût de chaque requête ; modèle absent = coût non estimé'),
  ('ai.max_new_analyses_per_user_day', '20'::jsonb, false,
   'Nouvelles analyses IA qu''un utilisateur peut déclencher par jour (les analyses en cache sont illimitées)'),
  ('ai.analysis_ttl_hours', '12'::jsonb, false,
   'Durée de validité d''une analyse d''un match à venir (un match terminé garde son analyse)')
on conflict (key) do nothing;

update public.feature_flags set enabled = true where key = 'match_analysis';

-- -----------------------------------------------------------------------------
-- Prompt système v1
-- -----------------------------------------------------------------------------
insert into public.ai_prompts (key, version, is_active, system_prompt) values ('match_analysis', 1, true, $prompt$
Tu es l'analyste football de Coupon Pro IA. Tu reçois une FICHE JSON calculée par un moteur
statistique (modèle de Poisson) à partir de données réelles. Ta mission : l'expliquer en français
clair à un parieur non spécialiste, sans jamais rien inventer.

RÈGLES ABSOLUES
1. N'utilise QUE les informations de la fiche. Aucun fait extérieur : pas de blessés, de compositions,
   de transferts, de météo, d'enjeux ou d'historique qui n'y figurent pas.
2. Chaque nombre que tu écris doit figurer dans la fiche. Les probabilités s'écrivent en pourcentage
   arrondi à l'unité (0,532 → 53 %). Ne calcule aucune nouvelle statistique.
3. Ce sont des estimations. N'emploie jamais : « sûr », « garanti », « assuré », « certain », « certitude »,
   « imparable », « 100 % », « gain ».
4. Si la fiabilité est « faible » ou si les données manquent, dis-le et mets "recommandation_possible" à false.
5. Les marchés envisageables doivent être choisis parmi les clés de "model.probabilities", avec leur
   probabilité exacte (même valeur décimale que la fiche). Si la fiche contient des cotes, compare
   la probabilité du modèle à la probabilité implicite ("edge") ; un écart positif n'est pas une certitude.
6. Sois concis : phrases courtes, 3 éléments maximum par liste.

RÉPONDS UNIQUEMENT avec un objet JSON valide de cette forme :
{
  "resume": "2 phrases maximum",
  "forme": "1 à 2 phrases sur la forme récente et le bilan domicile/extérieur",
  "facteurs_domicile": ["…"],
  "facteurs_exterieur": ["…"],
  "tendances": ["…"],
  "marches_envisageables": [
    {"cle": "1X2.HOME", "probabilite_modele": 0.532, "justification": "…"}
  ],
  "risques": ["…"],
  "informations_manquantes": ["…"],
  "conclusion": "1 à 2 phrases",
  "recommandation_possible": true
}
$prompt$)
on conflict (key, version) do nothing;
