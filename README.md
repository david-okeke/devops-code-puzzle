# DevOps Code Puzzle — Terraform on AWS (Mid-Level)

A Flask app on EC2, talking to a PostgreSQL RDS database, served over HTTPS by
Caddy, deployed with Terraform, with CloudWatch monitoring, two environments,
least-privilege IAM, and no hardcoded secrets. CI/CD runs on GitHub Actions
using OIDC (no stored AWS keys).

## Architecture

Internet ──80/443 --> [EC2 + Elastic IP]
├─ Caddy container (self-signed TLS termination)
└─ Flask app container -- 5432 --> [RDS Postgres]
(private, no public IP)
IAM role on EC2 --> SSM Parameter Store (DB password, fetched at boot) -->
EC2 + custom metric -->  CloudWatch (health check + status check alarms) ──> SNS (email)
GitHub Actions -- OIDC --> IAM role (no stored AWS keys) --> Terraform plan/apply

## Live deployment (evaluation record)

Both environments were deployed live, verified working, screenshotted, and
torn down to avoid ongoing charges. See /devops-code-puzzle/images

DEV & PROD SCREENSHOTS INCLUDED
| Homepage - Public HTTPS access, env vars, DB write/read via visit counter
| Homepage health check - endpoint, monitoring
| Cloudwatch - CloudWatch alarms configured, monitoring
| Github Actions - I/CD pipeline: validate + plan passing
| SSM parameter - Secret stored in SSM Parameter Store, masked
| EC2 security groups - controls inbound and outbound network traffic for your container tasks or underlying EC2 instances
| IAM - least privilege - only the minimum permissions necessary to complete their specific tasks
| Terminal Output - created - 23 resources created
| Terminal Output - destroyed - 23 resources destroyed
| 2 environments support - dev vs prod vars configuration difference

## Prerequisites

- Terraform >= 1.9 (native build for your CPU architecture — see note below)
- AWS CLI v2, configured with credentials that can create VPC/EC2/RDS/IAM/SSM/CloudWatch resources
- An AWS account (free tier eligible resources are used by default)
- Session Manager plugin for the AWS CLI, if you want shell access to the instance without SSH

**Apple Silicon Mac note** make sure Terraform is the `darwin_arm64` build,
not `darwin_amd64`. Running the Intel build under Rosetta caused repeated
provider-plugin timeouts and pegged CPU during this project's own setup.
Check with `terraform version`.

## Deploy

1. Clone this repository.
2. Review `infrastructure/terraform/environments/dev.tfvars` and `prod.tfvars`.
   Leave `domain_name` blank to use a self-signed certificate (the app finds
   the instance's own public IP at boot and issues a cert for it). Set
   `sns_alarm_email` if you want alarm emails.
3. Deploy dev:
    chmod +x infrastructure/scripts/*.sh
    ./infrastructure/scripts/deploy.sh dev
    This runs `terraform plan`, shows the plan, and asks for confirmation
   before `apply`.
4. Deploy prod the same way:
    ./infrastructure/scripts/deploy.sh prod

Each `plan` step's output feeds directly into the matching `apply` — Terraform
applies exactly what was reviewed in the saved plan file.

## Verify

- Visit the URL in the Terraform output `app_url`. Your browser will show a
  certificate warning — this is expected, since there's no real domain and
  the cert is self-signed. Click through it ("Advanced" --> "Proceed").
  You should see environment, timestamp, cloud provider, and a database
  write counter that increments on refresh.
- Check `<app_url>/health` — returns `200 {"status":"ok","database":"reachable"}`.
- Connect to the instance without SSH:
    aws ssm start-session --target <instance-id> --region us-east-1
  (get `<instance-id>` from `terraform output` or the EC2 console)
- CloudWatch alarms: `<project>-<env>-ec2-status-check-failed` and
  `<project>-<env>-app-health-failed`.

## Teardown
./infrastructure/scripts/destroy.sh dev
./infrastructure/scripts/destroy.sh prod
Each asks you to type the environment name to confirm before destroying.

## Verify nothing is left running:
aws ec2 describe-instances --query "Reservations[].Instances[].State.Name"
aws rds describe-db-instances --query "DBInstances[].DBInstanceStatus"
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=devops-code-puzzle" --query "Vpcs[].VpcId"

All three should return empty.

## Estimated cost

Using the default `t3.micro` / `db.t3.micro` sizes on a free-tier-eligible
AWS account, this stays within the 12-month free tier (750 hrs/month EC2 +
750 hrs/month RDS + 20GB storage). SSM Parameter Store `SecureString` and the
first 10 CloudWatch alarms are free indefinitely, not just for 12 months.

Both environments were destroyed immediately after evaluation screenshots
were taken.

## CI/CD pipeline

GitHub Actions (`.github/workflows/deploy.yml`), authenticated via OIDC —
no long-lived AWS access keys are stored in GitHub.

Pipeline stages, mapped directly to the mid-level requirement
("pipeline should validate, test, and deploy" with "deployment gates or
manual approval"):

## Stages & Jobs
| Validate | `validate` — `terraform fmt -check` + `terraform validate`, runs on every push |
| Test | `smoke-test-dev` / `smoke-test-prod` — after a deploy, calls `/health` on the live app and fails the pipeline if it doesn't return `200 {"status":"ok"}`. This catches broken deployments that `plan`/`apply` alone cannot, since Terraform succeeding only means the resources were created, not that the application inside them works. |
| Deploy | `apply-dev` / `apply-prod` — `terraform apply -auto-approve` |
| Deployment gate / manual approval | `apply-prod` runs under the GitHub `production` environment, which requires a human reviewer to approve before it executes |

**Why `apply-dev`/`apply-prod` are gated behind a manual `workflow_dispatch`
trigger instead of running on every push to `main`:** Terraform state for
this project is local (on the machine that ran `apply`), not in a shared
remote backend. A pipeline run starts on a brand-new, disposable GitHub
runner with no state file, so it has no way to know the 23 resources this
project creates already exist. An automatic `apply` on every push would
therefore try to recreate everything and fail on AWS-enforced unique names
(IAM role, RDS identifier, SSM parameter path) — which is exactly what
happened during this project's own development, requiring manual cleanup of
duplicate VPCs left behind by a failed automatic run. Gating behind a manual
trigger avoids that failure mode. **The correct production fix is a remote
state backend (S3 bucket + DynamoDB lock table)**, so the pipeline and any
engineer share one source of truth for state; this is the documented next
step in this project rather than something implemented here, given time
constraints.

**OIDC trust policy detail:** the GitHub OIDC token's `sub` claim for this
account/repo combination is not the commonly-documented
`repo:owner/repo:*` format — it includes numeric IDs
(`repo:owner@ACCOUNT_ID/repo@REPO_ID:*`). The trust policy in
`infrastructure/bootstrap/trust-policy.json` reflects the actual format this
repository's tokens use, found by temporarily logging the token's decoded
claims during setup. This is stricter than the name-based form, since a
repo deleted and recreated with the same name gets a new ID and would no
longer match.

## Deployment automation
make plan ENV=dev # init, fmt, validate, plan — saves a plan file
make apply ENV=dev # applies exactly the saved plan
make destroy ENV=dev
make output ENV=dev

`infrastructure/scripts/deploy.sh` and `destroy.sh` wrap these with
confirmation prompts and pre-flight checks (Terraform/AWS CLI installed,
credentials configured).

## One-time CI/CD setup (not run by the pipeline itself)

The OIDC provider, IAM role, and permissions policy that let GitHub Actions
authenticate to AWS are one-time account setup, not something Terraform
manages (a pipeline should not have permission to modify its own trust
relationship). The policy documents are committed for reproducibility:

- `infrastructure/bootstrap/trust-policy.json` — who can assume the deploy role
- `infrastructure/bootstrap/deploy-policy.json` — what the deploy role can do

Setup, once per AWS account:
```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com

aws iam create-role --role-name github-deploy-role \
  --assume-role-policy-document file://infrastructure/bootstrap/trust-policy.json

aws iam create-policy --policy-name github-deploy-policy \
  --policy-document file://infrastructure/bootstrap/deploy-policy.json

aws iam attach-role-policy --role-name github-deploy-role \
  --policy-arn arn:aws:iam::<account-id>:policy/github-deploy-policy
```
Then add the role's ARN as the GitHub repo secret `AWS_DEPLOY_ROLE_ARN`, and
create `development` and `production` environments under repo Settings,
with a required reviewer on `production`.

## Assumptions & design decisions

- **Database: PostgreSQL on RDS, not the provided SQLite sample.** 
  The challenge explicitly allows either. RDS was chosen because the mid-level
  "secure secret management" requirement needs an actual secret to
  demonstrate — SQLite has no password to manage.
- **Secret management** SSM Parameter Store (`SecureString`), not Secrets
  Manager. The challenge lists Secrets Manager, HashiCorp Vault, or
  environment variables as acceptable. Plain environment variables were
  tried first, but that approach places the password in the EC2 instance's
  User Data field and Terraform state in plaintext, readable by anyone in
  the account with `ec2:DescribeInstanceAttribute`. Parameter Store avoids
  that — the password is generated by Terraform, stored encrypted, and
  fetched by the instance over the API at boot using a narrowly-scoped IAM
  permission (read access to exactly one parameter path). It is free
  indefinitely (Secrets Manager charges ~$0.40/month/secret with no free
  tier), which closes the security gap of plain env vars at no extra cost.
- **No SSH port anywhere.** Admin access is via AWS Systems Manager Session
  Manager instead, which needs no open inbound port and no bastion host —
  a stricter interpretation of "only necessary ports open" than the more
  common "restrict SSH to your IP."
- **No NAT Gateway.** Not free-tier. RDS sits in a public subnet but has no
  public IP and its security group only accepts traffic from the web
  server's security group — isolation is enforced by security groups, not
  subnet placement.
- **TLS is self-signed, not Let's Encrypt.** Let's Encrypt requires a real
  domain name pointed at the server; this deployment uses only an Elastic
  IP. Caddy is configured to issue an internal self-signed certificate for
  whatever public IP the instance has at boot, with `default_sni` set
  explicitly — clients connecting to a bare IP address don't send a TLS
  Server Name Indication, so without `default_sni` Caddy has no certificate
  to offer and the handshake fails. If a real domain were available, the
  Caddyfile would use it directly and Caddy would issue a trusted
  Let's Encrypt certificate automatically, no code changes needed.
- **Docker Compose and buildx versions are pinned explicitly**, rather than
  using whatever Amazon Linux 2023's default package repos provide.
  The default install initially resolved a Compose version whose `build`
  command required a newer `buildx` than what shipped alongside it,
  causing `docker compose up --build` to fail silently mid-deployment
  with no application ever starting.
- **The `visits` table is created inside the request path**, not only at
  container startup. The original code created it in a `if __name__ ==
  "__main__"` block, which gunicorn (the production WSGI server) never
  executes, since gunicorn imports the Flask app object directly rather
  than running the script as `__main__`. This caused every request to fail
  with a 500 error until fixed.
- **RDS `skip_final_snapshot = true`, `deletion_protection = false`.**
  Trades production safety for a clean, fast teardown appropriate for a
  time-boxed evaluation; a real production system would set both the
  other way.
- **CI/CD apply is gated behind manual trigger, not automatic on push.**
  Covered in detail in the CI/CD section above — the short version is that
  Terraform state is local, not shared, so an automatic pipeline apply
  would try to recreate existing resources and fail. This was discovered
  the hard way: an early automatic apply run failed partway through and
  left duplicate VPC resources behind, which had to be identified and
  manually cleaned up.
- **CloudWatch Logs agent was intentionally left out** to keep the boot
  script reliable within scope; logs are available via SSM +
  `docker compose logs`. A scope trade-off, not an oversight.
- **Terraform provider plugin binary architecture matters** -- On Apple
  Silicon** Running the Intel (`darwin_amd64`) build of Terraform under
  Rosetta caused the AWS provider plugin to peg over 100% CPU and
  repeatedly hit "timeout while waiting for plugin to start" errors,
  which looked like a code or network problem but was actually a toolchain
  mismatch, resolved by installing the native `darwin_arm64` build.

## Mid-level requirements — how each is met

## Requirements & Implementation
| SSL/TLS - Caddy, automatic self-signed cert on the instance's public IP (see assumptions above for the domain-name alternative) |
| Basic monitoring/health checks - `/health` endpoint; CloudWatch alarms on EC2 status check and a custom app-health metric pushed every minute via cron; SNS email subscription 
| Environment-specific variables - `environments/dev.tfvars` and `prod.tfvars`, differing in backup retention and (optionally) domain/alerting |
| Config separated from code - All environment values live in `.tfvars` files and are injected into the instance via `user_data`, never hardcoded in `.tf` files or the application
| Least privilege IAM/roles - The EC2 instance role can only read its one SSM parameter and publish to its one CloudWatch namespace; the CI/CD deploy role's policy is scoped to this project's resource-name prefix rather than using an AWS-managed broad policy |
| No hardcoded secrets - Database password is generated by Terraform (`random_password`), never appears in code, git, or plaintext state output |
| Secure secret management - SSM Parameter Store `SecureString`, fetched by the instance over the API at boot using its IAM role |
| CI/CD pipeline - GitHub Actions, OIDC authentication (no stored AWS keys) |
| Pipeline validates, tests, deploys - See CI/CD table above — validate (`fmt`/`validate`), test (post-deploy smoke test against `/health`), deploy (`apply`) |
| Deployment gate - manual approval | `production` GitHub environment requires a human reviewer before `apply-prod` runs |

## Known limitations / next steps

- No remote Terraform state backend — the single largest gap for real
  multi-person or fully-automated CI/CD use. Adding an S3 bucket + DynamoDB
  lock table would let the pipeline deploy automatically and safely.
- Prod was deployed once for verification and then destroyed; it was not
  left running continuously alongside dev, to avoid duplicate cost during
  evaluation.
- `tfsec`/`tflint` static analysis were considered but left out as outside
  the mid-level requirement's literal scope, given the size of this
  project; noted here as a reasonable next addition.