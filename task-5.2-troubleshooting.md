This will show you the complete error message, which is often truncated in the default view.

### Scenario 3: `docker stack deploy` ignores `build` instruction

**Symptom:** Services fail to start with errors like "image frontend-app:latest could not be accessed on a registry" or "No such image: backend-app:la...". This happens even when `build` is specified in `docker-compose.yml` for `docker stack deploy`.

**Explanation:** The `docker stack deploy` command, used for Docker Swarm deployments, ignores the `build` instruction in `docker-compose.yml`. It expects images to be pre-built and available on all Swarm nodes (either in a registry or locally on each node).

**Troubleshooting Steps:**

1.  **Build Images Manually:** Before deploying the stack, manually build the required images.

    ```bash
    docker build -t frontend-app:latest ./frontend
    docker build -t backend-app:latest ./backend
    ```

2.  **Redeploy Stack:** After building, redeploy the stack.

    ```bash
    docker stack deploy -c docker-compose.yml my_app_stack
    ```

### Scenario 4: Port Conflict During Stack Deployment

**Symptom:** A stack deployment fails with an error like "port '8080' is already in use by service 'my_app_stack_traefik' as an ingress port".

**Explanation:** This occurs when two or more services in your Swarm (possibly from different stacks) try to expose the same port on the host or as an ingress port.

**Troubleshooting Steps:**

1.  **Identify Conflicting Services/Ports:** The error message usually indicates which services and ports are conflicting.
2.  **Adjust Port Configuration:** Modify the `docker-compose.yml` of one of the conflicting services to use a different port.

    *   **Example:** Change cAdvisor's exposed port from `8080` to `8081` in `docker-compose.monitoring.yml`.

    ```yaml
    # In docker-compose.monitoring.yml for cadvisor service
    ports:
      - "8081:8080" # Exposed port:Container port
    ```

3.  **Redeploy Affected Stack(s):** Redeploy the stack(s) after making the port changes.

### Scenario 5: Service Still Stuck After Image Build (Health Check Related)

**Symptom:** After manually building images, a service shows `0/X` replicas, and `docker service ps` indicates `"task: non-zero exit (1): dockerexec: unhealthy container"`. `docker service logs` might be empty.

**Explanation:** The application starts, but its configured health check fails consistently, causing Swarm to restart the container repeatedly. An empty log might mean the container crashes too fast, or `stdout`/`stderr` aren't captured correctly.

**Troubleshooting Steps:**

1.  **Verify Health Check Command:**
    *   Ensure the command used in `healthcheck.test` is correct and actually returns `0` (success) when the application is healthy.
    *   **Example:** We found `wget` was missing from `node:16-alpine`.
        *   **Solution:** Add `RUN apk add --no-cache wget` to the `Dockerfile` for the `backend` service.

2.  **Increase Health Check `start_period` and `interval`:** The application might need more time to initialize before it can respond to health checks.

    *   **Example:** For the `backend` service, increase `start_period` and `interval`.

    ```yaml
    # In docker-compose.yml for backend service
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:3000/health || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s # Increased from default
    ```

3.  **Temporarily Disable Health Check:** To isolate if the health check is the actual problem, temporarily disable it. If the service then runs (e.g., `X/X` replicas), the issue is definitely with the health check configuration or timing.

    *   **Syntax:** `healthcheck: test: ["NONE"]`
    *   **Action:** Redeploy the stack after disabling.

### Scenario 6: Traefik `failed to decode configuration from flags`

**Symptom:** Traefik service fails to start with errors like `"failed to decode configuration from flags: field not found, node: middlewares"`.

**Explanation:** This typically indicates an incorrect syntax in the Traefik `command` flags, especially when defining middlewares. The error message usually points to the specific part of the configuration that Traefik cannot parse.

**Troubleshooting Steps:**

1.  **Review Traefik Command Flags:** Carefully examine the `command` section in your `docker-compose.yml` for Traefik.
2.  **Correct Middleware Flag Syntax:**
    *   Ensure there are no redundant prefixes (e.g., `--traefik.http`). Middleware definitions usually start directly with `--middlewares.<middleware_name>...`.
    *   Verify the exact syntax for each middleware (e.g., `ratelimit`, `headers`). Even a small typo can cause this error.
3.  **Simplify Configuration (Iteratively):** If the exact cause is unclear, remove parts of the Traefik configuration from the `command` section one by one (or in groups) and redeploy until Traefik starts. This helps isolate the problematic flag.

    *   **Example:** We removed security headers, then rate limiting, HTTP-to-HTTPS redirection, and certificate resolver configurations to identify the problematic part.

    ```yaml
    # Simplified Traefik command section (example for troubleshooting)
    command:
      - "--api.insecure=true"
      - "--providers.docker.swarmMode=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
    ```
