-- Mes coupons (02/11) : renommer un coupon. Le titre reste court (1 à 80 caractères) et sans
-- promesse de résultat ; un coupon publié reste immuable (déclencheur existant).

create or replace function app_private.check_user_coupon_title()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.title is distinct from old.title then
    new.title := btrim(new.title);
    if char_length(new.title) not between 1 and 80 then
      raise exception 'Nom du coupon : 1 à 80 caractères' using errcode = '22023';
    end if;
    if app_private.has_forbidden_words(new.title) then
      raise exception 'Nom refusé : pas de promesse de résultat' using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function app_private.check_user_coupon_title() from public, anon, authenticated;

drop trigger if exists user_coupons_check_title on public.user_coupons;
create trigger user_coupons_check_title
  before update of title on public.user_coupons
  for each row execute function app_private.check_user_coupon_title();
