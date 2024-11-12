# Lambda Fleet Monitoring Solution

A comprehensive solution for monitoring Lambda functions across multiple AWS accounts using OpenSearch for visualization and analysis.

## Overview

This solution provides real-time monitoring and analytics for AWS Lambda functions across multiple accounts. It collects metrics such as invocations, errors, duration, memory usage, and cold starts, storing them in OpenSearch for analysis and visualization.

## Architecture

```mermaid
subgraph MonitoringAccount[Monitoring Account]
    direction TB
    lambda[Monitoring Lambda]
    opensearch[OpenSearch Cluster]
    dashboard[OpenSearch Dashboards]
    setup[Setup Lambda]
end

subgraph Account1[Account 1]
    direction TB
    role1[Monitoring Role]
    functions1[Lambda Functions]
    metrics1[CloudWatch Metrics]
end

subgraph Account2[Account 2]
    direction TB
    role2[Monitoring Role]
    functions2[Lambda Functions]
    metrics2[CloudWatch Metrics]
end

subgraph AccountN[Account N]
    direction TB
    roleN[Monitoring Role]
    functionsN[Lambda Functions]
    metricsN[CloudWatch Metrics]
end

event --> lambda
lambda --> role1
lambda --> role2
lambda --> roleN

role1 --> metrics1
role2 --> metrics2
roleN --> metricsN

metrics1 --> functions1
metrics2 --> functions2
metricsN --> functionsN

lambda --> opensearch
setup --> opensearch
opensearch --> dashboard

classDef awsService fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:white;
classDef account fill:#f9f,stroke:#333,stroke-width:2px;
classDef resource fill:#ddd,stroke:#333,stroke-width:1px;

class EventBridge,opensearch,dashboard awsService;
class MonitoringAccount,Account1,Account2,AccountN account;
class lambda,role1,role2,roleN,functions1,functions2,functionsN,metrics1,metrics2,metricsN resource;
```

## Features

- Cross-account Lambda function monitoring
- Real-time metric collection
- Comprehensive dashboards
- Automated setup and configuration
- Customizable alerting capabilities
- Memory and timeout optimization insights

### Metrics Collected

- Invocation count
- Error rates
- Duration statistics
- Memory utilization
- Cold start frequency
- Timeout proximity
- Runtime distribution
- Cost metrics

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform v1.0.0 or later
- Python 3.9 or later
- Cross-account IAM roles configured
- AWS account with permissions to create:
  - Lambda functions
  - OpenSearch domains
  - IAM roles and policies
  - CloudWatch events
  - S3 buckets

## Installation

1. Clone the repository:
```bash
git clone https://github.com/cloudon-one/opensearch-monitoring.git
cd opensearch-monitoring/lambda
```

2. Create a `terraform.tfvars` file:
```hcl
aws_region = "eu-west-1"
monitored_accounts = ["123456789012", "098765432109"]
opensearch_master_user_password = "your-secure-password"
opensearch_instance_type = "t3.small.search"
opensearch_instance_count = 1
opensearch_volume_size = 10
```

3. Initialize Terraform:
```bash
terraform init
```

4. Deploy the solution:
```bash
terraform plan
terraform apply
```

## Configuration

### Cross-Account Setup

# Lambda Fleet Monitoring Solution

[Previous sections remain the same until "Cross-Account Setup"]

## Cross-Account Setup

### Step 1: Generate Trust Policy

First, install the requirements and run the trust policy generator script:

```bash
# Install required packages
pip install boto3

# Generate the trust policy
python generate_trust_policy.py --account-id YOUR_MONITORING_ACCOUNT_ID
```

This script will:
- Automatically fetch your AWS Organization ID
- Generate the trust policy with proper account IDs
- Save it to `monitoring-role-trust-policy.json`
- Provide next steps for deployment

### Step 2: Create IAM Roles in Monitored Accounts

For each account you want to monitor, create the required IAM role:

```bash
# Create the monitoring role
aws iam create-role \
  --role-name LambdaMonitoringRole \
  --assume-role-policy-document file://monitoring-role-trust-policy.json

# Attach AWS managed policy for basic Lambda execution
aws iam attach-role-policy \
  --role-name LambdaMonitoringRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Create and attach custom monitoring policy
aws iam put-role-policy \
  --role-name LambdaMonitoringRole \
  --policy-name LambdaMonitoringCustomPolicy \
  --policy-document file://monitoring-role-policy.json
```

### Step 3: Verify Role Configuration

Verify the role setup in each account:

```bash
# List role policies
aws iam list-role-policies \
  --role-name LambdaMonitoringRole

# List attached policies
aws iam list-attached-role-policies \
  --role-name LambdaMonitoringRole

# Get the trust policy
aws iam get-role \
  --role-name LambdaMonitoringRole
```

### Policy Details

#### Trust Policy
The trust policy (`monitoring-role-trust-policy.json`) enables:
- Cross-account access from the monitoring account
- Organization ID verification for security
- Access for both monitoring and setup roles

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::MONITORING_ACCOUNT_ID:role/lambda-monitoring-role"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "aws:PrincipalOrgID": "ORGANIZATION_ID"
                }
            }
        },
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::MONITORING_ACCOUNT_ID:role/opensearch-setup-role"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "aws:PrincipalOrgID": "ORGANIZATION_ID"
                }
            }
        }
    ]
}
```

#### Permissions Policy
The monitoring role permissions (`monitoring-role-policy.json`) allow:
- CloudWatch metrics access
- Lambda configuration retrieval
- Log creation and management

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:GetMetricData",
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:ListMetrics"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "lambda:ListFunctions",
                "lambda:GetFunction",
                "lambda:GetFunctionConfiguration"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
```

### Troubleshooting Role Setup

Common issues and solutions:

1. Trust Policy Issues
   ```bash
   # Verify organization ID
   aws organizations describe-organization
   
   # Update trust policy if needed
   aws iam update-assume-role-policy \
     --role-name LambdaMonitoringRole \
     --policy-document file://monitoring-role-trust-policy.json
   ```

2. Permission Issues
   ```bash
   # Check CloudWatch permissions
   aws cloudwatch list-metrics \
     --region us-west-2
   
   # Test Lambda list access
   aws lambda list-functions \
     --region us-west-2
   ```

3. Cross-Account Access
   ```bash
   # Test role assumption
   aws sts assume-role \
     --role-arn arn:aws:iam::TARGET_ACCOUNT_ID:role/LambdaMonitoringRole \
     --role-session-name TestSession
   ```

### Security Best Practices

1. Regular Rotation
   - Regularly review and rotate any access keys
   - Monitor and audit role usage

2. Access Logging
   - Enable CloudTrail for API activity logging
   - Monitor assumed role events

3. Least Privilege
   - Regularly review and minimize permissions
   - Remove unused permissions

4. Organization Controls
   - Use AWS Organizations SCPs for additional control
   - Implement compliance policies

[Rest of the README remains the same]