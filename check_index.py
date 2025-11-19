#!/usr/bin/env python3
"""Quick script to check index statistics and sample documents."""

import os
import requests
from dotenv import load_dotenv
import json

load_dotenv()

SEARCH_ENDPOINT = os.getenv('SEARCH_ENDPOINT')
SEARCH_API_KEY = os.getenv('SEARCH_API_KEY')
INDEX_NAME = 'idx-score-operatorsupport'

headers = {
    'api-key': SEARCH_API_KEY,
    'Content-Type': 'application/json'
}

# Get index statistics
print(f"=== Index Statistics for {INDEX_NAME} ===\n")
stats_url = f"{SEARCH_ENDPOINT}/indexes/{INDEX_NAME}/stats?api-version=2024-07-01"
stats_response = requests.get(stats_url, headers=headers)

if stats_response.status_code == 200:
    stats = stats_response.json()
    print(f"Document Count: {stats.get('documentCount', 0)}")
    print(f"Storage Size: {stats.get('storageSize', 0)} bytes")
    print(f"Vector Index Size: {stats.get('vectorIndexSize', 0)} bytes")
    print()
else:
    print(f"Error getting stats: {stats_response.status_code}")
    print(stats_response.text)
    exit(1)

# Get a few sample documents
print(f"=== Sample Documents ===\n")
search_url = f"{SEARCH_ENDPOINT}/indexes/{INDEX_NAME}/docs/search?api-version=2024-07-01"
search_body = {
    "search": "*",
    "top": 3
}

search_response = requests.post(search_url, headers=headers, json=search_body)

if search_response.status_code == 200:
    results = search_response.json()
    doc_count = results.get('@odata.count') or len(results.get('value', []))
    print(f"Total documents in search: {doc_count}\n")
    
    for i, doc in enumerate(results.get('value', []), 1):
        print(f"Document {i}:")
        print(f"  Available fields: {list(doc.keys())}")
        print()
        for key, value in doc.items():
            if key.startswith('@'):
                continue
            if isinstance(value, str):
                display_value = value[:200] + '...' if len(value) > 200 else value
            elif isinstance(value, list) and len(value) > 0:
                display_value = f"[{len(value)} items] {str(value[0])[:100]}..."
            else:
                display_value = str(value)[:200]
            print(f"  {key}: {display_value}")
        print()
else:
    print(f"Error searching: {search_response.status_code}")
    print(search_response.text)

# Test vector search
print(f"\n=== Vector Search Test ===\n")
vector_search_body = {
    "vectorQueries": [
        {
            "kind": "text",
            "text": "NCEMS integration requirements",
            "fields": "content_vector",
            "k": 3
        }
    ],
    "select": "title,source_url"
}

vector_response = requests.post(search_url, headers=headers, json=vector_search_body)

if vector_response.status_code == 200:
    results = vector_response.json()
    print(f"Vector search returned {len(results.get('value', []))} results\n")
    
    for i, doc in enumerate(results.get('value', []), 1):
        print(f"Result {i}:")
        print(f"  Score: {doc.get('@search.score', 'N/A')}")
        print(f"  Title: {doc.get('title', 'N/A')}")
        print(f"  Source URL: {doc.get('source_url', 'N/A')}")
        print()
    
    print("✅ Vector embeddings are working correctly!")
else:
    print(f"❌ Error with vector search: {vector_response.status_code}")
    print(vector_response.text)
