#!/bin/bash

# Script para generar los secretos aleatorios necesarios para Authelia
# Ejecuta este script y copia los valores generados en k8s/authelia/03-secret.yaml

set -e

echo "==========================================="
echo "  Generador de Secretos para Authelia"
echo "==========================================="
echo ""

echo "Generando secretos aleatorios..."
echo ""

JWT_SECRET=$(openssl rand -hex 32)
SESSION_SECRET=$(openssl rand -hex 32)
STORAGE_SECRET=$(openssl rand -hex 32)

echo "✓ Secretos generados con éxito"
echo ""
echo "==========================================="
echo "Copia estos valores en el archivo:"
echo "k8s/authelia/03-secret.yaml"
echo "==========================================="
echo ""
echo "JWT_SECRET: \"$JWT_SECRET\""
echo "SESSION_SECRET: \"$SESSION_SECRET\""
echo "STORAGE_ENCRYPTION_KEY: \"$STORAGE_SECRET\""
echo ""
echo "==========================================="
echo ""
echo "IMPORTANTE: Guarda estos valores en un lugar seguro."
echo "Si los pierdes, tendrás que regenerar las sesiones de todos los usuarios."
echo ""
