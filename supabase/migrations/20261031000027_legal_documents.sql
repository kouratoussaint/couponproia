-- LOT 12 : conditions générales d'utilisation, politique de confidentialité, règles de la communauté.
--  - Documents versionnés côté serveur : une nouvelle version se publie depuis la console, sans
--    nouvelle version de l'app ; les anciennes versions sont conservées.
--  - Lisibles sans connexion (à lire avant l'inscription).
--  - Acceptation enregistrée par utilisateur et par version ; une nouvelle version des CGU ou de
--    la politique de confidentialité redemande l'acceptation.
--  - Les champs {{editeur}}, {{forme}}, {{adresse}}, {{pays}}, {{immatriculation}} et {{contact}}
--    viennent du réglage public legal.editor (et app.support_email), complétés par le propriétaire.
--  TEXTES À FAIRE RELIRE PAR UN JURISTE AVANT L'OUVERTURE COMMERCIALE.

create table public.legal_documents (
  id            bigint generated always as identity primary key,
  code          text not null check (code in ('terms', 'privacy', 'community')),
  version       text not null check (version ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}(\.[0-9]+)?$'),
  title         text not null check (char_length(title) between 3 and 120),
  body          text not null check (char_length(body) between 50 and 60000),
  requires_acceptance boolean not null,
  published_at  timestamptz not null default now(),
  published_by  uuid references auth.users(id) on delete set null,
  unique (code, version)
);
create index legal_documents_published_by_fk_idx on public.legal_documents (published_by);
create index legal_documents_current_idx on public.legal_documents (code, published_at desc);

create table public.legal_acceptances (
  user_id      uuid not null references auth.users(id) on delete cascade,
  document_id  bigint not null references public.legal_documents(id) on delete cascade,
  accepted_at  timestamptz not null default now(),
  primary key (user_id, document_id)
);
create index legal_acceptances_document_fk_idx on public.legal_acceptances (document_id);

alter table public.legal_documents enable row level security;
alter table public.legal_acceptances enable row level security;
revoke all on public.legal_documents, public.legal_acceptances from anon, authenticated;
grant select on public.legal_documents to anon, authenticated;
create policy "documents légaux publics" on public.legal_documents for select to anon, authenticated using (true);
grant select on public.legal_acceptances to authenticated;
create policy "ses acceptations" on public.legal_acceptances for select to authenticated
  using (user_id = (select auth.uid()));

-- Identité de l'éditeur (affichée dans les documents) : à compléter par le propriétaire.
insert into public.app_settings (key, value, is_public, description) values
  ('legal.editor',
   '{"name": "", "legal_form": "", "address": "", "country": "Burkina Faso", "registration": ""}'::jsonb, true,
   'Éditeur affiché dans les CGU et la politique de confidentialité : nom ou raison sociale, forme juridique, adresse, pays, immatriculation (RCCM, IFU…). Contact : app.support_email.')
on conflict (key) do nothing;

-- Dernière version de chaque document.
create or replace function app_private.current_legal(p_code text)
returns public.legal_documents
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.legal_documents where code = p_code order by published_at desc, id desc limit 1;
$$;
revoke all on function app_private.current_legal(text) from public, anon, authenticated;

-- État pour l'utilisateur connecté : documents à accepter qui ne l'ont pas encore été.
create or replace function public.my_legal_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  return jsonb_build_object('pending', coalesce((
    select jsonb_agg(jsonb_build_object('id', d.id, 'code', d.code, 'version', d.version, 'title', d.title)
                     order by d.code desc)
    from (select (app_private.current_legal(c)).* from unnest(array['terms', 'privacy']) c) d
    where d.id is not null and d.requires_acceptance
      and not exists (select 1 from public.legal_acceptances a where a.user_id = v_uid and a.document_id = d.id)
  ), '[]'::jsonb));
end;
$$;

-- Acceptation des versions lues (identifiants renvoyés par my_legal_status).
create or replace function public.accept_legal(p_document_ids bigint[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_id bigint;
begin
  if v_uid is null then
    raise exception 'Connexion requise' using errcode = '42501';
  end if;
  foreach v_id in array coalesce(p_document_ids, '{}') loop
    -- Seule la version en vigueur d'un document peut être acceptée.
    if not exists (select 1 from public.legal_documents d
                   where d.id = v_id and d.id = (app_private.current_legal(d.code)).id) then
      raise exception 'Version de document périmée ou inconnue' using errcode = '22023';
    end if;
    insert into public.legal_acceptances (user_id, document_id) values (v_uid, v_id) on conflict do nothing;
  end loop;
  return public.my_legal_status();
end;
$$;

-- Publication d'une nouvelle version (console), journalisée.
create or replace function public.admin_publish_legal(p_code text, p_version text, p_title text, p_body text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_row public.legal_documents;
begin
  if v_actor is null or not app_private.has_permission(v_actor, 'settings.manage') then
    raise exception 'Permission refusée' using errcode = '42501';
  end if;
  if p_code not in ('terms', 'privacy', 'community') then
    raise exception 'Document inconnu' using errcode = '22023';
  end if;
  if exists (select 1 from public.legal_documents where code = p_code and version = p_version) then
    raise exception 'Cette version existe déjà' using errcode = '22023';
  end if;
  insert into public.legal_documents (code, version, title, body, requires_acceptance, published_by)
  values (p_code, p_version, trim(p_title), p_body, p_code in ('terms', 'privacy'), v_actor)
  returning * into v_row;
  insert into public.audit_logs (actor_id, action, target_type, target_id, details)
  values (v_actor, 'legal.publish', 'legal_document', v_row.id::text,
          jsonb_build_object('code', p_code, 'version', p_version));
  return jsonb_build_object('id', v_row.id, 'code', v_row.code, 'version', v_row.version);
end;
$$;

revoke all on function public.my_legal_status(), public.accept_legal(bigint[]),
  public.admin_publish_legal(text, text, text, text) from public, anon;
grant execute on function public.my_legal_status(), public.accept_legal(bigint[]),
  public.admin_publish_legal(text, text, text, text) to authenticated;

-- -----------------------------------------------------------------------------
-- Versions initiales (31/10/2026)
-- -----------------------------------------------------------------------------
insert into public.legal_documents (code, version, title, requires_acceptance, body) values
('terms', '2026-10-31', 'Conditions générales d''utilisation', true, $terms$
## 1. Objet et éditeur
Les présentes conditions encadrent l'utilisation de l'application Coupon Pro IA (le « Service »), éditée par {{editeur}} {{forme}}, {{adresse}}, {{pays}}, {{immatriculation}}. Contact : {{contact}}.
Créer un compte et utiliser le Service suppose d'avoir lu et accepté ces conditions et la politique de confidentialité.

## 2. Ce que propose le Service
Coupon Pro IA est une plateforme d'analyse du football et de création de contenus de pronostics :
- analyses de matchs, probabilités estimées par un modèle statistique et commentaires rédigés avec l'aide d'une intelligence artificielle à partir de données vérifiées ;
- coupons proposés par la plateforme, assistant de création de coupons, laboratoire, studio graphique ;
- espace communautaire et profils Tipsters ;
- suivi des résultats et statistiques calculées par la plateforme.
**Coupon Pro IA n'est pas un bookmaker.** Aucun pari n'est pris, placé ou encaissé dans l'application, et aucun coupon créé dans l'application ne correspond à un pari réellement placé.

## 3. Nature des contenus
- Les pronostics et probabilités sont des **estimations**, jamais des certitudes. Les résultats sportifs sont incertains.
- Les performances passées ne garantissent pas les performances futures. **Aucun gain n'est garanti.**
- Les cotes affichées proviennent de sources tierces à un instant donné et peuvent changer à tout moment.
- Les données sportives (calendriers, compositions, absents, scores) proviennent de fournisseurs tiers et peuvent être incomplètes ou en retard ; elles sont affichées telles que reçues.
- Les décisions de pari éventuellement prises ailleurs relèvent de la seule responsabilité de l'utilisateur. L'éditeur ne peut être tenu responsable d'une perte liée à un pari placé auprès d'un opérateur tiers.

## 4. Accès et compte
- Le Service est **réservé aux personnes majeures** (18 ans ou âge de la majorité dans leur pays si celui-ci est plus élevé).
- L'utilisateur fournit une adresse e-mail valide, garde son mot de passe confidentiel et reste responsable de l'usage de son compte.
- Un compte est personnel. Les comptes créés pour contourner une limite, une suspension ou un quota peuvent être supprimés.

## 5. Forfaits, crédits et paiements
- Les forfaits (FREE, STARTER, PRO TIPSTER, BUSINESS) et leurs prix en FCFA sont affichés dans l'écran « Abonnement et crédits ». Les prix peuvent évoluer ; le prix payé est celui affiché et confirmé au moment du paiement.
- Le paiement se fait par Mobile Money via l'agrégateur CinetPay. Un forfait ou des crédits ne sont activés qu'après confirmation du paiement par l'opérateur, vérifiée par le serveur.
- Un forfait couvre la durée achetée (1 mois ou 12 mois). **Il n'y a pas de renouvellement automatique** : l'utilisateur prolonge s'il le souhaite.
- Les crédits IA inclus dans un forfait se renouvellent chaque mois et ne se reportent pas ; les crédits achetés en pack n'expirent pas.
- Un code promo s'utilise une seule fois par compte, dans ses conditions de validité.
- Toute demande de remboursement s'adresse au support ({{contact}}). Elle est examinée au cas par cas, notamment en cas de double paiement ou d'impossibilité d'accéder au service payé. Un remboursement accordé retire les droits correspondants (forfait arrêté, crédits restants retirés).

## 6. Contenus publiés par les utilisateurs
- L'utilisateur reste responsable de ce qu'il publie (profil, publications, commentaires, coupons, visuels) et respecte les Règles de la communauté.
- Il accorde à l'éditeur le droit non exclusif d'afficher ces contenus dans le Service, le temps de leur publication.
- Un coupon publié par un Tipster ne peut plus être modifié ni supprimé : ses résultats, gagnants comme perdants, sont réglés et affichés par la plateforme. Seule la suppression du compte l'efface.
- L'éditeur peut masquer un contenu ou suspendre un compte qui enfreint ces conditions ou les Règles de la communauté. Toute personne peut signaler un contenu.

## 7. Studio graphique
Les visuels générés portent les avertissements prévus. L'utilisateur qui les diffuse s'engage à ne pas les présenter comme des gains assurés ni à en retirer les mentions d'avertissement.

## 8. Jeu responsable
Le pari sportif comporte un risque de perte d'argent et de dépendance. La page « Jeu responsable » de l'application rappelle les bonnes pratiques et les signes d'alerte. En cas de difficulté, parlez-en à un proche ou à un professionnel de santé.

## 9. Disponibilité et responsabilité
Le Service est fourni en l'état, avec une obligation de moyens. Il peut être interrompu pour maintenance, en cas de panne d'un fournisseur ou de force majeure. L'éditeur n'est pas responsable des contenus et décisions des utilisateurs ni des données fournies par des tiers.

## 10. Propriété intellectuelle
L'application, sa marque, son logo, ses textes, analyses et modèles graphiques appartiennent à l'éditeur ou à ses partenaires. Toute reproduction non autorisée est interdite, hors partage des visuels créés par l'utilisateur dans le studio.

## 11. Suppression du compte
L'utilisateur peut supprimer son compte à tout moment depuis Profil → « Supprimer mon compte ». La suppression est définitive. Les sommes déjà payées pour une période en cours ne sont pas remboursées du seul fait de la suppression.

## 12. Données personnelles
Le traitement des données est décrit dans la Politique de confidentialité.

## 13. Modification des conditions
Les conditions peuvent être mises à jour. Toute nouvelle version est datée et doit être acceptée dans l'application pour continuer à utiliser le Service.

## 14. Droit applicable et litiges
Ces conditions sont soumises au droit du pays d'établissement de l'éditeur ({{pays}}), sans priver l'utilisateur des protections impératives de son pays de résidence. Avant toute action, les parties recherchent une solution amiable par écrit auprès du support.
$terms$),
('privacy', '2026-10-31', 'Politique de confidentialité', true, $privacy$
## 1. Responsable du traitement
{{editeur}} {{forme}}, {{adresse}}, {{pays}}. Contact pour toute question sur vos données : {{contact}}.

## 2. Données traitées et pourquoi
- **Compte** : adresse e-mail, mot de passe (enregistré sous forme chiffrée, jamais lisible), nom affiché. Pour créer et sécuriser votre compte.
- **Préférences** : compétitions et équipes suivies, niveau, taille du texte, réglages de notifications et heures calmes. Pour personnaliser l'application.
- **Utilisation du service** : coupons enregistrés, demandes à l'assistant et au laboratoire, consommation de crédits et d'analyses. Pour fournir le service et appliquer les quotas de votre forfait.
- **Communauté** (si vous l'utilisez) : profil Tipster, photo, publications, commentaires, réactions, abonnements, signalements, blocages. Pour faire fonctionner l'espace communautaire et la modération.
- **Studio** : logo, couverture, signature et visuels générés. Pour produire vos visuels.
- **Paiements** : forfait ou pack acheté, montant, référence de transaction, statut, moyen de paiement indiqué par l'opérateur. Vos identifiants Mobile Money sont saisis chez l'opérateur et ne sont pas reçus par l'application.
- **Notifications** : identifiant technique de l'appareil pour l'envoi des notifications, si vous les acceptez.
- **Sécurité** : journal des actions sensibles (administration, paiements, modération) et journaux techniques des serveurs.
Les données sportives (matchs, cotes, résultats) ne sont pas des données personnelles.

## 3. Bases du traitement
L'exécution du service que vous demandez (compte, forfait, fonctions utilisées), votre consentement (notifications sur le téléphone, publications dans la communauté), le respect d'obligations légales et l'intérêt légitime de sécuriser le service et de prévenir les abus.

## 4. Intelligence artificielle
Les textes que vous envoyez à l'assistant ou au laboratoire, ainsi que les données de match et de coupon nécessaires, sont transmis au service d'intelligence artificielle Gemini (Google) pour rédiger les réponses. N'y indiquez pas d'informations personnelles inutiles. Les sélections, cotes, probabilités et résultats sont toujours calculés par nos serveurs, pas par l'IA.

## 5. Destinataires et prestataires
Vos données ne sont ni vendues ni louées. Elles sont accessibles à l'équipe habilitée (support, administration, modération) et traitées par les prestataires techniques suivants, pour notre compte :
- **Supabase** : hébergement de la base de données, des fichiers et de l'authentification, sur des serveurs situés dans l'Union européenne (Irlande) ;
- **Google** : Gemini (intelligence artificielle) et Firebase Cloud Messaging (notifications) ;
- **CinetPay** : traitement des paiements Mobile Money ;
- **API-Football** : fournisseur des données sportives (aucune donnée personnelle ne lui est transmise).
Ces prestataires peuvent traiter des données hors de votre pays de résidence. Le profil Tipster, les publications et les coupons publiés sont visibles des autres utilisateurs ; les personnes que vous bloquez ne les voient plus.

## 6. Durées de conservation
Vos données sont conservées tant que votre compte existe. Lorsque vous supprimez votre compte (Profil → « Supprimer mon compte »), vos données de compte, préférences, coupons, publications, commentaires, fichiers et historique de paiements sont effacés. Le journal de sécurité conserve la trace de la suppression, sans contenu personnel. Les journaux techniques des serveurs sont conservés pour une durée limitée par nos prestataires.

## 7. Sécurité
Échanges chiffrés (HTTPS), accès aux données contrôlé ligne par ligne selon l'utilisateur et ses droits, mots de passe chiffrés, clés des services tiers uniquement sur les serveurs, actions sensibles journalisées. Aucune mesure n'offrant une sécurité absolue, signalez-nous tout problème à {{contact}}.

## 8. Vos droits
Vous pouvez accéder à vos données, les rectifier (Profil), les supprimer (suppression du compte), vous opposer à certains traitements (réglages des notifications) et demander une copie de vos données en écrivant à {{contact}}. Vous pouvez aussi saisir l'autorité de protection des données de votre pays, par exemple la CIL au Burkina Faso, l'ARTCI en Côte d'Ivoire ou la CDP au Sénégal.

## 9. Mineurs
Le Service est réservé aux personnes majeures. Si nous apprenons qu'un compte appartient à un mineur, il est supprimé.

## 10. Traceurs
L'application n'intègre aucun outil de publicité ni de mesure d'audience tiers. Elle conserve sur votre téléphone votre session de connexion et vos réglages d'affichage.

## 11. Modifications
Cette politique peut être mise à jour. Toute nouvelle version est datée et doit être acceptée dans l'application.
$privacy$),
('community', '2026-10-31', 'Règles de la communauté', false, $community$
## Esprit
La communauté Coupon Pro IA sert à partager des analyses et des coupons de façon transparente. Les statistiques des Tipsters sont calculées par la plateforme, sur des coupons publiés avant le coup d'envoi et impossibles à modifier ensuite.

## Interdit
- Promettre des gains ou présenter un pronostic comme certain (« sûr », « garanti », « gain assuré », « 100 % »…).
- Publier de faux résultats, des captures retouchées ou des statistiques non vérifiables.
- Vendre des pronostics, des « matchs truqués » ou des accès payants, ou rediriger vers d'autres services de paiement : ce sont des arnaques fréquentes.
- Insulter, harceler, menacer, tenir des propos haineux ou discriminatoires.
- Publier les données personnelles d'autrui (numéro, adresse, photos privées).
- Publier des contenus illégaux, violents, sexuels ou visant des mineurs.
- Spammer, créer plusieurs comptes ou usurper l'identité d'une autre personne.
- Inciter au jeu excessif, à emprunter ou à parier l'argent nécessaire au quotidien.

## Signaler et bloquer
Chaque publication et chaque commentaire peuvent être signalés. Vous pouvez bloquer un utilisateur : vous ne voyez plus ses contenus et il ne peut plus interagir avec vous.

## Sanctions
Selon la gravité : masquage du contenu, suspension du profil Tipster, suspension ou suppression du compte. Les décisions de modération sont journalisées.
$community$);
