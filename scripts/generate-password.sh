#!/bin/bash

# Script para generar un password hasheado con Argon2id para Authelia
# Uso: ./generate-password.sh [password]
# Si no se proporciona password, se pedirá de forma interactiva

set -e

echo "==========================================="
echo "  Generador de Password Hash para Authelia"
echo "==========================================="
echo ""

# Verificar si Docker está disponible
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker no está instalado o no está en el PATH"
    echo ""
    echo "Este script requiere Docker para generar el hash del password."
    echo "Por favor, instala Docker o genera el hash manualmente desde un pod de Authelia."
    exit 1
fi

# Obtener el password
if [ -z "$1" ]; then
    echo "Ingresa el password que quieres hashear:"
    read -s PASSWORD
    echo ""
    echo "Confirma el password:"
    read -s PASSWORD_CONFIRM
    echo ""

    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        echo "❌ Error: Los passwords no coinciden"
        exit 1
    fi
else
    PASSWORD="$1"
fi

echo "Generando hash del password..."
echo ""

# Generar el hash usando Docker
HASH=$(docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password "$PASSWORD" 2>/dev/null | grep 'Digest:' | awk '{print $2}')

if [ -z "$HASH" ]; then
    echo "❌ Error: No se pudo generar el hash"
    exit 1
fi

echo "✓ Hash generado con éxito"
echo ""
echo "==========================================="
echo "Hash del password:"
echo "==========================================="
echo ""
echo "$HASH"
echo ""
echo "==========================================="
echo ""
echo "Copia este hash en el archivo k8s/authelia/03-secret.yaml"
echo "en la sección 'users_database.yml' bajo el usuario correspondiente."
echo ""
