#!/bin/bash

# Quick Git Commit Script
# Usage: ./quick-commit.sh "your commit message" [type]
# Types: feat, fix, docs, test, refactor, style, chore

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Default commit type
COMMIT_TYPE="feat"

# Parse arguments
if [ $# -eq 0 ]; then
    echo -e "${RED}Usage: $0 \"commit message\" [type]${NC}"
    echo -e "${YELLOW}Types: feat, fix, docs, test, refactor, style, chore${NC}"
    echo -e "${BLUE}Example: $0 \"add user authentication\" feat${NC}"
    exit 1
fi

COMMIT_MESSAGE="$1"
if [ $# -eq 2 ]; then
    COMMIT_TYPE="$2"
fi

# Validate commit type
case $COMMIT_TYPE in
    feat|fix|docs|test|refactor|style|chore)
        ;;
    *)
        echo -e "${RED}Invalid commit type: $COMMIT_TYPE${NC}"
        echo -e "${YELLOW}Valid types: feat, fix, docs, test, refactor, style, chore${NC}"
        exit 1
        ;;
esac

echo -e "${BLUE}🚀 Quick commit with type: ${COMMIT_TYPE}${NC}"

# Check for changes
if [ -z "$(git status --porcelain 2>/dev/null)" ]; then
    echo -e "${YELLOW}⚠ No changes to commit${NC}"
    exit 0
fi

# Show what will be committed
echo -e "\n${YELLOW}Files to be committed:${NC}"
git status --short

# Add all changes
git add .

# Create commit message
FULL_MESSAGE="${COMMIT_TYPE}: ${COMMIT_MESSAGE}"

# Commit
git commit -m "$FULL_MESSAGE"

echo -e "\n${GREEN}✅ Committed: ${FULL_MESSAGE}${NC}"

# Show recent commits
echo -e "\n${BLUE}Recent commits:${NC}"
git log --oneline -5
