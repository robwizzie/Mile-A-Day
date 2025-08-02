# Mile-A-Day API

## Endpoints

-   **[Users](#users)**
    -   **[Get User](#get-user)**
    -   **[Search For User](#search-for-user)**
    -   **[Create User](#create-user)**
    -   **[Delete User](#delete-user)**
    -   **[Update User](#update-user)**

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

<a name="create-user"></a>

### Create User

**POST** `/users/create`

#### Parameters

| Name       | Type   | Description                                  | Required |
| :--------- | :----- | :------------------------------------------- | :------: |
| username   | String | The username for the user you are creating   |    ✅    |
| email      | String | The email for the user you are creating      |    ✅    |
| first_name | String | The first name for the user you are creating |    ✖️    |
| last_name  | String | The last name for the user you are creating  |    ✖️    |

#### Examples

<details>
<summary>Click to expand</summary>

> **POST** `/users/create`
>
> ##### Example Body
>
> ```
> {
>     "username": "PJ",
>     "email": "peter@mindgoblin.tech",
>     "first_name": "Peter",
>     "last_name": "Johnson"
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
>     "first_name": "Peter",
>     "last_name": "Johnson"
> }
> ```
>
> ##### Full cURL Example
>
> ```
> curl --location 'https://mad.mindgoblin.tech/users/create' \
> --header 'Content-Type: application/json' \
> --data-raw '{
>     "username": "PJ",
>     "email": "peter@mindgoblin.tech",
>     "first_name": "Peter",
>     "last_name": "Johnson"
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
> curl --location --request DELETE 'https://mad.mindgoblin.tech/users/peter'
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

---
