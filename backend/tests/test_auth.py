from tests.conftest import register


async def test_register_login_me(client):
    u = await register(client, email="Alice@Example.com")
    assert u["user"]["email"] == "alice@example.com"
    r = await client.post("/auth/login", json={"email": "alice@example.com", "password": "correct horse"})
    assert r.status_code == 200
    me = await client.get("/auth/me", headers={"Authorization": f"Bearer {r.json()['access_token']}"})
    assert me.json()["email"] == "alice@example.com"


async def test_duplicate_email(client):
    u = await register(client)
    r = await client.post("/auth/register", json={"email": u["email"].upper(), "password": "another one"})
    assert r.status_code == 409


async def test_wrong_password_and_unknown_user_look_the_same(client):
    u = await register(client)
    a = await client.post("/auth/login", json={"email": u["email"], "password": "wrong password"})
    b = await client.post("/auth/login", json={"email": "nobody@example.com", "password": "wrong password"})
    assert a.status_code == b.status_code == 401
    assert a.json() == b.json()


async def test_validation(client):
    assert (
        await client.post("/auth/register", json={"email": "x@example.com", "password": "short"})
    ).status_code == 422
    assert (
        await client.post("/auth/register", json={"email": "not-an-email", "password": "long enough"})
    ).status_code == 422


async def test_tokens(client):
    u = await register(client)
    assert (await client.get("/auth/me")).status_code == 401
    assert (await client.get("/auth/me", headers={"Authorization": "Bearer garbage"})).status_code == 401
    # A refresh token is not an access token, and vice versa.
    assert (await client.get("/auth/me", headers={"Authorization": f"Bearer {u['refresh_token']}"})).status_code == 401
    assert (await client.post("/auth/refresh", json={"refresh_token": u["access_token"]})).status_code == 401
    r = await client.post("/auth/refresh", json={"refresh_token": u["refresh_token"]})
    assert r.status_code == 200
    assert (
        await client.get("/auth/me", headers={"Authorization": f"Bearer {r.json()['access_token']}"})
    ).status_code == 200
