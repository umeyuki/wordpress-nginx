# Virtual Configuration for PHP FastCGI
server {
    listen   18082; ## listen for ipv4; this line is default and implied
    #listen   [::]:80 default ipv6only=on; ## listen for ipv6

    server_name  _;

    location / {
        root   /var/www/kyofu-daichan.com;
        index  index.php;

        # static files
        if (-f $request_filename) {
            expires 30d;
            break;
        }

        # request to index.php
        if (!-e $request_filename) {
            rewrite ^(.+)$  /index.php?q=$1 last;
        }
    }

    location ~ \.php$ {
        root /var/www/kyofu-daichan.com; 
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass   phpfpm;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  /var/www/kyofu-daichan.com/$fastcgi_script_name;
        include        fastcgi_params;
    }

    access_log /var/log/nginx/kyofu-daichan.com/fcgi_access.log;
    error_log /var/log/nginx/kyofu-daichan.com/fcgi_error.log;
}

server {
    listen 80;
    server_name kyofu-daichan.com *.kyofu-daichan.com;

    location ~ /favicon.ico {
        access_log  off;
        expires 24h;
        root /var/www/kyofu-daichan.com;
        break;
    }
    location ~ ^/(media|share_img)/.+.(jpg|jpeg|gif|png|css|js|flv|swf|ico|xml)(\?[0-9\.]*)?$ {
        access_log  off;
        expires 24h;
        root /var/www/kyofu-daichan.com;
        break;
    }
    location ~ ^/purge(/.*)$ {
        access_log  off;
        allow 127.0.0.1;
        allow 49.212.131.72;
        deny all;
        proxy_cache_purge czone "$scheme$host$1";
    }

    # WordPress Static Files
    location ~ ^/wp-[^/]+/.+.(jpg|jpeg|gif|png|css|js|flv|swf|ico|xml)(\?[0-9\.]*)?$ {
        access_log  off;
        #expires 24h;
        root /var/www/kyofu-daichan.com;
        break;
    }
    rewrite /wp-admin$ $scheme://$host$uri/ permanent;
    access_log /var/log/nginx/kyofu-daichan.com/access.log;
    error_log /var/log/nginx/kyofu-daichan.com/error.log;
    if (!-e $request_filename) {
#        rewrite ^/(.+)$ /$1 redirect;
        rewrite ^/(wp-.*)$ /$1 last;
#        rewrite ^/(wp-admin/.*\.php)$ /$1 last;
        rewrite ^/(.*\.php)$ /$1 last;
    }
    location / {
        set $do_not_cache 0;
        if ($http_cookie ~* "comment_author_|wordpress_(?!test_cookie)|wp-postpass_" ) {
            set $do_not_cache 1;
        }

        if ( $uri ~ /wp-content/(plugins|themes)/.+\.(jpg|jpeg|gif|png|css|js|flv|swf|ico|xml)(\?ver=.+)?$ ) {
            access_log off;
            expires 24h;
        } 

        if ( $uri ~ /wp-includes/(js|css|images)/.+\.(jpg|jpeg|gif|png|css|js|flv|swf|ico|xml)(\?ver=.+)?$ ) {
            access_log off;
            expires 24h;
        } 

        if ($http_user_agent ~* “2.0\ 2mmp|240×320|400x240|avantgo|blackberry|blazer|cellphone|danger|docomo|elaine/3.0|eudoraweb|googlebot-mobile|hiptop|iemobile|kyocera/wx310k|lg/u990|midp-2.|mmef20|mot-v|netfront|newt|nintendo\ wii|nitro|nokia|opera\ mini|palm|playstation\ portable|portalmmm|proxinet|proxinet|sharp-tq-gx10|shg-i900|small|sonyericsson|symbian\ os|symbianos|ts21i-10|up.browser|up.link|webos|windows\ ce|winwap|yahooseeker/m1a1-r2d2|iphone|ipod|android|blackberry9530|lg-tu915\ obigo|lge\ vx|webos|nokia5800″) {
            set $do_not_cache 1;
        }

        proxy_no_cache     $do_not_cache;
        proxy_cache_bypass $do_not_cache;
        proxy_cache        czone;
        proxy_cache_key    $scheme$host$uri$is_args$args;
        proxy_cache_valid  200 1d;
        proxy_pass         http://kyofu-daichan.com_backend;

    }
}
