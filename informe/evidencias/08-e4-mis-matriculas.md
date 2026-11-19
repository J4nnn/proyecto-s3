### Evidencias · Extensión E4 (mis matrículas)

Continuando con los datos de E2/E1.

#### Paso 1 — Login como estudiante y GET /auth/validate

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

#### Paso 2 — ADMIN: GET /api/matriculas (matrículas de varios estudiantes)

**Esperado:** Existen matrículas de los estudiantes 1, 2, 3 (y 5) · **Obtenido:** HTTP 200

```http
GET http://localhost:8084/api/matriculas?size=20
Authorization: Bearer <token de admin>
```

```json
{
  "success": true,
  "message": "OK",
  "data": {
    "content": [
      {
        "id": 1,
        "estudianteId": 1,
        "cursoId": 3,
        "fechaMatricula": "2026-11-12",
        "estado": "ACTIVA"
      },
      {
        "id": 2,
        "estudianteId": 2,
        "cursoId": 3,
        "fechaMatricula": "2026-11-12",
        "estado": "ANULADA"
      },
      {
        "id": 3,
        "estudianteId": 3,
        "cursoId": 3,
        "fechaMatricula": "2026-11-12",
        "estado": "ACTIVA"
      },
      {
        "id": 4,
        "estudianteId": 5,
        "cursoId": 2,
        "fechaMatricula": "2026-11-12",
        "estado": "ANULADA"
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
    "totalElements": 4,
    "size": 20,
    "number": 0,
    "sort": [],
    "first": true,
    "numberOfElements": 4,
    "empty": false
  }
}
```

#### Paso 3 — ESTUDIANTE: GET /api/matriculas/mias

**Esperado:** Solo las matrículas del estudiante 1 · **Obtenido:** HTTP 200

```http
GET http://localhost:8084/api/matriculas/mias
Authorization: Bearer <token de estudiante>
```

```json
{
  "success": true,
  "message": "OK",
  "data": [
    {
      "id": 1,
      "estudianteId": 1,
      "cursoId": 3,
      "fechaMatricula": "2026-11-12",
      "estado": "ACTIVA"
    }
  ]
}
```

#### Paso 4 — ESTUDIANTE: GET /api/matriculas

**Esperado:** 403 AUTH_FORBIDDEN · **Obtenido:** HTTP 403

```http
GET http://localhost:8084/api/matriculas
Authorization: Bearer <token de estudiante>
```

```json
{
  "success": false,
  "message": "No tiene permisos para acceder a este recurso",
  "errorCode": "AUTH_FORBIDDEN",
  "status": 403,
  "path": "/api/matriculas",
  "timestamp": "2026-11-12T17:49:20.636102809"
}
```

#### Paso 5 — ESTUDIANTE: GET /api/matriculas/2 (de otro estudiante)

**Esperado:** 403 · **Obtenido:** HTTP 403

```http
GET http://localhost:8084/api/matriculas/2
Authorization: Bearer <token de estudiante>
```

```json
{
  "success": false,
  "message": "No tiene permisos para acceder a este recurso",
  "errorCode": "AUTH_FORBIDDEN",
  "status": 403,
  "path": "/api/matriculas/2",
  "timestamp": "2026-11-12T17:49:20.687309182"
}
```

#### Paso 6 — ADMIN: GET /api/matriculas/mias

**Esperado:** 403 · **Obtenido:** HTTP 403

```http
GET http://localhost:8084/api/matriculas/mias
Authorization: Bearer <token de admin>
```

```json
{
  "success": false,
  "message": "No tiene permisos para acceder a este recurso",
  "errorCode": "AUTH_FORBIDDEN",
  "status": 403,
  "path": "/api/matriculas/mias",
  "timestamp": "2026-11-12T17:49:20.733528281"
}
```

