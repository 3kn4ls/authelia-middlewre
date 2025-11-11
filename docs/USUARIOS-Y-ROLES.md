# Usuarios, Grupos (Roles) y Cómo Leerlos desde tus Aplicaciones

Esta guía explica cómo crear usuarios, asignar grupos (roles), y cómo tus aplicaciones frontend y backend pueden leer esta información para implementar lógica de autorización.

## Índice

1. [Crear Usuarios y Asignar Grupos](#crear-usuarios-y-asignar-grupos)
2. [Configurar Políticas Basadas en Grupos](#configurar-políticas-basadas-en-grupos)
3. [Headers que Reciben tus Aplicaciones](#headers-que-reciben-tus-aplicaciones)
4. [Leer Headers desde el Frontend](#leer-headers-desde-el-frontend)
5. [Leer Headers desde el Backend](#leer-headers-desde-el-backend)
6. [Ejemplos Prácticos Completos](#ejemplos-prácticos-completos)
7. [Mejores Prácticas](#mejores-prácticas)

---

## Crear Usuarios y Asignar Grupos

### 1. Estructura de Usuarios y Grupos

Los usuarios y sus grupos se definen en `k8s/authelia/03-secret.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: authelia-users
  namespace: authelia
type: Opaque
stringData:
  users_database.yml: |
    users:
      # Usuario administrador
      admin:
        displayname: "Administrador Principal"
        password: "$argon2id$v=19$m=65536,t=3,p=4$..."
        email: admin@tudominio.com
        groups:
          - admins
          - developers

      # Usuario desarrollador
      juan:
        displayname: "Juan Pérez"
        password: "$argon2id$v=19$m=65536,t=3,p=4$..."
        email: juan@tudominio.com
        groups:
          - developers
          - testers

      # Usuario solo lectura
      maria:
        displayname: "María García"
        password: "$argon2id$v=19$m=65536,t=3,p=4$..."
        email: maria@tudominio.com
        groups:
          - viewers

      # Usuario con múltiples roles
      carlos:
        displayname: "Carlos Rodríguez"
        password: "$argon2id$v=19$m=65536,t=3,p=4$..."
        email: carlos@tudominio.com
        groups:
          - developers
          - admins
          - support
```

**Importante:**
- Los **grupos** son como **roles** - puedes nombrarlos como quieras
- Un usuario puede pertenecer a **múltiples grupos**
- Los nombres de grupos son case-sensitive

### 2. Generar Passwords para Nuevos Usuarios

```bash
# Generar password para cada usuario
./scripts/generate-password.sh

# El script te pedirá el password y te dará un hash como:
# $argon2id$v=19$m=65536,t=3,p=4$xyz123...
```

### 3. Aplicar los Cambios

Después de añadir usuarios:

```bash
# Aplicar el secret actualizado
kubectl apply -f k8s/authelia/03-secret.yaml

# Reiniciar Authelia para que cargue los nuevos usuarios
kubectl rollout restart deployment/authelia -n authelia

# Verificar que se reinició correctamente
kubectl -n authelia get pods -w
```

---

## Configurar Políticas Basadas en Grupos

Puedes definir qué grupos tienen acceso a qué servicios en `k8s/authelia/02-configmap.yaml`:

```yaml
access_control:
  default_policy: deny  # Por defecto todo bloqueado

  rules:
    # Portal de Authelia - acceso público
    - domain: "auth.tudominio.com"
      policy: bypass

    # Servicios solo para admins
    - domain: "admin.tudominio.com"
      policy: two_factor
      subject:
        - "group:admins"  # Solo el grupo admins

    # Panel de desarrollo - solo developers y admins
    - domain: "dev.tudominio.com"
      policy: one_factor
      subject:
        - "group:developers"
        - "group:admins"

    # Dashboard de monitoreo - developers y viewers
    - domain: "monitoring.tudominio.com"
      policy: one_factor
      subject:
        - "group:developers"
        - "group:viewers"

    # API - acceso para developers
    - domain: "api.tudominio.com"
      policy: one_factor
      subject:
        - "group:developers"

    # Servicios internos - cualquier usuario autenticado
    - domain: "*.tudominio.com"
      policy: one_factor
```

**Tipos de subject:**
- `"group:nombre-grupo"` - Usuarios que pertenecen a ese grupo
- `"user:nombre-usuario"` - Usuario específico

**Combinación de reglas:**
- Las reglas se evalúan en orden (de arriba hacia abajo)
- La primera regla que coincide se aplica
- Si ninguna regla coincide, se usa `default_policy`

---

## Headers que Reciben tus Aplicaciones

Cuando un usuario está autenticado, Authelia añade estos headers a **todas las peticiones** que llegan a tu aplicación:

| Header | Descripción | Ejemplo |
|--------|-------------|---------|
| `Remote-User` | Nombre de usuario (login) | `admin` |
| `Remote-Name` | Nombre completo (displayname) | `Administrador Principal` |
| `Remote-Email` | Email del usuario | `admin@tudominio.com` |
| `Remote-Groups` | Grupos separados por comas | `admins,developers` |

**Importante:**
- Estos headers **SOLO** los puede poner Authelia
- Un atacante **NO puede** falsificarlos (Traefik los elimina antes de llamar a Authelia)
- Tus aplicaciones pueden confiar 100% en estos headers

---

## Leer Headers desde el Frontend

### JavaScript Vanilla

**Importante:** El frontend NO puede leer los headers directamente. Debes exponerlos desde tu backend.

**Backend expone los headers como datos:**

```javascript
// Backend (Node.js/Express) - Endpoint que expone info del usuario
app.get('/api/me', (req, res) => {
  res.json({
    username: req.headers['remote-user'],
    name: req.headers['remote-name'],
    email: req.headers['remote-email'],
    groups: req.headers['remote-groups']?.split(',') || []
  });
});
```

**Frontend consulta el endpoint:**

```javascript
// Frontend - Obtener información del usuario actual
async function getCurrentUser() {
  const response = await fetch('/api/me');
  const user = await response.json();

  console.log('Usuario:', user.username);
  console.log('Grupos:', user.groups);

  return user;
}

// Verificar si el usuario tiene un rol específico
function hasRole(user, role) {
  return user.groups.includes(role);
}

// Ejemplo de uso
getCurrentUser().then(user => {
  if (hasRole(user, 'admins')) {
    console.log('Usuario es administrador');
    document.getElementById('admin-panel').style.display = 'block';
  }

  if (hasRole(user, 'developers')) {
    console.log('Usuario es desarrollador');
    document.getElementById('dev-tools').style.display = 'block';
  }
});
```

### React

```jsx
import { useState, useEffect } from 'react';

// Hook personalizado para obtener el usuario actual
function useCurrentUser() {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch('/api/me')
      .then(res => res.json())
      .then(data => {
        setUser({
          ...data,
          groups: data.groups || []
        });
        setLoading(false);
      })
      .catch(err => {
        console.error('Error al obtener usuario:', err);
        setLoading(false);
      });
  }, []);

  const hasRole = (role) => user?.groups.includes(role);

  return { user, loading, hasRole };
}

// Componente que usa el hook
function Dashboard() {
  const { user, loading, hasRole } = useCurrentUser();

  if (loading) return <div>Cargando...</div>;

  return (
    <div>
      <h1>Bienvenido, {user.name}!</h1>
      <p>Email: {user.email}</p>
      <p>Grupos: {user.groups.join(', ')}</p>

      {hasRole('admins') && (
        <div className="admin-panel">
          <h2>Panel de Administración</h2>
          {/* Contenido solo para admins */}
        </div>
      )}

      {hasRole('developers') && (
        <div className="dev-tools">
          <h2>Herramientas de Desarrollo</h2>
          {/* Contenido solo para developers */}
        </div>
      )}
    </div>
  );
}
```

### Vue 3

```vue
<template>
  <div v-if="loading">Cargando...</div>
  <div v-else>
    <h1>Bienvenido, {{ user.name }}!</h1>
    <p>Email: {{ user.email }}</p>
    <p>Grupos: {{ user.groups.join(', ') }}</p>

    <div v-if="hasRole('admins')" class="admin-panel">
      <h2>Panel de Administración</h2>
      <!-- Contenido solo para admins -->
    </div>

    <div v-if="hasRole('developers')" class="dev-tools">
      <h2>Herramientas de Desarrollo</h2>
      <!-- Contenido solo para developers -->
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue';

const user = ref(null);
const loading = ref(true);

onMounted(async () => {
  try {
    const response = await fetch('/api/me');
    const data = await response.json();
    user.value = {
      ...data,
      groups: data.groups || []
    };
  } catch (err) {
    console.error('Error al obtener usuario:', err);
  } finally {
    loading.value = false;
  }
});

function hasRole(role) {
  return user.value?.groups.includes(role);
}
</script>
```

---

## Leer Headers desde el Backend

### Node.js / Express

```javascript
const express = require('express');
const app = express();

// Middleware para extraer info del usuario de los headers
function extractUserInfo(req, res, next) {
  req.authUser = {
    username: req.headers['remote-user'],
    name: req.headers['remote-name'],
    email: req.headers['remote-email'],
    groups: req.headers['remote-groups']?.split(',') || []
  };
  next();
}

app.use(extractUserInfo);

// Helper para verificar roles
function hasRole(req, role) {
  return req.authUser.groups.includes(role);
}

function requireRole(role) {
  return (req, res, next) => {
    if (!hasRole(req, role)) {
      return res.status(403).json({ error: 'Acceso denegado' });
    }
    next();
  };
}

// Rutas públicas (ya protegidas por Authelia)
app.get('/api/me', (req, res) => {
  res.json(req.authUser);
});

// Ruta solo para admins
app.get('/api/admin/users', requireRole('admins'), (req, res) => {
  res.json({ message: 'Lista de usuarios (solo admins)' });
});

// Ruta para developers o admins
app.get('/api/dev/logs', (req, res) => {
  if (!hasRole(req, 'developers') && !hasRole(req, 'admins')) {
    return res.status(403).json({ error: 'Acceso denegado' });
  }
  res.json({ logs: [] });
});

// Ruta que devuelve datos según el rol
app.get('/api/dashboard', (req, res) => {
  const data = {
    user: req.authUser.username,
    widgets: []
  };

  if (hasRole(req, 'admins')) {
    data.widgets.push('admin-stats', 'user-management');
  }

  if (hasRole(req, 'developers')) {
    data.widgets.push('api-metrics', 'error-logs');
  }

  if (hasRole(req, 'viewers')) {
    data.widgets.push('general-stats');
  }

  res.json(data);
});

app.listen(3000);
```

### Python / Flask

```python
from flask import Flask, request, jsonify
from functools import wraps

app = Flask(__name__)

def get_user_info():
    """Extrae la información del usuario de los headers"""
    groups_header = request.headers.get('Remote-Groups', '')
    return {
        'username': request.headers.get('Remote-User'),
        'name': request.headers.get('Remote-Name'),
        'email': request.headers.get('Remote-Email'),
        'groups': groups_header.split(',') if groups_header else []
    }

def has_role(role):
    """Verifica si el usuario tiene un rol específico"""
    user = get_user_info()
    return role in user['groups']

def require_role(role):
    """Decorador para requerir un rol específico"""
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if not has_role(role):
                return jsonify({'error': 'Acceso denegado'}), 403
            return f(*args, **kwargs)
        return decorated_function
    return decorator

@app.route('/api/me')
def me():
    """Endpoint que devuelve info del usuario actual"""
    return jsonify(get_user_info())

@app.route('/api/admin/users')
@require_role('admins')
def admin_users():
    """Solo para admins"""
    return jsonify({'message': 'Lista de usuarios (solo admins)'})

@app.route('/api/dashboard')
def dashboard():
    """Dashboard con datos según el rol"""
    user = get_user_info()
    data = {
        'user': user['username'],
        'widgets': []
    }

    if 'admins' in user['groups']:
        data['widgets'].extend(['admin-stats', 'user-management'])

    if 'developers' in user['groups']:
        data['widgets'].extend(['api-metrics', 'error-logs'])

    if 'viewers' in user['groups']:
        data['widgets'].append('general-stats')

    return jsonify(data)

if __name__ == '__main__':
    app.run(port=3000)
```

### Python / FastAPI

```python
from fastapi import FastAPI, Header, HTTPException, Depends
from typing import List, Optional

app = FastAPI()

class User:
    def __init__(self, username: str, name: str, email: str, groups: List[str]):
        self.username = username
        self.name = name
        self.email = email
        self.groups = groups

    def has_role(self, role: str) -> bool:
        return role in self.groups

async def get_current_user(
    remote_user: Optional[str] = Header(None),
    remote_name: Optional[str] = Header(None),
    remote_email: Optional[str] = Header(None),
    remote_groups: Optional[str] = Header(None)
) -> User:
    """Dependency para obtener el usuario actual de los headers"""
    groups = remote_groups.split(',') if remote_groups else []
    return User(
        username=remote_user or '',
        name=remote_name or '',
        email=remote_email or '',
        groups=groups
    )

def require_role(role: str):
    """Dependency para requerir un rol específico"""
    async def role_checker(user: User = Depends(get_current_user)):
        if not user.has_role(role):
            raise HTTPException(status_code=403, detail="Acceso denegado")
        return user
    return role_checker

@app.get("/api/me")
async def me(user: User = Depends(get_current_user)):
    """Endpoint que devuelve info del usuario actual"""
    return {
        'username': user.username,
        'name': user.name,
        'email': user.email,
        'groups': user.groups
    }

@app.get("/api/admin/users")
async def admin_users(user: User = Depends(require_role('admins'))):
    """Solo para admins"""
    return {'message': 'Lista de usuarios (solo admins)'}

@app.get("/api/dashboard")
async def dashboard(user: User = Depends(get_current_user)):
    """Dashboard con datos según el rol"""
    data = {
        'user': user.username,
        'widgets': []
    }

    if user.has_role('admins'):
        data['widgets'].extend(['admin-stats', 'user-management'])

    if user.has_role('developers'):
        data['widgets'].extend(['api-metrics', 'error-logs'])

    if user.has_role('viewers'):
        data['widgets'].append('general-stats')

    return data
```

### Go / Gin

```go
package main

import (
    "net/http"
    "strings"

    "github.com/gin-gonic/gin"
)

type User struct {
    Username string   `json:"username"`
    Name     string   `json:"name"`
    Email    string   `json:"email"`
    Groups   []string `json:"groups"`
}

func getUserFromHeaders(c *gin.Context) User {
    groupsHeader := c.GetHeader("Remote-Groups")
    groups := []string{}
    if groupsHeader != "" {
        groups = strings.Split(groupsHeader, ",")
    }

    return User{
        Username: c.GetHeader("Remote-User"),
        Name:     c.GetHeader("Remote-Name"),
        Email:    c.GetHeader("Remote-Email"),
        Groups:   groups,
    }
}

func hasRole(user User, role string) bool {
    for _, g := range user.Groups {
        if g == role {
            return true
        }
    }
    return false
}

func requireRole(role string) gin.HandlerFunc {
    return func(c *gin.Context) {
        user := getUserFromHeaders(c)
        if !hasRole(user, role) {
            c.JSON(http.StatusForbidden, gin.H{"error": "Acceso denegado"})
            c.Abort()
            return
        }
        c.Set("user", user)
        c.Next()
    }
}

func main() {
    r := gin.Default()

    r.GET("/api/me", func(c *gin.Context) {
        user := getUserFromHeaders(c)
        c.JSON(http.StatusOK, user)
    })

    r.GET("/api/admin/users", requireRole("admins"), func(c *gin.Context) {
        c.JSON(http.StatusOK, gin.H{"message": "Lista de usuarios (solo admins)"})
    })

    r.GET("/api/dashboard", func(c *gin.Context) {
        user := getUserFromHeaders(c)
        widgets := []string{}

        if hasRole(user, "admins") {
            widgets = append(widgets, "admin-stats", "user-management")
        }
        if hasRole(user, "developers") {
            widgets = append(widgets, "api-metrics", "error-logs")
        }
        if hasRole(user, "viewers") {
            widgets = append(widgets, "general-stats")
        }

        c.JSON(http.StatusOK, gin.H{
            "user":    user.Username,
            "widgets": widgets,
        })
    })

    r.Run(":3000")
}
```

### PHP

```php
<?php

class User {
    public $username;
    public $name;
    public $email;
    public $groups;

    public function __construct() {
        $this->username = $_SERVER['HTTP_REMOTE_USER'] ?? '';
        $this->name = $_SERVER['HTTP_REMOTE_NAME'] ?? '';
        $this->email = $_SERVER['HTTP_REMOTE_EMAIL'] ?? '';

        $groupsHeader = $_SERVER['HTTP_REMOTE_GROUPS'] ?? '';
        $this->groups = $groupsHeader ? explode(',', $groupsHeader) : [];
    }

    public function hasRole($role) {
        return in_array($role, $this->groups);
    }
}

// Obtener usuario actual
$user = new User();

// Endpoint /api/me
if ($_SERVER['REQUEST_URI'] === '/api/me') {
    header('Content-Type: application/json');
    echo json_encode([
        'username' => $user->username,
        'name' => $user->name,
        'email' => $user->email,
        'groups' => $user->groups
    ]);
    exit;
}

// Endpoint solo para admins
if ($_SERVER['REQUEST_URI'] === '/api/admin/users') {
    if (!$user->hasRole('admins')) {
        http_response_code(403);
        echo json_encode(['error' => 'Acceso denegado']);
        exit;
    }

    header('Content-Type: application/json');
    echo json_encode(['message' => 'Lista de usuarios (solo admins)']);
    exit;
}

// Dashboard con lógica según rol
if ($_SERVER['REQUEST_URI'] === '/api/dashboard') {
    $widgets = [];

    if ($user->hasRole('admins')) {
        $widgets[] = 'admin-stats';
        $widgets[] = 'user-management';
    }

    if ($user->hasRole('developers')) {
        $widgets[] = 'api-metrics';
        $widgets[] = 'error-logs';
    }

    if ($user->hasRole('viewers')) {
        $widgets[] = 'general-stats';
    }

    header('Content-Type: application/json');
    echo json_encode([
        'user' => $user->username,
        'widgets' => $widgets
    ]);
    exit;
}
?>
```

---

## Ejemplos Prácticos Completos

### Caso 1: Dashboard con Secciones por Rol

**Backend (Node.js):**
```javascript
app.get('/api/dashboard/sections', (req, res) => {
  const sections = [];

  if (hasRole(req, 'admins')) {
    sections.push({
      id: 'users',
      title: 'Gestión de Usuarios',
      icon: 'users',
      url: '/admin/users'
    });
  }

  if (hasRole(req, 'developers') || hasRole(req, 'admins')) {
    sections.push({
      id: 'api',
      title: 'API Logs',
      icon: 'code',
      url: '/dev/api-logs'
    });
  }

  // Todos los usuarios autenticados ven esto
  sections.push({
    id: 'profile',
    title: 'Mi Perfil',
    icon: 'user',
    url: '/profile'
  });

  res.json({ sections });
});
```

**Frontend (React):**
```jsx
function DashboardMenu() {
  const [sections, setSections] = useState([]);

  useEffect(() => {
    fetch('/api/dashboard/sections')
      .then(res => res.json())
      .then(data => setSections(data.sections));
  }, []);

  return (
    <nav>
      {sections.map(section => (
        <a key={section.id} href={section.url}>
          <i className={section.icon}></i>
          {section.title}
        </a>
      ))}
    </nav>
  );
}
```

### Caso 2: API con Diferentes Permisos

```javascript
// Crear recurso - solo developers y admins
app.post('/api/resources', (req, res) => {
  if (!hasRole(req, 'developers') && !hasRole(req, 'admins')) {
    return res.status(403).json({ error: 'Sin permisos para crear' });
  }
  // Lógica de creación
});

// Leer recurso - todos los autenticados
app.get('/api/resources/:id', (req, res) => {
  // Todos pueden leer
});

// Actualizar recurso - solo developers y admins
app.put('/api/resources/:id', (req, res) => {
  if (!hasRole(req, 'developers') && !hasRole(req, 'admins')) {
    return res.status(403).json({ error: 'Sin permisos para actualizar' });
  }
  // Lógica de actualización
});

// Eliminar recurso - solo admins
app.delete('/api/resources/:id', requireRole('admins'), (req, res) => {
  // Lógica de eliminación
});
```

---

## Mejores Prácticas

### 1. Nombrar Grupos de Forma Clara

```yaml
# ✅ BIEN - nombres descriptivos
groups:
  - admins
  - developers
  - support-team
  - read-only

# ❌ MAL - nombres ambiguos
groups:
  - group1
  - g2
  - team
```

### 2. Principio de Menor Privilegio

```yaml
# Asignar solo los grupos necesarios
juan:
  groups:
    - developers  # Solo lo necesario

# No dar admin a todos
carlos:
  groups:
    - admins
    - developers  # Solo si realmente necesita ambos
```

### 3. Validar SIEMPRE en el Backend

```javascript
// ❌ MAL - Solo validar en frontend
function AdminPanel() {
  const { hasRole } = useCurrentUser();

  // Un atacante podría modificar el frontend
  if (!hasRole('admins')) return null;

  return <div>Panel de admin sin validación en backend</div>;
}

// ✅ BIEN - Validar en frontend Y backend
function AdminPanel() {
  const { hasRole } = useCurrentUser();

  // Frontend: UX, ocultar botones
  if (!hasRole('admins')) return null;

  // Backend: endpoint también valida
  // app.get('/api/admin/...', requireRole('admins'), ...)

  return <div>Panel de admin protegido</div>;
}
```

### 4. Cachear Información del Usuario

```javascript
// Frontend - cachear para no hacer múltiples requests
const userCache = {
  data: null,
  promise: null,

  async get() {
    if (this.data) return this.data;
    if (this.promise) return this.promise;

    this.promise = fetch('/api/me')
      .then(res => res.json())
      .then(data => {
        this.data = data;
        return data;
      });

    return this.promise;
  },

  clear() {
    this.data = null;
    this.promise = null;
  }
};
```

### 5. Auditar Acciones Importantes

```javascript
// Backend - log de acciones de admins
app.delete('/api/users/:id', requireRole('admins'), (req, res) => {
  const admin = req.authUser.username;
  const targetUser = req.params.id;

  logger.info(`Admin ${admin} eliminó al usuario ${targetUser}`);

  // Lógica de eliminación
});
```

---

## Resumen

**Para crear usuarios y roles:**
1. Edita `k8s/authelia/03-secret.yaml`
2. Genera passwords con `./scripts/generate-password.sh`
3. Asigna grupos (roles) a cada usuario
4. Aplica cambios: `kubectl apply -f k8s/authelia/03-secret.yaml`
5. Reinicia: `kubectl rollout restart deployment/authelia -n authelia`

**Para leer desde aplicaciones:**
1. **Frontend**: Crea endpoint `/api/me` en tu backend que exponga los headers
2. **Backend**: Lee los headers `Remote-User`, `Remote-Groups`, etc.
3. **Valida SIEMPRE en el backend**, no confíes solo en el frontend

**Los headers que recibes:**
- `Remote-User`: Nombre de usuario
- `Remote-Name`: Nombre completo
- `Remote-Email`: Email
- `Remote-Groups`: Grupos separados por comas

**Estos headers son 100% confiables** - solo Authelia puede ponerlos, ningún atacante puede falsificarlos.

---

¿Necesitas ayuda con algún caso de uso específico o algún lenguaje que no esté en los ejemplos?
