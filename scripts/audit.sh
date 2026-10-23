
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

# TODO 1: проверьте, что значение параметра port отлично от 22
CURRENT_PORT="$(sudo sshd -T | awk '/^port/{print $2}')"
if [[ "$CURRENT_PORT" != "22" && -n "$CURRENT_PORT" ]]; then
    check "Порт SSH отличен от 22 (текущий: $CURRENT_PORT)" "true" "true"
else
    check "Порт SSH отличен от#!/usr/bin/env bash
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

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1 22 (текущий: $CURRENT_PORT)" "true" "false"
fi

# TODO 2: проверьте, что значение параметра maxauthtries равно 3
check "Лимит попыток аутентификации MaxAuthTries равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"

# TODO 3: проверьте, что политика по умолчанию для входящего трафика равна deny
DEFAULT_INCOMING="unknown"
if sudo ufw status verbose | grep -i "Default:" | grep -iq "deny (incoming)"; then
    DEFAULT_INCOMING="deny"
fi
check "Политика по умолчанию для входящего трафика: deny" "deny" "$DEFAULT_INCOMING"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s)\n", $1, $3}' /etc/passwd

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
