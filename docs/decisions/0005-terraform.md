# 0005 — The infrastructure in Terraform, applied by HCP Terraform

**Status:** accepted  
**Date:** 2026-10-31

## Context

Labs 4–6 added three CloudFormation templates, each with a deploy script run from a laptop:
`infra/auth.yaml` (Cognito, `make deploy-auth`), `infra/reports.yaml` (the weekly report) and
`infra/ai.yml` (the agenda parser). They worked, but:

- **Applied from a laptop.** Every change was `aws cloudformation deploy` with the author's own
  keys. The repository showed the template, not who applied which version when, and nobody
  reviewed what the deploy would actually change. A change set was possible but optional.
- **Inputs scattered.** Each script put together its parameters from `.env`, from other stacks
  and from live AWS calls (route tables, the running image, the database secret). The real
  description of each stack was the template plus the script plus one person's `.env`.
- **Spry already reaches past AWS.** The Google OAuth client, the GitHub repository and its
  OIDC role, and the DNS records at nic.ua are all configuration that CloudFormation cannot
  describe.
- **A second environment is coming** (stage, then perhaps a white-label copy), and three
  hand-parameterised stacks do not copy well.

The 31 resources in those stacks hold data that must not be lost: every account in the user
pool (Lab 4) and every report in the bucket (Lab 5).

## Decision

- **Terraform** describes those three stacks, in `infra/*.tf`: one root module, one file per
  former template (`auth.tf`, `reports.tf`, `ai.tf`), plus `data.tf`, `variables.tf`,
  `outputs.tf`. Non-secret inputs are in `terraform.tfvars`, in Git.
- **State and runs live in HCP Terraform**: organization `ooad-anastasiialem`, workspace
  `spry-dev`, Remote execution, working directory `infra`, connected to the GitHub repository.
  A pull request gets a speculative plan as a check, and a merge to `main` plans and applies.
- **No AWS keys anywhere.** Every run assumes the IAM role `hcp-terraform-ooad-anastasiialem`
  through OIDC dynamic credentials (`TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN`). That role
  and its trust were created once, from a laptop, by a separate bootstrap configuration
  with local state.
- **Adopted, not re-created.** The stacks were redeployed with `DeletionPolicy: Retain` and then
  deleted. `import` blocks handed all 31 resources to Terraform, which models them as 46
  resources: in Terraform the inline IAM policies, the managed-policy attachments and the
  bucket's settings are separate resources. The first apply was
  `46 to import, 0 to add, 4 to change, 0 to destroy`. The four in-place changes were the two
  zip Lambdas re-uploaded with the same code, and two values marked sensitive in the state
  (the value did not change). Nothing was re-created.
- **The older stacks stay CloudFormation** for now: `backend.yaml` (VPC use, API, database),
  `frontend.yaml`, `github-oidc.yaml`. Terraform reads them through `aws_cloudformation_stack`
  data sources, the database URL from Secrets Manager, and the running image from the API
  function. They move to Terraform the same way, one at a time.
- **Two roads, one per kind of change.** GitHub Actions still deploys the *application*: it
  builds the image, rolls the three image Lambdas and builds the site. HCP Terraform deploys the
  *infrastructure*. The image Lambdas have `ignore_changes = [image_uri]`, so the two do not
  fight. When a change needs both (a new environment variable that new code reads), the
  infrastructure goes first. Merge the Terraform pull request, wait for *Apply finished*, then
  merge the code.

## Answers to the questions this has to settle

**Why Terraform, not CloudFormation, CDK or OpenTofu?**
CloudFormation keeps the state for us and rolls back by itself, which is real value. But it
stops at the edge of one AWS account, and Spry's configuration does not. CDK is CloudFormation
underneath, with the same limit, and adds a TypeScript or Python build step to infrastructure
that is mostly declarations. OpenTofu would accept these files unchanged, and its open licence
is a point in its favour. The course and HCP Terraform use Terraform, and HCP Terraform runs
Terraform, not OpenTofu. If the BSL licence or HCP pricing ever becomes a problem, moving to
OpenTofu and an S3 backend is a small change. Nothing in `infra/` is specific to HashiCorp.

**Who can change the infrastructure now, and how?**
Anyone who can open a pull request can *propose* a change. The plan in the check shows what it
will do, and a reviewer approves the *plan*, not only the HCL diff. Only a merge to `main`
applies, and only HCP Terraform holds credentials that can apply. Members of the HCP
organization can also start a run from the UI, which is the emergency path. `make infra-plan`
from a laptop gives a speculative plan and cannot apply, and there is no `terraform apply`
in the Makefile. An AI assistant goes through the same road. It writes `.tf` files and runs
`terraform plan`, and a person merges.

**Where do the secrets end up, the state included?**
- `google_client_secret`: a sensitive Terraform variable in the `spry-dev` workspace. The UI
  shows it as write-only, and plans print `(sensitive value)`. It is **in the state in plain
  text** (`aws_cognito_identity_provider.google.provider_details`), and Cognito holds it, as
  before. It is also in the author's gitignored `.env`, which was needed for laptop plans
  during the migration.
- The database URL: read from Secrets Manager into the builder Lambda's environment, as the
  CloudFormation parameter did. It is now **in the state too**.
- The state is stored by HCP Terraform, encrypted at rest. Anyone with *read state versions*
  permission on the workspace can download it, so workspace access is as sensitive as the
  secrets themselves. `sensitive = true` hides values in plan output, not in the state. No
  state file is ever on a laptop or in Git (`infra/.gitignore`).
- A plan started from a laptop uploads the repository root, because the workspace's working
  directory is `infra`. The first three migration runs uploaded the gitignored `.env` with it,
  so those configuration versions in HCP Terraform hold the Google secret and the database
  password. `.terraformignore` now keeps `.env` out of every CLI upload. Runs started by a push
  only see what is in Git.
- CI reads outputs with an HCP API token (`TF_API_TOKEN` repository secret). The outputs used
  are public values only (the pool id, the client id, the parser URL).

**What happens if HCP Terraform is down?**
Nothing that already runs is affected: HCP Terraform is not in any request path. Infrastructure
changes wait. Application deploys also stop, because `deploy-frontend` refuses to build without
the Terraform outputs in CI rather than ship a site without sign-in. For a real emergency, fix
by hand in the console, write down what was changed, and once HCP is back, put the same change
in a pull request. Its plan must then show *No changes*, otherwise the next apply undoes the
fix. Moving the state to an S3 backend (`terraform state pull`, then a `backend "s3"` block)
is the way out if HCP Terraform goes away for good.

## Alternatives considered

| Alternative | Why it lost |
|---|---|
| Keep CloudFormation, add a GitHub Actions job that deploys the stacks on merge | Fixes "applied from a laptop", but not the AWS-only limit or the scattered parameters. Change sets are not shown in a pull request without extra tooling. |
| Delete the stacks and `terraform apply` from scratch | Deletes every user account and every report. Unacceptable for a pool people have signed up to. |
| State in S3 with a lock, applies from GitHub Actions | Works, and avoids another vendor. But we would own the bucket, its encryption and its access policy, and build the plan-as-a-PR-check ourselves. HCP Terraform's free tier does all of that. |
| One workspace per former stack (auth, reports, ai) | Three states and the outputs wired between them (`terraform_remote_state`). They change together and are small, so one root module is simpler. Split when there is a reason. |

## Consequences

- `make deploy-auth`, `make deploy-reports` and `make deploy-ai` are gone, together with their
  scripts and the three YAML templates. `make infra-plan` shows a plan, `make infra-env`
  copies the public outputs to `.env`, and `make auth-branding` sets the sign-in page
  background, which Terraform deliberately ignores (`ignore_changes` on the branding's
  settings and assets).
- Drift is visible: every plan compares the files with AWS, so a change made in the console
  shows up as a `~` line in the next plan, and the next apply reverts it.
- Terraform has no automatic rollback. A failed apply stops halfway, and the fix is a new
  commit and another apply.
- Attributes that force replacement and would lose data are marked in comments: the user
  pool's `schema` blocks (every account) and the bucket's name (every report).
- The bootstrap role has `AdministratorAccess` and trusts every workspace in the organization.
  For a real team it should trust `organization:ooad-anastasiialem:project:*:workspace:spry-dev:run_phase:*`
  only, with policies limited to Cognito, Lambda, IAM (roles with a path), S3, SQS,
  Scheduler, SES, Logs, EC2 VPC endpoints, Budgets and read-only CloudFormation and Secrets
  Manager.
