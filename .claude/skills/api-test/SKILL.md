---
name: api-test
description: Test a backend API endpoint with curl. Use when the user wants to test, debug, or verify an API endpoint.
---

# Test a Backend API Endpoint

Test the endpoint described in `$ARGUMENTS`.

## Steps

1. Determine the target URL:
   - Local dev: `http://localhost:3000`
   - Production: `https://mad.mindgoblin.tech`
   - Default to production unless the user says "local" or "localhost"

2. Build and run the curl command:
   - Include `-s` for silent mode and pipe through `jq` for formatting (fall back to raw output if jq unavailable)
   - For protected endpoints, ask the user for a bearer token or check if one was provided in `$ARGUMENTS`
   - Add `-H "Authorization: Bearer <token>"` for authenticated routes
   - Add `-H "Content-Type: application/json"` for POST/PUT/PATCH requests
   - Use `-X <METHOD>` explicitly

3. Show the full curl command before running it so the user can reuse it.

4. Analyze the response:
   - Flag any error status codes
   - Highlight unexpected response shapes vs what the controller returns
   - If it fails, check if the endpoint exists in the route files and suggest fixes

## Examples

- `/api-test GET /users/123/stats` → tests the user stats endpoint on prod
- `/api-test POST /workouts/123/upload [{"distance": 1.6}]` → posts workout data
- `/api-test local GET /status` → tests health check on localhost
