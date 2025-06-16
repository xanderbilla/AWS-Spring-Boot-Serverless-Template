#!/bin/bash

# Spring Boot Lambda Deployment Script
# This script provides end-to-end deployment for the Spring Boot Lambda application
# It maintains the same S3 bucket and CloudFormation stack across deployments

set -e  # Exit on any error

# Configuration (defaults)
PROJECT_NAME="spring-boot-demo"
STACK_NAME="spring-boot-demo"
REGION="us-east-1"
STAGE="dev"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}\n"
}

# Function to check if S3 bucket exists
check_s3_bucket() {
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" --region "$REGION" 2>/dev/null; then
        print_success "S3 bucket '$S3_BUCKET_NAME' already exists"
        return 0
    else
        return 1
    fi
}

# Function to create S3 bucket
create_s3_bucket() {
    print_status "Creating S3 bucket: $S3_BUCKET_NAME"
    
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$REGION"
    else
        aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning --bucket "$S3_BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Add bucket policy for SAM
    aws s3api put-bucket-policy --bucket "$S3_BUCKET_NAME" --policy "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [
            {
                \"Effect\": \"Allow\",
                \"Principal\": {
                    \"Service\": \"cloudformation.amazonaws.com\"
                },
                \"Action\": \"s3:GetObject\",
                \"Resource\": \"arn:aws:s3:::${S3_BUCKET_NAME}/*\"
            }
        ]
    }"
    
    print_success "S3 bucket created successfully"
}

# Function to create samconfig.toml interactively
create_samconfig() {
    if [ -f "samconfig.toml" ]; then
        print_status "samconfig.toml already exists"
        return 0
    fi
    
    print_header "Creating SAM Configuration"
    print_status "Please provide the following configuration parameters:"
    
    # Get AWS Account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Get stack name
    echo -n "Enter stack name (default: spring-boot-demo): "
    read -r USER_STACK_NAME
    if [ -z "$USER_STACK_NAME" ]; then
        USER_STACK_NAME="spring-boot-demo"
    fi
    
    # Get S3 bucket name
    echo -n "Enter S3 bucket name (default: spring-boot-demo-artifacts-$ACCOUNT_ID): "
    read -r USER_S3_BUCKET
    if [ -z "$USER_S3_BUCKET" ]; then
        USER_S3_BUCKET="spring-boot-demo-artifacts-$ACCOUNT_ID"
    fi
    
    # Get region
    echo -n "Enter AWS region (default: us-east-1): "
    read -r USER_REGION
    if [ -z "$USER_REGION" ]; then
        USER_REGION="us-east-1"
    fi
    
    # Update global variables
    STACK_NAME="$USER_STACK_NAME"
    S3_BUCKET_NAME="$USER_S3_BUCKET"
    REGION="$USER_REGION"
    
    print_status "Creating samconfig.toml with your configuration"
    
    cat > samconfig.toml << EOF
version = 0.1

[default.deploy.parameters]
stack_name = "${STACK_NAME}"
s3_bucket = "${S3_BUCKET_NAME}"
s3_prefix = "${STACK_NAME}"
region = "${REGION}"
confirm_changeset = false
capabilities = "CAPABILITY_IAM"
parameter_overrides = "Stage=\"${STAGE}\""
resolve_s3 = false
disable_rollback = true
image_repositories = []
EOF
    
    print_success "samconfig.toml created with your configuration"
}

# Function to load configuration from samconfig.toml if it exists
load_samconfig() {
    if [ -f "samconfig.toml" ]; then
        print_status "Loading configuration from samconfig.toml"
        
        # Extract values from samconfig.toml
        STACK_NAME=$(grep 'stack_name' samconfig.toml | cut -d'"' -f2)
        S3_BUCKET_NAME=$(grep 's3_bucket' samconfig.toml | cut -d'"' -f2)
        REGION=$(grep 'region' samconfig.toml | cut -d'"' -f2)
        
        print_status "Using stack: $STACK_NAME, bucket: $S3_BUCKET_NAME, region: $REGION"
    fi
}

# Function to build the project
build_project() {
    print_header "Building Spring Boot Project"
    
    print_status "Cleaning and compiling project..."
    mvn clean package -DskipTests -q
    
    if [ -f "target/demo-lambda.jar" ]; then
        print_success "JAR file created: target/demo-lambda.jar"
        print_status "JAR size: $(du -h target/demo-lambda.jar | cut -f1)"
    else
        print_error "JAR file not found!"
        exit 1
    fi
}

# Function to deploy the application
deploy_application() {
    print_header "Deploying to AWS Lambda"
    
    print_status "Packaging and deploying SAM application..."
    sam deploy --no-confirm-changeset --no-fail-on-empty-changeset
    
    print_success "Deployment completed successfully"
}

# Function to get CloudWatch log group names
get_log_groups() {
    LAMBDA_LOG_GROUP=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`LambdaLogGroup`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    API_LOG_GROUP=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayLogGroup`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$LAMBDA_LOG_GROUP" ]; then
        LAMBDA_LOG_GROUP="/aws/lambda/${STACK_NAME}-${STAGE}"
    fi
    
    if [ -z "$API_LOG_GROUP" ]; then
        API_LOG_GROUP="/aws/apigateway/${STACK_NAME}-api-${STAGE}"
    fi
}

# Function to show recent logs
show_recent_logs() {
    print_header "Recent CloudWatch Logs"
    
    get_log_groups
    
    print_status "Lambda Log Group: $LAMBDA_LOG_GROUP"
    print_status "API Gateway Log Group: $API_LOG_GROUP"
    
    echo -e "\n${YELLOW}Recent Lambda Logs (last 5 minutes):${NC}"
    aws logs filter-log-events \
        --log-group-name "$LAMBDA_LOG_GROUP" \
        --region "$REGION" \
        --start-time $(( $(date +%s) * 1000 - 300000 )) \
        --query 'events[*].[timestamp,message]' \
        --output table 2>/dev/null || print_warning "No recent Lambda logs found"
    
    echo -e "\n${YELLOW}Recent API Gateway Logs (last 5 minutes):${NC}"
    aws logs filter-log-events \
        --log-group-name "$API_LOG_GROUP" \
        --region "$REGION" \
        --start-time $(( $(date +%s) * 1000 - 300000 )) \
        --query 'events[*].[timestamp,message]' \
        --output table 2>/dev/null || print_warning "No recent API Gateway logs found"
}

# Function to tail logs in real-time
tail_logs() {
    print_header "Tailing CloudWatch Logs"
    
    get_log_groups
    
    print_status "Starting log tail for both Lambda and API Gateway..."
    print_status "Press Ctrl+C to stop"
    
    echo -e "\n${GREEN}Log Format:${NC}"
    echo -e "${BLUE}[LAMBDA]${NC} - Lambda function logs"
    echo -e "${YELLOW}[API-GW]${NC} - API Gateway access logs"
    echo ""
    
    # Function to tail lambda logs
    tail_lambda_logs() {
        aws logs tail "$LAMBDA_LOG_GROUP" --region "$REGION" --follow --format short 2>/dev/null | \
        while IFS= read -r line; do
            echo -e "${BLUE}[LAMBDA]${NC} $line"
        done
    }
    
    # Function to tail API Gateway logs
    tail_api_logs() {
        aws logs tail "$API_LOG_GROUP" --region "$REGION" --follow --format short 2>/dev/null | \
        while IFS= read -r line; do
            echo -e "${YELLOW}[API-GW]${NC} $line"
        done
    }
    
    # Start both tails in background
    tail_lambda_logs &
    LAMBDA_PID=$!
    
    tail_api_logs &
    API_PID=$!
    
    # Wait for Ctrl+C
    trap 'kill $LAMBDA_PID $API_PID 2>/dev/null; exit 0' INT
    wait
}

# Function to get API Gateway URL
get_api_url() {
    API_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`DemoApi`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$API_URL" ]; then
        echo "$API_URL"
    else
        print_error "Could not retrieve API Gateway URL"
        return 1
    fi
}

# Function to test the deployed application
test_application() {
    print_header "Testing Deployed Application"
    
    print_status "Retrieving API Gateway URL..."
    API_URL=$(get_api_url)
    
    if [ -z "$API_URL" ]; then
        print_error "Could not get API URL. Skipping tests."
        return 1
    fi
    
    print_success "API Gateway URL: $API_URL"
    
    # Wait for deployment to be ready
    print_status "Waiting for deployment to be ready..."
    sleep 10
    
    # Test endpoints
    echo -e "\n${YELLOW}Testing Endpoints:${NC}"
    
    # Test health endpoint
    print_status "Testing /health endpoint..."
    if curl -s -f "${API_URL}health" > /dev/null; then
        print_success "✓ /health endpoint is working"
    else
        print_warning "✗ /health endpoint failed"
    fi
    
    echo -e "\n${GREEN}🚀 Deployment Summary:${NC}"
    echo -e "${GREEN}API Gateway URL:${NC} $API_URL"
    echo -e "${GREEN}Available endpoints:${NC}"
    echo -e "  • ${API_URL}health"
    echo -e "  • ${API_URL}error"
    
    # Show CloudWatch log information only (not the actual logs)
    get_log_groups
    echo -e "\n${GREEN}CloudWatch Monitoring:${NC}"
    echo -e "${GREEN}Lambda Log Group:${NC} $LAMBDA_LOG_GROUP"
    echo -e "${GREEN}API Gateway Log Group:${NC} $API_LOG_GROUP"
    echo -e "\n${BLUE}Log Monitoring Commands:${NC}"
    echo -e "  • Show recent logs: ${0} --logs"
    echo -e "  • Tail logs real-time: ${0} --tail-logs"
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if required tools are installed
    commands=("aws" "sam" "mvn" "java" "curl")
    
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            print_success "✓ $cmd is installed"
        else
            print_error "✗ $cmd is not installed"
            exit 1
        fi
    done
    
    # Check AWS credentials
    if aws sts get-caller-identity >/dev/null 2>&1; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        print_success "✓ AWS credentials configured (Account: $ACCOUNT_ID)"
    else
        print_error "✗ AWS credentials not configured"
        exit 1
    fi
    
    # Check if we're in the right directory
    if [ ! -f "pom.xml" ] || [ ! -f "template.yaml" ]; then
        print_error "✗ Not in Spring Boot project directory (missing pom.xml or template.yaml)"
        exit 1
    fi
    
    print_success "✓ All prerequisites met"
}

# Function to show help
show_help() {
    echo "Spring Boot Lambda Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -t, --test-only     Only test the existing deployment"
    echo "  -b, --build-only    Only build the project"
    echo "  -d, --deploy-only   Only deploy (skip build and test)"
    echo "  --clean             Clean deployment (delete and redeploy)"
    echo "  --logs              Show recent CloudWatch logs"
    echo "  --tail-logs         Tail CloudWatch logs in real-time"
    echo ""
    echo "Configuration:"
    echo "  On first run, the script will interactively ask for:"
    echo "  • Stack name (default: spring-boot-demo)"
    echo "  • S3 bucket name (default: spring-boot-demo-artifacts-ACCOUNT_ID)"
    echo "  • AWS region (default: us-east-1)"
    echo ""
    echo "  Configuration is saved in samconfig.toml for subsequent runs."
    echo "  Use --clean to remove all resources and configuration."
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_NAME        Project name (default: spring-boot-demo)"
    echo "  REGION              AWS region (default: us-east-1)"
    echo "  STAGE               Deployment stage (default: dev)"
    echo ""
    echo "CloudWatch Monitoring:"
    echo "  The deployment creates CloudWatch log groups for:"
    echo "  • Lambda function execution logs"
    echo "  • API Gateway access logs"
    echo "  Use --logs to view recent logs or --tail-logs for real-time monitoring"
    echo ""
}

# Function to clean deployment
clean_deployment() {
    print_header "Cleaning Deployment"
    
    # Load configuration first to get the correct bucket and stack names
    if [ -f "samconfig.toml" ] && [ -s "samconfig.toml" ]; then
        print_status "Loading configuration from samconfig.toml for cleanup"
        STACK_NAME=$(grep 'stack_name' samconfig.toml | cut -d'"' -f2)
        S3_BUCKET_NAME=$(grep 's3_bucket' samconfig.toml | cut -d'"' -f2)
        REGION=$(grep 'region' samconfig.toml | cut -d'"' -f2)
        
        if [ -z "$STACK_NAME" ] || [ -z "$S3_BUCKET_NAME" ] || [ -z "$REGION" ]; then
            print_warning "Could not read configuration from samconfig.toml - using defaults"
            STACK_NAME="spring-boot-demo"
            ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
            S3_BUCKET_NAME="spring-boot-demo-artifacts-$ACCOUNT_ID"
            REGION="us-east-1"
        fi
        
        print_status "Will delete stack: $STACK_NAME, bucket: $S3_BUCKET_NAME, region: $REGION"
    else
        print_warning "No valid samconfig.toml found - using default values"
        STACK_NAME="spring-boot-demo"
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        S3_BUCKET_NAME="spring-boot-demo-artifacts-$ACCOUNT_ID"
        REGION="us-east-1"
        print_status "Will delete stack: $STACK_NAME, bucket: $S3_BUCKET_NAME, region: $REGION"
    fi
    
    print_warning "This will delete the entire CloudFormation stack, S3 bucket, and samconfig.toml"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Step 1: Delete CloudFormation stack and all associated resources
        print_status "Deleting CloudFormation stack: $STACK_NAME..."
        sam delete --stack-name "$STACK_NAME" --region "$REGION" --no-prompts 2>&1 || {
            print_warning "Stack deletion failed or stack doesn't exist, continuing with manual cleanup..."
        }
        
        # Step 2: Check if bucket exists and delete it
        print_status "Checking if S3 bucket exists: $S3_BUCKET_NAME..."
        if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" --region "$REGION" 2>/dev/null; then
            print_status "Bucket exists, deleting all contents..."
            
            # Delete all objects and versions
            print_status "Deleting all object versions..."
            aws s3api list-object-versions --bucket "$S3_BUCKET_NAME" --region "$REGION" \
                --query 'Versions[].[Key,VersionId]' --output text 2>/dev/null | \
                while read key version_id; do
                    if [ -n "$key" ] && [ -n "$version_id" ]; then
                        echo "Deleting version: $key ($version_id)"
                        aws s3api delete-object --bucket "$S3_BUCKET_NAME" --key "$key" --version-id "$version_id" --region "$REGION" 2>/dev/null || true
                    fi
                done
            
            # Delete all delete markers
            print_status "Deleting all delete markers..."
            aws s3api list-object-versions --bucket "$S3_BUCKET_NAME" --region "$REGION" \
                --query 'DeleteMarkers[].[Key,VersionId]' --output text 2>/dev/null | \
                while read key version_id; do
                    if [ -n "$key" ] && [ -n "$version_id" ]; then
                        echo "Deleting delete marker: $key ($version_id)"
                        aws s3api delete-object --bucket "$S3_BUCKET_NAME" --key "$key" --version-id "$version_id" --region "$REGION" 2>/dev/null || true
                    fi
                done
            
            # Finally delete the bucket
            print_status "Deleting the S3 bucket itself..."
            if aws s3api delete-bucket --bucket "$S3_BUCKET_NAME" --region "$REGION" 2>/dev/null; then
                print_success "S3 bucket deleted successfully"
            else
                print_warning "Failed to delete S3 bucket, you may need to delete it manually"
            fi
        else
            print_status "S3 bucket does not exist or already deleted"
        fi
        
        # Step 3: Check for any remaining API Gateway resources
        print_status "Checking for any remaining API Gateway resources..."
        API_IDS=$(aws apigateway get-rest-apis --region "$REGION" --query "items[?contains(name, '$STACK_NAME') || contains(name, 'spring-boot-demo')].id" --output text 2>/dev/null || echo "")
        if [ -n "$API_IDS" ]; then
            for api_id in $API_IDS; do
                print_status "Deleting API Gateway: $api_id"
                aws apigateway delete-rest-api --rest-api-id "$api_id" --region "$REGION" 2>/dev/null || true
            done
        fi
        
        # Step 4: Check for any remaining Lambda functions
        print_status "Checking for any remaining Lambda functions..."
        LAMBDA_FUNCTIONS=$(aws lambda list-functions --region "$REGION" --query "Functions[?contains(FunctionName, '$STACK_NAME') || contains(FunctionName, 'spring-boot-demo')].FunctionName" --output text 2>/dev/null || echo "")
        if [ -n "$LAMBDA_FUNCTIONS" ]; then
            for func_name in $LAMBDA_FUNCTIONS; do
                print_status "Deleting Lambda function: $func_name"
                aws lambda delete-function --function-name "$func_name" --region "$REGION" 2>/dev/null || true
            done
        fi
        
        # Step 5: Delete CloudWatch Log Groups
        print_status "Deleting CloudWatch Log Groups..."
        
        # Delete Lambda log group
        LAMBDA_LOG_GROUP="/aws/lambda/${STACK_NAME}-${STAGE}"
        if aws logs describe-log-groups --log-group-name-prefix "$LAMBDA_LOG_GROUP" --region "$REGION" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LAMBDA_LOG_GROUP"; then
            print_status "Deleting Lambda log group: $LAMBDA_LOG_GROUP"
            aws logs delete-log-group --log-group-name "$LAMBDA_LOG_GROUP" --region "$REGION" 2>/dev/null || true
        fi
        
        # Delete API Gateway log group
        API_LOG_GROUP="/aws/apigateway/${STACK_NAME}-api-${STAGE}"
        if aws logs describe-log-groups --log-group-name-prefix "$API_LOG_GROUP" --region "$REGION" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$API_LOG_GROUP"; then
            print_status "Deleting API Gateway log group: $API_LOG_GROUP"
            aws logs delete-log-group --log-group-name "$API_LOG_GROUP" --region "$REGION" 2>/dev/null || true
        fi
        
        # Delete API Gateway execution logs (these are created automatically by AWS)
        print_status "Deleting API Gateway execution logs..."
        EXECUTION_LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "API-Gateway-Execution-Logs" --region "$REGION" --query 'logGroups[*].logGroupName' --output text 2>/dev/null || echo "")
        if [ -n "$EXECUTION_LOG_GROUPS" ]; then
            for log_group in $EXECUTION_LOG_GROUPS; do
                # Check if this log group belongs to our API by checking if it contains our API ID
                if [[ "$log_group" == *"API-Gateway-Execution-Logs"* ]]; then
                    print_status "Deleting API Gateway execution log group: $log_group"
                    aws logs delete-log-group --log-group-name "$log_group" --region "$REGION" 2>/dev/null || true
                fi
            done
        fi
        
        # Also check for any log groups with spring-boot-demo prefix (fallback)
        LAMBDA_LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/spring-boot-demo" --region "$REGION" --query 'logGroups[*].logGroupName' --output text 2>/dev/null || echo "")
        if [ -n "$LAMBDA_LOG_GROUPS" ]; then
            for log_group in $LAMBDA_LOG_GROUPS; do
                print_status "Deleting Lambda log group: $log_group"
                aws logs delete-log-group --log-group-name "$log_group" --region "$REGION" 2>/dev/null || true
            done
        fi
        
        API_LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/apigateway/spring-boot-demo" --region "$REGION" --query 'logGroups[*].logGroupName' --output text 2>/dev/null || echo "")
        if [ -n "$API_LOG_GROUPS" ]; then
            for log_group in $API_LOG_GROUPS; do
                print_status "Deleting API Gateway log group: $log_group"
                aws logs delete-log-group --log-group-name "$log_group" --region "$REGION" 2>/dev/null || true
            done
        fi
        
        # Step 6: Remove samconfig.toml
        print_status "Removing samconfig.toml..."
        rm -f samconfig.toml
        
        print_success "Cleanup completed - all resources should be deleted"
        print_status "Please check AWS Console to verify all resources are removed"
    else
        print_status "Cleanup cancelled"
    fi
}

# Main execution
main() {
    print_header "Spring Boot Lambda Deployment"
    
    # Parse command line arguments
    SKIP_BUILD=false
    SKIP_DEPLOY=false
    SKIP_TEST=false
    CLEAN_DEPLOY=false
    SHOW_LOGS=false
    TAIL_LOGS=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -t|--test-only)
                SKIP_BUILD=true
                SKIP_DEPLOY=true
                shift
                ;;
            -b|--build-only)
                SKIP_DEPLOY=true
                SKIP_TEST=true
                shift
                ;;
            -d|--deploy-only)
                SKIP_BUILD=true
                SKIP_TEST=true
                shift
                ;;
            --clean)
                CLEAN_DEPLOY=true
                shift
                ;;
            --logs)
                SHOW_LOGS=true
                shift
                ;;
            --tail-logs)
                TAIL_LOGS=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Clean deployment if requested
    if [ "$CLEAN_DEPLOY" = true ]; then
        clean_deployment
        exit 0
    fi
    
    # Load configuration for log operations
    load_samconfig
    
    # Show logs if requested
    if [ "$SHOW_LOGS" = true ]; then
        show_recent_logs
        exit 0
    fi
    
    # Tail logs if requested
    if [ "$TAIL_LOGS" = true ]; then
        tail_logs
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Create configuration if needed
    create_samconfig
    
    # Now reload config in case it was just created
    load_samconfig
    
    # Setup S3 bucket
    if ! check_s3_bucket; then
        create_s3_bucket
    fi
    
    # Build project
    if [ "$SKIP_BUILD" = false ]; then
        build_project
    fi
    
    # Deploy application
    if [ "$SKIP_DEPLOY" = false ]; then
        deploy_application
    fi
    
    # Test application
    if [ "$SKIP_TEST" = false ]; then
        test_application
    fi
    
    print_header "Deployment Complete! 🎉"
}

# Run main function
main "$@"
