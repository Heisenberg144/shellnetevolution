#!/bin/bash
# Por Adrian Gabriel Cirino
# Configuração de certificado SSL para Nginx
sslconf_file="ssl_certificate /etc/nginx/certificado/cert.crt;
ssl_certificate_key /etc/nginx/certificado/cert.key;
ssl_dhparam /etc/nginx/certificado/dhparam.pem;"

# Página inicial exibida no PHP
indexphp_file="<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <title>Hello World</title>
    <link href=\"https://fonts.googleapis.com/css2?family=Montserrat:wght@700\&display=swap\" rel=\"stylesheet\">
    <style>
        body {
            background-color: #041656;
            color: #0AE782;
            font-family: \"Montserrat\", sans-serif;
            font-weight: 700;
            font-size: 4em;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            margin: 0;
        }
    </style>
</head>
<body>
    Eu tô no NET {evolution}! 🚀<br>
    <a href=\"?page= adrian cirino\" style=\"color:#0AE782; font-size:0.4em;\">local host de Adrian Cirino</a>
</body>
</html>"

# Configuração do pool do PHP-FPM
wwwconf_file="[www]
user = www-data
group = www-data
listen = /run/php/php-fpm.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 200
pm.start_servers = 20
pm.min_spare_servers = 10
pm.max_spare_servers = 20
pm.max_requests = 1000
pm.status_path = /status
ping.path = /ping
ping.response = OK
chdir = /"

# Configuração de status do PHP e Nginx
statusproc_file="server {
	listen 8087;
	listen [::]:8087;
	allow 127.0.0.1;
	allow ::1;
	deny all;

	location ~ ^/(status|ping)$ {
		chunked_transfer_encoding off;
		include fastcgi_params;
		fastcgi_pass unix:/run/php/php-fpm.sock;
		fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
	}

	location /basic_status {
		stub_status;
	}
}"

# Fonte do repositório MariaDB
mariadbsource_file="# MariaDB 11.4 repository list
# https://mariadb.org/download/
Types: deb
URIs: https://mirror.rackspace.com/mariadb/repo/11.4/debian
Suites: bookworm
Components: main
Signed-By: /etc/apt/keyrings/mariadb-keyring.pgp"

# FUNÇÓES

# Função para criar certificado SSL autoassinado
configurar_certificado() {
    echo "[INFO] Criando certificado SSL..."

    mkdir -p /etc/nginx/certificado

    # Geração de chaves e certificado autoassinado
    openssl req -x509 -nodes -days 4380 -newkey rsa:4096 \
        -keyout "/etc/nginx/certificado/cert.key" \
        -out "/etc/nginx/certificado/cert.crt" \
        -subj "/C=BR/ST=netevolution/L=Chapeco/O=Dis/CN=netevolution.ixcsoft.com.br" || {
            echo "[ERRO] Falha ao criar chaves do certificado."
            exit 1
        }

    # Geração do Diffie-Hellman Parameter
    openssl dhparam -out "/etc/nginx/certificado/dhparam.pem" 2048 || {
        echo "[ERRO] Falha ao criar dhparam."
        exit 1
    }

    echo "[OK] Certificado SSL gerado."
}

# Função para instalar e configurar Nginx
config_nginx() {
    echo "[INFO] Configurando Nginx..."

    nginx -t || {
        apt purge nginx-common nginx nginx-core -y
        rm -rf /etc/nginx
        apt install nginx -y
    }

    systemctl start nginx
    systemctl enable nginx

    configurar_certificado

    # Remove configuração padrão
    rm -f /etc/nginx/sites-enabled/default

    # Configuração HTTP -> HTTPS
    cat > /etc/nginx/sites-enabled/http <<EOF
server {
	listen 80 default_server;
	listen [::]:80 default_server;
	location / {
		return 301 https://\$host\$request_uri;
	}
}
EOF

    # Configuração HTTPS
    cat > /etc/nginx/sites-enabled/https <<EOF
server {
	listen 443 ssl;
	listen [::]:443 ssl;
	include sites-enabled/*.conf;
	error_page 405 =200;

	root /var/www/html;
	server_name _;
	index index.php index.html;

	location / {
		try_files \$uri \$uri/ /index.php?\$args;
	}

	location ~ \.php$ {
		include /etc/nginx/fastcgi_params;
		include snippets/fastcgi-php.conf;
		fastcgi_pass unix:/run/php/php-fpm.sock;
		fastcgi_read_timeout 3600;
	}
}
EOF

    # Configuração SSL
    echo "$sslconf_file" > /etc/nginx/sites-enabled/ssl.conf

    nginx -t && echo "[OK] Nginx configurado."
}

# Função para instalar e configurar PHP-FPM
config_php() {
    echo "[INFO] Configurando PHP..."

    php -v || {
        apt purge -y php8.2-common php8.2-fpm php8.2-cli
        rm -rf /etc/php/8.2/
        apt install php8.2-fpm -y
    }

    systemctl start php8.2-fpm
    systemctl enable php8.2-fpm

    mkdir -p /var/www/html
    echo "$indexphp_file" > /var/www/html/index.php
    chown -R www-data:www-data /var/www/html
    chmod -R 755 /var/www/html

    echo "[OK] PHP configurado."
}

# Função para configurar monitoramento de processos
config_processos() {
    echo "[INFO] Configurando monitoramento de processos..."

    echo "$wwwconf_file" > /etc/php/8.2/fpm/pool.d/www.conf
    echo "$statusproc_file" > /etc/nginx/sites-enabled/status_proc

    systemctl reload nginx
    nginx -t && echo "[OK] Monitoramento configurado."
}

# Função para instalar e configurar MariaDB
config_banco() {
    echo "[INFO] Configurando MariaDB..."

    bd_file=$(echo ./*.sql | awk '{print $1}')
    bd_usuario="netevolution"
    bd_senha="netevolution"
    bd_host="localhost"

    apt install apt-transport-https curl -y
    mkdir -p /etc/apt/keyrings
    curl -o /etc/apt/keyrings/mariadb-keyring.pgp "https://mariadb.org/mariadb_release_signing_key.pgp"
    echo "$mariadbsource_file" > /etc/apt/sources.list.d/mariadb.sources

    apt update
    apt install mariadb-server -y

    mariadb -e "CREATE DATABASE IF NOT EXISTS std"
    mariadb std < "$bd_file"
    mariadb -e "CREATE USER IF NOT EXISTS '$bd_usuario'@'$bd_host' IDENTIFIED BY '$bd_senha'"

    echo "[OK] Banco de dados configurado."
}

# Função principal que chama todas as outras
principal() {
    if [ "$EUID" -ne 0 ]; then
        echo "[ERRO] Execute como root."
        exit 1
    fi

    apt update
    config_nginx
    config_php
    config_processos
    config_banco
}

# Execução do script
principal
