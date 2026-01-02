# Task 4.1: Prometheus & Grafana Monitoring Stack

This document explains how to deploy the monitoring stack and import the Grafana dashboard.

## 1. Deploying the Monitoring Stack

The `docker-compose.monitoring.yml` file contains the services for Prometheus, Grafana, Node Exporter, and cAdvisor.

To deploy the stack, run the following command in your Swarm manager node:

```bash
docker stack deploy --compose-file docker-compose.monitoring.yml monitoring
```

This will create a new stack named `monitoring` with all the necessary services.

## 2. Accessing the Services

- **Prometheus:** `http://<your_swarm_manager_ip>:9090`
- **Grafana:** `http://<your_swarm_manager_ip>:3000` (default credentials: `admin`/`admin`)
- **cAdvisor:** `http://<your_swarm_manager_ip>:8080` (Note: cAdvisor's web UI is on port 8080 of each node it runs on, so you might need to check the IP of the specific node)

## 3. Configuring Prometheus

The `prometheus.yml` file provided in this project is configured to use Docker Swarm service discovery.

To make your application services discoverable by Prometheus, you need to add the following labels to your services in the main `docker-compose.yml` file:

```yaml
services:
  backend:
    # ...
    deploy:
      labels:
        - "prometheus-scrape=true"
        - "prometheus-port=3000" # The port your app exposes metrics on
```

The `prometheus.yml` also includes jobs for `node-exporter` and `cadvisor`, which are discovered via labels.

## 4. Importing the Grafana Dashboard

1.  Log in to Grafana (`http://<your_swarm_manager_ip>:3000`).
2.  Navigate to "Dashboards" -> "Import".
3.  Click "Upload JSON file" and select the `grafana-dashboard.json` file from this project.
4.  Choose the Prometheus data source.
5.  Click "Import".

The dashboard will be imported, and you can view the metrics from your Swarm cluster, including service replicas, node CPU/memory usage, container restarts, and network traffic.
