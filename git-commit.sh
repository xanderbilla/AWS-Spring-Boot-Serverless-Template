#!/bin/bash

# Git Commit Script for Spring Boot Serverless Demo Project
# This script organizes and commits the project with proper commit messages

set -e  # Exit on any error

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project information
PROJECT_NAME="AWS Spring Boot Serverless Template"
PROJECT_VERSION="0.0.1-SNAPSHOT"

echo -e "${BLUE}🚀 Starting Git commit process for ${PROJECT_NAME}${NC}"
echo -e "${BLUE}================================================${NC}"

# Function to print status messages
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if git is installed
if ! command -v git &> /dev/null; then
    print_error "Git is not installed. Please install Git first."
    exit 1
fi

# Initialize git repository if it doesn't exist
if [ ! -d ".git" ]; then
    print_warning "Git repository not found. Initializing..."
    git init
    print_status "Git repository initialized"
else
    print_status "Git repository found"
fi

# Create .gitignore if it doesn't exist
if [ ! -f ".gitignore" ]; then
    print_warning "Creating .gitignore file..."
    cat > .gitignore << 'EOF'
# Compiled class files
*.class
target/

# Log files
*.log

# Package Files
*.jar
*.war
*.nar
*.ear
*.zip
*.tar.gz
*.rar

# Maven
.m2/
**/target/
pom.xml.tag
pom.xml.releaseBackup
pom.xml.versionsBackup
pom.xml.next
release.properties
dependency-reduced-pom.xml
buildNumber.properties
.mvn/timing.properties
.mvn/wrapper/maven-wrapper.jar

# IDE files
.idea/
*.iml
*.ipr
*.iws
.vscode/
.classpath
.project
.settings/

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# AWS SAM
.aws-sam/
samconfig.toml

# Environment files
.env
.env.local
.env.*.local

# Temporary files
*.tmp
*.temp
*~
EOF
    print_status ".gitignore created"
fi

# Function to commit files with organized structure
commit_files() {
    local commit_type="$1"
    local scope="$2"
    local description="$3"
    local files="$4"
    
    if [ -n "$files" ]; then
        git add $files
        local commit_message="${commit_type}"
        if [ -n "$scope" ]; then
            commit_message="${commit_message}(${scope})"
        fi
        commit_message="${commit_message}: ${description}"
        
        git commit -m "$commit_message"
        print_status "Committed: $commit_message"
    fi
}

# Check if there are any files to commit
if [ -z "$(git status --porcelain 2>/dev/null)" ] && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
    print_warning "No changes to commit"
    exit 0
fi

echo -e "\n${BLUE}📦 Organizing commits by categories...${NC}"

# Stage and commit configuration files
echo -e "\n${YELLOW}1. Configuration Files${NC}"
config_files=""
[ -f "pom.xml" ] && config_files="$config_files pom.xml"
[ -f "template.yaml" ] && config_files="$config_files template.yaml"
[ -f "mvnw" ] && config_files="$config_files mvnw"
[ -f "mvnw.cmd" ] && config_files="$config_files mvnw.cmd"
[ -f ".gitignore" ] && config_files="$config_files .gitignore"

if [ -n "$config_files" ]; then
    commit_files "feat" "config" "add project configuration and build files" "$config_files"
fi

# Stage and commit application properties
echo -e "\n${YELLOW}2. Application Configuration${NC}"
if [ -d "src/main/resources" ]; then
    props_files=""
    [ -f "src/main/resources/application.properties" ] && props_files="$props_files src/main/resources/application.properties"
    [ -f "src/main/resources/application-dev.properties" ] && props_files="$props_files src/main/resources/application-dev.properties"
    [ -f "src/main/resources/application-local.properties" ] && props_files="$props_files src/main/resources/application-local.properties"
    
    if [ -n "$props_files" ]; then
        commit_files "feat" "config" "add application properties for different environments" "$props_files"
    fi
fi

# Stage and commit main application class
echo -e "\n${YELLOW}3. Main Application${NC}"
if [ -f "src/main/java/com/example/demo/DemoApplication.java" ]; then
    commit_files "feat" "app" "add Spring Boot main application class" "src/main/java/com/example/demo/DemoApplication.java"
fi

# Stage and commit DTOs
echo -e "\n${YELLOW}4. Data Transfer Objects${NC}"
if [ -d "src/main/java/com/example/demo/dto" ]; then
    commit_files "feat" "dto" "add API response and health response DTOs" "src/main/java/com/example/demo/dto/"
fi

# Stage and commit controllers
echo -e "\n${YELLOW}5. Controllers${NC}"
if [ -d "src/main/java/com/example/demo/controller" ]; then
    commit_files "feat" "api" "add health check and error handling controllers" "src/main/java/com/example/demo/controller/"
fi

# Stage and commit exception handling
echo -e "\n${YELLOW}6. Exception Handling${NC}"
if [ -d "src/main/java/com/example/demo/exception" ]; then
    commit_files "feat" "error" "add global exception handler" "src/main/java/com/example/demo/exception/"
fi

# Stage and commit AWS Lambda handler
echo -e "\n${YELLOW}7. AWS Lambda Handler${NC}"
if [ -d "src/main/java/com/example/demo/handler" ]; then
    commit_files "feat" "aws" "add AWS Lambda stream handler for serverless deployment" "src/main/java/com/example/demo/handler/"
fi

# Stage and commit tests
echo -e "\n${YELLOW}8. Tests${NC}"
if [ -d "src/test" ]; then
    commit_files "test" "app" "add Spring Boot application tests" "src/test/"
fi

# Stage and commit deployment script
echo -e "\n${YELLOW}9. Deployment${NC}"
deploy_files=""
[ -f "deploy.sh" ] && deploy_files="$deploy_files deploy.sh"
[ -f "git-commit.sh" ] && deploy_files="$deploy_files git-commit.sh"

if [ -n "$deploy_files" ]; then
    commit_files "feat" "deploy" "add deployment and git commit automation scripts" "$deploy_files"
fi

# Stage and commit documentation
echo -e "\n${YELLOW}10. Documentation${NC}"
if [ -f "README.md" ]; then
    commit_files "docs" "" "add comprehensive project documentation and API reference" "README.md"
fi

# Stage any remaining files
echo -e "\n${YELLOW}11. Additional Files${NC}"
remaining_files=$(git ls-files --others --exclude-standard 2>/dev/null || true)
if [ -n "$remaining_files" ]; then
    commit_files "feat" "misc" "add additional project files" "$remaining_files"
fi

# Check for any unstaged changes
unstaged_changes=$(git diff --name-only 2>/dev/null || true)
if [ -n "$unstaged_changes" ]; then
    echo -e "\n${YELLOW}12. Modified Files${NC}"
    commit_files "fix" "update" "update modified files" "$unstaged_changes"
fi

echo -e "\n${GREEN}🎉 All commits completed successfully!${NC}"
echo -e "${BLUE}================================================${NC}"

# Show git log summary
echo -e "\n${BLUE}📋 Commit Summary:${NC}"
git log --oneline -10 2>/dev/null || echo "No commits found"

echo -e "\n${GREEN}✅ Project successfully committed with organized commit messages!${NC}"
echo -e "${BLUE}💡 Tip: You can now push to your remote repository with: git push origin main${NC}"
