# Preguntas Frecuentes (FAQ)

## General

### ¿Qué es Authelia?

Authelia es un servidor de autenticación de código abierto que actúa como middleware entre tu reverse proxy y tus aplicaciones. Proporciona autenticación de dos factores y SSO (Single Sign-On) sin modificar el código de tus aplicaciones.

### ¿Por qué usar Authelia en lugar de Keycloak?

**Authelia** es ideal para tu caso porque:
- Es mucho más ligero (perfecto para Raspberry Pi)
- No requiere configurar OAuth2/OIDC en cada aplicación
- Instalación y configuración más simple
- Protección transparente: no tocas el código de las apps

**Keycloak** es mejor si:
- Necesitas un sistema complejo de roles y permisos
- Tienes múltiples aplicaciones que ya soportan OAuth2/OIDC
- Necesitas federación de identidades con otros proveedores

Para protección simple y centralizada de servicios web, Authelia es la mejor opción.

### ¿Funciona con cualquier aplicación web?

Sí, Authelia funciona con **cualquier** aplicación web, sin importar el lenguaje o framework. Solo protege el acceso HTTP/HTTPS, no necesita integración especial.

### ¿Qué puertos y servicios afecta Authelia?

**Authelia SOLO afecta a servicios HTTP/HTTPS (puertos 80 y 443)** que pasen por Traefik Ingress.

**✅ Servicios que SÍ protege:**
- Aplicaciones web accesibles por HTTP/HTTPS
- Paneles de administración web
- APIs REST expuestas vía Ingress
- Cualquier servicio con un Ingress de Kubernetes que tenga el middleware de Authelia

**❌ Servicios que NO afecta:**
- SSH (puerto 22) - Seguirá funcionando normalmente
- Minecraft (puerto 19132) - Sin cambios
- Bases de datos (MySQL, PostgreSQL, MongoDB, etc.)
- Servicios TCP/UDP que no sean HTTP
- Servicios expuestos por NodePort o LoadBalancer sin Ingress

**Ejemplo en tu Raspberry Pi:**
```
Puerto 22 (SSH)        → No protegido por Authelia, usa autenticación SSH
Puerto 80 (HTTP)       → Protegido por Authelia (solo servicios con middleware)
Puerto 443 (HTTPS)     → Protegido por Authelia (solo servicios con middleware)
Puerto 19132 (Minecraft) → No protegido por Authelia, funciona normal
```

**Importante:** Incluso en los puertos 80/443, solo se protegen los servicios que **explícitamente** tengan el middleware de Authelia en su Ingress. Los servicios sin el middleware seguirán siendo accesibles sin autenticación.

### ¿Puedo proteger servicios no-HTTP como SSH o bases de datos?

No, Authelia es específicamente para HTTP/HTTPS. Para otros servicios:

- **SSH (puerto 22)**: Usa autenticación por clave SSH y/o configuración de `sshd_config`
- **Minecraft**: Usa whitelist del servidor (`whitelist.json`)
- **Bases de datos**: Usa autenticación nativa del motor (usuarios/passwords de MySQL, PostgreSQL, etc.)
- **Otros servicios TCP/UDP**: Usa NetworkPolicies de Kubernetes o firewall (iptables/ufw)

## Instalación

### ¿Necesito tener Traefik instalado?

Sí. K3s viene con Traefik por defecto, así que probablemente ya lo tienes. Para verificar:

```bash
kubectl get pods -n kube-system | grep traefik
```

### ¿Puedo usar Nginx en lugar de Traefik?

Sí, pero tendrías que modificar los manifiestos. Este proyecto está configurado para Traefik que viene por defecto en K3s. Si usas Nginx, consulta la [documentación de Authelia para Nginx](https://www.authelia.com/integration/proxies/nginx/).

### ¿Funciona en otros clusters además de K3s?

Sí, funciona en cualquier cluster Kubernetes. Solo asegúrate de tener Traefik instalado o adapta la configuración para tu ingress controller.

### ¿Necesito tener un certificado SSL?

Authelia funciona tanto con HTTP como HTTPS, pero **se recomienda encarecidamente usar HTTPS** para seguridad. Puedes usar cert-manager para obtener certificados gratuitos de Let's Encrypt automáticamente.

## Configuración

### ¿Cómo añado más usuarios?

Edita el archivo `k8s/authelia/03-secret.yaml` y añade más usuarios en la sección `users_database.yml`:

```yaml
users:
  admin:
    displayname: "Admin"
    password: "$argon2id$..."
    email: admin@midominio.com
    groups:
      - admins

  nuevo_usuario:
    displayname: "Nuevo Usuario"
    password: "$argon2id$..."  # Genera con ./scripts/generate-password.sh
    email: nuevo@midominio.com
    groups:
      - users
```

Aplica los cambios:

```bash
kubectl apply -f k8s/authelia/03-secret.yaml
kubectl rollout restart deployment/authelia -n authelia
```

### ¿Cómo cambio el password de un usuario?

1. Genera el nuevo hash:
   ```bash
   ./scripts/generate-password.sh nuevoPassword
   ```

2. Edita `k8s/authelia/03-secret.yaml` y reemplaza el hash

3. Aplica los cambios:
   ```bash
   kubectl apply -f k8s/authelia/03-secret.yaml
   kubectl rollout restart deployment/authelia -n authelia
   ```

### ¿Puedo proteger solo algunos servicios y dejar otros públicos?

¡Sí! Hay dos formas:

**Opción 1**: No añadas el middleware a los servicios públicos.

**Opción 2**: Usa políticas de `bypass` en la configuración de Authelia:

```yaml
access_control:
  default_policy: one_factor
  rules:
    - domain: "publico.midominio.com"
      policy: bypass  # Sin autenticación

    - domain: "privado.midominio.com"
      policy: one_factor  # Con autenticación
```

### ¿Cómo configuro diferentes niveles de seguridad?

Usa las políticas de acceso en `k8s/authelia/02-configmap.yaml`:

```yaml
access_control:
  default_policy: deny
  rules:
    # Sin autenticación
    - domain: "www.midominio.com"
      policy: bypass

    # Usuario + password
    - domain: "app.midominio.com"
      policy: one_factor

    # Usuario + password + 2FA
    - domain: "admin.midominio.com"
      policy: two_factor
```

### ¿Puedo usar LDAP/Active Directory en lugar del archivo de usuarios?

Sí, edita `k8s/authelia/02-configmap.yaml` y cambia `authentication_backend`:

```yaml
authentication_backend:
  ldap:
    url: ldap://tu-servidor-ldap:389
    base_dn: dc=example,dc=com
    username_attribute: uid
    additional_users_dn: ou=users
    users_filter: (&({username_attribute}={input})(objectClass=person))
    user: cn=admin,dc=example,dc=com
    password: password  # Mejor usar un secret
```

### ¿Cómo creo usuarios con diferentes roles y cómo leo esta información desde mis aplicaciones?

Para crear usuarios, asignar grupos (roles), y leer esta información desde tus aplicaciones frontend y backend, consulta la **guía completa**: [docs/USUARIOS-Y-ROLES.md](USUARIOS-Y-ROLES.md)

Esta guía incluye:
- Cómo añadir usuarios y asignar grupos
- Configurar políticas de acceso basadas en grupos
- Leer headers de usuario desde frontend (React, Vue, JavaScript)
- Leer headers desde backend (Node.js, Python, Go, PHP, Java)
- Ejemplos prácticos de autorización basada en roles
- Mejores prácticas de seguridad

**Resumen rápido:**
Los usuarios reciben grupos (roles) en `k8s/authelia/03-secret.yaml`, y tus aplicaciones pueden leer esta información desde los headers:
- `Remote-User`: Nombre de usuario
- `Remote-Groups`: Grupos separados por comas (ej: `admins,developers`)
- `Remote-Email`: Email del usuario
- `Remote-Name`: Nombre completo

## Uso

### ¿Cómo configuro 2FA?

1. Inicia sesión en Authelia
2. Haz clic en tu usuario (arriba a la derecha)
3. Selecciona "Register device"
4. Escanea el QR con Google Authenticator, Authy, etc.
5. Ingresa el código de verificación

### ¿Puedo usar 2FA para todos los servicios o solo algunos?

Puedes configurarlo por dominio. En `k8s/authelia/02-configmap.yaml`:

```yaml
access_control:
  rules:
    # Servicios normales - solo password
    - domain: "app.midominio.com"
      policy: one_factor

    # Servicios críticos - password + 2FA obligatorio
    - domain: "admin.midominio.com"
      policy: two_factor
```

### ¿Cuánto tiempo dura la sesión?

Por defecto:
- **Sesión activa**: 1 hora
- **Inactividad máxima**: 5 minutos
- **Recordar sesión**: 1 mes

Puedes cambiar esto en `k8s/authelia/02-configmap.yaml`:

```yaml
session:
  expiration: 1h
  inactivity: 5m
  remember_me_duration: 1M
```

### ¿Se cierra la sesión si reinicio Authelia?

No, las sesiones se guardan en la base de datos SQLite en el PersistentVolume, por lo que sobreviven reinicios.

## Troubleshooting

### El pod de Authelia no inicia

Ver los logs:

```bash
kubectl -n authelia logs deployment/authelia
```

Causas comunes:
- Secretos mal configurados
- ConfigMap con errores de sintaxis YAML
- PVC no puede montar el volumen

### Error 502 al acceder a un servicio protegido

Causas comunes:

1. Authelia no está corriendo:
   ```bash
   kubectl -n authelia get pods
   ```

2. Middleware mal configurado - verifica la anotación:
   ```bash
   kubectl describe ingress MI-INGRESS -n MI-NAMESPACE
   ```

3. El servicio de Authelia no está accesible:
   ```bash
   kubectl -n authelia get svc
   ```

### No recibo notificaciones

Por defecto, las notificaciones se guardan en un archivo (`/config/notification.txt`). Para ver notificaciones:

```bash
kubectl -n authelia exec deployment/authelia -- cat /config/notification.txt
```

Para configurar email, edita la sección `notifier` en `k8s/authelia/02-configmap.yaml`.

### "Invalid credentials" pero el password es correcto

1. Verifica que el hash del password sea correcto:
   ```bash
   ./scripts/generate-password.sh tuPassword
   ```

2. Compara el hash con el que está en `k8s/authelia/03-secret.yaml`

3. El email debe coincidir con el dominio configurado en `session.domain`

### Los cambios en la configuración no se aplican

Después de modificar ConfigMaps o Secrets, debes reiniciar el deployment:

```bash
kubectl apply -f k8s/authelia/02-configmap.yaml
kubectl rollout restart deployment/authelia -n authelia
```

## Seguridad

### ¿Es seguro el password por defecto?

**NO**. El password por defecto es `password` y **DEBES cambiarlo** antes de exponer Authelia a internet.

### ¿Dónde se guardan los secretos?

Los secretos se guardan en:
- `k8s/authelia/03-secret.yaml` - en formato base64 en el cluster
- `/secrets/` dentro del pod - montados como archivos

**Importante**: No subas el archivo `03-secret.yaml` con secretos reales a un repositorio público.

### ¿Puedo usar un gestor de secretos externo?

Sí, puedes integrar con:
- **Sealed Secrets**
- **External Secrets Operator**
- **Vault**

Esto requeriría modificar los manifiestos para usar estos sistemas.

### ¿Authelia protege contra ataques de fuerza bruta?

Sí, tiene protección integrada:

```yaml
regulation:
  max_retries: 3        # Máximo 3 intentos
  find_time: 2m         # En 2 minutos
  ban_time: 5m          # Bloqueo de 5 minutos
```

Puedes ajustar estos valores en `k8s/authelia/02-configmap.yaml`.

## Performance

### ¿Cuánta memoria usa Authelia?

En Raspberry Pi, típicamente:
- **Memoria**: 64-128 MB
- **CPU**: < 0.1 core en reposo

Es muy ligero y perfecto para dispositivos con recursos limitados.

### ¿Funciona bien en Raspberry Pi?

Sí, Authelia está diseñado para ser ligero. Funciona perfectamente en Raspberry Pi 3 y superiores.

### ¿Hay latencia al acceder a los servicios?

La latencia añadida es mínima (< 50ms) ya que es solo una verificación de sesión contra SQLite local.

## Migración y Backup

### ¿Cómo hago backup de la configuración?

Los datos importantes están en:
- `k8s/authelia/03-secret.yaml` - Usuarios y secretos
- `k8s/authelia/02-configmap.yaml` - Configuración
- El PersistentVolume - Base de datos y sesiones

Para backup del PV:

```bash
kubectl -n authelia exec deployment/authelia -- tar czf - /config > authelia-backup.tar.gz
```

### ¿Cómo restauro desde backup?

```bash
kubectl -n authelia exec -i deployment/authelia -- tar xzf - -C / < authelia-backup.tar.gz
kubectl rollout restart deployment/authelia -n authelia
```

### ¿Puedo migrar a otro cluster?

Sí:

1. Haz backup de los manifiestos personalizados
2. Haz backup del PersistentVolume
3. Despliega en el nuevo cluster
4. Restaura el backup del PV

## Más Ayuda

Si tu pregunta no está aquí:

1. Consulta la [documentación oficial de Authelia](https://www.authelia.com/docs/)
2. Revisa el [README principal](../README.md)
3. Consulta la [Guía de Inicio Rápido](./QUICKSTART.md)
