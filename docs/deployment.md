# Deployment Guide

This document describes the deployment architecture, configuration, and procedures for the Vivvo application.

## Overview

The application uses a containerized deployment approach with Docker and GitHub Actions. Deployments are automated through GitHub workflows and can be triggered in three different ways:

1. **Automatic Testing Deployment**: Triggered automatically after successful CI runs on the `main` branch
2. **Manual Deployment**: Triggered manually via GitHub Actions with environment selection
3. **Automatic Production Deployment**: Triggered automatically when a new release is published

### Deployment Architecture

```
GitHub Repository
    │
    ├── CI Workflow (on push to main)
    │       │
    │       └── Success ──► Deploy to Testing
    │
    ├── Manual Dispatch (workflow_dispatch)
    │       │
    │       ├── Testing ──► Deploy to Testing Environment
    │       └── Production ──► Deploy to Production Environment (tags only)
    │
    └── Release Published
            │
            └── Deploy to Production (using release tag)
```

### Key Characteristics

- **Environment Isolation**: Testing and production use separate GitHub Environments with isolated secrets and variables
- **Immutable Deployments**: Each deployment pulls the latest code from the repository and builds a new Docker image
- **Brief Downtime During Deployments**: Services are briefly stopped and restarted during deployment
- **Data Preservation**: Production deployments preserve database and volume data; testing deployments reset all data

## Environments

### Testing Environment

The testing environment is designed for continuous integration and development testing.

**Characteristics:**
- **IMAGE_TAG**: Always set to `testing`
- **Data Handling**: Complete reset on each deployment (volumes cleaned, database re-seeded)
- **Purpose**: Integration testing, QA validation, stakeholder demos
- **URL**: Configured via `PHX_HOST` variable

**Deployment Triggers:**
1. Automatic: After successful CI workflow on `main` branch
2. Manual: Via workflow dispatch selecting "testing" environment

### Production Environment

The production environment hosts the live application.

**Characteristics:**
- **IMAGE_TAG**: Set to the release tag being deployed (e.g., `v1.2.3`)
- **Data Handling**: Preserves all data; only runs database migrations
- **Purpose**: Live production application
- **URL**: Configured via `PHX_HOST` variable

**Deployment Triggers:**
1. Automatic: When a new release is published on GitHub
2. Manual: Via workflow dispatch selecting "production" environment (must use a tag, not a branch)

**Important:** Production deployments require a Git tag (release) and will reject branch deployments.

## GitHub Configuration

### Repository Secrets (Shared)

These secrets are used across all environments and should be configured at the repository level:

| Secret | Description | Where to Get It |
|--------|-------------|-----------------|
| `DOCKERHUB_USERNAME` | DockerHub username for pushing images | Your DockerHub account |
| `DOCKERHUB_TOKEN` | DockerHub access token | DockerHub → Account Settings → Security |
| `TAILSCALE_CLIENT_ID` | Tailscale OAuth client ID | Tailscale Admin Console → OAuth clients |
| `TAILSCALE_CLIENT_SECRET` | Tailscale OAuth client secret | Generated when creating OAuth client |
| `MAIL_PASSWORD` | SMTP password for sending emails | Your email provider |

### Environment-Specific Configuration

Configure these in **Settings → Environments** for each environment (`testing` and `production`).

#### Environment Variables

| Variable | Description | Example (Testing) | Example (Production) |
|----------|-------------|-------------------|---------------------|
| `APP_NAME` | Application name | `vivvo` | `vivvo` |
| `APP_PORT` | Port exposed on the host | `4000` | `4000` |
| `PHX_HOST` | Phoenix/Elixir host URL | `test.vivvo.app` | `vivvo.app` |
| `SERVER_TAILSCALE_HOST` | Tailscale hostname of the deployment server | `testing-server.tailnet-name.ts.net` | `prod-server.tailnet-name.ts.net` |
| `MAIL_USER` | SMTP username for sending emails | `noreply@example.com` | `noreply@example.com` |

#### Environment Secrets

| Secret | Description | Example |
|--------|-------------|---------|
| `POSTGRES_USER` | PostgreSQL database username | `vivvo_test` |
| `POSTGRES_PASSWORD` | PostgreSQL database password | *(strong generated password)* |
| `POSTGRES_DB` | PostgreSQL database name | `vivvo_test` |
| `SECRET_KEY_BASE` | Phoenix secret key base (run `mix phx.gen.secret`) | *(64-byte secret)* |

## Deployment Process

### 1. Automatic Testing Deployment

**When:** After every successful CI workflow run on the `main` branch

**What happens:**
1. CI workflow completes successfully
2. Deploy workflow triggers automatically
3. Docker image is built with tag `testing`
4. Image is pushed to DockerHub
5. Tailscale VPN connection is established
6. SSH connection to testing server is made
7. Repository is updated on the server
8. `make deploy.testing` is executed

**Verification:** Check the Actions tab in GitHub to see the deployment status.

### 2. Manual Deployment

**When:** You need to deploy a specific branch or tag on-demand

**Steps:**
1. Go to **Actions → Deploy → Run workflow**
2. Select the environment:
   - **testing**: Can use any branch or tag
   - **production**: Must use a tag (releases only)
3. Enter the branch or tag to deploy:
   - **testing** examples: `main`, `feature/my-branch`, `v1.2.3`, `refs/tags/v1.2.3`
   - **production** examples: `v1.2.3`, `refs/tags/v1.2.3` (must be a release tag; plain tags like `v1.2.3` are accepted)
4. Click **Run workflow**

**What happens:**
- Similar to automatic deployment, but uses your selected ref
- Production deployments will fail if a branch is provided instead of a tag

### 3. Automatic Production Deployment

**When:** A new release is published on GitHub

**Steps:**
1. Create a new release on GitHub (this creates a tag)
2. Publish the release
3. Deploy workflow triggers automatically
4. Docker image is built with the release tag (e.g., `v1.2.3`)
5. Image is deployed to production

**What happens:**
1. Release is published (e.g., `v1.2.3`)
2. Deploy workflow triggers with `IMAGE_TAG=v1.2.3`
3. Image is built and pushed as `username/vivvo:v1.2.3`
4. `make deploy.production` is executed on the production server

## Makefile Commands

The deployment uses a Makefile on the target server with the following targets:

### `make deploy.testing`

Deploys the testing environment with a complete reset:

1. Pulls latest Docker images
2. Stops all services
3. **Cleans volume directories** (data reset)
4. Starts all services
5. Runs database migrations
6. **Runs database seeds** (repopulates data)
7. Cleans old dangling Docker images

**Use case:** Fresh testing environment with clean data.

### `make deploy.production`

Deploys the production environment preserving data:

1. Pulls latest Docker images
2. Stops all services
3. Starts all services (with new image)
4. Runs database migrations
5. Cleans old dangling Docker images

**Use case:** Production deployments where data must be preserved.

### Other Useful Commands

```bash
# Run database migrations manually
make db.migrate

# Rollback last database migration
make db.rollback

# Run database seeds
make db.seed

# Open PostgreSQL shell
make shell.db

# Open IEx remote shell to running app
make shell.app

# Show help
make help
```

## Docker Image Tagging

The deployment workflow uses different image tagging strategies based on the environment:

| Environment | IMAGE_TAG | Example |
|-------------|-----------|---------|
| Testing | `testing` | `username/vivvo:testing` |
| Production | Release tag | `username/vivvo:v1.2.3` |

**Note:** The testing environment always uses the `testing` tag, which means the testing server always pulls the latest testing image. Production uses immutable tags based on release versions.

## Troubleshooting

### Deployment Fails with "Production deployments must use a release tag"

**Cause:** You tried to deploy to production using a branch name or invalid tag format.

**Solution:** Create a release/tag first, then deploy using the tag. Accepted formats are:
- Plain tag: `v1.2.3`
- Full ref: `refs/tags/v1.2.3`

Branch names (like `main` or `feature/xyz`) are not accepted for production deployments.

### Container Fails to Start

**Check:**
1. Environment variables are correctly set in GitHub
2. Secrets are configured for the correct environment
3. Tailscale host is accessible
4. DockerHub credentials are valid

**Debug:**
View the deployment logs in GitHub Actions for detailed error messages.

### Database Migration Failures

**Testing:** Database is reset on each deployment, so migration failures are typically code issues.

**Production:** Migration failures may leave the database in an inconsistent state. Check logs and potentially rollback if needed:

```bash
# On the production server
make db.rollback
```

### SSH Connection Issues

**Check:**
1. Tailscale OAuth client has correct permissions
2. Target server is online in Tailscale
3. `SERVER_TAILSCALE_HOST` variable is correctly set

## Security Considerations

1. **Environment Isolation**: Production and testing secrets are completely isolated through GitHub Environments
2. **Tag Protection**: Production deployments only accept tags, preventing accidental branch deployments
3. **VPN Access**: All server connections go through Tailscale VPN
4. **Secret Management**: Sensitive values are never logged or exposed in workflow outputs
5. **Immutable Tags**: Production uses versioned Docker images for reproducibility

## Best Practices

1. **Testing First**: Always test thoroughly in the testing environment before creating a production release
2. **Versioning**: Use semantic versioning (e.g., `v1.2.3`) for production releases
3. **Release Notes**: Write clear release notes when publishing GitHub releases
4. **Monitoring**: Monitor the production deployment after each release
5. **Rollback Plan**: Keep previous release tags available for quick rollback if needed

## Server Setup

This section describes how to set up a target server for deployments.

### Prerequisites

- Docker and Docker Compose installed
- Tailscale installed and authenticated
- SSH access configured
- `APP_NAME` environment variable configured (must match the value set in GitHub environment variables)

### Repository Setup

The deployment process only needs the `deploy/` directory from the repository. Use sparse checkout to clone only the necessary files:

```bash
# Set your application name (must match APP_NAME in GitHub environment variables)
# IMPORTANT: This environment variable is required and must be persisted!
export APP_NAME=vivvo

# Add to ~/.bashrc or ~/.profile to persist across sessions
echo 'export APP_NAME=vivvo' >> ~/.bashrc

# Create the apps directory
mkdir -p ~/apps
cd ~/apps

# Clone with sparse checkout to only get the deploy/ directory
git clone --filter=blob:none --sparse https://github.com/CimimUxMaio/vivvo.git "$APP_NAME"
cd "$APP_NAME"

# Configure sparse checkout to only include the deploy directory
git sparse-checkout set deploy

# Verify the files are present
ls -la deploy/
```

### Required Directory Structure

After setup, your server should have:

```
~/apps/
└── vivvo/                    # APP_NAME directory
    ├── deploy/
    │   ├── docker-compose.yml
    │   └── Makefile
    └── .git/                 # Git metadata (sparse checkout)
```

### Updating Server Files

When the deploy configuration changes in the repository, update the server:

```bash
cd ~/apps/$APP_NAME
git pull
```

## Configuration Checklist

Before the deployment system will work, ensure:

- [ ] Repository secrets configured (DockerHub, Tailscale, Mail password)
- [ ] `testing` environment created in GitHub with variables and secrets
- [ ] `production` environment created in GitHub with variables and secrets
- [ ] Target servers have Tailscale installed and configured
- [ ] Target servers have Docker and Docker Compose installed
- [ ] `APP_NAME` environment variable is set on target servers (e.g., `export APP_NAME=vivvo` in `~/.bashrc` or `~/.profile`)
- [ ] Target servers have the repository cloned at `~/apps/<APP_NAME>/` using sparse checkout (see [Server Setup](#server-setup))
- [ ] Target servers have the Makefile and docker-compose.yml in the `deploy/` directory
