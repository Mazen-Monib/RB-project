# Task 5.3: Docker Swarm Cluster Management Runbook

This runbook provides commands and best practices for managing a Docker Swarm cluster.

## 1. Adding and Removing Nodes

### Adding Nodes

1.  **Get the Join Token:** On a manager node, get the join token for either a worker or a manager.

    ```bash
    # Get the worker join token
    docker swarm join-token worker

    # Get the manager join token
    docker swarm join-token manager
    ```

2.  **Join the Swarm:** On the new node, run the `docker swarm join` command provided by the previous step.

    ```bash
    docker swarm join --token <token> <manager_ip>:<manager_port>
    ```

### Removing Nodes

1.  **Drain the Node (if it's a worker):** Before removing a worker node, it's best practice to drain it to gracefully move its tasks to other nodes.

    ```bash
    docker node update --availability drain <node_id>
    ```

2.  **Remove the Node:** On a manager node, remove the node from the Swarm.

    ```bash
    docker node rm <node_id>
    ```

## 2. Promoting and Demoting Manager Nodes

You can promote a worker node to a manager or demote a manager node to a worker. This is useful for maintaining manager quorum.

- **Promote a worker:** `docker node promote <node_id>`
- **Demote a manager:** `docker node demote <node_id>`

**Best Practice:** Maintain an odd number of manager nodes (3 or 5) to ensure high availability and prevent split-brain scenarios.

## 3. Draining Nodes for Maintenance

When you need to perform maintenance on a node (e.g., system updates), you should drain it first. This will gracefully stop and reschedule all tasks running on that node to other available nodes.

```bash
# Drain the node
docker node update --availability drain <node_id>

# After maintenance, set the node back to active
docker node update --availability active <node_id>
```

## 4. Recovering from Quorum Loss

Quorum loss happens when a majority of the manager nodes are down. In this state, the Swarm cannot process any management commands.

To recover from quorum loss, you need to force a new cluster to be created from one of the remaining manager nodes.

**Warning:** This is a drastic measure and should only be used as a last resort.

```bash
docker swarm init --force-new-cluster
```

## 5. Backing Up and Restoring Swarm State

The Swarm state, including services, networks, and secrets, is stored in the `/var/lib/docker/swarm` directory on the manager nodes.

### Backup

To back up the Swarm, you can stop Docker on a manager node and create a tarball of the `/var/lib/docker/swarm` directory. It's also recommended to back up the manager's TLS key and certificate.

### Restore

To restore, you would stop Docker on the new manager node, replace the `/var/lib/docker/swarm` directory with your backup, and then start Docker again.

For more details, refer to the official Docker documentation on [backing up and restoring a Swarm](https://docs.docker.com/engine/swarm/admin_guide/#back-up-the-swarm).

## 6. Node Labeling and Constraint-based Scheduling

Node labels allow you to add custom metadata to your Swarm nodes, which can then be used for service placement constraints.

### Adding Labels to a Node

```bash
# Example: Add a label for the region
docker node update --label-add region=us-east-1 my-node-1

# Example: Add a label for a special hardware type
docker node update --label-add storage=ssd my-node-2
```

### Using Constraints in `docker-compose.yml`

You can use these labels in your `docker-compose.yml` file to control where your services are scheduled. The `backend` service in this project already uses a placement preference to spread replicas across regions.

Here's an example of a hard constraint:

```yaml
services:
  my-service:
    deploy:
      placement:
        constraints:
          - node.labels.storage == ssd
```

This ensures that `my-service` will only be scheduled on nodes with the label `storage=ssd`.
