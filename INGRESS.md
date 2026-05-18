What you want to achieve

You want something like:

api.example.com → service A
app.example.com → service B
grafana.example.com → monitoring service

This is done using Ingress resources.


helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace

i want to use nginx, because it is the most popular


Internet
   ↓
[ Reverse Proxy / Ingress Controller ]
   ↓        ↓        ↓
 app      api     grafana
service   service   service
