---
title: "Building a DevOps Blog with Hugo, Docker, and Firebase CI/CD"
date: 2026-04-04
draft: false
description: "The complete journey of building a technical blog: from choosing Hugo SSG, containerizing with Docker Multi-stage and Distroless Images, to setting up a fully automated CI/CD pipeline to Firebase Hosting."
tags: ["hugo", "docker", "firebase", "ci-cd", "devops", "nginx"]
categories: ["Projects"]
series: ["DevOps Blog from Scratch"]
showHero: true
heroStyle: "background"
showTableOfContents: true
showReadingTime: true
showWordCount: true
---

This is the very first post on this blog. Instead of writing theoretical articles, I decided to start by building the blog itself—applying DevOps skills to a real, visible project.

This post will breakdown the entire process: from choosing the technology stack, containerizing the application, to setting up a complete CI/CD pipeline that automatically deploys to Firebase every time I push code.

---

## Why Hugo?

My first requirement was simple: *the blog must be as cheap as possible to operate*. Platforms like WordPress or Ghost need a server running constantly, incurring monthly fees. Hugo solves this problem completely.

**Hugo** is a Static Site Generator (SSG): instead of rendering HTML from a database on every request, Hugo compiles all content into static HTML files once. These static files are then served directly—no server, no database, no runtime required.

The result is a blog that can be hosted **completely for free** on Firebase Hosting while still loading incredibly fast thanks to Google's global CDN.

The chosen theme is [**Blowfish**](https://blowfish.page)—one of the most modern Hugo themes available today, supporting dark mode, multi-language, and extensive customization.

---

## Overall Architecture

Before diving into the details, let's look at the big picture of the system:

```
Local Machine
  └── hugo server -D          → Preview at localhost:1313
  └── docker-compose up       → Test Production at localhost:8080

git push → GitHub Repository
  └── GitHub Actions trigger
        ├── [1] Checkout code + Blowfish submodule
        ├── [2] docker build  → Validate Dockerfile (Infra check)
        ├── [3] docker run    → Build Hugo → generate public/ folder
        └── [4] Firebase CLI  → Deploy public/ to CDN
              └── 🌐 theor-devops.web.app
```

---

## Containerization with Docker Multi-stage Build

This is the most interesting technical part of the project. The goal is to create a lightweight and highly secure Production Docker Image.

### The Problem with Standard Builds

If you use a single-stage Dockerfile, the final image will contain the entire Hugo compiler (including Go runtime, tools...) along with the output HTML files. This is redundant data, useless for Production, and only bloats the image while increasing the attack surface.

### Multi-stage Build

The solution is to split the Dockerfile into two separate stages:

```dockerfile
# ========================================
# Build Stage — only exists during build
# ========================================
FROM hugomods/hugo:exts AS builder

WORKDIR /src
COPY . .

# --minify: compresses HTML/CSS/JS, reduces size by 30-50%
# --gc: cleans up old cache before building
RUN hugo --minify --gc

# ========================================
# Production Stage — the final image
# ========================================
FROM cgr.dev/chainguard/nginx:latest

# Only copy public/ folder from previous stage, Hugo compiler is left behind
COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 8080
```

**Stage 1 (Builder):** Uses `hugomods/hugo:exts` to compile Hugo source code into static HTML files. This stage **will not appear** in the final image.

**Stage 2 (Runtime):** Only takes Nginx and the newly compiled `public/` folder. The final image weighs only ~20MB.

### Distroless Image — Maximum Security

Instead of standard `nginx:alpine`, I use `cgr.dev/chainguard/nginx`—a **Distroless Image**.

Standard Alpine images still contain a shell (`sh`), package manager (`apk`), and basic Linux binaries. An attacker could use these to escalate privileges if they compromise the container.

Distroless removes **all** of that:
- No shell, no package manager
- Zero CVEs (Known vulnerabilities)
- Runs as non-root (port 8080 instead of 80)

### `.dockerignore` — Optimizing Build Speed

When running `docker build`, Docker sends the entire directory to the Docker Daemon. Without filtering, it sends the `public/` folder (tens of MBs of HTML) and `.git/` (commit history). `.dockerignore` prevents this:

```
.git
public/
resources/_gen/
.hugo_build.lock
```

---

## CI/CD Pipeline with GitHub Actions

This is where the real DevOps value lies: **never having to deploy manually again**.

```yaml
name: Build and Deploy to Firebase Hosting
on:
  push:
    branches: [main]

jobs:
  build_and_deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4
        with:
          submodules: true  # Pulls the Blowfish theme
          fetch-depth: 0

      - name: Validate Production Docker Image
        run: |
          docker build -t hugo-blog-prod:ci .
          docker images hugo-blog-prod:ci --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

      - name: Build Hugo Static Files
        run: |
          docker run --rm \
            -v ${{ github.workspace }}:/src \
            hugomods/hugo:exts \
            hugo --minify --gc

      - name: Deploy to Firebase Hosting
        uses: FirebaseExtended/action-hosting-deploy@v0
        with:
          repoToken: ${{ secrets.GITHUB_TOKEN }}
          firebaseServiceAccount: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
          channelId: live
          projectId: theor-devops
```

The pipeline consists of 4 sequential steps:

1. **Checkout** — Pulls all source code, including the Blowfish theme (git submodule).
2. **Validate Docker** — Builds the Dockerfile from scratch to ensure the container infrastructure is still working. This step also prints the image size for monitoring.
3. **Build Hugo** — Uses `docker run` with the Hugo image to compile source code into the `public/` directory on the GitHub Actions runner filesystem.
4. **Deploy Firebase** — The Firebase Action takes the `public/` directory and pushes it to the CDN.

### Secrets Management

The pipeline needs to authenticate with Firebase. Instead of hardcoding credentials into the code (extremely dangerous), I used **GitHub Secrets**:

- Created a Service Account JSON key from the Firebase Console
- Pasted the JSON content into GitHub → Settings → Secrets as `FIREBASE_SERVICE_ACCOUNT`
- The pipeline reads the secret using `${{ secrets.FIREBASE_SERVICE_ACCOUNT }}`

The JSON key file is deleted after being pasted into Secrets. Never commit this file to Git.

---

## Results

After everything, the final results:

| Category | Result |
|:---|:---|
| **Live site at** | `theor-devops.web.app` |
| **Docker Image size** | ~20MB (Production) |
| **Build time** | ~35 seconds (CI/CD pipeline) |
| **Hosting cost** | $0 (Firebase Free Tier) |
| **Deployment** | Automatic after every `git push` |
| **Security** | Distroless, non-root, zero CVEs |

---

## Next Steps

This is just the foundation. Future plans include:

- **Custom Domain** — Linking a real domain instead of `*.web.app`
- **Terraform** — Codifying the entire Firebase infrastructure with IaC
- **Monitoring** — Tracking performance and uptime
- **Kubernetes** — Migrating to K8s when scaling is needed

This series will continue to document that entire journey. Stay tuned. 🚀
