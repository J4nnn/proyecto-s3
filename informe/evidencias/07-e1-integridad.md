### Evidencias · Extensión E1 (integridad entre servicios)

Continuando con los datos de E2 (curso 3 con dos matrículas activas). Token de admin.

#### Paso 1 — GET /api/matriculas/activas/conteo?cursoId=3

**Esperado:** 200 con data: 2 · **Obtenido:** HTTP 200

```http
GET http://localhost:8084/api/matriculas/activas/conteo?cursoId=3
Authorization: Bearer <token de admin>
```

```json
{
  "success": true,
  "message": "OK",
  "data": 2
}
```

#### Paso 2 — GET /api/matriculas/activas/conteo (sin filtro)

**Esperado:** 400 Envíe exactamente uno de los parámetros… · **Obtenido:** HTTP 400

```http
GET http://localhost:8084/api/matriculas/activas/conteo
Authorization: Bearer <token de admin>
```

```json
{
  "success": false,
  "message": "Envíe exactamente uno de los parámetros: estudianteId o cursoId",
  "data": null
}
```

#### Paso 3 — DELETE /api/cursos/3

**Esperado:** 409 No se puede eliminar: el curso tiene 2 matrícula(s) activa(s) · **Obtenido:** HTTP 409

```http
DELETE http://localhost:8083/api/cursos/3
Authorization: Bearer <token de admin>
```

```json
{
  "success": false,
  "message": "No se puede eliminar: el curso tiene 2 matrícula(s) activa(s)",
  "data": null
}
```

#### Paso 4 — DELETE /api/estudiantes/1 (tiene una matrícula activa)

**Esperado:** 409 · **Obtenido:** HTTP 409

```http
DELETE http://localhost:8082/api/estudiantes/1
Authorization: Bearer <token de admin>
```

```json
{
  "success": false,
  "message": "No se puede eliminar: el estudiante tiene 1 matrícula(s) activa(s)",
  "data": null
}
```

#### Paso 5 — DELETE /api/estudiantes/50 (sin matrículas)

**Esperado:** 200 · **Obtenido:** HTTP 200

```http
DELETE http://localhost:8082/api/estudiantes/50
Authorization: Bearer <token de admin>
```

```json
{
  "success": true,
  "message": "Estudiante eliminado",
  "data": null
}
```

#### Paso 6a — Matricular al estudiante 5 en el curso 2

**Esperado:** 201 · **Obtenido:** HTTP 201

```http
POST http://localhost:8084/api/matriculas
Authorization: Bearer <token de admin>
Content-Type: application/json

{"estudianteId":5,"cursoId":2}
```

```json
{
  "success": true,
  "message": "Matrícula registrada",
  "data": {
    "id": 4,
    "estudianteId": 5,
    "cursoId": 2,
    "fechaMatricula": "2026-11-12",
    "estado": "ACTIVA"
  }
}
```

#### Paso 6b — DELETE /api/cursos/2

**Esperado:** 409 …tiene 1 matrícula(s) activa(s) · **Obtenido:** HTTP 409

```http
DELETE http://localhost:8083/api/cursos/2
Authorization: Bearer <token de admin>
```

```json
{
  "success": false,
  "message": "No se puede eliminar: el curso tiene 1 matrícula(s) activa(s)",
  "data": null
}
```

#### Paso 7a — Anular la matrícula 4

**Esperado:** 200 · **Obtenido:** HTTP 200

```http
PUT http://localhost:8084/api/matriculas/4/anular
Authorization: Bearer <token de admin>
```

```json
{
  "success": true,
  "message": "Matrícula anulada",
  "data": {
    "id": 4,
    "estudianteId": 5,
    "cursoId": 2,
    "fechaMatricula": "2026-11-12",
    "estado": "ANULADA"
  }
}
```

#### Paso 7b — Repetir DELETE /api/cursos/2

**Esperado:** 200: sin matrículas activas, el curso se elimina · **Obtenido:** HTTP 200

```http
DELETE http://localhost:8083/api/cursos/2
Authorization: Bearer <token de admin>
```

```json
{
  "success": true,
  "message": "Curso eliminado",
  "data": null
}
```

_El paso 8 (detener matriculas-service) se ejecuta al final; ver la sección de pruebas de caída._

#### Prueba de caída (ejecutada al final)

Se detuvo matriculas-service (`servicios.sh stop matriculas-service`).

#### Paso 8 — Con matriculas-service detenido: DELETE /api/cursos/1

**Esperado:** 502 No fue posible verificar las matrículas del curso… · **Obtenido:** HTTP 502

```http
DELETE http://localhost:8083/api/cursos/1
Authorization: Bearer <token de admin>
```

```json
{
  "success": false,
  "message": "No fue posible verificar las matrículas del curso (código remoto -1)",
  "data": null
}
```

#### Paso 8b — GET /api/cursos/1 (comprobar que el curso sigue existiendo)

**Esperado:** 200 · **Obtenido:** HTTP 200

```http
GET http://localhost:8083/api/cursos/1
Authorization: Bearer <token de admin>
```

```json
{
  "success": true,
  "message": "OK",
  "data": {
    "id": 1,
    "codigo": "IS3-001",
    "nombre": "Ingeniería de Software III",
    "descripcion": "Arquitectura y microservicios",
    "creditos": 4,
    "docenteResponsable": "Docente principal",
    "cupoMaximo": 30
  }
}
```

