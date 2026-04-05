---
title: "CakeProject Dockerization: Solving MySQL Connectivity and Optimizing with Docker Compose"
date: 2026-04-05
draft: false
description: "A detailed guide on containerizing a Spring Boot application (CakeProject), connecting to a MySQL Database, and transitioning from manual docker run commands to professional orchestration with Docker Compose."
tags: ["docker", "docker-compose", "spring-boot", "mysql", "devops", "java"]
categories: ["Projects", "Tutorials"]
series: ["DevOps Blog from Scratch"]
showHero: true
heroStyle: "background"
showTableOfContents: true
---

In the next real-world project I want to share, we’ll dive into **CakeProject** — a classic Java Spring Boot Web application. The interest here doesn't lie in the Java code itself, but in how we containerize it and solve a classic "pain point": **How does the App see the Database?**

---

## The Challenge: When App and DB are "Out of Sync"

When I first started Dockerizing CakeProject, I encountered two major issues:
1. **Startup Order:** The Database must be "fully running" before the App can connect. If they run in parallel without a waiting mechanism, the App will crash immediately.
2. **Networking:** The App container cannot use `localhost:3306` to find MySQL, because `localhost` inside a container refers to... itself.

---

## Solution 1: Manual Deployment (Docker Run)

Initially, I followed a 4-step process to understand the core data flow:

### Step 1: Package the App (Multi-stage Build)
I used the Multi-stage Build technique to ensure the final image only contains the `.jar` file running on a JRE, excluding all Maven and redundant source code.

```dockerfile
# Builder Stage
FROM maven:3.9.6-eclipse-temurin-17 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn package -DskipTests

# Runner Stage
FROM eclipse-temurin:17-jre
COPY --from=builder /app/target/*.jar app.jar
ENTRYPOINT ["java", "-jar", "/app.jar"]
```

### Step 2: Run the MySQL Database
```bash
docker run -d --name mysql-db \
  -e MYSQL_ROOT_PASSWORD=your_pass \
  -e MYSQL_DATABASE=cake \
  -p 3306:3306 \
  mysql:8.0
```

### Step 3: Data Migration (Script Import)
Instead of installing a MySQL Client on my local machine, I leveraged the power of `docker exec` to pump the `script.sql` file directly into the container:
```bash
docker exec -i mysql-db mysql -uroot -pYourPass cake < src/main/resources/script.sql
```

### Step 4: Connecting App and DB
To let the App see the DB running on the Host machine (Mac/Windows), I used the `host.docker.internal` bridge:
```bash
docker run -d --name cake-app -p 8080:8080 \
  -e DB_HOST=host.docker.internal \
  cake-project:v1
```

---

## Solution 2: Optimizing with Docker Compose (The DevOps Way)

Typing those 4 commands every time you deploy is a nightmare and highly prone to error. This is where **Docker Compose** comes to the rescue.

Instead of typing commands, we write a "blueprint" in `docker-compose.yml`:

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
      DB_HOST: db # Find DB using service name instead of IP
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

### Why is Docker Compose "Better"?
1. **Internal Networking:** You no longer need `host.docker.internal`. In the same network, the App can simply call the host `db` (service name), and Docker handles the DNS.
2. **Persistence (Volumes):** Your data persists even after deleting the container thanks to `volumes`.
3. **One-Command Deployment:** Just run `docker-compose up -d --build`, and the entire system is set up automatically.

---

## Key Takeaways

From the CakeProject project, I've derived three golden rules for Container DevOps:
- **"DB First" Principle:** Always ensure the Database is ready before starting the App.
- **Leverage Environment Variables:** Never hardcode passwords or hosts in your code. Pass them via environment variables.
- **Use Service Names as Hosts:** In a Docker Network, the service name in Compose is the DNS. Use it to connect instead of hardcoded IPs.

You can apply this model to any Spring Boot + MySQL project. It’s simple, robust, and professional! 🚀
