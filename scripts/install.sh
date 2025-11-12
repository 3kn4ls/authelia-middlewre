#!/bin/bash
# Script de instalación automatizada de Authelia para K3s
# Lee configuración desde config.env y despliega todo automáticamente

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PROJECT_ROOT/config.env"

echo "============================================"
echo "  Instalación Automatizada de Authelia"
echo "============================================"
echo ""

# Verificar que existe el archivo de configuración
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Error: No se encuentra el archivo config.env"
    echo ""
    echo "Por favor, crea el archivo config.env basándote en config.env.example:"
    echo "  cp config.env.example config.env"
    echo "  nano config.env  # Edita con tus valores"
    echo ""
    exit 1
fi

# Cargar configuración
echo "📋 Cargando configuración desde config.env..."
source "$CONFIG_FILE"

# Validar configuración obligatoria
if [ -z "$DOMAIN" ]; then
    echo "❌ Error: DOMAIN no está definido en config.env"
    exit 1
fi

echo "✓ Configuración cargada"
echo "  - Dominio: $DOMAIN"
echo "  - Namespace: ${NAMESPACE:-authelia}"
echo ""

# Verificar dependencias
echo "🔍 Verificando dependencias..."

if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl no está instalado"
    exit 1
fi
echo "  ✓ kubectl encontrado"

if ! command -v openssl &> /dev/null; then
    echo "❌ Error: openssl no está instalado"
    exit 1
fi
echo "  ✓ openssl encontrado"

if ! command -v docker &> /dev/null; then
    echo "⚠️  Advertencia: Docker no está instalado"
    echo "     Se necesita Docker para generar hashes de passwords."
    echo "     ¿Continuar de todas formas? (y/N)"
    read -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    SKIP_PASSWORD_HASH=true
fi

echo ""
echo "============================================"
echo "  Paso 1: Generar Secretos Aleatorios"
echo "============================================"
echo ""

# Generar secretos si no están definidos
if [ -z "$JWT_SECRET" ]; then
    echo "Generando JWT_SECRET..."
    JWT_SECRET=$(openssl rand -hex 32)
fi

if [ -z "$SESSION_SECRET" ]; then
    echo "Generando SESSION_SECRET..."
    SESSION_SECRET=$(openssl rand -hex 32)
fi

if [ -z "$STORAGE_ENCRYPTION_KEY" ]; then
    echo "Generando STORAGE_ENCRYPTION_KEY..."
    STORAGE_ENCRYPTION_KEY=$(openssl rand -hex 32)
fi

echo "✓ Secretos generados/validados"
echo ""

# Guardar secretos en config.env si no estaban
if ! grep -q "JWT_SECRET=" "$CONFIG_FILE"; then
    echo "JWT_SECRET=\"$JWT_SECRET\"" >> "$CONFIG_FILE"
    echo "SESSION_SECRET=\"$SESSION_SECRET\"" >> "$CONFIG_FILE"
    echo "STORAGE_ENCRYPTION_KEY=\"$STORAGE_ENCRYPTION_KEY\"" >> "$CONFIG_FILE"
    echo "✓ Secretos guardados en config.env"
fi

echo "============================================"
echo "  Paso 2: Generar Hashes de Passwords"
echo "============================================"
echo ""

declare -A USER_HASHES

# Función para generar hash de password
generate_password_hash() {
    local password="$1"

    if [ "$SKIP_PASSWORD_HASH" = true ]; then
        # Password por defecto hasheado ("password")
        echo '$argon2id$v=19$m=65536,t=3,p=4$MlpOaUtQSE5oWW5wWmtmUw$O07iQx+8lv5n8dNzPr/B0HFpvwjqWKMz7/3kJlwRLbM'
        return
    fi

    docker run --rm authelia/authelia:latest \
        authelia crypto hash generate argon2 --password "$password" 2>/dev/null | \
        grep 'Digest:' | awk '{print $2}'
}

# Leer usuarios de las variables de entorno
# Formato: USERS="admin:password123:admins,developers user2:pass456:users"
if [ -n "$USERS" ]; then
    echo "Generando hashes para usuarios configurados..."

    IFS=' ' read -ra USER_ARRAY <<< "$USERS"
    for user_def in "${USER_ARRAY[@]}"; do
        IFS=':' read -ra USER_PARTS <<< "$user_def"
        username="${USER_PARTS[0]}"
        password="${USER_PARTS[1]}"

        echo "  - Generando hash para usuario: $username"
        hash=$(generate_password_hash "$password")
        USER_HASHES["$username"]="$hash"
    done

    echo "✓ Hashes generados"
else
    echo "⚠️  No se definieron usuarios en config.env"
    echo "   Se usará el usuario admin por defecto"
fi

echo ""

echo "============================================"
echo "  Paso 3: Personalizar Manifiestos"
echo "============================================"
echo ""

# Crear directorio temporal para manifiestos procesados
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Copiando manifiestos a directorio temporal..."
cp -r "$PROJECT_ROOT/k8s/authelia" "$TEMP_DIR/"

# Personalizar dominio en todos los archivos
echo "Personalizando dominio: $DOMAIN"
find "$TEMP_DIR/authelia" -type f -name "*.yaml" -exec sed -i "s/TUDOMINIO\.COM/$DOMAIN/g" {} \;

# Actualizar secretos en 03-secret.yaml
echo "Actualizando secretos..."
sed -i "s|JWT_SECRET:.*|JWT_SECRET: \"$JWT_SECRET\"|g" "$TEMP_DIR/authelia/03-secret.yaml"
sed -i "s|SESSION_SECRET:.*|SESSION_SECRET: \"$SESSION_SECRET\"|g" "$TEMP_DIR/authelia/03-secret.yaml"
sed -i "s|STORAGE_ENCRYPTION_KEY:.*|STORAGE_ENCRYPTION_KEY: \"$STORAGE_ENCRYPTION_KEY\"|g" "$TEMP_DIR/authelia/03-secret.yaml"

# Generar sección de usuarios
if [ -n "$USERS" ]; then
    echo "Generando configuración de usuarios..."

    # Crear archivo temporal con usuarios
    USERS_YAML="$TEMP_DIR/users.yml"
    echo "    users:" > "$USERS_YAML"

    IFS=' ' read -ra USER_ARRAY <<< "$USERS"
    for user_def in "${USER_ARRAY[@]}"; do
        IFS=':' read -ra USER_PARTS <<< "$user_def"
        username="${USER_PARTS[0]}"
        password="${USER_PARTS[1]}"
        groups="${USER_PARTS[2]:-users}"
        displayname="${USER_PARTS[3]:-$username}"
        email="${USER_PARTS[4]:-$username@$DOMAIN}"

        hash="${USER_HASHES[$username]}"

        cat >> "$USERS_YAML" << EOF
      $username:
        displayname: "$displayname"
        password: "$hash"
        email: $email
        groups:
EOF

        IFS=',' read -ra GROUP_ARRAY <<< "$groups"
        for group in "${GROUP_ARRAY[@]}"; do
            echo "          - $group" >> "$USERS_YAML"
        done
    done

    # Reemplazar sección de usuarios en el secret
    # Esto es un poco complejo, vamos a recrear el secret completo
    cat > "$TEMP_DIR/authelia/03-secret.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: authelia-secrets
  namespace: ${NAMESPACE:-authelia}
  labels:
    app: authelia
type: Opaque
stringData:
  JWT_SECRET: "$JWT_SECRET"
  SESSION_SECRET: "$SESSION_SECRET"
  STORAGE_ENCRYPTION_KEY: "$STORAGE_ENCRYPTION_KEY"
---
apiVersion: v1
kind: Secret
metadata:
  name: authelia-users
  namespace: ${NAMESPACE:-authelia}
  labels:
    app: authelia
type: Opaque
stringData:
  users_database.yml: |
    ---
$(cat "$USERS_YAML")
    ...
EOF
fi

# Personalizar namespace si se especificó
if [ -n "$NAMESPACE" ] && [ "$NAMESPACE" != "authelia" ]; then
    echo "Personalizando namespace: $NAMESPACE"
    find "$TEMP_DIR/authelia" -type f -name "*.yaml" -exec sed -i "s/namespace: authelia/namespace: $NAMESPACE/g" {} \;
    sed -i "s/name: authelia$/name: $NAMESPACE/" "$TEMP_DIR/authelia/00-namespace.yaml"
fi

echo "✓ Manifiestos personalizados"
echo ""

echo "============================================"
echo "  Paso 4: Desplegar en K3s"
echo "============================================"
echo ""

# Verificar conexión a K3s
echo "Verificando conexión al cluster..."
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Error: No se puede conectar al cluster K3s"
    echo "   Verifica que kubectl esté configurado correctamente"
    exit 1
fi
echo "✓ Conectado al cluster"
echo ""

# Confirmar antes de desplegar
echo "⚠️  ¿Estás listo para desplegar Authelia en K3s?"
echo ""
echo "Se desplegarán los siguientes recursos:"
echo "  - Namespace: ${NAMESPACE:-authelia}"
echo "  - Dominio: $DOMAIN"
echo "  - Portal: https://auth.$DOMAIN"
if [ -n "$USERS" ]; then
    echo "  - Usuarios: $(echo "$USERS" | tr ' ' '\n' | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')"
fi
echo ""
read -p "¿Continuar? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Instalación cancelada"
    exit 0
fi

echo ""
echo "Desplegando recursos..."

# Desplegar en orden
kubectl apply -f "$TEMP_DIR/authelia/00-namespace.yaml"
echo "  ✓ Namespace creado"

sleep 2

kubectl apply -f "$TEMP_DIR/authelia/01-pvc.yaml"
echo "  ✓ PersistentVolumeClaim creado"

kubectl apply -f "$TEMP_DIR/authelia/02-configmap.yaml"
echo "  ✓ ConfigMap creado"

kubectl apply -f "$TEMP_DIR/authelia/03-secret.yaml"
echo "  ✓ Secrets creados"

kubectl apply -f "$TEMP_DIR/authelia/04-deployment.yaml"
echo "  ✓ Deployment creado"

kubectl apply -f "$TEMP_DIR/authelia/05-service.yaml"
echo "  ✓ Service creado"

kubectl apply -f "$TEMP_DIR/authelia/06-middleware.yaml"
echo "  ✓ Middleware creado"

kubectl apply -f "$TEMP_DIR/authelia/07-ingress.yaml"
echo "  ✓ Ingress creado"

echo ""
echo "============================================"
echo "  ✅ Instalación Completada"
echo "============================================"
echo ""

# Esperar a que el pod esté listo
echo "Esperando a que Authelia esté listo..."
kubectl wait --for=condition=ready pod -l app=authelia -n "${NAMESPACE:-authelia}" --timeout=120s || true

echo ""
echo "Estado del deployment:"
kubectl -n "${NAMESPACE:-authelia}" get pods

echo ""
echo "============================================"
echo "  🎉 ¡Authelia está desplegado!"
echo "============================================"
echo ""
echo "Portal de Authelia:"
echo "  https://auth.$DOMAIN"
echo ""

if [ -n "$USERS" ]; then
    echo "Usuarios configurados:"
    IFS=' ' read -ra USER_ARRAY <<< "$USERS"
    for user_def in "${USER_ARRAY[@]}"; do
        IFS=':' read -ra USER_PARTS <<< "$user_def"
        username="${USER_PARTS[0]}"
        groups="${USER_PARTS[2]:-users}"
        echo "  - $username (grupos: $groups)"
    done
else
    echo "Usuario por defecto:"
    echo "  - admin / password (¡CÁMBIALO!)"
fi

echo ""
echo "Próximos pasos:"
echo "  1. Accede a https://auth.$DOMAIN"
echo "  2. Inicia sesión con tus credenciales"
echo "  3. Configura 2FA si lo deseas (Perfil > Register device)"
echo "  4. Protege tus servicios añadiendo el middleware de Authelia"
echo ""
echo "Ver logs:"
echo "  kubectl -n ${NAMESPACE:-authelia} logs -f deployment/authelia"
echo ""
echo "Documentación completa:"
echo "  README.md"
echo "  docs/USUARIOS-Y-ROLES.md"
echo "  docs/COMO-FUNCIONA.md"
echo ""
