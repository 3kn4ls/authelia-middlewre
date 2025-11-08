# Configurar Certificados SSL con cert-manager

Esta guía te ayudará a configurar certificados SSL automáticos usando cert-manager y Let's Encrypt.

## ¿Por qué usar cert-manager?

- **Certificados gratuitos** de Let's Encrypt
- **Renovación automática** antes de que expiren
- **Integración nativa** con Kubernetes
- **HTTPS en todos tus servicios** sin esfuerzo manual

## Instalación de cert-manager

### Paso 1: Instalar cert-manager

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

Verifica la instalación:

```bash
kubectl get pods -n cert-manager
```

Espera a que todos los pods estén en `Running`.

### Paso 2: Crear ClusterIssuer para Let's Encrypt

Crea un archivo `letsencrypt-prod.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # Email para notificaciones de Let's Encrypt
    email: tuusuario@tudominio.com

    # Servidor de producción de Let's Encrypt
    server: https://acme-v02.api.letsencrypt.org/directory

    privateKeySecretRef:
      name: letsencrypt-prod

    solvers:
    # Solver HTTP01 para validación
    - http01:
        ingress:
          class: traefik
```

Aplica el ClusterIssuer:

```bash
kubectl apply -f letsencrypt-prod.yaml
```

### Paso 3 (Opcional): Crear ClusterIssuer de Staging

Para pruebas, usa el servidor de staging de Let's Encrypt (límites más altos):

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: tuusuario@tudominio.com
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: traefik
```

## Configurar SSL para Authelia

### Opción A: Modificar el Ingress de Authelia

Edita `k8s/authelia/07-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: authelia
  namespace: authelia
  annotations:
    # Cert-manager
    cert-manager.io/cluster-issuer: "letsencrypt-prod"

    # Traefik
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

  # Sección TLS
  tls:
  - hosts:
    - auth.tudominio.com
    secretName: authelia-tls  # Cert-manager creará este secret automáticamente
```

Aplica los cambios:

```bash
kubectl apply -f k8s/authelia/07-ingress.yaml
```

### Opción B: Comando rápido

Si ya tienes el Ingress creado:

```bash
kubectl annotate ingress authelia \
  cert-manager.io/cluster-issuer=letsencrypt-prod \
  -n authelia

kubectl patch ingress authelia -n authelia --type=json -p='[
  {
    "op": "add",
    "path": "/spec/tls",
    "value": [
      {
        "hosts": ["auth.tudominio.com"],
        "secretName": "authelia-tls"
      }
    ]
  }
]'
```

## Verificar el Certificado

### Ver el estado de la Certificate Request

```bash
kubectl get certificate -n authelia
kubectl describe certificate authelia-tls -n authelia
```

### Ver los CertificateRequests

```bash
kubectl get certificaterequest -n authelia
```

### Ver los Challenges

```bash
kubectl get challenge -n authelia
```

Si hay problemas, revisa los logs:

```bash
kubectl logs -n cert-manager deployment/cert-manager
```

## Configurar SSL para otros Servicios

Para cualquier otro servicio, solo necesitas añadir las mismas anotaciones:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mi-servicio
  namespace: default
  annotations:
    # Authelia
    traefik.ingress.kubernetes.io/router.middlewares: authelia-authelia@kubernetescrd

    # SSL con cert-manager
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
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
  tls:
  - hosts:
    - miapp.tudominio.com
    secretName: miapp-tls
```

## Redirección Automática de HTTP a HTTPS

Para redirigir automáticamente HTTP a HTTPS, crea un middleware:

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: https-redirect
  namespace: default
spec:
  redirectScheme:
    scheme: https
    permanent: true
```

Luego añade el middleware a tus Ingress:

```yaml
annotations:
  traefik.ingress.kubernetes.io/router.middlewares: default-https-redirect@kubernetescrd,authelia-authelia@kubernetescrd
```

## Troubleshooting

### El certificado no se genera

1. Verifica que cert-manager está corriendo:
   ```bash
   kubectl get pods -n cert-manager
   ```

2. Verifica el ClusterIssuer:
   ```bash
   kubectl get clusterissuer
   kubectl describe clusterissuer letsencrypt-prod
   ```

3. Revisa los challenges:
   ```bash
   kubectl get challenge -n authelia
   kubectl describe challenge -n authelia
   ```

### Error "too many certificates already issued"

Let's Encrypt tiene límites de rate:
- **50 certificados** por dominio por semana
- **5 duplicados** por semana

Solución: Usa el ClusterIssuer de staging para pruebas.

### El challenge HTTP01 falla

Verifica que:
1. El puerto 80 está abierto y redirigido a tu K3s
2. El DNS apunta correctamente a tu IP
3. Traefik puede servir el challenge:
   ```bash
   curl -I http://tudominio.com/.well-known/acme-challenge/test
   ```

### Certificado de staging en producción

Si usaste el ClusterIssuer de staging y quieres cambiarlo a producción:

1. Elimina el secret:
   ```bash
   kubectl delete secret authelia-tls -n authelia
   ```

2. Cambia el issuer en el Ingress:
   ```yaml
   cert-manager.io/cluster-issuer: "letsencrypt-prod"
   ```

3. Aplica los cambios:
   ```bash
   kubectl apply -f k8s/authelia/07-ingress.yaml
   ```

## Renovación Automática

cert-manager renueva automáticamente los certificados cuando quedan menos de 30 días para expirar. No necesitas hacer nada manualmente.

Para forzar una renovación inmediata:

```bash
kubectl delete secret authelia-tls -n authelia
kubectl delete certificate authelia-tls -n authelia
kubectl apply -f k8s/authelia/07-ingress.yaml
```

## Wildcard Certificates

Para un certificado wildcard (`*.tudominio.com`), necesitas usar DNS01 en lugar de HTTP01:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns
spec:
  acme:
    email: tuusuario@tudominio.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-dns
    solvers:
    - dns01:
        cloudflare:  # O tu proveedor DNS
          email: tuusuario@cloudflare.com
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
```

Esto requiere configurar credenciales de tu proveedor DNS.

## Recursos Adicionales

- [Documentación de cert-manager](https://cert-manager.io/docs/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [cert-manager con Traefik](https://cert-manager.io/docs/tutorials/acme/ingress/)

---

Con cert-manager configurado, todos tus servicios tendrán certificados SSL válidos y se renovarán automáticamente. ¡Nunca más tendrás que preocuparte por certificados expirados! 🔒✨
