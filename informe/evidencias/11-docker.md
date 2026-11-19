### Evidencias · Docker, Swagger y pruebas

Con Docker 29.9.3 (modo rootless) y Compose v5.7.1.

#### Paso 1 — docker compose ps

**Esperado:** cinco servicios en estado running

```
NAME                     IMAGE                                STATE     STATUS          PORTS
auth-service             proyecto-s3-auth-service             running   Up 48 seconds   0.0.0.0:8081->8081/tcp, [::]:8081->8081/tcp
calificaciones-service   proyecto-s3-calificaciones-service   running   Up 44 seconds   0.0.0.0:8085->8085/tcp, [::]:8085->8085/tcp
cursos-service           proyecto-s3-cursos-service           running   Up 47 seconds   0.0.0.0:8083->8083/tcp, [::]:8083->8083/tcp
estudiantes-service      proyecto-s3-estudiantes-service      running   Up 47 seconds   0.0.0.0:8082->8082/tcp, [::]:8082->8082/tcp
matriculas-service       proyecto-s3-matriculas-service       running   Up 46 seconds   0.0.0.0:8084->8084/tcp, [::]:8084->8084/tcp
```

#### Paso 2 — Swagger de cada servicio (contenedores)

- http://localhost:8081/swagger-ui.html → HTTP 200 · captura en la sección 12.1 del informe
- http://localhost:8082/swagger-ui.html → HTTP 200 · captura en la sección 12.1 del informe
- http://localhost:8083/swagger-ui.html → HTTP 200 · captura en la sección 12.1 del informe
- http://localhost:8084/swagger-ui.html → HTTP 200 · captura en la sección 12.1 del informe
- http://localhost:8085/swagger-ui.html → HTTP 200 · captura en la sección 12.1 del informe

#### Paso 3 — Login como admin (8081) y POST /api/matriculas (8084) con {estudianteId:1, cursoId:1}

**Esperado:** 201: los servicios se comunican por la red de Docker · **Obtenido:** HTTP 201

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
    "id": 1,
    "estudianteId": 1,
    "cursoId": 1,
    "fechaMatricula": "2026-11-12",
    "estado": "ACTIVA"
  }
}
```

#### Paso 3b — GET /api/matriculas antes del reinicio

**Esperado:** 1 matrícula · **Obtenido:** HTTP 200

```http
GET http://localhost:8084/api/matriculas
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
    "totalPages": 1,
    "totalElements": 1,
    "last": true,
    "size": 20,
    "number": 0,
    "sort": [],
    "first": true,
    "numberOfElements": 1,
    "empty": false
  }
}
```

#### Paso 4 — docker compose logs matriculas-service

**Esperado:** los registros de arranque y de la petición (extracto)

```
matriculas-service  | 2026-11-12T22:52:54.621Z  INFO 1 --- [           main] c.e.m.MatriculasServiceApplication       : Starting MatriculasServiceApplication v0.0.1-SNAPSHOT using Java 21.0.13 with PID 1 (/app/app.jar started by root in /app)
matriculas-service  | 2026-11-12T22:53:08.375Z  INFO 1 --- [           main] o.apache.catalina.core.StandardService   : Starting service [Tomcat]
matriculas-service  | 2026-11-12T22:53:08.376Z  INFO 1 --- [           main] o.apache.catalina.core.StandardEngine    : Starting Servlet engine: [Apache Tomcat/10.1.20]
matriculas-service  | 2026-11-12T22:53:08.597Z  INFO 1 --- [           main] o.a.c.c.C.[Tomcat].[localhost].[/]       : Initializing Spring embedded WebApplicationContext
matriculas-service  | 2026-11-12T22:53:09.006Z  INFO 1 --- [           main] com.zaxxer.hikari.HikariDataSource       : HikariPool-1 - Starting...
matriculas-service  | 2026-11-12T22:53:27.234Z  INFO 1 --- [           main] o.s.b.w.embedded.tomcat.TomcatWebServer  : Tomcat started on port 8084 (http) with context path ''
matriculas-service  | 2026-11-12T22:53:27.384Z  INFO 1 --- [           main] c.e.m.MatriculasServiceApplication       : Started MatriculasServiceApplication in 36.407 seconds (process running for 39.5)
matriculas-service  | 2026-11-12T22:53:30.125Z  INFO 1 --- [nio-8084-exec-1] o.a.c.c.C.[Tomcat].[localhost].[/]       : Initializing Spring DispatcherServlet 'dispatcherServlet'
matriculas-service  | 2026-11-12T22:53:30.125Z  INFO 1 --- [nio-8084-exec-1] o.s.web.servlet.DispatcherServlet        : Initializing Servlet 'dispatcherServlet'
matriculas-service  | 2026-11-12T22:53:30.130Z  INFO 1 --- [nio-8084-exec-1] o.s.web.servlet.DispatcherServlet        : Completed initialization in 4 ms
```

Observación: matriculas-service tiene `show-sql: false` y ningún componente registra las peticiones, así que la petición del paso 3 **no deja una línea propia** en el log. La única huella de tráfico es la inicialización perezosa del `DispatcherServlet` (`Initializing Servlet 'dispatcherServlet'`), que ocurre con la primera petición HTTP que recibe el contenedor (aquí, la sonda a `/v3/api-docs` que espera a que el servicio esté listo). Para tener trazas por petición habría que activar, por ejemplo, `logging.level.org.springframework.web=DEBUG` o los access logs de Tomcat.

#### Paso 5 — docker compose restart matriculas-service y GET /api/matriculas

**Esperado:** Lista vacía: H2 en memoria pierde los datos al reiniciar · **Obtenido:** HTTP 200

```http
GET http://localhost:8084/api/matriculas
Authorization: Bearer <token de admin>
```

```json
{
  "success": true,
  "message": "OK",
  "data": {
    "content": [],
    "pageable": {
      "pageNumber": 0,
      "pageSize": 20,
      "sort": [],
      "offset": 0,
      "paged": true,
      "unpaged": false
    },
    "last": true,
    "totalPages": 0,
    "totalElements": 0,
    "size": 20,
    "number": 0,
    "sort": [],
    "first": true,
    "numberOfElements": 0,
    "empty": true
  }
}
```

#### Paso 6 — mvn test en los cinco servicios

**Esperado:** 27 pruebas, 0 fallos

```
== auth-service
[INFO] Tests run: 4, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
== estudiantes-service
[INFO] Tests run: 3, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
== cursos-service
[INFO] Tests run: 4, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
== matriculas-service
[INFO] Tests run: 8, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
== calificaciones-service
[INFO] Tests run: 8, Failures: 0, Errors: 0, Skipped: 0
[INFO] BUILD SUCCESS
```

Total: 4 + 3 + 4 + 8 + 8 = **27 pruebas, 0 fallos, 0 errores**.

#### Paso 7 — docker compose down

**Esperado:** los contenedores se detienen y se eliminan

```
 Container calificaciones-service Stopping 
 Container calificaciones-service Stopped 
 Container calificaciones-service Removing 
 Container calificaciones-service Removed 
 Container matriculas-service Stopping 
 Container matriculas-service Stopped 
 Container matriculas-service Removing 
 Container matriculas-service Removed 
 Container estudiantes-service Stopping 
 Container cursos-service Stopping 
 Container estudiantes-service Stopped 
 Container estudiantes-service Removing 
 Container cursos-service Stopped 
 Container cursos-service Removing 
 Container estudiantes-service Removed 
 Container cursos-service Removed 
 Container auth-service Stopping 
 Container auth-service Stopped 
 Container auth-service Removing 
 Container auth-service Removed 
 Network proyecto-s3_default Removing 
 Network proyecto-s3_default Removed 

$ docker compose ps
NAME      IMAGE     COMMAND   SERVICE   CREATED   STATUS    PORTS
```

