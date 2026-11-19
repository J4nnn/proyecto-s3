### Evidencias · Seguridad

Sobre servicios recién iniciados (local).

#### Paso 1 — GET /api/cursos/1 sin autorizar

**Esperado:** 401 AUTH_HEADER_MISSING · **Obtenido:** HTTP 401

```http
GET http://localhost:8083/api/cursos/1
Authorization: (sin encabezado Authorization)
```

```json
{
  "success": false,
  "message": "Debe enviar un token Bearer válido",
  "errorCode": "AUTH_HEADER_MISSING",
  "status": 401,
  "path": "/api/cursos/1",
  "timestamp": "2026-11-12T17:47:46.350719165"
}
```

#### Paso 2 — GET /api/cursos/1 con un token inventado

**Esperado:** 401 TOKEN_INVALID · **Obtenido:** HTTP 401

```http
GET http://localhost:8083/api/cursos/1
Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.inve…
```

```json
{
  "success": false,
  "message": "El token no es válido o expiró",
  "errorCode": "TOKEN_INVALID",
  "status": 401,
  "path": "/api/cursos/1",
  "timestamp": "2026-11-12T17:47:46.635456245"
}
```

#### Paso 3 — DOCENTE: POST /api/cursos

**Esperado:** 403 AUTH_FORBIDDEN · **Obtenido:** HTTP 403

```http
POST http://localhost:8083/api/cursos
Authorization: Bearer <token de docente>
Content-Type: application/json

{"codigo":"DOC-001","nombre":"Curso docente","creditos":3,"docenteResponsable":"Docente","cupoMaximo":10}
```

```json
{
  "success": false,
  "message": "No tiene permisos para acceder a este recurso",
  "errorCode": "AUTH_FORBIDDEN",
  "status": 403,
  "path": "/api/cursos",
  "timestamp": "2026-11-12T17:47:46.70733663"
}
```

#### Paso 4 — ESTUDIANTE: GET /api/cursos

**Esperado:** 200 · **Obtenido:** HTTP 200

```http
GET http://localhost:8083/api/cursos
Authorization: Bearer <token de estudiante>
```

```json
{
  "success": true,
  "message": "OK",
  "data": {
    "content": [
      {
        "id": 1,
        "codigo": "IS3-001",
        "nombre": "Ingeniería de Software III",
        "descripcion": "Arquitectura y microservicios",
        "creditos": 4,
        "docenteResponsable": "Docente principal",
        "cupoMaximo": 30
      },
      {
        "id": 2,
        "codigo": "BD2-001",
        "nombre": "Bases de Datos II",
        "descripcion": "Modelado avanzado y SQL",
        "creditos": 3,
        "docenteResponsable": "Docente de bases de datos",
        "cupoMaximo": 25
      },
      {
        "id": 3,
        "codigo": "RED-001",
        "nombre": "Redes de Computadores",
        "descripcion": "Fundamentos de redes TCP/IP",
        "creditos": 3,
        "docenteResponsable": "Docente de redes",
        "cupoMaximo": 2
      }
    ],
    "pageable": {
      "pageNumber": 0,
      "pageSize": 20,
      "sort": [],
      "offset": 0,
      "paged": true,
      "unpaged": false
    },
    "last": true,
    "totalPages": 1,
    "totalElements": 3,
    "size": 20,
    "number": 0,
    "sort": [],
    "first": true,
    "numberOfElements": 3,
    "empty": false
  }
}
```

#### Paso 5 — ESTUDIANTE: GET /api/estudiantes (8082)

**Esperado:** 403 · **Obtenido:** HTTP 403

```http
GET http://localhost:8082/api/estudiantes
Authorization: Bearer <token de estudiante>
```

```json
{
  "success": false,
  "message": "No tiene permisos para acceder a este recurso",
  "errorCode": "AUTH_FORBIDDEN",
  "status": 403,
  "path": "/api/estudiantes",
  "timestamp": "2026-11-12T17:47:46.95981999"
}
```

#### Paso 6 — GET /v3/api-docs sin token

**Esperado:** 200 · **Obtenido:** HTTP 200

```http
GET http://localhost:8083/v3/api-docs
Authorization: (sin encabezado Authorization)
```

```json
{
  "openapi": "3.0.1",
  "info": {
    "title": "Cursos Service",
    "description": "CRUD de cursos protegido con JWT",
    "version": "1.0.0"
  },
  "paths": [
    "/api/cursos",
    "/api/cursos/{id}"
  ]
}
```

(Se muestra un extracto: versión, info y rutas documentadas.)

#### Paso 7 — ADMIN: POST /api/matriculas (8084) con {estudianteId:2, cursoId:2}

**Esperado:** 201: el token se propagó a estudiantes y cursos · **Obtenido:** HTTP 201

```http
POST http://localhost:8084/api/matriculas
Authorization: Bearer <token de admin>
Content-Type: application/json

{"estudianteId":2,"cursoId":2}
```

```json
{
  "success": true,
  "message": "Matrícula registrada",
  "data": {
    "id": 1,
    "estudianteId": 2,
    "cursoId": 2,
    "fechaMatricula": "2026-11-12",
    "estado": "ACTIVA"
  }
}
```

#### Paso 8 — Consola H2 de auth (jdbc:h2:mem:authdb): SELECT * FROM usuarios

**Esperado:** contraseñas con formato `$2a$10$…` (BCrypt)

| ID | ESTUDIANTE_ID | PASSWORD | ROLE | USERNAME |
|---|---|---|---|---|
| 1 | null | $2a$10$VX8RUxhhNCbNhBoe7SNbpOi.e1MU8LjKVgtTEuNNyT2.JB.pkZ.ey | ADMIN | admin |
| 2 | null | $2a$10$SozYsqj/o3SHR1zJu0CZXO1O1oe8JZkL1cSN6mmyP9PmrBr9Q3p7e | DOCENTE | docente |
| 3 | 1 | $2a$10$a22cpqDS.xYrgFjVpX1BpekawFwlsx.hlOWtFJODO5LsEcvZFxxTa | ESTUDIANTE | estudiante |

_El paso 9 (detener auth-service) se ejecuta al final; ver la sección de pruebas de caída._

#### Prueba de caída (ejecutada al final)

Se detuvo auth-service (`servicios.sh stop auth-service`).

#### Paso 9 — Con auth-service detenido: ESTUDIANTE GET /api/cursos

**Esperado:** 401 TOKEN_VALIDATION_ERROR · **Obtenido:** HTTP 401

```http
GET http://localhost:8083/api/cursos
Authorization: Bearer <token de estudiante>
```

```json
{
  "success": false,
  "message": "No fue posible validar el token con auth-service",
  "errorCode": "TOKEN_VALIDATION_ERROR",
  "status": 401,
  "path": "/api/cursos",
  "timestamp": "2026-11-12T17:50:27.556228828"
}
```

