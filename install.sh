#!/bin/bash

# Exit immediately if any command fails
set -e

# Progress bar function using pv
progress_bar() {
  local duration=${1}
  local message=${2}
  echo "$message"
  (
    for i in $(seq 1 $duration); do
      echo -n "▇"
      sleep 1
    done
    echo ""
  ) | pv -pte -l -s $duration > /dev/null
}

echo "🚀 Setting up epsilon.fm inside Docker on Debian 12 Minimal OS inside Proxmox LXC..."

# Ensure the script is running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root! Use sudo su or run with sudo."
   exit 1
fi

# Install pv for progress bars if not installed
if ! command -v pv &> /dev/null; then
    echo "📥 Installing pv for progress bars..."
    apt update && apt install -y pv
fi

# Function to remove a package if installed
remove_if_installed() {
    if dpkg -l | grep -q "$1"; then
        echo "🗑️ Removing existing installation of $1..."
        apt remove --purge -y "$1"
        apt autoremove -y
        apt clean
    fi
}

# Disable UFW Firewall
echo "🛡️ Disabling UFW firewall..."
if command -v ufw &> /dev/null; then
    sudo ufw disable
    sudo systemctl stop ufw
    sudo systemctl disable ufw
    echo "✅ UFW has been disabled."
else
    echo "⚠️ UFW is not installed. Skipping firewall disable step."
fi
progress_bar 3 "🔄 Disabling Firewall..."

# Update and install required system dependencies
echo "🔄 Updating system packages..."
apt update && apt upgrade -y
progress_bar 5 "📦 System packages updated."

# Remove and reinstall essential packages
echo "📦 Removing old packages and installing required dependencies..."
PACKAGES=(
    docker.io
    git
    curl
    sudo
    ca-certificates
    wget
    postgresql-client
)

for package in "${PACKAGES[@]}"; do
    remove_if_installed "$package"
    apt install -y "$package"
done
progress_bar 5 "📦 Essential packages installed."

# Install Docker Compose (if not installed)
if ! command -v docker-compose &> /dev/null; then
    echo "📥 Installing Docker Compose..."
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
    progress_bar 3 "🐳 Docker Compose installed."
fi

# Ensure Docker service is running and enabled at boot
echo "🐳 Starting and enabling Docker service..."
systemctl enable --now docker
progress_bar 3 "🐳 Docker service is running."

# Get server's IP address (excluding localhost)
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "🌐 Detected Server IP: $SERVER_IP"

# Remove old epsilon.fm installation if it exists
if [[ -d "epsilon.fm" ]]; then
    echo "🗑️ Removing existing epsilon.fm directory..."
    rm -rf epsilon.fm
    progress_bar 2 "📂 Old epsilon.fm directory removed."
fi

# Clone epsilon.fm repository
echo "📥 Cloning the epsilon.fm repository..."
git clone https://github.com/epsilon-records/epsilon.fm.git
cd epsilon.fm
progress_bar 3 "📥 Repository cloned."

# Create Dockerfile
echo "📝 Creating Dockerfile..."
cat <<EOF > Dockerfile
# Use an official Bun image
FROM oven/bun:1.0.0

# Set working directory inside the container
WORKDIR /app

# Copy package files first to leverage Docker cache
COPY package.json bun.lockb ./

# Install dependencies
RUN bun install

# Copy all files into the container
COPY . .

# Set environment variables
ENV DATABASE_URL=postgresql://epsilonfm_user:password@postgres/epsilonfm
ENV REDIS_URL=redis://redis:6379

# Expose the application port
EXPOSE 3000

# Start the application
CMD ["bun", "run", "dev", "--", "--host", "0.0.0.0", "--open"]
EOF
progress_bar 2 "✅ Dockerfile created."

# Create docker-compose.yml
echo "📝 Creating docker-compose.yml..."
cat <<EOF > docker-compose.yml
version: "3.8"

services:
  app:
    build: .
    container_name: epsilon_app
    restart: unless-stopped
    env_file: .env
    ports:
      - "3000:3000"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  postgres:
    image: postgres:15
    container_name: epsilon_postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: epsilonfm
      POSTGRES_USER: epsilonfm_user
      POSTGRES_PASSWORD: password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U epsilonfm_user"]
      interval: 10s
      retries: 5
      timeout: 5s

  redis:
    image: redis:alpine
    container_name: epsilon_redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      retries: 5
      timeout: 3s

volumes:
  postgres_data:
EOF
progress_bar 2 "✅ docker-compose.yml created."

# Create .env file with server IP
echo "📝 Creating .env file..."
cat <<EOF > .env
DATABASE_URL=postgresql://epsilonfm_user:password@${SERVER_IP}/epsilonfm
REDIS_URL=redis://redis:6379
EOF
progress_bar 2 "✅ .env file created with server IP."

# Build and run the Docker containers
echo "🐳 Building and starting Docker containers..."
docker-compose up -d --build
progress_bar 5 "🚀 Docker containers built and started."

# Enable auto-start of Docker containers on boot
echo "🔄 Ensuring Docker containers auto-start on boot..."
crontab -l | { cat; echo "@reboot sleep 10 && cd $(pwd) && /usr/local/bin/docker-compose up -d"; } | crontab -
progress_bar 3 "✅ Auto-start configured."

# Final message before reboot
echo "✅ epsilon.fm is now installed and running!"
echo "🌐 Open your browser and go to: http://$SERVER_IP:3000"
echo "🔄 The system will reboot in 10 seconds to apply all changes..."
echo "📝 Created by Ivan Gonzalez @i.gonzolv"

# Wait for 10 seconds before reboot
sleep 10

# Reboot the server
reboot
