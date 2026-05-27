# [7] Установка .NET 10

## Задача
Установить `dotnet-sdk-10.0` через официальный репозиторий Microsoft.

## Цель
Среда выполнения для backend Part 1 на nodeA (:8081) — опциональный компонент (только если `INSTALL_DOTNET=1`).

## Обоснование
Официальные пакеты Microsoft для Ubuntu — единственный поддерживаемый способ установки .NET 10 на Linux Ubuntu 24.04.

## Ссылки
- [.NET on Linux Ubuntu](https://learn.microsoft.com/dotnet/core/install/linux-ubuntu)

## Детали

### Репозиторий Microsoft
URL пакета: `https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb`

Установка: `dpkg -i <packages-microsoft-prod.deb>` → `apt-get update` → `apt-get install dotnet-sdk-10.0`

### Пакет
| Параметр | Значение |
|---|---|
| Имя пакета | `dotnet-sdk-10.0` |
| ОС | Ubuntu 24.04 |

### Порты
| Компонент | Порт | Видимость |
|---|---|---|
| Backend Part 1 | `:8081` | Внутренний (только nodeA) |
