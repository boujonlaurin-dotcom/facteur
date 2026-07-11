"""Service métier — système d'intérêts unifié (Story 22.1).

Gère les mutations d'état (`hidden`/`unfollowed`/`followed`/`favorite`) sur les
3 entités (Thèmes, Sujets, Sources) et l'ordre canonique des favoris (cap=5
par catégorie). L'invalidation cache et les events PostHog sont du ressort
des routers (couche transport).
"""

from uuid import UUID

import structlog
from sqlalchemy import delete, func, select, text, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.constants import FAVORITE_CAP
from app.models.enums import InterestState
from app.models.source import UserSource
from app.models.user import UserInterest
from app.models.user_favorites import UserFavoriteInterest, UserFavoriteSource
from app.models.user_personalization import UserPersonalization
from app.models.user_topic_profile import UserTopicProfile
from app.models.veille import VeilleConfig, VeilleStatus
from app.schemas.user_interests import (
    CustomTopicInterestResponse,
    FavoriteRef,
    SourceFavoriteRef,
    SourceStateResponse,
    ThemeInterestResponse,
    UserInterestsResponse,
    UserSourcesStateResponse,
)

logger = structlog.get_logger(__name__)


class FavoriteCapReached(Exception):
    """Levée quand l'utilisateur tente d'ajouter un (n+1)ème favori (n=cap)."""

    def __init__(self, kind: str, target_id: str, current_count: int):
        self.kind = kind
        self.target_id = target_id
        self.current_count = current_count
        super().__init__(
            f"favorite_cap_reached: kind={kind} target={target_id} count={current_count}"
        )


class TargetNotFound(Exception):
    """Target inexistant pour ce user (custom_topic UUID inconnu, source non suivie)."""


class TargetNotFavorite(Exception):
    """Tentative de reorder qui inclut un target dont le state n'est pas favorite."""


class CustomTopicNotReorderable(Exception):
    """Un custom_topic favori ne peut pas occuper une position du top 5 reorderable.

    Le top 5 « Tournée du jour » est réservé aux thèmes et veilles (cf. Story
    23.x bug-custom-topic-favori-regression). Les custom_topic favoris sont
    affichés dans une section séparée « Sujets épinglés » côté mobile, alimentent
    les onglets de la section Explorer, mais ne sont pas draggable dans le top 5.
    """

    def __init__(self, target_id: str):
        self.target_id = target_id
        super().__init__(
            f"custom_topic {target_id} cannot be placed in the top reorderable favorites"
        )


class UserInterestsService:
    """CRUD sur l'état déclaré des Thèmes + Sujets + favoris ordonnés."""

    def __init__(self, db: AsyncSession):
        self.db = db

    # ─── READ ────────────────────────────────────────────────────────────────

    async def get_interests(self, user_id: UUID) -> UserInterestsResponse:
        themes_rows = (
            (
                await self.db.execute(
                    select(UserInterest).where(UserInterest.user_id == user_id)
                )
            )
            .scalars()
            .all()
        )
        topics_rows = (
            (
                await self.db.execute(
                    select(UserTopicProfile).where(UserTopicProfile.user_id == user_id)
                )
            )
            .scalars()
            .all()
        )
        favs_rows = (
            (
                await self.db.execute(
                    select(UserFavoriteInterest)
                    .where(UserFavoriteInterest.user_id == user_id)
                    .order_by(UserFavoriteInterest.position)
                )
            )
            .scalars()
            .all()
        )

        favorites: list[FavoriteRef] = []
        for row in favs_rows:
            if row.interest_slug:
                kind, target_id = "theme", row.interest_slug
            elif row.custom_topic_id:
                kind, target_id = "custom_topic", str(row.custom_topic_id)
            else:
                kind, target_id = "veille", str(row.veille_config_id)
            favorites.append(
                FavoriteRef(kind=kind, target_id=target_id, position=row.position)
            )

        return UserInterestsResponse(
            themes=[ThemeInterestResponse.model_validate(t) for t in themes_rows],
            custom_topics=[
                CustomTopicInterestResponse.model_validate(t) for t in topics_rows
            ],
            favorites=favorites,
            favorite_count=len(favorites),
            favorite_cap=FAVORITE_CAP,
        )

    # ─── MUTATE ──────────────────────────────────────────────────────────────

    async def set_state(
        self,
        user_id: UUID,
        kind: str,
        target_id: str,
        state: InterestState,
        position: int | None = None,
    ) -> InterestState | None:
        """Mute le state d'un Thème ou Sujet. Returns the previous state, or None
        if the target was created on the fly (theme without prior row)."""
        prev_state: InterestState | None = None

        if kind == "theme":
            interest_slug = target_id
            row = (
                await self.db.execute(
                    select(UserInterest).where(
                        UserInterest.user_id == user_id,
                        UserInterest.interest_slug == interest_slug,
                    )
                )
            ).scalar_one_or_none()
            if row is None:
                # Création implicite : permet à l'utilisateur d'épingler un Thème
                # qu'il n'avait pas encore (weight neutre, state demandé).
                # Upsert atomique : un double-tap concurrent ne lève plus
                # d'IntegrityError sur user_interests_user_slug_uniq.
                # prev_state reste None (sémantique "créé à la volée").
                stmt = (
                    insert(UserInterest)
                    .values(user_id=user_id, interest_slug=interest_slug, state=state)
                    .on_conflict_do_update(
                        constraint="user_interests_user_slug_uniq",
                        set_={"state": state},
                    )
                )
                await self.db.execute(stmt)
            else:
                prev_state = row.state
                row.state = state
        elif kind == "custom_topic":
            try:
                topic_uuid = UUID(target_id)
            except ValueError as e:
                raise TargetNotFound(f"invalid custom_topic id: {target_id}") from e
            row = (
                await self.db.execute(
                    select(UserTopicProfile).where(
                        UserTopicProfile.user_id == user_id,
                        UserTopicProfile.id == topic_uuid,
                    )
                )
            ).scalar_one_or_none()
            if row is None:
                raise TargetNotFound(
                    f"custom_topic {target_id} not found for user {user_id}"
                )
            prev_state = row.state
            row.state = state
            # `feed.py:get_tab_counts` identifie les sujets épinglés via
            # `priority_multiplier == 2.0` — sync requis pour que Explorer
            # reflète l'état en temps réel.
            target_multiplier = 2.0 if state == InterestState.FAVORITE else 1.0
            if row.priority_multiplier != target_multiplier:
                row.priority_multiplier = target_multiplier
        else:
            raise ValueError(f"unknown kind: {kind}")

        # Sync table user_favorite_interests selon le nouveau state.
        await self._sync_favorite_interest(
            user_id=user_id,
            kind=kind,
            target_id=target_id,
            state=state,
            position=position,
        )
        await self.db.commit()
        return prev_state

    async def _sync_favorite_interest(
        self,
        user_id: UUID,
        kind: str,
        target_id: str,
        state: InterestState,
        position: int | None,
    ) -> None:
        """Aligne user_favorite_interests sur le nouveau state.

        - state=favorite + pas déjà fav → cap check + insert (auto-position si None)
        - state=favorite + déjà fav + position fournie → update position si changée
        - state≠favorite + actuellement fav → delete row (laisse trous, compactés au prochain reorder)
        """
        # Lecture des favoris actuels du user.
        existing = (
            (
                await self.db.execute(
                    select(UserFavoriteInterest).where(
                        UserFavoriteInterest.user_id == user_id
                    )
                )
            )
            .scalars()
            .all()
        )

        # Find current row matching this target (si elle existe).
        def _matches(fav: UserFavoriteInterest) -> bool:
            if kind == "theme":
                return fav.interest_slug == target_id
            if kind == "veille":
                return (
                    fav.veille_config_id is not None
                    and str(fav.veille_config_id) == target_id
                )
            return (
                fav.custom_topic_id is not None
                and str(fav.custom_topic_id) == target_id
            )

        current = next((f for f in existing if _matches(f)), None)

        if state == InterestState.FAVORITE:
            if current is not None:
                # Déjà favori — éventuellement bouger la position.
                if position is not None and current.position != position:
                    if any(
                        f.position == position and f is not current for f in existing
                    ):
                        # Conflit de position : on laisse au /reorder le soin
                        # d'arbitrer (ou raise ?). Pour l'instant : ignore.
                        return
                    current.position = position
                return
            # Nouveau favori : plus de cap dur (Story 22.2). Append à la fin.
            taken = {f.position for f in existing}
            if position is None or position in taken:
                position = (max(taken) + 1) if taken else 0

            row = UserFavoriteInterest(
                user_id=user_id,
                position=position,
                interest_slug=target_id if kind == "theme" else None,
                custom_topic_id=UUID(target_id) if kind == "custom_topic" else None,
                veille_config_id=UUID(target_id) if kind == "veille" else None,
            )
            self.db.add(row)
        else:
            if current is not None:
                await self.db.delete(current)

    async def reorder_favorites(
        self, user_id: UUID, favorites: list[FavoriteRef]
    ) -> None:
        """Réécrit complètement user_favorite_interests pour ce user.

        Valide que chaque target est bien déclaré state=favorite sur sa table
        source — sinon raise TargetNotFavorite. Transactionnel : DELETE +
        INSERT(s) atomique.
        """
        for fav in favorites:
            if fav.kind == "custom_topic":
                raise CustomTopicNotReorderable(fav.target_id)
            if fav.kind == "theme":
                row = (
                    await self.db.execute(
                        select(UserInterest).where(
                            UserInterest.user_id == user_id,
                            UserInterest.interest_slug == fav.target_id,
                        )
                    )
                ).scalar_one_or_none()
                if row is None or row.state != InterestState.FAVORITE:
                    raise TargetNotFavorite(
                        f"theme {fav.target_id} is not favorite for user {user_id}"
                    )
            elif fav.kind == "veille":
                try:
                    veille_uuid = UUID(fav.target_id)
                except ValueError as e:
                    raise TargetNotFound(
                        f"invalid veille_config id: {fav.target_id}"
                    ) from e
                cfg = (
                    await self.db.execute(
                        select(VeilleConfig).where(
                            VeilleConfig.user_id == user_id,
                            VeilleConfig.id == veille_uuid,
                        )
                    )
                ).scalar_one_or_none()
                if cfg is None or cfg.status != VeilleStatus.ACTIVE.value:
                    raise TargetNotFavorite(
                        f"veille {fav.target_id} is not active for user {user_id}"
                    )

        await self.db.execute(
            delete(UserFavoriteInterest).where(UserFavoriteInterest.user_id == user_id)
        )
        for fav in favorites:
            self.db.add(
                UserFavoriteInterest(
                    user_id=user_id,
                    position=fav.position,
                    interest_slug=fav.target_id if fav.kind == "theme" else None,
                    custom_topic_id=UUID(fav.target_id)
                    if fav.kind == "custom_topic"
                    else None,
                    veille_config_id=UUID(fav.target_id)
                    if fav.kind == "veille"
                    else None,
                )
            )
        await self.db.commit()


async def ensure_veille_favorite(
    db: AsyncSession, user_id: UUID, veille_config_id: UUID
) -> int:
    """Idempotent : garantit que la veille active du user figure dans `user_favorite_interests`.

    Si une row existe déjà avec ce `veille_config_id`, retourne sa position
    sans rien faire. Sinon, append à la fin (`max(position)+1`, ou 0 si la
    table est vide pour ce user). Ne commit pas — l'appelant (router veille)
    gère la transaction englobante.
    """
    existing = (
        (
            await db.execute(
                select(UserFavoriteInterest).where(
                    UserFavoriteInterest.user_id == user_id
                )
            )
        )
        .scalars()
        .all()
    )
    for fav in existing:
        if fav.veille_config_id == veille_config_id:
            return fav.position

    taken = {f.position for f in existing}
    position = (max(taken) + 1) if taken else 0
    db.add(
        UserFavoriteInterest(
            user_id=user_id,
            position=position,
            veille_config_id=veille_config_id,
        )
    )
    await db.flush()
    return position


class UserSourcesStateService:
    """CRUD sur l'état déclaré des Sources + favoris ordonnés."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_sources_state(self, user_id: UUID) -> UserSourcesStateResponse:
        sources_rows = (
            (
                await self.db.execute(
                    select(UserSource).where(UserSource.user_id == user_id)
                )
            )
            .scalars()
            .all()
        )
        favs_rows = (
            (
                await self.db.execute(
                    select(UserFavoriteSource)
                    .where(UserFavoriteSource.user_id == user_id)
                    .order_by(UserFavoriteSource.position)
                )
            )
            .scalars()
            .all()
        )

        return UserSourcesStateResponse(
            sources=[SourceStateResponse.model_validate(s) for s in sources_rows],
            favorites=[
                SourceFavoriteRef(source_id=f.source_id, position=f.position)
                for f in favs_rows
            ],
            favorite_count=len(favs_rows),
            favorite_cap=FAVORITE_CAP,
        )

    async def set_state(
        self,
        user_id: UUID,
        source_id: UUID,
        state: InterestState,
        position: int | None = None,
    ) -> InterestState | None:
        row = (
            await self.db.execute(
                select(UserSource).where(
                    UserSource.user_id == user_id, UserSource.source_id == source_id
                )
            )
        ).scalar_one_or_none()
        if row is None:
            # Upsert : un utilisateur peut basculer une source en
            # followed/favorite directement depuis le reader sans avoir de row
            # préexistante. On crée alors l'association avec le state demandé.
            row = UserSource(
                user_id=user_id,
                source_id=source_id,
                state=state,
            )
            self.db.add(row)
            await self.db.flush()  # mirror UserInterest upsert (line ~163)
            prev_state = None
        else:
            prev_state = row.state
            row.state = state

        await self._sync_favorite_source(
            user_id=user_id, source_id=source_id, state=state, position=position
        )
        await self._sync_muted_source(user_id=user_id, source_id=source_id, state=state)
        await self.db.commit()
        return prev_state

    async def _sync_muted_source(
        self, user_id: UUID, source_id: UUID, state: InterestState
    ) -> None:
        """Garde `personalization.muted_sources` cohérent avec l'état de la source.

        Le feed exclut une source via `personalization.muted_sources` (cf.
        `recommendation_service` + `pillars/penalties`), JAMAIS via
        `UserSource.state` (contrairement aux Thèmes/Sujets, cf. `pertinence`).
        Le curseur de priorité de la fiche source expose un palier « Masqué »
        qui passe la source en `HIDDEN` : sans ce miroir, « Masqué » ne
        retirerait pas la source du flux. On ajoute donc la source à
        `muted_sources` sur `HIDDEN`, et on l'en retire sur tout autre état
        (suivi/favori/neutre) pour rester réversible.
        """
        if state == InterestState.HIDDEN:
            # FK user_personalization → user_profiles : garantir le profil
            # avant l'upsert (un user peut masquer depuis le reader sans row
            # de personnalisation préexistante).
            from app.services.user_service import UserService

            await UserService(self.db).get_or_create_profile(str(user_id))
            await self.db.execute(
                insert(UserPersonalization)
                .values(user_id=user_id, muted_sources=[source_id])
                .on_conflict_do_update(
                    index_elements=["user_id"],
                    set_={
                        # array_remove avant array_append → idempotent (pas de
                        # doublon si déjà mutée).
                        "muted_sources": func.array_append(
                            func.array_remove(
                                func.coalesce(
                                    UserPersonalization.muted_sources,
                                    text("ARRAY[]::uuid[]"),
                                ),
                                source_id,
                            ),
                            source_id,
                        ),
                        "updated_at": func.now(),
                    },
                )
            )
        else:
            # Démutage idempotent : no-op si pas de row perso / source absente.
            await self.db.execute(
                update(UserPersonalization)
                .where(UserPersonalization.user_id == user_id)
                .values(
                    muted_sources=func.array_remove(
                        UserPersonalization.muted_sources, source_id
                    ),
                    updated_at=func.now(),
                )
            )

    async def _sync_favorite_source(
        self,
        user_id: UUID,
        source_id: UUID,
        state: InterestState,
        position: int | None,
    ) -> None:
        existing = (
            (
                await self.db.execute(
                    select(UserFavoriteSource).where(
                        UserFavoriteSource.user_id == user_id
                    )
                )
            )
            .scalars()
            .all()
        )
        current = next((f for f in existing if f.source_id == source_id), None)

        if state == InterestState.FAVORITE:
            if current is not None:
                if position is not None and current.position != position:
                    if any(
                        f.position == position and f is not current for f in existing
                    ):
                        return
                    current.position = position
                return
            # Plus de cap dur (Story 22.2) — append à la fin.
            taken = {f.position for f in existing}
            if position is None or position in taken:
                position = (max(taken) + 1) if taken else 0

            self.db.add(
                UserFavoriteSource(
                    user_id=user_id, position=position, source_id=source_id
                )
            )
        else:
            if current is not None:
                await self.db.delete(current)

    async def reorder_favorites(
        self, user_id: UUID, favorites: list[SourceFavoriteRef]
    ) -> None:
        for fav in favorites:
            row = (
                await self.db.execute(
                    select(UserSource).where(
                        UserSource.user_id == user_id,
                        UserSource.source_id == fav.source_id,
                    )
                )
            ).scalar_one_or_none()
            if row is None or row.state != InterestState.FAVORITE:
                raise TargetNotFavorite(
                    f"source {fav.source_id} is not favorite for user {user_id}"
                )

        await self.db.execute(
            delete(UserFavoriteSource).where(UserFavoriteSource.user_id == user_id)
        )
        for fav in favorites:
            self.db.add(
                UserFavoriteSource(
                    user_id=user_id, position=fav.position, source_id=fav.source_id
                )
            )
        await self.db.commit()
