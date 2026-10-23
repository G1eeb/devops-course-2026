#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

# Определение корня репозитория (требование 2)
REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

# 1. Разбор аргументов (требование 1)
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
elif [[ -n "${1:-}" ]]; then
    echo "Ошибка: неизвестный аргумент '$1'" >&2
    echo "Использование: $0 [--dry-run]" >&2
    exit 1
fi

# 2. Проверка требования 4: наличие site/index.html
if [[ ! -f "${REPO_ROOT}/site/index.html" ]]; then
    echo "Ошибка: обязательный файл site/index.html отсутствует!" >&2
    exit 1
fi

# 3. Проверка требования 5: отсутствие незафиксированных изменений в рабочей копии и индексе
if ! git -C "${REPO_ROOT}" diff --quiet || ! git -C "${REPO_ROOT}" diff --cached --quiet; then
    echo "Ошибка: в репозитории есть незафиксированные изменения!" >&2
    echo "Зафиксируйте изменения коммитом перед выполнением деплоя." >&2
    exit 1
fi

# 4. Формирование опций rsync (требования 3, 8 и 9)
# rsync открывает ровно 1 SSH-соединение для передачи; опции SSH задают неинтерактивный режим
SSH_CMD="ssh -o BatchMode=yes -o ConnectTimeout=5"
RSYNC_OPTS=(-avz --delete --chmod=D755,F644 -e "${SSH_CMD}")

if [[ "${DRY_RUN}" == true ]]; then
    echo "=== Запуск деплоя в режиме пробного прогона (--dry-run) ==="
    rsync "${RSYNC_OPTS[@]}" --dry-run "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"
    echo "План операций выведен. Состояние сервера не изменялось."
    exit 0
fi

# 5. Фактическая синхронизация каталога
echo "Синхронизация файлов на сервер ${REMOTE}:${REMOTE_DIR}..."
rsync "${RSYNC_OPTS[@]}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# 6. Проверка доступности ресурса (требование 6)
echo "Проверка доступности веб-ресурса по адресу ${SITE_URL}..."
if ! curl -f -s -o /dev/null --cacert "${CA_CERT}" "${SITE_URL}"; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен после доставки!" >&2
    exit 1
fi

# 7. Успешное завершение (требование 7)
COMMIT_HASH="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
echo "Деплой успешно завершён. Доставлен коммит: ${COMMIT_HASH}"
exit 0
