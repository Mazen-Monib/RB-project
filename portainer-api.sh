#!/bin/bash

# This script provides a simple command-line interface for interacting with the Portainer API.
# It allows you to list stacks and deploy/update a stack from a docker-compose file.

# --- Configuration ---
PORTAINER_URLS=(
  "http://localhost:9000"
  # Add other Portainer endpoints here
)
# Use the first URL as the default
PORTAINER_URL=${PORTAINER_URLS[0]}
PORTAINER_API_KEY="" # Your Portainer API key

# --- Usage ---
usage() {
  echo "Usage: $0 [-u <portainer_url>] [-k <api_key>] <action>"
  echo "Actions:"
  echo "  list                  List all stacks."
  echo "  deploy <stack_name> <compose_file>  Deploy or update a stack."
  exit 1
}

# --- Functions ---

# Function to authenticate with the Portainer API
authenticate() {
  response=$(curl -s -H "X-API-Key: $PORTAINER_API_KEY" "$PORTAINER_URL/api/endpoints")
  if ! echo "$response" | grep -q "Id"; then
    echo "Authentication failed. Please check your API key and Portainer URL."
    exit 1
  fi
}

# Function to list all stacks
list_stacks() {
  curl -s -H "X-API-Key: $PORTAINER_API_KEY" "$PORTAINER_URL/api/stacks" | jq .
}

# Function to deploy or update a stack
deploy_stack() {
  stack_name=$1
  compose_file=$2

  if [ ! -f "$compose_file" ]; then
    echo "Compose file not found: $compose_file"
    exit 1
  fi

  # Check if the stack already exists
  stack_id=$(curl -s -H "X-API-Key: $PORTAINER_API_KEY" "$PORTAINER_URL/api/stacks" | jq -r ".[] | select(.Name == \"$stack_name\") | .Id")

  if [ -n "$stack_id" ]; then
    # Update existing stack
    echo "Updating stack: $stack_name"
    curl -s -X PUT \
      -H "X-API-Key: $PORTAINER_API_KEY" \
      -H "Content-Type: application/json" \
      --data-binary @- \
      "$PORTAINER_URL/api/stacks/$stack_id?endpointId=1" <<EOF
{
  "stackFileContent": "$(cat $compose_file | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n')"
}
EOF
  else
    # Create new stack
    echo "Creating new stack: $stack_name"
    curl -s -X POST \
      -H "X-API-Key: $PORTAINER_API_KEY" \
      -H "Content-Type: application/json" \
      --data-binary @- \
      "$PORTAINER_URL/api/stacks?type=1&method=file&endpointId=1" <<EOF
{
  "name": "$stack_name",
  "stackFileContent": "$(cat $compose_file | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n')"
}
EOF
  fi
}

# Function to validate deployment status (placeholder)
validate_deployment() {
  echo "Validating deployment... (This is a placeholder)"
  # In a real script, you would poll the service status until it's healthy.
}

# --- Main Script ---

while getopts "u:k:" opt; do
  case $opt in
    u) PORTAINER_URL=$OPTARG ;;
    k) PORTAINER_API_KEY=$OPTARG ;;
    *) usage ;;
  esac
done
shift $((OPTIND -1))

if [ -z "$PORTAINER_API_KEY" ]; then
  echo "Error: API key is required."
  usage
fi

action=$1
if [ -z "$action" ]; then
  usage
fi

authenticate

case $action in
  list)
    list_stacks
    ;;
  deploy)
    if [ $# -ne 3 ]; then
      usage
    fi
    deploy_stack "$2" "$3"
    validate_deployment
    ;;
  *)
    usage
    ;;
esac
