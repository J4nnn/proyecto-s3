### Evidencias · cursos-service

Token de admin salvo que se indique.

#### Paso 1 — GET /api/cursos

**Esperado:** 200 con los tres cursos semilla y su cupoMaximo · **Obtenido:** HTTP 200

```http
GET http://localhost:8083/api/cursos
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

#### Paso 2 — POST curso ARQ-001

**Esperado:** 201 · **Obtenido:** HTTP 201

```http
POST http://localhost:8083/api/cursos
Authorization: Bearer <token de admin>
Content-Type: application/json

{"codigo":"ARQ-001","nombre":"Arquitectura","creditos":3,"docenteResponsable":"Docente","cupoMaximo":20}
```

```json
{
  "success": true,
  "message": "Curso creado",
  "data": {
    "id": 4,
    "codigo": "ARQ-001",
    "nombre": "Arquitectura",
    "descripcion": null,
    "creditos": 3,
    "docenteResponsable": "Docente",
    "cupoMaximo": 20
  }
}
```

#### Paso 3 — Repetir el paso 2

**Esperado:** 400 Ya existe un curso con el código: ARQ-001 · **Obtenido:** HTTP 400

```http
POST http://localhost:8083/api/cursos
Authorization: Bearer <token de admin>
Content-Type: application/json

{"codigo":"ARQ-001","nombre":"Arquitectura","creditos":3,"docenteResponsable":"Docente","cupoMaximo":20}
```

```json
{
  "success": false,
  "message": "Ya existe un curso con el código: ARQ-001",
  "data": null
}
```

#### Paso 4 — POST con creditos: 11

**Esperado:** 400 Los créditos máximos son 10 · **Obtenido:** HTTP 400

```http
POST http://localhost:8083/api/cursos
Authorization: Bearer <token de admin>
Content-Type: application/json

{"codigo":"ARQ-002","nombre":"Arquitectura","creditos":11,"docenteResponsable":"Docente","cupoMaximo":20}
```

```json
{
  "success": false,
  "message": "Error de validación",
  "data": {
    "creditos": "Los créditos máximos son 10"
  }
}
```

#### Paso 5 — PUT /api/cursos/1 con codigo BD2-001

**Esperado:** 400 Ya existe otro curso con el código: BD2-001 · **Obtenido:** HTTP 400

```http
PUT http://localhost:8083/api/cursos/1
Authorization: Bearer <token de admin>
Content-Type: application/json

{"codigo":"BD2-001","nombre":"Ingeniería de Software III","descripcion":"Arquitectura y microservicios","creditos":4,"docenteResponsable":"Docente principal","cupoMaximo":30}
```

```json
{
  "success": false,
  "message": "Ya existe otro curso con el código: BD2-001",
  "data": null
}
```

#### Paso 6a — ESTUDIANTE: GET /api/cursos

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
      },
      {
        "id": 4,
        "codigo": "ARQ-001",
        "nombre": "Arquitectura",
        "descripcion": null,
        "creditos": 3,
        "docenteResponsable": "Docente",
        "cupoMaximo": 20
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

#### Paso 6b — ESTUDIANTE: POST /api/cursos

**Esperado:** 403 · **Obtenido:** HTTP 403

```http
POST http://localhost:8083/api/cursos
Authorization: Bearer <token de estudiante>
Content-Type: application/json

{"codigo":"EST-001","nombre":"X","creditos":3,"docenteResponsable":"Docente","cupoMaximo":20}
```

```json
{
  "success": false,
  "message": "No tiene permisos para acceder a este recurso",
  "errorCode": "AUTH_FORBIDDEN",
  "status": 403,
  "path": "/api/cursos",
  "timestamp": "2026-11-12T17:47:50.070888051"
}
```

#### Paso 7 — DELETE /api/cursos/4 (curso creado en el paso 2)

**Esperado:** 200 (no tiene matrículas) · **Obtenido:** HTTP 200

```http
DELETE http://localhost:8083/api/cursos/4
Authorization: Bearer <token de admin>
```

```json
{
  "success": true,
  "message": "Curso eliminado",
  "data": null
}
```

