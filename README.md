# Uptime Kuma — локальный контур мониторинга

Решение разворачивает Uptime Kuma 2 с MariaDB и независимый слой наблюдаемости Prometheus + Grafana. Жизненным циклом Docker Compose управляет Dagger Go module.

## Архитектура

Слой приложения (compose/app.yml): Uptime Kuma 2 использует MariaDB через официальные переменные UPTIME_KUMA_DB_*. MariaDB 11.4 работает одной нодой; данные MariaDB и приложения сохраняются в named volumes. Порт БД не опубликован на хост.

Слой наблюдаемости (compose/monitoring.yml): Prometheus собирает метрики cAdvisor, node-exporter, mysqld-exporter и blackbox-exporter. Blackbox проверяет HTTP Uptime Kuma и TCP MariaDB. Grafana содержит provisioning и dashboard с состояниями сервисов, CPU/RAM контейнеров и доступностью БД.

Два Compose-проекта соединяются внешней сетью kuma-observability. Веб-порты опубликованы только на loopback: Uptime Kuma 3001, Grafana 3000, Prometheus 9090.

## Требования

- Docker Engine и Docker Compose plugin v2 либо Docker Desktop с WSL2.
- Dagger CLI 0.21.11 или совместимая версия.
- Git.

На Docker Desktop метрики node-exporter относятся к Linux VM, а не к физической Windows/macOS системе. На Linux cAdvisor и node-exporter используют host mounts; cAdvisor требует расширенных привилегий.

Проверить версии:

    docker version
    docker compose version
    dagger version

## Подготовка

    git clone https://github.com/ArtMagedon/kaspersky-DevOps-monitoring.git
    cd kaspersky-DevOps-monitoring
    cp .env.example .env

Замените все пароли в .env на уникальные длинные секреты. Для совместимости с shell-скриптами используйте hex-строки, например openssl rand -hex 24 для каждого значения. Не коммитьте .env: он исключён через .gitignore.

После клонирования или изменения экспортируемых методов Go-модуля выполните:

    dagger develop

Dagger подключается к Docker daemon через /var/run/docker.sock. На Linux процесс Dagger должен иметь доступ к сокету. На Windows используйте WSL2 и Docker Desktop с работающим Docker Engine.

## Запуск

    dagger call deploy-app
    dagger call deploy-monitoring
    dagger call configure-grafana

Полный запуск с проверкой:

    dagger call deploy-all

Отдельная проверка:

    dagger call validate

## Адреса

- Uptime Kuma: http://localhost:3001
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090

Учётные данные Grafana задаются в .env. При первом входе в Uptime Kuma создайте администратора.

В Prometheus откройте Status → Targets: ожидаются UP для prometheus, cadvisor, node-exporter, mysqld-exporter и двух blackbox jobs. В Grafana откройте dashboard Uptime Kuma — Infrastructure health в папке General.

## Chaos testing

    dagger call chaos-test --target uptime-kuma
    dagger call chaos-test --target mariadb

Сценарий выполняет docker stop, ждёт probe_success=0 в Prometheus, затем docker start и ждёт probe_success=1. После этого docker kill проверяет автоматический рестарт по restart: unless-stopped.

Важно: намеренный docker stop не вызывает автоматический restart policy. Поэтому после наблюдения DOWN сценарий явно выполняет docker start. Автоматическое восстановление проверяется отдельным аварийным завершением процесса через docker kill. Grafana обновит значения с учётом scrape_interval 15 секунд.

## Остановка и очистка

    docker compose --env-file .env -f compose/monitoring.yml down
    docker compose --env-file .env -f compose/app.yml down

Named volumes сохраняются. Для полного удаления данных (необратимо):

    docker compose --env-file .env -f compose/monitoring.yml down -v
    docker compose --env-file .env -f compose/app.yml down -v
    docker network rm kuma-observability

## Структура

- dagger.json, go.mod, main.go — Dagger Go module.
- compose/ — два независимых Compose-файла.
- prometheus/ — scrape и Blackbox exporter конфигурации.
- grafana/ — provisioning и dashboard.
- mariadb/init/ — создание отдельного пользователя exporter.
- scripts/ — Grafana API, validation и chaos testing.
- AI_REVIEW.md — использование AI и разбор проверенных предложений.

## Эксплуатационные замечания

Uptime Kuma поддерживает MariaDB в ветке 2.x; v1 использует SQLite. Прямая штатная миграция существующей SQLite базы на MariaDB не поддерживается. Для production закрепляйте образы по digest, используйте secret store, TLS reverse proxy, резервное копирование volumes и регулярное обновление. cAdvisor работает с privileged и host mounts; это осознанное послабление локального стенда.
