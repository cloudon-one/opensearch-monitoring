
import argparse
import base64
import json
import requests
import sys
from urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

def create_auth_header(username, password):
    credentials = f"{username}:{password}"
    encoded = base64.b64encode(credentials.encode()).decode()
    return f"Basic {encoded}"

def import_dashboard(endpoint, auth_header, dashboard_file):
    base_url = f"https://{endpoint}"
    
    # Create index pattern
    index_pattern_url = f"{base_url}/_dashboards/api/saved_objects/index-pattern/metrics-*"
    index_pattern_data = {
        "attributes": {
            "title": "metrics-*",
            "timeFieldName": "timestamp"
        }
    }
    
    headers = {
        "Authorization": auth_header,
        "Content-Type": "application/json",
        "osd-xsrf": "true"
    }
    
    try:
        # Create index pattern
        response = requests.put(
            index_pattern_url,
            headers=headers,
            json=index_pattern_data,
            verify=False
        )
        print(f"Index pattern creation status: {response.status_code}")
        
        # Import dashboard
        import_url = f"{base_url}/_dashboards/api/saved_objects/_import?overwrite=true"
        with open(dashboard_file, 'rb') as f:
            files = {'file': ('dashboard.json', f)}
            response = requests.post(
                import_url,
                headers={"Authorization": auth_header, "osd-xsrf": "true"},
                files=files,
                verify=False
            )
        print(f"Dashboard import status: {response.status_code}")
        
        if response.status_code not in (200, 201):
            print(f"Error response: {response.text}")
            sys.exit(1)
            
    except Exception as e:
        print(f"Error importing dashboard: {str(e)}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description='Import OpenSearch dashboard')
    parser.add_argument('--endpoint', required=True, help='OpenSearch endpoint')
    parser.add_argument('--username', required=True, help='OpenSearch username')
    parser.add_argument('--password', required=True, help='OpenSearch password')
    parser.add_argument('--dashboard-file', required=True, help='Dashboard JSON file path')
    
    args = parser.parse_args()
    auth_header = create_auth_header(args.username, args.password)
    
    import_dashboard(args.endpoint, auth_header, args.dashboard_file)

if __name__ == '__main__':
    main()