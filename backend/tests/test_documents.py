import io
from datetime import UTC, datetime

import img2pdf

from tests.conftest import register

NOW = datetime(2026, 10, 22, 12, 0, tzinfo=UTC).isoformat()


def page(pid: str, **kw) -> dict:
    return {
        "id": pid,
        "source_width": 30,
        "source_height": 40,
        "corners": [[0, 0], [29, 0], [29, 39], [0, 39]],
        "edits": {"filter": "bw", "turns": 1, "crop": [0, 0, 1, 1]},
        "revision": 2,
        "render_width": 40,
        "render_height": 30,
        **kw,
    }


def doc(*pages: dict, base_version=None, title="Receipt") -> dict:
    return {"title": title, "created_at": NOW, "updated_at": NOW, "pages": list(pages), "base_version": base_version}


async def upload_page(client, headers, doc_id, pid, data):
    for kind in ("source", "render", "thumb"):
        r = await client.put(f"/documents/{doc_id}/pages/{pid}/files/{kind}", content=data, headers=headers)
        assert r.status_code == 204, r.text


async def test_files_must_be_uploaded_before_metadata(client, user, small_jpeg):
    h = user["headers"]
    r = await client.put("/documents/d1", json=doc(page("p1")), headers=h)
    assert r.status_code == 422
    assert set(r.json()["detail"]["missing"]) == {"p1/source", "p1/render", "p1/thumb"}
    await upload_page(client, h, "d1", "p1", small_jpeg)
    r = await client.put("/documents/d1", json=doc(page("p1")), headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["version"] == 1 and body["id"] == "d1" and body["pages"][0]["edits"]["filter"] == "bw"


async def test_versioning_conflict_and_page_removal(client, user, small_jpeg):
    h = user["headers"]
    for pid in ("a", "b"):
        await upload_page(client, h, "d2", pid, small_jpeg)
    v1 = (await client.put("/documents/d2", json=doc(page("a"), page("b")), headers=h)).json()
    v2 = await client.put("/documents/d2", json=doc(page("b"), base_version=1, title="Renamed"), headers=h)
    assert v2.status_code == 200 and v2.json()["version"] == 2 and v2.json()["change_seq"] > v1["change_seq"]
    # Page "a" was dropped: its files are gone.
    assert (await client.get("/documents/d2/pages/a/files/render", headers=h)).status_code == 404
    assert (await client.get("/documents/d2/pages/b/files/render", headers=h)).status_code == 200
    # Another device still based on version 1 gets a conflict with the server copy.
    stale = await client.put("/documents/d2", json=doc(page("b"), base_version=1, title="Other"), headers=h)
    assert stale.status_code == 409
    assert stale.json()["document"]["title"] == "Renamed"


async def test_list_since_cursor_and_tombstones(client, user, small_jpeg):
    h = user["headers"]
    await upload_page(client, h, "d3", "p", small_jpeg)
    await client.put("/documents/d3", json=doc(page("p")), headers=h)
    first = (await client.get("/documents", headers=h)).json()
    assert [d["id"] for d in first["documents"]] == ["d3"]
    cursor = first["cursor"]
    assert (await client.get(f"/documents?since={cursor}", headers=h)).json()["documents"] == []

    assert (await client.delete("/documents/d3?base_version=5", headers=h)).status_code == 409
    assert (await client.delete("/documents/d3?base_version=1", headers=h)).status_code == 204
    assert (await client.get("/documents", headers=h)).json()["documents"] == []
    changes = (await client.get(f"/documents?since={cursor}", headers=h)).json()
    assert [(d["id"], d["deleted"]) for d in changes["documents"]] == [("d3", True)]
    assert (await client.get("/documents/d3/pages/p/files/thumb", headers=h)).status_code == 404
    assert (await client.get("/documents/d3", headers=h)).status_code == 404
    # Deleting twice is fine; re-creating on top of the tombstone works.
    assert (await client.delete("/documents/d3", headers=h)).status_code == 204
    await upload_page(client, h, "d3", "p", small_jpeg)
    r = await client.put("/documents/d3", json=doc(page("p"), base_version=2), headers=h)
    assert r.status_code == 200 and r.json()["deleted"] is False


async def test_pagination(client, user, small_jpeg):
    h = user["headers"]
    for i in range(3):
        await upload_page(client, h, f"pg{i}", "p", small_jpeg)
        await client.put(f"/documents/pg{i}", json=doc(page("p")), headers=h)
    a = (await client.get("/documents?since=0&limit=2", headers=h)).json()
    assert len(a["documents"]) == 2 and a["has_more"]
    b = (await client.get(f"/documents?since={a['cursor']}&limit=2", headers=h)).json()
    assert len(b["documents"]) == 1 and not b["has_more"]


async def test_users_are_isolated(client, user, small_jpeg):
    await upload_page(client, user["headers"], "secret", "p", small_jpeg)
    await client.put("/documents/secret", json=doc(page("p")), headers=user["headers"])
    other = await register(client)
    h = other["headers"]
    assert (await client.get("/documents/secret", headers=h)).status_code == 404
    assert (await client.get("/documents/secret/pages/p/files/render", headers=h)).status_code == 404
    assert (await client.get("/documents", headers=h)).json()["documents"] == []
    # Same client id in another account is a separate document.
    await upload_page(client, h, "secret", "p", small_jpeg)
    assert (await client.put("/documents/secret", json=doc(page("p")), headers=h)).status_code == 200


async def test_file_validation(client, user, small_jpeg):
    h = user["headers"]
    url = "/documents/d4/pages/p/files/render"
    assert (await client.put(url, content=b"not an image at all", headers=h)).status_code == 415
    assert (await client.put(url, content=b"\xff\xd8\xff" + b"0" * (3 * 1024 * 1024), headers=h)).status_code == 413
    assert (await client.put("/documents/d4/pages/p/files/other", content=small_jpeg, headers=h)).status_code == 422
    assert (
        await client.put("/documents/bad%20id/pages/p/files/render", content=small_jpeg, headers=h)
    ).status_code == 422
    assert (await client.put(url, content=small_jpeg, headers=h)).status_code == 204
    r = await client.get(url, headers=h)
    assert r.status_code == 200 and r.content == small_jpeg and r.headers["content-type"] == "image/jpeg"
    assert (await client.get(url)).status_code == 401


async def test_metadata_validation(client, user):
    h = user["headers"]
    bad_crop = page("p", edits={"filter": "bw", "turns": 0, "crop": [0.5, 0, 0.9, 1]})
    assert (await client.put("/documents/v", json=doc(bad_crop), headers=h)).status_code == 422
    assert (await client.put("/documents/v", json=doc(page("p"), page("p")), headers=h)).status_code == 422
    assert (await client.put("/documents/v", json=doc(page("p", corners=[[0, 0]])), headers=h)).status_code == 422
    assert (await client.put("/documents/v", json={**doc(), "title": ""}, headers=h)).status_code == 422
    too_many = doc(*[page(f"p{i}") for i in range(21)])
    assert (await client.put("/documents/v", json=too_many, headers=h)).status_code == 422


async def test_pdf_download(client, user, photo):
    h = user["headers"]
    for pid in ("one", "two"):
        await upload_page(client, h, "pdfdoc", pid, photo)
    await client.put("/documents/pdfdoc", json=doc(page("one"), page("two"), title="Tax: 2026"), headers=h)
    r = await client.get("/documents/pdfdoc/pdf", headers=h)
    assert r.status_code == 200 and r.content.startswith(b"%PDF")
    assert (
        r.content.count(b"/Type /Page\n") + r.content.count(b"/Type /Page ") + r.content.count(b"/Type/Page") >= 2
        or len(__import__("pypdfium2").PdfDocument(r.content)) == 2
    )
    assert "Tax%3A%202026.pdf" in r.headers["content-disposition"]


async def test_upload_pdf_and_photo(client, user, photo):
    h = user["headers"]
    pdf = img2pdf.convert([photo, photo])
    files = [
        ("files", ("scan.pdf", io.BytesIO(pdf), "application/pdf")),
        ("files", ("page.jpg", io.BytesIO(photo), "image/jpeg")),
    ]
    r = await client.post("/documents/upload", files=files, headers=h)
    assert r.status_code == 201, r.text
    d = r.json()
    assert len(d["pages"]) == 3
    pdf_page, photo_page = d["pages"][0], d["pages"][2]
    assert pdf_page["edits"]["filter"] == "original"
    assert photo_page["edits"]["filter"] == "magic_color", "photo: page detected"
    assert 0.65 < photo_page["render_width"] / photo_page["render_height"] < 0.85
    for p in d["pages"]:
        for kind in ("source", "render", "thumb"):
            assert (
                await client.get(f"/documents/{d['id']}/pages/{p['id']}/files/{kind}", headers=h)
            ).status_code == 200
    # It shows up for sync.
    assert d["id"] in [x["id"] for x in (await client.get("/documents", headers=h)).json()["documents"]]


async def test_upload_rejects_bad_files(client, user):
    h = user["headers"]
    r = await client.post("/documents/upload", files=[("files", ("x.txt", b"hello", "text/plain"))], headers=h)
    assert r.status_code == 415
    r = await client.post(
        "/documents/upload", files=[("files", ("x.pdf", b"%PDF-1.4 broken", "application/pdf"))], headers=h
    )
    assert r.status_code == 422


async def test_markup_round_trip_and_limits(client, user, small_jpeg):
    h = user["headers"]
    await upload_page(client, h, "mk", "p", small_jpeg)
    item = {"k": "text", "id": "t1", "text": "Approved", "x": 0.5, "y": 0.1}
    r = await client.put("/documents/mk", json=doc(page("p", markup=[item])), headers=h)
    assert r.status_code == 200 and r.json()["pages"][0]["markup"] == [item]
    bad = await client.put("/documents/mk", json=doc(page("p", markup=[{"x": 1}]), base_version=1), headers=h)
    assert bad.status_code == 422
    huge = [{"k": "pen", "id": str(i), "p": [0.1] * 400} for i in range(1500)]
    assert (
        await client.put("/documents/mk", json=doc(page("p", markup=huge), base_version=1), headers=h)
    ).status_code == 422
