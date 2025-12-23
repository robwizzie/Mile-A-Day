# Mile-A-Day API

## Endpoints

-   **[Authentication](#authentication)**
    -   **[Sign In](#sign-in)**
    -   **[Refresh Token](#refresh-token)**
    -   **[Logout](#logout)**
    -   **[Logout All](#logout-all)**
-   **[Users](#users)**
    -   **[Get User](#get-user)**
    -   **[Search For User](#search-for-user)**
    -   **[Update User](#update-user)**
    -   **[Delete User](#delete-user)**
-   **[Friendships](#friendships)**
    -   **[Get Friends](#get-friends)**
    -   **[Get Friend Requests](#get-friend-requests)**
    -   **[Get Sent Requests](#get-sent-requests)**
    -   **[Send Friend Request](#send-friend-request)**
    -   **[Accept Friend Request](#accept-friend-request)**
    -   **[Ignore Friend Request](#ignore-friend-request)**
    -   **[Decline Friend Request](#decline-friend-request)**
    -   **[Remove Friend](#remove-friend)**
-   **[Workouts](#workouts)**
    -   **[Upload Workouts](#upload-workouts)**
    -   **[Get Streak](#get-streak)**
    -   **[Get Recent Workouts](#get-recent-workouts)**
    -   **[Get User Stats](#get-user-stats)**
-   **[Competitions](#competitions)**
    -   **[Create Competition](#create-competition)**
    -   **[Get All Competitions](#get-all-competitions)**
    -   **[Get Competition](#get-competition)**
    -   **[Update Competition](#update-competition)**
    -   **[Get Competition Invites](#get-competition-invites)**
    -   **[Invite Users to Competition](#invite-users-to-competition)**
    -   **[Accept Competition Invite](#accept-competition-invite)**
    -   **[Decline Competition Invite](#decline-competition-invite)**

## API Domain

Access MAD endpoints from `https://mad.mindgoblin.tech/`

<br/>

---

## Error Response

Whenever an error occurs, the API will respond with an error code as well as an object containing an `error` key with more details about what went wrong.

### Example Error

```
{
    "error": "User not found"
}
```

<br/>

---

<a name="authentication"></a>

## 🔐 Authentication

Most endpoints require authentication via a JWT Bearer token in the Authorization header:

```
Authorization: Bearer <your_access_token>
```

### Token Types

The API uses two types of tokens:

- **Access Token**: Long-lived JWT (30 days) used for API requests
- **Refresh Token**: Long-lived opaque token used to obtain new access tokens

### Token Security Features

- **Automatic Rotation**: Refresh tokens are rotated on each use (old token revoked, new issued)
- **Token Reuse Detection**: If a revoked refresh token is used, entire token family is revoked
- **Session Tracking**: Tokens stored with user agent, IP address, and device info for security monitoring
- **Immediate Revocation**: Tokens can be instantly revoked (logout, security breach)

If you attempt to access a resource you don't own, you'll receive a 403 error:

```json
{
	"error": "Access denied - can only access your own data"
}
```

### Development Testing

For development and staging environments, you can generate test tokens without Apple Sign-In:

**POST** `/dev/test-token`

#### Parameters

| Name   | Type   | Description                       | Required |
| :----- | :----- | :-------------------------------- | :------: |
| userId | String | The user ID to generate token for |    ✅    |

#### Example

```bash
curl --location 'http://localhost:3000/dev/test-token' \
--header 'Content-Type: application/json' \
--data '{
    "userId": "peter"
}'
```

#### Response

```json
{
	"token": "eyJhbGciOiJIUzI1NiJ9...",
	"userId": "peter",
	"expiresIn": "30d",
	"expiresAt": 1740326400000,
	"environment": "development"
}
```

**Note**: `expiresAt` is a Unix timestamp in milliseconds indicating when the token expires.

**Note:** This endpoint is only available in development and staging environments. It will return a 403 error in production.

<a name="sign-in"></a>

### Sign In

**POST** `/auth/signin`

Authenticates users via Apple Sign-In and returns both access and refresh tokens.

#### Parameters

| Name               | Type   | Description                               | Required |
| :----------------- | :----- | :---------------------------------------- | :------: |
| user_id            | String | The Apple user identifier                 |    ✅    |
| identity_token     | String | The JWT identity token from Apple Sign-In |    ✅    |
| authorization_code | String | The authorization code from Apple Sign-In |    ✅    |
| email              | String | User's email (fallback if not in token)   |    ✖️    |
| device_info        | Object | Device information for security tracking  |    ✖️    |

#### Device Info Object (Optional)

| Name       | Type   | Description                     |
| :--------- | :----- | :------------------------------ |
| model      | String | Device model (e.g., "iPhone15") |
| os_version | String | OS version (e.g., "iOS 17.2")   |

#### Examples

<details>
<summary>Click to expand</summary>

> **POST** `/auth/signin`
>
> ##### Example Body
>
> ```
> {
>     "user_id": "000123.abc123def456.0000",
>     "identity_token": "eyJhbGciOiJSUzI1NiIsImtpZCI6IldRYUFiOGh...",
>     "authorization_code": "c12345abcdef67890...",
>     "email": "user@example.com",
>     "device_info": {
>         "model": "iPhone15,2",
>         "os_version": "iOS 17.2"
>     }
> }
> ```
>
> ##### Example Response
>
> ```
> {
>     "user": {
>         "user_id": "peter",
>         "username": null,
>         "email": "user@example.com",
>         "first_name": null,
>         "last_name": null,
>         "bio": null,
>         "profile_image_url": null,
>         "apple_id": "000123.abc123def456.0000",
>         "auth_provider": "apple"
>     },
>     "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
>     "refreshToken": "rt_a3f2b1c4d5e6f7a8b9c0d1e2f3a4b5c6_abc123",
>     "expiresIn": "30d",
>     "expiresAt": 1740326400000
> }
> ```
>
> **Note**: `expiresAt` is a Unix timestamp in milliseconds indicating when the access token expires.
>
> ##### Full cURL Example
>
> ```
> curl --location 'https://mad.mindgoblin.tech/auth/signin' \
> --header 'Content-Type: application/json' \
> --data '{
>     "user_id": "000123.abc123def456.0000",
>     "identity_token": "eyJhbGciOiJSUzI1NiIsImtpZCI6IldRYUFiOGh...",
>     "authorization_code": "c12345abcdef67890...",
>     "email": "user@example.com"
> }'
> ```

</details>

<br/>

<a name="refresh-token"></a>

### Refresh Token

**POST** `/auth/refresh`

Exchanges a refresh token for a new access token and refresh token pair. The old refresh token is automatically revoked.

#### Parameters

| Name         | Type   | Description                   | Required |
| :----------- | :----- | :---------------------------- | :------: |
| refreshToken | String | The current valid refresh token |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **POST** `/auth/refresh`
>
> ##### Example Body
>
> ```json
> {
>     "refreshToken": "rt_a3f2b1c4d5e6f7a8b9c0d1e2f3a4b5c6_abc123"
> }
> ```
>
> ##### Example Response
>
> ```json
> {
>     "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
>     "refreshToken": "rt_b4g3c2d5e6f7a8b9c0d1e2f3a4b5c7d8_def456",
>     "expiresIn": "30d",
>     "expiresAt": 1740326400000
> }
> ```
>
> **Note**: `expiresAt` is a Unix timestamp in milliseconds indicating when the access token expires.
>
> ##### Full cURL Example
>
> ```bash
> curl --location 'https://mad.mindgoblin.tech/auth/refresh' \
> --header 'Content-Type: application/json' \
> --data '{
>     "refreshToken": "rt_a3f2b1c4d5e6f7a8b9c0d1e2f3a4b5c6_abc123"
> }'
> ```

</details>

#### Error Responses

- **403 Forbidden**: Refresh token is invalid, expired, or has been revoked
- **Token Reuse Detected**: If a revoked refresh token is used, all tokens in the family are revoked

<br/>

<a name="logout"></a>

### Logout

**POST** `/auth/logout`

Revokes a specific refresh token (single session logout).

#### Parameters

| Name         | Type   | Description                       | Required |
| :----------- | :----- | :-------------------------------- | :------: |
| refreshToken | String | The refresh token to revoke       |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **POST** `/auth/logout`
>
> ##### Example Body
>
> ```json
> {
>     "refreshToken": "rt_a3f2b1c4d5e6f7a8b9c0d1e2f3a4b5c6_abc123"
> }
> ```
>
> ##### Example Response
>
> ```json
> {
>     "success": true,
>     "message": "Logged out successfully"
> }
> ```
>
> ##### Full cURL Example
>
> ```bash
> curl --location 'https://mad.mindgoblin.tech/auth/logout' \
> --header 'Content-Type: application/json' \
> --data '{
>     "refreshToken": "rt_a3f2b1c4d5e6f7a8b9c0d1e2f3a4b5c6_abc123"
> }'
> ```

</details>

<br/>

<a name="logout-all"></a>

### Logout All

**POST** `/auth/logout-all`

Revokes all refresh tokens for the authenticated user (all sessions logout).

**Requires Authentication**: Yes (Bearer token in Authorization header)

#### Examples

<details>
<summary>Click to expand</summary>

> **POST** `/auth/logout-all`
>
> ##### Headers
>
> ```
> Authorization: Bearer <access_token>
> ```
>
> ##### Example Response
>
> ```json
> {
>     "success": true,
>     "message": "All sessions revoked",
>     "revokedCount": 3
> }
> ```
>
> ##### Full cURL Example
>
> ```bash
> curl --location 'https://mad.mindgoblin.tech/auth/logout-all' \
> --header 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...' \
> --header 'Content-Type: application/json'
> ```

</details>

<br/><br/>

---

<a name="users"></a>

## 👤 Users

<a name="get-user"></a>

### Get User

**GET** `/users/{userId}`

#### Parameters

| Name   | Type           | Description                 | Required |
| :----- | :------------- | :-------------------------- | :------: |
| userId | Path Parameter | The ID of the user to fetch |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **GET** `/users/peter`
>
> ##### Example Response
>
> ```
> {
>    "user_id": "peter",
>    "username": "PJ",
>    "email": "peter@mindgoblin.tech",
>    "first_name": "Peter",
>    "last_name": "Johnson"
> }
> ```
>
> ##### Full cURL Example
>
> ```
> curl --location 'https://mad.mindgoblin.tech/users/peter'
> ```

</details>

<br/><br/>

<a name="search-for-user"></a>

### Search For Users

**GET** `/users/search`

Searches for users by partial username or email match. Returns up to 50 results.

#### Parameters

| Name  | Type            | Description                                                                | Required |
| :---- | :-------------- | :------------------------------------------------------------------------- | :------: |
| query | Query Parameter | Search term to match against username or email (case-insensitive, partial) |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **GET** `/users/search?query=peter`
>
> ##### Example Response
>
> ```
> [
>     {
>         "user_id": "peter",
>         "username": "PJ",
>         "email": "peter@mindgoblin.tech",
>         "first_name": "Peter",
>         "last_name": "Johnson"
>     },
>     {
>         "user_id": "peter2",
>         "username": "PeterParker",
>         "email": "spiderman@example.com",
>         "first_name": "Peter",
>         "last_name": "Parker"
>     }
> ]
> ```
>
> ##### Full cURL Example
>
> ```
> curl --location 'https://mad.mindgoblin.tech/users/search?query=peter'
> ```

</details>

<br/><br/>

<a name="update-user"></a>

### Update User

**PATCH** `/users/{userId}`

#### Parameters

| Name       | Type   | Description                                  | Required |
| :--------- | :----- | :------------------------------------------- | :------: |
| username   | String | The username for the user you are creating   |    ✖️    |
| first_name | String | The first name for the user you are creating |    ✖️    |
| last_name  | String | The last name for the user you are creating  |    ✖️    |

_**Note: fields that are not included in the response will not be updated**_

#### Examples

<details>
<summary>Click to expand</summary>

> **PATCH** `/users/peter`
>
> ##### Example Body
>
> ```
> {
>     "first_name": "PJ",
> }
> ```
>
> ##### Example Response
>
> ```
> {
>     "user_id": "peter",
>     "username": "PJ",
>     "email": "peter@mindgoblin.tech",
>     "first_name": "PJ",
>     "last_name": "Johnson"
> }
> ```
>
> ##### Full cURL Example
>
> ```
> curl --location --request PATCH 'https://mad.mindgoblin.tech/users/peter' \
> --header 'Content-Type: application/json' \
> --header 'Authorization: Bearer <your_jwt_token>' \
> --data '{
>     "first_name": "PJ"
> }'
> ```

</details>

<br/><br/>

<a name="delete-user"></a>

### Delete User

**DELETE** `/users/{userId}`

#### Parameters

| Name   | Type           | Description                  | Required |
| :----- | :------------- | :--------------------------- | :------: |
| userId | Path Parameter | The ID of the user to delete |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **DELETE** `/users/peter`
>
> ##### Example Response
>
> ```
> {
>     "message": "Successfully deleted user peter",
> }
> ```
>
> ##### Full cURL Example
>
> ```
> curl --location --request DELETE 'https://mad.mindgoblin.tech/users/peter' \
> --header 'Authorization: Bearer <your_jwt_token>'
> ```

</details>

---

<a name="friendships"></a>

## 👥 Friendships

<a name="get-friends"></a>

### Get Friends

**GET** `/friendships/{userId}`

Returns all accepted friends for a user.

#### Parameters

| Name   | Type           | Description                           | Required |
| :----- | :------------- | :------------------------------------ | :------: |
| userId | Path Parameter | The ID of the user to get friends for |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **GET** `/friendships/peter`
>
> ##### Example Response
>
> ```
> [
>     {
>         "user_id": "john",
>         "username": "JohnDoe",
>         "email": "john@example.com",
>         "first_name": "John",
>         "last_name": "Doe"
>     }
> ]
> ```
>
> ##### Full cURL Example
>
> ```
> curl --location 'https://mad.mindgoblin.tech/friendships/peter' \
> --header 'Authorization: Bearer <your_jwt_token>'
> ```

</details>

<br/><br/>

<a name="get-friend-requests"></a>

### Get Friend Requests

**GET** `/friendships/requests/{userId}`

Returns all pending friend requests received by a user.

#### Parameters

| Name   | Type           | Description                                   | Required |
| :----- | :------------- | :-------------------------------------------- | :------: |
| userId | Path Parameter | The ID of the user to get friend requests for |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **GET** `/friendships/requests/peter`
>
> ##### Example Response
>
> ```
> [
>     {
>         "user_id": "jane",
>         "username": "JaneDoe",
>         "email": "jane@example.com",
>         "first_name": "Jane",
>         "last_name": "Doe"
>     }
> ]
> ```
>
> ##### Full cURL Example
>
> ```
> curl --location 'https://mad.mindgoblin.tech/friendships/requests/peter' \
> --header 'Authorization: Bearer <your_jwt_token>'
> ```

</details>

<br/><br/>

<a name="get-sent-requests"></a>

### Get Sent Requests

**GET** `/friendships/sent-requests/{userId}`

Returns all friend requests sent by a user that are still pending.

#### Parameters

| Name   | Type           | Description                                 | Required |
| :----- | :------------- | :------------------------------------------ | :------: |
| userId | Path Parameter | The ID of the user to get sent requests for |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **GET** `/friendships/sent-requests/peter`
>
> ##### Example Response
>
> ```
> [
>     {
>         "user_id": "bob",
>         "username": "BobSmith",
>         "email": "bob@example.com",
>         "first_name": "Bob",
>         "last_name": "Smith"
>     }
> ]
> ```
>
> ##### Full cURL Example
>
> ```
> curl --location 'https://mad.mindgoblin.tech/friendships/sent-requests/peter' \
> --header 'Authorization: Bearer <your_jwt_token>'
> ```

</details>

<br/><br/>

<a name="send-friend-request"></a>

### Send Friend Request

**POST** `/friendships/request`

Sends a friend request from one user to another.

#### Parameters

| Name     | Type   | Description                              | Required |
| :------- | :----- | :--------------------------------------- | :------: |
| fromUser | String | The ID of the user sending the request   |    ✅    |
| toUser   | String | The ID of the user receiving the request |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **POST** `/friendships/request`
>
> ##### Example Body
>
> ```
> {
>     "fromUser": "peter",
>     "toUser": "john"
> }
> ```
>
> ##### Example Response
>
> ```
> {
>     "message": "Friend request sent successfully"
> }
> ```
>
> ##### Full cURL Example
>
> ```
> curl --location 'https://mad.mindgoblin.tech/friendships/request' \
> --header 'Content-Type: application/json' \
> --header 'Authorization: Bearer <your_jwt_token>' \
> --data '{
>     "fromUser": "peter",
>     "toUser": "john"
> }'
> ```

</details>

<br/><br/>

<a name="accept-friend-request"></a>

### Accept Friend Request

**PATCH** `/friendships/accept`

Accepts a pending friend request.

#### Parameters

| Name     | Type   | Description                              | Required |
| :------- | :----- | :--------------------------------------- | :------: |
| fromUser | String | The ID of the user who sent the request  |    ✅    |
| toUser   | String | The ID of the user accepting the request |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **PATCH** `/friendships/accept`
>
> ##### Example Body
>
> ```
> {
>     "fromUser": "john",
>     "toUser": "peter"
> }
> ```
>
> ##### Example Response
>
> ```
> {
>     "message": "Friend request accepted"
> }
> ```
>
> ##### Full cURL Example
>
> ```
> curl --location --request PATCH 'https://mad.mindgoblin.tech/friendships/accept' \
> --header 'Content-Type: application/json' \
> --header 'Authorization: Bearer <your_jwt_token>' \
> --data '{
>     "fromUser": "john",
>     "toUser": "peter"
> }'
> ```

</details>

<br/><br/>

<a name="ignore-friend-request"></a>

### Ignore Friend Request

**PATCH** `/friendships/ignore`

Ignores a pending friend request without declining it.

#### Parameters

| Name     | Type   | Description                             | Required |
| :------- | :----- | :-------------------------------------- | :------: |
| fromUser | String | The ID of the user who sent the request |    ✅    |
| toUser   | String | The ID of the user ignoring the request |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **PATCH** `/friendships/ignore`
>
> ##### Example Body
>
> ```
> {
>     "fromUser": "john",
>     "toUser": "peter"
> }
> ```
>
> ##### Example Response
>
> ```
> {
>     "message": "Friend request ignored"
> }
> ```
>
> ##### Full cURL Example
>
> ```
> curl --location --request PATCH 'https://mad.mindgoblin.tech/friendships/ignore' \
> --header 'Content-Type: application/json' \
> --header 'Authorization: Bearer <your_jwt_token>' \
> --data '{
>     "fromUser": "john",
>     "toUser": "peter"
> }'
> ```

</details>

<br/><br/>

<a name="decline-friend-request"></a>

### Decline Friend Request

**DELETE** `/friendships/decline`

Declines a pending friend request.

#### Parameters

| Name     | Type   | Description                              | Required |
| :------- | :----- | :--------------------------------------- | :------: |
| fromUser | String | The ID of the user who sent the request  |    ✅    |
| toUser   | String | The ID of the user declining the request |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **DELETE** `/friendships/decline`
>
> ##### Example Body
>
> ```
> {
>     "fromUser": "john",
>     "toUser": "peter"
> }
> ```
>
> ##### Example Response
>
> ```
> {
>     "message": "Friend request declined"
> }
> ```
>
> ##### Full cURL Example
>
> ```
> curl --location --request DELETE 'https://mad.mindgoblin.tech/friendships/decline' \
> --header 'Content-Type: application/json' \
> --header 'Authorization: Bearer <your_jwt_token>' \
> --data '{
>     "fromUser": "john",
>     "toUser": "peter"
> }'
> ```

</details>

<br/><br/>

<a name="remove-friend"></a>

### Remove Friend

**DELETE** `/friendships/remove`

Removes an existing friendship.

#### Parameters

| Name     | Type   | Description                                | Required |
| :------- | :----- | :----------------------------------------- | :------: |
| fromUser | String | The ID of one user in the friendship       |    ✅    |
| toUser   | String | The ID of the other user in the friendship |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **DELETE** `/friendships/remove`
>
> ##### Example Body
>
> ```
> {
>     "fromUser": "peter",
>     "toUser": "john"
> }
> ```
>
> ##### Example Response
>
> ```
> {
>     "message": "Friendship removed"
> }
> ```
>
> ##### Full cURL Example
>
> ```
> curl --location --request DELETE 'https://mad.mindgoblin.tech/friendships/remove' \
> --header 'Content-Type: application/json' \
> --header 'Authorization: Bearer <your_jwt_token>' \
> --data '{
>     "fromUser": "peter",
>     "toUser": "john"
> }'
> ```

</details>

<br/><br/>

---

<a name="workouts"></a>

## 🏃 Workouts

<a name="upload-workouts"></a>

### Upload Workouts

**POST** `/workouts/{userId}/upload`

Uploads one or more workout records for a user. Each workout includes distance, duration, calories, split times, and other metadata. The endpoint uses an upsert operation, updating existing workouts if they already exist.

#### Parameters

| Name   | Type           | Description                            | Required |
| :----- | :------------- | :------------------------------------- | :------: |
| userId | Path Parameter | The ID of the user uploading workouts  |    ✅    |

#### Request Body

An array of workout objects with the following structure:

| Field          | Type     | Description                                    | Required |
| :------------- | :------- | :--------------------------------------------- | :------: |
| workoutId      | String   | Unique identifier for the workout              |    ✅    |
| distance       | Number   | Distance in miles                              |    ✅    |
| localDate      | String   | Date of workout in local timezone (YYYY-MM-DD) |    ✅    |
| timezoneOffset | Number   | Timezone offset in minutes                     |    ✅    |
| workoutType    | String   | Type of workout (e.g., "running", "walking")   |    ✅    |
| deviceEndDate  | String   | End timestamp from device                      |    ✅    |
| calories       | Number   | Calories burned                                |    ✅    |
| totalDuration  | Number   | Total duration in seconds                      |    ✅    |
| splitTimes     | Number[] | Array of split times in seconds                |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **POST** `/workouts/peter/upload`
>
> ##### Example Body
>
> ```json
> [
>     {
>         "workoutId": "ABC123",
>         "distance": 1.25,
>         "localDate": "2025-10-26",
>         "timezoneOffset": -240,
>         "workoutType": "running",
>         "deviceEndDate": "2025-10-26T08:30:00Z",
>         "calories": 150,
>         "totalDuration": 720,
>         "splitTimes": [360, 360]
>     }
> ]
> ```
>
> ##### Example Response
>
> ```json
> {
>     "message": "Successfully uploaded workouts."
> }
> ```
>
> ##### Full cURL Example
>
> ```bash
> curl --location 'https://mad.mindgoblin.tech/workouts/peter/upload' \
> --header 'Content-Type: application/json' \
> --header 'Authorization: Bearer <your_jwt_token>' \
> --data '[
>     {
>         "workoutId": "ABC123",
>         "distance": 1.25,
>         "localDate": "2025-10-26",
>         "timezoneOffset": -240,
>         "workoutType": "running",
>         "deviceEndDate": "2025-10-26T08:30:00Z",
>         "calories": 150,
>         "totalDuration": 720,
>         "splitTimes": [360, 360]
>     }
> ]'
> ```

</details>

<br/><br/>

<a name="get-streak"></a>

### Get Streak

**GET** `/workouts/{userId}/streak`

Calculates the current workout streak for a user. A streak is the number of consecutive days (starting from the most recent day) where the user completed at least 0.95 miles of workouts.

#### Parameters

| Name   | Type           | Description                            | Required |
| :----- | :------------- | :------------------------------------- | :------: |
| userId | Path Parameter | The ID of the user to get streak for   |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **GET** `/workouts/peter/streak`
>
> ##### Example Response
>
> ```json
> {
>     "streak": 42
> }
> ```
>
> ##### Full cURL Example
>
> ```bash
> curl --location 'https://mad.mindgoblin.tech/workouts/peter/streak' \
> --header 'Authorization: Bearer <your_jwt_token>'
> ```

</details>

<br/><br/>

<a name="get-recent-workouts"></a>

### Get Recent Workouts

**GET** `/workouts/{userId}/recent`

Retrieves the most recent workouts for a user, ordered by device end date (newest first). By default, returns the 10 most recent workouts, but can be customized with the limit query parameter.

#### Parameters

| Name   | Type            | Description                                      | Required |
| :----- | :-------------- | :----------------------------------------------- | :------: |
| userId | Path Parameter  | The ID of the user to get recent workouts for    |    ✅    |
| limit  | Query Parameter | Maximum number of workouts to return (default: 10)|    ✖️    |

#### Examples

<details>
<summary>Click to expand</summary>

> **GET** `/workouts/peter/recent?limit=5`
>
> ##### Example Response
>
> ```json
> [
>     {
>         "user_id": "peter",
>         "workout_id": "ABC123",
>         "distance": 1.25,
>         "local_date": "2025-10-26",
>         "date": "2025-10-26T08:30:00Z",
>         "timezone_offset": -240,
>         "workout_type": "running",
>         "device_end_date": "2025-10-26T08:30:00Z",
>         "calories": 150,
>         "total_duration": 720
>     },
>     {
>         "user_id": "peter",
>         "workout_id": "DEF456",
>         "distance": 1.0,
>         "local_date": "2025-10-25",
>         "date": "2025-10-25T07:15:00Z",
>         "timezone_offset": -240,
>         "workout_type": "walking",
>         "device_end_date": "2025-10-25T07:15:00Z",
>         "calories": 100,
>         "total_duration": 900
>     }
> ]
> ```
>
> ##### Full cURL Example
>
> ```bash
> curl --location 'https://mad.mindgoblin.tech/workouts/peter/recent?limit=5' \
> --header 'Authorization: Bearer <your_jwt_token>'
> ```

</details>

<br/><br/>

<a name="get-user-stats"></a>

### Get User Stats

**GET** `/workouts/{userId}/stats`

Retrieves comprehensive workout statistics for a user, including their current streak, total miles, best performance metrics, and recent workouts. Optionally, you can limit statistics to only the current streak period.

#### Parameters

| Name           | Type            | Description                                                          | Required |
| :------------- | :-------------- | :------------------------------------------------------------------- | :------: |
| userId         | Path Parameter  | The ID of the user to get stats for                                  |    ✅    |
| current_streak | Query Parameter | If "true", limits stats to current streak period only (default: false)|    ✖️    |

#### Response Fields

| Field            | Type     | Description                                              |
| :--------------- | :------- | :------------------------------------------------------- |
| streak           | Number   | Current consecutive days with at least 0.95 miles        |
| start_date       | String   | Date when the current streak started (YYYY-MM-DD)        |
| total_miles      | Number   | Total distance across all workouts (or current streak)   |
| best_miles_day   | Number   | Most miles completed in a single day                     |
| best_split_time  | Number   | Fastest mile split time in seconds                       |
| recent_workouts  | Array    | Array of the 10 most recent workout objects              |

#### Examples

<details>
<summary>Click to expand</summary>

> **GET** `/workouts/peter/stats`
>
> ##### Example Response (All-Time Stats)
>
> ```json
> {
>     "streak": 42,
>     "start_date": "2025-09-15",
>     "total_miles": 125.5,
>     "best_miles_day": 5.2,
>     "best_split_time": 420,
>     "recent_workouts": [
>         {
>             "user_id": "peter",
>             "workout_id": "ABC123",
>             "distance": 1.25,
>             "local_date": "2025-10-26",
>             "date": "2025-10-26T08:30:00Z",
>             "timezone_offset": -240,
>             "workout_type": "running",
>             "device_end_date": "2025-10-26T08:30:00Z",
>             "calories": 150,
>             "total_duration": 720
>         }
>     ]
> }
> ```
>
> **GET** `/workouts/peter/stats?current_streak=true`
>
> ##### Example Response (Current Streak Stats Only)
>
> ```json
> {
>     "streak": 42,
>     "start_date": "2025-09-15",
>     "total_miles": 52.3,
>     "best_miles_day": 3.5,
>     "best_split_time": 450,
>     "recent_workouts": [
>         {
>             "user_id": "peter",
>             "workout_id": "ABC123",
>             "distance": 1.25,
>             "local_date": "2025-10-26",
>             "date": "2025-10-26T08:30:00Z",
>             "timezone_offset": -240,
>             "workout_type": "running",
>             "device_end_date": "2025-10-26T08:30:00Z",
>             "calories": 150,
>             "total_duration": 720
>         }
>     ]
> }
> ```
>
> ##### Full cURL Example
>
> ```bash
> # Get all-time stats
> curl --location 'https://mad.mindgoblin.tech/workouts/peter/stats' \
> --header 'Authorization: Bearer <your_jwt_token>'
>
> # Get current streak stats only
> curl --location 'https://mad.mindgoblin.tech/workouts/peter/stats?current_streak=true' \
> --header 'Authorization: Bearer <your_jwt_token>'
> ```

</details>

<br/><br/>

---

<a name="competitions"></a>

## 🏆 Competitions

<a name="create-competition"></a>

### Create Competition

**POST** `/competitions`

Creates a new competition. The authenticated user becomes the owner and is automatically added as an accepted participant.

#### Request Body

| Field            | Type     | Description                                                    | Required |
| :--------------- | :------- | :------------------------------------------------------------- | :------: |
| competition_name | String   | Name of the competition                                        |    ✅    |
| type             | String   | Competition type: "streaks", "apex", "clash", "targets", "race"|    ✅    |
| start_date       | String   | Start date (YYYY-MM-DD)                                        |    ✖️    |
| end_date         | String   | End date (YYYY-MM-DD)                                          |    ✖️    |
| workouts         | String[] | Allowed workout types: ["run", "walk"]                         |    ✖️    |
| options          | Object   | Competition-specific options                                   |    ✖️    |

#### Options Object

| Field    | Type   | Description                              | Required |
| :------- | :----- | :--------------------------------------- | :------: |
| goal     | Number | Goal value for the competition           |    ✅    |
| unit     | String | Unit of measurement: "miles" or "steps"  |    ✅    |
| first_to | Number | Number of wins needed (for some types)   |    ✅    |
| history  | Boolean| Whether to include historical data       |    ✖️    |
| interval | String | Time interval: "day", "week", or "month" |    ✖️    |

#### Examples

<details>
<summary>Click to expand</summary>

> **POST** `/competitions`
>
> ##### Example Body
>
> ```json
> {
>     "competition_name": "Summer Running Challenge",
>     "type": "streaks",
>     "start_date": "2025-06-01",
>     "end_date": "2025-08-31",
>     "workouts": ["run"],
>     "options": {
>         "goal": 1,
>         "unit": "miles",
>         "first_to": 5,
>         "history": false,
>         "interval": "day"
>     }
> }
> ```
>
> ##### Example Response
>
> ```json
> {
>     "competition_id": "comp_abc123"
> }
> ```
>
> ##### Full cURL Example
>
> ```bash
> curl --location 'https://mad.mindgoblin.tech/competitions' \
> --header 'Content-Type: application/json' \
> --header 'Authorization: Bearer <your_jwt_token>' \
> --data '{
>     "competition_name": "Summer Running Challenge",
>     "type": "streaks",
>     "start_date": "2025-06-01",
>     "end_date": "2025-08-31",
>     "workouts": ["run"],
>     "options": {
>         "goal": 1,
>         "unit": "miles",
>         "first_to": 5,
>         "history": false,
>         "interval": "day"
>     }
> }'
> ```

</details>

<br/><br/>

<a name="get-all-competitions"></a>

### Get All Competitions

**GET** `/competitions`

Retrieves all competitions for the authenticated user with pagination and optional status filtering.

#### Query Parameters

| Name     | Type            | Description                                      | Required |
| :------- | :-------------- | :----------------------------------------------- | :------: |
| page     | Query Parameter | Page number (default: 1)                         |    ✖️    |
| pageSize | Query Parameter | Number of results per page (default: 25)         |    ✖️    |
| status   | Query Parameter | Filter by status (e.g., "on_your_mark", "active")|    ✖️    |

#### Examples

<details>
<summary>Click to expand</summary>

> **GET** `/competitions?page=1&pageSize=10&status=active`
>
> ##### Example Response
>
> ```json
> {
>     "competitions": [
>         {
>             "competition_id": "comp_abc123",
>             "competition_name": "Summer Running Challenge",
>             "start_date": "2025-06-01",
>             "end_date": "2025-08-31",
>             "workouts": ["run"],
>             "type": "streaks",
>             "options": {
>                 "goal": 1,
>                 "unit": "miles",
>                 "first_to": 5,
>                 "history": false,
>                 "interval": "day"
>             },
>             "owner": "peter",
>             "users": [
>                 {
>                     "competition_id": "comp_abc123",
>                     "user_id": "peter",
>                     "invite_status": "accepted"
>                 }
>             ]
>         }
>     ]
> }
> ```
>
> ##### Full cURL Example
>
> ```bash
> curl --location 'https://mad.mindgoblin.tech/competitions?page=1&pageSize=10' \
> --header 'Authorization: Bearer <your_jwt_token>'
> ```

</details>

<br/><br/>

<a name="get-competition"></a>

### Get Competition

**GET** `/competitions/{competitionId}`

Retrieves details for a specific competition.

#### Parameters

| Name          | Type           | Description                           | Required |
| :------------ | :------------- | :------------------------------------ | :------: |
| competitionId | Path Parameter | The ID of the competition to retrieve |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **GET** `/competitions/comp_abc123`
>
> ##### Example Response
>
> ```json
> {
>     "competition": {
>         "competition_id": "comp_abc123",
>         "competition_name": "Summer Running Challenge",
>         "start_date": "2025-06-01",
>         "end_date": "2025-08-31",
>         "workouts": ["run"],
>         "type": "streaks",
>         "options": {
>             "goal": 1,
>             "unit": "miles",
>             "first_to": 5,
>             "history": false,
>             "interval": "day"
>         },
>         "owner": "peter",
>         "users": [
>             {
>                 "competition_id": "comp_abc123",
>                 "user_id": "peter",
>                 "invite_status": "accepted"
>             },
>             {
>                 "competition_id": "comp_abc123",
>                 "user_id": "john",
>                 "invite_status": "pending"
>             }
>         ]
>     }
> }
> ```
>
> ##### Full cURL Example
>
> ```bash
> curl --location 'https://mad.mindgoblin.tech/competitions/comp_abc123' \
> --header 'Authorization: Bearer <your_jwt_token>'
> ```

</details>

<br/><br/>

<a name="update-competition"></a>

### Update Competition

**PATCH** `/competitions/{competitionId}`

Updates a competition. Only fields included in the request will be updated. For options, the new values are merged with existing options, so you only need to include the option fields you want to change. Only the competition owner can update it.

#### Parameters

| Name          | Type           | Description               | Required |
| :------------ | :------------- | :------------------------ | :------: |
| competitionId | Path Parameter | The ID of the competition |    ✅    |

#### Request Body (All Optional)

| Field            | Type     | Description                                                    | Required |
| :--------------- | :------- | :------------------------------------------------------------- | :------: |
| competition_name | String   | Name of the competition                                        |    ✖️    |
| type             | String   | Competition type: "streaks", "apex", "clash", "targets", "race"|    ✖️    |
| start_date       | String   | Start date (YYYY-MM-DD)                                        |    ✖️    |
| end_date         | String   | End date (YYYY-MM-DD)                                          |    ✖️    |
| workouts         | String[] | Allowed workout types: ["run", "walk"]                         |    ✖️    |
| options          | Object   | Competition options to merge with existing options            |    ✖️    |

#### Options Object (Partial Update)

Any of the following fields can be included. Only specified fields will be updated:

| Field    | Type    | Description                              |
| :------- | :------ | :--------------------------------------- |
| goal     | Number  | Goal value for the competition           |
| unit     | String  | Unit of measurement: "miles" or "steps"  |
| first_to | Number  | Number of wins needed (for some types)   |
| history  | Boolean | Whether to include historical data       |
| interval | String  | Time interval: "day", "week", or "month" |

#### Examples

<details>
<summary>Click to expand</summary>

> **PATCH** `/competitions/comp_abc123`
>
> ##### Example Body (Update Name and Goal Only)
>
> ```json
> {
>     "competition_name": "Updated Summer Challenge",
>     "options": {
>         "goal": 2
>     }
> }
> ```
>
> ##### Example Response
>
> ```json
> {
>     "competition": {
>         "competition_id": "comp_abc123",
>         "competition_name": "Updated Summer Challenge",
>         "start_date": "2025-06-01",
>         "end_date": "2025-08-31",
>         "workouts": ["run"],
>         "type": "streaks",
>         "options": {
>             "goal": 2,
>             "unit": "miles",
>             "first_to": 5,
>             "history": false,
>             "interval": "day"
>         },
>         "owner": "peter",
>         "users": [
>             {
>                 "competition_id": "comp_abc123",
>                 "user_id": "peter",
>                 "invite_status": "accepted"
>             }
>         ]
>     }
> }
> ```
>
> ##### Full cURL Example
>
> ```bash
> curl --location --request PATCH 'https://mad.mindgoblin.tech/competitions/comp_abc123' \
> --header 'Content-Type: application/json' \
> --header 'Authorization: Bearer <your_jwt_token>' \
> --data '{
>     "competition_name": "Updated Summer Challenge",
>     "options": {
>         "goal": 2
>     }
> }'
> ```

</details>

<br/><br/>

<a name="get-competition-invites"></a>

### Get Competition Invites

**GET** `/competitions/invites`

Retrieves all pending competition invites for the authenticated user.

#### Query Parameters

| Name | Type            | Description                  | Required |
| :--- | :-------------- | :--------------------------- | :------: |
| page | Query Parameter | Page number (default: 1)     |    ✖️    |

#### Examples

<details>
<summary>Click to expand</summary>

> **GET** `/competitions/invites?page=1`
>
> ##### Example Response
>
> ```json
> {
>     "competitionInvites": [
>         {
>             "competition_id": "comp_xyz789",
>             "competition_name": "Weekend Warriors",
>             "start_date": "2025-07-01",
>             "end_date": "2025-07-31",
>             "workouts": ["run", "walk"],
>             "type": "targets",
>             "options": {
>                 "goal": 50,
>                 "unit": "miles",
>                 "first_to": 1
>             },
>             "owner": "john",
>             "users": [
>                 {
>                     "competition_id": "comp_xyz789",
>                     "user_id": "peter",
>                     "invite_status": "pending"
>                 }
>             ]
>         }
>     ]
> }
> ```
>
> ##### Full cURL Example
>
> ```bash
> curl --location 'https://mad.mindgoblin.tech/competitions/invites' \
> --header 'Authorization: Bearer <your_jwt_token>'
> ```

</details>

<br/><br/>

<a name="invite-users-to-competition"></a>

### Invite Users to Competition

**POST** `/competitions/{competitionId}/invite`

Invites a user to join a competition. Only participants who have already accepted can invite others.

#### Parameters

| Name          | Type           | Description                      | Required |
| :------------ | :------------- | :------------------------------- | :------: |
| competitionId | Path Parameter | The ID of the competition        |    ✅    |

#### Request Body

| Field      | Type   | Description                       | Required |
| :--------- | :----- | :-------------------------------- | :------: |
| inviteUser | String | The user ID of the user to invite |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **POST** `/competitions/comp_abc123/invite`
>
> ##### Example Body
>
> ```json
> {
>     "inviteUser": "john"
> }
> ```
>
> ##### Example Response
>
> ```json
> {
>     "message": "Successfully invited user john to competition comp_abc123"
> }
> ```
>
> ##### Full cURL Example
>
> ```bash
> curl --location 'https://mad.mindgoblin.tech/competitions/comp_abc123/invite' \
> --header 'Content-Type: application/json' \
> --header 'Authorization: Bearer <your_jwt_token>' \
> --data '{
>     "inviteUser": "john"
> }'
> ```

</details>

<br/><br/>

<a name="accept-competition-invite"></a>

### Accept Competition Invite

**POST** `/competitions/{competitionId}/accept`

Accepts a pending competition invite for the authenticated user.

#### Parameters

| Name          | Type           | Description               | Required |
| :------------ | :------------- | :------------------------ | :------: |
| competitionId | Path Parameter | The ID of the competition |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **POST** `/competitions/comp_abc123/accept`
>
> ##### Example Response
>
> ```json
> {
>     "competition": {
>         "competition_id": "comp_abc123",
>         "competition_name": "Summer Running Challenge",
>         "start_date": "2025-06-01",
>         "end_date": "2025-08-31",
>         "workouts": ["run"],
>         "type": "streaks",
>         "options": {
>             "goal": 1,
>             "unit": "miles",
>             "first_to": 5
>         },
>         "owner": "peter",
>         "users": [
>             {
>                 "competition_id": "comp_abc123",
>                 "user_id": "peter",
>                 "invite_status": "accepted"
>             },
>             {
>                 "competition_id": "comp_abc123",
>                 "user_id": "john",
>                 "invite_status": "accepted"
>             }
>         ]
>     }
> }
> ```
>
> ##### Full cURL Example
>
> ```bash
> curl --location 'https://mad.mindgoblin.tech/competitions/comp_abc123/accept' \
> --header 'Authorization: Bearer <your_jwt_token>'
> ```

</details>

<br/><br/>

<a name="decline-competition-invite"></a>

### Decline Competition Invite

**POST** `/competitions/{competitionId}/decline`

Declines a pending competition invite for the authenticated user.

#### Parameters

| Name          | Type           | Description               | Required |
| :------------ | :------------- | :------------------------ | :------: |
| competitionId | Path Parameter | The ID of the competition |    ✅    |

#### Examples

<details>
<summary>Click to expand</summary>

> **POST** `/competitions/comp_abc123/decline`
>
> ##### Example Response
>
> ```json
> {
>     "competition": {
>         "competition_id": "comp_abc123",
>         "competition_name": "Summer Running Challenge",
>         "start_date": "2025-06-01",
>         "end_date": "2025-08-31",
>         "workouts": ["run"],
>         "type": "streaks",
>         "options": {
>             "goal": 1,
>             "unit": "miles",
>             "first_to": 5
>         },
>         "owner": "peter",
>         "users": [
>             {
>                 "competition_id": "comp_abc123",
>                 "user_id": "peter",
>                 "invite_status": "accepted"
>             },
>             {
>                 "competition_id": "comp_abc123",
>                 "user_id": "john",
>                 "invite_status": "declined"
>             }
>         ]
>     }
> }
> ```
>
> ##### Full cURL Example
>
> ```bash
> curl --location 'https://mad.mindgoblin.tech/competitions/comp_abc123/decline' \
> --header 'Authorization: Bearer <your_jwt_token>'
> ```

</details>

<br/><br/>

---
