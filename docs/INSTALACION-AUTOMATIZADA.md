# Instalación Automatizada de Authelia

Esta guía te muestra cómo instalar Authelia en K3s de forma completamente automatizada usando un archivo de configuración.

## 🚀 Instalación en 3 Pasos Simples

### Paso 1: Copiar el Archivo de Configuración

```bash
cd authelia-middlewre
cp config.env.example config.env
```

### Paso 2: Editar la Configuración

Abre `config.env` y personaliza los valores:

```bash
nano config.env
```

**Configuración mínima necesaria:**

```env
# Dominio principal (OBLIGATORIO)
DOMAIN="midominio.com"

# Usuarios (formato: username:password:grupos:nombre_completo:email)
USERS="admin:miPasswordSeguro123:admins:Administrador:admin@midominio.com"
```

### Paso 3: Ejecutar el Script de Instalación

```bash
./scripts/install.sh
```

¡Eso es todo! El script se encargará de:
- ✅ Generar secretos aleatorios seguros
- ✅ Hashear todos los passwords con Argon2id
- ✅ Personalizar los manifiestos con tu dominio
- ✅ Desplegar Authelia en K3s
- ✅ Verificar que todo esté funcionando

---

## 📋 Guía Detallada del Archivo config.env

### Configuración Básica

```env
# Dominio principal
DOMAIN="midominio.com"

# Namespace de Kubernetes (opcional)
NAMESPACE="authelia"
```

### Configurar Usuarios

El formato para definir usuarios es:

```
username:password:grupos:nombre_completo:email
```

**Parámetros:**
- **username** (obligatorio): Nombre de usuario para login
- **password** (obligatorio): Password en texto plano (se hasheará automáticamente)
- **grupos** (opcional): Grupos separados por comas
- **nombre_completo** (opcional): Nombre para mostrar
- **email** (opcional): Email del usuario

**Ejemplos:**

```env
# Usuario simple (solo username y password)
USERS="admin:miPasswordSeguro"

# Usuario con grupos
USERS="admin:miPasswordSeguro:admins,developers"

# Usuario con todos los campos
USERS="admin:miPasswordSeguro:admins:Admin Principal:admin@midominio.com"

# Múltiples usuarios (separados por espacio)
USERS="admin:pass1:admins juan:pass2:developers maria:pass3:viewers"
```

### Ejemplos Completos de Configuración

#### Ejemplo 1: Configuración Simple (Un Solo Admin)

```env
DOMAIN="midominio.com"
USERS="admin:MiPasswordSuperSeguro123:admins"
```

#### Ejemplo 2: Empresa Pequeña (Admin + Desarrolladores)

```env
DOMAIN="miempresa.com"
USERS="admin:admin123:admins:Administrador:admin@miempresa.com juan:dev456:developers:Juan Pérez:juan@miempresa.com maria:dev789:developers:María García:maria@miempresa.com"
```

#### Ejemplo 3: Organización con Múltiples Roles

```env
DOMAIN="miorganizacion.com"

USERS="admin:AdminPass123:admins:Admin Principal:admin@miorganizacion.com jefe_dev:DevLead456:admins,developers:Jefe Dev:jefe@miorganizacion.com dev1:DevPass1:developers:Developer 1:dev1@miorganizacion.com dev2:DevPass2:developers:Developer 2:dev2@miorganizacion.com soporte:SupportPass:support:Soporte Técnico:soporte@miorganizacion.com viewer:ViewPass:viewers:Usuario Lectura:viewer@miorganizacion.com"
```

### Grupos (Roles) Comunes

Puedes usar cualquier nombre para los grupos, pero estos son nombres comunes:

| Grupo | Descripción | Uso Típico |
|-------|-------------|------------|
| `admins` | Administradores | Acceso total, panel de administración |
| `developers` | Desarrolladores | Acceso a herramientas de desarrollo, logs, métricas |
| `users` | Usuarios normales | Acceso a aplicaciones internas |
| `viewers` | Solo lectura | Ver dashboards, sin editar |
| `support` | Soporte técnico | Acceso a herramientas de soporte |
| `testers` | Testers/QA | Acceso a entornos de prueba |

**Ejemplo de políticas basadas en grupos:**

```yaml
# En k8s/authelia/02-configmap.yaml
access_control:
  rules:
    # Panel de admin - solo admins
    - domain: "admin.midominio.com"
      policy: two_factor
      subject:
        - "group:admins"

    # Herramientas de dev - developers y admins
    - domain: "dev.midominio.com"
      policy: one_factor
      subject:
        - "group:developers"
        - "group:admins"

    # Dashboards - viewers, developers y admins
    - domain: "dashboard.midominio.com"
      policy: one_factor
      subject:
        - "group:viewers"
        - "group:developers"
        - "group:admins"
```

---

## 🔧 Opciones Avanzadas

### Secretos Personalizados

Por defecto, el script genera secretos aleatorios automáticamente. Si quieres usar valores específicos:

```env
# Generar secretos manualmente:
# openssl rand -hex 32

JWT_SECRET="tu_secreto_jwt_aquí"
SESSION_SECRET="tu_secreto_sesión_aquí"
STORAGE_ENCRYPTION_KEY="tu_clave_encriptación_aquí"
```

### Recursos del Pod

```env
MEMORY_REQUEST="128Mi"
MEMORY_LIMIT="256Mi"
CPU_REQUEST="100m"
CPU_LIMIT="500m"
```

### Zona Horaria

```env
TZ="Europe/Madrid"  # o America/Mexico_City, etc.
```

---

## 🔄 Actualizar Configuración

### Añadir Nuevos Usuarios

1. Edita `config.env` y añade el nuevo usuario a `USERS`:

```env
USERS="admin:pass1:admins usuario_nuevo:pass_nuevo:developers"
```

2. Ejecuta el script de nuevo:

```bash
./scripts/install.sh
```

El script detectará los cambios y actualizará la configuración.

### Cambiar Password de un Usuario

1. Edita `config.env` y cambia el password:

```env
USERS="admin:nuevoPassword123:admins"
```

2. Ejecuta el script de nuevo:

```bash
./scripts/install.sh
```

---

## 🛠️ Troubleshooting

### Error: "config.env not found"

```bash
cp config.env.example config.env
nano config.env  # Edita con tus valores
```

### Error: "Docker not found"

El script necesita Docker para generar hashes de passwords. Opciones:

1. **Instalar Docker** (recomendado):
```bash
curl -fsSL https://get.docker.com | sh
```

2. **Continuar sin Docker** (usará password por defecto):
```bash
# El script preguntará si quieres continuar
# Presiona 'y' para continuar
```

### Error: "kubectl not found"

```bash
# Verificar que kubectl esté instalado
kubectl version

# Si no está instalado, instálalo según tu distribución
```

### El pod no arranca

Ver logs:

```bash
kubectl -n authelia logs -f deployment/authelia
```

Verificar estado:

```bash
kubectl -n authelia get pods
kubectl -n authelia describe pod <nombre-del-pod>
```

### No puedo acceder al portal

1. Verifica el DNS:
```bash
nslookup auth.tudominio.com
```

2. Verifica el Ingress:
```bash
kubectl -n authelia get ingress
kubectl -n authelia describe ingress authelia
```

3. Verifica que Traefik esté corriendo:
```bash
kubectl -n kube-system get pods | grep traefik
```

---

## 📊 Comparación: Manual vs Automatizado

| Tarea | Manual | Automatizado |
|-------|--------|--------------|
| Personalizar dominio | ✋ Editar 7+ archivos | ✅ Una línea en config.env |
| Generar secretos | ✋ 3 comandos openssl | ✅ Automático |
| Hashear passwords | ✋ 1 comando por usuario | ✅ Automático |
| Actualizar manifiestos | ✋ Buscar/reemplazar manual | ✅ Automático |
| Desplegar en K3s | ✋ 7+ comandos kubectl | ✅ Un solo comando |
| Añadir usuarios | ✋ Editar YAML, hashear, aplicar | ✅ Editar config.env, ejecutar script |
| **Tiempo total** | ~15-20 minutos | **~2 minutos** |

---

## 🔐 Seguridad

### Proteger config.env

El archivo `config.env` contiene passwords en texto plano. **Importante:**

1. **NO subas config.env a Git** - Ya está en `.gitignore`
2. **Guarda una copia segura** - En un password manager o bóveda segura
3. **Limita permisos del archivo**:

```bash
chmod 600 config.env
```

### Los Passwords se Hashean

Aunque defines passwords en texto plano en `config.env`, el script:
- Los hashea con **Argon2id** (muy seguro)
- Solo guarda el hash en Kubernetes
- Los passwords originales solo están en `config.env` (local)

### Regenerar Secretos

Si crees que los secretos fueron comprometidos:

1. Elimina las líneas de secretos en `config.env`:
```env
# Borra estas líneas para regenerar
# JWT_SECRET="..."
# SESSION_SECRET="..."
# STORAGE_ENCRYPTION_KEY="..."
```

2. Ejecuta el script de nuevo:
```bash
./scripts/install.sh
```

Se generarán nuevos secretos y todas las sesiones existentes se invalidarán.

---

## 📚 Próximos Pasos

Después de la instalación:

1. **Accede al portal**: https://auth.tudominio.com
2. **Inicia sesión** con tus credenciales
3. **Configura 2FA** (opcional): Perfil > Register device
4. **Protege tus servicios**: Ver [README.md](../README.md#proteger-tus-servicios)
5. **Configura políticas de acceso**: Ver [USUARIOS-Y-ROLES.md](USUARIOS-Y-ROLES.md)

---

## 💡 Tips

### Backup de tu Configuración

```bash
# Hacer backup de config.env
cp config.env config.env.backup

# Guardar en un lugar seguro (no en Git)
```

### Múltiples Entornos

Si tienes múltiples clusters (dev, staging, prod):

```bash
# Crear configuraciones separadas
cp config.env config.dev.env
cp config.env config.prod.env

# Usar configuración específica
CONFIG_FILE=config.prod.env ./scripts/install.sh
```

### Validar Configuración Antes de Desplegar

```bash
# Ver qué haría el script sin desplegarlo
# (añade opción de dry-run al script)
```

---

## ❓ FAQ Rápido

**P: ¿Puedo usar el mismo config.env para múltiples instalaciones?**
R: Sí, pero cambia al menos los secretos para cada instalación.

**P: ¿Los passwords en config.env están seguros?**
R: El archivo local debe protegerse (chmod 600). Los passwords se hashean antes de guardarse en K8s.

**P: ¿Qué pasa si pierdo config.env?**
R: Puedes extraer la configuración de K8s, pero los passwords originales no se pueden recuperar (solo los hashes).

**P: ¿Puedo editar los manifiestos después de la instalación?**
R: Sí, pero si ejecutas install.sh de nuevo, se sobrescribirán. Mejor edita config.env y vuelve a ejecutar el script.

**P: ¿Cómo elimino Authelia?**
R: Usa el script de desinstalación: `./scripts/uninstall.sh`

---

Para más información, consulta la [documentación completa](../README.md).
