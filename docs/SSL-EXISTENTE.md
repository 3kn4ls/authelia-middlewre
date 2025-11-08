# Usar Authelia con Certificados SSL Existentes

Si ya tienes certificados SSL configurados en tu cluster K3s (por ejemplo, con Let's Encrypt), esta guía te mostrará cómo Authelia funcionará con tu configuración existente.

## Escenarios Comunes

### Escenario 1: Certificado Wildcard (*.tudominio.com)

Si tienes un certificado wildcard que cubre `*.tudominio.com`, **no necesitas hacer nada adicional**. Authelia funcionará automáticamente con tu certificado existente.

**Cómo verificar:**

```bash
# Ver tus certificados existentes
kubectl get certificates --all-namespaces

# Ver los secrets TLS
kubectl get secrets --all-namespaces | grep tls
```

Si tienes un secret TLS para tu dominio wildcard, puedes referenciarlo en el Ingress de Authelia:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: authelia
  namespace: authelia
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  rules:
  - host: auth.tudominio.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: authelia
            port:
              number: 80
  tls:
  - hosts:
    - auth.tudominio.com
    secretName: tu-wildcard-tls-secret  # Nombre de tu secret wildcard existente
```

### Escenario 2: cert-manager con ClusterIssuer

Si ya tienes cert-manager instalado con un ClusterIssuer (ej: `letsencrypt-prod`), solo necesitas añadir la anotación al Ingress de Authelia:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: authelia
  namespace: authelia
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # Tu ClusterIssuer existente
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  rules:
  - host: auth.tudominio.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: authelia
            port:
              number: 80
  tls:
  - hosts:
    - auth.tudominio.com
    secretName: authelia-tls  # cert-manager creará esto automáticamente
```

### Escenario 3: Certificado Manual/Propio

Si cargaste manualmente un certificado SSL como Secret en Kubernetes:

1. **Ver tus secrets TLS:**
   ```bash
   kubectl get secrets -n authelia --field-selector type=kubernetes.io/tls
   ```

2. **Si el secret está en otro namespace**, cópialo al namespace de Authelia:
   ```bash
   kubectl get secret tu-tls-secret -n tu-namespace -o yaml | \
   sed 's/namespace: tu-namespace/namespace: authelia/' | \
   kubectl apply -f -
   ```

3. **Referencia el secret en el Ingress:**
   ```yaml
   tls:
   - hosts:
     - auth.tudominio.com
     secretName: tu-tls-secret
   ```

### Escenario 4: Traefik Maneja SSL Automáticamente

Si Traefik está configurado para manejar SSL automáticamente (por ejemplo, con un certificado por defecto), simplemente asegúrate de que el Ingress use el entrypoint correcto:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: authelia
  namespace: authelia
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  rules:
  - host: auth.tudominio.com
    # ... resto de la configuración
  # NO es necesaria la sección tls si Traefik la maneja automáticamente
```

## Configuración Paso a Paso

### 1. Identificar Tu Configuración SSL Actual

Ejecuta estos comandos para entender cómo está configurado tu SSL:

```bash
# Ver ClusterIssuers de cert-manager (si lo usas)
kubectl get clusterissuer

# Ver certificados existentes
kubectl get certificates --all-namespaces

# Ver secrets TLS
kubectl get secrets --all-namespaces --field-selector type=kubernetes.io/tls

# Ver la configuración de Traefik
kubectl -n kube-system get configmap traefik -o yaml
```

### 2. Actualizar el Ingress de Authelia

Según lo que encontraste arriba, edita `k8s/authelia/07-ingress.yaml`:

**Para certificado wildcard existente:**

```bash
# Primero encuentra el nombre de tu secret
WILDCARD_SECRET=$(kubectl get secrets --all-namespaces --field-selector type=kubernetes.io/tls -o jsonpath='{.items[?(@.metadata.annotations.cert-manager\.io/common-name=="*.tudominio.com")].metadata.name}')

echo "Tu secret wildcard es: $WILDCARD_SECRET"
```

Luego edita el Ingress:

```yaml
spec:
  # ... rules ...
  tls:
  - hosts:
    - auth.tudominio.com
    secretName: $WILDCARD_SECRET  # Reemplaza con el nombre real
```

**Para cert-manager automático:**

Solo descomenta las líneas en `k8s/authelia/07-ingress.yaml`:

```yaml
annotations:
  cert-manager.io/cluster-issuer: "letsencrypt-prod"  # O tu ClusterIssuer

# Y al final del archivo:
tls:
- hosts:
  - auth.tudominio.com
  secretName: authelia-tls
```

### 3. Aplicar los Cambios

```bash
kubectl apply -f k8s/authelia/07-ingress.yaml
```

### 4. Verificar el Certificado

```bash
# Ver el certificado en el Ingress
kubectl describe ingress authelia -n authelia

# Si usas cert-manager, ver el estado del certificado
kubectl get certificate -n authelia
kubectl describe certificate authelia-tls -n authelia

# Probar el certificado desde fuera
curl -vI https://auth.tudominio.com 2>&1 | grep -A 10 "SSL connection"

# O con OpenSSL
openssl s_client -connect auth.tudominio.com:443 -servername auth.tudominio.com < /dev/null
```

## Proteger Servicios con SSL

Cuando proteges otros servicios con Authelia, también usarán tus certificados SSL existentes de la misma manera:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mi-servicio
  namespace: default
  annotations:
    # Authelia
    traefik.ingress.kubernetes.io/router.middlewares: authelia-authelia@kubernetescrd

    # SSL (usa el mismo método que Authelia)
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"

    # Si usas cert-manager:
    # cert-manager.io/cluster-issuer: "letsencrypt-prod"
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
  # Si usas wildcard o cert-manager:
  # tls:
  # - hosts:
  #   - miapp.tudominio.com
  #   secretName: tu-secret-tls  # O déjalo a cert-manager generar uno
```

## Troubleshooting SSL

### Certificado no válido / Error de certificado

1. **Verifica que el dominio esté cubierto:**
   ```bash
   # Ver el certificado actual
   kubectl get secret tu-secret-tls -n authelia -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text | grep -A 2 "Subject Alternative Name"
   ```

2. **Si el dominio no está cubierto**, necesitas:
   - Regenerar el certificado incluyendo `auth.tudominio.com`
   - O usar cert-manager para generar uno específico

### Redirect loop después de login

Si después de hacer login en Authelia te redirige infinitamente, verifica:

1. **La sesión domain en Authelia** debe coincidir con tu dominio:
   ```yaml
   # En k8s/authelia/02-configmap.yaml
   session:
     domain: tudominio.com  # SIN 'auth.' o 'www.'
   ```

2. **El protocolo en el redirect** debe ser HTTPS:
   ```yaml
   # En k8s/authelia/06-middleware.yaml
   address: http://authelia.authelia.svc.cluster.local/api/verify?rd=https://auth.tudominio.com
   #                                                                    ^^^^^^ HTTPS
   ```

### Error "x509: certificate signed by unknown authority"

Tu certificado probablemente es autofirmado o de una CA personalizada. Opciones:

1. **Usar Let's Encrypt** (recomendado para producción)
2. **Añadir tu CA al trust store** del sistema
3. **Solo para desarrollo**: Aceptar el certificado en el navegador

## Consejos de Seguridad

1. **Usa siempre HTTPS** para Authelia (no HTTP)
2. **Verifica que el certificado sea válido** antes de exponer al internet
3. **Configura renovación automática** de certificados (cert-manager lo hace)
4. **Usa certificados de CA reconocidas** (Let's Encrypt, DigiCert, etc.) en producción
5. **Monitorea la expiración** de certificados:
   ```bash
   kubectl get certificates --all-namespaces
   ```

## Resumen Rápido

Para la mayoría de usuarios con SSL ya configurado:

1. ✅ **NO necesitas modificar nada** si tienes certificado wildcard
2. ✅ **Solo añade una anotación** si usas cert-manager
3. ✅ **Authelia respeta tu configuración SSL** existente
4. ✅ **Todos los servicios protegidos** usarán el mismo método SSL

Si tienes dudas, la opción más simple es usar cert-manager con Let's Encrypt - ver `docs/CERT-MANAGER.md` para configuración completa.
