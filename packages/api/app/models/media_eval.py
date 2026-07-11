"""Modèles évaluation des médias C1–C11 (méthodologie ouverte v1.2).

Data store du pipeline collecte ≠ évaluation (cf. docs/media-eval/) : les
collecteurs écrivent des signaux horodatés + snapshots, les évaluateurs (sans
accès web) citent des ``signal_ids``, la synthèse produit une fiche. Tables
préfixées ``media_eval_*``, RLS deny-all (migration ``me01``), backend-only.

``media_eval_runs`` est l'entité batch : tout enregistrement daté porte un
``run_id`` FK — un run est isolable, daté (``date_reference`` pilote la
fenêtre de fraîcheur, jamais ``now()``) et supprimable en cascade.

``media_eval_medias`` est un référentiel **niveau domaine**, distinct de
``sources`` (niveau feed) : ``source_ids`` fait le lien applicatif futur sans
FK dure.
"""

import uuid
from datetime import date, datetime
from enum import StrEnum
from uuid import UUID

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

_CRITERES_VALIDES = tuple(f"C{i}" for i in range(1, 12))
_CRITERE_CHECK = "critere IN ({})".format(
    ", ".join(f"'{c}'" for c in _CRITERES_VALIDES)
)


class TypeMedia(StrEnum):
    PRESSE_EN_LIGNE = "presse_en_ligne"
    PRESSE_ECRITE = "presse_ecrite"
    AUDIOVISUEL = "audiovisuel"


class TypePage(StrEnum):
    MENTIONS_LEGALES = "mentions_legales"
    A_PROPOS = "a_propos"
    CHARTE = "charte"
    OURS_EQUIPE = "ours_equipe"
    DONS_FINANCEMENT = "dons_financement"
    LIGNE_EDITORIALE = "ligne_editoriale"
    REGIE_PUB = "regie_pub"
    AUTRE = "autre"


class ModeAcces(StrEnum):
    LIBRE = "libre"
    PAYWALL = "paywall"
    BLOQUE = "bloque"


class StatutSignal(StrEnum):
    """La distinction clé (arbitrage n°3) : bloqué ≠ absent."""

    PRESENT = "present"
    ABSENT_VERIFIE = "absent_verifie"
    PARTIEL = "partiel"
    BLOQUE_ACCES = "bloque_acces"


class VoieCollecte(StrEnum):
    CODE = "code"
    AGENT = "agent"
    HUMAIN = "humain"


class PoidsEmetteur(StrEnum):
    FORT = "fort"
    MOYEN = "moyen"
    FAIBLE = "faible"


class GraviteDebunkage(StrEnum):
    MINEURE = "mineure"
    SIGNIFICATIVE = "significative"
    GRAVE = "grave"


class SuiteDonnee(StrEnum):
    CORRECTION_PUBLIEE = "correction_publiee"
    RETRAIT = "retrait"
    AUCUNE = "aucune"
    CONTESTATION = "contestation"
    INCONNUE = "inconnue"


class StatutEvaluation(StrEnum):
    EVALUEE = "evaluee"
    NON_APPLICABLE = "non_applicable"
    REVUE_REQUISE = "revue_requise"


class ConfianceFiche(StrEnum):
    HAUTE = "haute"
    MOYENNE = "moyenne"
    BASSE = "basse"


class StatutFiche(StrEnum):
    BROUILLON = "brouillon"
    VALIDEE = "validee"
    PUBLIEE = "publiee"


class StatutRun(StrEnum):
    EN_COURS = "en_cours"
    CLOS = "clos"


class TypeNoteCollecte(StrEnum):
    """Notes libres des collecteurs — hors registre des signaux.

    ``amelioration_protocole`` : revue humaine uniquement (faire évoluer
    ``TYPE_SIGNAUX``) ; les deux autres sont injectées aux évaluateurs comme
    contexte non-citable (pas de signal_id → ne peut fonder aucun score).
    """

    AMELIORATION_PROTOCOLE = "amelioration_protocole"
    CONTEXTE_MEDIA = "contexte_media"
    DONNEE_NON_STRUCTUREE = "donnee_non_structuree"


def _str_enum(enum_cls: type[StrEnum], length: int = 30) -> Enum:
    """Enum stocké VARCHAR (pas de type Postgres natif), pattern Source."""
    return Enum(
        enum_cls,
        values_callable=lambda x: [e.value for e in x],
        native_enum=False,
        length=length,
    )


class MediaEvalRun(Base):
    """L'entité batch : un cycle de collecte + évaluation nommé et daté."""

    __tablename__ = "media_eval_runs"

    run_id: Mapped[str] = mapped_column(String(50), primary_key=True)
    libelle: Mapped[str | None] = mapped_column(Text, nullable=True)
    version_methodo: Mapped[str] = mapped_column(String(20), nullable=False)
    # Pilote la fenêtre de fraîcheur (build_eval_input) : un run rejoué plus
    # tard produit exactement les mêmes entrées évaluateur.
    date_reference: Mapped[date] = mapped_column(Date, nullable=False)
    # {"medias": [...], "criteres": [...]} — périmètre prévu du batch.
    perimetre: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    statut: Mapped[StatutRun] = mapped_column(
        _str_enum(StatutRun),
        nullable=False,
        default=StatutRun.EN_COURS,
        server_default=StatutRun.EN_COURS.value,
    )
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    cree_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    clos_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )


class MediaEvalMedia(Base):
    """Référentiel des médias évalués (niveau domaine, étape 0 du pipeline)."""

    __tablename__ = "media_eval_medias"

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    nom: Mapped[str] = mapped_column(String(200), nullable=False)
    domaine: Mapped[str] = mapped_column(String(255), nullable=False, unique=True)
    type_media: Mapped[TypeMedia] = mapped_column(_str_enum(TypeMedia), nullable=False)
    paywall: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    rubriques_opinion: Mapped[list[str] | None] = mapped_column(
        ARRAY(Text), nullable=True
    )
    volume_articles_jour: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # Lien applicatif futur vers sources (niveau feed) — volontairement sans FK.
    source_ids: Mapped[list[UUID] | None] = mapped_column(
        ARRAY(PGUUID(as_uuid=True)), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )


class MediaEvalSnapshot(Base):
    """Capture horodatée d'une page type — la preuve derrière un signal."""

    __tablename__ = "media_eval_snapshots"
    __table_args__ = (Index("ix_media_eval_snapshots_media_id", "media_id"),)

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    media_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("media_eval_medias.id", ondelete="CASCADE"),
        nullable=False,
    )
    run_id: Mapped[str] = mapped_column(
        String(50),
        ForeignKey("media_eval_runs.run_id", ondelete="CASCADE"),
        nullable=False,
    )
    url: Mapped[str] = mapped_column(Text, nullable=False)
    type_page: Mapped[TypePage] = mapped_column(_str_enum(TypePage), nullable=False)
    contenu: Mapped[str | None] = mapped_column(Text, nullable=True)
    hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    http_status: Mapped[int | None] = mapped_column(Integer, nullable=True)
    mode_acces: Mapped[ModeAcces] = mapped_column(
        _str_enum(ModeAcces),
        nullable=False,
        default=ModeAcces.LIBRE,
        server_default=ModeAcces.LIBRE.value,
    )
    capture_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )


class MediaEvalCorpusArticle(Base):
    """Corpus d'articles échantillonnés (§5.4) — créée mais vide en V0."""

    __tablename__ = "media_eval_corpus_articles"
    __table_args__ = (
        UniqueConstraint(
            "media_id", "run_id", "url", name="uq_media_eval_corpus_media_run_url"
        ),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    media_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("media_eval_medias.id", ondelete="CASCADE"),
        nullable=False,
    )
    run_id: Mapped[str] = mapped_column(
        String(50),
        ForeignKey("media_eval_runs.run_id", ondelete="CASCADE"),
        nullable=False,
    )
    url: Mapped[str] = mapped_column(Text, nullable=False)
    titre: Mapped[str | None] = mapped_column(Text, nullable=True)
    date_pub: Mapped[date | None] = mapped_column(Date, nullable=True)
    rubrique: Mapped[str | None] = mapped_column(String(100), nullable=True)
    texte: Mapped[str | None] = mapped_column(Text, nullable=True)
    mode_acquisition: Mapped[str | None] = mapped_column(String(30), nullable=True)
    pre_metriques: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )


class MediaEvalSignal(Base):
    """La table pivot : une observation factuelle, sourcée, jamais un score."""

    __tablename__ = "media_eval_signaux"
    __table_args__ = (
        CheckConstraint(_CRITERE_CHECK, name="ck_media_eval_signaux_critere"),
        UniqueConstraint(
            "media_id",
            "run_id",
            "dedupe_key",
            name="uq_media_eval_signaux_media_run_dedupe",
        ),
        Index("ix_media_eval_signaux_media_critere", "media_id", "critere"),
        Index("ix_media_eval_signaux_run_id", "run_id"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    media_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("media_eval_medias.id", ondelete="CASCADE"),
        nullable=False,
    )
    critere: Mapped[str] = mapped_column(String(3), nullable=False)
    type_signal: Mapped[str] = mapped_column(String(50), nullable=False)
    statut: Mapped[StatutSignal] = mapped_column(
        _str_enum(StatutSignal), nullable=False
    )
    valeur: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    citation: Mapped[str | None] = mapped_column(Text, nullable=True)
    voie: Mapped[VoieCollecte] = mapped_column(_str_enum(VoieCollecte), nullable=False)
    # Ex. "code:collect_cdjm@v1", "agent:media-eval-collecteur-debunkages@v1".
    collecteur: Mapped[str] = mapped_column(String(100), nullable=False)
    source_urls: Mapped[list[str]] = mapped_column(
        ARRAY(Text), nullable=False, default=list, server_default="{}"
    )
    # Preuve de recherche pour les statuts absent_verifie (§5.3-É1).
    sources_consultees: Mapped[list[str] | None] = mapped_column(
        ARRAY(Text), nullable=True
    )
    snapshot_id: Mapped[UUID | None] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("media_eval_snapshots.id", ondelete="SET NULL"),
        nullable=True,
    )
    run_id: Mapped[str] = mapped_column(
        String(50),
        ForeignKey("media_eval_runs.run_id", ondelete="CASCADE"),
        nullable=False,
    )
    # sha256 canonique calculé par code → ré-ingestion idempotente.
    dedupe_key: Mapped[str] = mapped_column(String(64), nullable=False)
    # Moment réel de collecte (genere_at de l'artefact voie B) ≠ ingere_at
    # (écriture DB). version_prompt_collecteur = sha256 du prompt collecteur.
    collecte_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    ingere_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    version_prompt_collecteur: Mapped[str | None] = mapped_column(
        String(64), nullable=True
    )
    # Contexte libre propre au signal — jamais un signal en soi.
    note_collecteur: Mapped[str | None] = mapped_column(Text, nullable=True)


class MediaEvalDebunkage(Base):
    """Vérification négative qualifiée (C1, pondération v1.2).

    Chaque débunkage est aussi un signal C1 (``signal_id`` unique NOT NULL) :
    le contrat évaluateur reste uniforme, la table porte la qualification.
    """

    __tablename__ = "media_eval_debunkages"

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    media_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("media_eval_medias.id", ondelete="CASCADE"),
        nullable=False,
    )
    signal_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("media_eval_signaux.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    url_debunkage: Mapped[str] = mapped_column(Text, nullable=False)
    emetteur: Mapped[str] = mapped_column(String(100), nullable=False)
    # Dérivé par code (POIDS_EMETTEUR), jamais choisi par l'agent.
    poids_emetteur: Mapped[PoidsEmetteur] = mapped_column(
        _str_enum(PoidsEmetteur), nullable=False
    )
    gravite: Mapped[GraviteDebunkage] = mapped_column(
        _str_enum(GraviteDebunkage), nullable=False
    )
    suite_donnee: Mapped[SuiteDonnee] = mapped_column(
        _str_enum(SuiteDonnee), nullable=False
    )
    resume: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Requis pour la fenêtre de fraîcheur (2 ans).
    publie_at: Mapped[date] = mapped_column(Date, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )


class MediaEvalEvaluation(Base):
    """Évaluation d'un critère : score dérivé par code, signaux cités."""

    __tablename__ = "media_eval_evaluations"
    __table_args__ = (
        CheckConstraint(_CRITERE_CHECK, name="ck_media_eval_evaluations_critere"),
        CheckConstraint(
            "niveau IS NULL OR (niveau >= 0 AND niveau <= 2)",
            name="ck_media_eval_evaluations_niveau",
        ),
        UniqueConstraint(
            "media_id",
            "critere",
            "evaluateur",
            "run_id",
            name="uq_media_eval_evaluations_media_critere_eval_run",
        ),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    media_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("media_eval_medias.id", ondelete="CASCADE"),
        nullable=False,
    )
    critere: Mapped[str] = mapped_column(String(3), nullable=False)
    # NULL si non_applicable / revue_requise (jamais 0 par défaut).
    score: Mapped[float | None] = mapped_column(Float, nullable=True)
    score_max: Mapped[float] = mapped_column(Float, nullable=False)
    # Niveau 0-2 pour les critères à 3 niveaux (C9, C11), NULL sinon.
    niveau: Mapped[int | None] = mapped_column(Integer, nullable=True)
    statut: Mapped[StatutEvaluation] = mapped_column(
        _str_enum(StatutEvaluation), nullable=False
    )
    justification: Mapped[str] = mapped_column(Text, nullable=False)
    signal_ids: Mapped[list[UUID]] = mapped_column(
        ARRAY(PGUUID(as_uuid=True)), nullable=False, default=list, server_default="{}"
    )
    flags: Mapped[list[str]] = mapped_column(
        ARRAY(Text), nullable=False, default=list, server_default="{}"
    )
    # "agent:media-eval-evaluateur@v1" / "humain:laurin" / "code:jti_shortcut".
    evaluateur: Mapped[str] = mapped_column(String(100), nullable=False)
    version_methodo: Mapped[str] = mapped_column(String(20), nullable=False)
    # sha256 du fichier rubrique utilisé (build_eval_input).
    version_prompt: Mapped[str] = mapped_column(String(64), nullable=False)
    run_id: Mapped[str] = mapped_column(
        String(50),
        ForeignKey("media_eval_runs.run_id", ondelete="CASCADE"),
        nullable=False,
    )
    evalue_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )


class MediaEvalFiche(Base):
    """Synthèse par (média, run) : renormalisation, lettre, confiance."""

    __tablename__ = "media_eval_fiches"
    __table_args__ = (
        UniqueConstraint("media_id", "run_id", name="uq_media_eval_fiches_media_run"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    media_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("media_eval_medias.id", ondelete="CASCADE"),
        nullable=False,
    )
    run_id: Mapped[str] = mapped_column(String(50), nullable=False)
    score_brut: Mapped[float] = mapped_column(Float, nullable=False)
    score_max_applicable: Mapped[float] = mapped_column(Float, nullable=False)
    score_renormalise: Mapped[float] = mapped_column(Float, nullable=False)
    lettre: Mapped[str] = mapped_column(String(1), nullable=False)
    criteres_evalues: Mapped[list[str]] = mapped_column(
        ARRAY(Text), nullable=False, default=list, server_default="{}"
    )
    criteres_na: Mapped[list[str]] = mapped_column(
        ARRAY(Text), nullable=False, default=list, server_default="{}"
    )
    confiance: Mapped[ConfianceFiche] = mapped_column(
        _str_enum(ConfianceFiche), nullable=False
    )
    statut: Mapped[StatutFiche] = mapped_column(
        _str_enum(StatutFiche),
        nullable=False,
        default=StatutFiche.BROUILLON,
        server_default=StatutFiche.BROUILLON.value,
    )
    detail: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    genere_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
