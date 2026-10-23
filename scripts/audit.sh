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
    check "Порт SSH отличен от 22 (текущий: $CURRENT_PORT)" "true" "false"
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
