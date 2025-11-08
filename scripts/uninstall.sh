#!/bin/bash

# Script para desinstalar Authelia del cluster K3s

set -e

echo "==========================================="
echo "  Desinstalando Authelia de K3s"
echo "==========================================="
echo ""

read -p "¿Estás seguro de que quieres desinstalar Authelia? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operación cancelada."
    exit 0
fi

echo ""
echo "Eliminando recursos de Authelia..."
echo ""

# Directorio raíz del proyecto
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K8S_DIR="$PROJECT_ROOT/k8s/authelia"

# Eliminar en orden inverso
kubectl delete -f "$K8S_DIR/07-ingress.yaml" --ignore-not-found=true
echo "✓ Ingress eliminado"

kubectl delete -f "$K8S_DIR/06-middleware.yaml" --ignore-not-found=true
echo "✓ Middleware eliminado"

kubectl delete -f "$K8S_DIR/05-service.yaml" --ignore-not-found=true
echo "✓ Service eliminado"

kubectl delete -f "$K8S_DIR/04-deployment.yaml" --ignore-not-found=true
echo "✓ Deployment eliminado"

kubectl delete -f "$K8S_DIR/03-secret.yaml" --ignore-not-found=true
echo "✓ Secrets eliminados"

kubectl delete -f "$K8S_DIR/02-configmap.yaml" --ignore-not-found=true
echo "✓ ConfigMap eliminado"

kubectl delete -f "$K8S_DIR/01-pvc.yaml" --ignore-not-found=true
echo "✓ PersistentVolumeClaim eliminado"

echo ""
read -p "¿Deseas eliminar también el namespace (esto eliminará todos los datos)? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl delete -f "$K8S_DIR/00-namespace.yaml" --ignore-not-found=true
    echo "✓ Namespace eliminado"
fi

echo ""
echo "==========================================="
echo "✓ Authelia desinstalado con éxito"
echo "==========================================="
echo ""
