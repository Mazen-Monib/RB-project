# Task 4.2: Centralized Logging with Fluentd

This document describes the centralized logging architecture using Fluentd.

## 1. Logging Architecture

The logging architecture is designed to centralize logs from all services in the Swarm cluster.

- **Fluentd Service:** A `fluentd` service is deployed as part of the `monitoring_stack`. It listens for log messages from other services on port `24224`.

- **Logging Driver:** The `frontend` and `backend` services are configured to use the `fluentd` logging driver. This driver sends the container logs to the `fluentd` service.

- **Log Processing:** The `fluentd` service is configured with a `fluentd.conf` file. This file defines how to process the incoming logs:
    - Logs are parsed as JSON.
    - The container name is added as a tag to the log record.
    - Logs are written to a file inside the `fluentd` container (`/fluentd/log/app.log`).
    - Logs are also sent to standard output for easy debugging.

## 2. Viewing Centralized Logs

To view the aggregated logs, you can check the logs of the `fluentd` service:

```bash
docker service logs monitoring_stack_fluentd
```

This will show a stream of all logs from the `frontend` and `backend` services.

You can also inspect the log file inside the `fluentd` container:

```bash
# Find the fluentd container ID
docker ps -q --filter "name=monitoring_stack_fluentd"

# Exec into the container and view the log file
docker exec -it <fluentd_container_id> tail -f /fluentd/log/app.log
```

## 3. Log Rotation and Retention

- **Fluentd Log Rotation:** The `fluentd.conf` file is configured to rotate the aggregated log file daily.
- **Docker Log Rotation:** For services that don't use the `fluentd` driver, Docker's default `json-file` driver can be configured with log rotation options (`max-size`, `max-file`) in the `docker-compose.yml` file.
