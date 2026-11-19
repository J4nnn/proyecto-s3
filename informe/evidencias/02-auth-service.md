### Evidencias · auth-service

#### Paso 1 — POST /auth/login con admin / admin123

**Esperado:** 200 con token, username y role · **Obtenido:** HTTP 200

```http
POST http://localhost:8081/auth/login
Authorization: (sin encabezado Authorization)
Content-Type: application/json

{"username":"admin","password":"admin123"}
```

```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhZG1pbiIsInJvbGUiOiJBRE1JTiIsImlhdCI6MTc5NDUyMzY2OCwiZXhwIjoxNzk0NTI3MjY4fQ.yPrx1KMQSSmaGpTV9yXS4VkdeHgLasRZo7DVmOpM1WI",
  "username": "admin",
  "role": "ADMIN"
}
```

#### Paso 2 — Login con contraseña incorrecta

**Esperado:** 401 AUTH_INVALID_CREDENTIALS · **Obtenido:** HTTP 401

```http
POST http://localhost:8081/auth/login
Authorization: (sin encabezado Authorization)
Content-Type: application/json

{"username":"admin","password":"mala"}
```

```json
{
  "success": false,
  "message": "Credenciales inválidas",
  "errorCode": "AUTH_INVALID_CREDENTIALS",
  "status": 401,
  "path": "/auth/login",
  "timestamp": "2026-11-12T17:47:48.185785719"
}
```

Comprobación adicional (usuario inexistente → mismo mensaje):

#### Paso 2b — Login con usuario inexistente

**Esperado:** 401 AUTH_INVALID_CREDENTIALS, mismo mensaje que el paso 2 · **Obtenido:** HTTP 401

```http
POST http://localhost:8081/auth/login
Authorization: (sin encabezado Authorization)
Content-Type: application/json

{"username":"noexiste","password":"x"}
```

```json
{
  "success": false,
  "message": "Credenciales inválidas",
  "errorCode": "AUTH_INVALID_CREDENTIALS",
  "status": 401,
  "path": "/auth/login",
  "timestamp": "2026-11-12T17:47:48.246284739"
}
```

#### Paso 3 — Login con cuerpo {}

**Esperado:** 400 VALIDATION_ERROR · **Obtenido:** HTTP 400

```http
POST http://localhost:8081/auth/login
Authorization: (sin encabezado Authorization)
Content-Type: application/json

{}
```

```json
{
  "path": "/auth/login",
  "success": false,
  "errorCode": "VALIDATION_ERROR",
  "message": "Error de validación",
  "errors": {
    "password": "must not be blank",
    "username": "must not be blank"
  },
  "status": 400
}
```

#### Paso 4 — GET /auth/validate con token de admin

**Esperado:** 200, valid: true, role: ADMIN · **Obtenido:** HTTP 200

```http
GET http://localhost:8081/auth/validate
Authorization: Bearer <token de admin>
```

```json
{
  "valid": true,
  "username": "admin",
  "role": "ADMIN",
  "estudianteId": null
}
```

#### Paso 5 — GET /auth/validate con token de estudiante

**Esperado:** estudianteId: 1 · **Obtenido:** HTTP 200

```http
GET http://localhost:8081/auth/validate
Authorization: Bearer <token de estudiante>
```

```json
{
  "valid": true,
  "username": "estudiante",
  "role": "ESTUDIANTE",
  "estudianteId": 1
}
```

#### Paso 6 — GET /auth/validate sin autorizar

**Esperado:** 401 AUTH_INVALID_TOKEN · **Obtenido:** HTTP 401

```http
GET http://localhost:8081/auth/validate
Authorization: (sin encabezado Authorization)
```

```json
{
  "success": false,
  "message": "Debe enviar un token Bearer válido",
  "errorCode": "AUTH_INVALID_TOKEN",
  "status": 401,
  "path": "/auth/validate",
  "timestamp": "2026-11-12T17:47:48.519593032"
}
```

#### Paso 7 — GET /auth/validate con el token alterado (una letra del payload cambiada)

**Esperado:** 401 AUTH_INVALID_TOKEN · **Obtenido:** HTTP 401

```http
GET http://localhost:8081/auth/validate
Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJz…
```

```json
{
  "success": false,
  "message": "Token inválido o expirado",
  "errorCode": "AUTH_INVALID_TOKEN",
  "status": 401,
  "path": "/auth/validate",
  "timestamp": "2026-11-12T17:47:48.583319147"
}
```

#### Paso 8 — Consola H2 (jdbc:h2:mem:authdb): SELECT * FROM usuarios

**Esperado:** contraseñas cifradas y estudiante_id = 1 solo para el estudiante

| ID | USERNAME | ROLE | ESTUDIANTE_ID | PASSWORD |
|---|---|---|---|---|
| 1 | admin | ADMIN | null | $2a$10$VX8RUxhhNCbNhBoe7SNbpOi.e1MU8LjKVgtTEuNNyT2.JB.pkZ.ey |
| 2 | docente | DOCENTE | null | $2a$10$SozYsqj/o3SHR1zJu0CZXO1O1oe8JZkL1cSN6mmyP9PmrBr9Q3p7e |
| 3 | estudiante | ESTUDIANTE | 1 | $2a$10$a22cpqDS.xYrgFjVpX1BpekawFwlsx.hlOWtFJODO5LsEcvZFxxTa |

Decodificación (sin secreto) del payload del token de estudiante — muestra que el contenido del JWT es legible:

```json
{
  "sub": "estudiante",
  "role": "ESTUDIANTE",
  "iat": 1794523666,
  "exp": 1794527266,
  "estudianteId": 1
}
```

