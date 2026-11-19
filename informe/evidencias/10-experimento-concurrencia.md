### Experimento adicional · Condición de carrera en el cupo (E2, pregunta 2)

Se crea un curso con cupoMaximo 1 y se envían 20 POST /api/matriculas **en paralelo** (estudiantes 10 a 29).

#### Paso A — Crear curso de prueba con cupo 1

**Esperado:** 201 · **Obtenido:** HTTP 201

```http
POST http://localhost:8083/api/cursos
Authorization: Bearer <token de admin>
Content-Type: application/json

{"codigo":"CONC-001","nombre":"Concurrencia","creditos":1,"docenteResponsable":"Docente","cupoMaximo":1}
```

```json
{
  "success": true,
  "message": "Curso creado",
  "data": {
    "id": 4,
    "codigo": "CONC-001",
    "nombre": "Concurrencia",
    "descripcion": null,
    "creditos": 1,
    "docenteResponsable": "Docente",
    "cupoMaximo": 1
  }
}
```

#### Paso B — Conteo de matrículas activas del curso 4

**Esperado:** Si la regla fuera atómica: 1 · **Obtenido:** HTTP 200

```http
GET http://localhost:8084/api/matriculas/activas/conteo?cursoId=4
Authorization: Bearer <token de admin>
```

```json
{
  "success": true,
  "message": "OK",
  "data": 1
}
```

Códigos HTTP de las 20 peticiones paralelas (cantidad · código):

```
      1 201
     19 400
```

#### Repetición con mayor paralelismo (45 peticiones simultáneas por ronda, `xargs -P45`)

Cada ronda crea un curso nuevo con `cupoMaximo: 1` y envía 45 matrículas simultáneas (estudiantes 1 a 45):

| Ronda | Curso | 201 Created | 400 | Matrículas activas (conteo) |
|---|---|---|---|---|
| 1 | 5 | 1 | 44 | 1 |
| 2 | 6 | 2 | 43 | 2 |
| 3 | 7 | 1 | 44 | 1 |
| 4 | 8 | 3 | 42 | 3 |
| 5 | 9 | 1 | 44 | 1 |

**Resultado:** en las rondas 2 y 4 el curso quedó con 2 y 3 matrículas activas a pesar de tener cupo 1. La condición de carrera es real (ver la respuesta a la pregunta 2 de E2).

