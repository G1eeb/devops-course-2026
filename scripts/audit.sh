#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK] $desc"
        ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date +'%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

CURRENT_PORT="$(sudo sshd -T | awk '/^port/{print $2}')"
if [[ "$CURRENT_PORT" != "22" && -n "$CURRENT_PORT" ]]; then
    check "Порт SSH отличен от 22 (текущий: $CURRENT_PORT)" "true" "true"
else
    check "Порт SSH отличен от 22 (текущий: $CURRENT_PORT)" "true" "false"
fi

check "Лимит попыток аутентификации MaxAuthTries равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"

DEFAULT_INCOMING="unknown"
if sudo ufw status verbose | grep -i "Default:" | grep -iq "deny (incoming)"; then
    DEFAULT_INCOMING="deny"
fi
check "Политика по умолчанию для входящего трафика: deny" "deny" "$DEFAULT_INCOMING"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s)\n", $1, $3}' /etc/passwd

echo "[4] Веб-сервер"
# а) служба nginx активна
check "Служба nginx активна" "active" "$(systemctl is-active nginx 2>/dev/null || echo 'inactive')"

# б) конфигурация nginx синтаксически корректна
sudo nginx -t >/dev/null 2>&1 && NGINX_SYNTAX="ok" || NGINX_SYNTAX="error"
check "Синтаксис конфигурации Nginx корректен" "ok" "$NGINX_SYNTAX"

# в) сертификат не истекает в течение 30 дней (30 дней = 2592000 сек)
CERT_DAYS_SEC=${AUDIT_CERT_OFFSET:-2592000}
if openssl x509 -checkend "$CERT_DAYS_SEC" -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; then
    CERT_STATUS="valid"
else
    CERT_STATUS="expiring"
fi
check "Сертификат devops.crt действует не менее 30 дней" "valid" "$CERT_STATUS"

# г) отсутствие файлов с правами записи для всех и строгие права 600 на закрытый ключ
WORLD_WRITABLE="$(find /var/www/devops-site -perm -o+w 2>/dev/null | tr '\n' ' ')"
KEY_PERM="$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null || echo 'none')"

if [[ -z "${WORLD_WRITABLE// /}" && "$KEY_PERM" == "600" ]]; then
    SECURITY_CHECK="secure"
else
    SECURITY_CHECK="insecure (wr: [${WORLD_WRITABLE}], key: [${KEY_PERM}])"
fi
check "Безопасность файлов (нет world-writable и права ключа 600)" "secure" "$SECURITY_CHECK"

echo "[5] Контейнеризация"
# а) служба docker активна
check "Служба docker активна" "active" "$(systemctl is-active docker 2>/dev/null || echo 'inactive')"

# б) контейнер СУБД находится в состоянии healthy
DB_CONTAINER="$(docker ps -aq -f "name=app-db-1" 2>/dev/null || true)"
if [[ -n "$DB_CONTAINER" ]]; then
    DB_HEALTH="$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo 'unknown')"
else
    DB_HEALTH="not_found"
fi
check "Контейнер СУБД app-db-1 в состоянии healthy" "healthy" "$DB_HEALTH"

# в) порты 5000 и 5432 не прослушиваются ни на одном адресе, кроме 127.0.0.1
INSECURE_PORTS="$(ss -tln 2>/dev/null | awk '{print $4}' | grep -E ':(5000|5432)$' | grep -v '127.0.0.1' | tr '\n' ' ')"
if [[ -z "${INSECURE_PORTS// /}" ]]; then
    PORTS_STATUS="secure"
else
    PORTS_STATUS="insecure: $INSECURE_PORTS"
fi
check "Порты 5000 и 5432 изолированы (только 127.0.0.1)" "secure" "$PORTS_STATUS"

# г) права файла ~/app/.env равны 600
ENV_FILE="${HOME}/app/.env"
if [[ -f "$ENV_FILE" ]]; then
    ENV_PERM="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || echo 'none')"
else
    ENV_PERM="missing"
fi
check "Права файла ~/app/.env равны 600" "600" "$ENV_PERM"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
