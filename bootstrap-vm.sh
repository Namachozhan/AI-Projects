#!/usr/bin/env bash
# Prepare a fresh Ubuntu VM for KubePilot: git, unzip, Docker Engine + Compose plugin, Azure CLI.
# Run as your normal user (NOT root); it uses sudo where needed.   bash bootstrap-vm.sh
# Safe to run again: steps that are already done are skipped.
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user (e.g. azureuser), not as root." >&2
  exit 1
fi
. /etc/os-release
if [ "${ID:-}" != "ubuntu" ]; then
  echo "This script is written for Ubuntu (found: ${ID:-unknown})." >&2
  exit 1
fi

# A fresh VM may still be running automatic updates and holding the apt lock.
APT="sudo apt-get -o DPkg::Lock::Timeout=300 -y"

echo "==> 1/4 Base packages (git, unzip, curl, certificates)"
$APT update
$APT install ca-certificates curl gnupg lsb-release git unzip

echo "==> 2/4 Docker Engine and the Compose plugin (from Docker's official apt repository)"
if ! command -v docker >/dev/null 2>&1; then
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  $APT update
  $APT install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  echo "    docker already installed, skipping"
fi
sudo systemctl enable --now docker
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  sudo usermod -aG docker "$USER"
  RELOGIN_MSG="Log out and back in (or run: newgrp docker) so you can use docker without sudo."
else
  RELOGIN_MSG="Docker group membership is already active; nothing to do."
fi

echo "==> 3/4 Azure CLI (Microsoft's official installer for Debian/Ubuntu)"
if ! command -v az >/dev/null 2>&1; then
  curl -fsSL https://aka.ms/InstallAzureCLIDeb -o /tmp/install-azure-cli.sh
  sudo bash /tmp/install-azure-cli.sh
  rm -f /tmp/install-azure-cli.sh
else
  echo "    az already installed, skipping"
fi

echo "==> 4/4 Versions"
git --version
sudo docker --version
sudo docker compose version
az version --query '"azure-cli"' -o tsv 2>/dev/null | sed 's/^/azure-cli /' || true

cat <<EOF

Done. Next steps:

  1. ${RELOGIN_MSG}
  2. Get the code:        git clone <your-repo-url> && cd <repo>
  3. Create the config:   cp .env.example .env     (keep MOCK_MODE=true for the first run)
  4. Start the app:       docker compose up --build -d
  5. To use ACR with the VM's managed identity:
       az login --identity --client-id <identity_client_id from terraform output>
       az acr login --name <acr_name from terraform output>
     and add AZURE_CLIENT_ID=<identity_client_id> to .env for the live Azure calls.
EOF
