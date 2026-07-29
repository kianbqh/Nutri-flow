# Protected Public Deployment

This guide deploys Nutri-flow as a protected staging environment on one Ubuntu
server. Caddy serves the Vue application, terminates HTTPS, and protects the
site with a single invitation code backed by a secure browser session cookie.
All databases and internal services stay on the private Docker network.

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

Choose a long invitation code and generate an independent session secret:

```bash
openssl rand -hex 32
```

Edit `.env.prod`:

```dotenv
NUTRI_ACCESS_CODE=CHOOSE_A_LONG_INVITATION_CODE
NUTRI_ACCESS_SESSION=PASTE_THE_RANDOM_HEX_VALUE
```

Set `NUTRI_SITE_ADDRESS` to the real domain, set
`NUTRI_CORS_ALLOWED_ORIGINS` to its `https://` origin, then configure the ACME
email, generated passwords, and optional LLM API key. Keep
`NUTRI_AUTH_EXPOSE_DEBUG_CODE=true` only while the invitation-code gate is enabled
and the project has no real SMS provider.

For a temporary IP-only HTTP deployment before DNS is ready, use:

```dotenv
NUTRI_SITE_ADDRESS=http://SERVER_IP
NUTRI_CORS_ALLOWED_ORIGINS=http://SERVER_IP
```

Switch both values to the HTTPS domain as soon as DNS is available.

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
curl -H 'X-Nutri-Access-Code: YOUR_INVITATION_CODE' \
  https://nutri.example.com/api/actuator/health

docker compose --env-file .env.prod -f compose.prod.yml logs \
  --tail=200 business agent inference gateway
```

Open `https://nutri.example.com` in a browser, enter the invitation code,
log in with the protected staging OTP, upload a smoke image, and verify that the
task reaches `COMPLETED`.

For a temporary Flutter iOS or Android test build, pass the same staging code
at build time:

```bash
flutter build ios --release \
  --dart-define=NUTRI_API_BASE=https://nutri.example.com/api/v1 \
  --dart-define=NUTRI_DEMO_ACCESS_CODE=YOUR_INVITATION_CODE
```

The compiled staging code is not suitable for a public App Store release.
Replace the scaffold user ID flow with real token-based authentication before
removing the outer gate or distributing a public build.

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

Complete all of the following before removing the Caddy invitation-code gate:

- Replace header-based identity with signed JWT access and refresh tokens.
- Connect a real SMS or email verification provider and disable debug OTPs.
- Add API rate limits, abuse controls, and account deletion.
- Publish privacy and data-retention policies.
- Pin and test database, object-store, and Chroma image versions.
- Add monitoring, off-server backups, and alerting.

Internal TestFlight builds may use the temporary compiled staging code.
External TestFlight testing and App Store distribution should wait until
application-level authentication replaces the staging gate.
