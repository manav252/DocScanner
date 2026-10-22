import uuid
from datetime import UTC, datetime

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, Index, Integer, Sequence, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def utcnow() -> datetime:
    return datetime.now(UTC)


class Base(DeclarativeBase):
    pass


# Global, monotonically increasing change counter: clients pull "everything after N".
change_seq = Sequence("document_change_seq", metadata=Base.metadata)


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(320), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Document(Base):
    """A document; its pages live in `pages` (JSONB) and their images in S3."""

    __tablename__ = "documents"
    __table_args__ = (
        UniqueConstraint("owner_id", "client_id", name="uq_documents_owner_client"),
        Index("ix_documents_owner_seq", "owner_id", "change_seq"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"))
    # The id the app generated; stable across devices, used in URLs.
    client_id: Mapped[str] = mapped_column(String(64))
    title: Mapped[str] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    # Bumped on every server-side change (optimistic concurrency).
    version: Mapped[int] = mapped_column(Integer, default=1)
    change_seq: Mapped[int] = mapped_column(BigInteger, change_seq, server_default=change_seq.next_value())
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    pages: Mapped[list[dict]] = mapped_column(JSONB, default=list)
