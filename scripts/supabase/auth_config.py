"""Construit le corps JSON des réglages Supabase Auth (API de gestion).

Deux niveaux :
- toujours : confirmation d'email obligatoire, codes à 6 chiffres, mot de passe de
  8 caractères minimum, page d'arrivée des liens (Edge Function email-confirmed) ;
- si un SMTP est fourni (variables SMTP_USER, SMTP_PASS, SMTP_SENDER_EMAIL) : serveur
  d'envoi, modèles d'emails en français ou en anglais (métadonnée locale) affichant le code, limite d'envoi relevée.
  Sans SMTP, Supabase refuse la modification des modèles sur l'offre gratuite.

Usage : SUPABASE_REF=xxxx python3 scripts/supabase/auth_config.py > auth.json
"""
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEMPLATES = ROOT / "supabase" / "templates"


def template(name: str) -> str:
    text = (TEMPLATES / name).read_text(encoding="utf-8")
    lines = [line for line in text.splitlines() if not line.lstrip().startswith("<!--")]
    return "\n".join(lines).strip()


ref = os.environ["SUPABASE_REF"]
config = {
    "external_email_enabled": True,
    "mailer_autoconfirm": False,
    "mailer_otp_length": 6,
    "mailer_otp_exp": 3600,
    "password_min_length": 8,
    # Changement d'adresse : un code à la nouvelle adresse ; l'app redemande le mot de passe avant.
    "mailer_secure_email_change_enabled": False,
    "site_url": f"https://{ref}.supabase.co/functions/v1/email-confirmed",
}

smtp_user = os.environ.get("SMTP_USER", "").strip()
smtp_pass = os.environ.get("SMTP_PASS", "").strip()
smtp_sender = os.environ.get("SMTP_SENDER_EMAIL", "").strip()
if smtp_user and smtp_pass and smtp_sender:
    config.update({
        "smtp_host": os.environ.get("SMTP_HOST", "").strip() or "smtp-relay.brevo.com",
        "smtp_port": os.environ.get("SMTP_PORT", "").strip() or "587",
        "smtp_user": smtp_user,
        "smtp_pass": smtp_pass,
        "smtp_admin_email": smtp_sender,
        "smtp_sender_name": "Coupon Pro IA",
        "rate_limit_email_sent": 30,
        "mailer_subjects_confirmation": "Votre code Coupon Pro IA · Your Coupon Pro IA code",
        "mailer_templates_confirmation_content": template("confirmation.html"),
        "mailer_subjects_recovery": "Mot de passe Coupon Pro IA · Coupon Pro IA password",
        "mailer_templates_recovery_content": template("recovery.html"),
        "mailer_subjects_email_change": "Nouvelle adresse Coupon Pro IA · New Coupon Pro IA address",
        "mailer_templates_email_change_content": template("email_change.html"),
    })
    print("mode=smtp", file=sys.stderr)
else:
    print("mode=base", file=sys.stderr)

print(json.dumps(config, ensure_ascii=False))
