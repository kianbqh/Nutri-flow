# Protected Public Deployment

This guide deploys Nutri-flow as a protected staging environment on one Ubuntu
server. Caddy serves the Vue application, terminates HTTPS, and protects the
site with HTTP Basic Authentication. All databases and internal services stay
on the private Docker network.

This profile is intended for invited testing. It is not a substitute for
application-level JWT authentication.

## 1. Server and DNS

Recommended starting point:

- Ubuntu 24.04 x86_64
- 4 vCPU
- 16 GB RAM
- 100 GB SSD
- A domain such as `nutri.example.com`

Point the domain's `A` record to the server public IP. Allow inbound TCP ports
22, 80, and 443, plus UDP 443 for HTTP/3. Do not expose database or middleware
ports.

## 2. Install Docker

Follow Docker's official Ubuntu installation guide, including the Compose
plugin. Verify the installation:

```bash
sudo systemctl enable --now docker
sudo docker run --rm hello-world
sudo docker compose version
```

Optionally add the current user to the Docker group, then sign out and back in:

```bash
sudo usermod -aG docker "$USER"
```

## 3. Clone the repository

```bash
sudo mkdir -p /opt/nutri-flow
sudo chown "$USER":"$USER" /opt/nutri-flow
git clone https://github.com/KianBao/Nutri-flow.git /opt/nutri-flow
cd /opt/nutri-flow
```

## 4. Create production secrets

Copy the template:

```bash
cp .env.prod.example .env.prod
chmod 600 .env.prod
```

Generate independent URL-safe passwords:

```bash
openssl rand -hex 24
openssl rand -hex 24
openssl rand -hex 24
openssl rand -hex 24
openssl rand -hex 24
```

Generate the Caddy Basic Auth password hash:

```bash
docker run --rm caddy:2-alpine \
  caddy hash-password --plaintext 'CHOOSE_A_LONG_TEST_PASSWORD'
```

Edit `.env.prod`. Put the bcrypt hash in single quotes because it contains
dollar signs:

```dotenv
NUTRI_BASIC_AUTH_HASH='$2a$14$...'
```

Set the real domain, ACME email, generated passwords, and optional LLM API key.
Keep `NUTRI_AUTH_EXPOSE_DEBUG_CODE=true` only while the Basic Auth gate is
enabled and the project has no real SMS provider.

## 5. Upload the model checkpoint

The checkpoint is deliberately not stored in Git. From the local machine:

```bash
scp best_stage7s1_tiny_img512_mask135_cls095_phaseA_12ep.pth \
  ubuntu@SERVER_IP:/opt/nutri-flow/models/stage7s1.pth
```

On the server:

```bash
cd /opt/nutri-flow
test -s models/stage7s1.pth
chmod 444 models/stage7s1.pth
```

The inference container fails fast when the required checkpoint is missing or
cannot be loaded.

## 6. Validate and start

```bash
docker compose --env-file .env.prod -f compose.prod.yml config --quiet
docker compose --env-file .env.prod -f compose.prod.yml pull
docker compose --env-file .env.prod -f compose.prod.yml build
docker compose --env-file .env.prod -f compose.prod.yml up -d
docker compose --env-file .env.prod -f compose.prod.yml ps
```

The first inference build downloads the CPU PyTorch runtime and can take several
minutes. Caddy obtains the TLS certificate automatically after DNS and ports 80
and 443 are reachable.

## 7. Verify

```bash
curl -u 'nutri-tester:YOUR_TEST_PASSWORD' \
  https://nutri.example.com/api/actuator/health

docker compose --env-file .env.prod -f compose.prod.yml logs \
  --tail=200 business agent inference gateway
```

Open `https://nutri.example.com` in a browser, enter the Basic Auth credentials,
log in with the protected staging OTP, upload a smoke image, and verify that the
task reaches `COMPLETED`.

## 8. Update and roll back

Before updating, record the current commit:

```bash
git rev-parse HEAD
git pull --ff-only
docker compose --env-file .env.prod -f compose.prod.yml up -d --build
```

To roll back:

```bash
git switch --detach PREVIOUS_COMMIT_SHA
docker compose --env-file .env.prod -f compose.prod.yml up -d --build
```

## 9. Back up persistent data

Create a MySQL dump:

```bash
mkdir -p backups
docker compose --env-file .env.prod -f compose.prod.yml exec -T mysql \
  sh -c 'exec mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction "$MYSQL_DATABASE"' \
  > "backups/nutri-$(date +%F-%H%M).sql"
```

Also back up the Docker volumes for MySQL, MinIO, RabbitMQ, and Chroma before
major upgrades. Do not use `docker compose down -v` unless permanent data
deletion is intended.

## 10. Before removing the staging gate

Complete all of the following before removing Caddy Basic Auth:

- Replace header-based identity with signed JWT access and refresh tokens.
- Connect a real SMS or email verification provider and disable debug OTPs.
- Add API rate limits, abuse controls, and account deletion.
- Publish privacy and data-retention policies.
- Pin and test database, object-store, and Chroma image versions.
- Add monitoring, off-server backups, and alerting.

The iOS app should target the same HTTPS API, but external TestFlight testing
should wait until application-level authentication replaces the staging gate.
