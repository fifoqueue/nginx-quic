# nginx-quic

Forked from [Hakase/nginx-quic](https://git.hakase.app/Hakase/nginx-quic)
Original: [nginx](https://github.com/nginx/nginx)

## 추가 내용

1. OCSP file stapling 지원 (`ssl_stapling on;` 및 `ssl_stapling_file ...;` 설정)
2. Server Header 지원 (config.inc 수정)
3. SSL 설정의 일부 변경 (ciphers, prefer, session_timeout, early_data, ...)
4. Cloudflare HPACK Patch 적용
5. SSL Dynamic 적용
6. JA3/JA4 SSL fingerprint 변수 지원 (`SSL_FINGERPRINT=1`)
7. nginx-ssl-fingerprint용 nginx core/OpenSSL patch 자동 적용
8. OpenSSL 4.0.1 정적 빌드 (RSA/ECDSA 다중 인증서 및 PQC hybrid key exchange 검증)
9. OpenResty lua-nginx-module 지원 (`LUA=1`)
10. nginx 표준 선택 모듈 추가 활성화 (`HTTP_DEGRADATION=1`, `PERL=1`, select/poll event modules)

## Debian/Ubuntu 기반

```
apt install build-essential libjemalloc-dev uuid-dev libatomic1 libatomic-ops-dev expat unzip autoconf automake libtool libgd-dev libmaxminddb-dev libxslt1-dev libxml2-dev curl golang libunwind-dev ninja-build libzstd-dev cmake patch libluajit-5.1-dev libperl-dev
```

Ubuntu 26.04 LTS / GCC 15 환경에서는 gold 링커가 기본 빌드 도구에서 빠져 있거나 deprecated 패키지로 분리되어 있을 수 있습니다. `auto.sh` 는 기본 링커를 사용하므로 gold 링커를 별도로 설치하지 않아도 됩니다.

`PERL=1` 로 `ngx_http_perl_module` 을 빌드하려면 `libperl-dev` 가 필요합니다. 설치되어 있지 않으면 링크 단계에서 `cannot find -lperl` 오류가 발생합니다. Perl 모듈이 필요 없으면 `config.inc` 에서 `PERL=0` 으로 비활성화하세요.

## RHEL 9

```
dnf install epel-release -y
dnf config-manager --set-enabled crb
dnf install automake cmake ninja-build golang gcc-c++ libtool libunwind-devel libxml2-devel libxslt-devel gd-devel jemalloc-devel libatomic_ops-devel libmaxminddb-devel libzstd-devel patch luajit-devel perl-devel
```

`PERL=1` 로 빌드하려면 `perl-devel` 이 필요합니다. Perl 모듈이 필요 없으면 `config.inc` 에서 `PERL=0` 으로 비활성화하세요.
