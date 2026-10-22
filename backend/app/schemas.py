import json
from datetime import datetime
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator

Id = Annotated[str, Field(pattern=r"^[A-Za-z0-9_-]{1,64}$")]
FilterName = Literal["original", "grayscale", "bw", "magic_color"]
FileKind = Literal["source", "render", "thumb"]


# ---------- auth ----------

class Credentials(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class RefreshIn(BaseModel):
    refresh_token: str


class UserOut(BaseModel):
    id: str
    email: str


class TokenOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int
    user: UserOut


# ---------- documents ----------

class Edits(BaseModel):
    model_config = ConfigDict(extra="forbid")
    filter: FilterName = "magic_color"
    turns: int = Field(0, ge=0, le=3)
    crop: list[float] = Field(default_factory=lambda: [0.0, 0.0, 1.0, 1.0], min_length=4, max_length=4)

    @field_validator("crop")
    @classmethod
    def _crop_in_unit_square(cls, v: list[float]) -> list[float]:
        l, t, w, h = v
        if not (0 <= l < 1 and 0 <= t < 1 and 0 < w <= 1.0001 - l and 0 < h <= 1.0001 - t):
            raise ValueError("crop must lie inside [0, 1]")
        return v


class Page(BaseModel):
    model_config = ConfigDict(extra="forbid")
    id: Id
    source_width: int = Field(gt=0, le=30000)
    source_height: int = Field(gt=0, le=30000)
    corners: list[list[float]] = Field(min_length=4, max_length=4)
    edits: Edits = Field(default_factory=Edits)
    revision: int = Field(0, ge=0)
    source_version: int = Field(0, ge=0)
    render_width: int = Field(0, ge=0, le=30000)
    render_height: int = Field(0, ge=0, le=30000)
    ocr_text: str | None = Field(None, max_length=200_000)
    # Editable annotations from the app's markup editor (opaque to the server).
    markup: list[dict[str, Any]] = Field(default_factory=list, max_length=2_000)

    @field_validator("markup")
    @classmethod
    def _markup_size(cls, v: list[dict[str, Any]]) -> list[dict[str, Any]]:
        if len(json.dumps(v)) > 1_000_000:
            raise ValueError("markup too large (max 1 MB per page)")
        if any(not isinstance(m.get("k"), str) or not isinstance(m.get("id"), str) for m in v):
            raise ValueError("each markup item needs a kind 'k' and an 'id'")
        return v

    @field_validator("corners")
    @classmethod
    def _points(cls, v: list[list[float]]) -> list[list[float]]:
        if any(len(p) != 2 for p in v):
            raise ValueError("corners must be 4 [x, y] points")
        return v


class DocumentIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    title: str = Field(min_length=1, max_length=200)
    created_at: datetime
    updated_at: datetime
    pages: list[Page] = Field(default_factory=list)
    # Server version this edit is based on; None when creating.
    base_version: int | None = None

    @model_validator(mode="after")
    def _unique_pages(self) -> "DocumentIn":
        ids = [p.id for p in self.pages]
        if len(ids) != len(set(ids)):
            raise ValueError("duplicate page ids")
        return self


class DocumentOut(BaseModel):
    id: str
    title: str
    created_at: datetime
    updated_at: datetime
    version: int
    change_seq: int
    deleted: bool
    pages: list[Page]


class DocumentList(BaseModel):
    documents: list[DocumentOut]
    # Pass as `since` to get only later changes.
    cursor: int
    has_more: bool


class Conflict(BaseModel):
    detail: str
    document: DocumentOut


class ProcessResult(BaseModel):
    found: bool
    corners: list[list[float]]
    width: int
    height: int
