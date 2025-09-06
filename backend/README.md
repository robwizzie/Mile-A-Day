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

All protected endpoints require authentication via a JWT Bearer token in the Authorization header:

```
Authorization: Bearer <your_jwt_token>
```

Obtain an authentication token using the Sign In endpoint below.

<a name="sign-in"></a>

### Sign In

**POST** `/auth/signin`

Authenticates users via Apple Sign-In and returns a JWT token for accessing protected endpoints.

#### Parameters

| Name               | Type   | Description                                    | Required |
| :----------------- | :----- | :--------------------------------------------- | :------: |
| user_id            | String | The Apple user identifier                      |    ✅    |
| identity_token     | String | The JWT identity token from Apple Sign-In     |    ✅    |
| authorization_code | String | The authorization code from Apple Sign-In     |    ✅    |
| email              | String | User's email (fallback if not in token)       |    ✖️    |

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

### Search For User

**GET** `/users/search`

#### Parameters

| Name     | Type            | Description                                                    | Required |
| :------- | :-------------- | :------------------------------------------------------------- | :------: |
| username | Query Parameter | The _<u>exact</u>_ username of the user to search for.         |    ✖️    |
| email    | Query Parameter | The _<u>exact</u>_ URL-encoded email of the user to search for |    ✖️    |

_**Note: one of email or username is required**_

#### Examples

<details>
<summary>Click to expand</summary>

> ##### With username
>
> **GET** `/users/search?username=peter`
>
> ##### With email
>
> **GET** `/users/search?email=peter%40mindgoblin.tech`
>
> ##### Example Response
>
> ```
> {
>     "user_id": "peter",
>     "username": "PJ",
>     "email": "peter@mindgoblin.tech",
>     "first_name": "Peter",
>     "last_name": "Johnson"
> }
> ```
>
> ##### Full cURL Example
>
> ```
> curl --location 'https://mad.mindgoblin.tech/users/search?username=peter'
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
> --data '    {
>         "first_name": "PJ"
>     }
> '
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
> curl --location --request DELETE 'https://mad.mindgoblin.tech/users/peter'
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

| Name   | Type           | Description                                    | Required |
| :----- | :------------- | :--------------------------------------------- | :------: |
| userId | Path Parameter | The ID of the user to get friends for          |    ✅    |

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

| Name   | Type           | Description                                           | Required |
| :----- | :------------- | :---------------------------------------------------- | :------: |
| userId | Path Parameter | The ID of the user to get friend requests for        |    ✅    |

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

| Name   | Type           | Description                                       | Required |
| :----- | :------------- | :------------------------------------------------ | :------: |
| userId | Path Parameter | The ID of the user to get sent requests for      |    ✅    |

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

| Name     | Type   | Description                                    | Required |
| :------- | :----- | :--------------------------------------------- | :------: |
| fromUser | String | The ID of the user who sent the request       |    ✅    |
| toUser   | String | The ID of the user accepting the request      |    ✅    |

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

| Name     | Type   | Description                                  | Required |
| :------- | :----- | :------------------------------------------- | :------: |
| fromUser | String | The ID of the user who sent the request     |    ✅    |
| toUser   | String | The ID of the user ignoring the request     |    ✅    |

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

| Name     | Type   | Description                                   | Required |
| :------- | :----- | :-------------------------------------------- | :------: |
| fromUser | String | The ID of the user who sent the request      |    ✅    |
| toUser   | String | The ID of the user declining the request     |    ✅    |

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

| Name     | Type   | Description                                 | Required |
| :------- | :----- | :------------------------------------------ | :------: |
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
