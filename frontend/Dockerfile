FROM nginx:1.27-alpine
# Copy static assets
COPY index.html /usr/share/nginx/html/index.html
# nginx config is injected via ConfigMap at runtime — see applications/templates/configmap.yaml
USER 101
EXPOSE 8080
