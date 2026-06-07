# Architecture

## Runtime (request path + dependencies)

```mermaid
flowchart LR
  subgraph caller["Loan-officer system (in-VPC)"]
    U[finished underwriter review]
  end

  subgraph aws["AWS account · region us-east-1"]
    subgraph vpc["VPC (private)"]
      ALB["Internal ALB\nTLS 1.2+ (ACM)"]
      subgraph eks["EKS cluster (private API)"]
        SVC[Service ClusterIP]
        POD["agent pods\nuvicorn / FastAPI\nCPU HPA · Pod Identity"]
        SVC --> POD
      end
      RDS[("RDS Postgres\nMulti-AZ · KMS · PITR")]
      VPCE["VPC endpoints\nBedrock · S3 · SES\nSecrets Mgr · ECR · STS"]
    end

    S3D[("S3 borrower docs\nKMS · versioned")]
    S3A[("S3 audit trail\nObject Lock · 7y")]
    DDB[("DynamoDB\nidempotency keys")]
    BR["Bedrock\n(PrivateLink, prod)"]
    SES["SES\n(borrower email)"]
    SM["Secrets Manager\nDB URL · API key"]
    KMS["KMS CMKs\ndata · audit"]
  end

  U -- "HTTPS POST /v1/items/process" --> ALB --> SVC
  POD -- read docs --> S3D
  POD -- append audit --> S3A
  POD -- idempotency --> DDB
  POD -- classify+decide --> BR
  POD -- draft email --> SES
  POD -- read secrets --> SM
  POD -. via .-> VPCE
  POD -- loan/item state --> RDS
  KMS -. encrypts .-> RDS & S3D & S3A & DDB & SM
```

Synchronous request/response — the agent's native contract. We **deploy and
operate** the agent as shipped; we do not place a queue in front (that would
require building a consumer, which is out of scope). If arrival outgrows
synchronous serving, the documented evolution is SQS + a queue-depth scaler.

## Delivery (how code reaches the cluster)

```mermaid
flowchart LR
  DEV[push / PR] --> CI["GitHub Actions CI\nruff · pytest · docker\nhelm lint · tf validate · tfsec\nkind deploy smoke-test"]
  CI -->|merge to main| BUILD["build image\nECR push (OIDC)"]
  BUILD --> BUMP["bump image tag in\nvalues-<env>.yaml (git)"]
  BUMP --> ARGO["Argo CD"]
  ARGO -->|auto-sync| DEVENV[dev / staging]
  ARGO -->|manual sync + approval| PRODENV[prod]
  TF["Terraform\n(bootstrap · global · per-env stack)"] -. provisions .-> AWSINFRA[(EKS · RDS · S3 · IAM · KMS)]
```

## Environment separation

```mermaid
flowchart TB
  subgraph state["Remote state (S3 + DynamoDB lock, KMS)"]
    B[bootstrap] --- G[global: ECR + OIDC]
  end
  G --> DEVS["env/dev\n2 AZ · spot · Anthropic\ndisposable data"]
  G --> STG["env/staging\n3 AZ · on-demand · Anthropic"]
  G --> PRD["env/prod\n3 AZ · per-AZ NAT · Bedrock\nMulti-AZ RDS · 7y audit"]
  DEVS & STG & PRD --> STACK["modules/stack\n(network·eks·karpenter·data·secrets·identity·obs)"]
```

Each environment is a separate state file and (recommended) a separate AWS
account; the composition lives once in `modules/stack` and is parameterised per
env. No production data ever lands in non-prod (separate accounts + synthetic
dev data + `force_destroy` only in dev).
