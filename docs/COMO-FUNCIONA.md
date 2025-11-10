# Cómo Funciona Authelia - Explicación Técnica

Esta guía explica exactamente cómo Authelia protege tus aplicaciones y bloquea el acceso no autorizado.

## Concepto Fundamental: ForwardAuth

Authelia utiliza un patrón llamado **Forward Authentication** (ForwardAuth). Este es el concepto clave:

1. **Traefik intercepta** TODAS las peticiones HTTP antes de que lleguen a tu aplicación
2. **Pregunta a Authelia**: "¿Este usuario está autenticado?"
3. **Según la respuesta**, Traefik decide:
   - ✅ **Autenticado** → La petición pasa a la aplicación
   - ❌ **NO autenticado** → Redirige al login de Authelia

**Tu aplicación NUNCA ve peticiones no autenticadas**. Authelia es el guardián de la puerta.

---

## Flujo Técnico Detallado

### Escenario 1: Usuario NO Autenticado (Primera Visita)

```
Usuario intenta acceder a https://miapp.tudominio.com
         │
         ▼
    ┌─────────────┐
    │   Traefik   │ ◄── Punto de entrada (puerto 443)
    │  (Ingress)  │
    └─────────────┘
         │
         │ 1. Middleware "authelia" intercepta la petición
         │
         ▼
    ┌─────────────┐
    │  Authelia   │
    │   /api/verify
    └─────────────┘
         │
         │ 2. Authelia verifica si hay sesión válida
         │    → NO HAY SESIÓN
         │
         ▼
    HTTP 302 Redirect
    Location: https://auth.tudominio.com/?rd=https://miapp.tudominio.com
         │
         ▼
    ┌─────────────┐
    │  Navegador  │ → Redirigido al portal de Authelia
    │  del Usuario│    con "rd" (return destination)
    └─────────────┘
         │
         │ 3. Usuario ve el formulario de login
         │    Ingresa: usuario + password (+ 2FA si está habilitado)
         │
         ▼
    ┌─────────────┐
    │  Authelia   │
    │   /api/login│ → Valida credenciales contra users_database.yml
    └─────────────┘
         │
         │ 4. Si las credenciales son correctas:
         │    - Crea una SESIÓN en SQLite (/config/db.sqlite3)
         │    - Genera una COOKIE firmada (authelia_session)
         │    - Redirige de vuelta a: https://miapp.tudominio.com
         │
         ▼
    HTTP 302 Redirect + Set-Cookie: authelia_session=...
    Location: https://miapp.tudominio.com
         │
         ▼
    Usuario vuelve a intentar acceder a miapp.tudominio.com
         │
         ▼
    ┌─────────────┐
    │   Traefik   │
    └─────────────┘
         │
         │ 5. Middleware intercepta OTRA VEZ
         │    Pero ahora la petición incluye Cookie: authelia_session=...
         │
         ▼
    ┌─────────────┐
    │  Authelia   │
    │   /api/verify
    └─────────────┘
         │
         │ 6. Authelia verifica la cookie:
         │    - Cookie válida? ✓
         │    - Sesión existe en DB? ✓
         │    - No expirada? ✓
         │    - Dominio correcto? ✓
         │
         │ 7. Authelia responde a Traefik:
         │    HTTP 200 OK
         │    Headers: Remote-User: admin
         │             Remote-Groups: admins
         │
         ▼
    ┌─────────────┐
    │   Traefik   │ → Recibe HTTP 200 de Authelia
    └─────────────┘  → PERMITE el acceso
         │
         │ 8. Traefik envía la petición ORIGINAL a la aplicación
         │    + headers adicionales (Remote-User, etc.)
         │
         ▼
    ┌─────────────┐
    │     Tu      │
    │  Aplicación │ ◄── FINALMENTE recibe la petición
    │  (miapp)    │     La app ni siquiera sabe que Authelia existe
    └─────────────┘
```

### Escenario 2: Usuario YA Autenticado (Visitas Posteriores)

```
Usuario accede a https://miapp.tudominio.com
Cookie: authelia_session=xyz123 (guardada en el navegador)
         │
         ▼
    ┌─────────────┐
    │   Traefik   │
    └─────────────┘
         │
         │ 1. Middleware intercepta
         │    Detecta cookie authelia_session
         │
         ▼
    ┌─────────────┐
    │  Authelia   │
    │   /api/verify│ → Valida sesión en < 10ms
    └─────────────┘
         │
         │ 2. Sesión válida → HTTP 200 OK
         │
         ▼
    ┌─────────────┐
    │   Traefik   │ → Permite el acceso
    └─────────────┘
         │
         ▼
    ┌─────────────┐
    │     Tu      │
    │  Aplicación │ ◄── Acceso directo, transparente
    └─────────────┘

TIEMPO TOTAL: < 50ms
```

### Escenario 3: Atacante Intenta Acceder

```
Atacante intenta: https://miapp.tudominio.com
SIN cookie authelia_session
         │
         ▼
    ┌─────────────┐
    │   Traefik   │
    └─────────────┘
         │
         │ 1. Middleware intercepta
         │    NO encuentra cookie
         │
         ▼
    ┌─────────────┐
    │  Authelia   │
    │   /api/verify│ → Sin sesión válida
    └─────────────┘
         │
         │ 2. HTTP 302 Redirect → Login
         │
         ▼
    ┌─────────────┐
    │  Navegador  │ → Redirigido a login
    │  Atacante   │
    └─────────────┘
         │
         │ 3. Atacante ve formulario de login
         │    Necesita: usuario + password (+ 2FA si está habilitado)
         │
         ▼
    ❌ SIN CREDENCIALES = SIN ACCESO

    La aplicación NUNCA recibe la petición del atacante
```

---

## Componentes Clave

### 1. Middleware de Traefik (`k8s/authelia/06-middleware.yaml`)

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: authelia
  namespace: authelia
spec:
  forwardAuth:
    # URL a la que Traefik pregunta antes de permitir acceso
    address: http://authelia.authelia.svc.cluster.local/api/verify?rd=https://auth.TUDOMINIO.COM

    # Traefik confía en los headers de la respuesta
    trustForwardHeader: true

    # Headers que Authelia añade a la petición
    # Tu aplicación puede leer estos headers para saber quién accede
    authResponseHeaders:
      - Remote-User      # ej: "admin"
      - Remote-Groups    # ej: "admins"
      - Remote-Name      # ej: "Administrador"
      - Remote-Email     # ej: "admin@tudominio.com"
```

**¿Qué hace este middleware?**

Cada vez que Traefik recibe una petición a un servicio protegido:

1. **PAUSA** la petición
2. **LLAMA** a `http://authelia:9091/api/verify`
3. **ESPERA** la respuesta de Authelia:
   - `200 OK` → Permite el acceso
   - `302 Redirect` → Redirige al login
   - `401 Unauthorized` → Bloquea el acceso
4. **SOLO SI ES 200**, envía la petición a tu aplicación

### 2. Endpoint `/api/verify` de Authelia

Este endpoint es la **función de verificación**:

```
Input:
  - Cookie: authelia_session=...
  - Header: X-Forwarded-Host: miapp.tudominio.com
  - Header: X-Forwarded-Uri: /alguna/ruta

Proceso:
  1. Extrae la cookie
  2. Busca la sesión en la base de datos SQLite
  3. Verifica:
     - ¿La sesión existe?
     - ¿No ha expirado?
     - ¿El dominio coincide?
     - ¿El usuario cumple las políticas de access_control?

Output (si todo OK):
  HTTP 200 OK
  Remote-User: admin
  Remote-Groups: admins
  Remote-Name: Administrador
  Remote-Email: admin@tudominio.com

Output (si falta autenticación):
  HTTP 302 Found
  Location: https://auth.tudominio.com/?rd=https://miapp.tudominio.com
```

### 3. Sesiones (Storage)

Las sesiones se guardan en **SQLite** (`/config/db.sqlite3`):

```sql
-- Tabla de sesiones (simplificado)
CREATE TABLE user_sessions (
    id TEXT PRIMARY KEY,
    user TEXT NOT NULL,
    created_at TIMESTAMP,
    last_activity TIMESTAMP,
    expiration TIMESTAMP,
    domain TEXT,
    ip_address TEXT,
    user_agent TEXT
);
```

**Cada sesión contiene:**
- ID único (generado aleatoriamente)
- Usuario asociado
- Timestamp de creación y última actividad
- Fecha de expiración
- Dominio para el que es válida
- IP y User-Agent para seguridad adicional

### 4. Cookie de Sesión

Cuando te autentificas, Authelia te da una cookie:

```
Set-Cookie: authelia_session=eyJhbGc...base64_encoded...;
            Domain=.tudominio.com;
            Path=/;
            Expires=Wed, 10 Nov 2025 12:00:00 GMT;
            Secure;
            HttpOnly;
            SameSite=Lax
```

**Características de seguridad:**
- **HttpOnly**: JavaScript no puede leer la cookie (protección XSS)
- **Secure**: Solo se envía por HTTPS
- **SameSite=Lax**: Protección contra CSRF
- **Domain=.tudominio.com**: Válida para todos los subdominios

---

## Políticas de Acceso

En `k8s/authelia/02-configmap.yaml`:

```yaml
access_control:
  default_policy: deny  # Por defecto, TODO está bloqueado

  rules:
    # Portal de Authelia - sin protección (sino loop infinito)
    - domain: "auth.tudominio.com"
      policy: bypass

    # Servicios protegidos con 1 factor (usuario + password)
    - domain: "*.tudominio.com"
      policy: one_factor

    # Servicios críticos con 2FA obligatorio
    - domain: "admin.tudominio.com"
      policy: two_factor
```

**Tipos de políticas:**

1. **bypass**: Sin autenticación (público)
2. **one_factor**: Usuario + password
3. **two_factor**: Usuario + password + TOTP (2FA)
4. **deny**: Siempre bloqueado

---

## Ejemplo Práctico con Código

Vamos a ver qué pasa con una petición real:

### 1. Configuración del Ingress de tu app

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mi-app
  namespace: default
  annotations:
    # ESTA LÍNEA es la que activa la protección
    traefik.ingress.kubernetes.io/router.middlewares: authelia-authelia@kubernetescrd
spec:
  rules:
  - host: miapp.tudominio.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: mi-app
            port:
              number: 80
```

### 2. ¿Qué hace Traefik con esta anotación?

Traefik lee: `router.middlewares: authelia-authelia@kubernetescrd`

Y ejecuta internamente (pseudocódigo):

```python
def handle_request(request):
    # 1. Buscar el middleware
    middleware = get_middleware("authelia", "authelia")

    # 2. Llamar a Authelia
    auth_response = http.get(
        "http://authelia.authelia.svc.cluster.local/api/verify",
        headers={
            "X-Forwarded-Host": request.host,  # miapp.tudominio.com
            "X-Forwarded-Uri": request.path,   # /
            "X-Forwarded-Method": request.method  # GET
        },
        cookies=request.cookies  # Incluye authelia_session si existe
    )

    # 3. Decidir según la respuesta
    if auth_response.status_code == 200:
        # ✅ AUTENTICADO
        # Añadir headers de Authelia a la petición original
        request.headers["Remote-User"] = auth_response.headers["Remote-User"]
        request.headers["Remote-Groups"] = auth_response.headers["Remote-Groups"]

        # Enviar a la aplicación
        return proxy_to_app(request)

    elif auth_response.status_code == 302:
        # ❌ NO AUTENTICADO
        # Redirigir al login
        return redirect(auth_response.headers["Location"])

    else:
        # ⛔ ERROR
        return error_503("Service Unavailable")
```

### 3. Tu aplicación recibe la petición

Si tu aplicación lee los headers, puede saber quién es el usuario:

**En Node.js/Express:**
```javascript
app.get('/', (req, res) => {
    const user = req.headers['remote-user'];  // "admin"
    const groups = req.headers['remote-groups'];  // "admins"

    res.send(`Hola ${user}, perteneces a los grupos: ${groups}`);
});
```

**En Python/Flask:**
```python
@app.route('/')
def index():
    user = request.headers.get('Remote-User')  # "admin"
    groups = request.headers.get('Remote-Groups')  # "admins"

    return f"Hola {user}, perteneces a los grupos: {groups}"
```

**Importante:** Estos headers **SOLO** los puede poner Authelia. Un atacante NO puede falsificarlos porque Traefik los elimina antes de llamar a Authelia.

---

## Protección Contra Ataques

### Ataque 1: Intentar saltarse Authelia accediendo directamente al Service

```bash
# Atacante intenta acceder directamente al pod
kubectl port-forward -n default pod/mi-app-xxx 8080:80
curl http://localhost:8080
```

**Resultado:** ✅ **Bloqueado** (si el servicio solo acepta tráfico de Traefik)

**Mejor práctica:** Configurar NetworkPolicy para que solo Traefik pueda hablar con tus pods:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-only-from-traefik
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: mi-app
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: kube-system  # Namespace de Traefik
```

### Ataque 2: Intentar falsificar la cookie

```bash
curl -H "Cookie: authelia_session=fake-token" https://miapp.tudominio.com
```

**Resultado:** ❌ **Bloqueado**

**Por qué:**
1. La cookie está **firmada criptográficamente** con el `SESSION_SECRET`
2. Authelia valida la firma antes de leer el contenido
3. Si la firma no coincide → sesión inválida → redirect a login

### Ataque 3: Robar la cookie de sesión (Session Hijacking)

```bash
# Atacante roba tu cookie (ej: XSS, man-in-the-middle)
curl -H "Cookie: authelia_session=tu-token-real" https://miapp.tudominio.com
```

**Resultado:** Depende de la configuración

**Protecciones activadas por defecto:**
1. **HttpOnly**: JavaScript no puede leer la cookie
2. **Secure**: Solo funciona en HTTPS
3. **SameSite=Lax**: Protección contra CSRF
4. **IP binding** (opcional): Authelia puede validar que la IP coincida

### Ataque 4: Fuerza bruta en el login

```bash
# Atacante intenta adivinar passwords
for pwd in password123 admin123 qwerty; do
    curl -X POST https://auth.tudominio.com/api/login \
         -d "username=admin&password=$pwd"
done
```

**Resultado:** ❌ **Bloqueado después de 3 intentos**

**Protección:** Configurada en `k8s/authelia/02-configmap.yaml`:

```yaml
regulation:
  max_retries: 3        # Máximo 3 intentos fallidos
  find_time: 2m         # En una ventana de 2 minutos
  ban_time: 5m          # Bloqueo de 5 minutos
```

---

## Monitoreo y Logs

### Ver intentos de acceso

```bash
# Logs de Authelia
kubectl -n authelia logs -f deployment/authelia

# Ejemplo de log de acceso exitoso:
# level=info msg="Successful 1FA authentication" username=admin

# Ejemplo de log de acceso bloqueado:
# level=warn msg="Unsuccessful 1FA authentication" username=admin error="Invalid credentials"
```

### Ver sesiones activas

```bash
# Acceder a la base de datos SQLite
kubectl -n authelia exec -it deployment/authelia -- sh

# Dentro del pod:
sqlite3 /config/db.sqlite3

# Ver sesiones activas:
SELECT user, created_at, last_activity, ip_address
FROM user_sessions
WHERE expiration > datetime('now');
```

---

## Resumen: ¿Por Qué Es Seguro?

1. **Interceptación obligatoria**: Traefik NO puede enviar tráfico a tu app sin pasar por Authelia
2. **Verificación en cada petición**: Incluso con sesión válida, se verifica en cada request
3. **Cookies firmadas**: Imposible falsificar sin conocer el `SESSION_SECRET`
4. **Default deny**: Por defecto TODO está bloqueado, debes permitir explícitamente
5. **Protección contra fuerza bruta**: Límite de intentos de login
6. **2FA opcional**: Para servicios críticos, puedes exigir TOTP
7. **Sesiones con expiración**: Las sesiones caducan automáticamente
8. **HTTPS obligatorio**: Toda la comunicación cifrada

**En resumen:** Un atacante necesitaría:
- Tener credenciales válidas (usuario + password)
- Pasar el 2FA (si está habilitado)
- O robar una cookie firmada (muy difícil con HTTPS)

Y aún así, la sesión expiraría después de un tiempo configurable.

---

## Diagrama Visual Simplificado

```
Internet → Firewall (80/443) → Raspberry Pi (192.168.1.95)
                                       │
                                       ▼
                                  ┌──────────┐
                                  │  Traefik │ (Puerto 443)
                                  │  Ingress │
                                  └──────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    │                  │                  │
                    ▼                  ▼                  ▼
            ┌──────────────┐   ┌──────────────┐  ┌──────────────┐
            │ Middleware   │   │ Middleware   │  │ Middleware   │
            │  "authelia"  │   │  "authelia"  │  │  "authelia"  │
            └──────────────┘   └──────────────┘  └──────────────┘
                    │                  │                  │
                    └──────────────────┼──────────────────┘
                                       │
                         Todos preguntan a Authelia
                                       │
                                       ▼
                              ┌─────────────────┐
                              │    Authelia     │
                              │   /api/verify   │
                              └─────────────────┘
                                       │
                        ┌──────────────┴──────────────┐
                        │                             │
                   ¿Autenticado?                ¿No autenticado?
                        │                             │
                    200 OK                      302 Redirect
                        │                             │
                        ▼                             ▼
              ┌──────────────────┐          ┌──────────────────┐
              │  Permite acceso  │          │  Portal Login    │
              │  a la app        │          │  de Authelia     │
              └──────────────────┘          └──────────────────┘
```

---

¿Quieres que profundice en algún aspecto específico del funcionamiento?
