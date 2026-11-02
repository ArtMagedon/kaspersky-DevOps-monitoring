# AI_REVIEW

## Использованные инструменты

- ChatGPT (GPT-6): анализ требований, проектирование Compose/Dagger, подготовка Go-модуля, конфигураций Prometheus/Grafana, скриптов и документации.
- Официальная документация и исходный код Uptime Kuma, Dagger, Docker, Grafana и exporters: проверка спорных технических решений.

## Примеры предложений, требующих проверки

1. **MariaDB в Uptime Kuma.** Утверждение, что Uptime Kuma поддерживает только SQLite, устарело для 2.x. В документации Uptime Kuma 2.x описаны MariaDB и переменные UPTIME_KUMA_DB_TYPE, UPTIME_KUMA_DB_HOSTNAME, UPTIME_KUMA_DB_PORT, UPTIME_KUMA_DB_NAME, UPTIME_KUMA_DB_USERNAME и UPTIME_KUMA_DB_PASSWORD. Для v1 этот backend не подходит.

2. **Поведение docker stop.** Ожидать автоматический restart после docker stop неправильно: намеренная остановка не запускает restart policy. Chaos test разделяет проверку DOWN/UP с docker stop/start и проверку автоматического восстановления через docker kill.

3. **Сетевой доступ из Dagger.** localhost внутри Dagger-контейнера не указывает на Grafana/Prometheus, запущенные Docker daemon на хосте. Для API и validation используется временный контейнер в сети kuma-observability и DNS-имена сервисов.

4. **Относительные пути Compose.** Пути bind mounts вычисляются относительно Compose-файла. В compose/*.yml используются ../prometheus, ../grafana и ../mariadb, соответствующие структуре репозитория.

5. **Проверка здоровья.** Успешный HTTP-запрос к Grafana не доказывает доступность MariaDB или Uptime Kuma. Validation дополнительно проверяет blackbox probe_success и mysql_up через Prometheus API.

## Проверки на целевой машине

- docker compose --env-file .env -f compose/app.yml config
- docker compose --env-file .env -f compose/monitoring.yml config
- dagger develop
- dagger call deploy-all
- Prometheus Status → Targets, запросы probe_success и mysql_up.
- Повторный dagger call configure-grafana для проверки идемпотентности.
- Оба chaos-test сценария.

## Ограничение верификации

Файлы подготовлены, но runtime deployment здесь не выполнялся: среда редактирования GitHub не предоставляет подключённый Docker daemon и Dagger Engine. Следовательно, запуск контейнеров, Grafana API, exporter scrape и chaos tests требуют проверки на целевой машине. Нельзя считать их пройденными до такого запуска.
