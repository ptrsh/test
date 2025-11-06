###############################################################################
# modules/ec2/main.tf - Модуль создания EC2 инстансов
###############################################################################

data "aws_vpc" "default" {
  for_each = toset([var.region])
  
  default = true
  region  = var.region
}

data "aws_ami" "selected" {
  for_each    = var.ami_id == "" ? toset([var.region]) : []
  most_recent = true
  owners      = ["amazon"]
  region      = var.region

  filter {
    name   = "name"
    values = [var.ami_name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "main" {
  name        = var.security_group_name
  description = "Security group for EC2 instances"
  vpc_id      = data.aws_vpc.default[var.region].id
  region      = var.region

  tags = merge(
    var.tags,
    {
      Name = var.security_group_name
    }
  )
}

resource "aws_security_group_rule" "ingress_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.main.id
  self              = true
  description       = "Allow all traffic from same security group"
  region            = var.region
}

resource "aws_security_group_rule" "ingress_wireguard" {
  type              = "ingress"
  from_port         = 51820
  to_port           = 51820
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.main.id
  description       = "Allow WireGuard UDP traffic"
  region            = var.region
}

resource "aws_security_group_rule" "ingress_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.main.id
  description       = "Allow SSH traffic"
  region            = var.region
}

resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.main.id
  description       = "Allow all outbound traffic"
  region            = var.region
}

resource "aws_key_pair" "main" {
  count      = var.create_key_pair ? 1 : 0
  key_name   = var.key_pair_name
  public_key = var.public_key
  region     = var.region

  tags = merge(
    var.tags,
    {
      Name = var.key_pair_name
    }
  )
}

resource "aws_instance" "main" {
  count                  = var.instance_count
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.selected[var.region].id
  instance_type          = var.instance_type
  key_name               = var.create_key_pair ? aws_key_pair.main[0].key_name : var.key_pair_name
  vpc_security_group_ids = [aws_security_group.main.id]
  region                 = var.region
  
  tags = merge(
    var.tags,
    {
      Name = "${var.instance_name_prefix}-${count.index + 1}"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# modules/ec2/variables.tf
###############################################################################

variable "region" {
  description = "AWS регион для создания ресурсов"
  type        = string
}

variable "instance_type" {
  description = "Тип EC2 инстанса"
  type        = string
  default     = "t3.micro"
}

variable "instance_count" {
  description = "Количество EC2 инстансов для создания"
  type        = number
  default     = 1
}

variable "instance_name_prefix" {
  description = "Префикс для имен инстансов"
  type        = string
  default     = "ec2-instance"
}

variable "security_group_name" {
  description = "Имя security group"
  type        = string
}

variable "ami_id" {
  description = "ID AMI для EC2 инстанса (если пусто, будет использован ami_name)"
  type        = string
  default     = ""
}

variable "ami_name" {
  description = "Имя AMI для поиска (используется если ami_id пуст)"
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "key_pair_name" {
  description = "Имя key pair для EC2 инстансов"
  type        = string
}

variable "create_key_pair" {
  description = "Создать ли новый key pair (если false, использует существующий)"
  type        = bool
  default     = false
}

variable "public_key" {
  description = "Публичный ключ SSH (требуется если create_key_pair = true)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Дополнительные теги для ресурсов"
  type        = map(string)
  default     = {}
}

###############################################################################
# modules/ec2/outputs.tf
###############################################################################

output "instance_ids" {
  description = "ID созданных EC2 инстансов"
  value       = aws_instance.main[*].id
}

output "instance_public_ips" {
  description = "Публичные IP адреса инстансов"
  value       = aws_instance.main[*].public_ip
}

output "instance_private_ips" {
  description = "Приватные IP адреса инстансов"
  value       = aws_instance.main[*].private_ip
}

output "security_group_id" {
  description = "ID security group"
  value       = aws_security_group.main.id
}

output "key_pair_name" {
  description = "Имя использованного key pair"
  value       = var.create_key_pair ? aws_key_pair.main[0].key_name : var.key_pair_name
}

###############################################################################
# modules/ec2/versions.tf
###############################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
  }
}

###############################################################################
# modules/quota-check/main.tf - Модуль проверки квот
###############################################################################

data "aws_servicequotas_service_quota" "ec2_standard" {
  service_code = "ec2"
  quota_code   = "L-1216C47A"
  region       = var.region
}

data "aws_ec2_instance_type" "selected" {
  instance_type = var.instance_type
  region        = var.region
}

data "aws_instances" "running_standard" {
  region = var.region
  
  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

locals {
  quota_limit       = data.aws_servicequotas_service_quota.ec2_standard.value
  vcpu_per_instance = data.aws_ec2_instance_type.selected.default_vcpus
  required_vcpu     = var.required_instances * local.vcpu_per_instance
  current_usage     = length(data.aws_instances.running_standard.ids) * 2
  available         = local.quota_limit - local.current_usage
  can_create        = local.available >= local.required_vcpu
}

###############################################################################
# modules/quota-check/variables.tf
###############################################################################

variable "region" {
  description = "AWS регион для проверки"
  type        = string
}

variable "instance_type" {
  description = "Тип инстанса для расчета vCPU"
  type        = string
  default     = "t3.micro"
}

variable "required_instances" {
  description = "Требуемое количество инстансов"
  type        = number
}

###############################################################################
# modules/quota-check/outputs.tf
###############################################################################

output "quota_limit" {
  description = "Лимит vCPU квоты"
  value       = local.quota_limit
}

output "current_usage" {
  description = "Текущее использование vCPU (приблизительно)"
  value       = local.current_usage
}

output "available" {
  description = "Доступно vCPU"
  value       = local.available
}

output "can_create" {
  description = "Можно ли создать требуемое количество инстансов"
  value       = local.can_create
}

output "required_vcpu" {
  description = "Требуется vCPU для создания инстансов"
  value       = local.required_vcpu
}

output "vcpu_per_instance" {
  description = "vCPU на один инстанс"
  value       = local.vcpu_per_instance
}

###############################################################################
# modules/quota-check/versions.tf
###############################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
  }
}

###############################################################################
# main.tf - Основная конфигурация
###############################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
  }
}

# Один провайдер для всех регионов!
provider "aws" {
  region = var.default_region
}

# Проверка квот для каждого региона
module "quota_check" {
  source   = "./modules/quota-check"
  for_each = var.regions

  region             = each.key
  instance_type      = var.instance_type
  required_instances = each.value.instance_count
}

# Создание EC2 инстансов в каждом регионе
module "ec2" {
  source   = "./modules/ec2"
  for_each = var.regions

  region               = each.key
  instance_type        = var.instance_type
  instance_count       = each.value.instance_count
  instance_name_prefix = "${var.project_name}-${each.key}"
  security_group_name  = "${var.project_name}-sg-${each.key}"
  ami_name             = var.ami_name
  key_pair_name        = var.key_pair_name
  create_key_pair      = var.create_key_pair
  public_key           = var.public_key

  tags = merge(
    var.common_tags,
    {
      Region = each.key
    }
  )
}

###############################################################################
# variables.tf
###############################################################################

variable "project_name" {
  description = "Имя проекта (используется в именах ресурсов)"
  type        = string
  default     = "my-project"
}

variable "default_region" {
  description = "Default AWS регион для провайдера"
  type        = string
  default     = "us-east-1"
}

variable "regions" {
  description = "Map регионов и количества инстансов в каждом"
  type = map(object({
    instance_count = number
  }))
  
  # Пример:
  # regions = {
  #   "us-east-1" = {
  #     instance_count = 2
  #   }
  #   "eu-west-1" = {
  #     instance_count = 3
  #   }
  #   "ap-southeast-1" = {
  #     instance_count = 1
  #   }
  # }
}

variable "instance_type" {
  description = "Тип EC2 инстанса"
  type        = string
  default     = "t3.micro"
}

variable "ami_name" {
  description = "Имя AMI для поиска"
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "key_pair_name" {
  description = "Имя key pair для EC2 инстансов"
  type        = string
}

variable "create_key_pair" {
  description = "Создать ли новый key pair"
  type        = bool
  default     = false
}

variable "public_key" {
  description = "Публичный ключ SSH (если create_key_pair = true)"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Общие теги для всех ресурсов"
  type        = map(string)
  default = {
    ManagedBy = "terraform"
  }
}

###############################################################################
# outputs.tf
###############################################################################

output "quota_check_results" {
  description = "Результаты проверки квот по регионам"
  value = {
    for region, check in module.quota_check : region => {
      quota_limit   = check.quota_limit
      current_usage = check.current_usage
      available     = check.available
      can_create    = check.can_create
      required_vcpu = check.required_vcpu
    }
  }
}

output "instances_by_region" {
  description = "Информация об инстансах по регионам"
  value = {
    for region, ec2 in module.ec2 : region => {
      instance_ids = ec2.instance_ids
      public_ips   = ec2.instance_public_ips
      private_ips  = ec2.instance_private_ips
    }
  }
}

output "ssh_commands" {
  description = "Команды для SSH подключения ко всем инстансам"
  value = {
    for region, ec2 in module.ec2 : region => [
      for ip in ec2.instance_public_ips :
      "ssh -i ~/.ssh/${var.key_pair_name} ubuntu@${ip}"
    ]
  }
}

output "all_instance_ids" {
  description = "Все ID инстансов из всех регионов"
  value = flatten([
    for region, ec2 in module.ec2 : ec2.instance_ids
  ])
}

###############################################################################
# terraform.tfvars.example
###############################################################################

project_name = "my-infrastructure"

# Default регион для провайдера
default_region = "us-east-1"

# Конфигурация регионов - ЛЮБЫЕ регионы AWS!
regions = {
  "us-east-1" = {
    instance_count = 2
  }
  "eu-west-1" = {
    instance_count = 3
  }
  "ap-southeast-1" = {
    instance_count = 1
  }
  "eu-central-1" = {
    instance_count = 2
  }
  # Добавляйте любые регионы без изменения кода!
}

# Настройки инстансов
instance_type = "t3.micro"
ami_name      = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"

# SSH ключ
key_pair_name   = "my-keypair"
create_key_pair = true
# public_key    = "ssh-rsa AAAA..."

# Теги
common_tags = {
  Environment = "production"
  ManagedBy   = "terraform"
  Project     = "infrastructure"
}

###############################################################################
# import.tf - Импорт существующих инстансов
###############################################################################

# Импорт с AWS Provider 6.0 стал проще!
# Новый синтаксис: ID@регион
#
# Способ 1: Команда terraform import с @регион
# terraform import 'module.ec2["us-east-1"].aws_instance.main[0]' i-1234567890abcdef0@us-east-1
# terraform import 'module.ec2["us-east-1"].aws_instance.main[1]' i-0987654321fedcba0@us-east-1
# terraform import 'module.ec2["eu-west-1"].aws_instance.main[0]' i-aabbccdd11223344@eu-west-1
#
# Способ 2: Import блоки (Terraform 1.5+)

# import {
#   to = module.ec2["us-east-1"].aws_instance.main[0]
#   id = "i-1234567890abcdef0@us-east-1"
# }

# import {
#   to = module.ec2["us-east-1"].aws_instance.main[1]
#   id = "i-0987654321fedcba0@us-east-1"
# }

# import {
#   to = module.ec2["eu-west-1"].aws_instance.main[0]
#   id = "i-aabbccdd11223344@eu-west-1"
# }

###############################################################################
# README.md
###############################################################################

# AWS EC2 Multi-Region Infrastructure (AWS Provider 6.0+)

Terraform модуль для управления EC2 инстансами в **любых** AWS регионах.

## 🎉 Новое в AWS Provider 6.0

Использует новую возможность AWS Provider 6.0 - атрибут `region` на уровне ресурсов!

**Преимущества:**
- ✅ **Один провайдер** вместо десятков с алиасами
- ✅ **Динамические регионы** - добавляйте любые регионы без изменения кода
- ✅ **Меньше памяти** - один instance провайдера
- ✅ **Проще импорт** - новый синтаксис `ID@регион`
- ✅ **Чище код** - используем `for_each` для модулей

## Структура проекта

```
.
├── modules/
│   ├── ec2/              # Модуль создания EC2
│   │   ├── main.tf       # Все ресурсы с region атрибутом
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   └── quota-check/      # Модуль проверки квот
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── versions.tf
├── main.tf               # Один provider + for_each модулей
├── variables.tf
├── outputs.tf
├── import.tf
├── terraform.tfvars.example
└── README.md
```

## Требования

⚠️ **Обязательно:**
- **AWS Provider >= 6.0.0**
- Terraform >= 1.0

## Конфигурация регионов

Просто добавьте любой регион в `terraform.tfvars`:

```hcl
regions = {
  "us-east-1" = {
    instance_count = 2
  }
  "eu-west-1" = {
    instance_count = 3
  }
  "ap-southeast-1" = {
    instance_count = 1
  }
  "eu-central-1" = {
    instance_count = 2
  }
  # Добавляйте любые AWS регионы!
  # Больше НЕ НУЖНО менять код!
}
```

**Никаких изменений в коде не требуется!** Provider 6.0 автоматически обработает любой регион.

## Быстрый старт

### 1. Установка правильной версии провайдера

Убедитесь что используете AWS Provider >= 6.0:

```bash
terraform version
# Terraform должен показать aws provider >= 6.0.0
```

### 2. Проверка квот

```bash
terraform init
terraform apply -target=module.quota_check
terraform output quota_check_results
```

### 3. Создание инстансов

```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars

terraform plan
terraform apply
```

## Импорт существующих инстансов

### Новый синтаксис в Provider 6.0: `ID@регион`

**Способ 1: CLI команда**

```bash
# Новый синтаксис с @регион
terraform import 'module.ec2["us-east-1"].aws_instance.main[0]' i-1234567890abcdef0@us-east-1

terraform import 'module.ec2["eu-west-1"].aws_instance.main[0]' i-aabbccdd11223344@eu-west-1
```

**Способ 2: Import блоки (Terraform 1.5+)**

```hcl
import {
  to = module.ec2["us-east-1"].aws_instance.main[0]
  id = "i-1234567890abcdef0@us-east-1"  # Указываем регион после @
}
```

### Пример: импорт нескольких инстансов

```bash
# Есть 3 ручных инстанса в us-east-1
terraform import 'module.ec2["us-east-1"].aws_instance.main[0]' i-111111@us-east-1
terraform import 'module.ec2["us-east-1"].aws_instance.main[1]' i-222222@us-east-1
terraform import 'module.ec2["us-east-1"].aws_instance.main[2]' i-333333@us-east-1

# В terraform.tfvars указываем 5 инстансов
regions = {
  "us-east-1" = {
    instance_count = 5  # 3 импортированных + 2 новых
  }
}

terraform apply  # Создаст еще 2
```

## Основной файл конфигурации

`main.tf` теперь **очень простой**:

```hcl
# Один провайдер!
provider "aws" {
  region = var.default_region
}

# Модули с for_each - работают для ЛЮБЫХ регионов
module "ec2" {
  source   = "./modules/ec2"
  for_each = var.regions

  region        = each.key          # Магия Provider 6.0!
  instance_count = each.value.instance_count
  # ...
}
```

Весь секрет в том, что каждый ресурс внутри модуля имеет атрибут `region`:

```hcl
# modules/ec2/main.tf
resource "aws_instance" "main" {
  region        = var.region  # Provider 6.0 автоматически использует нужный регион!
  instance_type = var.instance_type
  # ...
}
```

## Переменные

| Переменная | Описание | По умолчанию | Обязательно |
|-----------|----------|--------------|-------------|
| `project_name` | Имя проекта | `my-project` | Нет |
| `default_region` | Default регион провайдера | `us-east-1` | Нет |
| `regions` | Map регионов и количества | - | Да |
| `instance_type` | Тип инстанса | `t3.micro` | Нет |
| `key_pair_name` | Имя SSH ключа | - | Да |

## Outputs

```bash
# Квоты по всем регионам
terraform output quota_check_results

# Инстансы по регионам
terraform output instances_by_region

# SSH команды
terraform output ssh_commands

# Все ID инстансов
terraform output all_instance_ids
```

## Управление State

```bash
# Просмотр всех ресурсов
terraform state list

# Детали инстанса
terraform state show 'module.ec2["us-east-1"].aws_instance.main[0]'

# Удалить из state (оставить в AWS)
terraform state rm 'module.ec2["us-east-1"].aws_instance.main[0]'
```

## Миграция с Provider 5.x

Если у вас был код с множественными providers:

**Было:**
```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}

module "ec2_us" {
  providers = { aws = aws.us_east_1 }
  # ...
}
```

**Стало:**
```hcl
provider "aws" {
  region = "us-east-1"
}

module "ec2" {
  for_each = var.regions
  region   = each.key  # Просто!
  # ...
}
```

### Шаги миграции:

1. Обновите provider до 6.0:
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0"
    }
  }
}
```

2. Выполните `terraform init -upgrade`

3. При первом `terraform plan` после апгрейда, Terraform покажет изменения для добавления атрибута `region` ко всем ресурсам. Это нормально!

## Troubleshooting

### Provider version < 6.0

```
Error: Invalid attribute
attribute "region" is not expected here
```

**Решение:** Обновите провайдер:
```bash
terraform init -upgrade
```

### "Quota exceeded"

```bash
terraform output quota_check_results
# Запросите увеличение в AWS Console:
# Service Quotas -> EC2 -> Running On-Demand Standard instances
```

## Преимущества нового подхода

**Provider 5.x (старый):**
- ❌ Нужен отдельный provider для каждого региона
- ❌ Нужен отдельный модуль для каждого региона
- ❌ Большое потребление памяти
- ❌ Сложный код с множеством алиасов
- ❌ Нельзя использовать for_each с providers

**Provider 6.0 (новый):**
- ✅ Один provider для всех регионов
- ✅ Один модуль с for_each для всех регионов
- ✅ Меньшее потребление памяти
- ✅ Простой и читаемый код
- ✅ Динамическое добавление регионов

## Security

⚠️ **ВАЖНО:**
- Не коммитьте `terraform.tfvars` с приватными ключами
- Используйте remote state с шифрованием
- Ограничьте SSH доступ (0.0.0.0/0
