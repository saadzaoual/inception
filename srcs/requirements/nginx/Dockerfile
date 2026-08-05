FROM debian:bookworm
RUN apt-get update -y && \
    apt-get install -y nginx openssl
RUN mkdir -p /etc/nginx/ssl
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/inception.key \
    -out /etc/nginx/ssl/inception.crt \
    -subj "/C=MA/ST=Marrakesh/L=Benguerir/O=1337/OU=Inception/CN=szaoual.42.fr"
COPY conf/nginx.conf /etc/nginx/sites-available/default
EXPOSE 443
CMD ["nginx", "-g", "daemon off;"]