"""Construit le corps JSON des réglages Supabase Auth (API de gestion).

Codes à 6 chiffres envoyés par email pour la confirmation d'inscription et la
réinitialisation du mot de passe : l'app n'utilise aucun lien magique.

Usage : python3 scripts/supabase/auth_config.py > auth.json
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEMPLATES = ROOT / "supabase" / "templates"


def template(name: str) -> str:
    text = (TEMPLATES / name).read_text(encoding="utf-8")
    # Retire le commentaire d'en-tête destiné aux développeurs.
    lines = [line for line in text.splitlines() if not line.lstrip().startswith("<!--")]
    return "\n".join(lines).strip()


config = {
    "external_email_enabled": True,
    "mailer_autoconfirm": False,
    "mailer_otp_length": 6,
    "mailer_otp_exp": 3600,
    "password_min_length": 8,
    "mailer_subjects_confirmation": "Votre code Coupon Pro IA",
    "mailer_templates_confirmation_content": template("confirmation.html"),
    "mailer_subjects_recovery": "Réinitialisation de votre mot de passe Coupon Pro IA",
    "mailer_templates_recovery_content": template("recovery.html"),
}

print(json.dumps(config, ensure_ascii=False))
