# DevOps Portfolio Project — GitHub Actions → ECR → ECS Fargate → RDS

A hands-on DevOps project that demonstrates how to build, containerize, deploy, and monitor a Node.js application on AWS.

The project uses:

- Terraform for infrastructure
- GitHub Actions for CI/CD
- GitHub OIDC for AWS authentication
- Amazon ECR for Docker images
- Amazon ECS Fargate for application containers
- Application Load Balancer for public traffic
- Amazon RDS PostgreSQL for the database
- AWS Secrets Manager for the database credentials
- Amazon CloudWatch for logs, dashboards, and alarms

The **staging environment is the live/demo environment** used for validation. Production Terraform and CI/CD configuration are included, but production deployment is intentionally optional to avoid unnecessary AWS costs for this assignment.

---

## 1. Architecture

### Application flow

```text
Developer
   |
   v
GitHub Repository
   |
   v
GitHub Actions
   |
   | OIDC
   v
AWS IAM Role
   |
   +--------------------+
   |                    |
   v                    v
Amazon ECR          ECS Fargate
                        |
                        v
                Application Load Balancer
                        |
                        v
                 Node.js / Express
                        |
                        v
                 RDS PostgreSQL
```

### AWS network layout

```text
VPC
|
+-- Public Subnet AZ-1
|      |
|      +-- Application Load Balancer
|
+-- Public Subnet AZ-2
|      |
|      +-- Application Load Balancer
|      +-- NAT Gateway
|
+-- Private App Subnet AZ-1
|      |
|      +-- ECS Fargate
|
+-- Private App Subnet AZ-2
|      |
|      +-- ECS Fargate
|
+-- Private DB Subnet AZ-1
|      |
|      +-- RDS PostgreSQL
|
+-- Private DB Subnet AZ-2
       |
       +-- RDS PostgreSQL subnet group
```

For a detailed explanation of the architecture, see:

- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`

---

## 2. Technology choices

| Area | Technology | Purpose |
|---|---|---|
| Infrastructure | Terraform | Create and manage AWS resources |
| Application | Node.js + Express | Simple web application |
| Container | Docker | Package the application |
| Registry | Amazon ECR | Store Docker images |
| Compute | ECS Fargate | Run containers without managing EC2 servers |
| Load balancing | Application Load Balancer | Public HTTP entry point |
| Database | Amazon RDS PostgreSQL | Managed relational database |
| Secrets | AWS Secrets Manager | Store database credentials |
| CI/CD | GitHub Actions | Test, build, and deploy the application |
| AWS authentication | GitHub OIDC | Short-lived AWS credentials |
| Monitoring | CloudWatch | Logs, dashboards, and alarms |

---

## 3. Repository structure

```text
8byte-devops-assignment/
|
+-- application/
|   +-- server.js
|   +-- package.json
|   +-- package-lock.json
|   +-- .env.example
|   +-- tests/
|
+-- docker/
|   +-- Dockerfile
|   +-- .dockerignore
|
+-- infrastructure/
|   |
|   +-- bootstrap/
|   |   +-- main.tf
|   |   +-- variables.tf
|   |   +-- terraform.tfvars.example
|   |
|   +-- modules/
|   |   +-- vpc/
|   |   +-- alb/
|   |   +-- ecs/
|   |   +-- ecr/
|   |   +-- rds/
|   |   +-- iam/
|   |   +-- cloudwatch/
|   |
|   +-- envs/
|       +-- staging/
|       +-- prod/
|
+-- scripts/
|   +-- bootstrap.sh
|   +-- smoke-test.sh
|   +-- cleanup.sh
|
+-- monitoring/
|
+-- docs/
|   +-- ARCHITECTURE.md
|   +-- SECURITY.md
|
+-- .github/
|   +-- workflows/
|       +-- ci-cd.yml
|
+-- README.md
```

### How the Terraform folders are organized

`infrastructure/modules/` contains reusable Terraform modules.

`infrastructure/envs/staging/` and `infrastructure/envs/prod/` are the environment-specific Terraform root configurations that call those modules.

This keeps the environment configuration relatively small while the actual AWS resource definitions stay inside reusable modules.

---

## 4. Prerequisites

Install/configure:

- AWS account
- AWS CLI v2
- Terraform >= 1.10
- Docker
- Node.js >= 20
- Git
- GitHub repository
- `jq`

Verify:

```bash
terraform version
aws --version
docker --version
node --version
jq --version
```

Verify AWS authentication:

```bash
aws sts get-caller-identity
```

The AWS CLI must have enough permissions to create the resources used by this project.

---

## 5. Configuration

The main values that normally need to be customized are:

| Value | Location |
|---|---|
| AWS region | `infrastructure/envs/*/variables.tf` and GitHub Actions |
| GitHub organization/user | `terraform.tfvars` |
| GitHub repository | `terraform.tfvars` |
| Terraform state bucket | Terraform backend configuration |
| SNS alarm email | `terraform.tfvars` |
| GitHub Actions AWS role ARN | GitHub repository variables |

Do not commit real secrets or credentials.

The database password is generated/managed through RDS and AWS Secrets Manager rather than being hard-coded into Terraform variables.

---

# 6. Local application

From the repository root:

```bash
cd application

cp .env.example .env

npm install
npm test
npm start
```

In another terminal:

```bash
curl http://localhost:3000/health
curl http://localhost:3000/
```

The application can run locally without a database.

The health endpoint reports the database status so that the deployed ECS application can also be checked for database connectivity.

---

# 7. Docker

Build from the repository root:

```bash
docker build -f docker/Dockerfile -t devops-portfolio-app:local .
```

Run:

```bash
docker run --rm -p 3000:3000 \
  -e APP_ENV=local \
  devops-portfolio-app:local
```

Test:

```bash
curl http://localhost:3000/health
```

The Docker image runs the application as a non-root user and contains a health check.

---

# 8. Terraform remote state

The project uses an S3 bucket for Terraform remote state.

The bootstrap configuration creates the state bucket before the environment stacks are deployed.

Run:

```bash
cp infrastructure/bootstrap/terraform.tfvars.example \
   infrastructure/bootstrap/terraform.tfvars
```

Edit the file and provide a globally unique S3 bucket name.

Then:

```bash
./scripts/bootstrap.sh
```

After the bucket is created, make sure the backend configuration points to the correct bucket in:

```text
infrastructure/envs/staging/backend.tf
infrastructure/envs/prod/backend.tf
infrastructure/envs/prod/providers.tf
```

Terraform native S3 state locking is used with:

```text
use_lockfile = true
```

No separate DynamoDB lock table is required by this project.

---

# 9. Deploy staging infrastructure

Staging is the main environment used for this assignment.

```bash
cd infrastructure/envs/staging
```

Copy the example variables:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Set your GitHub organization/user and repository.

Then initialize Terraform:

```bash
terraform init
```

Format and validate:

```bash
terraform fmt -check
terraform validate
```

Review:

```bash
terraform plan
```

Apply:

```bash
terraform apply
```

After the infrastructure is created, the first ECS task may depend on an image already existing in ECR. The GitHub Actions pipeline performs the application image build and deployment.

---

# 10. ECR

The ECR repository is created by the staging infrastructure.

Check it:

```bash
aws ecr describe-repositories \
  --repository-names devops-portfolio-app \
  --region us-east-1
```

The CI/CD workflow builds the Docker image and pushes it to ECR.

Images are tagged using the Git commit SHA so that each deployment can be traced back to a specific source revision.

---

# 11. GitHub Actions and OIDC

GitHub Actions uses AWS OIDC instead of storing long-lived AWS access keys.

The flow is:

```text
GitHub Actions
      |
      | OIDC token
      v
AWS STS
      |
      | temporary credentials
      v
GitHub Actions IAM Role
      |
      +-- ECR
      +-- ECS
      +-- iam:PassRole
```

The IAM trust policy restricts the GitHub identity that can assume the deployment role.

The project creates the GitHub OIDC provider once in the AWS account and reuses its ARN for the other environment.

### GitHub configuration

In the GitHub repository, configure the required environment/variables used by the workflow, including the staging deployment role ARN and staging ALB URL.

Production has a separate GitHub Environment and can be protected with required reviewers.

No long-lived AWS access key is required for GitHub Actions.

---

# 12. CI/CD pipeline

The workflow is:

```text
Pull Request / Push
        |
        v
Run tests
        |
        v
Build Docker image
        |
        v
Push image to ECR
        |
        v
Deploy staging
        |
        v
Wait for ECS service
        |
        v
Run staging smoke test
        |
        +--------------------+
        |                    |
        | Production enabled |
        |                    |
        v                    |
Production approval          |
        |                    |
        v                    |
Deploy production <----------+
        |
        v
Production smoke test
```

For the final assignment demonstration, the **staging path is the validated deployment path**.

---

# 13. Staging deployment — validated

The staging environment is currently the live AWS demonstration environment.

Validated ECS service:

```text
Cluster:
devops-portfolio-staging-cluster

Service:
devops-portfolio-staging-app-service
```

The service was verified with:

```bash
aws ecs describe-services \
  --cluster devops-portfolio-staging-cluster \
  --services devops-portfolio-staging-app-service \
  --region us-east-1 \
  --query 'services[0].{desired:desiredCount,running:runningCount,pending:pendingCount,status:status}' \
  --output table
```

Expected healthy result:

```text
desired = 1
running = 1
pending = 0
status  = ACTIVE
```

The staging health endpoint was also validated:

```bash
curl http://<STAGING_ALB_DNS>/health
```

Example response:

```json
{
  "status": "ok",
  "app_version": "staging",
  "app_env": "staging",
  "database": "ok"
}
```

The repository smoke test also validates:

```bash
./scripts/smoke-test.sh "http://<STAGING_ALB_DNS>"
```

Expected:

```text
PASS: GET /health -> 200
PASS: GET / -> 200
==> Smoke test passed.
```

---

# 14. Production deployment

Production configuration exists in:

```text
infrastructure/envs/prod/
```

and the GitHub Actions workflow contains the production deployment path.

However, **production is intentionally optional for this assignment**.

The reason is cost control.

Running another environment can create ongoing AWS charges from resources such as:

- NAT Gateway
- Application Load Balancer
- ECS Fargate
- RDS
- CloudWatch
- ECR/storage and data transfer

For this reason, the final demonstration focuses on the successfully deployed staging environment rather than keeping a second complete production environment running.

### Important clarification

Production was not treated as a missing part of the project.

The production configuration demonstrates how the same application/infrastructure pattern can be extended to another environment, while the staging environment is used as the live validation environment.

Production can be enabled later when an actual production deployment is required.

---

# 15. Monitoring

Monitoring is implemented with Amazon CloudWatch.

There are two dashboards:

```text
devops-portfolio-staging-application
devops-portfolio-staging-infrastructure
```

### Infrastructure dashboard

The infrastructure dashboard focuses on AWS resource health, including:

- ECS CPU utilization
- ECS memory utilization
- ECS running task count
- ALB request metrics
- ALB 4xx/5xx metrics
- Target health

### Application dashboard

The application dashboard focuses more on application traffic and behavior, including:

- Request count
- Target 5xx responses
- Response latency
- Healthy targets
- Application logs / error information

---

# 16. CloudWatch alarms

The staging environment has CloudWatch alarms for important health conditions.

Examples include:

```text
ECS CPU high
ECS memory high
ECS running tasks below desired
ALB 5xx high
ALB unhealthy hosts
ALB latency high
RDS CPU high
RDS free storage low
```

The running-task alarm is configured against the actual staging desired count.

For the current low-cost staging configuration:

```text
Desired ECS tasks: 1
Alarm threshold:   1
```

This avoids keeping the alarm permanently in `ALARM` simply because staging intentionally runs one task.

Some AWS-generated ECS target-tracking alarms may also appear in the CloudWatch console because ECS Service Auto Scaling creates them.

---

# 17. Viewing monitoring in the AWS Console

Monitoring should be demonstrated through the AWS Console during the project walkthrough.

Make sure the AWS Console region is:

```text
US East (N. Virginia)
us-east-1
```

This is important because the staging resources are deployed in `us-east-1`.

### View alarms

Go to:

```text
AWS Console
  → CloudWatch
  → Alarms
```

You should see the staging alarms.

### View dashboards

Go to:

```text
AWS Console
  → CloudWatch
  → Dashboards
```

Open:

```text
devops-portfolio-staging-infrastructure
```

and:

```text
devops-portfolio-staging-application
```

### View logs

Go to:

```text
AWS Console
  → CloudWatch
  → Logs
  → Log groups
```

The ECS application log group is:

```text
/ecs/devops-portfolio-staging
```

Current configured log retention is:

```text
14 days
```

---

# 18. Monitoring verification from CLI

The console is the preferred way to demonstrate monitoring visually, but the CLI can be used to verify the configuration.

List dashboards:

```bash
aws cloudwatch list-dashboards \
  --region us-east-1
```

List staging alarms:

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix devops-portfolio-staging \
  --region us-east-1
```

Check the running-task alarm:

```bash
aws cloudwatch describe-alarms \
  --alarm-names devops-portfolio-staging-ecs-running-tasks-below-desired \
  --region us-east-1
```

Check ECS service health:

```bash
aws ecs describe-services \
  --cluster devops-portfolio-staging-cluster \
  --services devops-portfolio-staging-app-service \
  --region us-east-1
```

CLI verification is useful for troubleshooting, while the CloudWatch Console is better for the final project demonstration.

---

# 19. Testing

### Application tests

```bash
cd application
npm install
npm test
```

### Smoke test

```bash
./scripts/smoke-test.sh "http://<ALB_DNS>"
```

The smoke test checks:

```text
GET /
GET /health
```

and expects HTTP 200 responses.

### ECS service

```bash
aws ecs describe-services \
  --cluster devops-portfolio-staging-cluster \
  --services devops-portfolio-staging-app-service \
  --region us-east-1
```

### ALB target health

```bash
TG_ARN=$(aws elbv2 describe-target-groups \
  --names devops-portfolio-staging-tg \
  --region us-east-1 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

aws elbv2 describe-target-health \
  --target-group-arn "$TG_ARN" \
  --region us-east-1
```

The target should report:

```text
healthy
```

---

# 20. Validation checklist

Before considering the project complete:

### Local application

```bash
cd application
npm install
npm test
```

### Docker

```bash
docker build -f docker/Dockerfile \
  -t devops-portfolio-app:local .
```

### Terraform

Run in the relevant Terraform directory:

```bash
terraform fmt -check
terraform validate
terraform plan
```

Expected result when the deployed staging infrastructure matches the configuration:

```text
No changes.
Your infrastructure matches the configuration.
```

### ECS

Confirm:

```text
desired = 1
running = 1
pending = 0
status  = ACTIVE
```

### ALB

Confirm the target is:

```text
healthy
```

### Application

```bash
./scripts/smoke-test.sh "http://<STAGING_ALB_DNS>"
```

### CloudWatch

Confirm:

- Infrastructure dashboard exists
- Application dashboard exists
- Staging alarms exist
- ECS logs are available
- Running-task alarm is `OK`

### Git

```bash
git status
```

Expected:

```text
nothing to commit, working tree clean
```

---

# 21. Troubleshooting

## Terraform AWS authentication error

Run:

```bash
aws sts get-caller-identity
```

If using SSO:

```bash
aws sso login
```

Then retry Terraform.

If you see a `Signature expired` error, check that the local machine's system clock is correct and refresh AWS credentials.

---

## CloudWatch shows no alarms

Check the AWS Console region.

The staging environment is in:

```text
us-east-1
```

If the console is showing another region such as:

```text
ap-southeast-2
```

the staging alarms will not appear.

---

## ECS task is not running

Check the service:

```bash
aws ecs describe-services \
  --cluster <cluster-name> \
  --services <service-name> \
  --region us-east-1
```

Then check the task:

```bash
aws ecs list-tasks \
  --cluster <cluster-name> \
  --region us-east-1
```

and:

```bash
aws ecs describe-tasks \
  --cluster <cluster-name> \
  --tasks <task-arn> \
  --region us-east-1
```

Look at:

```text
lastStatus
healthStatus
stoppedReason
```

---

## ALB target is unhealthy

Check:

- ECS container is running
- Application listens on the configured container port
- `/health` returns HTTP 200
- ECS security group allows traffic from the ALB security group
- Target group health check configuration is correct

---

## ECS cannot pull the image

Check:

- ECR image tag exists
- ECS task execution role has ECR permissions
- ECS task has network access through the configured networking/NAT path

---

## GitHub Actions cannot authenticate to AWS

Check:

- GitHub repository name
- GitHub organization/user name
- OIDC provider exists
- IAM role trust policy
- GitHub Environment configuration
- deployment role ARN configured in GitHub
- workflow permissions include the required OIDC token permission

The project intentionally uses OIDC instead of storing AWS access keys in GitHub.

---

## RDS connection fails

Check:

- RDS is available
- ECS and RDS are in the expected VPC
- RDS security group allows PostgreSQL traffic from the ECS security group
- Secrets Manager secret exists
- ECS task execution role can read the database secret

---

# 22. Cleanup

When finished testing, destroy the environment so that unnecessary AWS resources do not continue generating charges.

For staging:

```bash
./scripts/cleanup.sh staging
```

For production, only if production resources were actually deployed:

```bash
./scripts/cleanup.sh prod
```

The Terraform state bucket is intentionally separate from the environment cleanup.

Do not delete it until the project is completely finished.

Before deleting the state bucket, verify that no Terraform state still depends on it.

---

# 23. Cost considerations

This project intentionally keeps staging small.

Current staging configuration uses:

```text
ECS desired tasks: 1
ECS task CPU:       156
ECS task memory:    512 MB
RDS:                db.t4g.micro
RDS Multi-AZ:       false
ECS min capacity:   1
```

AWS resources can still generate charges.

The main cost areas are:

| Resource | Main cost driver |
|---|---|
| NAT Gateway | Hourly charge + data processing |
| RDS | Instance hours + storage |
| ALB | Hourly charge + load balancer capacity units |
| ECS Fargate | CPU/memory usage while tasks run |
| CloudWatch | Logs, dashboards, and metrics |
| ECR | Image storage |

For an assignment/demo environment, it is better to deploy only what is needed and clean it up after testing.

---

# 24. Security considerations

The project includes several basic security practices:

- GitHub Actions uses OIDC instead of long-lived AWS access keys
- ECS tasks run in private application subnets
- RDS is placed in private database subnets
- Security groups are used between ALB → ECS → RDS
- Database credentials are managed through Secrets Manager
- Container runs as a non-root user
- IAM roles are separated for ECS task execution and application tasks
- `iam:PassRole` is limited to the ECS roles
- ECR image tags are immutable
- Terraform state is stored remotely in S3

HTTPS, ACM, WAF, VPC Flow Logs, and some other production hardening measures are documented as future improvements rather than being required for this assignment.

See:

```text
docs/SECURITY.md
```

---

# 25. Assumptions and limitations

This is a portfolio/assignment project rather than a large production platform.

Current limitations include:

- HTTP is used instead of HTTPS
- One NAT Gateway is used to reduce cost
- Staging uses one ECS task
- Staging RDS is not Multi-AZ
- Production deployment is optional
- Both environments are designed for the same AWS account
- The sample application contains minimal business logic
- Rollback is handled through ECS deployment behavior/manual operational steps rather than a fully automated production rollback workflow

These are deliberate scope/cost decisions rather than missing core components.

---

# 26. Future improvements

Possible next steps:

- HTTPS using ACM
- Route 53 DNS
- AWS WAF
- VPC Flow Logs
- GuardDuty
- Separate AWS accounts for staging and production
- Blue/green deployments
- Automated production rollback
- More application-level metrics
- Integration tests with a temporary database
- Automated infrastructure security scanning
- Container vulnerability scanning gates in CI/CD

---

# 27. Important DevOps concepts demonstrated

### VPC

Provides the isolated AWS network for the application.

### Public subnet

Has a route to the Internet Gateway. The ALB is placed here so users can reach the application.

### Private application subnet

ECS tasks run here and are not directly exposed to the internet.

### Private database subnet

RDS runs here and is not directly reachable from the internet.

### NAT Gateway

Allows private application resources to make outbound connections without exposing them directly to the internet.

### Security group

Acts as a stateful firewall around AWS resources.

The project uses:

```text
Internet
   |
   v
ALB Security Group
   |
   v
ECS Security Group
   |
   v
RDS Security Group
```

### ECS

Runs and maintains the desired number of application containers.

### Fargate

Runs ECS containers without requiring us to manage EC2 instances.

### ALB

Provides the public HTTP entry point and routes requests to healthy ECS targets.

### ECR

Stores Docker images used by ECS.

### RDS

Provides the managed PostgreSQL database.

### Secrets Manager

Stores sensitive database credentials.

### IAM

Controls which AWS identities can perform which actions.

### GitHub OIDC

Allows GitHub Actions to obtain short-lived AWS credentials without storing an AWS access key and secret key in GitHub.

### Terraform modules

Keep reusable infrastructure definitions separate from environment-specific configuration.

### Remote state

Stores Terraform state centrally in S3 instead of only on the developer's local machine.

### CloudWatch

Provides logs, dashboards, and alarms for the deployed application.

---

# 28. Interview questions

## Networking

### 1. Why use multiple Availability Zones?

To improve availability. Resources can be distributed across more than one AZ so that an AZ-level issue does not automatically take down the whole application.

### 2. Why use a NAT Gateway?

ECS tasks are in private subnets. NAT allows them to make outbound connections without assigning public IP addresses to the application tasks.

### 3. Why is the database private?

The database does not need to be publicly accessible. Only the application security group should be allowed to connect to it.

### 4. Why use security-group references?

Instead of allowing an entire CIDR range, the RDS security group can allow PostgreSQL traffic specifically from the ECS security group.

---

## ECS and Docker

### 5. Why use Fargate?

Fargate removes the need to manage EC2 instances. For a small portfolio project, this makes the infrastructure simpler.

### 6. Why use `target_type = "ip"`?

Fargate tasks use their own network interfaces/IP addresses, so the ALB target group uses IP targets.

### 7. Why use a Docker multi-stage build?

It helps keep the final runtime image smaller by separating build dependencies from runtime content.

### 8. Why run the container as a non-root user?

It reduces the impact of a possible application/container compromise.

---

## Database

### 9. How are database credentials handled?

RDS/Secrets Manager manages the credentials, and the ECS task definition references the secret instead of hard-coding the password into the application configuration.

### 10. Why is staging RDS not Multi-AZ?

This is a cost decision. Staging is used for testing and demonstration, so the additional Multi-AZ cost is not necessary for this assignment.

---

## CI/CD and IAM

### 11. Why use GitHub OIDC?

It avoids storing long-lived AWS access keys in GitHub. GitHub Actions receives temporary credentials through AWS STS.

### 12. What does the OIDC trust policy do?

It controls which GitHub identity is allowed to assume the AWS deployment role.

### 13. What is the ECS task execution role?

It is used by ECS to perform tasks such as pulling the image, reading required secrets, and writing container logs.

### 14. What is the ECS task role?

It is the IAM role available to the application code inside the container if the application needs to call AWS APIs.

### 15. Why is `iam:PassRole` restricted?

The GitHub deployment role should only be able to pass the specific ECS roles needed for deployment.

---

## Terraform

### 16. Why use Terraform modules?

Modules make the infrastructure reusable and keep environment configuration easier to understand.

### 17. Why use remote state?

Remote state provides a shared and durable location for Terraform state.

### 18. Why use state locking?

It prevents multiple Terraform operations from modifying the same state at the same time.

---

## Monitoring

### 19. Why use CloudWatch?

It is already integrated with AWS services such as ECS, ALB, and RDS, so it provides monitoring without deploying another monitoring platform.

### 20. Why have separate infrastructure and application dashboards?

The infrastructure dashboard focuses on AWS resource health, while the application dashboard focuses more on application traffic, errors, latency, and logs.

---

# 29. Final project demonstration flow

For a short project walkthrough/video, use this order:

```text
1. GitHub repository
       |
2. Repository structure
       |
3. Terraform modules
       |
4. GitHub Actions workflow
       |
5. OIDC/IAM configuration
       |
6. ECR image
       |
7. ECS service
       |
8. ALB
       |
9. Application /health endpoint
       |
10. CloudWatch Infrastructure dashboard
       |
11. CloudWatch Application dashboard
       |
12. CloudWatch alarms
       |
13. CloudWatch logs
       |
14. Explain production is optional to control AWS costs
```

The main thing to demonstrate is the complete working path:

```text
Code
  ↓
GitHub Actions
  ↓
OIDC
  ↓
ECR
  ↓
ECS Fargate
  ↓
ALB
  ↓
Application
  ↓
RDS

and

ECS / ALB / RDS
  ↓
CloudWatch
  ↓
Dashboards + Logs + Alarms
```

---

## 30. Final status

### Staging

**Validated and working.**

Current validation includes:

- Terraform validation passed
- Terraform plan reports no changes
- ECS service is `ACTIVE`
- Desired tasks = `1`
- Running tasks = `1`
- ALB target is healthy
- `/health` returns HTTP 200
- `/` returns HTTP 200
- Database reports `ok`
- Smoke test passed
- CloudWatch dashboards exist
- CloudWatch staging alarms exist
- ECS CloudWatch log group exists
- Git working tree is clean

### Production

**Configuration exists but deployment is optional.**

Production is intentionally not kept running for the final demonstration because the project is an assignment/portfolio environment and additional AWS resources would create additional costs.

---

## Questions or issues?

Check the troubleshooting section first, then review the relevant Terraform module under:

```text
infrastructure/modules/
```
