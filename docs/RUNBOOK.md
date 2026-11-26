# FilOzone github-mgmt runbook

## How it works

Edit `github/FilOzone.yml` to change managed GitHub settings through a PR. `Plan` previews the change, `Apply` makes it, and `Sync` reads GitHub back into Terraform state and YAML. [Organization configuration](../github/FilOzone.yml)

| Backend | Value |
| --- | --- |
| FilOz AWS account and region | `941641221830`, `us-east-1` |
| Bucket and workspace | `filoz-github-mgmt-filozone`, `FilOzone` |
| State and lock paths | `org/FilOzone/terraform.tfstate` and `org/FilOzone/terraform.tfstate.tflock` |
| OIDC roles | `filoz-github-mgmt-filozone-ro` and `filoz-github-mgmt-filozone-rw` |

Keep the separate bootstrap state for changes to the versioned bucket or IAM roles. [Backend](../terraform/terraform_override.tf) · [Bootstrap](../terraform/bootstrap/aws.tf)

### Workflow credentials

GitHub Apps authenticate GitHub API calls. Use the read-only App to inspect configuration and the read-write App for steps that apply changes or push branches.

| GitHub App | Jobs that use it |
| --- | --- |
| Read-only | `Plan`, the read step of `Fix`, `Apply` prepare, and `Clean Up` (in `push`) |
| Read-write | `Apply`, `Sync`, `Update`, the push step of `Fix`, `Clean`, `Labels`, and `Upgrade` |

AWS OIDC gives `Plan`, `Comment`, and `Fix` temporary read-only S3 credentials through `read`. `Apply`, `Sync`, and `Clean` use the read-write role through `write`. Both `write` and `push` are restricted to `master`. [GitHub OIDC documentation](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)

## Change access through a PR

1. Edit the relevant member, team, or collaborator in `github/FilOzone.yml`. Open a PR to `master` and check any `Fix` commits.
2. Review each resource in the Terraform plan posted on the PR. For a long plan, open **Plan → Comment → Show terraform plans** in Actions.
3. Squash and merge after approval. Check that **Terraform Apply** ran successfully for the merge commit, then verify the result in GitHub.
4. Wait for `Apply` and `Update` before merging another PR. `Update` attempts to bring eligible open PRs up to date and trigger fresh plans. Update any skipped or conflicting PR branch manually and review its fresh plan. [Update script](../scripts/src/actions/update-pull-requests.ts)

In #83, the single `destroy` removed one direct FOC-PM collaborator grant. Apply succeeded and we verified the grant was removed in GitHub. [Example PR](https://github.com/FilOzone/github-mgmt/pull/83) · [Apply run](https://github.com/FilOzone/github-mgmt/actions/runs/45827615933/job/139935891426)

## Sync from GitHub

Run **Actions → Sync → Run workflow** from `master` with workspace `FilOzone` or blank, `lock=true`, and `refresh=false`. Pause other merges while Sync writes back to `master`. Check that **Sync (FilOzone)** and **Push** succeeded, then review the YAML diff. The [`.sync` file](../.sync) records the run ID.

For a backend cutover, pause merges and disable `Apply` before merging the backend PR. Let existing Apply runs finish. Run Sync against the new backend, re-enable Apply after Sync succeeds, then verify with a fresh Plan and Apply. The first import took about 20 minutes. The first Plan listed merge and sign-off defaults for seven archived repositories. Review the exact fields and verify the repositories stay archived before accepting that diff. [First Sync](https://github.com/FilOzone/github-mgmt/actions/runs/45818396464) · [First Plan](https://github.com/FilOzone/github-mgmt/pull/82#issuecomment-7192897522) · [Provider behavior](https://github.com/integrations/terraform-provider-github/blob/v6.6.0/github/resource_github_repository.go#L740-L746)

## Recover from a failed Apply

Pause other merges and open the failed run for the merge commit.

- **AWS sign-in failed**. Check the role ARN, OIDC trust, and job environment. For GitHub sign-in, check the App ID, installation ID, and PEM secret location.
- **Reviewed plan missing**. Check **Find sha for plan** and **Download reviewed terraform plan**. Fix failures before any writes and retry only if the reviewed plan is still current.
- **Plan comparison failed or Apply may have made partial changes**. Check the affected GitHub settings and Terraform state, then review a fresh plan in a follow-up PR. Run `Sync` only when the current GitHub configuration should become the YAML.
- Resume merges after Apply succeeds, the GitHub result is verified, and `Update` completes. [Apply workflow](../.github/workflows/apply.yml)

## Recover from a stuck lock

Record the lock ID and path from the error. Check for active or queued `Apply`, `Sync`, and `Clean` runs and confirm with the operator that no state writer is active. If automatic unlock failed, a maintainer can use their MFA-backed AWS session from a fresh checkout of `master`.

```sh
aws sts get-caller-identity --query Account --output text
terraform -chdir=terraform init -input=false
terraform -chdir=terraform workspace select FilOzone
terraform -chdir=terraform workspace show
```

Verify account `941641221830`, workspace `FilOzone`, and the lock path above. Run `terraform -chdir=terraform force-unlock LOCK_ID` with the ID from the error. Keep locking enabled and review a fresh plan before resuming writes. [Terraform force-unlock](https://developer.hashicorp.com/terraform/language/state/locking#force-unlock)

## Rotate credentials

1. Check **Settings → Secrets and variables → Actions** and **Settings → Environments** for the active secrets. For environment-scoped secrets, place `RO_GITHUB_APP_*` in `read` and `push`, and `RW_GITHUB_APP_*` in `write` and `push`. If using `Upgrade`, also verify the upstream `GITHUB_APP_*` mapping in `push`.
2. Have an App manager generate a new PEM and update the corresponding `RO_GITHUB_APP_PEM_FILE` or `RW_GITHUB_APP_PEM_FILE`. Check Plan and Fix for the read-only key. Check Apply and any push workflows using the read-write key, including Upgrade if retained. Revoke the old key after verification. [GitHub App key rotation](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps)

AWS OIDC uses temporary credentials. Manage role and trust changes in the bootstrap Terraform. Retire any remaining legacy `RO_AWS_*` and `RW_AWS_*` repository secrets after cutover verification and approval.

## Upgrade from upstream

While `Upgrade` is enabled, run it from `master` with the chosen upstream commit SHA in `ref`, then review the generated PR. The `ref` selects the template revision. GitHub loads the reusable workflow from `@master`. [Upgrade workflow](../.github/workflows/upgrade.yml)

If `Upgrade` is retired, use a normal PR.

1. Check out a specific commit of `ipdxco/github-as-code` locally and copy the selected tracked files. Record the upstream SHA in the PR.
2. Keep the old exclusions (`github/*.yml`, `terraform/*_override.tf`, `README.md`, `scripts/src/actions/fix-yaml-config.ts`, `.github/dependabot.yml`, and `.github/workflows/*_reusable.yml`). Preserve FilOzone's workflow customizations, bootstrap, and runbook. [Upstream file selection](https://github.com/ipdxco/github-as-code/blob/master/.github/workflows/upgrade_reusable.yml#L47-L53)
3. Open a PR from a branch in this repository using your GitHub account. You can prepare the diff locally or with an agent. Keep the read-write App key in Actions secrets. Review Plan and verify Apply.
