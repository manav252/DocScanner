from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.security import create_token, current_user, decode_token, hash_password, verify_password
from ..db import get_session
from ..models import User
from ..schemas import Credentials, RefreshIn, TokenOut, UserOut

router = APIRouter(prefix="/auth", tags=["auth"])


def _tokens(request: Request, user: User) -> TokenOut:
    s = request.app.state.settings
    access, expires = create_token(s, user.id, "access")
    refresh, _ = create_token(s, user.id, "refresh")
    return TokenOut(access_token=access, refresh_token=refresh, expires_in=expires, user=UserOut(id=str(user.id), email=user.email))


@router.post("/register", response_model=TokenOut, status_code=status.HTTP_201_CREATED)
async def register(body: Credentials, request: Request, session: AsyncSession = Depends(get_session)) -> TokenOut:
    user = User(email=body.email.lower(), password_hash=hash_password(body.password))
    session.add(user)
    try:
        await session.commit()
    except IntegrityError as e:
        raise HTTPException(status.HTTP_409_CONFLICT, "An account with this email already exists") from e
    return _tokens(request, user)


@router.post("/login", response_model=TokenOut)
async def login(body: Credentials, request: Request, session: AsyncSession = Depends(get_session)) -> TokenOut:
    user = (await session.execute(select(User).where(User.email == body.email.lower()))).scalar_one_or_none()
    # Same message for unknown email and wrong password.
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Wrong email or password")
    return _tokens(request, user)


@router.post("/refresh", response_model=TokenOut)
async def refresh(body: RefreshIn, request: Request, session: AsyncSession = Depends(get_session)) -> TokenOut:
    user_id = decode_token(request.app.state.settings, body.refresh_token, "refresh")
    user = await session.get(User, user_id)
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "User no longer exists")
    return _tokens(request, user)


@router.get("/me", response_model=UserOut)
async def me(user: User = Depends(current_user)) -> UserOut:
    return UserOut(id=str(user.id), email=user.email)
