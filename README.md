# Authelia para K3s - Autenticación Centralizada

Este proyecto contiene todos los archivos necesarios para desplegar **Authelia** como capa de autenticación centralizada en tu cluster K3s con Traefik.

## ¿Qué es Authelia?

Authelia es un servidor de autenticación y autorización de código abierto que proporciona autenticación de dos factores y inicio de sesión único (SSO) a tus aplicaciones mediante un portal web. Actúa como middleware entre tu reverse proxy (Traefik) y tus servicios, protegiendo todos tus servicios web con un único punto de autenticación.

**¿Quieres entender cómo funciona técnicamente?** Consulta la guía detallada: [docs/COMO-FUNCIONA.md](docs/COMO-FUNCIONA.md) donde se explica el flujo completo de autenticación, cómo se interceptan las peticiones, y cómo se bloquea el acceso no autorizado.

## Características

- ✅ **Autenticación centralizada**: Un único login para todos tus servicios
- ✅ **Integración con Traefik**: Funciona nativamente con K3s
- ✅ **2FA opcional**: TOTP (Google Authenticator, Authy, etc.)
- ✅ **Ligero**: Perfecto para Raspberry Pi
- ✅ **Sin modificar aplicaciones**: Protege servicios sin tocar su código
- ✅ **Políticas flexibles**: Diferentes niveles de seguridad por servicio

## ⚠️ Alcance Importante

**Authelia SOLO protege servicios HTTP/HTTPS (puertos 80 y 443)** que pasen por Traefik Ingress.

- ✅ **SÍ afecta**: Aplicaciones web, APIs REST, paneles de administración web
- ❌ **NO afecta**: SSH (22), Minecraft (19132), bases de datos, otros servicios TCP/UDP

Tu SSH, servidor de Minecraft y otros servicios **seguirán funcionando exactamente igual**. Solo se protegen los servicios web que explícitamente configures con el middleware de Authelia.

**Más detalles:** Ver [FAQ - ¿Qué puertos y servicios afecta?](docs/FAQ.md#qué-puertos-y-servicios-afecta-authelia)

## Estructura del Proyecto

```
.
├── k8s/
│   ├── authelia/              # Manifiestos de Kubernetes para Authelia
│   │   ├── 00-namespace.yaml  # Namespace para Authelia
│   │   ├── 01-pvc.yaml        # Almacenamiento persistente
│   │   ├── 02-configmap.yaml  # Configuración de Authelia
│   │   ├── 03-secret.yaml     # Secretos y usuarios
│   │   ├── 04-deployment.yaml # Deployment de Authelia
│   │   ├── 05-service.yaml    # Service de Authelia
│   │   ├── 06-middleware.yaml # Middleware de Traefik
│   │   └── 07-ingress.yaml    # Ingress para el portal
│   └── examples/              # Ejemplos de servicios protegidos
│       ├── ejemplo-servicio-protegido.yaml
│       ├── ejemplo-kubernetes-dashboard.yaml
│       └── ejemplo-multiples-servicios.yaml
├── scripts/                   # Scripts de utilidad
│   ├── generate-secrets.sh    # Generar secretos aleatorios
│   ├── generate-password.sh   # Generar hash de passwords
│   ├── customize-domain.sh    # Personalizar dominio
│   ├── deploy.sh             # Desplegar Authelia
│   └── uninstall.sh          # Desinstalar Authelia
├── docs/                      # Documentación adicional
│   ├── QUICKSTART.md         # Guía de inicio rápido
│   ├── COMO-FUNCIONA.md      # Explicación técnica del flujo de autenticación
│   ├── FAQ.md                # Preguntas frecuentes
│   ├── SSL-EXISTENTE.md      # Usar certificados SSL existentes
│   └── CERT-MANAGER.md       # Configurar cert-manager
└── README.md                  # Esta guía
```

## Pre-requisitos

Antes de comenzar, asegúrate de tener:

1. **Cluster K3s funcionando** en tu Raspberry Pi (o cualquier servidor)
2. **Traefik** como Ingress Controller (viene por defecto en K3s)
3. **kubectl** configurado para acceder a tu cluster
4. **Un dominio** configurado apuntando a tu IP pública
5. **Puertos 80 y 443** abiertos y redirigidos a tu Raspberry Pi (192.168.1.95)
6. **Certificados SSL** configurados (Let's Encrypt u otro) - Si ya los tienes, ¡perfecto! Si no, consulta `docs/CERT-MANAGER.md`
7. **Docker** instalado (solo para generar passwords, opcional)

## Instalación Rápida

### Paso 1: Personalizar el Dominio

Reemplaza `TUDOMINIO.COM` en todos los archivos con tu dominio real:

```bash
./scripts/customize-domain.sh midominio.com
```

### Paso 2: Generar Secretos

Genera secretos aleatorios seguros:

```bash
./scripts/generate-secrets.sh
```

Copia los valores generados y pégalos en `k8s/authelia/03-secret.yaml` reemplazando las líneas que empiezan con `CAMBIAR_ESTE_SECRET`.

### Paso 3: Configurar Usuarios

Por defecto, hay un usuario `admin` con password `password`. **Debes cambiarlo**.

Para generar un nuevo password hasheado:

```bash
./scripts/generate-password.sh
```

O si prefieres especificar el password directamente:

```bash
./scripts/generate-password.sh miPasswordSeguro123
```

Copia el hash generado y actualiza el usuario en `k8s/authelia/03-secret.yaml` en la sección `users_database.yml`.

### Paso 4: Desplegar Authelia

```bash
./scripts/deploy.sh
```

Este script desplegará todos los recursos en el orden correcto.

### Paso 5: Verificar el Despliegue

Verifica que el pod esté corriendo:

```bash
kubectl -n authelia get pods
```

Ver los logs:

```bash
kubectl -n authelia logs -f deployment/authelia
```

### Paso 6: Acceder al Portal

Una vez que el pod esté en estado `Running`, accede a:

```
https://auth.tudominio.com
```

Deberías ver el portal de login de Authelia.

**Nota sobre SSL/TLS:**
- Si ya tienes certificados SSL configurados (ej: Let's Encrypt con cert-manager o wildcard certificate), Authelia usará automáticamente el certificado existente para `auth.tudominio.com`
- Si tienes un certificado wildcard (`*.tudominio.com`), todos tus subdominios ya estarán cubiertos
- Si NO tienes SSL configurado, consulta `docs/CERT-MANAGER.md` para configurar certificados automáticos

Credenciales por defecto (CÁMBIALAS):
- Usuario: `admin`
- Password: `password`

## Proteger tus Servicios

### Opción 1: Proteger un Ingress Existente

Si ya tienes un servicio con un Ingress, solo necesitas añadir una anotación:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mi-servicio
  namespace: default
  annotations:
    # Esta línea protege tu servicio con Authelia
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
            name: mi-servicio
            port:
              number: 80
```

### Opción 2: Crear el Middleware en Otro Namespace

Si tu servicio está en un namespace diferente a `default`, puedes crear el middleware directamente en ese namespace:

```bash
kubectl apply -f - <<EOF
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: authelia
  namespace: MI-NAMESPACE
spec:
  forwardAuth:
    address: http://authelia.authelia.svc.cluster.local/api/verify?rd=https://auth.tudominio.com
    trustForwardHeader: true
    authResponseHeaders:
      - Remote-User
      - Remote-Groups
      - Remote-Name
      - Remote-Email
EOF
```

Luego usa el middleware en tu Ingress:

```yaml
annotations:
  traefik.ingress.kubernetes.io/router.middlewares: MI-NAMESPACE-authelia@kubernetescrd
```

### Ejemplos Completos

Revisa la carpeta `k8s/examples/` para ver ejemplos completos de:

- Servicio básico protegido
- Kubernetes Dashboard protegido
- Múltiples servicios con diferentes políticas de seguridad

## Configuración Avanzada

### Políticas de Acceso Personalizadas

Edita `k8s/authelia/02-configmap.yaml` en la sección `access_control.rules` para definir políticas específicas:

```yaml
access_control:
  default_policy: deny
  rules:
    # Portal de Authelia - sin protección
    - domain: "auth.tudominio.com"
      policy: bypass

    # Servicios públicos - sin protección
    - domain: "www.tudominio.com"
      policy: bypass

    # Servicios internos - un factor (usuario + password)
    - domain: "*.tudominio.com"
      policy: one_factor

    # Servicios críticos - dos factores (usuario + password + TOTP)
    - domain: "admin.tudominio.com"
      policy: two_factor
```

Políticas disponibles:
- **bypass**: Sin autenticación
- **one_factor**: Usuario + password
- **two_factor**: Usuario + password + TOTP

### Añadir Más Usuarios

Edita `k8s/authelia/03-secret.yaml` en la sección `users_database.yml`:

```yaml
users:
  admin:
    displayname: "Administrador"
    password: "$argon2id$v=19$..."
    email: admin@tudominio.com
    groups:
      - admins

  usuario2:
    displayname: "Usuario 2"
    password: "$argon2id$v=19$..."  # Genera con ./scripts/generate-password.sh
    email: usuario2@tudominio.com
    groups:
      - users
```

Después de modificar, aplica los cambios:

```bash
kubectl apply -f k8s/authelia/03-secret.yaml
kubectl rollout restart deployment/authelia -n authelia
```

### Configurar 2FA (TOTP)

1. Inicia sesión en Authelia
2. Ve a tu perfil (icono de usuario arriba a la derecha)
3. Haz clic en "Register device"
4. Escanea el código QR con tu app de autenticación (Google Authenticator, Authy, etc.)
5. Ingresa el código de 6 dígitos para confirmar

### Configurar Notificaciones por Email (Opcional)

Si quieres recibir notificaciones por email, edita `k8s/authelia/02-configmap.yaml`:

```yaml
notifier:
  disable_startup_check: false
  smtp:
    host: smtp.gmail.com
    port: 587
    username: tuusuario@gmail.com
    password: tupassword  # Mejor usar un secret
    sender: authelia@tudominio.com
    subject: "[Authelia] {title}"
```

## Troubleshooting

### El pod no arranca

Ver los logs:

```bash
kubectl -n authelia logs deployment/authelia
```

### No puedo acceder al portal

1. Verifica que el DNS apunta a tu IP:
   ```bash
   nslookup auth.tudominio.com
   ```

2. Verifica que el Ingress está creado:
   ```bash
   kubectl -n authelia get ingress
   ```

3. Verifica que Traefik está funcionando:
   ```bash
   kubectl -n kube-system get pods | grep traefik
   ```

### Los servicios protegidos muestran error 502

1. Verifica que Authelia está corriendo:
   ```bash
   kubectl -n authelia get pods
   ```

2. Verifica que el middleware está aplicado correctamente:
   ```bash
   kubectl describe ingress MI-INGRESS -n MI-NAMESPACE
   ```

### Olvidé mi password

1. Genera un nuevo password hash:
   ```bash
   ./scripts/generate-password.sh nuevoPassword123
   ```

2. Edita el secret:
   ```bash
   kubectl edit secret authelia-users -n authelia
   ```

3. Reemplaza el hash del password (debe estar en base64)

4. Reinicia el deployment:
   ```bash
   kubectl rollout restart deployment/authelia -n authelia
   ```

## Desinstalar

Para desinstalar Authelia completamente:

```bash
./scripts/uninstall.sh
```

Esto eliminará todos los recursos excepto el namespace. Si también quieres eliminar el namespace (y todos los datos), el script te preguntará.

## Seguridad

### Recomendaciones

1. **Cambia el password por defecto** inmediatamente
2. **Genera secretos aleatorios** únicos con `./scripts/generate-secrets.sh`
3. **Usa HTTPS/TLS** para todos los servicios (configura cert-manager para certificados automáticos)
4. **Habilita 2FA** para servicios críticos
5. **Guarda los secretos** en un lugar seguro (password manager)
6. **Actualiza Authelia** regularmente

### Certificados SSL/TLS

#### Si ya tienes SSL configurado

Si ya tienes certificados SSL en tu cluster (Let's Encrypt, wildcard, etc.), **Authelia los usará automáticamente**. Consulta la guía detallada: [docs/SSL-EXISTENTE.md](docs/SSL-EXISTENTE.md)

#### Si necesitas configurar SSL desde cero

Para configurar certificados SSL automáticos con Let's Encrypt:

1. Instala cert-manager en tu cluster
2. Crea un ClusterIssuer para Let's Encrypt
3. Añade las anotaciones en los Ingress:

```yaml
annotations:
  cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - auth.tudominio.com
    secretName: authelia-tls
```

**Guía completa:** [docs/CERT-MANAGER.md](docs/CERT-MANAGER.md)

## Recursos Adicionales

- [Documentación oficial de Authelia](https://www.authelia.com/docs/)
- [Integración con Traefik](https://www.authelia.com/integration/proxies/traefik/)
- [Configuración de access control](https://www.authelia.com/configuration/security/access-control/)

## Soporte

Si tienes problemas o preguntas:

1. Revisa la sección de [Troubleshooting](#troubleshooting)
2. Consulta los logs: `kubectl -n authelia logs -f deployment/authelia`
3. Revisa la [documentación oficial de Authelia](https://www.authelia.com/docs/)

## Licencia

Este proyecto de configuración está disponible para uso libre. Authelia está bajo licencia Apache 2.0.

---

**¡Disfruta de tus servicios protegidos con Authelia!** 🔒
