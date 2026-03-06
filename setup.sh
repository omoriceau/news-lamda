#!/usr/bin/bash

# AWS Lambda News Fetcher - Automated Setup Script
# This script helps you set up AWS credentials and verify your environment

set -e

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_section() {
    echo ""
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

# Step 2B: Load AWS Credentials from ./.aws/credentials (if exists)
print_section "Step 1: Loading Credentials from ./.aws/credentials"

CREDENTIALS_FILE="./.aws/credentials"

if [ -f "$CREDENTIALS_FILE" ]; then
    print_status "Found $CREDENTIALS_FILE"

    # Extract values from [default] profile
    aws_access_key=$(awk -F'=' '/^\[default\]/ {flag=1; next} /^\[/ {flag=0} flag && /aws_access_key_id/ {gsub(/ /,"",$2); print $2}' "$CREDENTIALS_FILE")
    aws_secret_key=$(awk -F'=' '/^\[default\]/ {flag=1; next} /^\[/ {flag=0} flag && /aws_secret_access_key/ {gsub(/ /,"",$2); print $2}' "$CREDENTIALS_FILE")
    aws_session_token=$(awk -F'=' '/^\[default\]/ {flag=1; next} /^\[/ {flag=0} flag && /aws_session_token/ {gsub(/ /,"",$2); print $2}' "$CREDENTIALS_FILE")
    news_api_key=$(awk -F'=' '/^\[default\]/ {flag=1; next} /^\[/ {flag=0} flag && /news_api_key/ {gsub(/ /,"",$2); print $2}' "$CREDENTIALS_FILE")

    if [ -n "$aws_access_key" ] && [ -n "$aws_secret_key" ]; then
        print_status "Credentials loaded from file"

        # Export into environment
        export AWS_ACCESS_KEY_ID="$aws_access_key"
        export AWS_SECRET_ACCESS_KEY="$aws_secret_key"
        export AWS_SESSION_TOKEN="$aws_session_token"

        # Default region fallback
        aws_region=${AWS_DEFAULT_REGION:-us-east-1}
        export AWS_DEFAULT_REGION="$aws_region"
        export AWS_REGION="$aws_region"

        # Generate creds.sh
        cat > creds.sh << EOF
export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
export AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
export NEWS_API_KEY=$news_api_key
export S3_BUCKET_NAME=\${S3_BUCKET_NAME:-}
export NEWS_TOPICS=technology,science,business,sports,health
EOF

        chmod +x creds.sh
        source creds.sh
        print_status "creds.sh generated from .aws/credentials"

    else
        print_warning "AWS credentials found but values are empty"
    fi
else
    print_warning "No ./.aws/credentials file found"
fi

echo "=========================================="
echo "AWS Lambda News Fetcher - Setup Script"
echo "=========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color



# Step 1: Check prerequisites
print_section "Step 1: Checking Prerequisites"

# Check AWS CLI
if command -v aws &> /dev/null; then
    print_status "AWS CLI is installed"
    aws --version
else
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check SAM CLI
if command -v sam &> /dev/null; then
    print_status "SAM CLI is installed"
    sam --version
else
    print_error "SAM CLI is not installed. Please install it first."
    exit 1
fi

# Check Python
if command -v python3 &> /dev/null; then
    print_status "Python 3 is installed"
    python3 --version
else
    print_error "Python 3 is not installed. Please install it first."
    exit 1
fi

# Step 3: Verify AWS Credentials
print_section "Step 3: Verifying AWS Credentials"

if aws sts get-caller-identity &> /dev/null; then
    print_status "AWS credentials are valid"
    aws sts get-caller-identity
else
    print_error "AWS credentials are invalid or not set"
    echo "Please set your credentials and try again:"
    echo "  export AWS_ACCESS_KEY_ID='...'"
    echo "  export AWS_SECRET_ACCESS_KEY='...'"
    echo "  export AWS_SESSION_TOKEN='...'"
    exit 1
fi

# Step 4: Check S3 Access
print_section "Step 4: Checking S3 Access"

if aws s3 ls &> /dev/null; then
    print_status "S3 access verified"
    echo "Existing S3 buckets:"
    aws s3 ls | head -5
else
    print_error "Cannot access S3. Check your credentials and IAM permissions."
    exit 1
fi

# Step 6: Environment Variables
print_section "Step 6: Setting Environment Variables"
if [ -f "./creds.sh" ]; then
    print_section "Step 6: Loading Environment Variables"
    source ./creds.sh
    print_status "Environment variables loaded from creds.sh"
else
    print_warning "creds.sh not found"
fi

print_status "NEWS_COUNT set to: $NEWS_COUNT"
print_status "NEWS_TOPICS set to: $NEWS_TOPICS"

# Step 7: Python Dependencies
# Step 7: Installing Python Dependencies
print_section "Step 7: Installing Python Dependencies"

VENV_DIR=".venv"

if [ ! -d "$VENV_DIR" ]; then
    print_status "Creating Python virtual environment"
    python3 -m venv "$VENV_DIR"
fi

# Activate venv
source "$VENV_DIR/bin/activate"

print_status "Installing dependencies into virtual environment"

if pip install -r requirements.txt; then
    print_status "Python dependencies installed"
else
    print_error "Failed to install Python dependencies"
    exit 1
fi

# Step 8: Create S3 Bucket (Optional)
print_section "Step 8: S3 Bucket Setup"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="news-api-${ACCOUNT_ID}-${aws_region}"

echo "Bucket name will be: $BUCKET_NAME"
echo ""
echo "Do you want to create the S3 bucket now? (y/n)"
echo "(Note: SAM will create it during deployment if you skip this)"
read -r create_bucket

if [ "$create_bucket" = "y" ] || [ "$create_bucket" = "Y" ]; then
    if aws s3 mb "s3://${BUCKET_NAME}" --region "$aws_region" 2>/dev/null; then
        print_status "S3 bucket created: $BUCKET_NAME"
    else
        print_warning "Bucket may already exist or creation failed"
    fi
else
    print_status "Skipping bucket creation (will be created by SAM)"
fi

# Step 9: Update env-dev.json
print_section "Step 9: Updating Configuration Files"

cat > env.json << EOF
{
  "NewsLambda": {
    "AWS_ACCESS_KEY_ID": "$aws_access_key",
    "AWS_SECRET_ACCESS_KEY": "$aws_secret_key",
    "AWS_SESSION_TOKEN": "$aws_session_token",
    "AWS_REGION": "$aws_region",
    "NEWS_API_KEY": "$news_api_key",
    "NEWS_COUNT": "10",
    "NEWS_TOPICS": "technology,science,business,sports,health",
    "S3_BUCKET_NAME": "$BUCKET_NAME"
  }
}
EOF

print_status "env-dev.json updated"
print_warning "Remember: env-dev.json is in .gitignore and should NOT be committed"

# Step 10: Final Verification
print_section "Step 10: Final Verification"

echo "Checking all components..."
echo ""

# Check AWS credentials
if aws sts get-caller-identity &> /dev/null; then
    print_status "AWS credentials: OK"
else
    print_error "AWS credentials: FAILED"
fi

# Check S3 access
if aws s3 ls &> /dev/null; then
    print_status "S3 access: OK"
else
    print_error "S3 access: FAILED"
fi

# Check Python packages
if python3 -c "import requests, boto3" 2>/dev/null; then
    print_status "Python packages: OK"
else
    print_error "Python packages: FAILED"
fi

# Check SAM
if sam --version &> /dev/null; then
    print_status "SAM CLI: OK"
else
    print_error "SAM CLI: FAILED"
fi

# Summary
print_section "Setup Complete!"

echo ""
echo "Next steps:"
echo "1. Review and update env-dev.json if needed"
echo "2. Run: sam build"
echo "3. Run: sam deploy --guided"
echo "4. Test: aws lambda invoke --function-name NewsLambda response.json"
echo ""
echo "For more details, see SETUP_GUIDE.md"
echo ""
