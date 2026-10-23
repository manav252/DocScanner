# Putting DocScanner online for a demo

Everything works without the backend (scanning, editing, OCR, export, backup
as a ZIP). So the simplest public demo is just the website + web app on
GitHub Pages. Add the backend only if you want to show account backup/sync.

Nothing in this repository deploys by itself, and no account is created for you.
The steps below are done by you, in your browser.

| Part | Where | Cost | Config in this repo |
|---|---|---|---|
| Website + web app | GitHub Pages | free | `.github/workflows/pages.yml` |
| Backend API + database (optional) | Render | free tier | `render.yaml` |
| Page image storage for the backend (optional) | Cloudflare R2 (S3-compatible) | free tier (10 GB) | env vars in Render |

## 1. Website and web app on GitHub Pages (about 5 minutes)

The repository is already on GitHub: https://github.com/manav252/DocScanner

1. Open the repository on GitHub → **Settings** → **Pages**.
2. Under **Build and deployment** → **Source**, choose **GitHub Actions**.
3. Go to the **Actions** tab → **Deploy website and web app** → **Run workflow**
   (it also runs on every push to `main`). The first run takes about 5 minutes.
4. When it is green, open:
   - Website: **https://manav252.github.io/DocScanner/**
   - Web app: **https://manav252.github.io/DocScanner/app/**

Pages is served over HTTPS, so the camera works in phone browsers too. After the
first visit the app also works offline, and it can be installed ("Add to Home
Screen" on phones, the install icon in Chrome's address bar on computers).

Without step 2 below, the app's backup/sync screen simply reports that the server
cannot be reached; every other feature works.

## 2. Backend on Render (optional, about 15 minutes)

### 2a. Storage for page images: Cloudflare R2

1. Create a free Cloudflare account → **R2 Object Storage** → **Create bucket**,
   name it `docscanner`.
2. **R2** → **Manage R2 API Tokens** → **Create API token** with
   *Object Read & Write* on that bucket. Copy the **Access Key ID**, the
   **Secret Access Key** and the **S3 endpoint**
   (`https://<account-id>.r2.cloudflarestorage.com`).

(Any S3-compatible storage works: Backblaze B2, AWS S3, a MinIO server.)

### 2b. API and database: Render

1. Create a free account at https://render.com and connect your GitHub account.
2. **New** → **Blueprint** → choose the `DocScanner` repository. Render reads
   `render.yaml` and proposes a web service `docscanner-api` and a PostgreSQL
   database `docscanner-db`.
3. Fill in the values it asks for:
   - `DOCSCANNER_CORS_ORIGINS`: `["https://manav252.github.io"]`
   - `DOCSCANNER_S3_ENDPOINT`: the R2 S3 endpoint from 2a
   - `DOCSCANNER_S3_ACCESS_KEY` / `DOCSCANNER_S3_SECRET_KEY`: the R2 token keys
4. **Apply**. The first build takes ~5 minutes. Then open
   `https://docscanner-api.onrender.com/health` (your service's URL may differ);
   it should say `{"status":"ok","database":true,"storage":true}`.
   The database tables are created automatically on start (`alembic upgrade head`).

Free Render services sleep after 15 minutes without traffic; the first request
after that takes ~30-60 seconds. Open `/health` a minute before a demo.

### 2c. Point the web app at the backend

1. GitHub → repository **Settings** → **Secrets and variables** → **Actions** →
   **Variables** → **New repository variable**: name `API_URL`, value your Render
   URL (e.g. `https://docscanner-api.onrender.com`).
2. **Actions** → **Deploy website and web app** → **Run workflow** again.

New visitors get that server by default. Anyone can still change it under
Settings → Back up and sync → Server.

## Alternatives

- **Netlify / Vercel** instead of GitHub Pages: build command
  `cd app && flutter build web --release --base-href /app/ && cd .. && python3 tools/pwa_precache.py && mkdir -p public && cp -R website/. public/ && cp -R app/build/web public/app`,
  publish directory `public`. (Both need Flutter in the build image; GitHub Pages
  is simpler because the workflow installs it.)
- **Railway / Fly.io** instead of Render: deploy `backend/Dockerfile` with the
  repository root as build context, add a PostgreSQL database, and set the same
  `DOCSCANNER_*` variables as in `render.yaml`.

## Checklist before a demo

- [ ] Website opens; *How it works* finds the page in the sample photo.
- [ ] *Try it now* opens the app; the demo camera scans a page.
- [ ] On a phone: the real camera works (HTTPS), and the app installs from the browser.
- [ ] (With backend) `/health` is ok; sign up, scan, and the document appears on a second device.
