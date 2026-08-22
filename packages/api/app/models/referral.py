"""Parrainage — code de partage par utilisateur et attributions d'installation.

Story partage.2 (« Attribution & partage mobile »). Deux tables backend-only :
l'app lit son code via `GET /api/referral/me` et pose l'attribution au premier
lancement via `POST /api/referral/attribution`.

Les FK ciblent `user_profiles.user_id` (l'id Supabase), comme toutes les FK
existantes — `user_profiles.id` est une PK technique distincte.
"""

import uuid
from datetime import datetime
from uuid import UUID

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint, text
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# Alphabet sans caractères ambigus (pas de I/L/O/U, ni 0/1) : le code peut être
# lu à voix haute ou recopié à la main depuis un message partagé.
REFERRAL_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTVWXYZ23456789"
REFERRAL_CODE_LENGTH = 6


class ReferralCode(Base):
    """Code de parrainage stable d'un utilisateur (créé paresseusement)."""

    __tablename__ = "referral_codes"
    __table_args__ = (UniqueConstraint("code", name="uq_referral_codes_code"),)

    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("user_profiles.user_id", ondelete="CASCADE"),
        primary_key=True,
    )
    code: Mapped[str] = mapped_column(String(8), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )


class ReferralAttribution(Base):
    """Attribution d'un filleul à un code, posée au premier lancement.

    `referred_user_id` est unique : c'est cette contrainte — et non un test
    applicatif — qui rend `POST /attribution` idempotent, l'app pouvant rejouer
    l'appel tant qu'elle n'a pas reçu de 200.
    """

    __tablename__ = "referral_attributions"

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    referred_user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("user_profiles.user_id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
    )
    code: Mapped[str] = mapped_column(String(8), nullable=False, index=True)
    # Surface de partage d'origine — c'est l'`utm_content` de nos liens
    # (grille, article, notif_du_jour…), nommé comme le produit le nomme.
    surface: Mapped[str | None] = mapped_column(String(40), nullable=True)
    platform: Mapped[str | None] = mapped_column(String(16), nullable=True)
    store: Mapped[str | None] = mapped_column(String(16), nullable=True)
    # Trio UTM à plat, comme `waitlist_entries` et `event_rsvps` : l'acquisition
    # reste interrogeable de la même façon partout.
    utm_source: Mapped[str | None] = mapped_column(String(100), nullable=True)
    utm_medium: Mapped[str | None] = mapped_column(String(100), nullable=True)
    utm_campaign: Mapped[str | None] = mapped_column(String(100), nullable=True)
    # Chaîne brute de l'Install Referrer Play, gardée pour audit. Bornée plutôt
    # que TEXT : elle vient du client, et 2000 caractères couvrent largement le
    # format Play (`utm_source=…&utm_medium=…&ref=…`).
    referrer_raw: Mapped[str | None] = mapped_column(String(2000), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
