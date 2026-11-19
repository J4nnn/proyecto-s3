### Evidencias · Extensión E3 (calificaciones-service)

Matrícula 1 activa (estudiante 1) y matrícula 2 anulada, como quedan después de E2.

#### Paso 1 — DOCENTE: POST {matriculaId:1, corte:1, nota:4.0}

**Esperado:** 201, registradoPor: docente · **Obtenido:** HTTP 201

```http
POST http://localhost:8085/api/calificaciones
Authorization: Bearer <token de docente>
Content-Type: application/json

{"matriculaId":1,"corte":1,"nota":4.0}
```

```json
{
  "success": true,
  "message": "Calificación registrada",
  "data": {
    "id": 1,
    "matriculaId": 1,
    "corte": 1,
    "nota": 4.0,
    "registradoPor": "docente",
    "fechaRegistro": "2026-11-12T17:49:21.105817814"
  }
}
```

#### Paso 2 — DOCENTE: POST {matriculaId:1, corte:2, nota:3.0}

**Esperado:** 201 · **Obtenido:** HTTP 201

```http
POST http://localhost:8085/api/calificaciones
Authorization: Bearer <token de docente>
Content-Type: application/json

{"matriculaId":1,"corte":2,"nota":3.0}
```

```json
{
  "success": true,
  "message": "Calificación registrada",
  "data": {
    "id": 2,
    "matriculaId": 1,
    "corte": 2,
    "nota": 3.0,
    "registradoPor": "docente",
    "fechaRegistro": "2026-11-12T17:49:21.272949571"
  }
}
```

#### Paso 3 — DOCENTE: repetir el paso 1

**Esperado:** 400 …use PUT para corregirla · **Obtenido:** HTTP 400

```http
POST http://localhost:8085/api/calificaciones
Authorization: Bearer <token de docente>
Content-Type: application/json

{"matriculaId":1,"corte":1,"nota":4.0}
```

```json
{
  "success": false,
  "message": "Ya existe una nota para el corte 1 de esta matrícula; use PUT para corregirla",
  "data": null
}
```

#### Paso 4 — DOCENTE: POST con corte 4 y nota 5.5

**Esperado:** 400 con los errores de ambos campos · **Obtenido:** HTTP 400

```http
POST http://localhost:8085/api/calificaciones
Authorization: Bearer <token de docente>
Content-Type: application/json

{"matriculaId":1,"corte":4,"nota":5.5}
```

```json
{
  "success": false,
  "message": "Error de validación",
  "data": {
    "nota": "La nota máxima es 5.0",
    "corte": "El corte debe ser 1, 2 o 3"
  }
}
```

#### Paso 5 — DOCENTE: POST sobre la matrícula anulada (id 2)

**Esperado:** 400 La matrícula 2 no está activa · **Obtenido:** HTTP 400

```http
POST http://localhost:8085/api/calificaciones
Authorization: Bearer <token de docente>
Content-Type: application/json

{"matriculaId":2,"corte":1,"nota":4.0}
```

```json
{
  "success": false,
  "message": "La matrícula 2 no está activa",
  "data": null
}
```

#### Paso 6 — ADMIN: PUT /api/calificaciones/1 {nota:4.5}

**Esperado:** 200, registradoPor: admin · **Obtenido:** HTTP 200

```http
PUT http://localhost:8085/api/calificaciones/1
Authorization: Bearer <token de admin>
Content-Type: application/json

{"nota":4.5}
```

```json
{
  "success": true,
  "message": "Calificación actualizada",
  "data": {
    "id": 1,
    "matriculaId": 1,
    "corte": 1,
    "nota": 4.5,
    "registradoPor": "admin",
    "fechaRegistro": "2026-11-12T17:49:21.63421963"
  }
}
```

#### Paso 7 — DOCENTE: GET /api/calificaciones/matricula/1

**Esperado:** promedioPonderado: 3.75, completa: false · **Obtenido:** HTTP 200

```http
GET http://localhost:8085/api/calificaciones/matricula/1
Authorization: Bearer <token de docente>
```

```json
{
  "success": true,
  "message": "OK",
  "data": {
    "matriculaId": 1,
    "calificaciones": [
      {
        "id": 1,
        "matriculaId": 1,
        "corte": 1,
        "nota": 4.5,
        "registradoPor": "admin",
        "fechaRegistro": "2026-11-12T17:49:21.63422"
      },
      {
        "id": 2,
        "matriculaId": 1,
        "corte": 2,
        "nota": 3.0,
        "registradoPor": "docente",
        "fechaRegistro": "2026-11-12T17:49:21.27295"
      }
    ],
    "promedioPonderado": 3.75,
    "completa": false
  }
}
```

#### Paso 8 — DOCENTE: GET /api/calificaciones/matricula/99

**Esperado:** 404 · **Obtenido:** HTTP 404

```http
GET http://localhost:8085/api/calificaciones/matricula/99
Authorization: Bearer <token de docente>
```

```json
{
  "success": false,
  "message": "La matrícula 99 no existe",
  "data": null
}
```

#### Paso 9 — ESTUDIANTE: POST /api/calificaciones

**Esperado:** 403 · **Obtenido:** HTTP 403

```http
POST http://localhost:8085/api/calificaciones
Authorization: Bearer <token de estudiante>
Content-Type: application/json

{"matriculaId":1,"corte":3,"nota":5.0}
```

```json
{
  "success": false,
  "message": "No tiene permisos para acceder a este recurso",
  "errorCode": "AUTH_FORBIDDEN",
  "status": 403,
  "path": "/api/calificaciones",
  "timestamp": "2026-11-12T17:49:21.99596765"
}
```

#### Paso 10 — ESTUDIANTE: GET /api/calificaciones/mias

**Esperado:** Solo el resumen de sus matrículas · **Obtenido:** HTTP 200

```http
GET http://localhost:8085/api/calificaciones/mias
Authorization: Bearer <token de estudiante>
```

```json
{
  "success": true,
  "message": "OK",
  "data": [
    {
      "matriculaId": 1,
      "calificaciones": [
        {
          "id": 1,
          "matriculaId": 1,
          "corte": 1,
          "nota": 4.5,
          "registradoPor": "admin",
          "fechaRegistro": "2026-11-12T17:49:21.63422"
        },
        {
          "id": 2,
          "matriculaId": 1,
          "corte": 2,
          "nota": 3.0,
          "registradoPor": "docente",
          "fechaRegistro": "2026-11-12T17:49:21.27295"
        }
      ],
      "promedioPonderado": 3.75,
      "completa": false
    }
  ]
}
```

