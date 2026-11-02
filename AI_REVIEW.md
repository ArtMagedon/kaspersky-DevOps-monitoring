# AI_REVIEW

## Использованные инструменты

- ChatGPT (GPT-6): анализ требований, проектирование Compose/Dagger, подготовка Go-модуля, конфигураций Prometheus/Grafana, скриптов и документации.
- Официальная документация и исходный код Uptime Kuma, Dagger, Docker, Grafana и exporters: проверка спорных технических решений.

## Примеры использованных промптов

1. «Спроектируй локальный стенд Uptime Kuma + MariaDB + Prometheus + Grafana с двумя независимыми Docker Compose-слоями и управлением через Dagger Go SDK».
2. «Реализуй Dagger-команды deploy-app, deploy-monitoring, configure-grafana и deploy-all; используй Docker socket и сделай повторные запуски идемпотентными».
3. «Подготовь Prometheus scrape-конфигурацию, Blackbox Exporter для HTTP/TCP, cAdvisor, node-exporter, mysqld-exporter и Grafana dashboard».
5. «Проверь конфигурации на ошибки интеграции: сетевую адресацию, пути bind mounts, API Grafana, restart policy и поддержку MariaDB в Uptime Kuma».

## Примеры некорректных или неоптимальных предложений и исправления

1. **MariaDB в Uptime Kuma.** В ранней гипотезе AI рассматривалась только SQLite. Это устаревшее ограничение для Uptime Kuma 2.x: официальная документация описывает MariaDB и переменные UPTIME_KUMA_DB_TYPE, UPTIME_KUMA_DB_HOSTNAME, UPTIME_KUMA_DB_PORT, UPTIME_KUMA_DB_NAME, UPTIME_KUMA_DB_USERNAME и UPTIME_KUMA_DB_PASSWORD. Проверка документации привела к использованию образа louislam/uptime-kuma:2 и внешней MariaDB. Для v1 такой backend не подходит.

3. **Сетевой доступ из Dagger.** В раннем варианте вспомогательный контейнер пытался подключить рабочую директорию через bind mount по пути /workspace. Поскольку Docker CLI управляет хостовым daemon, bind source разрешается на хосте, а не в файловой системе Dagger-контейнера. Исправление: временный контейнер подключается к сети kuma-observability, файлы копируются через docker cp, а команды запускаются через docker exec.

4. **Относительные пути Compose.** Первоначальные пути монтирования были рассчитаны относительно корня репозитория, хотя Compose разрешает относительные bind paths от каталога Compose-файла. Исправление: для конфигураций в compose/ используются пути ../prometheus, ../grafana и ../mariadb.

5. **Готовность Prometheus.** Одного успешного healthcheck Prometheus недостаточно: он может стать healthy до первого scrape. Проверка могла ложно завершиться ошибкой из-за отсутствия свежих probe_success/mysql_up. Исправление: validation повторяет запросы к Prometheus API с ограниченным временем ожидания.

## Проверки на целевой машине

- docker compose --env-file .env -f compose/app.yml config
- docker compose --env-file .env -f compose/monitoring.yml config
- dagger develop
- dagger call deploy-all
- Prometheus Status → Targets, запросы probe_success и mysql_up.
- Повторный dagger call configure-grafana для проверки идемпотентности.

## Ограничение верификации

Файлы подготовлены и загружены в репозиторий, но runtime deployment здесь не выполнялся: среда редактирования GitHub не предоставляет подключённый Docker daemon и Dagger Engine. Следовательно, запуск контейнеров, Grafana API, exporter scrape требуют проверки на целевой машине. Нельзя считать их пройденными до такого запуска.
