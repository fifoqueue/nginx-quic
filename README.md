# nginx-quic

Forked from [Hakase/nginx-quic](https://git.hakase.app/Hakase/nginx-quic)
Original: [nginx](https://github.com/nginx/nginx)

## 추가 내용

1. ocsp file stapling 지원 (ssl_stapling on [http] 및 ssl_stapling_file [server] 사용 필요)
2. Server Header 지원 (config.inc 수정)
3. SSL 설정의 일부 변경 (ciphers, prefer, session_timeout, early_data, ...)
4. Cloudflare HPACK Patch 적용
5. SSL Dynamic 적용
6. JA3/JA4 SSL fingerprint 변수 지원 (`SSL_FINGERPRINT=1`)
7. nginx-ssl-fingerprint용 nginx core/OpenSSL patch 자동 적용
8. OpenSSL 3.6.2 정적 빌드
9. OpenResty lua-nginx-module 지원 (`LUA=1`)
10. nginx 표준 선택 모듈 추가 활성화 (`HTTP_DEGRADATION=1`, `PERL=1`, select/poll event modules)

## 미지원

1. Hybrid 인증서 지원 여부 미검증
2. OLD CHACHA20-POLY1305 미지원 (더 이상 쓸 일이 없음)
3. strict_sni 기능은 nginx 자체 기능에서 지원되므로 추가 지원 X
  - listen ssl 에 default_server 서버를 하나 만든 뒤에 ssl_reject_handshake on; 을 추가하세요.
  - http 에 추가 할 경우 TLS 오류가 발생할 수 있습니다.
  - strict_sni 처럼 http 안에서는 사용할 수 없습니다.
4. OCSP Stapling 은 제대로 지원 되지 않을 수 있음.
5. 기타 여러가지 버그가 아직 많을 수 있음.........

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
