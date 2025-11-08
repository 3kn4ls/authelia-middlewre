#!/bin/bash

# Script para personalizar el dominio en todos los archivos de configuración
# Uso: ./customize-domain.sh tudominio.com

set -e

if [ -z "$1" ]; then
    echo "Uso: $0 TUDOMINIO.COM"
    echo ""
    echo "Ejemplo: $0 midominio.com"
    exit 1
fi

DOMAIN="$1"

echo "==========================================="
echo "  Personalizador de Dominio para Authelia"
echo "==========================================="
echo ""
echo "Reemplazando 'TUDOMINIO.COM' con '$DOMAIN' en todos los archivos..."
echo ""

# Directorio raíz del proyecto
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Archivos a modificar
FILES=(
    "$PROJECT_ROOT/k8s/authelia/02-configmap.yaml"
    "$PROJECT_ROOT/k8s/authelia/03-secret.yaml"
    "$PROJECT_ROOT/k8s/authelia/06-middleware.yaml"
    "$PROJECT_ROOT/k8s/authelia/07-ingress.yaml"
    "$PROJECT_ROOT/k8s/examples/ejemplo-servicio-protegido.yaml"
    "$PROJECT_ROOT/k8s/examples/ejemplo-kubernetes-dashboard.yaml"
    "$PROJECT_ROOT/k8s/examples/ejemplo-multiples-servicios.yaml"
)

# Reemplazar en cada archivo
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        sed -i "s/TUDOMINIO\.COM/$DOMAIN/g" "$file"
        echo "✓ Actualizado: $(basename $file)"
    else
        echo "⚠ No encontrado: $(basename $file)"
    fi
done

echo ""
echo "==========================================="
echo "✓ Dominio actualizado con éxito a: $DOMAIN"
echo "==========================================="
echo ""
echo "Próximos pasos:"
echo "1. Revisa los archivos en k8s/authelia/ para confirmar los cambios"
echo "2. Genera los secretos con: ./scripts/generate-secrets.sh"
echo "3. Genera passwords para usuarios con: ./scripts/generate-password.sh"
echo "4. Despliega Authelia: kubectl apply -f k8s/authelia/"
echo ""
