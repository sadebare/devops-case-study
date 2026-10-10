# Helium Health DevOps Engineer Case Study: Containerise, Build And Deploy A REST API To Kubernetes

## Aim of the Project

The purpose of this project is to onboard a new microservice to a platform. I wrote a small REST API, containerised it, built a CI pipeline for it with GitHub Actions, wrote the Kubernetes manifests to deploy it, and provisioned the supporting AWS infrastructure with Terraform.

The application is kept very simple on purpose. The focus is on the infrastructure and the pipeline around it.

## Requirements

+ Docker - To build and run the image locally.
+ Go 1.24 or newer - Only needed if you want to run the app or its tests outside Docker.
+ kubectl - A command line interface to interact with the Kubernetes cluster.
+ Terraform 1.10 or newer - To provision the AWS resources.
+ AWS CLI - To authenticate to AWS.
+ A Kubernetes cluster with the NGINX ingress controller installed and a CNI that enforces NetworkPolicy (for example Calico or Cilium).
+ kind 0.24 or newer - Only needed to run the Kubernetes manifests on a local cluster.

## Project Structure

```
.
├── app/                  # The Go REST API and its tests
├── docker/               # Dockerfile and its .dockerignore
├── .github/workflows/    # GitHub Actions workflow
├── k8s/                  # Kubernetes manifests
├── terraform/
│   ├── bootstrap/        # Creates the S3 bucket for remote state (run once)
│   ├── modules/          # ecr, github-oidc-role, state-bucket
│   └── *.tf              # Root config that uses the modules
└── README.md
```

## Running The Application Locally

There are three ways to run the service on a laptop. Each one builds on the one before it, and we can stop after any of them:

1. With Go - The quickest way to see the API working.
2. With Docker - Runs the same image the CI pipeline builds.
3. On a local Kubernetes cluster (kind) - Applies the real manifests from `k8s/`.

All commands are run from the root of the repository unless stated otherwise. On macOS, the tools can be installed with Homebrew:

```bash
brew install go kind kubectl
brew install --cask docker   #then open Docker Desktop from Applications

#confirm everything is installed
go version
docker version
kind version
kubectl version --client
```

![Tool versions](./docs/images/00-prerequisites.png)

### Option 1: Run With Go

1. First, we run the tests. All of them should show `PASS`.

    ```bash
    cd app
    go test -race -v ./...
    ```

    ![Go tests passing](./docs/images/01-go-test.png)

2. Next, we start the app. It prints a JSON log line saying it is listening on `:8080`. Leave this terminal open.

    ```bash
    go run .
    ```

    ![App listening on 8080](./docs/images/02-go-run.png)

3. In a second terminal, we call the API:

    ```bash
    #health and readiness
    curl -s localhost:8080/healthz
    curl -s localhost:8080/readyz

    #create two items
    curl -s -X POST localhost:8080/api/v1/items -d '{"name":"stethoscope"}'
    curl -s -X POST localhost:8080/api/v1/items -d '{"name":"thermometer"}'

    #list all items, then get one by id
    curl -s localhost:8080/api/v1/items
    curl -s localhost:8080/api/v1/items/1
    ```

    The expected output is:

    ```
    {"status":"ok","version":"dev"}
    {"status":"ready"}
    {"id":1,"name":"stethoscope"}
    {"id":2,"name":"thermometer"}
    [{"id":1,"name":"stethoscope"},{"id":2,"name":"thermometer"}]
    {"id":1,"name":"stethoscope"}
    ```

    ![curl requests against the Go app](./docs/images/03-go-curl.png)

4. Lastly, we press `Ctrl+C` in the first terminal. The app logs `shutting down` and waits 5 seconds (`SHUTDOWN_DELAY`) before it exits. This is the graceful shutdown the readiness probe relies on in Kubernetes. Run `cd ..` to go back to the root of the repository.

    ![Graceful shutdown](./docs/images/04-go-shutdown.png)

### Option 2: Run With Docker

Docker Desktop must be running for this option.

1. First, we build the image. The `VERSION` build argument is what `/healthz` reports.

    ```bash
    docker build -f docker/Dockerfile -t items-api:dev --build-arg VERSION=local .
    ```

    ![Docker build](./docs/images/05-docker-build.png)

2. Next, we confirm the image is small and does not run as root:

    ```bash
    docker images items-api:dev
    docker inspect items-api:dev --format 'User: {{.Config.User}}'   #should print User: 65532:65532
    ```

    ![Image size and user](./docs/images/06-docker-image.png)

3. Now we run the container. This time we set `API_TOKEN`, so creating an item needs a token.

    ```bash
    docker run --rm --name items-api -p 8080:8080 -e API_TOKEN=local-token items-api:dev
    ```

    ![Container running](./docs/images/07-docker-run.png)

4. In a second terminal, we call the API. The first POST returns `401` because there is no token, and the second returns `201`.

    ```bash
    curl -s localhost:8080/healthz   #version is now "local"

    #without a token: 401 Unauthorized
    curl -s -i -X POST localhost:8080/api/v1/items -d '{"name":"stethoscope"}'

    #with the token: 201 Created
    curl -s -i -X POST localhost:8080/api/v1/items \
      -H 'Authorization: Bearer local-token' -d '{"name":"stethoscope"}'

    curl -s localhost:8080/api/v1/items
    ```

    ![Docker curl with auth](./docs/images/08-docker-curl.png)

5. Optionally, we can scan the image the same way the pipeline does:

    ```bash
    brew install trivy
    trivy image --severity HIGH,CRITICAL --ignore-unfixed items-api:dev
    ```

    ![Trivy scan](./docs/images/09-trivy.png)

6. Lastly, we stop the container with `Ctrl+C` or `docker stop items-api`.

### Option 3: Run On A Local Kubernetes Cluster (kind)

Here we apply the same manifests used in production to a cluster that runs inside Docker. The default network plugin in kind 0.24 and newer enforces NetworkPolicy, so the policies in `k8s/networkpolicy.yaml` are active.

1. First, we create the cluster:

    ```bash
    kind create cluster --name items-api
    kubectl get nodes
    ```

    ![kind cluster created](./docs/images/10-kind-create.png)

2. kind cannot see the images in our local Docker, so we load the image built in Option 2 into the cluster:

    ```bash
    kind load docker-image items-api:dev --name items-api
    ```

    ![Image loaded into kind](./docs/images/11-kind-load.png)

3. Next, we apply the manifests. `k8s/kustomization.yaml` points to the ECR image, so instead of editing that file we render the manifests, swap in the local image and apply the result:

    ```bash
    kubectl kustomize k8s/ \
      | sed 's#123456789012.dkr.ecr.eu-west-1.amazonaws.com/items-api:REPLACE_WITH_COMMIT_SHA#items-api:dev#' \
      | kubectl apply -f -
    ```

    ![Manifests applied](./docs/images/12-kubectl-apply.png)

4. We wait for the rollout and check what was created. Both pods should be `Running` and `1/1`. The Ingress has no address, which is expected because there is no NGINX ingress controller in this cluster.

    ```bash
    kubectl -n items-api rollout status deployment/items-api
    kubectl -n items-api get pods,svc,ingress,networkpolicy,configmap,secret,pdb
    ```

    ![Resources in the namespace](./docs/images/13-kubectl-get.png)

5. Now we call the API through the Service with a port-forward:

    ```bash
    kubectl -n items-api port-forward svc/items-api 8080:80
    ```

    In a second terminal (the token is the placeholder `REPLACE_ME` from `k8s/secret.yaml`):

    ```bash
    curl -s localhost:8080/healthz
    curl -s -X POST localhost:8080/api/v1/items \
      -H 'Authorization: Bearer REPLACE_ME' -d '{"name":"stethoscope"}'
    curl -s localhost:8080/api/v1/items
    ```

    ![curl through port-forward](./docs/images/14-k8s-curl.png)

6. To confirm the NetworkPolicy works, we start a temporary pod in the same namespace and try to reach the API. Only the ingress-nginx pods are allowed in, so the request should time out. The long `--overrides` flag is there because the namespace enforces the `restricted` Pod Security Standard and rejects pods without these settings.

    ```bash
    kubectl -n items-api run np-test --rm -it --restart=Never --image=curlimages/curl:8.10.1 \
      --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"np-test","image":"curlimages/curl:8.10.1","args":["-s","-m","5","http://items-api/healthz"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
    ```

    ![NetworkPolicy blocking traffic](./docs/images/15-networkpolicy.png)

7. Lastly, we delete the cluster:

    ```bash
    kind delete cluster --name items-api
    ```

**Troubleshooting**

| Problem | Fix |
|---|---|
| `address already in use` on port 8080 | Something else is using the port. Use another one, for example `PORT=9090 go run .` or `-p 9090:8080`. |
| `Cannot connect to the Docker daemon` | Docker Desktop is not running. Open it and wait for it to start. |
| Pods stuck in `ImagePullBackOff` | The image was not loaded into kind, or the `sed` did not match. Run step 2 again and confirm the image with `kubectl -n items-api get deploy items-api -o jsonpath='{..image}'`, which should print `items-api:dev`. |
| POST returns `401` | Send the header `Authorization: Bearer <API_TOKEN>`. In the cluster the token is `REPLACE_ME`. |

## Procedures

### 1. The Application

I wrote a minimal REST API in Go using only the standard library. I chose this because there are no third-party packages to patch or scan, and it compiles to a single binary, which makes the container image very small.

| Method | Path | What it does |
|---|---|---|
| GET | `/healthz` | Liveness check |
| GET | `/readyz` | Readiness check |
| GET | `/api/v1/items` | List all items |
| GET | `/api/v1/items/{id}` | Get one item |
| POST | `/api/v1/items` | Create an item |

We can run the tests and start the app locally with the commands below:

```bash
cd app

#run the tests
go test -race ./...

#start the app, it listens on port 8080
go run .

#in another terminal, confirm it is up
curl localhost:8080/healthz
```

The app reads its configuration from environment variables (`PORT`, `LOG_LEVEL`, `SHUTDOWN_DELAY` and `API_TOKEN`). If `API_TOKEN` is set, creating an item needs the header `Authorization: Bearer <token>`.

### 2. Containerisation

The Dockerfile is at [docker/Dockerfile](./docker/Dockerfile). We build it from the root of the repository:

```bash
#build the image
docker build -f docker/Dockerfile -t items-api:dev .

#run it
docker run --rm -p 8080:8080 items-api:dev
```

What I did here to follow best practices:

+ Multi-stage build. The first stage has the Go toolchain and compiles the binary. The final stage only copies that binary, so the build tools never end up in the image we ship.
+ Minimal base image. The final stage uses `gcr.io/distroless/static-debian12`. It has no shell and no package manager, so there is very little in it that can be attacked.
+ Non-root user. The container runs as user `65532` and not as root.
+ `.dockerignore` file. Only the `app/` folder is sent to Docker when building.

One thing to note about the `.dockerignore`. Because we build from the root of the repository, Docker would not read a `.dockerignore` placed inside the `docker/` folder. To keep it in that folder as suggested, I named it `Dockerfile.dockerignore`, which Docker picks up automatically for a Dockerfile of the same name.

### 3. CI Pipeline (GitHub Actions)

The workflow is at [.github/workflows/ci.yml](./.github/workflows/ci.yml).

**How to trigger the pipeline**

The pipeline is triggered in two ways:

1. When a pull request is opened or updated against `main`.
2. When a pull request is merged (a push) to `main`.

```bash
#create a branch and make a change
git checkout -b my-change
git commit -am "my change"
git push -u origin my-change

#open a pull request on GitHub, this triggers the pipeline
#merging the pull request triggers it again and this time the image is pushed
```

**What the pipeline does**

1. Lint and test the application (`gofmt`, `go vet`, `golangci-lint` and `go test`).
2. Check the Terraform code with `terraform fmt` and `terraform validate`.
3. Build the Docker image and tag it with the git commit SHA.
4. Scan the image with Trivy. The pipeline fails if there is a HIGH or CRITICAL vulnerability that has a fix available. The full result is also uploaded to the Security tab of the repository.
5. Push the image to ECR. This step only runs on a merge to `main`.

I decided to push the image only on a merge to `main` and only after the scan has passed. On a pull request the image is still built and scanned, but it is not pushed. This way an image that has not been reviewed, or that failed the scan, never gets to the registry.

**Credentials**

No AWS access key or secret key is stored anywhere, not even in GitHub secrets. The pipeline uses OIDC, where GitHub asks AWS for temporary credentials that expire after one hour. The IAM role it assumes is created by Terraform in step 5, and it can only be assumed from the `main` branch of this repository.

For this to work, we need to add three repository variables in GitHub under Settings > Secrets and variables > Actions > Variables after running Terraform:

| Variable | Where to get it |
|---|---|
| `AWS_ROLE_ARN` | `terraform output -raw ci_role_arn` |
| `AWS_REGION` | `terraform output -raw aws_region` |
| `ECR_REPOSITORY` | `terraform output -raw ecr_repository_name` |

Also, every action used in the workflow is pinned to a commit SHA and not a tag, so the code we run cannot be changed without us knowing.

### 4. Kubernetes Manifests

The manifests are in the [k8s](./k8s) folder. I used a `kustomization.yaml` so that everything can be applied with a single command and the image is set in one place.

**How to apply the manifests**

1. First, we point the deployment to the image that the pipeline pushed. Open `k8s/kustomization.yaml` and update the `images` section with your ECR registry and the commit SHA tag (the pipeline prints the tag at the end of its run).

2. We also need to replace the placeholder values, which are the hostname in `k8s/ingress.yaml` and the value in `k8s/secret.yaml`.

3. Now we can apply the manifests:

    ```bash
    #optional, to see what will be created
    kubectl diff -k k8s/

    #apply everything
    kubectl apply -k k8s/
    ```

4. Lastly, we confirm the deployment is running:

    ```bash
    kubectl -n items-api rollout status deployment/items-api
    kubectl -n items-api get pods,svc,ingress,networkpolicy

    #to test the app without going through the ingress
    kubectl -n items-api port-forward svc/items-api 8080:80
    curl localhost:8080/healthz
    ```

**What was created**

+ Namespace - `items-api`, with the restricted Pod Security Standard enforced.
+ Deployment - 2 replicas with resource requests and limits, plus startup, liveness and readiness probes. The container runs as non-root with a read-only filesystem and all Linux capabilities dropped.
+ Service - A ClusterIP service on port 80 that forwards to the container on port 8080.
+ Ingress - Exposes only the `/api` path through NGINX with TLS. The health endpoints are not exposed to the internet.
+ NetworkPolicy - Explained below.
+ ConfigMap - The non-sensitive configuration of the app.
+ Secret - A placeholder for the API token.
+ ServiceAccount and PodDisruptionBudget - A dedicated service account with no token mounted, and a budget that keeps at least one pod running when a node is drained.

**NetworkPolicy**

I first deny all traffic in and out of the namespace, then allow only what the service requires:

+ Ingress: only from the NGINX ingress controller pods, on port 8080.
+ Egress: only to the cluster DNS on port 53.

The app keeps its data in memory and does not call any other service, so that is all it needs. If we add a database later, we add one more rule for it.

**Probes**

The liveness and readiness probes use different endpoints. Liveness (`/healthz`) tells Kubernetes if the container should be restarted. Readiness (`/readyz`) tells Kubernetes if the pod should receive traffic. When the pod is shutting down, readiness fails first so that traffic stops coming before the app exits.

**Secrets**

The `secret.yaml` file only has a placeholder value (`REPLACE_ME`). A real secret should never be committed to git. In a real setup I would store the value in AWS Secrets Manager and use External Secrets Operator to sync it into the cluster.

### 5. Infrastructure as Code (Terraform)

I provisioned all three with Terraform, and each one is a reusable module in [terraform/modules](./terraform/modules):

+ `state-bucket` - An S3 bucket for the Terraform remote state. It is versioned, encrypted and blocked from public access.
+ `ecr` - The container registry. It has a lifecycle policy that deletes untagged images after 7 days and keeps only the last 30 images. Tags are immutable, so a tag cannot be overwritten.
+ `github-oidc-role` - The IAM role for the CI pipeline. It can only log in to ECR and push images to this one repository. It cannot delete images or touch any other AWS service.

**How to run it**

1. First, we authenticate to AWS:

    ```bash
    aws configure
    ```

2. We need the S3 bucket to exist before we can use it as a remote backend, so we create it first from the `bootstrap` folder. This is only done once.

    ```bash
    cd terraform/bootstrap
    terraform init
    terraform apply -var 'state_bucket_name=YOUR_BUCKET_NAME'
    ```

3. Now that we have the bucket, we can provision the ECR repository and the IAM role, with the state stored remotely in that bucket:

    ```bash
    cd ..

    #copy the example files and fill in your values
    cp backend.hcl.example backend.hcl
    cp terraform.tfvars.example terraform.tfvars

    terraform init -backend-config=backend.hcl
    terraform plan
    terraform apply
    ```

4. Lastly, we get the outputs and add them as repository variables in GitHub as shown in step 3:

    ```bash
    terraform output
    ```

The bucket name and region for the backend are passed in through `backend.hcl` and not hardcoded, because they are different for every AWS account. Both `backend.hcl` and `terraform.tfvars` are in `.gitignore`.

State locking uses the S3 lock file (`use_lockfile = true`), so there is no need for a DynamoDB table.

### Migration Question: Importing An Existing Resource Into Terraform

Importing a resource only adds it to the Terraform state. It does not change the resource in AWS, so the import on its own cannot cause downtime. The danger is the first `terraform apply` after the import. If my code does not match what is really in AWS, Terraform will try to change the resource, and for some settings that means deleting and recreating it.

So my approach is to make sure the plan shows no changes before I apply anything:

1. First, I make sure nobody is changing the resource manually while I work on it, then I check its current configuration from the console or with the AWS CLI.

2. I write the Terraform code to match exactly what exists right now, even if it is not how I would have set it up. Improvements come later.

3. I add an `import` block in the code so the import goes through a pull request and is reviewed like any other change:

    ```hcl
    import {
      to = module.ecr.aws_ecr_repository.this
      id = "items-api"
    }
    ```

4. I run `terraform plan` and keep adjusting the code until the plan says `1 to import, 0 to add, 0 to change, 0 to destroy`. If I see "forces replacement" anywhere in the plan, I stop and fix the code. I do not apply it.

5. As a safety net, I add `prevent_destroy = true` on the resource, and I confirm versioning is enabled on the state bucket so I can go back to the previous state if something goes wrong.

6. I apply the import on its own with no other change, then run `terraform plan` again to confirm it shows nothing to change.

7. Any improvement to the resource is done afterwards in a separate pull request.

## Assumptions

+ AWS is the cloud provider, with one account and one region (`eu-west-1` by default).
+ The Kubernetes cluster already exists (for example EKS) and its nodes can pull images from ECR. Creating the cluster is not part of this task.
+ The NGINX ingress controller is installed in the `ingress-nginx` namespace.
+ DNS and the TLS certificate for the ingress hostname are handled by the platform (I assumed cert-manager).
+ Terraform is run by an engineer with the right permissions. The CI role cannot create or change infrastructure.

## Trade-offs And Shortcuts

+ The pipeline stops at pushing the image. Deploying to the cluster is done manually with `kubectl apply`. I did not want to give the pipeline access to the cluster. I would use GitOps for this instead.
+ There is only one environment. There is no separate dev, staging and production.
+ I did not set a CPU limit on the container, only a CPU request and a memory limit. A CPU limit can slow the app down even when the node has free CPU. If the platform requires one, it is a one line change in the deployment.
+ The Trivy scan ignores vulnerabilities that do not have a fix yet, because failing the pipeline on something we cannot fix only blocks the team. They still show up in the Security tab.
+ The base images are pinned by tag and not by digest.
+ The image is built for `linux/amd64` only.
+ The image is not signed and no SBOM is generated.
+ The app stores data in memory, so the data is lost when the pod restarts. This is fine for a sample app.
+ The `bootstrap` folder keeps its state locally. It can be moved to the bucket afterwards with `terraform init -migrate-state`.
+ There is no autoscaling (HPA). The deployment is fixed at 2 replicas.

## What I Would Do Next

+ GitOps - Use Argo CD to watch the manifests in git and deploy to the cluster. The pipeline would then only update the image tag in git, and a rollback is a `git revert`.
+ Observability - Expose a `/metrics` endpoint for Prometheus, build dashboards in Grafana and set up alerts on error rate and latency.
+ Environments - Add Kustomize overlays for dev, staging and production.
+ Terraform in the pipeline - Run `terraform plan` on pull requests and `terraform apply` on merge.
