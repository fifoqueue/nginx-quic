#!/bin/sh

### Read config
if [ ! -f "config.inc" ]; then
    echo "--- The configuration file (config.inc) could not be found. Apply as default setting. ---"
    echo "--- All additional modules are not used. ---"
else
    . ./config.inc
fi

### If the value is incorrect, convert to normal data.
if [ ! "$SERVER_HEADER" ]; then SERVER_HEADER="hakase"; fi
if [ "$BITCHK" != 32 ] && [ "$BITCHK" != 64 ]; then BITCHK=32; fi
if [ ! "$LTO" ]; then LTO=0; fi
if [ ! "$BUILD_MTS" ]; then BUILD_MTS="-j2"; fi
if [ ! "$NGX_PREFIX" ]; then NGX_PREFIX="/usr/local/nginx"; fi
if [ ! "$NGX_SBIN_PATH" ]; then NGX_SBIN_PATH="/usr/sbin/nginx"; fi
if [ ! "$NGX_CONF" ]; then NGX_CONF="/etc/nginx/nginx.conf"; fi
if [ ! "$NGX_LIB" ]; then NGX_LIB="/var/lib/nginx"; fi
if [ ! "$NGX_LOG" ]; then NGX_LOG="/var/log/nginx"; fi
if [ ! "$NGX_PID" ]; then NGX_PID="/var/run/nginx.pid"; fi
if [ ! "$NGX_LOCK" ]; then NGX_LOCK="/var/lock/nginx.lock"; fi
if [ ! "$NGINX_PATCH_VERSION" ]; then NGINX_PATCH_VERSION="release-1.30.0"; fi
if [ ! "$OPENSSL_VERSION" ]; then OPENSSL_VERSION="openssl-3.6.2"; fi

### Remove Old file
rm -f ${NGX_SBIN_PATH}.old

### Multithread build
BUILD_MTS="-j$(expr $(nproc) \+ 1)"

### Submodule update
git submodule sync --recursive || exit 1
git submodule update --init --recursive --remote --force || exit 1

### OpenSSL source checkout
if ! git -C lib/openssl rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -e "lib/openssl" ]; then
        echo "lib/openssl exists but is not a git checkout."
        echo "Remove it or initialize it with https://github.com/openssl/openssl.git."
        exit 1
    fi

    git clone https://github.com/openssl/openssl.git lib/openssl || exit 1
fi

git -C lib/openssl remote set-url origin https://github.com/openssl/openssl.git || exit 1
git -C lib/openssl fetch --tags --force origin || exit 1
git -C lib/openssl checkout --force "$OPENSSL_VERSION" || exit 1

### LTO Build
if [ "$LTO" = 1 ]; then
    BUILD_LTO="-flto -ffat-lto-objects"
    BUILD_OPENSSL_LTO="-flto -ffat-lto-objects"
else
    BUILD_LTO=""
    BUILD_OPENSSL_LTO=""
fi

BUILD_OPENSSL_OPT="no-tests no-makedepend ${BUILD_OPENSSL_LTO}"

### nginx-ssl-fingerprint patches
OPENSSL_PATCH_FILE="lib/nginx-ssl-fingerprint/patches/${OPENSSL_VERSION}.patch"

if [ "$SSL_FINGERPRINT" = 1 ]; then
    NGINX_PATCH_FILE="lib/nginx-ssl-fingerprint/patches/${NGINX_PATCH_VERSION}.patch"

    if ! grep -q "fp_ja_data" "src/event/ngx_event_openssl.h"; then
        if [ ! -f "$NGINX_PATCH_FILE" ]; then
            echo "nginx patch file not found: $NGINX_PATCH_FILE"
            exit 1
        fi
        patch --forward --fuzz=3 -d . -p1 < "$NGINX_PATCH_FILE" || exit 1
    fi

    if ! grep -q "SSL_client_hello_get_ja_data" "lib/openssl/include/openssl/ssl.h.in"; then
        if [ ! -f "$OPENSSL_PATCH_FILE" ]; then
            echo "OpenSSL patch file not found: $OPENSSL_PATCH_FILE"
            exit 1
        fi
        patch -d lib/openssl -p1 < "$OPENSSL_PATCH_FILE" || exit 1
    fi
fi

### OpenSSL build
case ./lib/openssl in
    /*) OPENSSL_PREFIX="./lib/openssl/.openssl" ;;
    *)  OPENSSL_PREFIX="$PWD/lib/openssl/.openssl" ;;
esac

if [ ! -f "lib/openssl/.openssl/include/openssl/ssl.h" ] \
    || [ ! -f "lib/openssl/.openssl/lib/libssl.a" ] \
    || [ ! -f "lib/openssl/.openssl/lib/libcrypto.a" ]; then
    (
        cd lib/openssl || exit 1
        if [ -f Makefile ]; then
            make clean || exit 1
        fi
        ./config --prefix="$OPENSSL_PREFIX" no-shared no-threads $BUILD_OPENSSL_OPT || exit 1
        make $BUILD_MTS || make $BUILD_MTS || exit 1
        make install_sw LIBDIR=lib || exit 1
    ) || exit 1
fi

### PCRE reconf
if [ ! -f "lib/pcre/configure" ]; then
    cd lib/pcre
    autoreconf -f -i
    cd ../..
fi

### ZLIB reconf
if [ -f "lib/zlib-ng/configure" ]; then
    cd lib/zlib-ng
    ./configure
    cd ../..
fi

### ZLIB reconf
#if [ "$BITCHK" = 64 ]; then
#    if [ ! -f "lib/zlib/Makefile" ]; then
#        cd lib/zlib
#        ./configure --64
#        cd ../..
#    fi
#else
#    if [ ! -f "lib/zlib_x86/Makefile" ]; then
#        git submodule add --force https://github.com/madler/zlib.git lib/zlib_x86
#        cd lib/zlib_x86
#        ./configure
#        cd ../..
#    fi
#fi

### x86, x64 Check (Configuration)
if [ "$BITCHK" = 64 ]; then
    # Temporary remove
    #BUILD_BIT="-m64 "
    BUILD_ZLIB="./lib/zlib-ng"
    BUILD_LD="-lrt -ljemalloc -Wl,-z,relro -Wl,-z,now -fPIC"
else
    BUILD_BIT=""
    BUILD_ZLIB="./lib/zlib-ng"
    BUILD_LD=""
fi

### Temporary Ubuntu/Debian build error (libxslt/libxml2)
### URL : https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=721602
TEMP_OPT="-lm"

### Module check
if [ "$PAGESPEED" = 1 ]; then BUILD_MODULES="--add-module=./lib/pagespeed ${PS_NGX_EXTRA_FLAGS}"; fi
if [ "$FLV" = 1 ]; then BUILD_MODULES="${BUILD_MODULES} --add-module=./lib/nginx-http-flv-module"; fi
if [ "$NAXSI" = 1 ]; then
    BUILD_MODULES="${BUILD_MODULES} --add-module=./lib/naxsi/naxsi_src"
    BUILD_NAXSI_CC_OPT="-Wno-enum-int-mismatch -Wno-unused-function"
fi
if [ "$DAV_EXT" = 1 ]; then BUILD_MODULES="${BUILD_MODULES} --add-module=./lib/nginx-dav-ext-module"; fi
if [ "$FANCYINDEX" = 1 ]; then BUILD_MODULES="${BUILD_MODULES} --add-module=./lib/ngx-fancyindex"; fi
if [ "$GEOIP2" = 1 ]; then BUILD_MODULES="${BUILD_MODULES} --add-module=./lib/ngx_http_geoip2_module"; fi
if [ "$VTS" = 1 ]; then BUILD_MODULES="${BUILD_MODULES} --add-module=./lib/nginx-module-vts"; fi
if [ "$ZSTD" = 1 ]; then BUILD_MODULES="${BUILD_MODULES} --add-module=./lib/zstd-nginx-module"; fi
if [ "$DYNAMIC_ETAG" = 1 ]; then BUILD_MODULES="${BUILD_MODULES} --add-module=./lib/ngx_dynamic_etag"; fi
if [ "$CACHE_PURGE" = 1 ]; then BUILD_MODULES="${BUILD_MODULES} --add-module=./lib/ngx_cache_purge"; fi
if [ "$SSL_FINGERPRINT" = 1 ]; then BUILD_MODULES="${BUILD_MODULES} --add-module=./lib/nginx-ssl-fingerprint"; fi

auto/configure \
--with-cc-opt="-Wno-stringop-truncation ${BUILD_NAXSI_CC_OPT} -DTCP_FASTOPEN=23 ${BUILD_BIT}${BUILD_LTO} ${TEMP_OPT} -g -O3 -march=native -fstack-protector-strong -fuse-ld=gold -fuse-linker-plugin --param=ssp-buffer-size=4 -Wformat -Werror=format-security -Wno-strict-aliasing -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2 -gsplit-dwarf -DNGX_HTTP_HEADERS" \
--with-ld-opt="${BUILD_LD} ${BUILD_LTO}" \
--builddir=objs --prefix=${NGX_PREFIX} \
--conf-path=${NGX_CONF} \
--pid-path=${NGX_PID} \
--lock-path=${NGX_LOCK} \
--http-log-path=${NGX_LOG}/access.log \
--error-log-path=${NGX_LOG}/error.log \
--sbin-path=${NGX_SBIN_PATH} \
--http-client-body-temp-path=${NGX_LIB}/client_body_temp \
--http-proxy-temp-path=${NGX_LIB}/proxy_temp \
--http-fastcgi-temp-path=${NGX_LIB}/fastcgi_temp \
--http-scgi-temp-path=${NGX_LIB}/scgi_temp \
--http-uwsgi-temp-path=${NGX_LIB}/uwsgi_temp \
--with-pcre=./lib/pcre \
--with-pcre-jit \
--with-zlib=${BUILD_ZLIB} \
--with-openssl=./lib/openssl \
--with-openssl-opt="${BUILD_OPENSSL_OPT}" \
--with-http_realip_module \
--with-http_addition_module \
--with-http_sub_module \
--with-http_dav_module \
--with-http_stub_status_module \
--with-http_flv_module \
--with-http_mp4_module \
--with-http_gunzip_module \
--with-http_slice_module \
--with-http_xslt_module \
--with-http_gzip_static_module \
--with-http_auth_request_module \
--with-http_dav_module \
--with-http_random_index_module \
--with-http_secure_link_module \
--with-http_image_filter_module \
--with-file-aio \
--with-threads \
--with-libatomic \
--with-mail \
--with-compat \
--with-stream \
--with-http_ssl_module \
--with-mail_ssl_module \
--with-http_v2_module \
--with-http_v2_hpack_enc \
--with-http_v3_module \
--with-stream_ssl_module \
--with-stream_realip_module \
--with-stream_ssl_preread_module \
--add-module=./lib/ngx_devel_kit \
--add-module=./lib/ngx_brotli \
--add-module=./lib/headers-more-nginx-module \
${BUILD_MODULES}

### OpenSSL has already been built above.
### Keep nginx's OpenSSL make target newer than the generated Makefile.
if [ ! -f "lib/openssl/.openssl/include/openssl/ssl.h" ]; then
    echo "OpenSSL install header not found: lib/openssl/.openssl/include/openssl/ssl.h"
    exit 1
fi
touch lib/openssl/.openssl/include/openssl/ssl.h || exit 1

### SERVER HEADER CONFIG
NGX_AUTO_CONFIG_H="objs/ngx_auto_config.h";have="NGINX_SERVER";value="\"${SERVER_HEADER}\""; . auto/define

### Install
make $BUILD_MTS install

### Make directory NGX_LIB
mkdir -p ${NGX_LIB}

### Check for old files
if [ -f "${NGX_SBIN_PATH}.old" ]; then
    ### Test nginx configuration.
    "$NGX_SBIN_PATH" -t > /dev/null 2>&1
    if test $? -ne 0; then
        echo "Failed nginx configuration test."
        exit 1
    fi
    sleep 1
    rm ${NGX_SBIN_PATH}.old
    systemctl restart nginx
fi
