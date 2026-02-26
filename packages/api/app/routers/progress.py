from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.progress import TopicQuiz, UserTopicProgress
from app.schemas.progress import (
    FollowTopicRequest,
    QuizResponse,
    QuizResultRequest,
    QuizResultResponse,
    TopicProgressResponse,
)

router = APIRouter()
log = structlog.get_logger()

# MVP Note: Quiz functionality is deprioritized.
# Topic following is still active for user interest tracking.
# Quiz endpoints will log deprecation warnings.


@router.get("/", response_model=list[TopicProgressResponse])
async def get_my_progress(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Récupère la progression de l'utilisateur sur tous ses sujets suivis.
    """
    user_uuid = UUID(current_user_id)

    stmt = select(UserTopicProgress).where(UserTopicProgress.user_id == user_uuid)
    result = await db.execute(stmt)
    progress_list = result.scalars().all()

    return progress_list


@router.post(
    "/follow", response_model=TopicProgressResponse, status_code=status.HTTP_201_CREATED
)
async def follow_topic(
    request: FollowTopicRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Commence à suivre un thème pour progresser dessus.
    """
    user_uuid = UUID(current_user_id)

    # Vérifier si déjà suivi
    stmt = select(UserTopicProgress).where(
        UserTopicProgress.user_id == user_uuid, UserTopicProgress.topic == request.topic
    )
    result = await db.execute(stmt)
    existing = result.scalar_one_or_none()

    if existing:
        return existing

    # Créer nouvelle progression
    new_progress = UserTopicProgress(
        user_id=user_uuid, topic=request.topic, level=1, points=0
    )
    db.add(new_progress)
    await db.commit()
    await db.refresh(new_progress)

    return new_progress


@router.get("/quiz", response_model=QuizResponse)
async def get_quiz(
    topic: str,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Récupère un quiz aléatoire pour un thème donné.
    Si aucun quiz n'existe, en génère un mock pour la démo (WIP).

    MVP NOTE: Quiz feature is deprioritized. This endpoint remains functional
    but is not actively used by the mobile app.
    """
    log.warning(
        "quiz_endpoint_called",
        endpoint="get_quiz",
        topic=topic,
        note="Quiz feature deprioritized for MVP",
    )
    UUID(current_user_id)

    # 1. Chercher un quiz en base
    stmt = (
        select(TopicQuiz)
        .where(TopicQuiz.topic == topic)
        .order_by(func.random())
        .limit(1)
    )
    result = await db.execute(stmt)
    quiz = result.scalar_one_or_none()

    if quiz:
        return quiz

    # 2. Fallback mock pour la démo si pas de données
    # Cela permet de tester la feature sans peupler la DB manuellement tout de suite
    mock_quiz = QuizResponse(
        id=UUID("00000000-0000-0000-0000-000000000000"),
        topic=topic,
        question=f"Quelle est la principale caractéristique de {topic} dans l'actualité récente ?",
        options=[
            "C'est un sujet en forte croissance",
            "C'est un sujet controversé",
            "Personne n'en parle",
            "La réponse D",
        ],
        difficulty=1,
    )
    return mock_quiz


@router.post("/quiz/submit", response_model=QuizResultResponse)
async def submit_quiz(
    request: QuizResultRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Valide une réponse de quiz et met à jour la progression.

    MVP NOTE: Quiz feature is deprioritized. This endpoint remains functional
    but is not actively used by the mobile app.
    """
    log.warning(
        "quiz_endpoint_called",
        endpoint="submit_quiz",
        note="Quiz feature deprioritized for MVP",
    )
    user_uuid = UUID(current_user_id)

    # Récupérer le quiz (ou mocker)
    # Pour le mock UUID zero, on simule une réponse correcte à l'index 0
    is_mock = str(request.quiz_id) == "00000000-0000-0000-0000-000000000000"
    is_correct = False
    correct_answer = 0
    topic = "Mock Topic"

    if is_mock:
        is_correct = request.selected_option_index == 0
    else:
        quiz = await db.get(TopicQuiz, request.quiz_id)
        if not quiz:
            raise HTTPException(status_code=404, detail="Quiz not found")

        is_correct = request.selected_option_index == quiz.correct_answer
        correct_answer = quiz.correct_answer
        topic = quiz.topic

    # Calcul des points
    points_earned = 10 if is_correct else 0
    message = "Bravo ! Bonne réponse." if is_correct else "Dommage, ce n'est pas ça."

    new_level = None

    # Mise à jour progression si correct et pas mock (ou si on voulait supporter le mock progress)
    # Pour la démo, on cherche si le user a une progression sur ce topic "Mock Topic" si c'est un mock
    # Mais comme on n'a pas le topic dans la request, c'est compliqué pour le mock.
    # On assume que c'est une démo stateless pour le mock.

    if not is_mock and is_correct:
        # Update user progress
        stmt = select(UserTopicProgress).where(
            UserTopicProgress.user_id == user_uuid, UserTopicProgress.topic == topic
        )
        result = await db.execute(stmt)
        progress = result.scalar_one_or_none()

        if progress:
            progress.points += points_earned
            # Level up simple logic: every 100 points
            old_level = progress.level
            progress.level = 1 + (progress.points // 100)

            if progress.level > old_level:
                new_level = progress.level
                message = f"Excellent ! Vous passez au niveau {new_level} !"

            await db.commit()

    return QuizResultResponse(
        is_correct=is_correct,
        correct_answer=correct_answer,
        points_earned=points_earned,
        new_level=new_level,
        message=message,
    )
