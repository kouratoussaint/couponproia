#!/usr/bin/env bash
# Vérifie, avec la seule clé publique, que le projet Supabase répond comme l'app
# l'attend. Les résultats sont publiés en annotations GitHub (::notice / ::error).
set -uo pipefail

ENV_FILE="${1:-app/env/prod.json}"
URL="$(jq -r .SUPABASE_URL "$ENV_FILE")"
KEY="$(jq -r .SUPABASE_ANON_KEY "$ENV_FILE")"
fail=0

get() { curl -s -H "apikey: $KEY" -H "Authorization: Bearer $KEY" "$URL$1"; }

flags="$(get '/rest/v1/feature_flags?select=key,enabled')"
n_flags="$(echo "$flags" | jq 'if type=="array" then length else -1 end')"
if [ "$n_flags" -ge 13 ]; then
  echo "::notice::feature_flags lisibles par un visiteur : $n_flags flags"
else
  echo "::error::feature_flags illisibles ou incomplets : $flags"; fail=1
fi

settings="$(get '/rest/v1/app_settings?select=key&is_public=eq.true')"
n_settings="$(echo "$settings" | jq 'if type=="array" then length else -1 end')"
if [ "$n_settings" -ge 5 ]; then
  echo "::notice::réglages publics : $n_settings"
else
  echo "::error::réglages publics manquants : $settings"; fail=1
fi

private="$(get '/rest/v1/app_settings?select=key&is_public=eq.false')"
if [ "$(echo "$private" | jq 'if type=="array" then length else -1 end')" = "0" ]; then
  echo "::notice::réglages privés invisibles pour un visiteur (RLS OK)"
else
  echo "::error::un visiteur voit des réglages privés : $private"; fail=1
fi

profiles_code="$(curl -s -o /dev/null -w '%{http_code}' -H "apikey: $KEY" -H "Authorization: Bearer $KEY" "$URL/rest/v1/profiles?select=id")"
if [ "$profiles_code" = "401" ] || [ "$profiles_code" = "403" ]; then
  echo "::notice::profils refusés à un visiteur (HTTP $profiles_code)"
else
  echo "::error::profils accessibles à un visiteur (HTTP $profiles_code)"; fail=1
fi

auth="$(get '/auth/v1/settings')"
autoconfirm="$(echo "$auth" | jq -r '.mailer_autoconfirm')"
if [ "$autoconfirm" = "false" ]; then
  echo "::notice::confirmation d'email obligatoire (mailer_autoconfirm=false)"
else
  echo "::error::confirmation d'email non exigée : mailer_autoconfirm=$autoconfirm"; fail=1
fi

exit $fail
