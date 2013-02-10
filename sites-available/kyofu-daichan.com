server {
    listen       80;
    server_name kyofu-daichan.com www.kyofu-daichan.com;
    root /var/www/kyofu-daichan.com;
    access_log logs/access.log main;

    location / {
        # 静的なファイルの場合は処理をとめる
        # リクエストの度にファイルの存在をチェックするのは無駄だという意見もありますが、
        # どのURLの時index.phpに渡すのか、プラグインを含めて全仕様が分からないため、
        # これが最も安全だと思います。
        if (-f $request_filename) {
            break;
        }

        # ここからWP Super Cacheの設定（少しfastcgi cacheの設定も）
        # モバイルからのアクセスはキャッシュさせないようにする変数
        set $nocache "";
        set $supercache_file $document_root/wp-content/cache/supercache/${http_host}${uri}/index.html;
        set $supercache_uri "";
        if (-f $supercache_file) {
            set $supercache_uri /wp-content/cache/supercache/${http_host}${uri}/index.html;
        }

        if ($request_method = "POST") {
            set $supercache_uri "";
            set $nocache "1";
        }

        if ($query_string ~ .*=.*) {
            set $supercache_uri "";
        }

        if ($http_cookie ~ ^.*(comment_author_|wordpress_logged_in|wp-postpass_).*$) {
            set $supercache_uri "";
            set $nocache "1";
        }

        if ($http_x_wap_profile ~ ^[a-z0-9\"]+) {
            set $supercache_uri "";
            set $nocache "1";
        }

        if ($http_profile ~ ^[a-z0-9\"]+) {
            set $supercache_uri "";
            set $nocache "1";
        }

        if ($http_user_agent ~ ^.*(2.0\ MMP|240x320|400X240|AvantGo|BlackBerry|Blazer|Cellphone|Danger|DoCoMo|Elaine/3.0|EudoraWeb|Googlebot-Mobile|hiptop|IEMobile|KYOCERA/WX310K|LG/U990|MIDP-2.|MMEF20|MOT-V|NetFront|Newt|Nintendo\ Wii|Nitro|Nokia|Opera\ Mini|Palm|PlayStation\ Portable|portalmmm|Proxinet|ProxiNet|SHARP-TQ-GX10|SHG-i900|Small|SonyEricsson|Symbian\ OS|SymbianOS|TS21i-10|UP.Browser|UP.Link|webOS|Windows\ CE|WinWAP|YahooSeeker/M1A1-R2D2|iPhone|iPod|Android|BlackBerry9530|LG-TU915\ Obigo|LGE\ VX|webOS|Nokia5800).*) {
            set $supercache_uri "";
            set $nocache "1";
        }

        if ($http_user_agent ~ ^(w3c\ |w3c-|acs-|alav|alca|amoi|audi|avan|benq|bird|blac|blaz|brew|cell|cldc|cmd-|dang|doco|eric|hipt|htc_|inno|ipaq|ipod|jigs|kddi|keji|leno|lg-c|lg-d|lg-g|lge-|lg/u|maui|maxo|midp|mits|mmef|mobi|mot-|moto|mwbp|nec-|newt|noki|palm|pana|pant|phil|play|port|prox|qwap|sage|sams|sany|sch-|sec-|send|seri|sgh-|shar|sie-|siem|smal|smar|sony|sph-|symb|t-mo|teli|tim-|tosh|tsm-|upg1|upsi|vk-v|voda|wap-|wapa|wapi|wapp|wapr|webc|winw|winw|xda\ |xda-).*) {
            set $supercache_uri "";        
            set $nocache "1";
        }

        if ($http_user_agent ~ ^(DoCoMo/|J-PHONE/|J-EMULATOR/|Vodafone/|MOT(EMULATOR)?-|SoftBank/|[VS]emulator/|KDDI-|UP\.Browser/|emobile/|Huawei/|IAC/|Nokia|mixi-mobile-converter/)) {
            set $supercache_uri "";
            set $nocache "1";
        }

        if ($http_user_agent ~ (DDIPOCKET\;|WILLCOM\;|Opera\ Mini|Opera\ Mobi|PalmOS|Windows\ CE\;|PDA\;\ SL-|PlayStation\ Portable\;|SONY/COM|Nitro|Nintendo)) {
            set $supercache_uri "";
            set $nocache "1";
        }

        if ($supercache_uri) {
            rewrite ^ $supercache_uri last;
            break;
        }

        rewrite ^ /index.php last;
    }

    location ~ \.php {
        # 存在しないPHPファイルをシャットアウト
        if (!-f $request_filename) {
            return 404;
            break;
        }

        # fastcgi とfastcgi cacheの設定
        include ./fastcgi.conf;
        fastcgi_pass          phpfpm;
        fastcgi_cache         czone;
        fastcgi_cache_key     "$scheme://$host$request_uri";
        fastcgi_cache_valid   200 10m;
        fastcgi_cache_valid   404 1m;
        # $nocache = "1"の時、fastcgi cacheが無効になる
        fastcgi_cache_bypass  $nocache;
        fastcgi_pass_header "X-Accel-Redirect";
        fastcgi_pass_header "X-Accel-Expires";
    }

    # よくアクセスされる静的ファイルにブラウザキャッシュが効くように設定
    location ~ \.(jpg|png|gif|swf|jpeg)$ {
        log_not_found off; # 404の時にerror_logに書き込まないようにする設定
        access_log off;
        expires 3d;
    }

    location ~ \.ico$ {
        log_not_found off;
        access_log off;
        expires max;
    }

    location ~ \.(css|js)$ {
        charset  UTF-8;
        access_log off;
        expires 1d;
    }

    # ドット始まりのファイルはアクセスできないように
    location ~ /\. {
        deny all;
        log_not_found off;
        access_log off;
    }

    # リライトされたWP Super Cacheのファイル
    location ~ /wp-content/cache/supercache/${http_host}${uri}/index\.html(\.gz)?$ {
        charset  UTF-8;
        internal; # この指定をしておくとURLを指定して直接アクセスできなくなる
    }

    location ~ /wp-admin/$ {
        rewrite ^/wp-admin/$ /wp-admin/index.php last;
    }
}
