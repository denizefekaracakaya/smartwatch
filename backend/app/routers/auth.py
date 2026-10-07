"""Authentication & account endpoints."""

from html import escape
from typing import Annotated
from urllib.parse import parse_qs

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Request, Response, status
from fastapi.responses import HTMLResponse

from app.deps import CurrentUser, DbDep, EmailDep, LimiterDep, SettingsDep, client_ip
from app.errors import ApiError
from app.schemas import (
    ChangePasswordRequest,
    DeleteAccountRequest,
    EmailRequest,
    LoginRequest,
    MessageOut,
    RefreshRequest,
    RegisterRequest,
    ResetPasswordRequest,
    TokenPair,
    UpdateProfileRequest,
    UserOut,
    VerifyEmailRequest,
)
from app.services.auth import AuthService

router = APIRouter(prefix="/auth", tags=["auth"])

_ACCEPTED = MessageOut(detail="If the account exists, an e-mail has been sent")


@router.post("/register", status_code=status.HTTP_201_CREATED, response_model=UserOut)
def register(
    body: RegisterRequest,
    request: Request,
    background: BackgroundTasks,
    db: DbDep,
    settings: SettingsDep,
    mailer: EmailDep,
    limiter: LimiterDep,
):
    limiter.hit(f"register:{client_ip(request)}", settings.rate_limit_auth)
    user, mail = AuthService(db, settings).register(body.email, body.password, body.display_name)
    background.add_task(mailer.send, mail)
    return user


@router.post("/login", response_model=TokenPair)
def login(body: LoginRequest, request: Request, db: DbDep, settings: SettingsDep, limiter: LimiterDep):
    limiter.hit(f"login-ip:{client_ip(request)}", settings.rate_limit_auth)
    limiter.hit(f"login-account:{body.email}", settings.rate_limit_auth)
    service = AuthService(db, settings)
    return service.issue_session(service.authenticate(body.email, body.password))


@router.post("/refresh", response_model=TokenPair)
def refresh(body: RefreshRequest, request: Request, db: DbDep, settings: SettingsDep, limiter: LimiterDep):
    limiter.hit(f"refresh:{client_ip(request)}", "60/60")
    return AuthService(db, settings).refresh(body.refresh_token)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(body: RefreshRequest, db: DbDep, settings: SettingsDep) -> Response:
    AuthService(db, settings).logout(body.refresh_token)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/resend-verification", status_code=status.HTTP_202_ACCEPTED, response_model=MessageOut)
def resend_verification(
    body: EmailRequest,
    request: Request,
    background: BackgroundTasks,
    db: DbDep,
    settings: SettingsDep,
    mailer: EmailDep,
    limiter: LimiterDep,
):
    limiter.hit(f"resend-ip:{client_ip(request)}", settings.rate_limit_auth)
    limiter.hit(f"resend-account:{body.email}", "3/600")
    mail = AuthService(db, settings).resend_verification(body.email)
    if mail is not None:
        background.add_task(mailer.send, mail)
    return _ACCEPTED


@router.post("/verify-email", response_model=UserOut)
def verify_email(
    body: VerifyEmailRequest, request: Request, db: DbDep, settings: SettingsDep, limiter: LimiterDep
):
    limiter.hit(f"verify:{client_ip(request)}", settings.rate_limit_auth)
    return AuthService(db, settings).verify_email(body.token)


def _page(title: str, body_html: str, status_code: int = 200) -> HTMLResponse:
    html = (
        "<!doctype html><html lang='tr'><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>{title}</title><style>body{{font-family:sans-serif;background:#121212;color:#eee;"
        "display:grid;place-items:center;min-height:100vh;margin:0}main{max-width:28rem;padding:1.5rem}"
        "h1{color:#9f7aea}button{font-size:1rem;padding:.75rem 1.5rem;border:0;border-radius:.5rem;"
        "background:#7c4dff;color:#fff;cursor:pointer}</style></head>"
        f"<body><main><h1>{title}</h1>{body_html}</main></body></html>"
    )
    return HTMLResponse(html, status_code=status_code)


@router.get("/verify-email", response_class=HTMLResponse, include_in_schema=False)
def verify_email_link(token: str = Query(min_length=1, max_length=200)) -> HTMLResponse:
    """Target of the link in the verification e-mail.

    GET only renders a confirmation button: mail security scanners prefetch links, and a state-changing GET
    would let them consume the single-use token before the user clicks it.
    """
    return _page(
        "E-posta doğrulama",
        "<p>Hesabını etkinleştirmek için aşağıdaki düğmeye bas.</p>"
        "<form method='post' action='verify-email/confirm'>"
        f"<input type='hidden' name='token' value='{escape(token, quote=True)}'>"
        "<button type='submit'>E-postamı doğrula</button></form>",
    )


async def _form_token(request: Request) -> str:
    """Parse ``token`` from an url-encoded form body without requiring python-multipart."""
    body = await request.body()
    if len(body) > 1024:
        raise ApiError(status.HTTP_413_CONTENT_TOO_LARGE, "validation_error", "Request body too large")
    token = parse_qs(body.decode("utf-8", errors="replace")).get("token", [""])[0]
    if not 0 < len(token) <= 200:
        raise ApiError(status.HTTP_422_UNPROCESSABLE_CONTENT, "validation_error", "Missing token")
    return token


@router.post("/verify-email/confirm", response_class=HTMLResponse, include_in_schema=False)
def verify_email_confirm(
    request: Request,
    db: DbDep,
    settings: SettingsDep,
    limiter: LimiterDep,
    token: Annotated[str, Depends(_form_token)],
) -> HTMLResponse:
    limiter.hit(f"verify:{client_ip(request)}", settings.rate_limit_auth)
    try:
        user = AuthService(db, settings).verify_email(token)
    except ApiError:
        return _page(
            "Bağlantı geçersiz",
            "<p>Bu doğrulama bağlantısı geçersiz veya süresi dolmuş. Uygulamadan yeni bir bağlantı iste.</p>",
            400,
        )
    return _page(
        "E-posta doğrulandı",
        f"<p>Teşekkürler {escape(user.display_name)}! Artık uygulamaya giriş yapabilirsin.</p>",
    )


@router.post("/forgot-password", status_code=status.HTTP_202_ACCEPTED, response_model=MessageOut)
def forgot_password(
    body: EmailRequest,
    request: Request,
    background: BackgroundTasks,
    db: DbDep,
    settings: SettingsDep,
    mailer: EmailDep,
    limiter: LimiterDep,
):
    limiter.hit(f"forgot-ip:{client_ip(request)}", settings.rate_limit_auth)
    limiter.hit(f"forgot-account:{body.email}", "3/600")
    mail = AuthService(db, settings).forgot_password(body.email)
    if mail is not None:
        background.add_task(mailer.send, mail)
    return _ACCEPTED


@router.post("/reset-password", status_code=status.HTTP_204_NO_CONTENT)
def reset_password(
    body: ResetPasswordRequest, request: Request, db: DbDep, settings: SettingsDep, limiter: LimiterDep
) -> Response:
    limiter.hit(f"reset-ip:{client_ip(request)}", settings.rate_limit_auth)
    AuthService(db, settings).reset_password(body.email, body.code, body.new_password)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


# ----- current user -----
@router.get("/me", response_model=UserOut)
def me(user: CurrentUser):
    return user


@router.patch("/me", response_model=UserOut)
def update_me(body: UpdateProfileRequest, user: CurrentUser, db: DbDep):
    user.display_name = body.display_name
    db.commit()
    return user


@router.post("/me/change-password", response_model=TokenPair)
def change_password(
    body: ChangePasswordRequest, user: CurrentUser, db: DbDep, settings: SettingsDep, limiter: LimiterDep
):
    limiter.hit(f"change-password:{user.id}", settings.rate_limit_auth)
    return AuthService(db, settings).change_password(user, body.current_password, body.new_password)


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
def delete_me(
    body: DeleteAccountRequest, user: CurrentUser, db: DbDep, settings: SettingsDep, limiter: LimiterDep
) -> Response:
    limiter.hit(f"delete-account:{user.id}", settings.rate_limit_auth)
    AuthService(db, settings).delete_account(user, body.password)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
