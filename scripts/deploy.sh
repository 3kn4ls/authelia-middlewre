#!/bin/bash

# Script para desplegar Authelia en K3s
# Ejecuta los manifiestos en orden correcto

set -e

echo "==========================================="
echo "  Desplegando Authelia en K3s"
echo "==========================================="
echo ""

# Directorio raíz del proyecto
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K8S_DIR="$PROJECT_ROOT/k8s/authelia"

# Verificar que kubectl está disponible
if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl no está instalado o no está en el PATH"
    exit 1
fi

# Verificar que los archivos existen
if [ ! -d "$K8S_DIR" ]; then
    echo "❌ Error: No se encuentra el directorio $K8S_DIR"
    exit 1
fi

# Verificar que se han personalizado los archivos
if grep -q "TUDOMINIO.COM" "$K8S_DIR"/*.yaml 2>/dev/null; then
    echo "⚠️  ADVERTENCIA: Algunos archivos todavía contienen 'TUDOMINIO.COM'"
    echo ""
    echo "Por favor, ejecuta primero:"
    echo "  ./scripts/customize-domain.sh tudominio.com"
    echo ""
    read -p "¿Deseas continuar de todas formas? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Verificar secretos por defecto
if grep -q "CAMBIAR_ESTE_SECRET" "$K8S_DIR/03-secret.yaml" 2>/dev/null; then
    echo "⚠️  ADVERTENCIA: Estás usando secretos por defecto"
    echo ""
    echo "Por favor, genera secretos seguros con:"
    echo "  ./scripts/generate-secrets.sh"
    echo ""
    read -p "¿Deseas continuar de todas formas? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Desplegando recursos de Authelia..."
echo ""

# Aplicar los manifiestos en orden
kubectl apply -f "$K8S_DIR/00-namespace.yaml"
echo "✓ Namespace creado"

sleep 2

kubectl apply -f "$K8S_DIR/01-pvc.yaml"
echo "✓ PersistentVolumeClaim creado"

kubectl apply -f "$K8S_DIR/02-configmap.yaml"
echo "✓ ConfigMap creado"

kubectl apply -f "$K8S_DIR/03-secret.yaml"
echo "✓ Secrets creados"

kubectl apply -f "$K8S_DIR/04-deployment.yaml"
echo "✓ Deployment creado"

kubectl apply -f "$K8S_DIR/05-service.yaml"
echo "✓ Service creado"

kubectl apply -f "$K8S_DIR/06-middleware.yaml"
echo "✓ Middleware creado"

kubectl apply -f "$K8S_DIR/07-ingress.yaml"
echo "✓ Ingress creado"

echo ""
echo "==========================================="
echo "✓ Authelia desplegado con éxito"
echo "==========================================="
echo ""
echo "Verificando estado del deployment..."
echo ""

kubectl -n authelia get pods

echo ""
echo "Para ver los logs:"
echo "  kubectl -n authelia logs -f deployment/authelia"
echo ""
echo "Para verificar que el pod está listo:"
echo "  kubectl -n authelia get pods -w"
echo ""
echo "Una vez que el pod esté en estado 'Running', accede a:"
echo "  https://auth.TUDOMINIO.COM"
echo ""
