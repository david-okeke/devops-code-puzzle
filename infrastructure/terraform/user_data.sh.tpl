#!/bin/bash
set -euo pipefail

# --- 1. Install Docker + Compose plugin (pinned version) --------------------
dnf install -y docker
systemctl enable --now docker
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
# buildx is required by "docker compose build"
curl -SL https://github.com/docker/buildx/releases/download/v0.17.1/buildx-v0.17.1.linux-amd64 \
  -o /usr/local/lib/docker/cli-plugins/docker-buildx
chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

# --- 2. Write the application source (embedded, no registry needed) --------
mkdir -p /opt/app
echo "${app_py_b64}" | base64 -d > /opt/app/app.py
echo "${requirements_b64}" | base64 -d > /opt/app/requirements.txt
echo "${dockerfile_b64}" | base64 -d > /opt/app/Dockerfile

# --- 3. Fetch the DB password from SSM Parameter Store at boot time --------
# The password is NEVER embedded in this script, in User Data, or in
# Terraform state as plaintext output. It is fetched at runtime over the
# API using the instance's IAM role, which can read only this one parameter.
DB_PASSWORD=$(aws ssm get-parameter \
  --name "${secret_arn}" \
  --with-decryption \
  --region "${aws_region}" \
  --query Parameter.Value --output text)

cat > /opt/app/.env <<ENVEOF
DATABASE_URL=postgresql://${db_username}:$DB_PASSWORD@${db_host}:${db_port}/${db_name}
APP_ENV=${environment}
CLOUD_PROVIDER=AWS
ENVEOF
unset DB_PASSWORD

# --- 4. Caddy config: real TLS if a domain was given, else self-signed on the public IP
if [ -n "${domain_name}" ]; then
  cat > /opt/app/Caddyfile <<CADDYEOF
${domain_name} {
    reverse_proxy app:8080
}
CADDYEOF
else
  TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
  PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
    http://169.254.169.254/latest/meta-data/public-ipv4)
  cat > /opt/app/Caddyfile <<CADDYEOF
{
    default_sni $PUBLIC_IP
}

$PUBLIC_IP {
    tls internal
    reverse_proxy app:8080
}

:80 {
    redir https://{host}{uri} permanent
}
CADDYEOF
fi

# --- 5. Compose file: app container + Caddy container ----------------------
cat > /opt/app/docker-compose.yml <<COMPOSEEOF
services:
  app:
    build: /opt/app
    restart: unless-stopped
    env_file: /opt/app/.env
    expose:
      - "8080"
  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/app/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
volumes:
  caddy_data:
COMPOSEEOF

cd /opt/app
docker compose up -d --build

# --- 6. Basic health-check metric, pushed to CloudWatch every minute -------
cat > /opt/app/health_check.sh <<'HEALTHEOF'
#!/bin/bash
if curl -sf -o /dev/null http://localhost:8080/health; then VALUE=1; else VALUE=0; fi
aws cloudwatch put-metric-data \
  --region "${aws_region}" \
  --namespace "${metric_namespace}" \
  --metric-name HealthCheckStatus \
  --value "$VALUE" \
  --unit None
HEALTHEOF
chmod +x /opt/app/health_check.sh
echo "* * * * * root /opt/app/health_check.sh" > /etc/cron.d/app-health-check