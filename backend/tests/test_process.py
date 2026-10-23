import json

import cv2
import numpy as np


async def test_detect_only(client, user, photo, expected):
    r = await client.post(
        "/process",
        files={"file": ("p.jpg", photo, "image/jpeg")},
        data={"detect_only": "true"},
        headers=user["headers"],
    )
    assert r.status_code == 200
    body = r.json()
    assert body["found"] and (body["width"], body["height"]) == (1200, 1600)
    err = np.linalg.norm(np.float32(body["corners"]) - np.float32(expected["cases"]["tilted_paper"]["corners"]), axis=1)
    assert err.max() < 20


async def test_full_process_returns_page_jpeg(client, user, photo):
    r = await client.post(
        "/process",
        files={"file": ("p.jpg", photo, "image/jpeg")},
        data={"filter": "bw", "max_side": "1000"},
        headers=user["headers"],
    )
    assert r.status_code == 200 and r.headers["content-type"] == "image/jpeg"
    assert r.headers["x-document-found"] == "true"
    assert len(json.loads(r.headers["x-document-corners"])) == 4
    img = cv2.imdecode(np.frombuffer(r.content, np.uint8), cv2.IMREAD_GRAYSCALE)
    assert max(img.shape) == 1000 and img.shape[0] > img.shape[1]


async def test_given_corners_rotate_and_crop_without_warp(client, user, photo):
    corners = json.dumps([[0, 0], [599, 0], [599, 799], [0, 799]])
    r = await client.post(
        "/process",
        files={"file": ("p.jpg", photo, "image/jpeg")},
        data={"corners": corners, "filter": "original"},
        headers=user["headers"],
    )
    assert (int(r.headers["x-image-width"]), int(r.headers["x-image-height"])) == (599, 799)
    r = await client.post(
        "/process",
        files={"file": ("p.jpg", photo, "image/jpeg")},
        data={"flat": "true", "rotate": "1", "crop": "[0, 0, 0.5, 1]", "filter": "grayscale"},
        headers=user["headers"],
    )
    assert r.status_code == 200
    assert (int(r.headers["x-image-width"]), int(r.headers["x-image-height"])) == (800, 1200)


async def test_process_validation(client, user, photo):
    h = user["headers"]
    assert (await client.post("/process", files={"file": ("p.jpg", photo, "image/jpeg")})).status_code == 401
    assert (
        await client.post("/process", files={"file": ("x.txt", b"hello", "text/plain")}, headers=h)
    ).status_code == 415
    bad = await client.post(
        "/process", files={"file": ("p.jpg", photo, "image/jpeg")}, data={"corners": "[[1,2]]"}, headers=h
    )
    assert bad.status_code == 422
    bad = await client.post(
        "/process", files={"file": ("p.jpg", photo, "image/jpeg")}, data={"filter": "sepia"}, headers=h
    )
    assert bad.status_code == 422
    bad = await client.post(
        "/process", files={"file": ("p.jpg", photo, "image/jpeg")}, data={"crop": "[0.9,0,0.5,1]"}, headers=h
    )
    assert bad.status_code == 422
