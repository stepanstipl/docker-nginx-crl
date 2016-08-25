# docker-nginx-crl

This container will accept list of CRL's urls, create concatenated crl file for
nginx and periodically check whether any of these has been updated and if so,
update the crl bundle and notify nginx to reload it's configuration.

**This container needs to run in same IPC space as nginx one - see
docker-compose example and expects access to nginx.pid file in order to send
reload notifications.**

## crl.sh usage
```
crl.sh

Usage:
  crl.sh -s url_1 [-s url_2...] [-k] -t output
  crl.sh -h

Options:
  -h            Show this screen.
  -i            Interval to sleep in seconds (default 60, env CRL_INTERVAL)
  -k            Do not verify server ssl certs (curl -k, env CRL_VERIFY).
  -l            Header to check for modification (default Last-Modified, env CRL_HEADER).
  -m            Temp directory (default /tmp/crl.temp, env CRL_TMP).
  -p            Nginx PID location (default /run/nginx.pid, env CRL_NGINX_PID)
  -r            Signal to send to process on reload (default HUP, env CRL_SIGNAL)
  -s            Source url (required, env CRL_SOURCES).
  -t            Target file (required, env CRL_TARGET).
```

### example 
`./crl/sh -s https://mycrl.internal/crl.pem -t /etc/crl.pem`
