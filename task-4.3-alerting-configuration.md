# Task 4.3: Alerting Configuration

This document describes the alerting setup with Prometheus and Alertmanager.

## 1. Alerting Architecture

- **Prometheus:** Prometheus is configured with a set of alerting rules in `prometheus-rules.yml`. When an alert's condition is met, Prometheus sends the alert to Alertmanager.

- **Alertmanager:** The `alertmanager` service receives alerts from Prometheus. It is responsible for deduplicating, grouping, and routing alerts to the correct receiver.

- **Receivers:** A receiver is a destination for alerts, such as email, Slack, or a webhook. In this setup, a placeholder webhook receiver is configured in `alertmanager.yml`.

## 2. Configuration Files

- **`docker-compose.monitoring.yml`:** The `alertmanager` service has been added to this file.

- **`alertmanager.yml`:** This file configures Alertmanager. It defines the alert routing and receivers.

- **`prometheus-rules.yml`:** This file contains the alerting rules for Prometheus.

- **`prometheus.yml`:** This file has been updated to include the alerting rules and the Alertmanager service address.

## 3. Viewing Alerts

- **Prometheus UI:** You can view the status of the alerting rules in the "Alerts" section of the Prometheus UI (`http://<your_swarm_manager_ip>:9090`).

- **Alertmanager UI:** Alertmanager has its own UI for viewing and managing alerts. It is available on port `9093` (`http://<your_swarm_manager_ip>:9093`).

## 4. Redeploying the Monitoring Stack

To apply the new alerting configuration, you need to redeploy the `monitoring_stack`:

```bash
docker stack deploy -c docker-compose.monitoring.yml monitoring_stack
```
