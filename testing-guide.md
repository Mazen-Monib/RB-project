# Testing the Docker Swarm Deployment (Up to Task 4.1)

To test the changes made so far, you need to deploy both the main application stack and the monitoring stack to a Docker Swarm environment.

## Prerequisites

1.  **Initialize Docker Swarm:** Ensure you have a Docker Swarm initialized. If not, run `docker swarm init` on your manager node.
2.  **Create Secrets:** The `docker-compose.yml` file uses external secrets for the database credentials. You must create these secrets before deploying the stack. Replace `my_user`, `my_strong_password`, and `my_database` with your desired values.

    ```bash
    echo "my_user" | docker secret create postgres_user -
    echo "my_strong_password" | docker secret create postgres_password -
    echo "my_database" | docker secret create postgres_db -
    ```

3.  **Set `your_domain.com`:** Remember to replace `your_domain.com` in `docker-compose.yml` with your actual domain or a placeholder if you're testing locally without a domain (e.g., `localhost`).

## Deployment Steps

1.  **Deploy the Main Application Stack:**
    Navigate to the root of your project directory (where `docker-compose.yml` is located) and run:

    ```bash
    docker stack deploy -c docker-compose.yml my_app_stack
    ```
    This will deploy your frontend, backend, postgres, redis, and traefik services.

2.  **Deploy the Monitoring Stack:**
    Navigate to the root of your project directory and run:

    ```bash
    docker stack deploy -c docker-compose.monitoring.yml monitoring_stack
    ```
    This will deploy Prometheus, Grafana, Node Exporter, cAdvisor, and Fluentd (though Fluentd is not fully configured yet).

## Verification

After deploying both stacks, you can verify their status and access their UIs.

1.  **Check Service Status:**
    Verify that all services are running as expected:

    ```bash
    docker service ls
    ```
    You should see services for `my_app_stack` (frontend, backend, postgres, redis, traefik) and `monitoring_stack` (prometheus, grafana, node-exporter, cadvisor, fluentd).

2.  **Access Traefik Dashboard:**
    Traefik's dashboard is available on port `8080` of your Swarm manager node:
    `http://<your_swarm_manager_ip>:8080`

3.  **Access Portainer:**
    Portainer is available on port `9000` of your Swarm manager node:
    `http://<your_swarm_manager_ip>:9000`
    (You will need to initialize it and set up an admin user on first access).

4.  **Access Prometheus:**
    Prometheus's UI is available on port `9090` of your Swarm manager node:
    `http://<your_swarm_manager_ip>:9090`

5.  **Access Grafana:**
    Grafana's UI is available on port `3000` of your Swarm manager node:
    `http://<your_swarm_manager_ip>:3000`
    (Default credentials: `admin`/`admin`). You can then import the `grafana-dashboard.json` as described in `monitoring-readme.md`.

6.  **Application Access:**
    If you've configured DNS for `your_domain.com` to point to your Swarm manager's IP, you should be able to access your frontend and backend APIs via `https://your_domain.com` and `https://your_domain.com/api` respectively.

Please proceed with these steps to test the current state of the project.
