# Security Policy

## Scope

NutriFlow is an educational graduation project and public demonstration. It is
not a medical device and has not undergone a production security or regulatory
assessment.

The bundled invitation-code gate is intended for a small, controlled demo. It
is not a substitute for user authentication, abuse prevention, rate limiting,
or authorization at every API boundary.

## Deployment Checklist

- Keep `.env.prod`, model weights, database backups, SSH keys, and runtime logs
  outside Git.
- Generate independent random values for every password, access code, session
  token, dashboard key, and internal service key.
- Set `NUTRI_AUTH_EXPOSE_DEBUG_CODE=false` before accepting untrusted users and
  connect a real verification provider.
- Restrict SSH by firewall and key-based authentication. Do not expose MySQL,
  Redis, RabbitMQ, MinIO, Chroma, or internal application ports publicly.
- Treat meal images, phone numbers, body measurements, goals, and analysis
  history as sensitive personal data. Define consent, retention, deletion, and
  backup policies before collecting real data.
- Add rate limiting and monitoring at the edge before removing the invitation
  gate.
- Rotate a secret immediately if it is ever committed, even if the commit is
  later deleted.

## Reporting a Vulnerability

Please use GitHub's private vulnerability reporting or open a private security
advisory for this repository. Do not include credentials, personal data, or an
active exploit in a public issue.
