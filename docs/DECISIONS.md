# Architecture Decisions

Key design decisions and their rationale for this EKS platform.

---

## 1. Separate EKS Clusters per Environment

**Decision**: Two independent EKS clusters (dev + prod) instead of one shared cluster with namespace isolation.

**Rationale**: Blast radius isolation - a misconfigured NetworkPolicy or RBAC rule in dev cannot affect production workloads. Independent scaling: dev uses t3 spot instances, prod uses m5/c5 with on-demand fallback. Separate upgrade cycles allow testing Kubernetes version bumps on dev first.

**Trade-off**: Higher base cost (~$73/month per control plane). Acceptable for production workloads where isolation is critical.

---

## 2. Karpenter over Cluster Autoscaler

**Decision**: Karpenter 1.0 for node autoscaling instead of the Kubernetes Cluster Autoscaler.

**Rationale**: 30-60 second node provisioning vs 3-5 minutes. Karpenter evaluates all pending pods simultaneously and picks the cheapest instance type that fits. Built-in consolidation automatically removes underutilized nodes. Native spot interruption handling via SQS + EventBridge.

**Trade-off**: Requires IAM setup (Pod Identity) and NodePool/EC2NodeClass CRDs. More initial configuration, but fewer operational surprises.

---

## 3. ALB + Ingress-NGINX (Dual Ingress)

**Decision**: AWS ALB handles external traffic and load balancing. Ingress-NGINX handles internal path/host-based routing.

**Rationale**: ALB provides native AWS integration: security groups, target groups, and readiness for WAF/ACM when needed. NGINX provides flexible application-level routing (regex paths, canary, rate limiting) that ALB Ingress annotations cannot match. The dual pattern is standard in production EKS deployments. TLS termination can be added by attaching an ACM certificate to the ALB.

**Trade-off**: Two ingress components to manage instead of one. Justified by the clean separation of concerns between AWS-layer and application-layer routing.

---

## 4. External Secrets Operator over Kubernetes Secrets in Git

**Decision**: Secrets synced from AWS Secrets Manager via External Secrets Operator. No secrets in Git.

**Rationale**: Secrets never touch version control. IAM-scoped isolation ensures each cluster only reads its own secret prefixes (`dev/*`, `staging/*`, `production/*`). Secret rotation happens in Secrets Manager without Git changes. Full audit trail via CloudTrail.

**Trade-off**: Requires AWS Secrets Manager setup and ESO deployment. Worth it for any environment handling real credentials.

---

## 5. EKS Pod Identity over IRSA

**Decision**: EKS Pod Identity for all workload IAM authentication (Karpenter, AWS LBC, External Secrets).

**Rationale**: AWS-recommended replacement for IRSA (IAM Roles for Service Accounts). Simpler setup: no OIDC provider configuration, no service account annotations. Credentials are injected directly by the EKS Pod Identity Agent addon. Better error messages for debugging. Consistent authentication model across all components.

**Trade-off**: Requires EKS 1.24+ and the Pod Identity Agent addon. Both are already standard on modern EKS clusters.

---

## 6. Three Separate Repositories over Monorepo

**Decision**: `infra-live`, `helm-charts`, and `app-source` as independent Git repositories.

**Rationale**: Separation of concerns. Infrastructure changes go through different review/approval than application code. ArgoCD watches only `helm-charts` - a Terraform change should not trigger application redeployment. Different teams can own different repos with distinct CODEOWNERS and branch protection rules.

**Trade-off**: Cross-repo CI coordination requires a GitHub PAT for the CI pipeline to update helm-charts. Acceptable for the clarity and isolation gained.

---

## 7. Terragrunt DRY Pattern over Terraform Workspaces

**Decision**: Terragrunt with `env.hcl` per environment and shared modules, instead of Terraform workspaces.

**Rationale**: Explicit environment directories (`dev/`, `prod/`) make it immediately clear what infrastructure exists. Each environment is independently deployable and destroyable. `env.hcl` centralizes all per-environment differences (CIDR blocks, instance types, capacity types, replica counts). No workspace state confusion or accidental `terraform workspace select` mistakes.

**Trade-off**: Slightly more directory structure than workspaces. The explicitness is a feature, not a bug.

---

## 8. Generic Helm Chart with Base + Overlays

**Decision**: One reusable `generic-app` chart with value file layering (base + environment overlays) instead of per-application charts.

**Rationale**: Consistency across all applications: every app gets the same security context, health probes, PDB, and topology spread constraints. New applications only need value files, not new templates. ArgoCD merges `base/values.yaml` + `overlays/{env}/values.yaml` at deploy time. Reduces chart maintenance to a single location.

**Trade-off**: Less flexibility for highly specialized applications. For this project's scope, the consistency benefit outweighs the flexibility cost.
