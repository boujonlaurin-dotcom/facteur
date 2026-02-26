from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class TopicProgressResponse(BaseModel):
    id: UUID
    user_id: UUID
    topic: str
    level: int
    points: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class QuizOption(BaseModel):
    text: str
    id: int


class QuizResponse(BaseModel):
    id: UUID
    topic: str
    question: str
    options: list[str]  # Simplified for now, just list of strings
    difficulty: int
    # We don't return correct_answer here obviously

    class Config:
        from_attributes = True


class QuizResultRequest(BaseModel):
    quiz_id: UUID
    selected_option_index: int


class QuizResultResponse(BaseModel):
    is_correct: bool
    correct_answer: int
    points_earned: int
    new_level: int | None = None
    message: str


class FollowTopicRequest(BaseModel):
    topic: str
