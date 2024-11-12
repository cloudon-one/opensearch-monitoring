import boto3
import json
import os
import datetime
from opensearch_py import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

def get_assumed_role_credentials(account_id, role_name):
    """
    Assume role in target account and return credentials
    """
    sts = boto3.client('sts')
    role_arn = f'arn:aws:iam::{account_id}:role/{role_name}'
    
    assumed_role = sts.assume_role(
        RoleArn=role_arn,
        RoleSessionName='LambdaMonitoringSession'
    )
    
    return assumed_role['Credentials']

def get_lambda_metrics(credentials, region):
    """
    Get Lambda metrics using CloudWatch
    """
    cloudwatch = boto3.client(
        'cloudwatch',
        aws_access_key_id=credentials['AccessKeyId'],
        aws_secret_access_key=credentials['SecretAccessKey'],
        aws_session_token=credentials['SessionToken'],
        region_name=region
    )
    
    lambda_client = boto3.client(
        'lambda',
        aws_access_key_id=credentials['AccessKeyId'],
        aws_secret_access_key=credentials['SecretAccessKey'],
        aws_session_token=credentials['SessionToken'],
        region_name=region
    )
    
    functions = lambda_client.list_functions()['Functions']
    metrics = []
    
    for function in functions:
        function_name = function['FunctionName']
        
        # Get basic metrics
        response = cloudwatch.get_metric_data(
            MetricDataQueries=[
                {
                    'Id': 'invocations',
                    'MetricStat': {
                        'Metric': {
                            'Namespace': 'AWS/Lambda',
                            'MetricName': 'Invocations',
                            'Dimensions': [{'Name': 'FunctionName', 'Value': function_name}]
                        },
                        'Period': 300,
                        'Stat': 'Sum'
                    }
                },
                {
                    'Id': 'errors',
                    'MetricStat': {
                        'Metric': {
                            'Namespace': 'AWS/Lambda',
                            'MetricName': 'Errors',
                            'Dimensions': [{'Name': 'FunctionName', 'Value': function_name}]
                        },
                        'Period': 300,
                        'Stat': 'Sum'
                    }
                },
                {
                    'Id': 'duration',
                    'MetricStat': {
                        'Metric': {
                            'Namespace': 'AWS/Lambda',
                            'MetricName': 'Duration',
                            'Dimensions': [{'Name': 'FunctionName', 'Value': function_name}]
                        },
                        'Period': 300,
                        'Stat': 'Average'
                    }
                }
            ],
            StartTime=datetime.datetime.utcnow() - datetime.timedelta(minutes=5),
            EndTime=datetime.datetime.utcnow()
        )
        
        metrics.append({
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'account_id': account_id,
            'region': region,
            'function_name': function_name,
            'runtime': function.get('Runtime'),
            'memory': function.get('MemorySize'),
            'timeout': function.get('Timeout'),
            'last_modified': function.get('LastModified'),
            'invocations': response['MetricDataResults'][0]['Values'][0] if response['MetricDataResults'][0]['Values'] else 0,
            'errors': response['MetricDataResults'][1]['Values'][0] if response['MetricDataResults'][1]['Values'] else 0,
            'duration_ms': response['MetricDataResults'][2]['Values'][0] if response['MetricDataResults'][2]['Values'] else 0
        })
    
    return metrics

def lambda_handler(event, context):
    # Get environment variables
    monitored_accounts = json.loads(os.environ['MONITORED_ACCOUNTS'])
    monitoring_role_name = os.environ['MONITORING_ROLE_NAME']
    opensearch_host = os.environ['OPENSEARCH_HOST']
    aws_region = os.environ['AWS_REGION']
    
    # Configure OpenSearch client
    credentials = boto3.Session().get_credentials()
    awsauth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        aws_region,
        'es',
        session_token=credentials.token
    )
    
    opensearch = OpenSearch(
        hosts=[{'host': opensearch_host, 'port': 443}],
        http_auth=awsauth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection
    )
    
    # Collect metrics from all accounts
    for account_id in monitored_accounts:
        try:
            credentials = get_assumed_role_credentials(account_id, monitoring_role_name)
            metrics = get_lambda_metrics(credentials, aws_region)
            
            # Index metrics in OpenSearch
            for metric in metrics:
                index_name = f'lambda-metrics-{datetime.datetime.utcnow().strftime("%Y-%m")}'
                opensearch.index(
                    index=index_name,
                    body=metric,
                    id=f"{metric['account_id']}-{metric['function_name']}-{metric['timestamp']}"
                )
                
        except Exception as e:
            print(f"Error processing account {account_id}: {str(e)}")
            continue
    
    return {
        'statusCode': 200,
        'body': json.dumps('Metrics collection completed')
    }