#!/bin/bash
set -euo pipefail

# === Setup Github-runner ===

# === Configurable environment variables ===
GITHUB_ORG="$${GITHUB_ORG:-aka-org}"                    # GitHub org name
RUNNER_NAME="$${GITHUB_RUNNER_NAME:-$(hostname)}"       # Runner name
RUNNER_VERSION="$${RUNNER_VERSION:-2.323.0}"            # GitHub Runner version (default: latest as of now)
RUNNER_LABELS="$${RUNNER_LABELS-ansible,docker}"        # Github Runner Labels
RUNNER_DIR="$${RUNNER_DIR:-/opt/github-runner}"         # Installation path
RUNNER_USER="$${RUNNER_USER:-github-runner}"            # Github runner system user

# === Derived variables ===
RUNNER_URL="https://github.com/$${GITHUB_ORG}"
RUNNER_TGZ="actions-runner-linux-x64-$${RUNNER_VERSION}.tar.gz"
DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v$${RUNNER_VERSION}/$${RUNNER_TGZ}"
VENV_DIR="/home/$RUNNER_USER/.ansible_venv"
PLUGIN_PATH="/home/$RUNNER_USER/.ansible/plugins/inventory"
RUNNER_PRIVATE_KEY_DIR="/home/$RUNNER_USER/.ssh"

# === Get secret from secret manager ===
GITHUB_PAT=$(gcloud secrets versions access latest --secret="${secret_id}" --quiet)

# === Ensure runner user exists ===
echo "[*] Creating runner user"
sudo useradd -m -s /bin/bash "$RUNNER_USER" || true 
sudo mkdir -p "$RUNNER_PRIVATE_KEY_DIR"
sudo chown $RUNNER_USER:$RUNNER_USER $RUNNER_PRIVATE_KEY_DIR

# === Install ansible ===
echo "[+] Installing Ansible and dependencies"

# Install system dependencies
sudo apt-get update -y
sudo apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    git \
    curl

# Ensure virtualenv exists
if [[ ! -d "$VENV_DIR" ]]; then
  sudo -u "$RUNNER_USER" python3 -m venv "$VENV_DIR"
fi

# Setup Ansible
sudo -u "$RUNNER_USER" bash -c '
  VENV_DIR="/home/$USER/.ansible_venv"

  # Activate virtualenv
  source "$VENV_DIR/bin/activate"

  # Upgrade pip and install Ansible + GCP requirements
  echo "[+] Installing Python dependencies"
  pip install --upgrade pip
  pip install ansible google-auth requests google-api-python-client

  # Install Ansible collections
  ansible-galaxy collection install community.google

  # Confirm Ansible is installed
  echo "[*] Ansible version:"
  ansible --version

  # Deactivate venv
  deactivate
'
echo "[✓] Finished setting up Ansible with GCPinventory support."

# Installing Docker
sudo apt install -y docker.io
sudo usermod -aG docker $RUNNER_USER

echo "[✓] Finished setting up Docker." 

# === Ensure runner directory exists ===
sudo mkdir -p "$RUNNER_DIR"
sudo chown $RUNNER_USER:$RUNNER_USER $RUNNER_DIR
cd "$RUNNER_DIR"

# === Install runner if not already installed ===
if [[ ! -f "./config.sh" ]]; then
  echo "[+] Downloading GitHub Actions runner v$RUNNER_VERSION..."
  sudo -u $RUNNER_USER curl -sL -o "$RUNNER_TGZ" "$DOWNLOAD_URL"
  sudo -u $RUNNER_USER tar -xzf "$RUNNER_TGZ"
  sudo -u $RUNNER_USER rm "$RUNNER_TGZ"
fi

# === Get registration token from GitHub ===
echo "[+] Requesting GitHub registration token..."
TOKEN_RESPONSE=$(curl -X POST \
  -H "Authorization: Bearer $${GITHUB_PAT}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/orgs/$${GITHUB_ORG}/actions/runners/registration-token")

RUNNER_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -oP '"token"\s*:\s*"\K[^"]+')

if [[ -z "$RUNNER_TOKEN" ]]; then
  echo "[!] Failed to retrieve runner registration token. Response:"
  echo "$TOKEN_RESPONSE"
  exit 1
fi

# === Register runner only if not already registered ===
if [[ ! -d ".runner" ]]; then
  echo "[+] Configuring the GitHub runner..."
  sudo -u $RUNNER_USER ./config.sh --unattended \
    --url "$RUNNER_URL" \
    --token "$RUNNER_TOKEN" \
    --name "$RUNNER_NAME" \
    --work "_work" \
    --labels "$RUNNER_LABELS" \
    --replace
else
  echo "[+] Runner already configured. Skipping registration."
fi

# Derive the service name based on GitHub org/repo and runner name
SERVICE_NAME="actions.runner.$${GITHUB_ORG}.$${RUNNER_NAME}.service"

# === Install and start runner as a service (idempotent) ===
if [[ ! -f "/etc/systemd/system/github-runner.service" ]]; then
  echo "[+] Installing runner as a systemd service..."
  sudo ./svc.sh install $RUNNER_USER
  sudo systemctl enable $SERVICE_NAME 
  sudo systemctl start $SERVICE_NAME
else
  echo "[+] GitHub runner systemd service already installed."
  sudo systemctl restart $SERVICE_NAME
fi

echo "[✓] Finished setting up Github-runner."
