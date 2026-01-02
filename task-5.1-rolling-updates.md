# Task 5.1: Rolling Updates & Rollbacks in Docker Swarm

This document explains Docker Swarm's update and rollback strategies, as required by Task 5.1.

## 1. Zero-Downtime Rolling Update

The `backend` service in `docker-compose.yml` is configured for zero-downtime rolling updates using the `update_config` section:

```yaml
services:
  backend:
    # ...
    deploy:
      update_config:
        parallelism: 2
        delay: 10s
        failure_action: rollback
```

- `parallelism: 2`: Swarm will update 2 replicas at a time.
- `delay: 10s`: Swarm will wait 10 seconds between updating each set of replicas.

### Performing a Rolling Update

To perform a rolling update, you can change any property of the service, such as an environment variable or the image tag.

For example, let's update an environment variable in `docker-compose.yml`:

```yaml
services:
  backend:
    environment:
      - NEW_ENV_VAR=some_value
```

Then, redeploy the stack:

```bash
docker stack deploy -c docker-compose.yml my_app_stack
```

You can monitor the update process with:

```bash
docker service ps my_app_stack_backend
```

This will show the old replicas being shut down and the new ones being started, two at a time.

## 2. Simulating a Failed Deployment and Automatic Rollback

The `update_config` is also configured with `failure_action: rollback`. This means that if an update fails, Swarm will automatically roll back to the previous version.

To simulate a failure, we can introduce a change that will cause the service to fail its health check. For example, change the `healthcheck` command in `docker-compose.yml` to something that will always fail:

```yaml
services:
  backend:
    healthcheck:
      test: ["CMD-SHELL", "exit 1"]
```

Now, redeploy the stack:

```bash
docker stack deploy -c docker-compose.yml my_app_stack
```

If you monitor the service with `docker service ps my_app_stack_backend`, you will see the new tasks failing their health checks. After a few failures, Swarm will trigger an automatic rollback to the previous, healthy version.

## 3. Explanation of Update Configuration Options

- **`update-parallelism`**: The number of service tasks to update simultaneously. A value of `1` means one replica is updated at a time, which is the safest option but also the slowest.
- **`update-delay`**: The time to wait between updating a group of service tasks. This gives you time to observe the new tasks and make sure they are healthy before continuing the update.
- **`update-failure-action`**: The action to take if an update fails.
    - `pause` (default): Pauses the update and leaves the service in a mixed state. You can then manually intervene.
    - `continue`: Continues the update regardless of failures.
    - `rollback`: Automatically rolls back to the previous version.

## 4. Manual Rollback

If you need to manually roll back a service to its previous version (e.g., if you deployed with `failure_action: pause` or if you discover a bug after a successful deployment), you can use the `docker service rollback` command:

```bash
docker service rollback my_app_stack_backend
```

This will trigger a rollback to the previous version of the service, using the `rollback_config` defined in the `docker-compose.yml` file.
