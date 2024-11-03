import boto3
import json
import os
import requests
from datetime import datetime, timezone
from aws_requests_auth.aws_auth import AWSRequestsAuth
from typing import Dict, List, Optional, Tuple, Union
import logging

class LambdaMonitor:
    def __init__(self, opensearch_endpoint: str, region: str = None):
        """
        Initialize Lambda monitoring with OpenSearch configuration.
        
        Args:
            opensearch_endpoint: OpenSearch domain endpoint
            region: AWS region (defaults to environment variable)
        """
        self.opensearch_endpoint = opensearch_endpoint
        self.region = region or os.environ.get('AWS_REGION')
        self.session = boto3.Session()
        self.credentials = self.session.get_credentials()
        
        # Set up authentication
        self.auth = AWSRequestsAuth(
            aws_access_key=self.credentials.access_key,
            aws_secret_access_key=self.credentials.secret_key,
            aws_token=self.credentials.token,
            aws_host=opensearch_endpoint,
            aws_region=self.region,
            aws_service='es'
        )
        
        # Configure logging
        self.logger = logging.getLogger('LambdaMonitor')
        self.logger.setLevel(logging.INFO)

    def process_cloudwatch_event(self, event: Dict) -> bool:
        """
        Process CloudWatch Logs events and ship to OpenSearch.
        
        Args:
            event: CloudWatch Logs event
            
        Returns:
            bool: Success status
        """
        try:
            # Extract and decode CloudWatch data
            cw_data = event['awslogs']['data']
            log_events = json.loads(cw_data)
            
            # Process each log event
            processed_events = []
            for log_event in log_events['logEvents']:
                processed_event = self._process_log_event(
                    log_event,
                    log_events['logGroup'],
                    log_events['logStream']
                )
                processed_events.append(processed_event)
            
            # Ship to OpenSearch
            return self._ship_to_opensearch(processed_events)
            
        except Exception as e:
            self.logger.error(f"Error processing CloudWatch event: {str(e)}")
            return False

    def _process_log_event(self, event: Dict, log_group: str, log_stream: str) -> Dict:
        """
        Process individual log events and extract metrics.
        
        Args:
            event: Log event
            log_group: CloudWatch log group
            log_stream: CloudWatch log stream
            
        Returns:
            Dict: Processed metrics and data
        """
        try:
            # Parse message
            message = event['message']
            try:
                message_data = json.loads(message)
            except json.JSONDecodeError:
                message_data = {'raw_message': message}
            
            # Extract function name
            function_name = log_group.split('/')[-1]
            
            # Extract base metrics
            metrics = {
                'timestamp': datetime.fromtimestamp(event['timestamp'] / 1000, timezone.utc).isoformat(),
                'function_name': function_name,
                'log_group': log_group,
                'log_stream': log_stream,
                'message': message_data,
                'raw_message': message
            }
            
            # Extract performance metrics
            metrics.update(self._extract_performance_metrics(message))
            
            # Extract error information
            metrics.update(self._extract_error_info(message))
            
            # Calculate derived metrics
            metrics.update(self._calculate_derived_metrics(metrics))
            
            return metrics
            
        except Exception as e:
            self.logger.error(f"Error processing log event: {str(e)}")
            return {}

    def _extract_performance_metrics(self, message: str) -> Dict:
        """
        Extract performance metrics from log message.
        
        Args:
            message: Log message
            
        Returns:
            Dict: Performance metrics
        """
        metrics = {
            'duration': None,
            'memory_used': None,
            'max_memory': None,
            'cold_start': False
        }
        
        try:
            # Extract duration
            if 'Duration:' in message:
                duration_str = message.split('Duration:')[1].split('ms')[0].strip()
                metrics['duration'] = float(duration_str)
            
            # Extract memory usage
            if 'Memory Used:' in message:
                memory_str = message.split('Memory Used:')[1].split('MB')[0].strip()
                metrics['memory_used'] = int(memory_str)
            
            # Extract max memory
            if 'Max Memory Used:' in message:
                max_memory_str = message.split('Max Memory Used:')[1].split('MB')[0].strip()
                metrics['max_memory'] = int(max_memory_str)
            
            # Detect cold starts
            metrics['cold_start'] = 'Init Duration:' in message
            
            return metrics
            
        except Exception as e:
            self.logger.warning(f"Error extracting performance metrics: {str(e)}")
            return metrics

    def _extract_error_info(self, message: str) -> Dict:
        """
        Extract error information from log message.
        
        Args:
            message: Log message
            
        Returns:
            Dict: Error information
        """
        error_info = {
            'has_error': False,
            'error_type': None,
            'error_message': None
        }
        
        try:
            # Check for common error patterns
            if any(error_term in message for error_term in ['ERROR', 'Exception', 'Task timed out']):
                error_info['has_error'] = True
                
                # Extract error type
                if 'Exception:' in message:
                    error_info['error_type'] = message.split('Exception:')[0].split()[-1]
                
                # Extract error message
                error_info['error_message'] = message
            
            return error_info
            
        except Exception as e:
            self.logger.warning(f"Error extracting error info: {str(e)}")
            return error_info

    def _calculate_derived_metrics(self, metrics: Dict) -> Dict:
        """
        Calculate derived metrics from base metrics.
        
        Args:
            metrics: Base metrics
            
        Returns:
            Dict: Derived metrics
        """
        derived_metrics = {
            'memory_utilization': None,
            'cost_gb_seconds': None,
            'health_score': None
        }
        
        try:
            # Calculate memory utilization
            if metrics['memory_used'] and metrics['max_memory']:
                derived_metrics['memory_utilization'] = (
                    metrics['memory_used'] / metrics['max_memory'] * 100
                )
            
            # Calculate GB-seconds (for cost)
            if metrics['duration'] and metrics['memory_used']:
                gb_memory = metrics['memory_used'] / 1024
                seconds = metrics['duration'] / 1000
                derived_metrics['cost_gb_seconds'] = gb_memory * seconds
            
            # Calculate health score (0-100)
            health_score = 100
            if metrics['has_error']:
                health_score -= 50
            if metrics['duration'] and metrics['duration'] > 1000:
                health_score -= 20
            if derived_metrics['memory_utilization'] and derived_metrics['memory_utilization'] > 80:
                health_score -= 10
                
            derived_metrics['health_score'] = health_score
            
            return derived_metrics
            
        except Exception as e:
            self.logger.warning(f"Error calculating derived metrics: {str(e)}")
            return derived_metrics

    def _ship_to_opensearch(self, events: List[Dict]) -> bool:
        """
        Ship processed events to OpenSearch.
        
        Args:
            events: List of processed events
            
        Returns:
            bool: Success status
        """
        try:
            if not events:
                return True
                
            # Prepare bulk request body
            bulk_body = ''
            for event in events:
                if event:  # Skip empty events
                    # Create index name with date
                    index_name = f"lambda-logs-{datetime.now().strftime('%Y-%m')}"
                    
                    # Create action line
                    action = {
                        "index": {
                            "_index": index_name,
                            "_id": f"{event['function_name']}_{event['timestamp']}"
                        }
                    }
                    
                    # Add to bulk body
                    bulk_body += json.dumps(action) + '\n'
                    bulk_body += json.dumps(event) + '\n'
            
            # Send to OpenSearch
            if bulk_body:
                url = f'https://{self.opensearch_endpoint}/_bulk'
                headers = {'Content-Type': 'application/x-ndjson'}
                
                response = requests.post(
                    url,
                    auth=self.auth,
                    headers=headers,
                    data=bulk_body
                )
                
                if response.status_code not in (200, 201):
                    self.logger.error(
                        f"Error shipping to OpenSearch: {response.status_code} - {response.text}"
                    )
                    return False
                
                # Log success
                self.logger.info(
                    f"Successfully shipped {len(events)} events to OpenSearch"
                )
                return True
                
            return True
            
        except Exception as e:
            self.logger.error(f"Error shipping to OpenSearch: {str(e)}")
            return False

    def create_alert(self, alert_config: Dict) -> bool:
        """
        Create or update an alert in OpenSearch.
        
        Args:
            alert_config: Alert configuration
            
        Returns:
            bool: Success status
        """
        try:
            url = f'https://{self.opensearch_endpoint}/_plugins/_alerting/monitors'
            headers = {'Content-Type': 'application/json'}
            
            response = requests.post(
                url,
                auth=self.auth,
                headers=headers,
                json=alert_config
            )
            
            return response.status_code in (200, 201)
            
        except Exception as e:
            self.logger.error(f"Error creating alert: {str(e)}")
            return False

    def get_metrics(self, 
                   function_name: Optional[str] = None,
                   start_time: Optional[str] = None,
                   end_time: Optional[str] = None) -> Dict:
        """
        Get metrics for specified function and time range.
        
        Args:
            function_name: Lambda function name (optional)
            start_time: Start time in ISO format (optional)
            end_time: End time in ISO format (optional)
            
        Returns:
            Dict: Metrics data
        """
        try:
            # Build query
            query = {
                "size": 0,
                "query": {
                    "bool": {
                        "must": []
                    }
                },
                "aggs": {
                    "by_function": {
                        "terms": {
                            "field": "function_name",
                            "size": 100
                        },
                        "aggs": {
                            "error_rate": {
                                "filters": {
                                    "filters": {
                                        "errors": {"term": {"has_error": True}},
                                        "total": {"match_all": {}}
                                    }
                                }
                            },
                            "duration_stats": {
                                "stats": {"field": "duration"}
                            },
                            "memory_stats": {
                                "stats": {"field": "memory_utilization"}
                            },
                            "health_score_avg": {
                                "avg": {"field": "health_score"}
                            }
                        }
                    }
                }
            }
            
            # Add function filter if specified
            if function_name:
                query["query"]["bool"]["must"].append({
                    "term": {"function_name": function_name}
                })
            
            # Add time range if specified
            if start_time or end_time:
                time_range = {"range": {"timestamp": {}}}
                if start_time:
                    time_range["range"]["timestamp"]["gte"] = start_time
                if end_time:
                    time_range["range"]["timestamp"]["lte"] = end_time
                query["query"]["bool"]["must"].append(time_range)
            
            # Execute query
            url = f'https://{self.opensearch_endpoint}/lambda-logs-*/_search'
            headers = {'Content-Type': 'application/json'}
            
            response = requests.post(
                url,
                auth=self.auth,
                headers=headers,
                json=query
            )
            
            if response.status_code == 200:
                return response.json()
            else:
                self.logger.error(
                    f"Error getting metrics: {response.status_code} - {response.text}"
                )
                return {}
                
        except Exception as e:
            self.logger.error(f"Error getting metrics: {str(e)}")
            return {}

# Example usage
def lambda_handler(event, context):
    """
    Main Lambda handler for monitoring.
    
    Args:
        event: Lambda event
        context: Lambda context
        
    Returns:
        Dict: Processing results
    """
    # Initialize monitor
    monitor = LambdaMonitor(
        opensearch_endpoint=os.environ['OPENSEARCH_ENDPOINT']
    )
    
    # Process events
    success = monitor.process_cloudwatch_event(event)
    
    return {
        'statusCode': 200 if success else 500,
        'body': json.dumps({
            'message': 'Successfully processed events' if success else 'Error processing events'
        })
    }