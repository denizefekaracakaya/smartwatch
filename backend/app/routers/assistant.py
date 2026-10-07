"""AI search assistant endpoint."""

from fastapi import APIRouter, Request

from app.deps import CurrentUser, DbDep, LimiterDep, SettingsDep
from app.schemas import AssistantRequest, AssistantResponse
from app.services.assistant import AssistantService

router = APIRouter(prefix="/assistant", tags=["assistant"])


@router.post("/search", response_model=AssistantResponse)
def assistant_search(
    body: AssistantRequest,
    request: Request,
    user: CurrentUser,
    db: DbDep,
    settings: SettingsDep,
    limiter: LimiterDep,
):
    limiter.hit(f"assistant:{user.id}", settings.rate_limit_assistant)
    service = AssistantService(db, settings, request.app.state.assistant_client)
    return service.search(body.query, body.kind)
