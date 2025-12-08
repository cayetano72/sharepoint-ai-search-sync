#!/usr/bin/env python3
"""Check detailed indexer warnings and errors."""

import sys
import os
import requests
import json

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
if PROJECT_ROOT not in sys.path:
    sys.path.append(PROJECT_ROOT)

from config.settings import config

def get_indexer_status_details(indexer_name: str):
    """Get detailed indexer status including warnings."""
    headers = {
        "Content-Type": "application/json",
        "api-key": config.search_api_key
    }
    api_version = "2024-07-01"
    url = f"{config.search_endpoint}/indexers/{indexer_name}/status?api-version={api_version}"
    
    response = requests.get(url, headers=headers)
    
    if response.status_code == 200:
        status_data = response.json()
        
        print(f"\n=== Indexer: {indexer_name} ===")
        print(f"Status: {status_data.get('status')}")
        
        last_result = status_data.get('lastResult', {})
        if last_result:
            print(f"\nLast Run:")
            print(f"  Status: {last_result.get('status')}")
            print(f"  Items Processed: {last_result.get('itemsProcessed', 0)}")
            print(f"  Items Failed: {last_result.get('itemsFailed', 0)}")
            
            # Check for errors
            errors = last_result.get('errors', [])
            if errors:
                print(f"\n  ERRORS ({len(errors)}):")
                for i, error in enumerate(errors[:10], 1):
                    print(f"    {i}. {error.get('errorMessage', 'Unknown error')}")
                    print(f"       Key: {error.get('key', 'N/A')}")
                    print(f"       Name: {error.get('name', 'N/A')}")
            
            # Check for warnings
            warnings = last_result.get('warnings', [])
            if warnings:
                print(f"\n  WARNINGS ({len(warnings)}):")
                for i, warning in enumerate(warnings[:20], 1):
                    print(f"    {i}. {warning.get('message', 'Unknown warning')}")
                    print(f"       Key: {warning.get('key', 'N/A')}")
                    print(f"       Name: {warning.get('name', 'N/A')}")
                    print(f"       Details: {warning.get('details', 'N/A')}")
                    print()
        
        # Check execution history
        history = status_data.get('executionHistory', [])
        if history and len(history) > 1:
            print(f"\n=== Recent Execution ===")
            recent = history[0]
            print(f"Status: {recent.get('status')}")
            warnings = recent.get('warnings', [])
            if warnings:
                print(f"Warnings in this run: {len(warnings)}")
                for i, warning in enumerate(warnings[:5], 1):
                    print(f"  {i}. {warning.get('message', 'Unknown')}")
        
        return status_data
    else:
        print(f"Error: {response.status_code}")
        print(response.text)
        return None

if __name__ == "__main__":
    indexer_name = sys.argv[1] if len(sys.argv) > 1 else "pp-dev-navi-bki-code-ix"
    get_indexer_status_details(indexer_name)
