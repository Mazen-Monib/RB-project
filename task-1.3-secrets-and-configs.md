# Task 1.3: Docker Swarm Secrets & Configs

This document explains the commands and procedures for managing secrets and configs in a Docker Swarm environment, as required by Task 1.3 of the assignment.

## 1. Creating Docker Secrets

The `docker-compose.yml` file has been updated to use the following external secrets for the database credentials:
- `postgres_user`
- `postgres_password`
- `postgres_db`

These secrets must be created in the Docker Swarm manager node before deploying the stack.

**Commands to create the secrets:**

```bash
# Create the postgres_user secret
echo "my_user" | docker secret create postgres_user -

# Create the postgres_password secret
echo "my_strong_password" | docker secret create postgres_password -

# Create the postgres_db secret
echo "my_database" | docker secret create postgres_db -
```

You can verify that the secrets have been created with `docker secret ls`.

## 2. Using Docker Configs for Application Configuration

Docker Configs are useful for managing application configuration files that are not sensitive, such as a logging configuration or a Nginx `vhost` file.

Let's assume the backend application has a configuration file at `/usr/src/app/config/app-config.json`. We can manage this file using a Docker Config.

**Step 1: Create the configuration file**

Create a file named `app-config.json` with some configuration:

```json
{
  "logLevel": "info",
  "featureFlags": {
    "newAuth": true
  }
}
```

**Step 2: Create the Docker Config**

```bash
docker config create app_config app-config.json
```

**Step 3: Update `docker-compose.yml` to use the config**

```yaml
services:
  backend:
    # ... (other service configuration)
    configs:
      - source: app_config
        target: /usr/src/app/config/app-config.json
# ...
configs:
  app_config:
    external: true
```

The `target` path is where the config file will be mounted inside the container.

## 3. Rotating Secrets Without Downtime

Docker Swarm allows for updating a service's secrets without taking the service down. The process involves creating a new secret, updating the service to use it, and then removing the old secret.

This is the process for rotating the `postgres_password` secret:

**Step 1: Create a new version of the secret**

```bash
echo "my_new_strong_password" | docker secret create postgres_password_v2 -
```

**Step 2: Update the service to use the new secret**

First, grant the `postgres` service access to the new secret in the `docker-compose.yml`:

```yaml
services:
  postgres:
    # ...
    secrets:
      - postgres_user
      - postgres_password_v2
      - postgres_db
```

Then, update the running service:

```bash
docker stack deploy --compose-file docker-compose.yml my_stack
```

This will cause a rolling update of the service. Once the new tasks are running with the new secret, you need to update the password in the database itself.

**Step 3: Remove the old secret from the service**

Once the password has been updated in the database and the backend service is also updated to use the new secret, you can remove the old secret from the service definition in `docker-compose.yml`:

```yaml
services:
  postgres:
    # ...
    secrets:
      - postgres_user
      - postgres_password_v2
      - postgres_db
```

And update the stack again:

```bash
docker stack deploy --compose-file docker-compose.yml my_stack
```

**Step 4: Remove the old secret from the Swarm**

Finally, you can safely remove the old secret from the Swarm:

```bash
docker secret rm postgres_password
```
