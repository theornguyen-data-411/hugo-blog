---
title: "Xây dựng Blog DevOps với Hugo, Docker và Firebase CI/CD"
date: 2026-04-04
draft: false
description: "Toàn bộ hành trình xây dựng blog kỹ thuật: từ việc chọn Hugo Static Site Generator, containerize bằng Docker Multi-stage với Distroless Image, đến thiết lập pipeline CI/CD tự động deploy lên Firebase Hosting."
tags: ["hugo", "docker", "firebase", "ci-cd", "devops", "nginx"]
categories: ["Projects"]
series: ["DevOps Blog từ Số 0"]
showHero: true
heroStyle: "background"
showTableOfContents: true
showReadingTime: true
showWordCount: true
showSummary: true
---

Đây là bài viết đầu tiên trên blog. Thay vì viết lý thuyết chay, mình quyết định bắt đầu bằng chính việc xây dựng cái blog này — áp dụng luôn các kỹ năng DevOps vào một dự án thực tế có thể nhìn thấy được.

Bài viết này sẽ breakdown toàn bộ quá trình: từ chọn công nghệ, containerize ứng dụng, đến thiết lập một pipeline CI/CD hoàn chỉnh tự động deploy lên Firebase mỗi khi push code.

---

## Tại sao lại là Hugo?

Điều kiện đầu tiên của mình rất đơn giản: *blog phải tốn ít tiền nhất có thể để vận hành*. Các nền tảng như WordPress hay Ghost cần một server chạy liên tục, tốn phí server hàng tháng. Hugo giải quyết vấn đề đó hoàn toàn.

**Hugo** là một Static Site Generator (SSG): thay vì render HTML từ database mỗi khi có request, Hugo compile toàn bộ nội dung thành file HTML tĩnh một lần duy nhất. File HTML đó sau đó được serve trực tiếp — không cần server, không cần database, không cần runtime.

Kết quả là blog có thể host **hoàn toàn miễn phí** trên Firebase Hosting mà vẫn load siêu nhanh nhờ CDN toàn cầu của Google.

Theme được chọn là [**Blowfish**](https://blowfish.page) — một trong những theme Hugo hiện đại nhất hiện tại, hỗ trợ dark mode, đa ngôn ngữ, và rất nhiều tùy biến.

---

## Kiến trúc tổng thể

Trước khi đi vào chi tiết, hãy nhìn vào bức tranh tổng thể của hệ thống:

```
Local Machine
  └── hugo server -D          → Preview tại localhost:1313
  └── docker-compose up       → Test Production tại localhost:8080

git push → GitHub Repository
  └── GitHub Actions trigger
        ├── [1] Checkout code + Blowfish submodule
        ├── [2] docker build  → Validate Dockerfile (Infra check)
        ├── [3] docker run    → Build Hugo → sinh ra thư mục public/
        └── [4] Firebase CLI  → Deploy public/ lên CDN
              └── 🌐 theor-devops.web.app
```

---

## Containerize với Docker Multi-stage Build

Đây là phần kỹ thuật thú vị nhất của project. Mục tiêu là tạo ra một Docker Image Production siêu nhẹ và siêu bảo mật.

### Vấn đề với cách build thông thường

Nếu chỉ dùng 1 stage Dockerfile, image cuối sẽ chứa toàn bộ Hugo compiler (bao gồm Go runtime, tools...) cùng với file HTML đầu ra. Đây là dữ liệu thừa, vô dụng khi chạy Production, chỉ làm phình to image và tăng diện tích bề mặt tấn công.

### Multi-stage Build

Giải pháp là chia Dockerfile thành 2 stage riêng biệt:

```dockerfile
# ========================================
# Build Stage — chỉ tồn tại trong quá trình build
# ========================================
FROM hugomods/hugo:exts AS builder

WORKDIR /src
COPY . .

# --minify: nén HTML/CSS/JS, giảm 30-50% kích thước
# --gc: dọn sạch cache cũ trước khi build
RUN hugo --minify --gc

# ========================================
# Production Stage — image cuối cùng
# ========================================
FROM cgr.dev/chainguard/nginx:latest

# Chỉ copy folder public/ từ stage trước, Hugo compiler bị bỏ lại
COPY --from=builder /src/public /usr/share/nginx/html

EXPOSE 8080
```

**Stage 1 (Builder):** Dùng `hugomods/hugo:exts` để compile source code Hugo ra file HTML tĩnh. Stage này sẽ **không xuất hiện** trong image cuối.

**Stage 2 (Runtime):** Chỉ lấy Nginx và folder `public/` vừa được compile. Image cuối cùng chỉ nặng ~20MB.

### Distroless Image — Bảo mật tối đa

Thay vì `nginx:alpine` thông thường, mình dùng `cgr.dev/chainguard/nginx` — một **Distroless Image**.

Image Alpine thông thường vẫn chứa shell (`sh`), package manager (`apk`) và các binary Linux. Kẻ tấn công khi xâm nhập được container có thể dùng những thứ này để leo thang đặc quyền.

Distroless loại bỏ **toàn bộ** những thứ đó:
- Không shell, không package manager
- Zero CVEs (lỗ hổng bảo mật đã được biết đến)
- Chạy dưới quyền non-root (port 8080 thay vì 80)

### `.dockerignore` — Tăng tốc độ build

Khi chạy `docker build`, Docker gửi toàn bộ thư mục lên Docker Daemon. Nếu không lọc, sẽ gửi cả thư mục `public/` (hàng chục MB HTML) và `.git/` (lịch sử commit). `.dockerignore` ngăn điều đó:

```
.git
public/
resources/_gen/
.hugo_build.lock
```

---

## CI/CD Pipeline với GitHub Actions

Đây là phần mang lại giá trị DevOps thực sự: **không bao giờ phải deploy bằng tay nữa**.

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
          submodules: true  # Kéo theme Blowfish về
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

Pipeline gồm 4 bước tuần tự:

1. **Checkout** — Kéo toàn bộ source code về, bao gồm cả theme Blowfish (git submodule).
2. **Validate Docker** — Build Dockerfile từ đầu đến cuối để kiểm tra hạ tầng container còn hoạt động không. Bước này cũng in ra kích thước image để monitoring.
3. **Build Hugo** — Dùng `docker run` với image Hugo để compile source code ra thư mục `public/` trên filesystem của GitHub Actions runner.
4. **Deploy Firebase** — Firebase Action lấy thư mục `public/` và đẩy lên CDN.

### Secrets Management

Pipeline cần xác thực với Firebase. Thay vì hardcode credentials vào code (cực kỳ nguy hiểm), mình dùng **GitHub Secrets**:

- Tạo Service Account JSON key từ Firebase Console
- Paste nội dung JSON vào GitHub → Settings → Secrets với tên `FIREBASE_SERVICE_ACCOUNT`
- Pipeline đọc secret bằng cú pháp `${{ secrets.FIREBASE_SERVICE_ACCOUNT }}`

File JSON key sau khi đã paste vào Secrets thì xóa đi. Không bao giờ commit file này lên Git.

---

## Thành quả

Sau tất cả, kết quả cuối cùng:

| Hạng mục | Kết quả |
|:---|:---|
| **Blog live tại** | `theor-devops.web.app` |
| **Docker Image size** | ~20MB (Production) |
| **Build time** | ~35 giây (CI/CD pipeline) |
| **Chi phí hosting** | $0 (Firebase Free Tier) |
| **Thời gian deploy** | Tự động sau mỗi `git push` |
| **Bảo mật** | Distroless, non-root, zero CVEs |

---

## Bước tiếp theo

Đây mới là nền tảng. Các kế hoạch tiếp theo bao gồm:

- **Custom Domain** — Gắn domain thật thay vì `*.web.app`
- **Terraform** — Codify toàn bộ hạ tầng Firebase bằng IaC
- **Monitoring** — Theo dõi hiệu năng và uptime
- **Kubernetes** — Migrate sang K8s khi cần scale

Series này sẽ tiếp tục document toàn bộ hành trình đó. Stay tuned. 🚀
