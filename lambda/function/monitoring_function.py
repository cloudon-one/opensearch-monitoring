import json
import boto3
import os
import logging
from datetime import datetime
import time
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth
from concurrent.futures import ThreadPoolExecutor

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

class MetricsCollector:
    def __init__(self):
        self.cloudwatch = boto3.client('cloudwatch')
        self.logs = boto3.client('logs')
        self.function_name = os.environ['AWS_LAMBDA_FUNCTION_NAME']

    def collect_metrics(self, context):
        return {
            'memory': self._get_memory_metrics(context),
            'duration': self._get_duration_metrics(context),
            'errors': self._get_error_metrics(),
            'cost': self._calculate_cost(context),
            'timestamp': datetime.now().isoformat()
        }

    def _get_memory_metrics(self, context):
        return {
            'used_memory': context.memory_limit_in_mb,
            'timestamp': datetime.now().isoformat()
        }

    def _get_duration_metrics(self, context):
        remaining_time = context.get_remaining_time_in_millis()
        total_time = context.memory_limit_in_mb * 1000
        return {
            'duration': total_time - remaining_time,
            'timestamp': datetime.now().isoformat()
        }

    def _get_error_metrics(self):
        response = self.logs.filter_log_events(
            logGroupName=f"/aws/lambda/{self.function_name}",
            filterPattern="ERROR"
        )
        return {
            'error_count': len(response.get('events', [])),
            'timestamp': datetime.now().isoformat()
        }

    def _calculate_cost(self, context):
        memory_gb = context.memory_limit_in_mb / 1024
        duration_sec = context.get_remaining_time_in_millis() / 1000
        cost = (memory_gb * duration_sec * 0.0000166667)
        return {
            'cost': cost,
            'timestamp': datetime.now().isoformat()
        }

class AlertManager:
    def __init__(self):
        self.sns = boto3.client('sns')
        self.critical_topic = os.environ['CRITICAL_ALERTS_TOPIC']
        self.warning_topic = os.environ['WARNING_ALERTS_TOPIC']
        self.alerts = []

    def process_metrics(self, metrics):
        self._check_thresholds(metrics)
        return self.alerts

    def _check_thresholds(self, metrics):
        thresholds = self._load_thresholds()
        for metric_type, metric_data in metrics.items():
            if metric_type in thresholds:
                self._evaluate_metric(metric_type, metric_data, thresholds[metric_type])

    def _evaluate_metric(self, metric_type, metric_data, thresholds):
        value = self._extract_value(metric_data)
        if value > thresholds['critical']:
            self._create_alert('CRITICAL', metric_type, value, self.critical_topic)
        elif value > thresholds['warning']:
            self._create_alert('WARNING', metric_type, value, self.warning_topic)

    def _create_alert(self, severity, metric_type, value, topic_arn):
        alert = {
            'severity': severity,
            'metric_type': metric_type,
            'value': value,
            'timestamp': datetime.now().isoformat()
        }
        
        if not self._is_throttled(alert):
            self.alerts.append(alert)
            self.sns.publish(
                TopicArn=topic_arn,
                Message=json.dumps(alert),
                Subject=f"Lambda Monitor Alert: {severity} - {metric_type}"
            )

    def _is_throttled(self, alert):
        throttle_window = 300  # 5 minutes
        recent_alerts = [a for a in self.alerts 
                        if a['metric_type'] == alert['metric_type'] 
                        and a['severity'] == alert['severity']]
        
        if recent_alerts:
            latest_alert = max(recent_alerts, key=lambda x: x['timestamp'])
            time_diff = (datetime.now() - 
                        datetime.fromisoformat(latest_alert['timestamp'])).total_seconds()
            return time_diff < throttle_window
        return False

class StorageManager:
    def __init__(self):
        self.client = self._create_opensearch_client()
        
    def _create_opensearch_client(self):
        host = os.environ['OPENSEARCH_ENDPOINT']
        region = os.environ['AWS_REGION']
        credentials = boto3.Session().get_credentials()
        auth = AWS4Auth(
            credentials.access_key,
            credentials.secret_key,
            region,
            'es',
            session_token=credentials.token
        )
        
        return OpenSearch(
            hosts=[{'host': host, 'port': 443}],
            http_auth=auth,
            use_ssl=True,
            verify_certs=True,
            connection_class=RequestsHttpConnection
        )

    def store_metrics(self, metrics, alerts):
        index_name = f"metrics-{datetime.now().strftime('%Y.%m.%d')}"
        document = {
            'metrics': metrics,
            'alerts': alerts,
            'timestamp': datetime.now().isoformat(),
            'function_name': os.environ['AWS_LAMBDA_FUNCTION_NAME']
        }
        
        self.client.index(
            index=index_name,
            body=document,
            id=f"{document['function_name']}-{datetime.now().timestamp()}"
        )

def lambda_handler(event, context):
    try:
        metrics_collector = MetricsCollector()
        alert_manager = AlertManager()
        storage_manager = StorageManager()

        # Collect metrics
        metrics = metrics_collector.collect_metrics(context)
        
        # Process alerts
        alerts = alert_manager.process_metrics(metrics)
        
        # Store data
        storage_manager.store_metrics(metrics, alerts)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'metrics': metrics,
                'alerts': alerts
            })
        }
    except Exception as e:
        logger.error(f"Error in lambda handler: {str(e)}", exc_info=True)
        raise