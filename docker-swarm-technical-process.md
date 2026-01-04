# Docker Swarm Production Deployment: Complete Technical Process Document

**Project Overview**: End-to-end production deployment of a multi-tier web application using Docker Swarm orchestration, including security hardening, monitoring, high availability, and Kubernetes migration planning.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Security Implementation](#2-security-implementation)
3. [Network Design & Isolation](#3-network-design--isolation)
4. [Management & Orchestration](#4-management--orchestration)
5. [Observability & Monitoring](#5-observability--monitoring)
6. [High Availability & Resilience](#6-high-availability--resilience)
7. [Operational Procedures](#7-operational-procedures)
8. [Cloud Migration Strategy](#8-cloud-migration-strategy)

---

## 1. Architecture Overview

### 1.1 Stack Components

**Application Tier**:
- **Frontend**: React/Node.js SPA (Single Page Application)
- **Backend**: Node.js REST API (3 replicas for HA)
- **Database**: PostgreSQL (stateful, external secrets)
- **Cache**: Redis (in-memory data store)

**Infrastructure Tier**:
- **Ingress**: Traefik reverse proxy with automatic SSL
- **Management**: Portainer for cluster visualization
- **Monitoring**: Prometheus, Grafana, Node Exporter, cAdvisor
- **Logging**: Fluentd centralized log aggregation

### 1.2 Service Distribution

```
┌─────────────────────────────────────────────────────┐
│                   Public Network                     │
│                    (Internet)                        │
└────────────────────┬────────────────────────────────┘
                     │
              ┌──────▼──────┐
              │   Traefik   │ (Ingress Controller)
              │  Port 80/443│
              └──────┬──────┘
                     │
         ┌───────────┴───────────┐
         │                       │
    ┌────▼─────┐           ┌────▼─────┐
    │ Frontend │           │ Backend  │
    │ Network  │           │ Network  │
    └────┬─────┘           └────┬─────┘
         │                      │
    ┌────▼────┐        ┌────────┼────────┐
    │Frontend │        │Backend │ Redis  │
    │ Service │        │Service │Postgres│
    └─────────┘        └────────┴────────┘
```

---

## 2. Security Implementation

### 2.1 Docker Secrets Management

**Purpose**: Secure handling of sensitive credentials (database passwords, API keys)

**Implementation Process**:

```bash
# Create database secrets on Swarm manager
echo "production_user" | docker secret create postgres_user -
echo "$(openssl rand -base64 32)" | docker secret create postgres_password -
echo "production_db" | docker secret create postgres_db -

# Verify secret creation
docker secret ls
```

**Integration in Docker Compose**:
```yaml
services:
  postgres:
    secrets:
      - postgres_user
      - postgres_password
      - postgres_db
    environment:
      POSTGRES_USER_FILE: /run/secrets/postgres_user
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
      POSTGRES_DB_FILE: /run/secrets/postgres_db

secrets:
  postgres_user:
    external: true
  postgres_password:
    external: true
  postgres_db:
    external: true
```

**Key Features**:
- Secrets stored encrypted in Swarm Raft log
- Never exposed in container environment variables
- Mounted as read-only files in `/run/secrets/`
- Only accessible to services explicitly granted access

### 2.2 Secret Rotation Without Downtime

**Rotation Strategy** (Zero-Downtime):

1. **Create New Secret Version**:
```bash
echo "new_secure_password" | docker secret create postgres_password_v2 -
```

2. **Update Service Configuration**:
```yaml
services:
  postgres:
    secrets:
      - postgres_user
      - postgres_password_v2  # Add new secret
      - postgres_db
```

3. **Deploy Update** (Rolling):
```bash
docker stack deploy --compose-file docker-compose.yml my_stack
```

4. **Update Application Logic**: Update backend connection strings to use new secret

5. **Remove Old Secret**:
```bash
docker secret rm postgres_password
```

**Timeline**: ~5-10 minutes per secret with zero service interruption

### 2.3 Docker Configs for Non-Sensitive Data

**Use Cases**:
- Application configuration files
- Nginx virtual host configurations
- Logging configurations
- Feature flags

**Example Implementation**:

```bash
# Create config file
cat > app-config.json <<EOF
{
  "logLevel": "info",
  "featureFlags": {
    "newAuth": true,
    "betaFeatures": false
  },
  "apiTimeout": 30000
}
EOF

# Create Docker config
docker config create app_config_v1 app-config.json
```

**Mount in Service**:
```yaml
services:
  backend:
    configs:
      - source: app_config_v1
        target: /usr/src/app/config/app-config.json
        mode: 0440

configs:
  app_config_v1:
    external: true
```

**Config Updates**: Similar to secrets, configs can be rotated by creating new versions and updating service definitions.

---

## 3. Network Design & Isolation

### 3.1 Multi-Tier Network Architecture

**Network Segmentation Strategy**:

| Network | Purpose | Connected Services | Encryption |
|---------|---------|-------------------|------------|
| `public-net` | External ingress | Traefik only | No |
| `frontend-net` | Frontend tier | Traefik, Frontend | Yes |
| `backend-net` | Application logic | Traefik, Backend, Postgres, Redis | Yes |
| `monitoring-net` | Observability | Prometheus, Grafana, Exporters | Yes |

### 3.2 Network Isolation Rules

**Principle**: Least privilege network access

- **Frontend Service**:
  - ✅ Can communicate with Traefik (receive HTTP requests)
  - ❌ Cannot directly access database or Redis
  - ❌ Cannot access backend except through Traefik routing

- **Backend Service**:
  - ✅ Can communicate with Traefik (receive API requests)
  - ✅ Can access Postgres and Redis on `backend-net`
  - ✅ Uses Docker DNS for service discovery (`postgres`, `redis`)

- **Traefik**:
  - ✅ Connected to all networks (routing hub)
  - ✅ Enforces routing rules and path-based forwarding

### 3.3 Encrypted Overlay Networks

**Implementation**:

```bash
# Manual network creation (optional - stack deploy creates automatically)
docker network create \
  --driver overlay \
  --opt encrypted=true \
  --attachable \
  frontend-net

docker network create \
  --driver overlay \
  --opt encrypted=true \
  --attachable \
  backend-net

docker network create \
  --driver overlay \
  --opt encrypted=true \
  --attachable \
  monitoring-net
```

**Encryption Details**:
- Uses IPsec for overlay traffic encryption
- Encrypts all inter-service communication
- Minimal performance overhead (~5-10%)
- Automatic key rotation by Swarm

### 3.4 Service Discovery & DNS

**Built-in DNS Resolution**:
- Each service accessible via `<service_name>.<stack_name>`
- Example: Backend accesses database via `postgres` hostname
- Automatic load balancing across replicas
- DNS caching with 5-second TTL

**Connection String Example**:
```javascript
// Backend database connection
const pool = new Pool({
  host: 'postgres',  // Service name = hostname
  port: 5432,
  user: fs.readFileSync('/run/secrets/postgres_user', 'utf8'),
  password: fs.readFileSync('/run/secrets/postgres_password', 'utf8'),
  database: fs.readFileSync('/run/secrets/postgres_db', 'utf8')
});
```

---

## 4. Management & Orchestration

### 4.1 Portainer Deployment & Access

**Deployment**:

```yaml
# In docker-compose.yml
services:
  portainer:
    image: portainer/portainer-ce:latest
    command: -H unix:///var/run/docker.sock
    ports:
      - "9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    deploy:
      placement:
        constraints:
          - node.role == manager
```

**Initial Setup**:
1. Navigate to `http://<manager-ip>:9000`
2. Create admin account (username + password)
3. Select "Docker" environment
4. Auto-connects to local Swarm

### 4.2 Stack Management via Portainer UI

**Deployment Workflow**:

1. **Navigate**: Stacks → Add Stack
2. **Configure**:
   - Name: `production_app`
   - Method: Web editor or Git repository
3. **Environment Variables**: Define in UI or use `.env` file
4. **Deploy**: Click "Deploy the stack"

**Benefits**:
- Visual service monitoring
- Real-time log viewing
- Resource usage graphs
- Network topology visualization
- Secret and config management UI

### 4.3 Portainer API Automation

**API Key Generation**:
1. Navigate to User → API Keys
2. Create key with appropriate permissions
3. Store securely (e.g., in CI/CD secrets)

**Example API Calls**:

```bash
# Get stack list
curl -X GET \
  -H "X-API-Key: ptr_xxxxxxxxxx" \
  http://portainer:9000/api/stacks

# Deploy/update stack
curl -X POST \
  -H "X-API-Key: ptr_xxxxxxxxxx" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "production_app",
    "stackFileContent": "'"$(cat docker-compose.yml | sed 's/"/\\"/g')"'",
    "env": [
      {"name": "ENVIRONMENT", "value": "production"}
    ]
  }' \
  http://portainer:9000/api/stacks?type=1&method=string&endpointId=1

# Delete stack
curl -X DELETE \
  -H "X-API-Key: ptr_xxxxxxxxxx" \
  http://portainer:9000/api/stacks/{id}
```

**CI/CD Integration**:
- Jenkins pipeline can trigger deployments
- GitHub Actions can update stacks on push
- GitLab CI can manage blue-green deployments

### 4.4 Best Practices for Stack Organization

**Naming Conventions**:
- Environment-based: `app-prod`, `app-staging`, `app-dev`
- Service-based: `web-stack`, `api-stack`, `data-stack`
- Version-based: `app-v2.1.0`

**Access Control**:
- Use Portainer Teams for RBAC
- Separate environments with different endpoints
- Audit logs for compliance tracking

**Git Integration**:
- Connect Portainer to Git repository
- Automatic deployment on branch update
- GitOps workflow for production

---

## 5. Observability & Monitoring

### 5.1 Monitoring Stack Architecture

**Components**:

```
┌─────────────┐
│   Grafana   │ ← Visualization & Dashboards
│  Port 3000  │
└──────┬──────┘
       │ Query
┌──────▼──────┐
│ Prometheus  │ ← Metrics Collection & Storage
│  Port 9090  │
└──────┬──────┘
       │ Scrape
       ├──────────────┬──────────────┬──────────────┐
┌──────▼──────┐ ┌─────▼─────┐ ┌─────▼─────┐ ┌──────▼──────┐
│Node Exporter│ │  cAdvisor │ │  Backend  │ │  Postgres   │
│  Host Metrics│ │ Containers│ │/metrics   │ │  Exporter   │
└─────────────┘ └───────────┘ └───────────┘ └─────────────┘
```

### 5.2 Prometheus Configuration

**Scrape Configuration** (`prometheus.yml`):

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - '/etc/prometheus/rules/*.yml'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    dns_sd_configs:
      - names: ['tasks.node-exporter']
        type: 'A'
        port: 9100

  - job_name: 'cadvisor'
    dns_sd_configs:
      - names: ['tasks.cadvisor']
        type: 'A'
        port: 8080

  - job_name: 'backend'
    dns_sd_configs:
      - names: ['tasks.backend']
        type: 'A'
        port: 3000
    metrics_path: '/metrics'
```

**Key Features**:
- DNS-based service discovery
- Automatic target detection in Swarm
- 15-second scrape interval for real-time monitoring

### 5.3 Grafana Dashboard Setup

**Data Source Configuration**:
1. Login to Grafana (admin/admin)
2. Configuration → Data Sources → Add Prometheus
3. URL: `http://prometheus:9090`
4. Save & Test

**Pre-built Dashboards**:
- Node Exporter: Dashboard ID `1860`
- Docker Swarm: Dashboard ID `11599`
- Custom application metrics: Import `grafana-dashboard.json`

**Key Metrics to Monitor**:

| Metric | Query | Alert Threshold |
|--------|-------|----------------|
| CPU Usage | `rate(container_cpu_usage_seconds_total[5m])` | > 80% |
| Memory Usage | `container_memory_usage_bytes / container_spec_memory_limit_bytes` | > 90% |
| API Latency | `http_request_duration_seconds{quantile="0.95"}` | > 500ms |
| Error Rate | `rate(http_requests_total{status=~"5.."}[5m])` | > 1% |
| Replica Health | `up{job="backend"}` | < 2 replicas |

### 5.4 Centralized Logging with Fluentd

**Architecture**:

```
┌─────────┐  ┌─────────┐  ┌─────────┐
│Frontend │  │ Backend │  │  Redis  │
│Container│  │Container│  │Container│
└────┬────┘  └────┬────┘  └────┬────┘
     │            │            │
     │  fluentd:// driver     │
     └────────────┼────────────┘
                  │
            ┌─────▼─────┐
            │  Fluentd  │
            │Port 24224 │
            └─────┬─────┘
                  │
         ┌────────┴────────┐
         │                 │
    ┌────▼────┐      ┌─────▼─────┐
    │File Log │      │ Stdout    │
    │Rotation │      │ (Debug)   │
    └─────────┘      └───────────┘
```

**Fluentd Configuration** (`fluentd.conf`):

```xml
<source>
  @type forward
  port 24224
  bind 0.0.0.0
</source>

<filter **>
  @type record_transformer
  <record>
    hostname ${hostname}
    container_name ${tag}
  </record>
</filter>

<match **>
  @type copy
  
  <store>
    @type file
    path /fluentd/log/app.log
    <buffer>
      timekey 86400  # Daily rotation
      timekey_wait 10m
    </buffer>
  </store>
  
  <store>
    @type stdout
  </store>
</match>
```

**Service Logging Driver**:

```yaml
services:
  backend:
    logging:
      driver: fluentd
      options:
        fluentd-address: "localhost:24224"
        fluentd-async-connect: "true"
        tag: "backend.{{.Name}}"
```

**Viewing Logs**:

```bash
# View aggregated logs
docker service logs monitoring_stack_fluentd

# Access log file directly
docker exec -it $(docker ps -q -f name=fluentd) \
  tail -f /fluentd/log/app.log

# Search logs
docker exec -it $(docker ps -q -f name=fluentd) \
  grep "ERROR" /fluentd/log/app.log
```

### 5.5 Alerting Configuration

**Prometheus Alert Rules** (`prometheus-rules.yml`):

```yaml
groups:
  - name: application_alerts
    interval: 30s
    rules:
      - alert: HighCPUUsage
        expr: rate(container_cpu_usage_seconds_total[5m]) > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.container_label_com_docker_swarm_service_name }}"
          description: "CPU usage is above 80% for 5 minutes"

      - alert: ServiceDown
        expr: up{job="backend"} < 2
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Backend service has less than 2 healthy replicas"
          description: "Only {{ $value }} replicas are up"

      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.01
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value | humanizePercentage }}"
```

**Alertmanager Configuration** (`alertmanager.yml`):

```yaml
global:
  resolve_timeout: 5m

route:
  receiver: 'default-receiver'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  routes:
    - match:
        severity: critical
      receiver: 'critical-receiver'
      continue: true

receivers:
  - name: 'default-receiver'
    webhook_configs:
      - url: 'http://webhook-server:8080/alerts'
        send_resolved: true

  - name: 'critical-receiver'
    webhook_configs:
      - url: 'http://pagerduty-webhook:8080/critical'
    # email_configs:
    #   - to: 'ops-team@company.com'
    #     from: 'alertmanager@company.com'
```

**Accessing Alertmanager**:
- UI: `http://<manager-ip>:9093`
- Silence alerts temporarily
- View alert history and grouping

---

## 6. High Availability & Resilience

### 6.1 Rolling Update Configuration

**Zero-Downtime Update Strategy**:

```yaml
services:
  backend:
    deploy:
      replicas: 3
      update_config:
        parallelism: 1          # Update 1 replica at a time
        delay: 10s              # Wait 10s between updates
        failure_action: rollback # Auto-rollback on failure
        monitor: 60s            # Monitor for 60s before next update
        max_failure_ratio: 0.3  # Rollback if >30% fail
        order: start-first      # Start new before stopping old
      rollback_config:
        parallelism: 1
        delay: 5s
        failure_action: pause
        monitor: 30s
```

**Update Execution**:

```bash
# Update image version
docker service update \
  --image backend-app:v2.0.0 \
  my_stack_backend

# Update environment variable
docker service update \
  --env-add NEW_FEATURE=enabled \
  my_stack_backend

# Scale replicas
docker service scale my_stack_backend=5
```

**Monitoring Update Progress**:

```bash
# Watch update status
watch -n 1 'docker service ps my_stack_backend --no-trunc'

# View detailed update history
docker service inspect my_stack_backend --pretty

# Check logs during update
docker service logs -f my_stack_backend
```

### 6.2 Health Check Implementation

**Application Health Checks**:

```yaml
services:
  backend:
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:3000/health || exit 1"]
      interval: 10s      # Check every 10 seconds
      timeout: 5s        # Timeout after 5 seconds
      retries: 3         # Retry 3 times before unhealthy
      start_period: 30s  # Grace period for startup
```

**Health Endpoint Implementation** (Node.js):

```javascript
// /health endpoint
app.get('/health', async (req, res) => {
  try {
    // Check database connection
    await pool.query('SELECT 1');
    
    // Check Redis connection
    await redis.ping();
    
    // Return healthy status
    res.status(200).json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      database: 'connected',
      cache: 'connected'
    });
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy',
      error: error.message
    });
  }
});
```

**Health Check Behavior**:
- Failed health checks trigger container restart
- Swarm removes unhealthy containers from load balancer
- New containers spin up automatically
- Old containers only removed after new ones are healthy

### 6.3 Automatic Rollback

**Simulating Failed Deployment**:

```yaml
# Intentionally break health check
services:
  backend:
    image: backend-app:broken-v2.0.0
    healthcheck:
      test: ["CMD-SHELL", "exit 1"]  # Always fails
```

**Rollback Triggers**:
- Health check failures exceed `max_failure_ratio`
- Container crashes on startup
- Image pull failures

**Observing Automatic Rollback**:

```bash
# Watch service during failed update
docker service ps my_stack_backend

# Output shows:
# - New tasks failing health checks
# - Automatic rollback initiated
# - Previous version tasks restarted
# - Service returns to stable state
```

**Manual Rollback**:

```bash
# Rollback to previous version
docker service rollback my_stack_backend

# Rollback with custom config
docker service update \
  --rollback \
  --rollback-parallelism 2 \
  my_stack_backend
```

### 6.4 Placement Strategies

**Spread Across Availability Zones**:

```yaml
services:
  backend:
    deploy:
      placement:
        preferences:
          - spread: node.labels.region  # Spread across regions
        constraints:
          - node.role == worker         # Only on worker nodes
          - node.labels.storage == ssd  # Only on SSD nodes
```

**Node Labeling**:

```bash
# Label nodes by region
docker node update --label-add region=us-east-1 node1
docker node update --label-add region=us-east-2 node2
docker node update --label-add region=us-west-1 node3

# Label nodes by hardware
docker node update --label-add storage=ssd node1
docker node update --label-add storage=hdd node2
```

**Result**: Backend replicas automatically distributed across all regions for maximum availability.

---

## 7. Operational Procedures

### 7.1 Cluster Management

**Adding Worker Nodes**:

```bash
# On manager: Get join token
docker swarm join-token worker

# Output:
# docker swarm join --token SWMTKN-1-xxx <manager-ip>:2377

# On new worker node: Join swarm
docker swarm join --token SWMTKN-1-xxx 10.0.1.10:2377
```

**Adding Manager Nodes** (High Availability):

```bash
# Get manager token
docker swarm join-token manager

# On new manager node
docker swarm join --token SWMTKN-1-xxx 10.0.1.10:2377

# Verify manager quorum
docker node ls
```

**Best Practice**: Maintain 3 or 5 managers for quorum (odd numbers prevent split-brain).

### 7.2 Node Maintenance

**Draining Nodes**:

```bash
# Drain node for maintenance
docker node update --availability drain node2

# Verify tasks rescheduled
docker service ps my_stack_backend

# Perform maintenance (OS updates, hardware replacement, etc.)

# Reactivate node
docker node update --availability active node2
```

**Removing Nodes**:

```bash
# On the node to remove
docker swarm leave

# On manager
docker node rm node2

# Force remove unresponsive node
docker node rm --force node2
```

### 7.3 Troubleshooting Common Issues

**Issue 1: Service Stuck at 0/3 Replicas**

```bash
# Check service status
docker service ps my_stack_backend --no-trunc

# Common causes:
# - Image not found: Build and tag image
# - Port conflicts: Change port mapping
# - Resource constraints: Check node resources
# - Secret missing: Create required secrets

# View detailed errors
docker service ps my_stack_backend --format "{{.Error}}"
```

**Issue 2: Image Build Ignored**

```bash
# Stack deploy ignores 'build' directive
# Solution: Pre-build images

docker build -t backend-app:latest ./backend
docker build -t frontend-app:latest ./frontend

# Then deploy
docker stack deploy -c docker-compose.yml my_stack
```

**Issue 3: Port Conflict**

```bash
# Error: port 8080 already in use
# Find conflicting service
docker service ls | grep 8080

# Change port in docker-compose.yml
ports:
  - "8081:8080"  # Host:Container

# Redeploy
docker stack deploy -c docker-compose.yml my_stack
```

**Issue 4: Health Check Failures**

```bash
# Check health check command
docker service inspect my_stack_backend | grep -A 5 HealthCheck

# Common fixes:
# 1. Install missing tools (e.g., wget, curl)
# 2. Increase start_period for slow-starting apps
# 3. Fix health endpoint logic
# 4. Adjust timeout/retry values

# Temporary disable to test
healthcheck:
  test: ["NONE"]
```

**Issue 5: Network Connectivity**

```bash
# Test service-to-service communication
docker exec -it $(docker ps -q -f name=backend) \
  ping postgres

# Check network attachments
docker service inspect my_stack_backend | grep Networks -A 10

# Verify DNS resolution
docker exec -it $(docker ps -q -f name=backend) \
  nslookup postgres
```

### 7.4 Backup & Recovery

**Swarm State Backup**:

```bash
# Stop Docker on manager
sudo systemctl stop docker

# Backup Swarm data
sudo tar -czvf swarm-backup-$(date +%Y%m%d).tar.gz \
  /var/lib/docker/swarm

# Backup certificates
sudo cp -r /var/lib/docker/swarm/certificates /backup/

# Restart Docker
sudo systemctl start docker
```

**Database Backup**:

```bash
# Automated PostgreSQL backup
docker exec $(docker ps -q -f name=postgres) \
  pg_dumpall -U postgres > backup-$(date +%Y%m%d).sql

# Restore database
docker exec -i $(docker ps -q -f name=postgres) \
  psql -U postgres < backup-20260103.sql
```

**Disaster Recovery Steps**:

1. **Restore Swarm State**:
```bash
sudo systemctl stop docker
sudo rm -rf /var/lib/docker/swarm
sudo tar -xzvf swarm-backup.tar.gz -C /
sudo systemctl start docker
docker swarm init --force-new-cluster
```

2. **Recreate Secrets**:
```bash
# Restore from secure vault
cat secrets.txt | while read secret; do
  echo $secret | docker secret create $(echo $secret | cut -d= -f1) -
done
```

3. **Redeploy Stacks**:
```bash
docker stack deploy -c docker-compose.yml my_stack
docker stack deploy -c docker-compose.monitoring.yml monitoring_stack
```

### 7.5 Monitoring & Debugging Commands

**Essential Commands**:

```bash
# Cluster health
docker node ls
docker service ls
docker stack ls

# Service details
docker service ps <service_name> --no-trunc
docker service logs -f <service_name>
docker service inspect <service_name> --pretty

# Container debugging
docker ps -f name=<service_name>
docker exec -it <container_id> /bin/sh
docker stats $(docker ps -q)

# Network debugging
docker network ls
docker network inspect <network_name>

# Volume management
docker volume ls
docker volume inspect <volume_name>
```

---

## 8. Cloud Migration Strategy

### 8.1 Docker Swarm to Kubernetes Migration Plan

**Feature Mapping**:

| Docker Swarm | Kubernetes | Migration Complexity |
|--------------|------------|---------------------|
| Service | Deployment | Low |
| Replicas | Replica Set | Low |
| Secrets | Secret | Low |
| Configs | ConfigMap | Low |
| Overlay Network | CNI (Calico/Flannel) | Medium |
| Health Checks | Liveness/Readiness Probes | Low |
| Rolling Updates | RollingUpdate Strategy | Low |
| Placement Constraints | Node Affinity/Taints | Medium |
| Service Discovery | CoreDNS | Low |
| Ingress (Traefik) | Ingress Controller | Medium |
| Volumes | PersistentVolume/PVC | High |

### 8.2 Phased Migration Approach

**Phase 1: Infrastructure Setup (1-2 weeks)**

```bash
# Provision Kubernetes cluster (EKS/GKE/AKS)
eksctl create cluster \
  --name production-cluster \
  --region us-east-1 \
  --nodes 3 \
  --node-type t3.large

# Install Traefik Ingress Controller
helm repo add traefik https://traefik.github.io/charts
helm install traefik traefik/traefik

# Install monitoring stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack
```

**Phase 2: Staging Environment (2-3 weeks)**

```bash
# Convert docker-compose to Kubernetes manifests
kompose convert -f docker-compose.yml -o k8s/

# Manually refine generated manifests
# Example: backend-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: staging
spec:
  replicas: 3
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
        - name: backend
          image: backend-app:v1.0.0
          ports:
            - containerPort: 3000
          env:
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: username
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 30
            periodSeconds: 10
          resources:
            requests:
              memory: "256Mi"
              cpu: "250m"
            limits:
              memory: "512Mi"
              cpu: "500m"
```

**Phase 3: Data Migration (1 week)**

```bash
# Set up PostgreSQL replication
# Primary (Swarm) → Replica (Kubernetes)

# Configure logical replication on Swarm
docker exec -it $(docker ps -q -f name=postgres) psql -U postgres
postgres=# CREATE PUBLICATION my_pub FOR ALL TABLES;

# Set up subscription in Kubernetes
kubectl exec -it postgres-0 -- psql -U postgres
postgres=# CREATE SUBSCRIPTION my_sub 
           CONNECTION 'host=swarm-db.company.com port=5432 user=replicator password=xxx dbname=production'
           PUBLICATION my_pub;

# Monitor replication lag
SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

**Phase 4: Traffic Shadowing (1 week)**

```bash
# Configure Traefik to mirror traffic
# In Swarm Traefik config
--http.middlewares.mirror.mirror.service=k8s-backend
--http.middlewares.mirror.mirror.percent=10

# Gradually increase shadow traffic
# 10% → 25% → 50% → 100%
```

**Phase 5: Canary Release (1-2 weeks)**

```bash
# Kubernetes canary deployment
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: backend
spec:
  selector:
    app: backend
    version: stable
  ports:
    - port: 80
      targetPort: 3000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-stable
spec:
  replicas: 9  # 90% traffic
  selector:
    matchLabels:
      app: backend
      version: stable
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-canary
spec:
  replicas: 1  # 10% traffic
  selector:
    matchLabels:
      app: backend
      version: canary
EOF

# Monitor canary metrics
kubectl get pods -l version=canary
kubectl logs -f -l version=canary
```

**Phase 6: Full Migration (1 week)**

```bash
# Gradually shift traffic to Kubernetes
# DNS update or load balancer weighted routing

# Update DNS TTL to 60s for quick rollback
dig your-domain.com +short

# Switch traffic in increments
# 25% → 50% → 75% → 100%

# Monitor error rates, latency, resource usage
kubectl top pods
kubectl get events --sort-by='.lastTimestamp'
```

**Phase 7: Decommission Swarm (1 week)**

```bash
# Verify zero traffic to Swarm cluster
docker service logs my_stack_traefik | grep "upstream requests"

# Remove from load balancer
# Delete DNS records pointing to Swarm

# Backup final state
docker stack rm my_stack
docker swarm leave --force

# Archive infrastructure-as-code
git tag swarm-decommissioned-2026-01-03
```

### 8.3 Migration Tools

**Kompose** (Docker Compose → Kubernetes):

```bash
# Install kompose
curl -L https://github.com/kubernetes/kompose/releases/download/v1.32.0/kompose-linux-amd64 \
  -o /usr/local/bin/kompose
chmod +x /usr/local/bin/kompose

# Convert compose file
kompose convert -f docker-compose.yml -o k8s/

# Review generated manifests
ls k8s/
# backend-deployment.yaml
# backend-service.yaml
# postgres-deployment.yaml
# postgres-persistentvolumeclaim.yaml
```

**Manual Conversion** (Recommended for production):

Kompose provides a starting point, but production-grade manifests require manual refinement:
- Add resource limits/requests
- Configure autoscaling (HPA)
- Implement network policies
- Add monitoring annotations
- Configure backup strategies

### 8.4 Testing Strategy

**Load Testing**:

```bash
# Install k6
brew install k6

# Create load test script (load-test.js)
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },  // Ramp up
    { duration: '5m', target: 100 },  // Steady state
    { duration: '2m', target: 0 },    // Ramp down
  ],
};

export default function () {
  let response = http.get('https://your-domain.com/api/health');
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  sleep(1);
}

# Run load test
k6 run load-test.js
```

**Canary Analysis**:

```bash
# Compare metrics between stable and canary
kubectl top pods -l app=backend,version=stable
kubectl top pods -l app=backend,version=canary

# Error rate comparison
kubectl logs -l app=backend,version=stable | grep ERROR | wc -l
kubectl logs -l app=backend,version=canary | grep ERROR | wc -l

# Latency comparison (from Prometheus)
histogram_quantile(0.95,
  rate(http_request_duration_seconds_bucket{version="stable"}[5m])
)
histogram_quantile(0.95,
  rate(http_request_duration_seconds_bucket{version="canary"}[5m])
)
```

### 8.5 Rollback Plan

**During Migration** (Swarm still running):

```bash
# Immediate traffic switch back to Swarm
# Update DNS or load balancer configuration
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123456 \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.your-domain.com",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [{"Value": "10.0.1.10"}]
      }
    }]
  }'

# Wait for DNS propagation (60s TTL)
# Verify traffic returning to Swarm
docker service logs my_stack_traefik
```

**Post-Migration** (Swarm decommissioned):

```bash
# Emergency Swarm reconstruction
# Requires:
# 1. Swarm state backup
# 2. Infrastructure-as-code repository
# 3. Secret vault access

# Provision new Swarm cluster
terraform apply -var-file=swarm-restore.tfvars

# Restore Swarm state
scp swarm-backup.tar.gz manager:/tmp/
ssh manager "sudo systemctl stop docker && \
  sudo tar -xzvf /tmp/swarm-backup.tar.gz -C / && \
  sudo systemctl start docker && \
  docker swarm init --force-new-cluster"

# Recreate secrets
./scripts/restore-secrets.sh

# Redeploy application
docker stack deploy -c docker-compose.yml my_stack

# Update DNS
# Point traffic back to restored Swarm cluster

# Estimated RTO: 30-60 minutes
```

### 8.6 Risk Assessment & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Data loss during migration | Low | Critical | Replication + backup verification |
| Service downtime | Medium | High | Phased migration + rollback plan |
| Performance degradation | Medium | Medium | Load testing + canary analysis |
| Security misconfiguration | Medium | High | Security audit + penetration testing |
| Team knowledge gap | High | Medium | Training + documentation + pair programming |
| Cost overrun | Medium | Low | Budget monitoring + resource optimization |

### 8.7 Timeline & Resources

**Total Estimated Timeline**: 8-11 weeks

**Required Resources**:
- **Infrastructure**: Kubernetes cluster (3+ nodes)
- **Team**: 2-3 engineers (1 lead, 1-2 supporting)
- **Budget**: ~$2,000-5,000/month (cloud resources during migration)
- **Downtime Window**: <1 hour (for final DNS cutover)

**Success Criteria**:
- ✅ Zero data loss
- ✅ <1% error rate increase
- ✅ <10% latency increase
- ✅ All features functional
- ✅ Monitoring and alerting operational
- ✅ Team trained on Kubernetes operations

---

## Appendix: Configuration Files

### A. docker-compose.yml (Main Application)

```yaml
version: '3.8'

services:
  frontend:
    image: frontend-app:latest
    deploy:
      replicas: 2
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure
    networks:
      - frontend-net
    logging:
      driver: fluentd
      options:
        fluentd-address: "localhost:24224"
        tag: "frontend"

  backend:
    image: backend-app:latest
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 10s
        failure_action: rollback
        monitor: 60s
        max_failure_ratio: 0.3
      rollback_config:
        parallelism: 1
        delay: 5s
      placement:
        preferences:
          - spread: node.labels.region
    networks:
      - backend-net
    secrets:
      - postgres_user
      - postgres_password
      - postgres_db
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:3000/health || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s
    logging:
      driver: fluentd
      options:
        fluentd-address: "localhost:24224"
        tag: "backend"

  postgres:
    image: postgres:14
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - backend-net
    secrets:
      - postgres_user
      - postgres_password
      - postgres_db
    environment:
      POSTGRES_USER_FILE: /run/secrets/postgres_user
      POSTGRES_PASSWORD_FILE: /run/secrets/postgres_password
      POSTGRES_DB_FILE: /run/secrets/postgres_db

  redis:
    image: redis:7-alpine
    deploy:
      replicas: 1
    networks:
      - backend-net

  traefik:
    image: traefik:v2.10
    command:
      - "--api.insecure=true"
      - "--providers.docker.swarmMode=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - public-net
      - frontend-net
      - backend-net
    deploy:
      placement:
        constraints:
          - node.role == manager

  portainer:
    image: portainer/portainer-ce:latest
    command: -H unix:///var/run/docker.sock
    ports:
      - "9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    deploy:
      placement:
        constraints:
          - node.role == manager

networks:
  public-net:
    driver: overlay
  frontend-net:
    driver: overlay
    driver_opts:
      encrypted: "true"
  backend-net:
    driver: overlay
    driver_opts:
      encrypted: "true"

volumes:
  postgres_data:
  portainer_data:

secrets:
  postgres_user:
    external: true
  postgres_password:
    external: true
  postgres_db:
    external: true
```

### B. docker-compose.monitoring.yml

```yaml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - ./prometheus-rules.yml:/etc/prometheus/rules/alerts.yml
      - prometheus_data:/prometheus
    networks:
      - monitoring-net
    deploy:
      placement:
        constraints:
          - node.role == manager

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana-dashboard.json:/etc/grafana/provisioning/dashboards/dashboard.json
    networks:
      - monitoring-net
    deploy:
      placement:
        constraints:
          - node.role == manager

  node-exporter:
    image: prom/node-exporter:latest
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    networks:
      - monitoring-net
    deploy:
      mode: global

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    ports:
      - "8081:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    networks:
      - monitoring-net
    deploy:
      mode: global

  fluentd:
    image: fluent/fluentd:latest
    ports:
      - "24224:24224"
      - "24224:24224/udp"
    volumes:
      - ./fluentd.conf:/fluentd/etc/fluent.conf
      - fluentd_data:/fluentd/log
    networks:
      - monitoring-net
    deploy:
      placement:
        constraints:
          - node.role == manager

  alertmanager:
    image: prom/alertmanager:latest
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml
      - alertmanager_data:/alertmanager
    networks:
      - monitoring-net
    deploy:
      placement:
        constraints:
          - node.role == manager

networks:
  monitoring-net:
    driver: overlay
    driver_opts:
      encrypted: "true"

volumes:
  prometheus_data:
  grafana_data:
  fluentd_data:
  alertmanager_data:
```

---

## Conclusion

This comprehensive technical process document covers the end-to-end implementation of a production-grade Docker Swarm deployment, including:

- ✅ **Security**: Secrets management and rotation
- ✅ **Networking**: Multi-tier isolation with encryption
- ✅ **Observability**: Monitoring, logging, and alerting
- ✅ **High Availability**: Rolling updates, health checks, placement strategies
- ✅ **Operations**: Troubleshooting, backup/recovery, cluster management
- ✅ **Migration**: Kubernetes migration strategy with phased approach

**Key Takeaways**:
1. Docker Swarm provides excellent orchestration for medium-scale deployments
2. Security and observability are first-class concerns, not afterthoughts
3. Zero-downtime deployments are achievable with proper configuration
4. Migration to Kubernetes requires careful planning and phased execution
5. Documentation and runbooks are essential for operational success

**Next Steps**:
- Deploy to staging environment for validation
- Conduct load testing and chaos engineering
- Train operations team on runbooks
- Plan capacity and scaling strategy
- Execute Kubernetes migration when ready
