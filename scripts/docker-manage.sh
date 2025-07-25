#!/bin/bash

# OpenCut Docker Management Script
# This script helps manage Docker deployments for OpenCut

set -e

REGISTRY="ghcr.io"
IMAGE_NAME="ariqpradipa/opencut"
DEFAULT_TAG="latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo -e "${BLUE}"
    echo "🐳 OpenCut Docker Management"
    echo "=============================="
    echo -e "${NC}"
}

# Check if Docker is running
check_docker() {
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
}

# Pull latest image
pull_image() {
    local tag=${1:-$DEFAULT_TAG}
    local image="$REGISTRY/$IMAGE_NAME:$tag"
    
    print_info "Pulling image: $image"
    docker pull "$image"
    print_success "Image pulled successfully"
}

# List available tags (requires gh CLI or manual check)
list_tags() {
    print_info "Available tags can be viewed at:"
    echo "https://github.com/ariqpradipa/opencut/pkgs/container/opencut"
    echo ""
    print_info "Common tags:"
    echo "  - latest (most recent build)"
    echo "  - v0.1.0 (specific version)"
    echo "  - docker-build (development branch)"
    echo "  - sha-{commit} (specific commit)"
}

# Run with environment variables
run_with_env() {
    local tag=${1:-$DEFAULT_TAG}
    local image="$REGISTRY/$IMAGE_NAME:$tag"
    local port=${2:-3000}
    
    print_info "Running OpenCut with environment variables on port $port"
    print_warning "Make sure to set required environment variables"
    
    # Check if .env.docker exists
    local env_file=""
    if [ -f ".env.docker" ]; then
        env_file="--env-file .env.docker"
        print_info "Using environment file: .env.docker"
    else
        print_warning "No .env.docker file found. Using minimal configuration."
        print_info "Create .env.docker from template for full configuration."
    fi
    
    docker run -it --rm \
        -p "$port:3000" \
        $env_file \
        -e NODE_ENV=production \
        -e NEXT_TELEMETRY_DISABLED=1 \
        "$image"
}

# Start with docker-compose (production)
start_compose_prod() {
    local tag=${1:-$DEFAULT_TAG}
    local env_file=${2:-.env.docker}
    
    if [ ! -f "docker-compose.prod.yaml" ]; then
        print_error "docker-compose.prod.yaml not found. Run this script from the project root."
        exit 1
    fi
    
    # Check if environment file exists and offer to create it
    if [ ! -f "$env_file" ] && [ "$env_file" = ".env.docker" ]; then
        if [ -f ".env.docker.template" ]; then
            print_warning "Environment file $env_file not found."
            echo -n "Create from template? (y/N): "
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                cp .env.docker.template "$env_file"
                print_success "Created $env_file from template. Please edit it with your values."
                print_info "Required: Update BETTER_AUTH_SECRET and database credentials"
                return 1
            fi
        else
            print_warning "Environment file $env_file not found. Using default values."
        fi
    fi
    
    # Update the image tag in docker-compose.prod.yaml if custom tag provided
    if [ "$tag" != "$DEFAULT_TAG" ]; then
        print_info "Using custom tag: $tag"
        sed -i.bak "s|image: $REGISTRY/$IMAGE_NAME:.*|image: $REGISTRY/$IMAGE_NAME:$tag|g" docker-compose.prod.yaml
    fi
    
    print_info "Starting OpenCut with docker-compose (production)"
    
    # Use environment file if it exists
    if [ -f "$env_file" ]; then
        print_info "Using environment file: $env_file"
        docker-compose --env-file "$env_file" -f docker-compose.prod.yaml up -d
    else
        docker-compose -f docker-compose.prod.yaml up -d
    fi
    
    # Restore original file if we modified it
    if [ "$tag" != "$DEFAULT_TAG" ] && [ -f "docker-compose.prod.yaml.bak" ]; then
        mv docker-compose.prod.yaml.bak docker-compose.prod.yaml
    fi
    
    print_success "OpenCut started! Access it at http://localhost:3100"
    print_info "View logs with: $0 logs"
}

# Create environment file from template
create_env() {
    local env_file=${1:-.env.docker}
    
    if [ ! -f ".env.docker.template" ]; then
        print_error ".env.docker.template not found. Run this script from the project root."
        exit 1
    fi
    
    if [ -f "$env_file" ]; then
        echo -n "File $env_file already exists. Overwrite? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_info "Skipping file creation."
            return 0
        fi
    fi
    
    cp .env.docker.template "$env_file"
    print_success "Created $env_file from template"
    print_warning "Remember to update the following required values:"
    echo "  - BETTER_AUTH_SECRET (generate with: openssl rand -base64 32)"
    echo "  - Database credentials if using external database"
    echo "  - NEXT_PUBLIC_BETTER_AUTH_URL if deploying to custom domain"
}

# Start with docker-compose (development - builds locally)
start_compose_dev() {
    if [ ! -f "docker-compose.yaml" ]; then
        print_error "docker-compose.yaml not found. Run this script from the project root."
        exit 1
    fi
    
    print_info "Starting OpenCut with docker-compose (development - building locally)"
    docker-compose up -d --build
    print_success "OpenCut started! Access it at http://localhost:3100"
}
# Stop services
stop_services() {
    print_info "Stopping OpenCut services..."
    
    # Stop production configuration
    if [ -f "docker-compose.prod.yaml" ]; then
        docker-compose -f docker-compose.prod.yaml down
    fi
    
    # Stop development configuration
    if [ -f "docker-compose.yaml" ]; then
        docker-compose down
    fi
    
    print_success "Services stopped"
}

# Show logs
show_logs() {
    local service=${1:-web}
    
    if docker-compose -f docker-compose.prod.yaml ps -q "$service" &> /dev/null; then
        docker-compose -f docker-compose.prod.yaml logs -f "$service"
    elif docker-compose ps -q "$service" &> /dev/null; then
        docker-compose logs -f "$service"
    else
        print_error "Service '$service' not found or not running"
        exit 1
    fi
}

# Update to latest version
update() {
    local tag=${1:-$DEFAULT_TAG}
    
    print_info "Updating OpenCut to tag: $tag"
    pull_image "$tag"
    stop_services
    start_compose_prod "$tag"
    print_success "OpenCut updated successfully!"
}

# Show usage
usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  pull [TAG]              Pull Docker image (default: latest)"
    echo "  run [TAG] [PORT]        Run with environment variables (default: latest, 3000)"
    echo "  start-prod [TAG] [ENV]  Start with docker-compose using published image"
    echo "  start-dev               Start with docker-compose building locally"
    echo "  stop                    Stop all services"
    echo "  logs [SERVICE]          Show logs (default: web)"
    echo "  update [TAG]            Update to latest version"
    echo "  create-env [FILE]       Create environment file from template"
    echo "  tags                    List available tags"
    echo "  help                    Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 create-env                              # Create .env.docker from template"
    echo "  $0 pull                                    # Pull latest image"
    echo "  $0 pull v0.1.0                           # Pull specific version"
    echo "  $0 start-prod                             # Start with latest image"
    echo "  $0 start-prod v0.1.0 .env.production     # Start with specific version and env file"
    echo "  $0 run latest 8080                       # Run on port 8080"
    echo "  $0 logs web                               # Show web service logs"
    echo "  $0 update v0.2.0                         # Update to v0.2.0"
    echo ""
    echo "Environment Files:"
    echo "  .env.docker            Default environment file"
    echo "  .env.docker.template   Template with all available options"
    echo "  .env.production        Custom production environment file"
}

# Main script
main() {
    print_header
    check_docker
    
    case ${1:-help} in
        pull)
            pull_image "$2"
            ;;
        run)
            run_with_env "$2" "$3"
            ;;
        start-prod)
            start_compose_prod "$2" "$3"
            ;;
        start-dev)
            start_compose_dev
            ;;
        stop)
            stop_services
            ;;
        logs)
            show_logs "$2"
            ;;
        update)
            update "$2"
            ;;
        create-env)
            create_env "$2"
            ;;
        tags)
            list_tags
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            print_error "Unknown command: $1"
            echo ""
            usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
