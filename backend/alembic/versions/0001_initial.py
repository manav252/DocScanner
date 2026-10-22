"""users and documents

Revision ID: 0001
Revises:
Create Date: 2026-10-22
"""
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("email", sa.String(320), nullable=False),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)
    op.execute(sa.schema.CreateSequence(sa.Sequence("document_change_seq")))
    op.create_table(
        "documents",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("owner_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("client_id", sa.String(64), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("version", sa.Integer, nullable=False),
        sa.Column("change_seq", sa.BigInteger, nullable=False, server_default=sa.text("nextval('document_change_seq')")),
        sa.Column("deleted", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column("pages", postgresql.JSONB, nullable=False, server_default=sa.text("'[]'::jsonb")),
        sa.UniqueConstraint("owner_id", "client_id", name="uq_documents_owner_client"),
    )
    op.create_index("ix_documents_owner_seq", "documents", ["owner_id", "change_seq"])


def downgrade() -> None:
    op.drop_index("ix_documents_owner_seq", table_name="documents")
    op.drop_table("documents")
    op.execute(sa.schema.DropSequence(sa.Sequence("document_change_seq")))
    op.drop_index("ix_users_email", table_name="users")
    op.drop_table("users")
