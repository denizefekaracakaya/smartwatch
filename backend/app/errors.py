"""Uniform API error format: ``{"detail": str, "code": str}``."""

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class ApiError(Exception):
    def __init__(self, status_code: int, code: str, detail: str, headers: dict[str, str] | None = None):
        self.status_code = status_code
        self.code = code
        self.detail = detail
        self.headers = headers


def not_found(what: str = "Resource") -> ApiError:
    return ApiError(status.HTTP_404_NOT_FOUND, "not_found", f"{what} not found")


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api_error(_: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse(
            {"detail": exc.detail, "code": exc.code}, status_code=exc.status_code, headers=exc.headers
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = {401: "unauthorized", 403: "forbidden", 404: "not_found", 405: "method_not_allowed"}.get(
            exc.status_code, "http_error"
        )
        return JSONResponse(
            {"detail": str(exc.detail), "code": code},
            status_code=exc.status_code,
            headers=getattr(exc, "headers", None),
        )

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        errors = [
            {"loc": list(e.get("loc", [])), "msg": e.get("msg", ""), "type": e.get("type", "")}
            for e in exc.errors()
        ]
        return JSONResponse(
            {"detail": "Request validation failed", "code": "validation_error", "errors": errors},
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
        )
