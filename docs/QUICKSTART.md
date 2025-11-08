# Guía de Inicio Rápido - Authelia en K3s

Esta guía te llevará desde cero hasta tener Authelia funcionando en tu K3s en menos de 10 minutos.

## Checklist Pre-instalación

Antes de empezar, verifica que tienes:

- [ ] Cluster K3s funcionando
- [ ] `kubectl` instalado y configurado
- [ ] Un dominio (ej: `midominio.com`)
- [ ] DNS configurado apuntando `*.midominio.com` a tu IP pública
- [ ] Puertos 80 y 443 redirigidos a tu Raspberry Pi (192.168.1.95)
- [ ] Certificados SSL configurados (si ya los tienes, ¡perfecto! Ver `docs/SSL-EXISTENTE.md`)
- [ ] Docker instalado (solo para generar passwords)

## Instalación en 5 Pasos

### 1️⃣ Personalizar Dominio (1 minuto)

```bash
cd authelia-middlewre
./scripts/customize-domain.sh midominio.com
```

### 2️⃣ Generar Secretos (2 minutos)

```bash
./scripts/generate-secrets.sh
```

Copia los 3 valores generados y pégalos en `k8s/authelia/03-secret.yaml`:

```yaml
stringData:
  JWT_SECRET: "pegar_aquí"
  SESSION_SECRET: "pegar_aquí"
  STORAGE_ENCRYPTION_KEY: "pegar_aquí"
```

### 3️⃣ Generar Password de Admin (2 minutos)

```bash
./scripts/generate-password.sh
# Ingresa tu password cuando te lo pida
```

Copia el hash generado y actualiza en `k8s/authelia/03-secret.yaml`:

```yaml
users:
  admin:
    displayname: "Administrador"
    password: "pegar_hash_aquí"
    email: admin@midominio.com
```

### 4️⃣ Desplegar Authelia (2 minutos)

```bash
./scripts/deploy.sh
```

Espera a que el pod esté listo:

```bash
kubectl -n authelia get pods -w
```

### 5️⃣ Acceder al Portal (1 minuto)

Abre tu navegador y accede a:

```
https://auth.midominio.com
```

**Sobre SSL/HTTPS:**
- Si ya tienes certificados SSL configurados (Let's Encrypt, wildcard, etc.), Authelia los usará automáticamente
- Si tu certificado cubre `*.midominio.com`, ya estás listo
- Si necesitas configurar SSL desde cero, consulta `docs/CERT-MANAGER.md`
- Para usar un certificado SSL existente específico, consulta `docs/SSL-EXISTENTE.md`

Inicia sesión con:
- Usuario: `admin`
- Password: el que configuraste en el paso 3

¡Listo! ✅

## Siguiente Paso: Proteger tu Primer Servicio

Supongamos que tienes un servicio llamado `mi-app` con este Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mi-app
  namespace: default
spec:
  rules:
  - host: app.midominio.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: mi-app
            port:
              number: 80
```

Para protegerlo con Authelia, solo añade esta anotación:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mi-app
  namespace: default
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: authelia-authelia@kubernetescrd
spec:
  # ... resto igual
```

Aplica los cambios:

```bash
kubectl apply -f mi-app-ingress.yaml
```

Ahora cuando accedas a `https://app.midominio.com`, te pedirá que inicies sesión con Authelia primero.

## Comandos Útiles

### Ver estado de Authelia

```bash
kubectl -n authelia get all
```

### Ver logs

```bash
kubectl -n authelia logs -f deployment/authelia
```

### Reiniciar Authelia

```bash
kubectl rollout restart deployment/authelia -n authelia
```

### Actualizar configuración

Después de modificar ConfigMaps o Secrets:

```bash
kubectl apply -f k8s/authelia/02-configmap.yaml
kubectl apply -f k8s/authelia/03-secret.yaml
kubectl rollout restart deployment/authelia -n authelia
```

## ¿Problemas?

### No puedo acceder al portal

1. Verifica el DNS:
   ```bash
   nslookup auth.midominio.com
   ```

2. Verifica el pod:
   ```bash
   kubectl -n authelia get pods
   ```

3. Revisa los logs:
   ```bash
   kubectl -n authelia logs deployment/authelia
   ```

### Error 502 al proteger un servicio

Verifica la anotación del middleware:

```bash
kubectl describe ingress MI-INGRESS -n MI-NAMESPACE
```

La anotación debe ser exactamente:
```
traefik.ingress.kubernetes.io/router.middlewares: authelia-authelia@kubernetescrd
```

Si tu servicio está en otro namespace, usa:
```
traefik.ingress.kubernetes.io/router.middlewares: TU-NAMESPACE-authelia@kubernetescrd
```

## Próximos Pasos

Una vez que tengas Authelia funcionando:

1. **Configura 2FA**: Ve a tu perfil y registra un dispositivo TOTP
2. **Añade más usuarios**: Edita `k8s/authelia/03-secret.yaml`
3. **Protege más servicios**: Añade la anotación del middleware a otros Ingress
4. **Configura cert-manager**: Para certificados SSL automáticos
5. **Personaliza políticas**: Edita las reglas en `k8s/authelia/02-configmap.yaml`

Para más información, consulta el [README principal](../README.md).
