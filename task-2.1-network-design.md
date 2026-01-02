# Task 2.1: Docker Swarm Network Design

This document describes the multi-tier network architecture for the Docker Swarm deployment, as required by Task 2.1 of the assignment.

## 1. Network Topology

The network is designed with multiple layers to ensure proper isolation between services.

- **`public-net`**: This is the entry point for all external traffic. Only the `traefik` ingress controller is attached to this network. It's responsible for routing incoming requests to the appropriate services.

- **`frontend-net`**: This network is for the frontend application. `traefik` is attached to this network to forward traffic to the `frontend` service. The `frontend` service is only on this network, isolating it from the backend and database.

- **`backend-net`**: This network is for the backend services. `traefik` is also attached to this network to forward API requests to the `backend` service. The `backend`, `postgres`, and `redis` services are all on this network, allowing them to communicate with each other.

- **`monitoring-net`**: This network is reserved for the monitoring stack (e.g., Prometheus, Grafana). It is defined but not yet used.

## 2. Network Isolation

- **Frontend Isolation**: The `frontend` service is only connected to the `frontend-net`. It cannot directly access the `postgres` or `redis` services on the `backend-net`.

- **Backend Isolation**: The `backend` service and its database/cache are on the `backend-net`. They are not directly exposed to the internet. `traefik` acts as a controlled gateway for API requests.

- **Ingress Control**: `traefik` is the only service exposed to the public internet via the `public-net`.

## 3. Encrypted Overlay Networks

All custom overlay networks (`frontend-net`, `backend-net`, `monitoring-net`) are configured with `encrypted: "true"`. This ensures that all communication between services on these networks is encrypted.

## 4. Service Communication

- **External to Frontend**: An external user request hits `traefik` on the `public-net`. `traefik` then routes the request to the `frontend` service over the `frontend-net`.

- **External to Backend**: An external API request hits `traefik` on the `public-net`. `traefik` routes the request to the `backend` service over the `backend-net`.

- **Backend to Database**: The `backend` service communicates with `postgres` and `redis` over the `backend-net` using Docker's built-in DNS service discovery. For example, the `backend` service can reach the `postgres` database using the hostname `postgres`.

## 5. Manual Network Creation Commands

While `docker stack deploy` will create these networks automatically from the `docker-compose.yml` file, they can also be created manually with the following commands:

```bash
# Create the public network
docker network create --driver overlay public-net

# Create the encrypted frontend network
docker network create --driver overlay --opt encrypted=true frontend-net

# Create the encrypted backend network
docker network create --driver overlay --opt encrypted=true backend-net

# Create the encrypted monitoring network
docker network create --driver overlay --opt encrypted=true monitoring-net
```
