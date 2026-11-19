### Evidencias · estudiantes-service

Token de admin salvo que se indique.

#### Paso 1 — GET /api/estudiantes?page=0&size=5

**Esperado:** 200, 5 estudiantes y totalElements: 50 · **Obtenido:** HTTP 200

```http
GET http://localhost:8082/api/estudiantes?page=0&size=5
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
        "nombre": "Víctor",
        "apellido": "Gutiérrez",
        "email": "estudiante0@demoacademico.edu",
        "edad": 18
      },
      {
        "id": 2,
        "nombre": "Gabriela",
        "apellido": "Bañuelos",
        "email": "estudiante1@demoacademico.edu",
        "edad": 19
      },
      {
        "id": 3,
        "nombre": "Clemente",
        "apellido": "Menéndez",
        "email": "estudiante2@demoacademico.edu",
        "edad": 20
      },
      {
        "id": 4,
        "nombre": "Alfonso",
        "apellido": "Díaz",
        "email": "estudiante3@demoacademico.edu",
        "edad": 21
      },
      {
        "id": 5,
        "nombre": "Cristina",
        "apellido": "Pagan",
        "email": "estudiante4@demoacademico.edu",
        "edad": 22
      }
    ],
    "pageable": {
      "pageNumber": 0,
      "pageSize": 5,
      "sort": [],
      "offset": 0,
      "paged": true,
      "unpaged": false
    },
    "last": false,
    "totalPages": 10,
    "totalElements": 50,
    "size": 5,
    "number": 0,
    "sort": [],
    "first": true,
    "numberOfElements": 5,
    "empty": false
  }
}
```

#### Paso 2 — GET /api/estudiantes/999

**Esperado:** 404 Estudiante no encontrado: 999 · **Obtenido:** HTTP 404

```http
GET http://localhost:8082/api/estudiantes/999
Authorization: Bearer <token de admin>
```

```json
{
  "success": false,
  "message": "Estudiante no encontrado: 999",
  "data": null
}
```

#### Paso 3 — POST estudiante Ana Ruiz

**Esperado:** 201 · **Obtenido:** HTTP 201

```http
POST http://localhost:8082/api/estudiantes
Authorization: Bearer <token de admin>
Content-Type: application/json

{"nombre":"Ana","apellido":"Ruiz","email":"ana.ruiz@correo.edu","edad":20}
```

```json
{
  "success": true,
  "message": "Estudiante creado",
  "data": {
    "id": 51,
    "nombre": "Ana",
    "apellido": "Ruiz",
    "email": "ana.ruiz@correo.edu",
    "edad": 20
  }
}
```

#### Paso 4 — Repetir el paso 3

**Esperado:** 400 Ya existe un estudiante con el email… · **Obtenido:** HTTP 400

```http
POST http://localhost:8082/api/estudiantes
Authorization: Bearer <token de admin>
Content-Type: application/json

{"nombre":"Ana","apellido":"Ruiz","email":"ana.ruiz@correo.edu","edad":20}
```

```json
{
  "success": false,
  "message": "Ya existe un estudiante con el email: ana.ruiz@correo.edu",
  "data": null
}
```

#### Paso 5 — POST con email no-es-correo y edad 0

**Esperado:** 400 Error de validación con ambos campos · **Obtenido:** HTTP 400

```http
POST http://localhost:8082/api/estudiantes
Authorization: Bearer <token de admin>
Content-Type: application/json

{"nombre":"Ana","apellido":"Ruiz","email":"no-es-correo","edad":0}
```

```json
{
  "success": false,
  "message": "Error de validación",
  "data": {
    "email": "El email no es válido",
    "edad": "La edad mínima es 1"
  }
}
```

#### Paso 6 — PUT /api/estudiantes/2 con el correo del estudiante 3

**Esperado:** 400 Ya existe otro estudiante con el email… · **Obtenido:** HTTP 400

```http
PUT http://localhost:8082/api/estudiantes/2
Authorization: Bearer <token de admin>
Content-Type: application/json

{"nombre":"Gabriela","apellido":"Bañuelos","edad":19,"email":"estudiante2@demoacademico.edu"}
```

```json
{
  "success": false,
  "message": "Ya existe otro estudiante con el email: estudiante2@demoacademico.edu",
  "data": null
}
```

#### Paso 7a — DOCENTE: GET /api/estudiantes/1

**Esperado:** 200 · **Obtenido:** HTTP 200

```http
GET http://localhost:8082/api/estudiantes/1
Authorization: Bearer <token de docente>
```

```json
{
  "success": true,
  "message": "OK",
  "data": {
    "id": 1,
    "nombre": "Víctor",
    "apellido": "Gutiérrez",
    "email": "estudiante0@demoacademico.edu",
    "edad": 18
  }
}
```

#### Paso 7b — DOCENTE: POST /api/estudiantes

**Esperado:** 403 · **Obtenido:** HTTP 403

```http
POST http://localhost:8082/api/estudiantes
Authorization: Bearer <token de docente>
Content-Type: application/json

{"nombre":"Doc","apellido":"Ente","email":"doc@correo.edu","edad":30}
```

```json
{
  "success": false,
  "message": "No tiene permisos para acceder a este recurso",
  "errorCode": "AUTH_FORBIDDEN",
  "status": 403,
  "path": "/api/estudiantes",
  "timestamp": "2026-11-12T17:47:49.399144455"
}
```

#### Paso 8 — ESTUDIANTE: GET /api/estudiantes/1

**Esperado:** 403 · **Obtenido:** HTTP 403

```http
GET http://localhost:8082/api/estudiantes/1
Authorization: Bearer <token de estudiante>
```

```json
{
  "success": false,
  "message": "No tiene permisos para acceder a este recurso",
  "errorCode": "AUTH_FORBIDDEN",
  "status": 403,
  "path": "/api/estudiantes/1",
  "timestamp": "2026-11-12T17:47:49.44246439"
}
```

#### Paso 9 — GET /api/estudiantes/abc

**Esperado:** 400 Solicitud inválida… (no 401) · **Obtenido:** HTTP 400

```http
GET http://localhost:8082/api/estudiantes/abc
Authorization: Bearer <token de admin>
```

```json
{
  "success": false,
  "message": "Solicitud inválida: revise los parámetros de la URL y el formato del JSON",
  "data": null
}
```

