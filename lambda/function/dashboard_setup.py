import boto3
import requests
import json
import time
from requests_aws4auth import AWS4Auth
import os

def create_opensearch_dashboards():
    """
    Enhanced script to create OpenSearch dashboards and visualizations for Lambda monitoring
    """
    host = os.environ['OPENSEARCH_HOST']
    region = os.environ['AWS_REGION']
    service = 'es'
    
    credentials = boto3.Session().get_credentials()
    awsauth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        region,
        service,
        session_token=credentials.token
    )
    
    base_url = f"https://{host}/_dashboards/api"
    
    # Enhanced index pattern with additional fields
    index_pattern = {
        "attributes": {
            "title": "lambda-metrics-*",
            "timeFieldName": "timestamp",
            "fields": json.dumps([
                {"name": "account_id", "type": "string", "searchable": True, "aggregatable": True},
                {"name": "function_name", "type": "string", "searchable": True, "aggregatable": True},
                {"name": "region", "type": "string", "searchable": True, "aggregatable": True},
                {"name": "runtime", "type": "string", "searchable": True, "aggregatable": True},
                {"name": "memory", "type": "number", "searchable": True, "aggregatable": True},
                {"name": "timeout", "type": "number", "searchable": True, "aggregatable": True},
                {"name": "invocations", "type": "number", "searchable": True, "aggregatable": True},
                {"name": "errors", "type": "number", "searchable": True, "aggregatable": True},
                {"name": "duration_ms", "type": "number", "searchable": True, "aggregatable": True},
                {"name": "timestamp", "type": "date", "searchable": True, "aggregatable": True},
                {"name": "memory_utilization", "type": "number", "searchable": True, "aggregatable": True},
                {"name": "cold_starts", "type": "number", "searchable": True, "aggregatable": True}
            ])
        }
    }
    
    # Enhanced visualizations including new metrics
    visualizations = {
        "total_invocations": {
            "attributes": {
                "title": "Total Lambda Invocations",
                "visState": json.dumps({
                    "title": "Total Lambda Invocations",
                    "type": "metric",
                    "params": {
                        "metric": {
                            "percentageMode": False,
                            "useRanges": False,
                            "colorSchema": "Green to Red",
                            "metricColorMode": "None",
                            "colorsRange": [{"from": 0, "to": 10000}],
                            "labels": {"show": True},
                            "style": {"bgFill": "#000", "bgColor": False, "labelColor": False}
                        }
                    },
                    "aggs": [{
                        "id": "1",
                        "enabled": True,
                        "type": "sum",
                        "schema": "metric",
                        "params": {"field": "invocations"}
                    }]
                })
            }
        },
        "memory_usage_distribution": {
            "attributes": {
                "title": "Memory Usage Distribution",
                "visState": json.dumps({
                    "title": "Memory Usage Distribution",
                    "type": "histogram",
                    "params": {
                        "type": "histogram",
                        "grid": {"categoryLines": False},
                        "valueAxes": [{
                            "id": "ValueAxis-1",
                            "name": "LeftAxis-1",
                            "type": "value",
                            "position": "left",
                            "show": True,
                            "style": {},
                            "scale": {"type": "linear"},
                            "labels": {"show": True},
                            "title": {"text": "Function Count"}
                        }],
                        "seriesParams": [{
                            "show": True,
                            "type": "histogram",
                            "mode": "normal",
                            "data": {"label": "Function Count", "id": "1"},
                            "valueAxis": "ValueAxis-1"
                        }]
                    },
                    "aggs": [{
                        "id": "1",
                        "enabled": True,
                        "type": "count",
                        "schema": "metric",
                        "params": {}
                    },
                    {
                        "id": "2",
                        "enabled": True,
                        "type": "histogram",
                        "schema": "segment",
                        "params": {
                            "field": "memory",
                            "interval": 128,
                            "min_doc_count": 1
                        }
                    }]
                })
            }
        },
        "timeout_analysis": {
            "attributes": {
                "title": "Timeout Analysis",
                "visState": json.dumps({
                    "title": "Timeout Analysis",
                    "type": "gauge",
                    "params": {
                        "type": "gauge",
                        "addTooltip": True,
                        "addLegend": True,
                        "gauge": {
                            "verticalSplit": False,
                            "extendRange": True,
                            "percentageMode": True,
                            "gaugeType": "Arc",
                            "gaugeStyle": "Full",
                            "backStyle": "Full",
                            "orientation": "vertical",
                            "colorSchema": "Green to Red",
                            "gaugeColorMode": "Labels",
                            "colorsRange": [
                                {"from": 0, "to": 50},
                                {"from": 50, "to": 75},
                                {"from": 75, "to": 100}
                            ],
                            "labels": {"show": True}
                        }
                    },
                    "aggs": [{
                        "id": "1",
                        "enabled": True,
                        "type": "avg",
                        "schema": "metric",
                        "params": {
                            "field": "duration_ms",
                            "script": {
                                "source": "doc['duration_ms'].value / (doc['timeout'].value * 1000) * 100",
                                "lang": "painless"
                            }
                        }
                    }]
                })
            }
        },
        "runtime_distribution": {
            "attributes": {
                "title": "Runtime Distribution",
                "visState": json.dumps({
                    "title": "Runtime Distribution",
                    "type": "pie",
                    "params": {
                        "type": "pie",
                        "addTooltip": True,
                        "addLegend": True,
                        "legendPosition": "right",
                        "isDonut": False
                    },
                    "aggs": [
                        {
                            "id": "1",
                            "enabled": True,
                            "type": "count",
                            "schema": "metric",
                            "params": {}
                        },
                        {
                            "id": "2",
                            "enabled": True,
                            "type": "terms",
                            "schema": "segment",
                            "params": {
                                "field": "runtime",
                                "size": 10,
                                "order": "desc",
                                "orderBy": "1"
                            }
                        }
                    ]
                })
            }
        },
        "memory_utilization_trend": {
            "attributes": {
                "title": "Memory Utilization Trend",
                "visState": json.dumps({
                    "title": "Memory Utilization Trend",
                    "type": "line",
                    "params": {
                        "type": "line",
                        "grid": {"categoryLines": False},
                        "categoryAxes": [{
                            "id": "CategoryAxis-1",
                            "type": "category",
                            "position": "bottom",
                            "show": True,
                            "style": {},
                            "scale": {"type": "linear"},
                            "labels": {"show": True},
                            "title": {}
                        }],
                        "valueAxes": [{
                            "id": "ValueAxis-1",
                            "name": "LeftAxis-1",
                            "type": "value",
                            "position": "left",
                            "show": True,
                            "style": {},
                            "scale": {"type": "linear"},
                            "labels": {"show": True},
                            "title": {"text": "Memory Utilization %"}
                        }]
                    },
                    "aggs": [
                        {
                            "id": "1",
                            "enabled": True,
                            "type": "avg",
                            "schema": "metric",
                            "params": {"field": "memory_utilization"}
                        },
                        {
                            "id": "2",
                            "enabled": True,
                            "type": "date_histogram",
                            "schema": "segment",
                            "params": {
                                "field": "timestamp",
                                "interval": "auto",
                                "min_doc_count": 1
                            }
                        }
                    ]
                })
            }
        },
        "cold_starts_analysis": {
            "attributes": {
                "title": "Cold Starts Analysis",
                "visState": json.dumps({
                    "title": "Cold Starts Analysis",
                    "type": "area",
                    "params": {
                        "type": "area",
                        "grid": {"categoryLines": False},
                        "categoryAxes": [{
                            "id": "CategoryAxis-1",
                            "type": "category",
                            "position": "bottom",
                            "show": True,
                            "style": {},
                            "scale": {"type": "linear"},
                            "labels": {"show": True},
                            "title": {}
                        }],
                        "valueAxes": [{
                            "id": "ValueAxis-1",
                            "name": "LeftAxis-1",
                            "type": "value",
                            "position": "left",
                            "show": True,
                            "style": {},
                            "scale": {"type": "linear"},
                            "labels": {"show": True},
                            "title": {"text": "Cold Start Count"}
                        }]
                    },
                    "aggs": [
                        {
                            "id": "1",
                            "enabled": True,
                            "type": "sum",
                            "schema": "metric",
                            "params": {"field": "cold_starts"}
                        },
                        {
                            "id": "2",
                            "enabled": True,
                            "type": "date_histogram",
                            "schema": "segment",
                            "params": {
                                "field": "timestamp",
                                "interval": "auto",
                                "min_doc_count": 1
                            }
                        }
                    ]
                })
            }
        }
    }
    
    # Enhanced dashboard layout
    dashboard = {
        "attributes": {
            "title": "Lambda Fleet Monitoring",
            "hits": 0,
            "description": "Comprehensive overview of Lambda functions across accounts",
            "panelsJSON": json.dumps([
                {
                    "gridData": {"x": 0, "y": 0, "w": 12, "h": 8, "i": "1"},
                    "version": "7.9.0",
                    "panelIndex": "1",
                    "embeddableConfig": {},
                    "panelRefName": "panel_1"
                },
                {
                    "gridData": {"x": 12, "y": 0, "w": 12, "h": 8, "i": "2"},
                    "version": "7.9.0",
                    "panelIndex": "2",
                    "embeddableConfig": {},
                    "panelRefName": "panel_2"
                },
                {
                    "gridData": {"x": 0, "y": 8, "w": 12, "h": 8, "i": "3"},
                    "version": "7.9.0",
                    "panelIndex": "3",
                    "embeddableConfig": {},
                    "panelRefName": "panel_3"
                },
                {
                    "gridData": {"x": 12, "y": 8, "w": 12, "h": 8, "i": "4"},
                    "version": "7.9.0",
                    "panelIndex": "4",
                    "embeddableConfig": {},
                    "panelRefName": "panel_4"
                },
                {
                    "gridData": {"x": 0, "y": 16, "w": 24, "h": 8, "i": "5"},
                    "version": "7.9.0",
                    "panelIndex": "5",
                    "embeddableConfig": {},
                    "panelRefName": "panel_5"
                },
                {
                    "gridData": {"x": 0, "y": 24, "w": 24, "h": 8, "i": "6"},
                    "version": "7.9.0",
                    "panelIndex": "6",
                    "embeddableConfig": {},
                    "panelRefName": "panel_6"
                }
            ]),
            "optionsJSON": json.dumps({
                "hidePanelTitles": False,
                "useMargins": True
            }),
            "version": 1,
            "timeRestore": True,
            "timeTo": "now",
            "timeFrom": "now-24h",
            "refreshInterval": {
                "pause": False,
                "value": 300000
            }
        }
    }
    
    # Create index pattern
    response = requests.post(
        f"{base_url}/saved_objects/index-pattern",
        auth=awsauth,
        headers={"Content-Type": "application/json", "kbn-xsrf": "true"},
        json=index_pattern
    )
    print(f"Index pattern creation response: {response.status_code}")
    
    # Create visualizations
    viz_refs = []
    for viz_id, viz_config in visualizations.items():
        response = requests.post(
            f"{base_url}/saved_objects/visualization/{viz_id}",
            auth=awsauth,
            headers={"Content-Type": "application/json", "kbn-xsrf": "true"},
            json=viz_config
        )
        print(f"Visualization {viz_id} creation response: {response.status_code}")
        viz_refs.append({
            "name": f"panel_{len(viz_refs) + 1}",
            "type": "visualization",
            "id": viz_id
        })
    
    dashboard["references"] = viz_refs
    
    # Create dashboard
    response = requests.post(
        f"{base_url}/saved_objects/dashboard/lambda-fleet-monitoring",
        auth=awsauth,
        headers={"Content-Type": "application/json", "kbn-xsrf": "true"},
        json=dashboard
    )
    print(f"Dashboard creation response: {response.status_code}")

if __name__ == "__main__":
    create_opensearch_dashboards()