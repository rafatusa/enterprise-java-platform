# Java Spring Boot API on AWS EC2

A Spring Boot service built with Maven on a dedicated Ubuntu EC2 instance, run under systemd behind nginx.

## What you inherit

- EC2 + Elastic IP + security group as Terraform under `infra/`
- Ansible configuration: OpenJDK 17, Maven build, systemd unit, nginx
- Health-checked verify stage

## What the Build Agent tailors

- Your controllers/services under `src/main/java`
- Instance size, region

## Deploy behaviour

The pipeline provisions infrastructure with Terraform (state lives in the
platform-managed bucket, keyed by project), configures the server, and verifies
`/health` before the run goes green. Destroy tears down everything the template
created — the repository and its configuration survive for redeploys.
