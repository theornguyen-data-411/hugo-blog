---
title: "Container hóa CakeProject: Giải quyết bài toán MySQL Connect và tối ưu với Docker Compose"
date: 2026-04-05
draft: false
description: "Hướng dẫn chi tiết cách đóng gói ứng dụng Spring Boot (CakeProject), kết nối Database MySQL và chuyển dịch từ lệnh docker run thủ công sang Orchestration chuyên nghiệp bằng Docker Compose."
tags: ["docker", "docker-compose", "spring-boot", "mysql", "devops", "java"]
categories: ["Projects", "Tutorials"]
series: ["DevOps Blog từ Số 0"]
showHero: true
heroStyle: "background"
showTableOfContents: true
---

Trong dự án thực tế tiếp theo mà mình muốn chia sẻ, chúng ta sẽ cùng mổ xẻ **CakeProject** — một ứng dụng Web Java Spring Boot điển hình. Điểm thú vị ở đây không nằm ở code Java, mà là cách chúng ta đưa nó vào container và xử lý "nỗi đau" kinh điển: **Làm sao để App thấy được Database?**

---

## Thử thách: Khi App và DB "lệch pha"

Khi mới bắt đầu Dockerize CakeProject, mình gặp phải 2 vấn đề lớn:
1. **Thứ tự khởi động:** Database phải "nổ máy" xong thì App mới vào kết nối được. Nếu chạy song song mà không có cơ chế chờ, App sẽ crash ngay lập tức.
2. **Networking:** Container App không thể gọi `localhost:3306` để tìm MySQL, vì `localhost` bên trong container chính là... chính nó.

---

## Giải pháp 1: Triển khai thủ công (Docker Run)

Ban đầu, mình thực hiện theo quy trình 4 bước để hiểu rõ bản chất dòng chảy dữ liệu:

### Bước 1: Đóng gói App (Multi-stage Build)
Mình sử dụng kỹ thuật Multi-stage để đảm bảo image cuối cùng chỉ chứa file `.jar` chạy trên JRE, loại bỏ toàn bộ Maven và source code thừa.

```dockerfile
# Giai đoạn Builder
FROM maven:3.9.6-eclipse-temurin-17 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn package -DskipTests

# Giai đoạn Runner
FROM eclipse-temurin:17-jre
COPY --from=builder /app/target/*.jar app.jar
ENTRYPOINT ["java", "-jar", "/app.jar"]
```

### Bước 2: Chạy Database MySQL
```bash
docker run -d --name mysql-db \
  -e MYSQL_ROOT_PASSWORD=your_pass \
  -e MYSQL_DATABASE=cake \
  -p 3306:3306 \
  mysql:8.0
```

### Bước 3: Nạp dữ liệu (Database Migration)
Thay vì cài MySQL Client lên máy, mình tận dụng quyền năng của `docker exec` để bơm thẳng file `script.sql` vào container:
```bash
docker exec -i mysql-db mysql -uroot -pYourPass cake < src/main/resources/script.sql
```

### Bước 4: Kết nối App và DB
Để App thấy DB đang chạy ở máy Host (máy Mac/Windows), mình sử dụng bridge `host.docker.internal`:
```bash
docker run -d --name cake-app -p 8080:8080 \
  -e DB_HOST=host.docker.internal \
  cake-project:v1
```

---

## Giải pháp 2: Tối ưu hoá với Docker Compose (The DevOps Way)

Gõ 4 lệnh trên mỗi lần deploy là một cực hình và rất dễ sai sót. Đây là lúc **Docker Compose** xuất hiện để giải cứu. 

Thay vì gõ lệnh, chúng ta viết một "bản thiết kế" `docker-compose.yml`:

```yaml
version: '3.8'
services:
  db:
    image: mysql:8.0
    container_name: cake-db
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}
      MYSQL_DATABASE: cake
    volumes:
      - cake-data:/var/lib/mysql
    networks:
      - cake-network

  app:
    build: .
    container_name: cake-app
    ports:
      - "8080:8080"
    environment:
      DB_HOST: db # Tìm DB bằng tên service thay vì IP
    depends_on:
      - db
    networks:
      - cake-network

networks:
  cake-network:
    driver: bridge

volumes:
  cake-data:
```

### Tại sao Docker Compose lại "xịn" hơn?
1. **Network Nội bộ:** Bạn không cần dùng `host.docker.internal` nữa. Trong cùng một network, App chỉ cần gọi host là `db` (tên service) là Docker tự điều hướng.
2. **Persistence (Volume):** Data của bạn không bị mất khi xoá container nhờ `volumes`.
3. **Một lệnh duy nhất:** Chỉ cần `docker-compose up -d --build`, toàn bộ hệ thống tự dựng lên hoàn chỉnh.

---

## Bài học rút ra

Qua dự án CakeProject, mình rút ra được 3 quy tắc vàng khi làm DevOps với Container:
- **Nguyên tắc "DB First":** Luôn đảm bảo Database sẵn sàng trước khi khởi chạy App.
- **Tận dụng Environment Variables:** Đừng bao giờ hardcode password hay host vào code. Hãy truyền chúng qua biến môi trường.
- **Dùng tên Service làm Host:** Trong Docker Network, tên service trong Compose chính là DNS. Hãy dùng nó để kết nối thay vì IP cứng.

Bạn có thể áp dụng ngay mô hình này cho bất kỳ dự án Spring Boot + MySQL nào khác. Thật đơn giản và mạnh mẽ! 🚀
