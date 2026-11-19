# Informe de análisis · Proyecto final guiado (Ingeniería de Software III)

**Plataforma académica de microservicios:** auth, estudiantes, cursos, matrículas y calificaciones

**Estudiantes:** Janer Vega, Oscar Gamboa y Kevin Malagon

**Repositorio:** `proyecto-s3` (commit base `bedab2c`)

**Entorno:** Linux (Fedora), OpenJDK Temurin 21.0.13, Maven 3.9.16, Docker 29.9.3 en modo rootless, Docker Compose v5.7.1

## Contenido

1. [Resumen de la ejecución](#1-resumen-de-la-ejecución)
2. [Arquitectura del sistema (diagrama propio)](#2-arquitectura-del-sistema-diagrama-propio)
3. [Seguridad](#3-seguridad)
4. [auth-service](#4-auth-service)
5. [estudiantes-service](#5-estudiantes-service)
6. [cursos-service](#6-cursos-service)
7. [matriculas-service](#7-matriculas-service)
8. [Extensión E2 · Cupos](#8-extensión-e2--cupos)
9. [Extensión E1 · Integridad entre servicios](#9-extensión-e1--integridad-entre-servicios)
10. [Extensión E4 · Mis matrículas](#10-extensión-e4--mis-matrículas)
11. [Extensión E3 · Calificaciones](#11-extensión-e3--calificaciones)
12. [Docker, Swagger y pruebas](#12-docker-swagger-y-pruebas)
13. [Propuesta de mejora: cupo garantizado bajo concurrencia](#13-propuesta-de-mejora-cupo-garantizado-bajo-concurrencia)
14. [Otros hallazgos y riesgos](#14-otros-hallazgos-y-riesgos)
- [Anexo A · Cómo reproducir las evidencias](#anexo-a--cómo-reproducir-las-evidencias)
- [Anexo B · Evidencias completas](#anexo-b--evidencias-completas)

---

## 1. Resumen de la ejecución

| Checklist final | Estado | Evidencia |
|---|---|---|
| El sistema se ejecutó en local y con Docker Compose | ✅ | Secciones 3–11 (local) y 12 (Docker) |
| `mvn test` pasa en los cinco servicios (27 pruebas) | ✅ 27/27, 0 fallos | [Anexo B.11 · Docker, Swagger y pruebas](#b11--docker-swagger-y-pruebas) (paso 6) |
| Verificación de las diez guías, con evidencias | ✅ 90 pasos, todos con el resultado esperado | [Anexo B](#anexo-b--evidencias-completas) |
| Preguntas de análisis respondidas citando el código | ✅ 49 preguntas | Secciones 3–12 |
| Diagrama propio de la arquitectura | ✅ | Sección 2 |
| Propuesta de mejora justificada | ✅ (con experimento que demuestra el riesgo) | Sección 13 |

**Pruebas automatizadas (`mvn test`):**

| Servicio | Clases de prueba | Pruebas | Fallos |
|---|---|---|---|
| auth-service | `JwtUtilsTest` (2), `AuthFlowIntegrationTest` (2) | 4 | 0 |
| estudiantes-service | `EstudianteServiceImplTest` | 3 | 0 |
| cursos-service | `CursoServiceImplTest` | 4 | 0 |
| matriculas-service | `MatriculaServiceImplTest` (4), `MatriculaControllerSecurityTest` (4) | 8 | 0 |
| calificaciones-service | `CalificacionServiceImplTest` | 8 | 0 |
| **Total** | | **27** | **0** |

**Orden de ejecución y datos de partida.** Como las bases H2 están en memoria, las verificaciones se hicieron en cuatro fases:

1. **Fase 1** (servicios recién iniciados): seguridad 1–8, auth, estudiantes, cursos y matrículas 1–9.
2. **Fase 2** (servicios reiniciados, datos limpios): extensiones E2 → E1 (1–7) → E4 → E3, y el experimento de concurrencia.
3. **Fase 3** (al final, deteniendo servicios): matrículas 10 (estudiantes caído), E1 8 (matrículas caído) y seguridad 9 (auth caído).
4. **Fase 4**: guía de Docker con `docker compose`.

Las peticiones se hicieron con `curl` contra las mismas rutas que expone Swagger. Las capturas de la interfaz Swagger de cada servicio están en la [sección 12.1](#121-verificación).

---

## 2. Arquitectura del sistema (diagrama propio)

### 2.1 Servicios, dependencias y flujo del token

![Arquitectura: servicios, dependencias y flujo del token](diagramas/arquitectura.svg)

Lectura del diagrama:

- **Línea negra gruesa:** el cliente envía el JWT en el encabezado `Authorization: Bearer …` a los cuatro servicios de negocio.
- **Línea punteada gris (hacia auth):** autenticación. Los cuatro servicios de negocio llaman a `GET /auth/validate` en **cada** petición desde su `AuthValidationFilter`. Solo auth-service conoce el secreto del JWT.
- **Líneas azules (continuas) y naranjas (punteadas):** dependencias de negocio por OpenFeign. Las naranjas son las que agregó E1/E2 y cierran los ciclos. Todas viajan con el **mismo token del usuario**, reenviado por `FeignAuthPropagationConfig`, así que cada servicio remoto vuelve a aplicar sus reglas de rol.
- **Ciclos:** `estudiantes ⇄ matrículas` y `cursos ⇄ matrículas`, introducidos por E1 y E2 (ver §9).
- Cada servicio tiene su propia base H2 en memoria (*database per service*). No hay llaves foráneas entre servicios: matrículas guarda solo `estudianteId` y `cursoId`, y calificaciones guarda solo `matriculaId`.

### 2.2 Recorrido de una petición protegida que cruza servicios

```mermaid
sequenceDiagram
    autonumber
    actor U as ADMIN
    participant M as matriculas-service
    participant A as auth-service
    participant E as estudiantes-service
    participant C as cursos-service
    U->>M: POST /api/matriculas (Bearer JWT)
    M->>A: GET /auth/validate (JWT)
    A-->>M: {valid, username, role: ADMIN, estudianteId}
    Note over M: SecurityConfig: POST /api/matriculas/** → ADMIN ✔
    M->>E: GET /api/estudiantes/2 (JWT propagado)
    E->>A: GET /auth/validate (JWT)
    A-->>E: role ADMIN
    E-->>M: 200 {data: estudiante}
    M->>C: GET /api/cursos/2 (JWT propagado)
    C->>A: GET /auth/validate (JWT)
    A-->>C: role ADMIN
    C-->>M: 200 {data: curso con cupoMaximo}
    Note over M: duplicado activo? → cupo (E2)? → save
    M-->>U: 201 {data: matrícula ACTIVA}
```

### 2.3 Capas dentro de cada servicio

```
HTTP ─► [Filtro de seguridad] ─► Controller ─► Handler ─► Service ─► Repository ─► Model (JPA/H2)
          AuthValidationFilter     @Valid DTO    DTO ⇄ entidad  reglas de     Spring Data
          + SecurityConfig         ResponseBuilder              negocio,      derived queries
                                                                Feign clients
        ◄──────────────── GlobalExceptionHandler traduce excepciones a {success, message, data} ◄─────
```

| Capa | Responsabilidad | Ejemplo (estudiantes) |
|---|---|---|
| Controller | Ruta HTTP, `@Valid` del DTO de entrada y envoltura `ApiResponse` | `EstudianteController.java:27-30` |
| Handler | Traducir DTO ⇄ entidad; aísla al servicio del contrato HTTP | `EstudianteHandler.java:21-28, 51-59` |
| Service | Reglas de negocio, transacciones y llamadas remotas | `EstudianteServiceImpl.java:29-35, 63-72` |
| Repository | Acceso a datos con consultas derivadas | `EstudianteRepository.java:7-8` |
| Model | Entidad JPA y restricciones de BD | `Estudiante.java:6-8` (UK email) |

---

## 3. Seguridad

### 3.1 Verificación

Tokens de `admin/admin123`, `docente/docente123` y `estudiante/estudiante123`, contra cursos (8083) salvo que se indique otro servicio.

| # | Petición | Esperado | Obtenido | Respuesta (resumen) |
|---|---|---|---|---|
| 1 | GET /api/cursos/1 sin autorizar | 401 AUTH_HEADER_MISSING | HTTP 401 ✅ | `AUTH_HEADER_MISSING` · Debe enviar un token Bearer válido |
| 2 | GET /api/cursos/1 con un token inventado | 401 TOKEN_INVALID | HTTP 401 ✅ | `TOKEN_INVALID` · El token no es válido o expiró |
| 3 | DOCENTE: POST /api/cursos | 403 AUTH_FORBIDDEN | HTTP 403 ✅ | `AUTH_FORBIDDEN` · No tiene permisos para acceder a este recurso |
| 4 | ESTUDIANTE: GET /api/cursos | 200 | HTTP 200 ✅ | OK · totalElements=3, en página=3 |
| 5 | ESTUDIANTE: GET /api/estudiantes (8082) | 403 | HTTP 403 ✅ | `AUTH_FORBIDDEN` · No tiene permisos para acceder a este recurso |
| 6 | GET /v3/api-docs sin token | 200 | HTTP 200 ✅ | OpenAPI 3.0.1, 2 rutas |
| 7 | ADMIN: POST /api/matriculas (8084) con {estudianteId:2, cursoId:2} | 201: el token se propagó a estudiantes y cursos | HTTP 201 ✅ | Matrícula registrada · id=1, estado=ACTIVA |
| 8 | Consola H2 de auth (jdbc:h2:mem:authdb): SELECT * FROM usuarios | contraseñas con formato `$2a$10$…` (BCrypt) | — ✅ | ver tabla en la evidencia |
| 9 | Con auth-service detenido: ESTUDIANTE GET /api/cursos | 401 TOKEN_VALIDATION_ERROR | HTTP 401 ✅ | `TOKEN_VALIDATION_ERROR` · No fue posible validar el token con auth-service |

Evidencia completa (petición y respuesta JSON de cada paso): [Anexo B.1 · Seguridad](#b1--seguridad)

### 3.2 Preguntas de análisis

**1. ¿Por qué la petición 3 (DOCENTE: `POST /api/cursos`) devuelve 403 y no 401?**

Porque la identidad del docente **sí** queda establecida y lo que falla es el permiso:

1. `AuthValidationFilter` (`cursos-service/…/security/AuthValidationFilter.java:44-48`) encuentra el encabezado `Bearer`. auth-service valida la firma y responde `role: "DOCENTE"` (líneas 51-52). Como la respuesta es válida y trae rol (61-64), el filtro guarda en el `SecurityContext` un `UsernamePasswordAuthenticationToken` con la autoridad `DOCENTE` (66-71) y continúa la cadena (74). Ningún `reject(...)` se ejecuta, así que no hay 401.
2. Después, el `AuthorizationFilter` de Spring evalúa las reglas de `SecurityConfig` (`cursos-service/…/config/SecurityConfig.java:42`): `POST /api/cursos/**` exige `hasAuthority("ADMIN")`. El usuario está autenticado pero sin esa autoridad, así que Spring lanza `AccessDeniedException`. `ExceptionTranslationFilter` la entrega al `accessDeniedHandler` configurado en la línea 36, que es `CustomAccessDeniedHandler` y responde `403 AUTH_FORBIDDEN`.

La regla general es esta: 401 significa "no sé quién eres" y lo producen el filtro o el `CustomAuthenticationEntryPoint`. 403 significa "sé quién eres, pero no puedes hacer esto" y lo produce `CustomAccessDeniedHandler`. La evidencia de los pasos 1, 2 y 3 muestra los tres códigos distintos: `AUTH_HEADER_MISSING`, `TOKEN_INVALID` y `AUTH_FORBIDDEN`.

**2. Cada petición genera otra a auth-service. Ventajas, costos y qué cambiaría con validación local.**

| | Validación centralizada (actual) | Validación local con el secreto |
|---|---|---|
| Secreto | Solo lo conoce auth-service (`application.yaml:25`). Menor superficie de fuga | Debe distribuirse a los 5 servicios. Con HS256, quien puede validar también puede **firmar** tokens |
| Lógica | Un solo lugar decide qué es un token válido (`AuthServiceImpl.validate`, `:43-60`) | Se duplica en cada servicio, con riesgo de que diverjan (versiones de jjwt, *clock skew*) |
| Revocación | Se podría añadir una lista de revocación o comprobar el usuario en BD en un solo lugar | Un token es válido hasta su `exp` salvo que se agregue infraestructura extra |
| Latencia | +1 *round-trip* HTTP por petición, y más en cadena: registrar una matrícula provoca **3** validaciones (§7, P1) | Validación en memoria (microsegundos) |
| Disponibilidad | auth-service es un **punto único de fallo**: si cae, todo responde `401 TOKEN_VALIDATION_ERROR` (seguridad, paso 9) | Los servicios siguen atendiendo tokens ya emitidos aunque auth esté caído (solo falla el login) |
| Carga | auth-service recibe tráfico proporcional a todo el sistema | auth solo atiende logins |

Si se valida localmente, lo recomendable es firmar con **clave asimétrica (RS256/ES256)**: auth firma con la clave privada y los demás servicios verifican con la pública (por ejemplo, publicada en un endpoint JWKS). Spring lo soporta con `spring-boot-starter-oauth2-resource-server`. La revocación se mitiga con tokens de vida corta y *refresh tokens*. Una opción intermedia es mantener la llamada a `/auth/validate` y guardar su resultado en caché unos segundos.

**3. ¿Qué información no debería ir nunca dentro del JWT?**

Nada que sea secreto o sensible: contraseñas o hashes, datos personales (documento, correo, teléfono, notas), secretos de API, datos de salud o financieros, ni detalles internos de infraestructura. El JWT está firmado, **no cifrado**: el payload es Base64URL. La evidencia del paso 8 de auth incluye el payload del token de estudiante decodificado **sin el secreto**: `{"sub":"estudiante","role":"ESTUDIANTE","iat":…,"exp":…,"estudianteId":1}`. Además, el token viaja en cada petición y queda en logs, historiales y almacenamiento del navegador. El proyecto solo incluye identificadores y rol (`JwtUtils.java:30-38`), que es lo correcto. Si hiciera falta transportar datos confidenciales se usaría JWE, pero la práctica habitual es mandar solo un identificador y consultar el resto en el servidor.

**4. ¿Qué pasaría si se publicara `app.jwt.secret`? ¿Cómo protegerlo?**

**Ya está publicado**: `auth-service/src/main/resources/application.yaml:25` contiene `secret: 12345678901234567890123456789012` y el archivo está versionado en Git. Con HS256, cualquiera que conozca el secreto puede **fabricar** un token válido con `role: ADMIN` o con cualquier `estudianteId`. auth-service lo validaría (`JwtUtils.parseToken`, `:42-44`) y el atacante tendría control total del sistema: suplantación, escalamiento de privilegios y anulación de E4. Es aceptable en un proyecto académico, pero en producción habría que:

- Sacar el secreto del repositorio e inyectarlo por variable de entorno (`app.jwt.secret: ${JWT_SECRET}`, sin valor por defecto) o desde un gestor de secretos (Vault, AWS Secrets Manager, Docker/Kubernetes secrets).
- Generarlo aleatorio y largo (≥ 256 bits de entropía real; el actual es predecible) y **rotarlo**. Si alguna vez se publicó, se cambia y todos los tokens emitidos quedan inválidos.
- Purgar el historial de Git si el secreto real llegó a subirse, y agregar escáneres de secretos al CI (gitleaks, GitHub secret scanning).
- Preferir firma asimétrica (RS256), con la que la clave privada vive solo en auth-service.

**5. ¿Por qué `filterChain.doFilter` debe quedar fuera del `try` del filtro?**

El `try` (`AuthValidationFilter.java:51-59`) captura `FeignException` para traducir los fallos de la validación del token a 401. Con `filterChain.doFilter` dentro de ese `try`, también se capturaría cualquier `FeignException` lanzada **después**, en el controlador o el servicio, y se convertiría en un falso 401.

Ejemplo concreto: matriculas-service registra una matrícula y `EstudiantesClient.buscarPorId` falla porque estudiantes-service está caído, lo que produce una `FeignException` (`RetryableException`) desde `MatriculaServiceImpl.obtenerRemoto`. Hoy `obtenerRemoto` la traduce a `RemoteServiceException` y el `GlobalExceptionHandler` responde **502** (paso 10 de matrículas). Basta con que un método nuevo olvide ese `try/catch` y deje escapar la `FeignException`: con `doFilter` dentro del `try`, la excepción subiría por la cadena de filtros hasta el `catch (FeignException ex)` del filtro, y el usuario recibiría `401 TOKEN_VALIDATION_ERROR` "No fue posible validar el token con auth-service". El cliente pensaría que su sesión expiró, volvería a hacer login y el error persistiría: se oculta un problema de disponibilidad de otro servicio. Además, el filtro intentaría escribir un 401 sobre una respuesta que quizá ya se había empezado a enviar. Dejar `doFilter` fuera del `try` (línea 74, con el comentario de la 73) restringe el manejo del filtro **solo** a la autenticación.

---

## 4. auth-service

### 4.1 Verificación

| # | Petición | Esperado | Obtenido | Respuesta (resumen) |
|---|---|---|---|---|
| 1 | POST /auth/login con admin / admin123 | 200 con token, username y role | HTTP 200 ✅ | token emitido, role=ADMIN |
| 2 | Login con contraseña incorrecta | 401 AUTH_INVALID_CREDENTIALS | HTTP 401 ✅ | `AUTH_INVALID_CREDENTIALS` · Credenciales inválidas |
| 2b | Login con usuario inexistente | 401 AUTH_INVALID_CREDENTIALS, mismo mensaje que el paso 2 | HTTP 401 ✅ | `AUTH_INVALID_CREDENTIALS` · Credenciales inválidas |
| 3 | Login con cuerpo {} | 400 VALIDATION_ERROR | HTTP 400 ✅ | `VALIDATION_ERROR` · Error de validación |
| 4 | GET /auth/validate con token de admin | 200, valid: true, role: ADMIN | HTTP 200 ✅ | valid=true, role=ADMIN, estudianteId=null |
| 5 | GET /auth/validate con token de estudiante | estudianteId: 1 | HTTP 200 ✅ | valid=true, role=ESTUDIANTE, estudianteId=1 |
| 6 | GET /auth/validate sin autorizar | 401 AUTH_INVALID_TOKEN | HTTP 401 ✅ | `AUTH_INVALID_TOKEN` · Debe enviar un token Bearer válido |
| 7 | GET /auth/validate con el token alterado (una letra del payload cambiada) | 401 AUTH_INVALID_TOKEN | HTTP 401 ✅ | `AUTH_INVALID_TOKEN` · Token inválido o expirado |
| 8 | Consola H2 (jdbc:h2:mem:authdb): SELECT * FROM usuarios | contraseñas cifradas y estudiante_id = 1 solo para el estudiante | — ✅ |  |

Evidencia completa (petición y respuesta JSON de cada paso): [Anexo B.2 · auth-service](#b2--auth-service)

Resultado de la consola H2 (paso 8), extraído de la evidencia: las tres contraseñas tienen formato `$2a$10$…` (BCrypt, costo 10), y solo el usuario `estudiante` tiene `ESTUDIANTE_ID = 1`.

### 4.2 Preguntas de análisis

**1. ¿Por qué el login responde el mismo mensaje si el usuario no existe y si la contraseña es incorrecta?**

Para evitar la **enumeración de usuarios**. En `AuthServiceImpl.java:31-36` ambos casos lanzan `InvalidCredentialsException("Credenciales inválidas")`, que el `GlobalExceptionHandler` (`:24-37`) traduce al mismo `401 AUTH_INVALID_CREDENTIALS`. Los pasos 2 y 2b de la evidencia lo confirman: el usuario inexistente y la contraseña errada dan respuestas idénticas. Si los mensajes fueran distintos, un atacante podría averiguar qué usuarios existen y concentrar en ellos ataques de diccionario o de *credential stuffing*. Queda un canal lateral: cuando el usuario no existe no se ejecuta BCrypt, así que la respuesta es más rápida y la diferencia de tiempo delata la existencia del usuario. Se mitiga comparando contra un hash ficticio en ese caso.

**2. BCrypt genera un hash distinto cada vez. ¿Cómo verifica `matches`?**

Porque el hash **incluye su propia sal y su costo**. Un hash como `$2a$10$VX8RUxhhNCbNhBoe7SNbpO…` se lee así: `2a` es la versión del algoritmo, `10` es el costo (2¹⁰ rondas), los 22 caracteres siguientes son la **sal** aleatoria y el resto es el hash. `encode` genera una sal nueva en cada llamada (`DataSeeder.java:27`), por eso dos codificaciones de "admin123" difieren. `passwordEncoder.matches(raw, hash)` (`AuthServiceImpl.java:34`) **extrae la sal y el costo del hash guardado**, vuelve a calcular BCrypt de la contraseña recibida con esos mismos parámetros y compara el resultado en tiempo constante. Nunca se "descifra" nada. La sal impide usar tablas precalculadas (*rainbow tables*) y que dos usuarios con la misma contraseña tengan el mismo hash.

**3. ¿Qué sucede con un token ya emitido si el administrador cambia el rol del usuario?**

El token sigue llevando el rol **viejo** hasta su expiración (1 hora, `application.yaml:26`). `validate` (`AuthServiceImpl.java:43-60`) solo verifica la firma y la expiración y devuelve el `role` del *claim*, sin consultar la tabla `usuarios`. Así, un usuario degradado de ADMIN seguiría operando como ADMIN durante hasta 60 minutos. Soluciones posibles:

- Como la validación ya es centralizada, `validate` podría **releer al usuario** en BD con `findByUsername(sub)` y devolver el rol actual. Así el cambio aplica de inmediato, al costo de una consulta por validación (que se puede cachear brevemente).
- Guardar una `tokenVersion` en `Usuario`, incluirla en el JWT y rechazar el token si no coincide. Cambiar el rol incrementa la versión.
- Mantener una lista de revocación (por `jti`) en Redis.
- Usar *access tokens* de vida corta (5-15 min) con *refresh token*, de modo que el rol se actualiza en la siguiente renovación.

**4. `/auth/validate` responde 401 ante cualquier falla. ¿Qué se pierde y por qué podría ser intencional?**

El `catch (Exception ex)` de `AuthServiceImpl.java:57-59` agrupa todas las causas (`ExpiredJwtException`, `SignatureException`, `MalformedJwtException`, `UnsupportedJwtException`, etc.) en "Token inválido o expirado". Se pierde la causa exacta: el cliente no sabe si debe **renovar** el token (expirado) o si el token fue **manipulado** (firma inválida), y el equipo de operación no puede distinguir intentos de ataque de sesiones vencidas. La decisión puede ser intencional por seguridad: no se le da información a un atacante que fabrica tokens. Si el sistema dijera "firma inválida" frente a "formato inválido", el atacante sabría qué parte de su falsificación funciona. También simplifica a los clientes, para los que cualquier fallo significa volver a autenticarse. Lo recomendable es mantener la respuesta genérica hacia afuera y **registrar la causa en el log** del servidor. Una excepción razonable sería distinguir solo "expirado", que no da ventaja al atacante y le permite al cliente renovar el token automáticamente.

---

## 5. estudiantes-service

### 5.1 Verificación

| # | Petición | Esperado | Obtenido | Respuesta (resumen) |
|---|---|---|---|---|
| 1 | GET /api/estudiantes?page=0&size=5 | 200, 5 estudiantes y totalElements: 50 | HTTP 200 ✅ | OK · totalElements=50, en página=5 |
| 2 | GET /api/estudiantes/999 | 404 Estudiante no encontrado: 999 | HTTP 404 ✅ | Estudiante no encontrado: 999 |
| 3 | POST estudiante Ana Ruiz | 201 | HTTP 201 ✅ | Estudiante creado |
| 4 | Repetir el paso 3 | 400 Ya existe un estudiante con el email… | HTTP 400 ✅ | Ya existe un estudiante con el email: ana.ruiz@correo.edu |
| 5 | POST con email no-es-correo y edad 0 | 400 Error de validación con ambos campos | HTTP 400 ✅ | Error de validación |
| 6 | PUT /api/estudiantes/2 con el correo del estudiante 3 | 400 Ya existe otro estudiante con el email… | HTTP 400 ✅ | Ya existe otro estudiante con el email: estudiante2@demoacademico.edu |
| 7a | DOCENTE: GET /api/estudiantes/1 | 200 | HTTP 200 ✅ | OK |
| 7b | DOCENTE: POST /api/estudiantes | 403 | HTTP 403 ✅ | `AUTH_FORBIDDEN` · No tiene permisos para acceder a este recurso |
| 8 | ESTUDIANTE: GET /api/estudiantes/1 | 403 | HTTP 403 ✅ | `AUTH_FORBIDDEN` · No tiene permisos para acceder a este recurso |
| 9 | GET /api/estudiantes/abc | 400 Solicitud inválida… (no 401) | HTTP 400 ✅ | Solicitud inválida: revise los parámetros de la URL y el formato del JSON |

Evidencia completa (petición y respuesta JSON de cada paso): [Anexo B.3 · estudiantes-service](#b3--estudiantes-service)

En el paso 5 la respuesta incluye `data: {"email": "El email no es válido", "edad": "La edad mínima es 1"}`: ambos campos se reportan en la misma respuesta.

### 5.2 Preguntas de análisis

**1. Recorrido de `POST /api/estudiantes`, clase por clase.**

| # | Clase | Responsabilidad |
|---|---|---|
| 1 | `AuthValidationFilter` (`…/security/AuthValidationFilter.java:39-75`) | Exige `Bearer`, valida el token con auth-service mediante `AuthClient` (Feign) y pone usuario y rol en el `SecurityContext`. Si falla, delega en `CustomAuthenticationEntryPoint` y responde 401 |
| 2 | `SecurityConfig` (`…/config/SecurityConfig.java:42`) | Regla `POST /api/estudiantes/** → hasAuthority("ADMIN")`. Si no se cumple, `CustomAccessDeniedHandler` responde 403 |
| 3 | `EstudianteController.crear` (`…/controller/EstudianteController.java:27-30`) | Deserializa el JSON en `EstudianteCreateDTO` y dispara `@Valid` con las anotaciones de `EstudianteCreateDTO.java:10-22`. Si la validación falla, `MethodArgumentNotValidException` → `GlobalExceptionHandler.handleValidation` (`:50-58`) → 400 |
| 4 | `EstudianteHandler.crear` (`…/handler/EstudianteHandler.java:21-28`) | Convierte el DTO en la entidad `Estudiante` y luego el resultado en `EstudianteDTO` (`toDto`, `:51-59`) |
| 5 | `EstudianteServiceImpl.crear` (`…/service/EstudianteServiceImpl.java:29-35`) | Regla de negocio: correo único (`existsByEmail`). Si ya existe → `BusinessException` → 400. Es `@Transactional` (línea 18) |
| 6 | `EstudianteRepository` (`…/repository/EstudianteRepository.java:7`) | `existsByEmail` y `save`, implementados por Spring Data JPA |
| 7 | `Estudiante` (`…/model/Estudiante.java:6-25`) | Entidad JPA con `uk_estudiante_email` como respaldo en la BD |
| 8 | `ResponseBuilder.created` (`…/api/ResponseBuilder.java`) | Envuelve la respuesta en `ApiResponse{success, message, data}` con estado 201 |

**2. El correo único se valida en el servicio y en la BD. ¿Cuándo no basta la validación del servicio?**

Bajo **concurrencia**: dos `POST` simultáneos con el mismo correo ejecutan `existsByEmail` (`EstudianteServiceImpl.java:31`) antes de que alguno haga `save`. Ambos ven `false` y ambos intentan insertar (es una condición de carrera *check-then-act*). Ahí solo la restricción `uk_estudiante_email` (`Estudiante.java:6-8`) impide el duplicado: el segundo `INSERT` falla con `DataIntegrityViolationException`, que el `GlobalExceptionHandler` traduce a **409** "La operación viola una restricción de datos" (`:66-70`). La restricción también protege frente a escrituras que no pasan por el servicio (scripts SQL, la consola H2, migraciones u otro proceso). La validación del servicio sirve para dar un mensaje claro en el caso normal, y la de la BD garantiza la integridad en todos los casos.

**3. ¿Qué se gana y qué se pierde si el controlador recibiera y devolviera la entidad `Estudiante`?**

*Se ganaría* menos código (sin DTOs ni handler) y menos mapeo manual.

*Se perdería:*

- El **desacoplamiento del contrato HTTP y del modelo de datos**. Cualquier cambio en la tabla, como agregar un campo interno, cambiaría la API pública y rompería a los clientes. matriculas-service, por ejemplo, deserializa `EstudianteRemotoDTO`.
- **Protección contra *mass assignment***. El cliente podría enviar `id` y sobrescribir otro registro al hacer `save`, o fijar campos que no debería controlar.
- **Validación por caso de uso**. Las anotaciones `@Valid` quedarían en la entidad y se mezclarían con las de JPA.
- **Control de lo que se expone**. Con relaciones *lazy* aparecen problemas de serialización (`LazyInitializationException`, ciclos infinitos) y se pueden filtrar datos internos.
- La posibilidad de que el servicio evolucione su persistencia sin romper a sus consumidores.

**4. ¿Por qué hay dos DTO de entrada (creación y actualización) con los mismos campos?**

Porque representan **casos de uso distintos que pueden evolucionar por separado**. Hoy coinciden (`EstudianteCreateDTO.java` y `EstudianteUpdateDTO.java`), pero es fácil que diverjan: la actualización podría volver opcionales algunos campos (PATCH parcial), impedir cambiar el correo o exigir un campo de versión para control optimista, y la creación podría pedir datos que no se editan después. Con DTOs separados cada contrato cambia sin efectos colaterales sobre el otro, y Swagger documenta exactamente qué acepta cada endpoint. Es una aplicación del principio de responsabilidad única aplicado a los contratos y de la segregación de interfaces. El costo es algo de duplicación, aceptable porque son clases triviales.

**5. ¿Qué ventaja tiene paginar? ¿Qué pasaría con 100.000 estudiantes sin paginación?**

`listar(@ParameterObject Pageable)` (`EstudianteController.java:39-42`) delega en `findAll(pageable)`, que genera `SELECT … LIMIT ? OFFSET ?` y un `COUNT`. El paso 1 devuelve 5 registros con `totalElements: 50`. Con paginación, el costo de cada petición es acotado y predecible: memoria, tiempo de consulta, tamaño del JSON y tiempo de red. Además el cliente puede navegar. Sin paginación, con 100.000 estudiantes, cada `GET` cargaría 100.000 entidades en el *heap*, las mapearía a DTOs y serializaría un JSON de varios MB. Eso implica alta latencia, picos de GC, riesgo de `OutOfMemoryError` y saturación de la conexión. Unas pocas peticiones concurrentes bastarían para degradar o tumbar el servicio (DoS involuntario o intencional). Un buen complemento sería **limitar el tamaño máximo de página** (`spring.data.web.pageable.max-page-size`), porque hoy un cliente puede pedir `size=100000`.

---

## 6. cursos-service

### 6.1 Verificación

| # | Petición | Esperado | Obtenido | Respuesta (resumen) |
|---|---|---|---|---|
| 1 | GET /api/cursos | 200 con los tres cursos semilla y su cupoMaximo | HTTP 200 ✅ | OK · totalElements=3, en página=3 |
| 2 | POST curso ARQ-001 | 201 | HTTP 201 ✅ | Curso creado · ARQ-001, cupoMaximo=20 |
| 3 | Repetir el paso 2 | 400 Ya existe un curso con el código: ARQ-001 | HTTP 400 ✅ | Ya existe un curso con el código: ARQ-001 |
| 4 | POST con creditos: 11 | 400 Los créditos máximos son 10 | HTTP 400 ✅ | Error de validación · creditos: Los créditos máximos son 10 |
| 5 | PUT /api/cursos/1 con codigo BD2-001 | 400 Ya existe otro curso con el código: BD2-001 | HTTP 400 ✅ | Ya existe otro curso con el código: BD2-001 |
| 6a | ESTUDIANTE: GET /api/cursos | 200 | HTTP 200 ✅ | OK · totalElements=4, en página=4 |
| 6b | ESTUDIANTE: POST /api/cursos | 403 | HTTP 403 ✅ | `AUTH_FORBIDDEN` · No tiene permisos para acceder a este recurso |
| 7 | DELETE /api/cursos/4 (curso creado en el paso 2) | 200 (no tiene matrículas) | HTTP 200 ✅ | Curso eliminado |

Evidencia completa (petición y respuesta JSON de cada paso): [Anexo B.4 · cursos-service](#b4--cursos-service)

### 6.2 Preguntas de análisis

**1. Clases prácticamente iguales a las de estudiantes-service. ¿Es un problema? ¿Una librería compartida?**

Son idénticas salvo el paquete: `api/ApiResponse`, `api/ApiErrorResponse`, `api/ResponseBuilder`, `client/AuthClient`, `client/MatriculasClient` (cambia solo el parámetro), `config/FeignAuthPropagationConfig`, `config/OpenApiConfig`, `config/SecurityConfig` (cambian rutas y roles), `security/AuthValidationFilter`, `security/CustomAuthenticationEntryPoint`, `security/CustomAccessDeniedHandler`, `security/CustomAuthenticationException`, `dto/TokenValidationResponse`, `dto/RemoteApiResponse`, `exception/BusinessException`, `NotFoundException`, `ConflictException`, `RemoteServiceException` y `controller/GlobalExceptionHandler`. Además, `Curso*` replica la estructura `Controller/Handler/Service/Repository` de `Estudiante*`.

En microservicios, esta duplicación **no es necesariamente un problema**: cada servicio puede desplegarse, versionarse y evolucionar sin coordinarse con los demás. El principio DRY pesa menos que el bajo acoplamiento. El riesgo real está en el código de **seguridad** duplicado: si se descubre un fallo en `AuthValidationFilter` hay que corregirlo en cuatro lugares, y una copia olvidada deja un hueco.

Mi postura: crearía una **librería compartida pequeña y estable solo para la infraestructura transversal** (filtro, *entry point*, *access denied handler*, `ApiErrorResponse` y la propagación del token), por ejemplo como *starter* de Spring Boot versionado (`academico-security-starter`). **No** compartiría DTOs de dominio ni el `GlobalExceptionHandler` con sus mensajes de negocio, porque eso acopla los modelos y obliga a desplegar todos los servicios a la vez ante cada cambio. Una alternativa sin librería es mover la validación del token a un **API Gateway** y quitar el filtro de los servicios.

**2. ¿Por qué ESTUDIANTE puede consultar cursos pero no estudiantes? (mínimo privilegio)**

El **principio de mínimo privilegio** dice que cada rol debe tener solo los permisos necesarios para su función. Un estudiante necesita ver la **oferta de cursos** para saber en qué matricularse, y esa información es pública dentro de la institución: no contiene datos personales. Por eso `GET /api/cursos/**` incluye `ESTUDIANTE` (`cursos-service/…/SecurityConfig.java:41`). En cambio, `/api/estudiantes` expone **datos personales de otros estudiantes** (nombre, correo, edad), y ningún caso de uso del estudiante los requiere. Darle ese acceso violaría la privacidad (en Colombia, la Ley 1581 de 2012 de protección de datos). Por eso `GET /api/estudiantes/**` se limita a ADMIN y DOCENTE (`estudiantes-service/…/SecurityConfig.java:41`), y el paso 5 de seguridad y el 8 de estudiantes devuelven 403. Si el estudiante necesita sus propios datos, lo correcto sería un `/mias` con autorización por dueño (como E4), no abrir el recurso completo.

**3. ¿Qué pasa con las matrículas si un curso cambia de código?**

**Nada.** matriculas-service guarda solo el **`cursoId`** (`Matricula.java:18-19`), que es la clave sustituta inmutable, y no el código. `PUT /api/cursos/{id}` cambia `codigo` sobre la misma fila (`CursoServiceImpl.java:63`), con el mismo `id`, así que las matrículas siguen apuntando al curso correcto. matrículas tampoco guarda copias del nombre ni del código (`CursoRemotoDTO` se usa solo durante el registro, `MatriculaServiceImpl.java:55`). Esto muestra por qué en sistemas distribuidos se referencian **identificadores sustitutos estables** y no claves naturales mutables: si se hubiera usado `codigo` como referencia, cambiarlo dejaría matrículas huérfanas en otra base de datos, sin llave foránea que lo impida. El único efecto es en reportes históricos: una matrícula de 2025 mostrará el código **actual** del curso. Si se necesitara la foto histórica habría que guardar una copia del código al matricular, aceptando la desnormalización.

**4. ¿Qué reglas de cursos dependen de otro servicio y qué pasa si matrículas está caído?**

| Regla | Dependencia | Si matriculas-service está caído |
|---|---|---|
| Código único al crear y al actualizar (`CursoServiceImpl.java:31, 53`) | Local | Funciona |
| Validaciones de campos: créditos 1-10, cupo 1-60, obligatorios (`CursoCreateDTO.java`) | Local | Funciona |
| Consultar y listar cursos | Local (solo auth para el token) | Funciona |
| **Eliminar** solo si no hay matrículas activas (E1, `:73-81`) | matriculas-service (`contarActivasPorCurso`) | Rechaza con **502** y el curso **no** se borra (fail-closed). Verificado en E1, paso 8 |
| **Reducir el cupo** no puede quedar por debajo de las activas (reto E2, `:57-62`) | matriculas-service, solo si el cupo **baja** | Bajar el cupo → 502. **Subirlo o editar otros campos sigue funcionando**, porque no consulta a matrículas |

Todas las reglas dependen además de **auth-service**: sin él, cualquier petición termina en 401 `TOKEN_VALIDATION_ERROR`.

---

## 7. matriculas-service

### 7.1 Verificación

| # | Petición | Esperado | Obtenido | Respuesta (resumen) |
|---|---|---|---|---|
| 1 | POST {estudianteId:1, cursoId:1} | 201, estado ACTIVA | HTTP 201 ✅ | Matrícula registrada · id=2, estado=ACTIVA |
| 2 | Repetir el paso 1 | 400 Ya existe una matrícula activa… | HTTP 400 ✅ | Ya existe una matrícula activa para el estudiante y curso indicados |
| 3 | POST con estudianteId 999 | 400 El estudiante indicado no existe | HTTP 400 ✅ | El estudiante indicado no existe |
| 4 | POST con cursoId 999 | 400 El curso indicado no existe | HTTP 400 ✅ | El curso indicado no existe |
| 5 | POST con cuerpo {} | 400 Error de validación | HTTP 400 ✅ | Error de validación · estudianteId: El id del estudiante es obligatorio; cursoId: El id del curso es obligatorio |
| 6 | PUT /api/matriculas/2/anular | 200, estado ANULADA | HTTP 200 ✅ | Matrícula anulada · id=2, estado=ANULADA |
| 7 | Repetir el paso 6 | 400 La matrícula ya se encuentra anulada | HTTP 400 ✅ | La matrícula ya se encuentra anulada |
| 8 | Repetir el paso 1 | 201: una matrícula anulada no bloquea una nueva | HTTP 201 ✅ | Matrícula registrada · id=3, estado=ACTIVA |
| 9a | DOCENTE: GET /api/matriculas | 200 | HTTP 200 ✅ | OK · totalElements=3, en página=3 |
| 9b | DOCENTE: POST /api/matriculas | 403 | HTTP 403 ✅ | `AUTH_FORBIDDEN` · No tiene permisos para acceder a este recurso |
| 10 | Con estudiantes-service detenido, registrar otra matrícula | 502 No fue posible consultar el estudiante… | HTTP 502 ✅ | No fue posible consultar el estudiante (código remoto -1) |

Evidencia completa (petición y respuesta JSON de cada paso): [Anexo B.5 · matriculas-service](#b5--matriculas-service)

En el paso 10 el mensaje real fue "No fue posible consultar el estudiante (código remoto -1)". El `-1` es el `status()` que Feign asigna cuando no hubo respuesta HTTP (conexión rechazada).

### 7.2 Preguntas de análisis

**1. ¿Cuántas llamadas HTTP hay en total para registrar una matrícula? Latencia y disponibilidad.**

En el caso exitoso son **6 peticiones HTTP** en total: 1 externa y 5 internas.

1. Cliente → matriculas `POST /api/matriculas`.
2. matriculas → auth `GET /auth/validate` (su filtro).
3. matriculas → estudiantes `GET /api/estudiantes/{id}` (`MatriculaServiceImpl.java:54`).
4. estudiantes → auth `GET /auth/validate` (filtro de estudiantes con el token propagado).
5. matriculas → cursos `GET /api/cursos/{id}` (`:55`).
6. cursos → auth `GET /auth/validate`.

Las llamadas son **secuenciales**, así que la latencia total es aproximadamente la suma de los seis tramos, más las consultas a BD de cada servicio. La **disponibilidad** es el producto de las disponibilidades de los cuatro servicios implicados: con 99,5 % cada uno, la operación queda en ≈ 0,995⁴ ≈ **98 %**. Además, auth-service recibe tres validaciones por cada matrícula. Mejoras posibles: cachear la validación del token, validar el JWT localmente (§3, P2), consultar estudiante y curso en paralelo, y añadir *timeouts* explícitos, reintentos acotados y *circuit breakers* (Resilience4j) para fallar rápido.

**2. ¿Por qué un estudiante inexistente da 400 y un servicio caído 502? ¿Qué debe hacer el cliente?**

`obtenerRemoto` (`MatriculaServiceImpl.java:106-120`) traduce los errores remotos según su **causa**:

- `FeignException.NotFound` (estudiantes respondió 404) → `BusinessException` → **400**. El fallo está en los **datos que envió el cliente**: el `estudianteId` del cuerpo no corresponde a ningún estudiante. Para el cliente de matrículas no es un "recurso no encontrado" en la URL (la URL `/api/matriculas` existe), sino un dato inválido. El cliente **no debe reintentar** con los mismos datos, sino corregir el `estudianteId`.
- Otro `FeignException`, como conexión rechazada o 5xx (líneas 117-118) → `RemoteServiceException` → **502 Bad Gateway** (`GlobalExceptionHandler.java:40-44`). El problema está **en el servidor**: una dependencia no respondió. La petición del cliente era correcta, así que **puede reintentar más tarde** (con *backoff*) o mostrar "servicio no disponible temporalmente". No hay que pedirle al usuario que cambie nada.

Esta separación evita culpar al usuario de un fallo de infraestructura y evita reintentos inútiles ante errores de datos.

**3. ¿Por qué matrículas define `EstudianteRemotoDTO` en lugar de reutilizar `EstudianteDTO`?**

Para no **acoplar** los dos servicios a nivel de código. Reutilizar `EstudianteDTO` exigiría compartir una librería o depender del artefacto de estudiantes-service, y cualquier cambio en ese DTO obligaría a recompilar y redesplegar matrículas al mismo tiempo, en contra de la autonomía de despliegue. Con su propia copia, matrículas define **solo lo que necesita** (`EstudianteRemotoDTO`: `id`, `nombre`, `apellido`, `email`, sin `edad`), aplicando el patrón ***Tolerant Reader***: Jackson ignora los campos que no conoce, así que estudiantes puede agregar campos sin romper a matrículas. Es la idea del *bounded context* de DDD: el "estudiante" visto desde matrículas es un modelo distinto del de su servicio dueño. El costo es que, si estudiantes renombra o quita un campo usado, el fallo solo aparece en tiempo de ejecución. Se mitiga con **pruebas de contrato** (Spring Cloud Contract o Pact).

**4. Si no se propagara el token, ¿qué respuesta recibiría el usuario?**

Sin `FeignAuthPropagationConfig` (`matriculas-service/…/config/FeignAuthPropagationConfig.java`), la cadena sería:

1. ADMIN → matriculas `POST /api/matriculas` con un token válido. El filtro de matrículas lo valida y la regla ADMIN se cumple.
2. matriculas → estudiantes `GET /api/estudiantes/1` **sin encabezado `Authorization`**.
3. El `AuthValidationFilter` de estudiantes (`:44-48`) no encuentra `Bearer` y responde **401 `AUTH_HEADER_MISSING`** a matrículas.
4. En matrículas, Feign convierte ese 401 en `FeignException.Unauthorized`. `obtenerRemoto` lo captura en `MatriculaServiceImpl.java:115-116` y lanza `RemoteServiceException("No fue posible validar el estudiante: el servicio remoto rechazó el token")`.
5. El `GlobalExceptionHandler` lo traduce a **502 Bad Gateway**.

El usuario recibiría **502** "No fue posible validar el estudiante: el servicio remoto rechazó el token", aunque su token es válido y tiene permisos: **todas** las matrículas fallarían. Es correcto que sea 502 y no 401. El 401 se refiere a la credencial del cliente frente a matrículas, que sí es válida. Lo que falló es la comunicación con una dependencia, y si se reenviara el 401 tal cual, el cliente creería que debe volver a hacer login.

**5. ¿Qué ventaja tiene anular en lugar de borrar? ¿Qué consultas futuras permite?**

`anular` (`MatriculaServiceImpl.java:76-83`) cambia `estado` a `ANULADA` (`EstadoMatricula.java`) y conserva la fila. Ventajas:

- **Historial y auditoría**: queda registro de que el estudiante estuvo matriculado y cuándo (`fechaMatricula`), lo que importa para reclamos, certificados y requisitos legales.
- **Integridad con otros servicios**: calificaciones referencia `matriculaId`. Si se borrara la matrícula, sus notas quedarían huérfanas, sin llave foránea que lo evite. Con la anulación siguen siendo trazables, y E3 rechaza nuevas notas sobre matrículas anuladas (paso 5).
- **Reversibilidad** ante una anulación errónea.
- El conteo de cupos y de E1 filtra por `ACTIVA` (`countByCursoIdAndEstado`), así que una anulada libera el cupo sin perder información (E2, pasos 5-6).

Consultas que permite: historial completo de un estudiante, incluidas las anuladas; tasa de retiro o anulación por curso o periodo; cuántas veces se anuló y se volvió a matricular un estudiante en un curso (paso 8 de la verificación); estadísticas de deserción; y reconstruir quién estaba matriculado en una fecha. Para enriquecerlas convendría guardar también **fecha y motivo de la anulación** y el usuario que la hizo.

---

## 8. Extensión E2 · Cupos

### 8.1 Verificación

| # | Petición | Esperado | Obtenido | Respuesta (resumen) |
|---|---|---|---|---|
| 1 | GET /api/cursos/3 (8083) | RED-001 con cupoMaximo: 2 | HTTP 200 ✅ | OK · RED-001, cupoMaximo=2 |
| 2 | POST /api/matriculas {estudianteId:1, cursoId:3} | 201 | HTTP 201 ✅ | Matrícula registrada · id=1, estado=ACTIVA |
| 3 | POST /api/matriculas {estudianteId:2, cursoId:3} | 201 | HTTP 201 ✅ | Matrícula registrada · id=2, estado=ACTIVA |
| 4 | POST /api/matriculas {estudianteId:3, cursoId:3} | 400 El curso no tiene cupos disponibles (2/2) | HTTP 400 ✅ | El curso no tiene cupos disponibles (2/2) |
| 5 | PUT /api/matriculas/2/anular | 200, estado ANULADA | HTTP 200 ✅ | Matrícula anulada · id=2, estado=ANULADA |
| 6 | Repetir el paso 4 | 201: se liberó un cupo | HTTP 201 ✅ | Matrícula registrada · id=3, estado=ACTIVA |
| 7 | PUT /api/cursos/3 con los mismos datos y cupoMaximo: 1 | 400 El cupo no puede ser menor que las 2 matrícula(s) activa(s) del curso | HTTP 400 ✅ | El cupo no puede ser menor que las 2 matrícula(s) activa(s) del curso |
| 8 | POST /api/cursos sin cupoMaximo | 400 El cupo máximo es obligatorio | HTTP 400 ✅ | Error de validación · cupoMaximo: El cupo máximo es obligatorio |

Evidencia completa (petición y respuesta JSON de cada paso): [Anexo B.6 · Extensión E2 · Cupos](#b6--extensión-e2--cupos)

Pruebas automatizadas relacionadas, todas en verde: `MatriculaServiceImplTest.rechazaLaMatriculaCuandoElCursoEstaLleno` y `registraLaMatriculaCuandoQuedaCupo`, y `CursoServiceImplTest.noReduceElCupoPorDebajoDeLasMatriculasActivas`, `reduceElCupoSiAlcanzaParaLasMatriculasActivas` y `aumentarElCupoNoConsultaMatriculas`.

### 8.2 Preguntas de análisis

**1. ¿Por qué el cupo se guarda en cursos y el conteo se hace en matrículas? ¿Qué pasaría si matrículas guardara una copia del cupo?**

Cada dato vive en el servicio **dueño** de ese concepto (*single source of truth*). El cupo es un atributo del curso, que define y edita el administrador de cursos (`Curso.java:30-32`). Las matrículas activas son datos de matrículas, que es el único servicio que sabe cuántas hay (`countByCursoIdAndEstado`, `MatriculaServiceImpl.java:62`). Al registrar, matrículas pide el cupo **actual** a cursos (`CursoRemotoDTO.cupoMaximo`, `:55`) y lo compara con su conteo local (`:62-65`).

Si matrículas guardara una copia del cupo, aparecería un problema de **consistencia de datos replicados**: cuando el ADMIN cambie el cupo en cursos, la copia quedaría desactualizada hasta que algo la sincronice. Habría que publicar eventos (por ejemplo, `CursoActualizado` por un broker) o hacer *polling*, con una ventana de inconsistencia en la que se aceptarían matrículas por encima del nuevo cupo o se rechazarían aunque hubiera espacio. Además, habría dos lugares que editar y validar.

**2. Dos administradores registran a la vez la última matrícula disponible. ¿Pueden pasar ambas?**

**Sí, y lo comprobé experimentalmente.** El código del paso 4 (`MatriculaServiceImpl.java:62-72`) es un patrón *check-then-act* sin bloqueo:

```java
long activas = repository.countByCursoIdAndEstado(cursoId, EstadoMatricula.ACTIVA);  // (a) leer
if (curso.getCupoMaximo() != null && activas >= curso.getCupoMaximo()) { throw … }    // (b) decidir
… return repository.save(matricula);                                                  // (c) escribir
```

Cada petición corre en su propia transacción (`@Transactional`, línea 24) con aislamiento *READ COMMITTED* (el predeterminado de H2). Si la petición A ejecuta (a) y lee `activas = 1` (cupo 2), y la petición B ejecuta (a) antes de que A confirme (c), B también lee 1. Las dos pasan la verificación (b) y las dos insertan. Ninguna restricción de la base de datos lo impide. La ventana es amplia porque **antes** de (a) hay dos llamadas HTTP remotas cuya duración varía, lo que hace probable que las peticiones se solapen.

**Evidencia** ([Anexo B.10 · Experimento de concurrencia](#b10--experimento-de-concurrencia)): se crearon cursos con `cupoMaximo: 1` y se enviaron 45 matrículas simultáneas por curso. En **2 de 5 rondas** el curso quedó con **2 y 3 matrículas activas**, por encima del cupo de 1. El mismo problema afecta la regla de duplicado (`:57-59`): dos peticiones simultáneas del mismo estudiante y curso podrían crear dos matrículas activas.

Formas de evitarlo (detalladas en la **§13**):

- **Bloqueo pesimista por curso** en matrículas: una tabla `cupo_curso(curso_id PK)` con `SELECT … FOR UPDATE` (`@Lock(PESSIMISTIC_WRITE)`) antes de contar. Serializa solo las matrículas del mismo curso.
- **Contador con actualización condicional atómica**: `UPDATE cupo_curso SET activas = activas + 1 WHERE curso_id = ? AND activas < ?` y verificar que afectó 1 fila.
- Restricción única para el duplicado (índice parcial `(estudiante_id, curso_id) WHERE estado='ACTIVA'` en PostgreSQL).
- Aislamiento `SERIALIZABLE` con reintento ante el conflicto (más costoso).

**3. ¿Por qué la validación del cupo va después de la del duplicado? ¿Qué mensaje recibiría el usuario si fuera al revés?**

Porque el **mensaje debe reflejar la causa más específica y útil**. Si el estudiante ya tiene una matrícula activa en el curso, la razón real del rechazo es el duplicado: aunque hubiera cupo, no podría matricularse otra vez. Con el orden actual (`:57-59` y luego `:62-65`) recibe "Ya existe una matrícula activa para el estudiante y curso indicados" y sabe que no tiene que hacer nada. Con el orden inverso, en un curso lleno en el que el estudiante ya está matriculado (como el estudiante 1 en RED-001 tras el paso 2), recibiría "El curso no tiene cupos disponibles (2/2)". Eso es engañoso: le hace creer que no está matriculado y que debe esperar a que se libere un cupo, cuando en realidad ya ocupa uno de esos dos. El orden también evita contar (consulta agregada) cuando la verificación más barata y selectiva ya decide el resultado.

**4. En el reto, ¿por qué solo se consulta a matrículas cuando el cupo baja? ¿Qué se ahorra?**

`CursoServiceImpl.actualizar` (`:56-62`) solo llama a `contarMatriculasActivas` si `curso.getCupoMaximo() < actual.getCupoMaximo()`. Si el cupo sube o se mantiene igual, es **imposible** que quede por debajo de las activas, porque el cupo anterior ya las contenía (salvo la carrera de la P2). Consultar sería una llamada inútil. Se ahorra:

- Una petición HTTP a matrículas, más su validación del token en auth: **2 llamadas remotas** y su latencia en la mayoría de las ediciones (cambiar nombre, descripción, docente o créditos).
- Un **punto de fallo**: editar el nombre de un curso no falla con 502 aunque matriculas-service esté caído.

Lo confirma la prueba `aumentarElCupoNoConsultaMatriculas` (`CursoServiceImplTest`), que verifica con Mockito que no hay interacción con `MatriculasClient`.

**5. El código comprueba `curso.getCupoMaximo() != null`. ¿Cuándo podría llegar un cupo nulo?**

`MatriculaServiceImpl.java:63` es una lectura **defensiva**, porque matrículas no controla el contrato de cursos. Situaciones reales:

- **Datos anteriores a E2**: cursos creados antes de agregar la columna. Con `ddl-auto: update` sobre una BD persistente, la columna nueva se agregaría con `NULL` para las filas existentes, o directamente fallaría por el `nullable = false`.
- **Versiones desalineadas en un despliegue gradual**: matrículas ya desplegado con E2 llamando a un cursos-service viejo que todavía no devuelve `cupoMaximo`. Jackson deja el campo en `null` (*tolerant reader*).
- Un cambio de contrato en cursos: renombrar el campo (`cupo` en vez de `cupoMaximo`) o excluirlo de la respuesta.
- Inserciones directas en la BD que se salten la validación del DTO.

Con el `null`, matrículas trata el curso como **sin límite** en vez de lanzar `NullPointerException` (un 500). Es una decisión discutible: también podría tratarse como un error del servicio remoto (502), lo que sería *fail-closed*.

---

## 9. Extensión E1 · Integridad entre servicios

### 9.1 Verificación

Partiendo de los datos de E2: el curso 3 tiene dos matrículas activas (estudiantes 1 y 3).

| # | Petición | Esperado | Obtenido | Respuesta (resumen) |
|---|---|---|---|---|
| 1 | GET /api/matriculas/activas/conteo?cursoId=3 | 200 con data: 2 | HTTP 200 ✅ | OK · data=2 |
| 2 | GET /api/matriculas/activas/conteo (sin filtro) | 400 Envíe exactamente uno de los parámetros… | HTTP 400 ✅ | Envíe exactamente uno de los parámetros: estudianteId o cursoId |
| 3 | DELETE /api/cursos/3 | 409 No se puede eliminar: el curso tiene 2 matrícula(s) activa(s) | HTTP 409 ✅ | No se puede eliminar: el curso tiene 2 matrícula(s) activa(s) |
| 4 | DELETE /api/estudiantes/1 (tiene una matrícula activa) | 409 | HTTP 409 ✅ | No se puede eliminar: el estudiante tiene 1 matrícula(s) activa(s) |
| 5 | DELETE /api/estudiantes/50 (sin matrículas) | 200 | HTTP 200 ✅ | Estudiante eliminado |
| 6a | Matricular al estudiante 5 en el curso 2 | 201 | HTTP 201 ✅ | Matrícula registrada · id=4, estado=ACTIVA |
| 6b | DELETE /api/cursos/2 | 409 …tiene 1 matrícula(s) activa(s) | HTTP 409 ✅ | No se puede eliminar: el curso tiene 1 matrícula(s) activa(s) |
| 7a | Anular la matrícula 4 | 200 | HTTP 200 ✅ | Matrícula anulada · id=4, estado=ANULADA |
| 7b | Repetir DELETE /api/cursos/2 | 200: sin matrículas activas, el curso se elimina | HTTP 200 ✅ | Curso eliminado |
| 8 | Con matriculas-service detenido: DELETE /api/cursos/1 | 502 No fue posible verificar las matrículas del curso… | HTTP 502 ✅ | No fue posible verificar las matrículas del curso (código remoto -1) |
| 8b | GET /api/cursos/1 (comprobar que el curso sigue existiendo) | 200 | HTTP 200 ✅ | OK · IS3-001, cupoMaximo=30 |

Evidencia completa (petición y respuesta JSON de cada paso): [Anexo B.7 · Extensión E1 · Integridad entre servicios](#b7--extensión-e1--integridad-entre-servicios)

Pruebas automatizadas relacionadas, en verde: `EstudianteServiceImplTest` (3 casos: con activas, sin activas y matrículas caído) y `CursoServiceImplTest.noEliminaUnCursoConMatriculasActivas`.

### 9.2 Preguntas de análisis

**1. Dependencias entre los cinco servicios. ¿Qué ciclos aparecen y qué riesgos tienen?**

```
                 ┌──────────────► auth-service ◄──────────────┐   (todos validan el token)
                 │                     ▲                      │
          estudiantes ◄──────┐         │          ┌──────► cursos
               │              │         │          │          │
               │ (E1 conteo)  │ (validar│          │(validar  │ (E1 conteo / E2 bajar cupo)
               ▼              │ estud.) │          │ curso+   ▼
               └──────────► matriculas ─┴──────────┘ cupo) ◄──┘
                                 ▲
                                 │ (validar matrícula, /mias)
                          calificaciones
```

| Servicio | Depende de |
|---|---|
| auth | nadie |
| estudiantes | auth, **matriculas** (E1: `MatriculasClient.contarActivasPorEstudiante`) |
| cursos | auth, **matriculas** (E1/E2: `contarActivasPorCurso`) |
| matriculas | auth, **estudiantes**, **cursos** (`EstudiantesClient`, `CursosClient`) |
| calificaciones | auth, matriculas |

**Ciclos:** `estudiantes → matriculas → estudiantes` y `cursos → matriculas → cursos`. Ambos los introdujo E1. auth no forma parte de ningún ciclo porque no depende de nadie.

Riesgos:

- **Despliegue y arranque**: no hay un orden válido en el que cada servicio arranque después de sus dependencias. En `docker-compose.yml` matrículas declara `depends_on` estudiantes y cursos (líneas 37-40), pero estudiantes y cursos no pueden declarar `depends_on` matrículas sin formar un ciclo que Compose rechaza. Hoy funciona porque Feign es perezoso y solo llama en tiempo de petición, pero un *health check* que verificara las dependencias provocaría un *deadlock* de arranque.
- **Cambios de contrato**: un cambio incompatible en el contrato de matrículas (por ejemplo, el formato de `/activas/conteo`) rompe a estudiantes y cursos, y uno de estudiantes o cursos rompe a matrículas. No se puede desplegar "primero el proveedor" porque cada uno es proveedor y consumidor del otro. Hay que coordinar versiones o mantener contratos retrocompatibles.
- **Fallas en cascada y disponibilidad acoplada**: si matrículas cae, estudiantes y cursos no pueden borrar (E1, paso 8). Si estudiantes cae, matrículas no puede registrar. Es un **monolito distribuido**: tiene los costos de la distribución sin la independencia.
- Riesgo de **recursión** si en el futuro una operación de matrículas que llama a estudiantes disparara una consulta de vuelta a matrículas (latencia y bucles).

Alternativas para romper el ciclo: invertir la dependencia con **eventos**. Matrículas publicaría `MatriculaCreada/Anulada` y estudiantes y cursos mantendrían su propio conteo. Otra opción es que la decisión de borrar la coordine una capa superior (orquestador o *saga*).

**2. Eliminación lógica vs. física con verificación.**

| Criterio | Física + verificación remota (actual) | Eliminación lógica (`activo=false`) |
|---|---|---|
| Acoplamiento | Alto: cursos y estudiantes llaman a matrículas al borrar (y forman el ciclo) | Menor: desactivar es local. Matrículas consulta el curso al registrar, como ya hace, y rechaza los inactivos. No hace falta `MatriculasClient` en cursos ni en estudiantes |
| Disponibilidad | Borrar falla (502) si matrículas cae | Desactivar funciona aunque matrículas esté caído |
| Historial | Se pierde el curso o estudiante: las matrículas antiguas quedan con un `cursoId` que ya no existe y no se puede mostrar su nombre | Se conserva: reportes, certificados y auditoría siguen resolviendo nombres |
| Integridad referencial | Garantizada por la verificación previa (con la carrera de la P4) | Nunca hay referencias colgantes, porque nada se borra |
| Complejidad | Lógica simple, pero con llamadas remotas y manejo de errores | Todas las consultas deben filtrar por `activo` (`@Where`/`@SQLRestriction` o *scopes*). Las restricciones únicas deben contemplar los inactivos (¿se puede reutilizar el código de un curso inactivo?). Hay que decidir qué pasa con las matrículas **activas** de un curso que se desactiva |
| Privacidad | Permite borrar datos personales (derecho de supresión) | Hay que tener además un borrado o anonimización real para datos personales |

Para un sistema académico preferiría la **eliminación lógica**, porque la trazabilidad histórica es un requisito. La eliminación física quedaría para errores de captura, sin dependencias, o para cumplir solicitudes de supresión de datos personales.

**3. Fail-closed vs. fail-open. ¿Cuándo sería aceptable fail-open?**

El código actual es *fail-closed*: ante cualquier `FeignException` o respuesta sin datos, `contarMatriculasActivas` lanza `RemoteServiceException` y responde **502**, sin borrar (`CursoServiceImpl.java:83-93`, `EstudianteServiceImpl.java:74-84`). El paso 8 lo comprueba: el curso 1 sigue existiendo.

Con *fail-open* (si no se puede verificar, borrar igual), una caída de matrículas permitiría **eliminar cursos o estudiantes con matrículas activas**. Esas matrículas quedarían huérfanas, apuntando a ids inexistentes, y sin llave foránea nadie lo detectaría. Las consultas posteriores fallarían o mostrarían datos incompletos, y el daño es **irreversible**: el registro ya no existe.

*Fail-open* es aceptable cuando la operación es **reversible o de bajo impacto** y la disponibilidad vale más que la consistencia. Ejemplos: mostrar un listado aunque falle un servicio secundario de enriquecimiento (fotos, recomendaciones); registrar un evento analítico; un límite de tasa que, si no responde, deja pasar la petición; o validaciones que luego se **reconcilian** con un proceso asíncrono que detecta y corrige inconsistencias. Para borrados permanentes de datos maestros, fail-closed es la elección correcta.

**4. Entre la consulta del conteo y el delete pasa un instante. ¿Podría registrarse una matrícula justo en ese momento?**

**Sí.** `CursoServiceImpl.eliminar` (`:73-81`) cuenta en matrículas (llamada HTTP), decide y luego borra en su propia BD. Son dos bases de datos distintas y **no hay transacción distribuida ni bloqueo** que cubra ambos pasos. Secuencia problemática:

1. El ADMIN-1 pide `DELETE /api/cursos/2`, y cursos consulta el conteo: `0`.
2. En ese instante el ADMIN-2 registra `POST /api/matriculas {cursoId: 2}`. Matrículas consulta `GET /api/cursos/2`, que todavía existe, y guarda la matrícula como ACTIVA.
3. Cursos ejecuta `repository.delete(curso)` y confirma.

Consecuencia: queda una **matrícula activa huérfana**, que apunta a un `cursoId` inexistente. Se violó justo la invariante que E1 quería proteger: nadie podrá ver los datos de ese curso, el conteo de cupos ya no tiene sentido y E3 permitiría poner notas sobre una matrícula de un curso que no existe. La probabilidad es baja porque la ventana dura milisegundos, pero no es cero, como mostró el experimento de E2 con una ventana parecida.

Mitigaciones: eliminación lógica en dos fases (marcar primero el curso como "cerrado", para que matrículas rechace nuevas, y luego verificar y borrar); un patrón *saga* con compensación; o que matrículas **reconcilie** periódicamente las referencias huérfanas.

**5. ¿Por qué 409 y no 400? ¿Qué le dice cada código al cliente?**

- **400 Bad Request**: la petición **en sí** está mal formada o sus datos son inválidos (JSON mal escrito, un campo faltante, un id inexistente en el cuerpo). Le dice al cliente: *"corrige tu petición; enviarla igual nunca funcionará"*.
- **409 Conflict**: la petición es **correcta**, pero choca con el **estado actual del recurso** en el servidor. `DELETE /api/cursos/3` está bien formada y el curso existe, pero ahora mismo tiene matrículas activas (`ConflictException`, `CursoServiceImpl.java:78`, mapeada a 409 en `GlobalExceptionHandler.java:38-42` de cursos). Le dice al cliente: *"la petición es válida, pero el estado del recurso lo impide; resuelve el conflicto (anula las matrículas) y repite exactamente la misma petición"*.

El paso 7 de la verificación lo muestra: la **misma** `DELETE /api/cursos/2` pasó de 409 a 200 tras anular la matrícula, sin cambiar nada en la petición. Con un 400 el cliente concluiría que su petición es incorrecta y no la repetiría.

---

## 10. Extensión E4 · Mis matrículas

### 10.1 Verificación

| # | Petición | Esperado | Obtenido | Respuesta (resumen) |
|---|---|---|---|---|
| 1 | Login como estudiante y GET /auth/validate | estudianteId: 1 | HTTP 200 ✅ | valid=true, role=ESTUDIANTE, estudianteId=1 |
| 2 | ADMIN: GET /api/matriculas (matrículas de varios estudiantes) | Existen matrículas de los estudiantes 1, 2, 3 (y 5) | HTTP 200 ✅ | OK · totalElements=4, en página=4 |
| 3 | ESTUDIANTE: GET /api/matriculas/mias | Solo las matrículas del estudiante 1 | HTTP 200 ✅ | OK · 1 matrícula(s): id 1 (est. 1) |
| 4 | ESTUDIANTE: GET /api/matriculas | 403 AUTH_FORBIDDEN | HTTP 403 ✅ | `AUTH_FORBIDDEN` · No tiene permisos para acceder a este recurso |
| 5 | ESTUDIANTE: GET /api/matriculas/2 (de otro estudiante) | 403 | HTTP 403 ✅ | `AUTH_FORBIDDEN` · No tiene permisos para acceder a este recurso |
| 6 | ADMIN: GET /api/matriculas/mias | 403 | HTTP 403 ✅ | `AUTH_FORBIDDEN` · No tiene permisos para acceder a este recurso |

Evidencia completa (petición y respuesta JSON de cada paso): [Anexo B.8 · Extensión E4 · Mis matrículas](#b8--extensión-e4--mis-matrículas)

Pruebas automatizadas relacionadas, en verde: `JwtUtilsTest` (2) y `AuthFlowIntegrationTest` (2) en auth, y `MatriculaControllerSecurityTest` (4 casos) en matrículas.

### 10.2 Preguntas de análisis

**1. ¿Qué vulnerabilidad tendría `GET /api/matriculas?estudianteId=1` abierto al rol ESTUDIANTE?**

Una **IDOR (*Insecure Direct Object Reference*)**, que corresponde a *Broken Object Level Authorization*, el primer riesgo del OWASP API Security Top 10. El servidor tomaría el identificador del recurso **de la petición**, que el cliente controla, sin verificar que el usuario sea su dueño. El estudiante 1 solo tendría que cambiar el parámetro a `estudianteId=2`, `3`… para enumerar las matrículas de todos los estudiantes. Como los ids son secuenciales, es trivial. El diseño actual lo evita porque **el identificador sale del token firmado, no de la petición**: `MatriculaController.misMatriculas` (`:56-64`) usa `usuario.estudianteId()` del `@AuthenticationPrincipal`, que el filtro construyó con la respuesta de auth-service (`AuthValidationFilter.java:66-70`). No hay ningún parámetro que manipular. El paso 3 de la verificación muestra que el estudiante solo recibe la matrícula 1, la suya.

**2. ¿Qué pasaría si se invirtiera el orden de las dos reglas del paso 4?**

Las reglas de `SecurityConfig` (`matriculas-service/…/config/SecurityConfig.java:42-43`) se evalúan **en orden y gana la primera que coincide**:

```java
.requestMatchers(HttpMethod.GET, "/api/matriculas/mias").hasAuthority("ESTUDIANTE")          // 42
.requestMatchers(HttpMethod.GET, "/api/matriculas/**").hasAnyAuthority("ADMIN", "DOCENTE")   // 43
```

Si se invirtieran, la petición del estudiante `GET /api/matriculas/mias` **coincidiría primero con `/api/matriculas/**`**, que exige ADMIN o DOCENTE. El estudiante tiene `ESTUDIANTE`, así que recibiría **403** y nunca llegaría a la regla específica. El endpoint `/mias` quedaría inutilizable para su único destinatario, y ADMIN y DOCENTE sí podrían entrar a `/mias` (aunque el controlador los rechazaría con 403 porque no tienen `estudianteId`, `:60-62`). Por eso la regla más específica va primero, como advierte el comentario de la línea 41.

**3. Si un administrador cambia la asociación usuario–estudiante, ¿cuándo se entera matrículas?**

Cuando el usuario **obtiene un token nuevo**, es decir, al volver a hacer login o cuando expira el actual (hasta 1 h, `expiration-ms: 3600000`). `estudianteId` se escribe en el JWT al emitirlo (`JwtUtils.java:36-38`), y `validate` lo lee del *claim* sin consultar la BD (`AuthServiceImpl.java:55`). Mientras tanto, el usuario seguiría viendo las matrículas del estudiante **anterior**, una fuga de datos personales durante esa ventana.

| | Dato en el token (actual) | Consultar la asociación en cada petición |
|---|---|---|
| Frescura | Hasta 1 h desactualizado | Inmediata |
| Costo | Cero consultas extra | Una consulta a la tabla `usuarios` por petición (o llamada a auth) |
| Disponibilidad | No añade dependencia nueva | Ninguna dependencia nueva en este proyecto, porque ya se llama a `/auth/validate` en cada petición |

Dado que el proyecto **ya** consulta a auth-service en cada petición, sería barato que `validate` leyera `estudianteId` (y el rol) de la tabla `usuarios` en lugar del *claim*. El cambio aplicaría de inmediato sin tocar los demás servicios.

**4. ¿Por qué `UsuarioAutenticado` es un `record` que implementa `Principal`? ¿Qué se rompería si fuera un objeto cualquiera?**

`record` (`UsuarioAutenticado.java:9`) da un objeto **inmutable**: nadie puede cambiar el `estudianteId` del principal a mitad de la petición. También genera constructor, accesores, `equals`, `hashCode` y `toString` sin código repetitivo, ideal para un portador de datos.

Implementar `java.security.Principal` (con `getName()` devolviendo el `username`, líneas 11-14) importa porque Spring Security usa el principal en varios lugares:

- `Authentication.getName()` en `AbstractAuthenticationToken` devuelve `principal.getName()` **si el principal es un `Principal`** (o un `UserDetails`). Si no, devuelve `principal.toString()`. Con un objeto cualquiera, `authentication.getName()` y `request.getUserPrincipal().getName()` devolverían el `toString()` del record (`UsuarioAutenticado[username=estudiante, role=ESTUDIANTE, estudianteId=1]`) en lugar de `"estudiante"`. Todo lo que dependa del nombre fallaría o mostraría basura: logs de auditoría, `registradoPor` (como en calificaciones, que usa `authentication.getName()`), expresiones SpEL `authentication.name` y `principal.name` en `@PreAuthorize`, y la integración con el contenedor de servlets.

`@AuthenticationPrincipal UsuarioAutenticado usuario` (`MatriculaController.java:59`) funcionaría con cualquier clase, porque solo hace un *cast* del principal. Lo que se rompería es la **identidad textual** del usuario en el resto del ecosistema.

**5. ¿Podría un estudiante fabricar un token con otro `estudianteId`?**

Puede **construir** uno, porque el formato es público: basta con Base64URL del header y del payload modificado. Lo que no puede es **firmarlo válidamente**. El token se firma con HMAC-SHA256 y el secreto `app.jwt.secret` (`JwtUtils.java:39`), y `parseClaimsJws` (`:43`) recalcula la firma sobre header y payload. Si cambia un solo carácter del payload, la firma no coincide y se lanza `SignatureException`, que termina en `401 AUTH_INVALID_TOKEN`. El paso 7 de auth lo demuestra: un token de admin con una letra del payload cambiada fue rechazado. Tampoco sirve `alg: none`, porque jjwt rechaza tokens sin firma cuando se configura una clave. Además, **ningún servicio de negocio confía en el token por sí mismo**: todos le preguntan a auth-service, el único que tiene el secreto.

**Advertencia:** esa protección depende por completo del secreto, y el secreto actual está **publicado en el repositorio** (`application.yaml:25`, ver §3 P4). Cualquiera que lea el repositorio puede firmar un token con `estudianteId: 2` o `role: ADMIN` y auth-service lo aceptaría. En producción el secreto debe salir del código.

---

## 11. Extensión E3 · Calificaciones

### 11.1 Verificación

Partiendo de los datos de E2/E1/E4: matrícula 1 activa (estudiante 1) y matrícula 2 anulada.

| # | Petición | Esperado | Obtenido | Respuesta (resumen) |
|---|---|---|---|---|
| 1 | DOCENTE: POST {matriculaId:1, corte:1, nota:4.0} | 201, registradoPor: docente | HTTP 201 ✅ | Calificación registrada · registradoPor=docente |
| 2 | DOCENTE: POST {matriculaId:1, corte:2, nota:3.0} | 201 | HTTP 201 ✅ | Calificación registrada · registradoPor=docente |
| 3 | DOCENTE: repetir el paso 1 | 400 …use PUT para corregirla | HTTP 400 ✅ | Ya existe una nota para el corte 1 de esta matrícula; use PUT para corregirla |
| 4 | DOCENTE: POST con corte 4 y nota 5.5 | 400 con los errores de ambos campos | HTTP 400 ✅ | Error de validación · nota: La nota máxima es 5.0; corte: El corte debe ser 1, 2 o 3 |
| 5 | DOCENTE: POST sobre la matrícula anulada (id 2) | 400 La matrícula 2 no está activa | HTTP 400 ✅ | La matrícula 2 no está activa |
| 6 | ADMIN: PUT /api/calificaciones/1 {nota:4.5} | 200, registradoPor: admin | HTTP 200 ✅ | Calificación actualizada · registradoPor=admin |
| 7 | DOCENTE: GET /api/calificaciones/matricula/1 | promedioPonderado: 3.75, completa: false | HTTP 200 ✅ | OK · promedioPonderado=3.75, completa=false |
| 8 | DOCENTE: GET /api/calificaciones/matricula/99 | 404 | HTTP 404 ✅ | La matrícula 99 no existe |
| 9 | ESTUDIANTE: POST /api/calificaciones | 403 | HTTP 403 ✅ | `AUTH_FORBIDDEN` · No tiene permisos para acceder a este recurso |
| 10 | ESTUDIANTE: GET /api/calificaciones/mias | Solo el resumen de sus matrículas | HTTP 200 ✅ | OK · 1 resumen(es): matrícula 1 → 3.75 |

Evidencia completa (petición y respuesta JSON de cada paso): [Anexo B.9 · Extensión E3 · Calificaciones](#b9--extensión-e3--calificaciones)

Comprobación del promedio del paso 7: (4,5 × 0,30 + 3,0 × 0,30) / (0,30 + 0,30) = 2,25 / 0,60 = **3,75** (`CalificacionServiceImpl.calcularPromedio`, `:94-106`).

Pruebas automatizadas: `CalificacionServiceImplTest`, 8 casos en verde, incluidos `promedioParcialSeCalculaSobreLosCortesRegistrados` y `promedioDefinitivoConLosTresCortes`.

### 11.2 Preguntas de análisis

**1. "Una nota por corte" está en el servicio y en la BD. ¿Qué protege cada una?**

- **Servicio** (`CalificacionServiceImpl.java:43-45`, `existsByMatriculaIdAndCorte`): da un mensaje de negocio claro y accionable ("…use PUT para corregirla", paso 3) con un 400, **antes** de intentar escribir. La BD sola daría un `DataIntegrityViolationException` genérico. Esta validación no protege frente a la concurrencia.
- **BD** (`Calificacion.java:9-12`, `uk_calificacion_matricula_corte (matricula_id, corte)`): garantiza la invariante **siempre**, también cuando dos docentes registran a la vez la nota del mismo corte (los dos pasan el `exists` y solo un `INSERT` tiene éxito; el otro recibe 409 por el `GlobalExceptionHandler`), y frente a escrituras que no pasan por el servicio: SQL directo, consola H2, migraciones o un futuro *batch*.

Es el mismo patrón que el correo único (§5 P2), y justo lo que **le falta** a la regla de cupo de E2 (§8 P2), que no tiene respaldo en la BD.

**2. ¿Qué pasa con las notas si una matrícula se anula después de calificada? ¿Deberían conservarse?**

Hoy **se conservan sin cambios**. Anular solo cambia el estado en matrículas (`MatriculaServiceImpl.java:76-83`), calificaciones no se entera (no hay eventos) y sus filas siguen intactas. Desde ese momento ya no se pueden **registrar ni corregir** notas, porque `verificarMatriculaActiva` (`:113-124`) se ejecuta en `registrar` y en `actualizar`. Pero el resumen (`GET /matricula/{id}`) sigue mostrándolas: `resumen` solo exige que la matrícula exista (`:68-71`), no que esté activa.

Considero que **deben conservarse**. Son registros académicos con valor legal y de auditoría: muestran el desempeño hasta la anulación, sirven para reclamos y para normas como "el retiro después del segundo corte conserva la nota". Además, la anulación puede revertirse si fue un error. Borrarlas destruiría información de forma irreversible. Lo que sí convendría es **marcar el contexto**: incluir en el resumen el estado de la matrícula (por ejemplo, "anulada") para que nadie interprete un promedio parcial como nota definitiva, y excluir esas notas de cálculos como el promedio acumulado del estudiante.

**3. ¿Por qué `registradoPor` se toma del token y no del cuerpo?**

Por **no repudio e integridad de la auditoría**. `CalificacionController` pasa `authentication.getName()` (`:32` y `:41`), que es el `sub` del JWT validado por auth-service y no puede falsificarse sin el secreto. Si el campo viniera en el cuerpo, cualquier docente podría registrar o corregir una nota **a nombre de otro** (`"registradoPor": "admin"`) y ocultar quién la cambió realmente, y el campo dejaría de servir como evidencia. Es el mismo principio que en E4: **la identidad sale del token, nunca de la petición**. El paso 6 lo muestra: tras el PUT del ADMIN, `registradoPor` pasó de `docente` a `admin`. Un detalle: al corregir se **sobrescribe** el autor original (`:61`), así que se pierde quién registró la primera versión. Una tabla de historial de cambios resolvería eso.

**4. Diferencia entre el 400 del paso 5 y el 404 del paso 8.**

- **Paso 5**, `POST /api/calificaciones {"matriculaId": 2, …}` → **400** "La matrícula 2 no está activa". La URL `/api/calificaciones` existe. El problema es un **dato del cuerpo** que viola una regla de negocio: la matrícula existe pero está anulada. Si la matrícula del cuerpo no existiera, también sería 400 ("La matrícula indicada no existe"), porque `verificarMatriculaActiva` convierte el `NotFoundException` en `BusinessException` (`:113-120`, con el comentario de la línea 118). El cliente debe **corregir los datos** que envía.
- **Paso 8**, `GET /api/calificaciones/matricula/99` → **404** "La matrícula 99 no existe". Aquí el id está **en la URL**: identifica el recurso que se consulta (el resumen de esa matrícula), y ese recurso no existe. `resumen` llama a `obtenerMatricula` y deja propagar el `NotFoundException` (`:68-71`, `:126-134`).

La regla: un id inexistente **en la ruta** es 404 (el recurso pedido no existe). Un id inexistente o inválido **en el cuerpo** es 400 (la petición contiene datos incorrectos). Es el mismo criterio que usa matrículas con estudiantes y cursos (§7 P2). Lo cubren las pruebas `unaMatriculaInexistenteEnElCuerpoEsErrorDeDatos` y `elResumenDeUnaMatriculaInexistenteEs404`.

**5. Para "mis notas", calificaciones no puede consultar `GET /api/matriculas/{id}` con el token del estudiante. ¿Por qué? ¿Otras soluciones?**

Porque la llamada se hace con **el token del estudiante**, propagado por `FeignAuthPropagationConfig`, y matrículas aplica sus propias reglas a ese usuario. `GET /api/matriculas/**` exige `ADMIN` o `DOCENTE` (`matriculas-service/…/SecurityConfig.java:43`), y lo confirma el paso 5 de E4: el estudiante recibe 403 en `GET /api/matriculas/2`. La única ruta de matrículas abierta al estudiante es `/mias`. Por eso `misCalificaciones` (`CalificacionServiceImpl.java:75-88`) llama a `matriculasClient.misMatriculas()` (`MatriculasClient.java:17-19`) y calcula el resumen de cada matrícula devuelta. Con esto, **matrículas decide cuáles son del estudiante**, y calificaciones no necesita conocer el `estudianteId` ni confiar en datos del cliente.

| Alternativa | Ventajas | Desventajas |
|---|---|---|
| **Reutilizar `/mias` con el token del usuario** (actual) | Sin credenciales nuevas; la autorización por dueño vive en un solo lugar; se respeta el mínimo privilegio | Trae todas las matrículas del estudiante aunque solo interese una; acopla calificaciones al endpoint `/mias` |
| **Token propio del servicio** (*client credentials*, rol `SERVICE`) | Calificaciones puede consultar cualquier matrícula; no depende del rol del usuario final | Calificaciones tendría que **reimplementar** el control de dueño (comparar `estudianteId` de la matrícula con el del token del usuario), con riesgo de IDOR si se olvida; requiere emitir y rotar credenciales de servicio; un servicio comprometido puede leer todo; se pierde la trazabilidad del usuario real |
| **Abrir `GET /api/matriculas/{id}` a ESTUDIANTE con verificación de dueño** en matrículas | Consulta puntual por id | Agrega lógica de dueño a un endpoint general; si se implementa mal, es justo la IDOR de §10 P1 |
| **Copia local en calificaciones** (eventos `MatriculaCreada` con `estudianteId`) | Sin llamadas en tiempo de consulta; más rápido y resiliente | Consistencia eventual, infraestructura de mensajería, datos duplicados |
| **Token exchange** (RFC 8693) | Token de servicio que conserva la identidad del usuario ("en nombre de") | Complejidad: requiere un servidor de autorización compatible |

**6. ¿Qué ventajas tuvo crear calificaciones como servicio aparte? ¿Qué costos agregó?**

*Ventajas:*

- **Responsabilidad única y cohesión**: las notas son un subdominio distinto (evaluación) con sus propias reglas (cortes, pesos, promedio). Matrículas sigue enfocado en la inscripción.
- **Permisos diferentes**: el DOCENTE **escribe** notas pero no puede modificar matrículas. Con un servicio aparte, las reglas de seguridad quedan simples y separadas (`calificaciones-service/…/SecurityConfig.java:41-44`).
- **Despliegue y escalado independientes**: en épocas de cierre de notas se puede escalar calificaciones sin tocar matrículas, y un fallo o despliegue de calificaciones no afecta las inscripciones.
- **Evolución independiente**: cambiar los pesos o agregar un cuarto corte no implica redesplegar matrículas.

*Costos:*

- **Llamadas remotas** en cada registro o corrección: calificaciones → matrículas → auth (+1 validación), con más latencia y un punto de fallo. Si matrículas cae, no se pueden registrar notas (502).
- **Sin integridad referencial**: `matriculaId` no tiene llave foránea, y aparecen problemas de consistencia como notas de matrículas anuladas (P2).
- **Más infraestructura**: otro contenedor, puerto, base de datos, Swagger, y otra copia del código de seguridad (filtro, *handlers*, `ApiResponse`).
- **Autorización entre servicios más compleja**: el problema de la P5, que dentro de un mismo servicio se resolvía con un `JOIN`.
- Más difícil de probar de punta a punta y de depurar (trazas distribuidas).

---

## 12. Docker, Swagger y pruebas

### 12.1 Verificación

| # | Acción | Esperado | Obtenido |
|---|---|---|---|
| 1 | `docker compose ps` | Cinco servicios en estado running | ✅ Los cinco `running` (`auth-service`, `estudiantes-service`, `cursos-service`, `matriculas-service`, `calificaciones-service`) |
| 2 | Abrir `http://localhost:808X/swagger-ui.html`, X = 1…5 | Swagger de cada servicio | ✅ HTTP 200 en los cinco; capturas al final de esta sección |
| 3 | Login admin y `POST /api/matriculas {1,1}` | 201: comunicación por la red de Docker | ✅ HTTP 201, matrícula id 1 `ACTIVA` |
| 4 | `docker compose logs matriculas-service` | Registros de arranque y de la petición | ✅ Arranque completo ("Started MatriculasServiceApplication in 36.4 s") e inicialización del `DispatcherServlet` con la primera petición (ver la observación en la evidencia) |
| 5 | `docker compose restart matriculas-service` y `GET /api/matriculas` | Lista vacía | ✅ `totalElements: 0` (antes del reinicio había 1) |
| 6 | `mvn test` en los cinco servicios | 27 pruebas, 0 fallos | ✅ 4 + 3 + 4 + 8 + 8 = 27, 0 fallos |
| 7 | `docker compose down` | Los contenedores se detienen y se eliminan | ✅ 5 contenedores y la red `proyecto-s3_default` eliminados; `docker compose ps` vacío |

Evidencia completa: [Anexo B.11 · Docker, Swagger y pruebas](#b11--docker-swagger-y-pruebas). Salida de `docker compose ps`:

```
NAME                     IMAGE                                STATE     STATUS          PORTS
auth-service             proyecto-s3-auth-service             running   Up 48 seconds   0.0.0.0:8081->8081/tcp, [::]:8081->8081/tcp
calificaciones-service   proyecto-s3-calificaciones-service   running   Up 44 seconds   0.0.0.0:8085->8085/tcp, [::]:8085->8085/tcp
cursos-service           proyecto-s3-cursos-service           running   Up 47 seconds   0.0.0.0:8083->8083/tcp, [::]:8083->8083/tcp
estudiantes-service      proyecto-s3-estudiantes-service      running   Up 47 seconds   0.0.0.0:8082->8082/tcp, [::]:8082->8082/tcp
matriculas-service       proyecto-s3-matriculas-service       running   Up 46 seconds   0.0.0.0:8084->8084/tcp, [::]:8084->8084/tcp
```

Capturas de Swagger (en contenedores):

| auth (8081) | estudiantes (8082) | cursos (8083) |
|---|---|---|
| ![auth](evidencias/capturas/swagger-docker-8081.png) | ![estudiantes](evidencias/capturas/swagger-docker-8082.png) | ![cursos](evidencias/capturas/swagger-docker-8083.png) |

| matrículas (8084) | calificaciones (8085) |
|---|---|
| ![matriculas](evidencias/capturas/swagger-docker-8084.png) | ![calificaciones](evidencias/capturas/swagger-docker-8085.png) |

### 12.2 Preguntas de análisis

**1. ¿Por qué dentro de Docker se usa `http://auth-service:8081` y no `http://localhost:8081`?**

Cada contenedor tiene su **propio espacio de red**, así que dentro de un contenedor `localhost` es **ese mismo contenedor**, no la máquina anfitriona ni los demás. Desde matriculas-service, `localhost:8081` apunta a un puerto donde nadie escucha y daría "connection refused". Docker Compose crea una red *bridge* por proyecto (`proyecto-s3_default`) con un **DNS interno** que resuelve el **nombre de cada servicio** (`auth-service`, `estudiantes-service`…) a la IP del contenedor correspondiente. Por eso `docker-compose.yml` sobrescribe las URL con variables de entorno (`AUTH_SERVICE_URL: http://auth-service:8081`, líneas 12, 23, 34 y 48). Los `application.yaml` las leen con un valor por defecto para la ejecución local (`url: ${AUTH_SERVICE_URL:http://localhost:8081}`). Así, el mismo artefacto funciona en ambos entornos sin recompilar, como recomienda el factor III (configuración) de *12-factor*. Los `ports: "808X:808X"` solo publican los puertos hacia el anfitrión, para el navegador y Swagger.

**2. `depends_on` no espera a que un servicio esté listo. ¿Qué problema causa y cómo se resuelve?**

`depends_on` (forma corta, como en `docker-compose.yml:14, 25, 37, 50`) solo garantiza el **orden de arranque de los contenedores**: matrículas *inicia* después de que el contenedor de auth *inició*, no cuando auth ya acepta peticiones. En la evidencia, matriculas-service tardó **36,4 s** en estar listo después de iniciado su contenedor ("Started … in 36.407 seconds"). Durante esa ventana:

- Un cliente que llame a cursos mientras auth todavía arranca recibe `401 TOKEN_VALIDATION_ERROR`, un error engañoso para un token válido.
- Una matrícula registrada mientras estudiantes o cursos arrancan recibe 502.
- Si un servicio necesitara su dependencia **al arrancar** (cargar configuración, precalentar cachés, migraciones), fallaría y el contenedor terminaría. Además, Compose no tiene `restart:` configurado, así que no se recuperaría solo.

Solución: agregar **healthchecks** y `depends_on` con condición. Por ejemplo, con Spring Boot Actuator:

```yaml
  auth-service:
    build: ./auth-service
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8081/actuator/health | grep -q UP || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 20
      start_period: 20s
  matriculas-service:
    depends_on:
      auth-service:        { condition: service_healthy }
      estudiantes-service: { condition: service_healthy }
      cursos-service:      { condition: service_healthy }
    restart: on-failure
```

Comprobé que la imagen base `eclipse-temurin:21-jre` incluye `curl` y `wget`, así que el healthcheck no requiere instalar nada; solo hay que agregar `spring-boot-starter-actuator`. Además, el código debe ser **tolerante a fallos transitorios** (reintentos con *backoff* en Feign y *circuit breaker*), porque las dependencias también pueden caer después del arranque. Ojo con el ciclo de E1: estudiantes y cursos no pueden esperar a que matrículas esté *healthy* porque matrículas los espera a ellos, así que su healthcheck debe ser de *liveness* propio y no verificar sus dependencias.

**3. Explique la verificación 5. ¿Qué cambiaría para que los datos sobrevivan a un reinicio?**

La URL `jdbc:h2:mem:matriculasdb` (`application.yaml` de matrículas) crea la base **en la memoria del proceso Java**. `DB_CLOSE_DELAY=-1` la mantiene viva mientras dure la JVM, no más. `docker compose restart` detiene el proceso y lo vuelve a lanzar, así que la memoria se libera y la base se crea vacía (`ddl-auto: update` recrea el esquema). Por eso la matrícula que existía antes (paso 3b: `totalElements: 1`) desapareció (paso 5: `totalElements: 0`). En estudiantes y cursos los datos "vuelven" solo porque sus `DataSeeder` los regeneran en cada arranque. Las matrículas y las notas, en cambio, se pierden.

Para persistir los datos:

1. **Base de datos real en un contenedor con volumen** (recomendado): un servicio `postgres` (o un esquema o base por microservicio para respetar *database per service*) con un volumen nombrado (`volumes: [pgdata:/var/lib/postgresql/data]`). Se cambia `spring.datasource.url` a `jdbc:postgresql://postgres:5432/matriculas` por variable de entorno, se agrega el driver y se reemplaza `ddl-auto: update` por migraciones versionadas (Flyway o Liquibase).
2. Opción mínima: H2 **en archivo** (`jdbc:h2:file:/data/matriculasdb`) con un volumen montado en `/data`. Sirve para desarrollo, no para producción.

Además, los `DataSeeder` ya comprueban `count() > 0` antes de sembrar, así que con persistencia no duplicarían datos.

**4. ¿Qué ventajas tendría compilar dentro de Docker (multi-stage)?**

Hoy el `Dockerfile` hace `COPY target/*.jar app.jar`, así que **depende de que alguien haya ejecutado `mvn package` antes** en su máquina. Con un Dockerfile *multi-stage*:

```dockerfile
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY pom.xml .
RUN mvn -B dependency:go-offline          # capa cacheable mientras no cambie el pom
COPY src ./src
RUN mvn -B package -DskipTests

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /src/target/*.jar app.jar
USER 1000
ENTRYPOINT ["java","-jar","/app/app.jar"]
```

Ventajas:

- **Reproducibilidad**: la compilación siempre usa la misma versión de JDK y Maven, independientemente de lo que tenga instalado cada desarrollador. Desaparece el "en mi máquina funciona".
- **Un solo comando** (`docker compose up --build`) construye todo desde el código fuente, sin Java ni Maven en el anfitrión. Se simplifican el CI/CD y la incorporación de nuevos integrantes.
- **Sin artefactos obsoletos**: hoy, si se olvida recompilar, la imagen empaqueta un `.jar` viejo sin avisar.
- **Imagen final pequeña y segura**: solo el JRE y el `.jar`, sin Maven, código fuente ni el `~/.m2` (menor superficie de ataque).
- **Caché de capas**: las dependencias se descargan solo cuando cambia el `pom.xml`.
- Se pueden ejecutar las pruebas como parte de la etapa de build.

Costo: la primera construcción es más lenta y las dependencias se descargan dentro de Docker (se mitiga con la caché de capas o con `--mount=type=cache` de BuildKit).

**5. Las 27 pruebas se ejecutan sin levantar ningún servicio. ¿Qué errores detectan y cuáles no?**

Son **pruebas unitarias** con Mockito (los clientes Feign y los repositorios son *mocks*) y **de *slice*** (`@WebMvcTest` con `AuthClient` simulado en `MatriculaControllerSecurityTest`; `@SpringBootTest` con H2 en `AuthFlowIntegrationTest`, que solo involucra a auth).

*Detectan:*

- Errores en las **reglas de negocio** y sus casos límite: cupo lleno, reducir el cupo por debajo de las activas, duplicados, conteo con exactamente un filtro, no borrar con matrículas activas, notas de matrículas anuladas, cálculo del promedio ponderado.
- Errores en la **traducción de excepciones**: 400 frente a 404 frente a 502, y matrículas caído → `RemoteServiceException`.
- Errores en las **reglas de seguridad** de matrículas (orden de las reglas, 403 en `/mias` para ADMIN) y en la **emisión del JWT** (claim `estudianteId`).
- Regresiones al refactorizar.

*No detectan:*

- **Errores de integración real entre servicios**: un contrato incompatible (por ejemplo, si cursos renombra `cupoMaximo`, el *mock* seguiría devolviendo el campo viejo), anotaciones Feign mal escritas (ruta o parámetro), serialización y deserialización de `RemoteApiResponse`, o propagación del token por el `RequestInterceptor` real.
- **Configuración y despliegue**: URLs y variables de entorno de `docker-compose.yml`, puertos, Dockerfiles, red de Docker, orden de arranque.
- **Disponibilidad y red**: *timeouts*, latencia, servicios caídos de verdad (solo se simula la excepción).
- **Concurrencia**: la condición de carrera del cupo (§8 P2) pasa todas las pruebas, porque cada prueba ejecuta un único hilo.
- **Persistencia real**: restricciones únicas, consultas derivadas mal nombradas o dialecto SQL, salvo en auth.
- El comportamiento de seguridad de **los otros cuatro servicios** (sus `SecurityConfig` no tienen pruebas).

Para cubrirlos se necesitan pruebas de **contrato** (Pact o Spring Cloud Contract), de **integración** con Testcontainers o WireMock, *end-to-end* sobre `docker compose` (como las verificaciones de este informe, que están automatizadas en `informe/scripts/`) y pruebas de carga y concurrencia.

---

## 13. Propuesta de mejora: cupo garantizado bajo concurrencia

### 13.1 Riesgo detectado

La regla de negocio central de E2, **"un curso no puede tener más matrículas activas que su cupo"**, **no se cumple bajo concurrencia**. `MatriculaServiceImpl.registrar` (`:53-73`) cuenta las activas y luego inserta sin ningún bloqueo, y no hay restricción en la base de datos que respalde la regla (a diferencia del correo único o de "una nota por corte").

**Evidencia experimental** ([Anexo B.10 · Experimento de concurrencia](#b10--experimento-de-concurrencia)):

| Ronda | Cupo | Peticiones simultáneas | Matrículas aceptadas |
|---|---|---|---|
| 1 | 1 | 45 | 1 |
| 2 | 1 | 45 | **2** ❌ |
| 3 | 1 | 45 | 1 |
| 4 | 1 | 45 | **3** ❌ |
| 5 | 1 | 45 | 1 |

**Impacto:** sobrecupo real en los periodos de matrícula, que es justo cuando hay más concurrencia: cientos de estudiantes compitiendo por los últimos cupos al abrir inscripciones. Consecuencias: salones sobrecupados, matrículas que hay que anular a mano, reclamos y pérdida de confianza. Las 27 pruebas pasan, porque son de un solo hilo, así que el defecto es **invisible** para la suite actual. Por la misma causa también es posible crear **dos matrículas activas del mismo estudiante en el mismo curso** (regla de duplicado, `:57-59`).

### 13.2 Solución propuesta

Hacer que **la verificación y la escritura sean atómicas por curso**, con un bloqueo pesimista sobre una fila "candado" en la base de matrículas. El cupo sigue siendo propiedad de cursos-service y no se replica.

1. **Nueva entidad** en matriculas-service, `CursoCupo(cursoId PK)`, con una fila por curso que se crea la primera vez que alguien se matricula en él (`INSERT … ON CONFLICT DO NOTHING`, o `MERGE` en H2).
2. **Repositorio con bloqueo:**

   ```java
   @Lock(LockModeType.PESSIMISTIC_WRITE)
   @Query("select c from CursoCupo c where c.cursoId = :cursoId")
   Optional<CursoCupo> bloquear(@Param("cursoId") Long cursoId);   // SELECT … FOR UPDATE
   ```

3. **En `registrar`**, dentro de la misma transacción y **después** de las llamadas remotas, para no retener el bloqueo durante la red:

   ```java
   CursoRemotoDTO curso = obtenerRemoto("curso", () -> cursosClient.buscarPorId(cursoId));   // fuera del lock
   cupoRepository.bloquear(cursoId);              // serializa solo las matrículas de ESTE curso
   if (repository.existsByEstudianteIdAndCursoIdAndEstado(…ACTIVA)) throw …;   // duplicado, ya protegido
   long activas = repository.countByCursoIdAndEstado(cursoId, ACTIVA);
   if (activas >= curso.getCupoMaximo()) throw …;                                // cupo, ya protegido
   return repository.save(matricula);             // el commit libera el lock
   ```

   La segunda transacción que llegue al mismo curso espera en `bloquear` hasta que la primera confirme. Entonces su `count` ya incluye la matrícula nueva y la rechaza correctamente. Las matrículas de **cursos distintos** no se bloquean entre sí.
4. **`anular`** también toma el bloqueo, para que liberar y ocupar un cupo no se crucen.
5. **Respaldo para el duplicado**: en una BD de producción (PostgreSQL), agregar un índice único parcial `CREATE UNIQUE INDEX … ON matricula(estudiante_id, curso_id) WHERE estado = 'ACTIVA'`.
6. **Prueba de regresión**: una prueba de integración (`@SpringBootTest` con H2 y Feign simulado con WireMock) que lance N hilos con `ExecutorService` y un `CountDownLatch` sobre un curso de cupo 1, y que verifique que se acepta **exactamente 1**. Esta prueba fallaría con el código actual, igual que el experimento.

### 13.3 Justificación y alternativas descartadas

| Alternativa | Por qué no (o no sola) |
|---|---|
| `synchronized` o un `Lock` en Java | Solo sirve con **una instancia**. Al escalar matrículas horizontalmente (2+ réplicas) vuelve la carrera. El bloqueo en la BD sí es compartido |
| Aislamiento `SERIALIZABLE` | Correcto, pero aborta transacciones ante el conflicto y obliga a programar reintentos. Afecta a todo el servicio, no solo al registro |
| Copiar el cupo a matrículas y usar `UPDATE … SET activas = activas + 1 WHERE activas < cupo` | Atómico y muy eficiente, pero **replica el cupo**: vuelve el problema de consistencia de §8 P1. Podría ser una evolución si se sincroniza el cupo por eventos |
| Bloqueo distribuido (Redis/Redisson) | Agrega infraestructura nueva para algo que la BD que ya existe resuelve |

El bloqueo pesimista por curso es la opción con **menor cambio** (una entidad, un método de repositorio y unas líneas en el servicio), **correcta con múltiples réplicas**, y con un costo de rendimiento acotado: solo se serializan las matrículas simultáneas **del mismo curso**, y el bloqueo dura unos milisegundos porque las llamadas HTTP quedan fuera de él. La regla de negocio más visible del sistema pasa así de cumplirse "casi siempre" a cumplirse siempre.

---

## 14. Otros hallazgos y riesgos

Observaciones encontradas durante el análisis, que no se implementan:

| # | Hallazgo | Dónde | Riesgo | Recomendación |
|---|---|---|---|---|
| 1 | Secreto JWT en el repositorio, débil y predecible | `auth-service/…/application.yaml:25` | Cualquiera puede firmar tokens de ADMIN (§3 P4, §10 P5) | Variable de entorno o gestor de secretos; RS256 |
| 2 | Consola H2 pública (`permitAll` + `shouldNotFilter`) y `frameOptions().disable()` | `SecurityConfig` y `AuthValidationFilter` de todos los servicios | En un despliegue expuesto, acceso total a cada BD (usuario `sa` sin contraseña) | Deshabilitar `spring.h2.console` fuera del perfil `dev` |
| 3 | auth-service es punto único de fallo y cuello de botella | `AuthValidationFilter` (4 servicios) | Si cae, todo el sistema responde 401 (seguridad, paso 9) | Validación local con clave pública, o caché del resultado de `/auth/validate` |
| 4 | Rol y `estudianteId` del token no se revalidan durante 1 h | `AuthServiceImpl.validate:43-60` | Privilegios retirados siguen activos (§4 P3, §10 P3) | Leer el usuario en `validate` |
| 5 | Ciclos `estudiantes ⇄ matrículas` y `cursos ⇄ matrículas` | Clientes Feign de E1 | Despliegues acoplados, fallas en cascada (§9 P1) | Eliminación lógica o eventos |
| 6 | Sin healthchecks ni `restart` en Compose | `docker-compose.yml` | Errores 401/502 engañosos durante el arranque (§12 P2) | Actuator + `condition: service_healthy` |
| 7 | Sin *timeouts* explícitos ni *circuit breaker* en Feign | Todos los clientes | Un servicio lento bloquea hilos en cadena | Configurar `connectTimeout`/`readTimeout` y Resilience4j |
| 8 | Sin límite de tamaño de página | Listados paginados | `?size=1000000` carga toda la tabla (§5 P5) | `spring.data.web.pageable.max-page-size` |
| 9 | La corrección de una nota sobrescribe `registradoPor` y `fechaRegistro` | `CalificacionServiceImpl.actualizar:60-62` | Se pierde quién registró la nota original | Tabla de historial de cambios |
| 10 | Las peticiones no se registran en el log | Todos los servicios | Difícil diagnosticar en Docker (§12, paso 4) | Access log de Tomcat, *correlation id* propagado por Feign |

---

## Anexo A · Cómo reproducir las evidencias

Todo lo necesario está en `informe/scripts/`. Desde la raíz del repositorio:

```bash
# 0. Compilar y probar (genera target/*.jar y los resúmenes de mvn test)
for s in auth-service estudiantes-service cursos-service matriculas-service calificaciones-service; do
  (cd $s && mvn -B clean package)
done

cd informe/scripts
./servicios.sh start                 # levanta los 5 servicios en local (java -jar)
./fase1-modulos.sh                   # seguridad 1-8, auth, estudiantes, cursos, matrículas 1-9
./servicios.sh stop && ./servicios.sh start
./fase2-extensiones.sh               # E2, E1 1-7, E4, E3
./fase3-caidas.sh                    # matrículas 10, E1 8, seguridad 9 (detiene servicios)

cd ../.. && docker compose up -d --build && cd informe/scripts
./fase4-docker.sh                    # guía de Docker (termina con docker compose down)

pdf/exportar.sh                      # regenera el informe y lo exporta a PDF
```

| Archivo | Contenido |
|---|---|
| `scripts/lib.sh` | Funciones `login`, `tokens`, `paso` (ejecuta la petición y escribe la evidencia en Markdown) y `h2sql` (consulta la consola H2 por HTTP) |
| `scripts/servicios.sh` | Arranque y parada de los servicios en local |
| `scripts/fase*.sh` | Verificaciones de cada guía |
| `scripts/construir_informe.py` | Genera las tablas-resumen y el Anexo B a partir de las evidencias registradas |
| `scripts/pdf/exportar.sh` | Exporta el informe a PDF |

El experimento de concurrencia (§13) se ejecutó con comandos manuales que están documentados en el [Anexo B.10 · Experimento de concurrencia](#b10--experimento-de-concurrencia). Para repetirlo: crear un curso con `cupoMaximo: 1` y lanzar `seq 1 45 | xargs -P45 -I{} curl … -d '{"estudianteId":{},"cursoId":<id>}'`. Al ser una condición de carrera, el sobrecupo no aparece en todas las rondas.


---

<div class="page-break"></div>

## Anexo B · Evidencias completas

Petición HTTP y respuesta JSON de cada paso de verificación, tal como las registraron los scripts descritos en el Anexo A. Los tokens JWT se muestran abreviados como `<token de rol>`.

<div class="page-break"></div>

### B.1 · Seguridad

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

<div class="page-break"></div>

### B.2 · auth-service

#### Paso 1 — POST /auth/login con admin / admin123

**Esperado:** 200 con token, username y role · **Obtenido:** HTTP 200

```http
POST http://localhost:8081/auth/login
Authorization: (sin encabezado Authorization)
Content-Type: application/json

{"username":"admin","password":"admin123"}
```

```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhZG1pbiIsInJvbGUiOiJBRE1JTiIsImlhdCI6MTc5NDUyMzY2OCwiZXhwIjoxNzk0NTI3MjY4fQ.yPrx1KMQSSmaGpTV9yXS4VkdeHgLasRZo7DVmOpM1WI",
  "username": "admin",
  "role": "ADMIN"
}
```

#### Paso 2 — Login con contraseña incorrecta

**Esperado:** 401 AUTH_INVALID_CREDENTIALS · **Obtenido:** HTTP 401

```http
POST http://localhost:8081/auth/login
Authorization: (sin encabezado Authorization)
Content-Type: application/json

{"username":"admin","password":"mala"}
```

```json
{
  "success": false,
  "message": "Credenciales inválidas",
  "errorCode": "AUTH_INVALID_CREDENTIALS",
  "status": 401,
  "path": "/auth/login",
  "timestamp": "2026-11-12T17:47:48.185785719"
}
```

Comprobación adicional (usuario inexistente → mismo mensaje):

#### Paso 2b — Login con usuario inexistente

**Esperado:** 401 AUTH_INVALID_CREDENTIALS, mismo mensaje que el paso 2 · **Obtenido:** HTTP 401

```http
POST http://localhost:8081/auth/login
Authorization: (sin encabezado Authorization)
Content-Type: application/json

{"username":"noexiste","password":"x"}
```

```json
{
  "success": false,
  "message": "Credenciales inválidas",
  "errorCode": "AUTH_INVALID_CREDENTIALS",
  "status": 401,
  "path": "/auth/login",
  "timestamp": "2026-11-12T17:47:48.246284739"
}
```

#### Paso 3 — Login con cuerpo {}

**Esperado:** 400 VALIDATION_ERROR · **Obtenido:** HTTP 400

```http
POST http://localhost:8081/auth/login
Authorization: (sin encabezado Authorization)
Content-Type: application/json

{}
```

```json
{
  "path": "/auth/login",
  "success": false,
  "errorCode": "VALIDATION_ERROR",
  "message": "Error de validación",
  "errors": {
    "password": "must not be blank",
    "username": "must not be blank"
  },
  "status": 400
}
```

#### Paso 4 — GET /auth/validate con token de admin

**Esperado:** 200, valid: true, role: ADMIN · **Obtenido:** HTTP 200

```http
GET http://localhost:8081/auth/validate
Authorization: Bearer <token de admin>
```

```json
{
  "valid": true,
  "username": "admin",
  "role": "ADMIN",
  "estudianteId": null
}
```

#### Paso 5 — GET /auth/validate con token de estudiante

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

#### Paso 6 — GET /auth/validate sin autorizar

**Esperado:** 401 AUTH_INVALID_TOKEN · **Obtenido:** HTTP 401

```http
GET http://localhost:8081/auth/validate
Authorization: (sin encabezado Authorization)
```

```json
{
  "success": false,
  "message": "Debe enviar un token Bearer válido",
  "errorCode": "AUTH_INVALID_TOKEN",
  "status": 401,
  "path": "/auth/validate",
  "timestamp": "2026-11-12T17:47:48.519593032"
}
```

#### Paso 7 — GET /auth/validate con el token alterado (una letra del payload cambiada)

**Esperado:** 401 AUTH_INVALID_TOKEN · **Obtenido:** HTTP 401

```http
GET http://localhost:8081/auth/validate
Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJz…
```

```json
{
  "success": false,
  "message": "Token inválido o expirado",
  "errorCode": "AUTH_INVALID_TOKEN",
  "status": 401,
  "path": "/auth/validate",
  "timestamp": "2026-11-12T17:47:48.583319147"
}
```

#### Paso 8 — Consola H2 (jdbc:h2:mem:authdb): SELECT * FROM usuarios

**Esperado:** contraseñas cifradas y estudiante_id = 1 solo para el estudiante

| ID | USERNAME | ROLE | ESTUDIANTE_ID | PASSWORD |
|---|---|---|---|---|
| 1 | admin | ADMIN | null | $2a$10$VX8RUxhhNCbNhBoe7SNbpOi.e1MU8LjKVgtTEuNNyT2.JB.pkZ.ey |
| 2 | docente | DOCENTE | null | $2a$10$SozYsqj/o3SHR1zJu0CZXO1O1oe8JZkL1cSN6mmyP9PmrBr9Q3p7e |
| 3 | estudiante | ESTUDIANTE | 1 | $2a$10$a22cpqDS.xYrgFjVpX1BpekawFwlsx.hlOWtFJODO5LsEcvZFxxTa |

Decodificación (sin secreto) del payload del token de estudiante — muestra que el contenido del JWT es legible:

```json
{
  "sub": "estudiante",
  "role": "ESTUDIANTE",
  "iat": 1794523666,
  "exp": 1794527266,
  "estudianteId": 1
}
```

<div class="page-break"></div>

### B.3 · estudiantes-service

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

<div class="page-break"></div>

### B.4 · cursos-service

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

<div class="page-break"></div>

### B.5 · matriculas-service

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

<div class="page-break"></div>

### B.6 · Extensión E2 · Cupos

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

<div class="page-break"></div>

### B.7 · Extensión E1 · Integridad entre servicios

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

<div class="page-break"></div>

### B.8 · Extensión E4 · Mis matrículas

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

<div class="page-break"></div>

### B.9 · Extensión E3 · Calificaciones

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

<div class="page-break"></div>

### B.10 · Experimento de concurrencia

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

<div class="page-break"></div>

### B.11 · Docker, Swagger y pruebas

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
