"""S3-compatible object storage (MinIO locally) for page images."""
from __future__ import annotations

import boto3
from botocore.client import Config
from botocore.exceptions import ClientError
from starlette.concurrency import run_in_threadpool

from ..core.config import Settings


def page_key(owner_id: str, doc_id: str, page_id: str, kind: str) -> str:
    return f"users/{owner_id}/docs/{doc_id}/pages/{page_id}/{kind}"


def doc_prefix(owner_id: str, doc_id: str) -> str:
    return f"users/{owner_id}/docs/{doc_id}/"


class Storage:
    def __init__(self, settings: Settings):
        self.bucket = settings.s3_bucket
        self._s3 = boto3.client(
            "s3",
            endpoint_url=settings.s3_endpoint,
            aws_access_key_id=settings.s3_access_key,
            aws_secret_access_key=settings.s3_secret_key,
            region_name=settings.s3_region,
            config=Config(signature_version="s3v4", s3={"addressing_style": "path"}, retries={"max_attempts": 3}),
        )

    async def ensure_bucket(self) -> None:
        def _ensure() -> None:
            try:
                self._s3.head_bucket(Bucket=self.bucket)
            except ClientError:
                self._s3.create_bucket(Bucket=self.bucket)

        await run_in_threadpool(_ensure)

    async def put(self, key: str, data: bytes, content_type: str) -> None:
        await run_in_threadpool(self._s3.put_object, Bucket=self.bucket, Key=key, Body=data, ContentType=content_type)

    async def get(self, key: str) -> tuple[bytes, str] | None:
        def _get():
            try:
                obj = self._s3.get_object(Bucket=self.bucket, Key=key)
            except ClientError as e:
                if e.response.get("Error", {}).get("Code") in ("NoSuchKey", "404"):
                    return None
                raise
            return obj["Body"].read(), obj.get("ContentType", "application/octet-stream")

        return await run_in_threadpool(_get)

    async def exists(self, key: str) -> bool:
        def _head() -> bool:
            try:
                self._s3.head_object(Bucket=self.bucket, Key=key)
                return True
            except ClientError:
                return False

        return await run_in_threadpool(_head)

    async def keys(self, prefix: str) -> set[str]:
        def _list() -> set[str]:
            out: set[str] = set()
            for page in self._s3.get_paginator("list_objects_v2").paginate(Bucket=self.bucket, Prefix=prefix):
                out.update(o["Key"] for o in page.get("Contents", []))
            return out

        return await run_in_threadpool(_list)

    async def delete_keys(self, keys: list[str]) -> None:
        def _delete() -> None:
            for i in range(0, len(keys), 1000):
                chunk = keys[i:i + 1000]
                if chunk:
                    self._s3.delete_objects(Bucket=self.bucket, Delete={"Objects": [{"Key": k} for k in chunk]})

        await run_in_threadpool(_delete)

    async def delete_prefix(self, prefix: str) -> None:
        await self.delete_keys(sorted(await self.keys(prefix)))

    async def ping(self) -> bool:
        try:
            await run_in_threadpool(self._s3.head_bucket, Bucket=self.bucket)
            return True
        except Exception:  # noqa: BLE001
            return False
