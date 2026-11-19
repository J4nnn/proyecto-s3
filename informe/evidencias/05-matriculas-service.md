### Evidencias · matriculas-service

Token de admin salvo que se indique. (La matrícula id 1 la creó el paso 7 de la guía de seguridad.)

#### Paso 1 — POST {estudianteId:1, cursoId:1}

**Esperado:** 201, estado ACTIVA · **Obtenido:** HTTP 201

```http
POST http://localhost:8084/api/matriculas
Authorization: Bearer <token de admin>
Content-Type: application/json

{"estudianteId":1,"cursoId":1}
```

```json
{
  "success": true,
  "message": "Matrícula registrada",
  "data": {
    "id": 2,
    "estudianteId": 1,
    "cursoId": 1,
    "fechaMatricula": "2026-11-12",
    "estado": "ACTIVA"
  }
}
```

#### Paso 2 — Repetir el paso 1

**Esperado:** 400 Ya existe una matrícula activa… · **Obtenido:** HTTP 400

```http
POST http://localhost:8084/api/matriculas
Authorization: Bearer <token de admin>
Content-Type: application/json

{"estudianteId":1,"cursoId":1}
```

```json
{
  "success": false,
  "message": "Ya existe una matrícula activa para el estudiante y curso indicados",
  "data": null
}
```

#### Paso 3 — POST con estudianteId 999

**Esperado:** 400 El estudiante indicado no existe · **Obtenido:** HTTP 400

```http
POST http://localhost:8084/api/matriculas
Authorization: Bearer <token de admin>
Content-Type: application/json

{"estudianteId":999,"cursoId":1}
```

```json
{
  "success": false,
  "message": "El estudiante indicado no existe",
  "data": null
}
```

#### Paso 4 — POST con cursoId 999

**Esperado:** 400 El curso indicado no existe · **Obtenido:** HTTP 400

```http
POST http://localhost:8084/api/matriculas
Authorization: Bearer <token de admin>
Content-Type: application/json

{"estudianteId":1,"cursoId":999}
```

```json
{
  "success": false,
  "message": "El curso indicado no existe",
  "data": null
}
```

#### Paso 5 — POST con cuerpo {}

**Esperado:** 400 Error de validación · **Obtenido:** HTTP 400

```http
POST http://localhost:8084/api/matriculas
Authorization: Bearer <token de admin>
Content-Type: application/json

{}
```

```json
{
  "success": false,
  "message": "Error de validación",
  "data": {
    "estudianteId": "El id del estudiante es obligatorio",
    "cursoId": "El id del curso es obligatorio"
  }
}
```

#### Paso 6 — PUT /api/matriculas/2/anular

**Esperado:** 200, estado ANULADA · **Obtenido:** HTTP 200

```http
PUT http://localhost:8084/api/matriculas/2/anular
Authorization: Bearer <token de admin>
```

```json
{
  "success": true,
  "message": "Matrícula anulada",
  "data": {
    "id": 2,
    "estudianteId": 1,
    "cursoId": 1,
    "fechaMatricula": "2026-11-12",
    "estado": "ANULADA"
  }
}
```

#### Paso 7 — Repetir el paso 6

**Esperado:** 400 La matrícula ya se encuentra anulada · **Obtenido:** HTTP 400

```http
PUT http://localhost:8084/api/matriculas/2/anular
Authorization: Bearer <token de admin>
```

```json
{
  "success": false,
  "message": "La matrícula ya se encuentra anulada",
  "data": null
}
```

#### Paso 8 — Repetir el paso 1

**Esperado:** 201: una matrícula anulada no bloquea una nueva · **Obtenido:** HTTP 201

```http
POST http://localhost:8084/api/matriculas
Authorization: Bearer <token de admin>
Content-Type: application/json

{"estudianteId":1,"cursoId":1}
```

```json
{
  "success": true,
  "message": "Matrícula registrada",
  "data": {
    "id": 3,
    "estudianteId": 1,
    "cursoId": 1,
    "fechaMatricula": "2026-11-12",
    "estado": "ACTIVA"
  }
}
```

#### Paso 9a — DOCENTE: GET /api/matriculas

**Esperado:** 200 · **Obtenido:** HTTP 200

```http
GET http://localhost:8084/api/matriculas
Authorization: Bearer <token de docente>
```

```json
{
  "success": true,
  "message": "OK",
  "data": {
    "content": [
      {
        "id": 1,
        "estudianteId": 2,
        "cursoId": 2,
        "fechaMatricula": "2026-11-12",
        "estado": "ACTIVA"
      },
      {
        "id": 2,
        "estudianteId": 1,
        "cursoId": 1,
        "fechaMatricula": "2026-11-12",
        "estado": "ANULADA"
      },
      {
        "id": 3,
        "estudianteId": 1,
        "cursoId": 1,
        "fechaMatricula": "2026-11-12",
        "estado": "ACTIVA"
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

#### Paso 9b — DOCENTE: POST /api/matriculas

**Esperado:** 403 · **Obtenido:** HTTP 403

```http
POST http://localhost:8084/api/matriculas
Authorization: Bearer <token de docente>
Content-Type: application/json

{"estudianteId":3,"cursoId":1}
```

```json
{
  "success": false,
  "message": "No tiene permisos para acceder a este recurso",
  "errorCode": "AUTH_FORBIDDEN",
  "status": 403,
  "path": "/api/matriculas",
  "timestamp": "2026-11-12T17:47:51.049056913"
}
```

_El paso 10 (detener estudiantes-service) se ejecuta al final; ver la sección de pruebas de caída._

#### Pruebas de caída (ejecutadas al final)

Se detuvo estudiantes-service (`servicios.sh stop estudiantes-service`).

#### Paso 10 — Con estudiantes-service detenido, registrar otra matrícula

**Esperado:** 502 No fue posible consultar el estudiante… · **Obtenido:** HTTP 502

```http
POST http://localhost:8084/api/matriculas
Authorization: Bearer <token de admin>
Content-Type: application/json

{"estudianteId":4,"cursoId":1}
```

```json
{
  "success": false,
  "message": "No fue posible consultar el estudiante (código remoto -1)",
  "data": null
}
```

