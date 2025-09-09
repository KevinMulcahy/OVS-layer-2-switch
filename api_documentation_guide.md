# API Documentation Guide

## Table of Contents
1. [Overview](#overview)
2. [Getting Started](#getting-started)
3. [Authentication](#authentication)
4. [Base URL and Versioning](#base-url-and-versioning)
5. [Request/Response Format](#requestresponse-format)
6. [Status Codes](#status-codes)
7. [Rate Limiting](#rate-limiting)
8. [Error Handling](#error-handling)
9. [Endpoints](#endpoints)
10. [SDKs and Libraries](#sdks-and-libraries)
11. [Examples](#examples)
12. [Webhooks](#webhooks)
13. [Best Practices](#best-practices)
14. [Changelog](#changelog)
15. [Support](#support)

## Overview

This API provides comprehensive access to our platform's functionality, allowing developers to integrate our services into their applications. The API follows REST principles and returns JSON responses.

### Key Features
- RESTful architecture
- JSON request/response format
- OAuth 2.0 authentication
- Comprehensive error handling
- Rate limiting and throttling
- Webhook support
- Multiple SDKs available

### API Versions
- **Current Version**: v2.1
- **Supported Versions**: v2.0, v2.1
- **Deprecated Versions**: v1.x (sunset date: 2024-12-31)

## Getting Started

### Prerequisites
- Valid API account
- API key or OAuth 2.0 credentials
- HTTPS-enabled endpoint for webhooks (optional)

### Quick Start
1. Register for an API account
2. Generate your API credentials
3. Make your first API call
4. Implement error handling
5. Set up webhooks (optional)

### Sample First Request
```bash
curl -X GET \
  https://api.example.com/v2/users/me \
  -H 'Authorization: Bearer YOUR_API_KEY' \
  -H 'Content-Type: application/json'
```

## Authentication

### API Key Authentication
Simple authentication method for server-to-server communication.

```bash
curl -X GET \
  https://api.example.com/v2/endpoint \
  -H 'Authorization: Bearer YOUR_API_KEY'
```

### OAuth 2.0
For applications requiring user authorization.

#### Authorization Code Flow
1. **Authorization Request**
   ```
   GET https://api.example.com/oauth/authorize?
   response_type=code&
   client_id=YOUR_CLIENT_ID&
   redirect_uri=YOUR_REDIRECT_URI&
   scope=read write&
   state=RANDOM_STRING
   ```

2. **Token Exchange**
   ```bash
   curl -X POST \
     https://api.example.com/oauth/token \
     -H 'Content-Type: application/x-www-form-urlencoded' \
     -d 'grant_type=authorization_code&
         code=AUTHORIZATION_CODE&
         client_id=YOUR_CLIENT_ID&
         client_secret=YOUR_CLIENT_SECRET&
         redirect_uri=YOUR_REDIRECT_URI'
   ```

#### Token Refresh
```bash
curl -X POST \
  https://api.example.com/oauth/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=refresh_token&
      refresh_token=YOUR_REFRESH_TOKEN&
      client_id=YOUR_CLIENT_ID&
      client_secret=YOUR_CLIENT_SECRET'
```

### Scopes
| Scope | Description |
|-------|-------------|
| `read` | Read access to resources |
| `write` | Write access to resources |
| `admin` | Administrative access |
| `webhooks` | Webhook management |

## Base URL and Versioning

### Base URLs
- **Production**: `https://api.example.com`
- **Sandbox**: `https://sandbox-api.example.com`

### Versioning
All API requests must include a version number in the URL path:
```
https://api.example.com/v2/{endpoint}
```

### Version Migration
When migrating between versions:
1. Test thoroughly in sandbox environment
2. Update your application code
3. Monitor error rates after deployment
4. Have rollback plan ready

## Request/Response Format

### Request Format
- **Content-Type**: `application/json`
- **Character Encoding**: UTF-8
- **Date Format**: ISO 8601 (`2024-01-15T10:30:00Z`)

### Response Format
All responses return JSON with consistent structure:

#### Success Response
```json
{
  "data": {
    "id": 123,
    "name": "Example Resource",
    "created_at": "2024-01-15T10:30:00Z"
  },
  "meta": {
    "request_id": "req_abc123",
    "timestamp": "2024-01-15T10:30:00Z"
  }
}
```

#### List Response with Pagination
```json
{
  "data": [...],
  "pagination": {
    "total": 150,
    "page": 1,
    "per_page": 20,
    "total_pages": 8,
    "has_more": true
  },
  "meta": {
    "request_id": "req_abc123",
    "timestamp": "2024-01-15T10:30:00Z"
  }
}
```

### Common Headers
#### Request Headers
```
Authorization: Bearer YOUR_TOKEN
Content-Type: application/json
Accept: application/json
User-Agent: YourApp/1.0
```

#### Response Headers
```
Content-Type: application/json; charset=utf-8
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1640995200
X-Request-ID: req_abc123
```

## Status Codes

| Code | Status | Description |
|------|--------|-------------|
| 200 | OK | Request successful |
| 201 | Created | Resource created successfully |
| 204 | No Content | Request successful, no content returned |
| 400 | Bad Request | Invalid request parameters |
| 401 | Unauthorized | Authentication required or failed |
| 403 | Forbidden | Access denied |
| 404 | Not Found | Resource not found |
| 409 | Conflict | Resource conflict |
| 422 | Unprocessable Entity | Validation errors |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Server error |
| 503 | Service Unavailable | Service temporarily unavailable |

## Rate Limiting

### Limits
- **Default**: 1000 requests per hour per API key
- **Burst**: 100 requests per minute
- **Premium**: 5000 requests per hour per API key

### Headers
```
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 999
X-RateLimit-Reset: 1640995200
```

### Handling Rate Limits
```python
import time
import requests

def make_request_with_retry(url, headers, max_retries=3):
    for attempt in range(max_retries):
        response = requests.get(url, headers=headers)
        
        if response.status_code != 429:
            return response
        
        # Wait before retrying
        retry_after = int(response.headers.get('Retry-After', 60))
        time.sleep(retry_after)
    
    raise Exception("Rate limit exceeded after retries")
```

## Error Handling

### Error Response Format
```json
{
  "error": {
    "type": "validation_error",
    "code": "INVALID_PARAMETER",
    "message": "The email field is required.",
    "details": {
      "field": "email",
      "constraint": "required"
    }
  },
  "meta": {
    "request_id": "req_abc123",
    "timestamp": "2024-01-15T10:30:00Z"
  }
}
```

### Error Types
| Type | Description |
|------|-------------|
| `authentication_error` | Authentication failed |
| `authorization_error` | Insufficient permissions |
| `validation_error` | Request validation failed |
| `not_found_error` | Resource not found |
| `rate_limit_error` | Rate limit exceeded |
| `server_error` | Internal server error |

### Validation Errors
```json
{
  "error": {
    "type": "validation_error",
    "code": "VALIDATION_FAILED",
    "message": "Validation failed",
    "details": {
      "errors": [
        {
          "field": "email",
          "message": "Invalid email format"
        },
        {
          "field": "age",
          "message": "Must be between 18 and 120"
        }
      ]
    }
  }
}
```

## Endpoints

### Users

#### Get Current User
```
GET /v2/users/me
```

**Response:**
```json
{
  "data": {
    "id": 123,
    "email": "user@example.com",
    "name": "John Doe",
    "role": "user",
    "created_at": "2024-01-15T10:30:00Z",
    "updated_at": "2024-01-15T10:30:00Z"
  }
}
```

#### Update Current User
```
PATCH /v2/users/me
```

**Request Body:**
```json
{
  "name": "Jane Doe",
  "email": "jane@example.com"
}
```

#### List Users (Admin only)
```
GET /v2/users?page=1&per_page=20&role=user&sort=created_at:desc
```

**Query Parameters:**
- `page` (integer, default: 1): Page number
- `per_page` (integer, default: 20, max: 100): Items per page
- `role` (string): Filter by user role
- `sort` (string): Sort field and direction

### Resources

#### Create Resource
```
POST /v2/resources
```

**Request Body:**
```json
{
  "name": "My Resource",
  "description": "Resource description",
  "type": "document",
  "metadata": {
    "category": "important",
    "tags": ["tag1", "tag2"]
  }
}
```

**Response:**
```json
{
  "data": {
    "id": 456,
    "name": "My Resource",
    "description": "Resource description",
    "type": "document",
    "status": "active",
    "metadata": {
      "category": "important",
      "tags": ["tag1", "tag2"]
    },
    "created_at": "2024-01-15T10:30:00Z",
    "updated_at": "2024-01-15T10:30:00Z"
  }
}
```

#### Get Resource
```
GET /v2/resources/{id}
```

#### Update Resource
```
PATCH /v2/resources/{id}
```

#### Delete Resource
```
DELETE /v2/resources/{id}
```

#### List Resources
```
GET /v2/resources?page=1&per_page=20&type=document&status=active
```

### Search

#### Search Resources
```
GET /v2/search?q=query&type=resource&page=1&per_page=20
```

**Query Parameters:**
- `q` (string, required): Search query
- `type` (string): Filter by resource type
- `page` (integer): Page number
- `per_page` (integer): Items per page

**Response:**
```json
{
  "data": {
    "results": [...],
    "total": 150,
    "took": 25,
    "max_score": 1.5
  },
  "pagination": {
    "total": 150,
    "page": 1,
    "per_page": 20,
    "total_pages": 8,
    "has_more": true
  }
}
```

## SDKs and Libraries

### Official SDKs
- **Python**: `pip install example-api-client`
- **Node.js**: `npm install example-api-client`
- **Ruby**: `gem install example-api-client`
- **Java**: Available on Maven Central
- **PHP**: Available on Packagist

### Python SDK Example
```python
from example_api import Client

client = Client(api_key="your_api_key")

# Get current user
user = client.users.me()
print(f"Hello, {user.name}")

# Create a resource
resource = client.resources.create({
    "name": "My Resource",
    "type": "document"
})
print(f"Created resource: {resource.id}")
```

### Node.js SDK Example
```javascript
const { Client } = require('example-api-client');

const client = new Client({ apiKey: 'your_api_key' });

// Get current user
const user = await client.users.me();
console.log(`Hello, ${user.name}`);

// Create a resource
const resource = await client.resources.create({
  name: 'My Resource',
  type: 'document'
});
console.log(`Created resource: ${resource.id}`);
```

## Examples

### Complete Integration Example

#### Step 1: Authentication
```python
import requests
import json

class APIClient:
    def __init__(self, api_key, base_url="https://api.example.com/v2"):
        self.api_key = api_key
        self.base_url = base_url
        self.session = requests.Session()
        self.session.headers.update({
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        })
    
    def make_request(self, method, endpoint, **kwargs):
        url = f"{self.base_url}{endpoint}"
        response = self.session.request(method, url, **kwargs)
        
        if response.status_code == 429:
            # Handle rate limiting
            retry_after = int(response.headers.get('Retry-After', 60))
            time.sleep(retry_after)
            return self.make_request(method, endpoint, **kwargs)
        
        response.raise_for_status()
        return response.json()
```

#### Step 2: Resource Management
```python
def create_and_manage_resource():
    client = APIClient('your_api_key')
    
    # Create resource
    resource_data = {
        'name': 'Important Document',
        'description': 'This is an important document',
        'type': 'document',
        'metadata': {
            'category': 'business',
            'tags': ['important', 'document']
        }
    }
    
    resource = client.make_request('POST', '/resources', json=resource_data)
    resource_id = resource['data']['id']
    print(f"Created resource: {resource_id}")
    
    # Update resource
    update_data = {
        'description': 'Updated description'
    }
    
    updated = client.make_request('PATCH', f'/resources/{resource_id}', 
                                 json=update_data)
    print(f"Updated resource: {updated['data']['description']}")
    
    # Search for resources
    search_results = client.make_request('GET', '/search', 
                                       params={'q': 'important'})
    print(f"Found {search_results['data']['total']} resources")
    
    return resource_id
```

### Pagination Example
```python
def get_all_resources():
    client = APIClient('your_api_key')
    all_resources = []
    page = 1
    
    while True:
        response = client.make_request('GET', '/resources', 
                                     params={'page': page, 'per_page': 100})
        
        all_resources.extend(response['data'])
        
        if not response['pagination']['has_more']:
            break
        
        page += 1
    
    return all_resources
```

### Webhook Handling Example
```python
from flask import Flask, request, jsonify
import hmac
import hashlib

app = Flask(__name__)
WEBHOOK_SECRET = 'your_webhook_secret'

@app.route('/webhook', methods=['POST'])
def handle_webhook():
    # Verify webhook signature
    signature = request.headers.get('X-Webhook-Signature')
    payload = request.data
    
    expected_signature = hmac.new(
        WEBHOOK_SECRET.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()
    
    if not hmac.compare_digest(signature, f"sha256={expected_signature}"):
        return jsonify({'error': 'Invalid signature'}), 401
    
    # Process webhook
    event = request.json
    event_type = event.get('type')
    
    if event_type == 'resource.created':
        handle_resource_created(event['data'])
    elif event_type == 'resource.updated':
        handle_resource_updated(event['data'])
    elif event_type == 'resource.deleted':
        handle_resource_deleted(event['data'])
    
    return jsonify({'status': 'received'}), 200

def handle_resource_created(resource_data):
    print(f"New resource created: {resource_data['id']}")

def handle_resource_updated(resource_data):
    print(f"Resource updated: {resource_data['id']}")

def handle_resource_deleted(resource_data):
    print(f"Resource deleted: {resource_data['id']}")
```

## Webhooks

### Overview
Webhooks allow you to receive real-time notifications when events occur in your account.

### Supported Events
| Event | Description |
|-------|-------------|
| `resource.created` | New resource created |
| `resource.updated` | Resource updated |
| `resource.deleted` | Resource deleted |
| `user.created` | New user registered |
| `user.updated` | User profile updated |

### Setup
1. **Configure Endpoint**
   ```bash
   curl -X POST \
     https://api.example.com/v2/webhooks \
     -H 'Authorization: Bearer YOUR_API_KEY' \
     -H 'Content-Type: application/json' \
     -d '{
       "url": "https://your-domain.com/webhook",
       "events": ["resource.created", "resource.updated"],
       "active": true
     }'
   ```

2. **Webhook Payload**
   ```json
   {
     "id": "evt_abc123",
     "type": "resource.created",
     "created_at": "2024-01-15T10:30:00Z",
     "data": {
       "id": 456,
       "name": "New Resource",
       "type": "document"
     }
   }
   ```

3. **Security Headers**
   ```
   X-Webhook-Signature: sha256=signature_hash
   X-Webhook-ID: evt_abc123
   X-Webhook-Timestamp: 1640995200
   ```

### Best Practices
- Always verify webhook signatures
- Implement idempotency using webhook IDs
- Return 200 status code quickly
- Process webhooks asynchronously
- Handle webhook failures gracefully

## Best Practices

### Authentication Security
- Store API keys securely (environment variables, key management systems)
- Use OAuth 2.0 for user-facing applications
- Implement token refresh logic
- Never expose credentials in client-side code

### Error Handling
- Always check status codes
- Implement proper retry logic with exponential backoff
- Log errors with request IDs for debugging
- Handle rate limiting gracefully

### Performance
- Use pagination for large datasets
- Implement caching where appropriate
- Use connection pooling
- Monitor API response times

### Data Validation
- Validate input on client side
- Handle validation errors gracefully
- Use appropriate data types
- Implement field length limits

### Monitoring
- Track API usage and quotas
- Monitor error rates
- Set up alerting for failures
- Use request IDs for debugging

## Changelog

### v2.1 (2024-01-15)
- Added search endpoint
- Improved error responses
- Added webhook signature verification
- Performance improvements

### v2.0 (2023-12-01)
- Breaking: Changed authentication to Bearer tokens
- Added OAuth 2.0 support
- New resource management endpoints
- Improved rate limiting

### v1.2 (2023-09-15)
- Added pagination to list endpoints
- Bug fixes and performance improvements
- Deprecated: API key in query parameters

## Support

### Documentation
- **API Reference**: https://docs.example.com/api
- **Guides**: https://docs.example.com/guides
- **SDKs**: https://docs.example.com/sdks

### Getting Help
- **Support Portal**: https://support.example.com
- **Community Forum**: https://community.example.com
- **Email**: api-support@example.com

### Status and Monitoring
- **Status Page**: https://status.example.com
- **Maintenance Schedule**: Check status page for planned maintenance

### Feedback
We value your feedback! Please share your thoughts:
- **Feature Requests**: https://feedback.example.com
- **Bug Reports**: https://github.com/example/api/issues
- **Developer Survey**: Complete our quarterly developer survey

---

*Last Updated: January 15, 2024*
*API Version: 2.1*