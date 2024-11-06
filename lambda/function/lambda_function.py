import json
import boto3
import os
import logging
from datetime import datetime
import time

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')
logs = boto3.client('logs')
s3 = boto3.client('s3')
sts = boto3.client('sts')

class LambdaMonitor:
    def __init__(self):
        self.config = self._load_config()
        self.metrics = {}
        self.alerts = []
        self.target_roles = os.environ.get('TARGET_ACCOUNT_ROLES', '').split(',')
        
    def _load_config(self):
        """Load monitoring configuration"""
        try:
            with open('lambda_monitor.json', 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load config: {str(e)}")
            return {}

    def _assume_role(self, role_arn):
        """Assume IAM role in target account"""
        try:
            response = sts.assume_role(
                RoleArn=role_arn,
                RoleSessionName='LambdaMonitoringSession'
            )
            credentials = response['Credentials']
            return boto3.Session(
                aws_access_key_id=credentials['AccessKeyId'],
                aws_secret_access_key=credentials['SecretAccessKey'],
                aws_session_token=credentials['SessionToken']
            )
        except Exception as e:
            logger.error(f"Error assuming role {role_arn}: {str(e)}")
            return None

    def collect_metrics(self, context):
        """Collect performance metrics across all accounts"""
        # Collect metrics from the current account
        self.metrics['current_account'] = self._collect_account_metrics(context)

        # Collect metrics from target accounts
        for role_arn in self.target_roles:
            if not role_arn:  # Skip empty strings
                continue
                
            try:
                account_id = role_arn.split(':')[4]
                session = self._assume_role(role_arn)
                if session:
                    self.metrics[account_id] = self._collect_account_metrics(context, session)
            except Exception as e:
                logger.error(f"Error collecting metrics from account {account_id}: {str(e)}")

        return self.metrics

    def _collect_account_metrics(self, context, session=None):
        """Collect metrics for a specific account"""
        try:
            # Use provided session or default clients
            if session:
                account_cloudwatch = session.client('cloudwatch')
                account_logs = session.client('logs')
            else:
                account_cloudwatch = cloudwatch
                account_logs = logs

            return {
                'memory_used': self._get_memory_usage(context),
                'execution_duration': self._get_execution_duration(context),
                'error_count': self._get_error_count(account_logs),
                'cost_estimate': self._calculate_cost(context),
                'health_score': self._calculate_health_score()
            }
        except Exception as e:
            logger.error(f"Error collecting account metrics: {str(e)}")
            return {}

    def _get_memory_usage(self, context):
        """Get memory usage metrics"""
        try:
            used_memory = context.memory_limit_in_mb
            return {
                'value': used_memory,
                'timestamp': datetime.now().isoformat()
            }
        except Exception as e:
            logger.error(f"Error getting memory usage: {str(e)}")
            return None

    def _get_execution_duration(self, context):
        """Get function execution duration"""
        try:
            remaining_time = context.get_remaining_time_in_millis()
            total_time = context.memory_limit_in_mb * 1000  # Convert to milliseconds
            duration = total_time - remaining_time
            return {
                'value': duration,
                'timestamp': datetime.now().isoformat()
            }
        except Exception as e:
            logger.error(f"Error getting execution duration: {str(e)}")
            return None

    def _get_error_count(self, logs_client):
        """Get error count from CloudWatch Logs"""
        try:
            response = logs_client.filter_log_events(
                logGroupName=f"/aws/lambda/{os.environ.get('AWS_LAMBDA_FUNCTION_NAME')}",
                filterPattern="ERROR"
            )
            return {
                'value': len(response.get('events', [])),
                'timestamp': datetime.now().isoformat()
            }
        except Exception as e:
            logger.error(f"Error getting error count: {str(e)}")
            return None

    def _calculate_cost(self, context):
        """Calculate estimated cost based on execution metrics"""
        try:
            memory_gb = context.memory_limit_in_mb / 1024
            duration_sec = context.get_remaining_time_in_millis() / 1000
            # AWS Lambda pricing formula (simplified)
            cost = (memory_gb * duration_sec * 0.0000166667)  # $0.0000166667 per GB-second
            return {
                'value': cost,
                'timestamp': datetime.now().isoformat()
            }
        except Exception as e:
            logger.error(f"Error calculating cost: {str(e)}")
            return None

    def _calculate_health_score(self):
        """Calculate health score based on multiple metrics"""
        try:
            # Simplified scoring algorithm
            score = 100
            if self.metrics.get('error_count', {}).get('value', 0) > 0:
                score -= 20
            if self.metrics.get('memory_used', {}).get('value', 0) > 512:
                score -= 10
            return {
                'value': score,
                'timestamp': datetime.now().isoformat()
            }
        except Exception as e:
            logger.error(f"Error calculating health score: {str(e)}")
            return None

    def check_alerts(self):
        """Check metrics against thresholds and generate alerts"""
        try:
            thresholds = self.config.get('alerting', {}).get('thresholds', {})
            
            # Check alerts for each account
            for account_id, account_metrics in self.metrics.items():
                for metric_name, metric_data in account_metrics.items():
                    if metric_name in thresholds:
                        threshold = thresholds[metric_name]
                        if metric_data['value'] > threshold['critical']:
                            self._generate_alert(metric_name, 'CRITICAL', metric_data, account_id)
                        elif metric_data['value'] > threshold['warning']:
                            self._generate_alert(metric_name, 'WARNING', metric_data, account_id)
        except Exception as e:
            logger.error(f"Error checking alerts: {str(e)}")

    def _generate_alert(self, metric_name, severity, metric_data, account_id):
        """Generate and route alerts based on severity"""
        try:
            alert = {
                'account_id': account_id,
                'metric': metric_name,
                'severity': severity,
                'value': metric_data['value'],
                'timestamp': datetime.now().isoformat()
            }
            
            # Apply alert throttling
            if not self._is_throttled(alert):
                self.alerts.append(alert)
                self._route_alert(alert)
        except Exception as e:
            logger.error(f"Error generating alert: {str(e)}")

    def _is_throttled(self, alert):
        """Check if alert should be throttled"""
        try:
            throttle_window = self.config.get('alerting', {}).get('throttle_window', 300)  # 5 minutes default
            for existing_alert in self.alerts:
                if (existing_alert['metric'] == alert['metric'] and 
                    existing_alert['severity'] == alert['severity'] and
                    existing_alert['account_id'] == alert['account_id']):
                    time_diff = (datetime.fromisoformat(alert['timestamp']) - 
                               datetime.fromisoformat(existing_alert['timestamp'])).total_seconds()
                    if time_diff < throttle_window:
                        return True
            return False
        except Exception as e:
            logger.error(f"Error checking throttling: {str(e)}")
            return False

    def _route_alert(self, alert):
        """Route alerts to configured channels"""
        try:
            routing = self.config.get('alerting', {}).get('routing', {})
            channels = routing.get(alert['severity'].lower(), [])
            
            for channel in channels:
                if channel['type'] == 'slack':
                    self._send_slack_alert(alert, channel)
                elif channel['type'] == 'pagerduty':
                    self._send_pagerduty_alert(alert, channel)
                elif channel['type'] == 'sns':
                    self._send_sns_alert(alert, channel)
        except Exception as e:
            logger.error(f"Error routing alert: {str(e)}")

    def _send_slack_alert(self, alert, channel):
        """Send alert to Slack"""
        try:
            # Implement Slack webhook integration
            pass
        except Exception as e:
            logger.error(f"Error sending Slack alert: {str(e)}")

    def _send_pagerduty_alert(self, alert, channel):
        """Send alert to PagerDuty"""
        try:
            # Implement PagerDuty integration
            pass
        except Exception as e:
            logger.error(f"Error sending PagerDuty alert: {str(e)}")

    def _send_sns_alert(self, alert, channel):
        """Send alert through SNS"""
        try:
            sns.publish(
                TopicArn=channel['topic_arn'],
                Message=json.dumps(alert),
                Subject=f"Lambda Monitor Alert: {alert['severity']} - {alert['metric']} - Account {alert['account_id']}"
            )
        except Exception as e:
            logger.error(f"Error sending SNS alert: {str(e)}")

    def manage_storage(self):
        """Manage storage lifecycle and retention"""
        try:
            storage_config = self.config.get('storage', {})
            
            # Implement hot-warm-cold architecture
            if time.time() % (24 * 3600) == 0:  # Run once per day
                self._manage_data_lifecycle(storage_config)
                self._handle_index_rollover(storage_config)
                self._apply_retention_policy(storage_config)
        except Exception as e:
            logger.error(f"Error managing storage: {str(e)}")

    def _manage_data_lifecycle(self, storage_config):
        """Manage data lifecycle transitions"""
        try:
            # Implement lifecycle transitions between hot, warm, and cold storage
            pass
        except Exception as e:
            logger.error(f"Error managing data lifecycle: {str(e)}")

    def _handle_index_rollover(self, storage_config):
        """Handle automatic index rollover"""
        try:
            # Implement index rollover logic
            pass
        except Exception as e:
            logger.error(f"Error handling index rollover: {str(e)}")

    def _apply_retention_policy(self, storage_config):
        """Apply data retention policies"""
        try:
            # Implement retention policy enforcement
            pass
        except Exception as e:
            logger.error(f"Error applying retention policy: {str(e)}")

def lambda_handler(event, context):
    """Main Lambda handler"""
    try:
        monitor = LambdaMonitor()
        
        # Collect metrics across all accounts
        metrics = monitor.collect_metrics(context)
        
        # Check and generate alerts
        monitor.check_alerts()
        
        # Manage storage
        monitor.manage_storage()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'metrics': metrics,
                'alerts': monitor.alerts
            })
        }
    except Exception as e:
        logger.error(f"Lambda execution failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

# Add to your Lambda function

from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth
import boto3

class OpenSearchManager:
    def __init__(self, domain_endpoint, region):
        self.domain_endpoint = domain_endpoint
        self.region = region
        self.client = self._create_client()
        
    def _create_client(self):
        """Create OpenSearch client with AWS authentication"""
        credentials = boto3.Session().get_credentials()
        awsauth = AWS4Auth(
            credentials.access_key,
            credentials.secret_key,
            self.region,
            'es',
            session_token=credentials.token
        )
        
        return OpenSearch(
            hosts=[{'host': self.domain_endpoint, 'port': 443}],
            http_auth=awsauth,
            use_ssl=True,
            verify_certs=True,
            connection_class=RequestsHttpConnection,
            timeout=30
        )
    
    def store_metrics(self, metrics, index_prefix='metrics'):
        """Store metrics in OpenSearch"""
        timestamp = datetime.datetime.utcnow()
        index_name = f"{index_prefix}-{timestamp.strftime('%Y.%m.%d')}"
        
        try:
            # Create index if it doesn't exist
            if not self.client.indices.exists(index_name):
                self.client.indices.create(
                    index_name,
                    body={
                        'mappings': {
                            'properties': {
                                'timestamp': {'type': 'date'},
                                'account_id': {'type': 'keyword'},
                                'region': {'type': 'keyword'},
                                'function_name': {'type': 'keyword'},
                                'metrics': {'type': 'object'},
                                'health_score': {'type': 'float'},
                                'tags': {'type': 'keyword'}
                            }
                        },
                        'settings': {
                            'index': {
                                'number_of_shards': 3,
                                'number_of_replicas': 1
                            }
                        }
                    }
                )
            
            # Store metrics
            for metric in metrics:
                metric['timestamp'] = timestamp.isoformat()
                self.client.index(
                    index=index_name,
                    body=metric,
                    id=f"{metric['account_id']}-{metric['function_name']}-{timestamp.timestamp()}"
                )
                
        except Exception as e:
            logger.error(f"Error storing metrics in OpenSearch: {str(e)}")
            raise

    def query_metrics(self, query, index_pattern='metrics-*'):
        """Query metrics from OpenSearch"""
        try:
            response = self.client.search(
                index=index_pattern,
                body=query
            )
            return response['hits']['hits']
        except Exception as e:
            logger.error(f"Error querying OpenSearch: {str(e)}")
            return []

# Update the Lambda handler to use OpenSearch
    def lambda_handler(event, context):
        try:
            # Initialize components
            metrics_aggregator = MetricsAggregator()
            storage_manager = StorageManager()
            alert_manager = AlertManager()
            health_scorer = HealthScorer()
            
            # Initialize OpenSearch manager
            opensearch_manager = OpenSearchManager(
                os.environ['OPENSEARCH_ENDPOINT'],
                os.environ['AWS_REGION']
            )
            
            # Process accounts and collect metrics
            accounts_config = json.loads(os.environ['ACCOUNTS_CONFIG'])
            all_metrics = []
            
            with ThreadPoolExecutor(max_workers=10) as executor:
                futures = [
                    executor.submit(
                        process_account,
                        account,
                        metrics_aggregator,
                        alert_manager,
                        health_scorer
                    )
                    for account in accounts_config
                ]
                
                for future in futures:
                    all_metrics.extend(future.result())
        
            # Store metrics in both S3 and OpenSearch
            storage_manager.store_metrics(all_metrics, 'hot')
            opensearch_manager.store_metrics(all_metrics)
        
            # Example query to check for critical issues
            critical_issues_query = {
                "query": {
                    "bool": {
                        "must": [
                            {"range": {"health_score": {"lt": 0.6}}},
                            {"range": {"timestamp": {"gte": "now-1h"}}}
                        ]
                    }
                }
            }
        
            critical_issues = opensearch_manager.query_metrics(critical_issues_query)
            if critical_issues:
                alert_manager.send_alerts(critical_issues)
        
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Metrics collection and storage completed',
                    'metrics_collected': len(all_metrics),
                    'critical_issues': len(critical_issues)
                })
            }
        
        except Exception as e:
            logger.error(f"Error in Lambda handler: {str(e)}")
            raise