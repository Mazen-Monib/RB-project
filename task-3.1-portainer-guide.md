# Task 3.1: Portainer Stack Management & API Automation

This guide provides a step-by-step walkthrough for deploying and managing the application stack using Portainer, as required by Task 3.1.

## 1. Deploying Portainer

The `docker-compose.yml` file has been updated to include the Portainer service. To deploy it, simply run:

```bash
docker stack deploy --compose-file docker-compose.yml my_stack
```

This will deploy Portainer alongside the other services in the stack.

### Accessing Portainer

1.  Once the stack is deployed, Portainer will be available on port `9000` of your Swarm manager node.
2.  Open a web browser and navigate to `http://<your_swarm_manager_ip>:9000`.
3.  You will be prompted to create an administrator account. Set a strong password.
4.  On the next screen, choose "Docker" as the environment to manage, and Portainer will automatically connect to the local Swarm environment.

## 2. Deploying Stacks with Portainer

### Using the UI

1.  In the Portainer UI, navigate to "Stacks" in the left-hand menu.
2.  Click "Add stack".
3.  Give the stack a name (e.g., `my_app_stack`).
4.  You can either upload the `docker-compose.yml` file or copy and paste its contents into the "Web editor".
5.  Click "Deploy the stack".

Portainer will then deploy the stack, and you can monitor the services and containers from the Portainer UI.

### Using the API

1.  **Get an API key:** In Portainer, go to "Users" -> your user -> "API Keys". Create a new API key.
2.  **Get the stack ID:** You can get the stack ID from the "Stacks" page in the UI.
3.  **Deploy the stack using `curl`:**

```bash
curl -X POST \
  -H "X-API-Key: <your_api_key>" \
  -H "Content-Type: application/json" \
  --data '{ 
    "stackFileContent": "<your_docker_compose_file_content_as_a_string>"
  }' \
  http://<your_portainer_ip>:9000/api/stacks
```

## 3. Managing Environment Variables

Portainer provides a convenient way to manage environment variables for your stacks.

When creating or updating a stack, you can use the "Environment variables" section in the UI. Here, you can define environment variables that will be available to the services in your stack.

For sensitive data, it's always recommended to use Docker secrets. You can manage secrets in Portainer under the "Secrets" menu.

## 4. Using Portainer Templates

Portainer templates allow for repeatable deployments of common applications.

1.  Go to "App Templates".
2.  You can use one of the existing templates or create your own.
3.  To create a custom template, you can provide a `docker-compose.yml` file and define any custom fields that the user should fill in.

This is useful for creating a "one-click" deployment for your application stack.

## 5. Best Practices for Organizing Stacks

- **Naming:** Use clear and consistent naming for your stacks (e.g., `app-prod`, `app-staging`, `monitoring`).
- **Tagging:** Use tags to group related stacks (e.g., `production`, `development`, `database`).
- **Git-based deployment:** For production environments, it's recommended to connect Portainer to a Git repository. This allows for automated deployments whenever you push changes to your `docker-compose.yml` file.
- **Access Control:** Use Portainer's role-based access control (RBAC) to restrict who can deploy and manage stacks in different environments.
