import uuid
from datetime import UTC, datetime, timedelta

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pwdlib import PasswordHash
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import get_session
from ..models import User
from .config import Settings

_hasher = PasswordHash.recommended()  # Argon2id
_bearer = HTTPBearer(auto_error=False)


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, hashed: str) -> bool:
    return _hasher.verify(password, hashed)


def create_token(settings: Settings, user_id: uuid.UUID, kind: str) -> tuple[str, int]:
    lifetime = (
        timedelta(minutes=settings.access_token_minutes)
        if kind == "access"
        else timedelta(days=settings.refresh_token_days)
    )
    now = datetime.now(UTC)
    token = jwt.encode(
        {"sub": str(user_id), "type": kind, "iat": now, "exp": now + lifetime, "jti": uuid.uuid4().hex},
        settings.jwt_secret,
        algorithm="HS256",
    )
    return token, int(lifetime.total_seconds())


def decode_token(settings: Settings, token: str, kind: str) -> uuid.UUID:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"], options={"require": ["exp", "sub"]})
        if payload.get("type") != kind:
            raise jwt.InvalidTokenError("wrong token type")
        return uuid.UUID(payload["sub"])
    except (jwt.InvalidTokenError, ValueError) as e:
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED, "Invalid or expired token", headers={"WWW-Authenticate": "Bearer"}
        ) from e


async def current_user(
    request: Request,
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: AsyncSession = Depends(get_session),
) -> User:
    if creds is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not authenticated", headers={"WWW-Authenticate": "Bearer"})
    user_id = decode_token(request.app.state.settings, creds.credentials, "access")
    user = await session.get(User, user_id)
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User no longer exists")
    return user
