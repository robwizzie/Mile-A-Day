# Mile-A-Day API

## Endpoints

-   **[Authentication](#authentication)**
    -   **[Sign In](#sign-in)**
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
Authorization: Bearer <your_jwt_token>
```

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
	"environment": "development"
}
```

**Note:** This endpoint is only available in development and staging environments. It will return a 403 error in production.

<a name="sign-in"></a>

### Sign In

**POST** `/auth/signin`

Authenticates users via Apple Sign-In and returns a JWT token for accessing protected endpoints.

#### Parameters

| Name               | Type   | Description                               | Required |
| :----------------- | :----- | :---------------------------------------- | :------: |
| user_id            | String | The Apple user identifier                 |    ✅    |
| identity_token     | String | The JWT identity token from Apple Sign-In |    ✅    |
| authorization_code | String | The authorization code from Apple Sign-In |    ✅    |
| email              | String | User's email (fallback if not in token)   |    ✖️    |

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
>     "email": "user@example.com"
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
>         "last_name": null
>     },
>     "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
> }
> ```
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

---
