# deploy-roles

The reusable **spoke deploy roles** for the org's OIDC hub-spoke delivery model. Creates the
two IAM roles a spoke's CI assumes (via the ck-tooling hub) to plan/apply its own
infrastructure:

- **apply (RW)** — the gated write path, assumable by the spoke's apply principal(s): the hub CI
  *apply* role (itself reachable only from the spoke's protected GitHub Environment) and/or
  additional principals for a non-GHA executor (e.g. a CodeBuild apply role in the CodePipeline
  delivery model). At least one is required; a CodePipeline spoke trusts its CodeBuild role and sets
  `hub_apply_role_arn = null` to retire the GHA apply path.
- **plan (RO, optional)** — the read path, assumable by the spoke's plan principal(s): the hub CI
  *plan* role (PR previews) and/or additional principals for a non-GHA executor (e.g. the CodeBuild
  plan + drift roles in the CodePipeline model). Omit both for an apply-only spoke.

The standardized, security-critical part is the **trust**: every trusted principal is a concrete
ARN (no wildcard, no cross-trust between the plan and apply paths) for `sts:AssumeRole` +
`sts:TagSession`. The apply role trusts its apply-principal set (`hub_apply_role_arn` and/or
`apply_principal_arns`, at least one required); the plan role trusts its plan-principal set
(`hub_plan_role_arn` and/or `plan_principal_arns`). The
spoke supplies its own permissions (`*_policy_arns` / `*_inline_policy`);
the apply role needs at least one of `apply_policy_arns` / `apply_inline_policy`. The two role
names are the rendered org label plus a **literal** role-type suffix — `ck-<domain>-<name>-apply`
and `-plan` (`name` defaults to `deploy`) — so they are unique by construction. Names + tags come
from the **`cloudposse/context` provider** the consuming root configures. The wrong-account guard
is the **root's** job — the root calls the shared [`account-guard`](../account-guard) module once
per spoke account — so this module takes no `expected_account_id`.

## Usage (a spoke's `bootstrap/deploy-roles` root)

```hcl
# The consuming root configures the cloudposse/context provider (typically from the context-schema
# module); with namespace=ck, domain=org the roles render ck-org-deploy-apply / ck-org-deploy-plan.
module "deploy_roles" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/deploy-roles?ref=v0.5.0"

  # The hub CI roles permitted to assume each spoke role (from ck-tooling/environments/hub):
  hub_apply_role_arn = "arn:aws:iam::883385860947:role/ck-tooling-ci-foundation-apply"
  hub_plan_role_arn  = "arn:aws:iam::883385860947:role/ck-tooling-ci-foundation-plan" # null = apply-only

  # The spoke's own deploy permissions — policy resources you define elsewhere in this same root:
  apply_policy_arns = [aws_iam_policy.org_deploy.arn]
  plan_policy_arns  = [aws_iam_policy.org_readonly.arn]
}
```

Wire the outputs back into the hub's `spokes.auto.tfvars` (`apply_role_arns` / `plan_role_arns`)
and into the env-root providers' `assume_role`.

## Spokes whose apply role mints IAM roles (`managed_role_boundary`)

An apply role that can create IAM roles can otherwise create one **more privileged than itself** —
`CreateRole` → `AttachRolePolicy AdministratorAccess` → `PassRole` — which turns a compromised CI
apply into full administrative access. Scoping `iam:*` to a role-name prefix does not close this;
the prefix bounds *which* roles it can mint, not *how much* they may hold.

Set `managed_role_boundary` and the module takes over the whole role-management grant:

```hcl
module "deploy_roles" {
  source = "git::https://github.com/coursekata/ck-tf-modules.git//modules/deploy-roles?ref=v0.5.3"

  apply_principal_arns = [...]
  apply_inline_policy  = data.aws_iam_policy_document.spoke_apply.json # NO iam:* statements

  managed_role_boundary = {
    policy_document   = data.aws_iam_policy_document.workload_ceiling.json
    role_arn_patterns = ["arn:aws:iam::900303592457:role/ck-datalake-prd-*"]
  }
}
```

The spoke's own `apply_inline_policy` should contain **no** `iam:*` statements — the module emits
them, and hand-written ones are how the escalation gets reintroduced. What it generates:

- every widening action (`CreateRole`, `PutRolePolicy`, `AttachRolePolicy`, `DetachRolePolicy`,
  `DeleteRolePolicy`, `PutRolePermissionsBoundary`) conditioned on `iam:PermissionsBoundary`
  equalling the boundary policy this module creates — so a role minted without it is denied, and so
  is adding a policy to an unbounded role that already exists;
- the lifecycle/read actions (`UpdateAssumeRolePolicy`, `DeleteRole`, `TagRole`, `PassRole`, the
  `Get`/`List` family) unconditioned — AWS's delegation pattern conditions only the create/attach/put
  family, and a condition on an action that never populates the key would never match, costing the
  apply role those actions outright. Safety doesn't rest on that anyway: `CreateRole` is conditioned,
  so every role matching the patterns is bounded by construction;
- `Deny` on `iam:DeleteRolePermissionsBoundary` (`Resource: "*"`) so the boundary can't be stripped;
- `Deny` on editing the boundary policy itself, so the ceiling can't be rewritten;
- `Deny` on `iam:*` against the **deploy roles' own ARNs**.

That last one closes the shortest path, and no boundary condition can substitute for it: the deploy
roles carry no boundary themselves, so if their ARNs fall inside `role_arn_patterns` the apply role
can attach `AdministratorAccess` to *itself* in one call, or rewrite its own trust policy to admit
an arbitrary principal. Keep the patterns disjoint from the deploy-role names (`ck-<domain>-prd-*`
rather than `ck-<domain>-*`); the `Deny` is the backstop, not the design.

Pass `managed_role_boundary_arn` to the env roots so each `aws_iam_role` they create sets
`permissions_boundary` to it — the boundary is only enforced on roles that carry it, and the
conditioned grant is what makes carrying it mandatory.

Boundaries also limit **resource-based** policies that grant to a bounded role's ARN, so the ceiling
must cover every cross-account grant the workload roles rely on. Too narrow a ceiling doesn't fail
loudly at apply — it silently breaks the workload at runtime.
