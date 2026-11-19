### Evidencias · Extensión E2 (cupos)

Con los servicios recién reiniciados. Token de admin.

#### Paso 1 — GET /api/cursos/3 (8083)

**Esperado:** RED-001 con cupoMaximo: 2 · **Obtenido:** HTTP 200

```http
GET http://localhost:8083/api/cursos/3
Authorization: Bearer <token de admin>
```

```json
{
  "success": true,
  "message": "OK",
  "data": {
    "id": 3,
    "codigo": "RED-001",
    "nombre": "Redes de Computadores",
    "descripcion": "Fundamentos de redes TCP/IP",
    "creditos": 3,
    "docenteResponsable": "Docente de redes",
    "cupoMaximo": 2
  }
}
```

#### Paso 2 — POST /api/matriculas {estudianteId:1, cursoId:3}

**Esperado:** 201 · **Obtenido:** HTTP 201

```http
POST http://localhost:8084/api/matriculas
Authorization: Bearer <token de admin>
Content-Type: application/json

{"estudianteId":1,"cursoId":3}
```

```json
{
  "success": true,
  "message": "Matrícula registrada",
  "data": {
    "id": 1,
    "estudianteId": 1,
    "cursoId": 3,
    "fechaMatricula": "2026-11-12",
    "estado": "ACTIVA"
  }
}
```

#### Paso 3 — POST /api/matriculas {estudianteId:2, cursoId:3}

**Esperado:** 201 · **Obtenido:** HTTP 201

```http
POST http://localhost:8084/api/matriculas
Authorization: Bearer <token de admin>
Content-Type: application/json

{"estudianteId":2,"cursoId":3}
```

```json
{
  "success": true,
  "message": "Matrícula registrada",
  "data": {
    "id": 2,
    "estudianteId": 2,
    "cursoId": 3,
    "fechaMatricula": "2026-11-12",
    "estado": "ACTIVA"
  }
}
```

#### Paso 4 — POST /api/matriculas {estudianteId:3, cursoId:3}

**Esperado:** 400 El curso no tiene cupos disponibles (2/2) · **Obtenido:** HTTP 400

```http
POST http://localhost:8084/api/matriculas
Authorization: Bearer <token de admin>
Content-Type: application/json

{"estudianteId":3,"cursoId":3}
```

```json
{
  "success": false,
  "message": "El curso no tiene cupos disponibles (2/2)",
  "data": null
}
```

#### Paso 5 — PUT /api/matriculas/2/anular

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
    "estudianteId": 2,
    "cursoId": 3,
    "fechaMatricula": "2026-11-12",
    "estado": "ANULADA"
  }
}
```

#### Paso 6 — Repetir el paso 4

**Esperado:** 201: se liberó un cupo · **Obtenido:** HTTP 201

```http
POST http://localhost:8084/api/matriculas
Authorization: Bearer <token de admin>
Content-Type: application/json

{"estudianteId":3,"cursoId":3}
```

```json
{
  "success": true,
  "message": "Matrícula registrada",
  "data": {
    "id": 3,
    "estudianteId": 3,
    "cursoId": 3,
    "fechaMatricula": "2026-11-12",
    "estado": "ACTIVA"
  }
}
```

#### Paso 7 — PUT /api/cursos/3 con los mismos datos y cupoMaximo: 1

**Esperado:** 400 El cupo no puede ser menor que las 2 matrícula(s) activa(s) del curso · **Obtenido:** HTTP 400

```http
PUT http://localhost:8083/api/cursos/3
Authorization: Bearer <token de admin>
Content-Type: application/json

{"codigo":"RED-001","nombre":"Redes de Computadores","descripcion":"Fundamentos de redes TCP/IP","creditos":3,"docenteResponsable":"Docente de redes","cupoMaximo":1}
```

```json
{
  "success": false,
  "message": "El cupo no puede ser menor que las 2 matrícula(s) activa(s) del curso",
  "data": null
}
```

#### Paso 8 — POST /api/cursos sin cupoMaximo

**Esperado:** 400 El cupo máximo es obligatorio · **Obtenido:** HTTP 400

```http
POST http://localhost:8083/api/cursos
Authorization: Bearer <token de admin>
Content-Type: application/json

{"codigo":"SIN-CUPO","nombre":"Sin cupo","creditos":3,"docenteResponsable":"Docente"}
```

```json
{
  "success": false,
  "message": "Error de validación",
  "data": {
    "cupoMaximo": "El cupo máximo es obligatorio"
  }
}
```

