###############################################################################
# modules/ec2/main.tf - Модуль создания EC2 инстансов
###############################################################################

data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "selected" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

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
  vpc_id      = data.aws_vpc.default.id

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
}

resource "aws_security_group_rule" "ingress_wireguard" {
  type              = "ingress"
  from_port         = 51820
  to_port           = 51820
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.main.id
  description       = "Allow WireGuard UDP traffic"
}

resource "aws_security_group_rule" "ingress_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.main.id
  description       = "Allow SSH traffic"
}

resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.main.id
  description       = "Allow all outbound traffic"
}

resource "aws_key_pair" "main" {
  count      = var.create_key_pair ? 1 : 0
  key_name   = var.key_pair_name
  public_key = var.public_key

  tags = merge(
    var.tags,
    {
      Name = var.key_pair_name
    }
  )
}

resource "aws_instance" "main" {
  count                  = var.instance_count
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.selected[0].id
  instance_type          = var.instance_type
  key_name               = var.create_key_pair ? aws_key_pair.main[0].key_name : var.key_pair_name
  vpc_security_group_ids = [aws_security_group.main.id]
  
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
      version = "~> 5.0"
    }
  }
}

###############################################################################
# modules/quota-check/main.tf - Модуль проверки квот
###############################################################################

data "aws_servicequotas_service_quota" "ec2_standard" {
  service_code = "ec2"
  quota_code   = "L-1216C47A"
}

data "aws_ec2_instance_type" "selected" {
  instance_type = var.instance_type
}

data "aws_instances" "running_standard" {
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
      version = "~> 5.0"
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
      version = "~> 5.0"
    }
  }
}

# Проверка квот в us-east-1
module "quota_check_us_east_1" {
  source = "./modules/quota-check"
  count  = contains(keys(var.regions), "us-east-1") ? 1 : 0

  providers = {
    aws = aws.us_east_1
  }

  instance_type      = var.instance_type
  required_instances = try(var.regions["us-east-1"].instance_count, 0)
}

# Проверка квот в eu-west-1
module "quota_check_eu_west_1" {
  source = "./modules/quota-check"
  count  = contains(keys(var.regions), "eu-west-1") ? 1 : 0

  providers = {
    aws = aws.eu_west_1
  }

  instance_type      = var.instance_type
  required_instances = try(var.regions["eu-west-1"].instance_count, 0)
}

# Проверка квот в ap-southeast-1
module "quota_check_ap_southeast_1" {
  source = "./modules/quota-check"
  count  = contains(keys(var.regions), "ap-southeast-1") ? 1 : 0

  providers = {
    aws = aws.ap_southeast_1
  }

  instance_type      = var.instance_type
  required_instances = try(var.regions["ap-southeast-1"].instance_count, 0)
}

# EC2 инстансы в us-east-1
module "ec2_us_east_1" {
  source = "./modules/ec2"
  count  = contains(keys(var.regions), "us-east-1") ? 1 : 0

  providers = {
    aws = aws.us_east_1
  }

  instance_type        = var.instance_type
  instance_count       = var.regions["us-east-1"].instance_count
  instance_name_prefix = "${var.project_name}-us-east-1"
  security_group_name  = "${var.project_name}-sg-us-east-1"
  ami_name             = var.ami_name
  key_pair_name        = var.key_pair_name
  create_key_pair      = var.create_key_pair
  public_key           = var.public_key

  tags = merge(
    var.common_tags,
    {
      Region = "us-east-1"
    }
  )
}

# EC2 инстансы в eu-west-1
module "ec2_eu_west_1" {
  source = "./modules/ec2"
  count  = contains(keys(var.regions), "eu-west-1") ? 1 : 0

  providers = {
    aws = aws.eu_west_1
  }

  instance_type        = var.instance_type
  instance_count       = var.regions["eu-west-1"].instance_count
  instance_name_prefix = "${var.project_name}-eu-west-1"
  security_group_name  = "${var.project_name}-sg-eu-west-1"
  ami_name             = var.ami_name
  key_pair_name        = var.key_pair_name
  create_key_pair      = var.create_key_pair
  public_key           = var.public_key

  tags = merge(
    var.common_tags,
    {
      Region = "eu-west-1"
    }
  )
}

# EC2 инстансы в ap-southeast-1
module "ec2_ap_southeast_1" {
  source = "./modules/ec2"
  count  = contains(keys(var.regions), "ap-southeast-1") ? 1 : 0

  providers = {
    aws = aws.ap_southeast_1
  }

  instance_type        = var.instance_type
  instance_count       = var.regions["ap-southeast-1"].instance_count
  instance_name_prefix = "${var.project_name}-ap-southeast-1"
  security_group_name  = "${var.project_name}-sg-ap-southeast-1"
  ami_name             = var.ami_name
  key_pair_name        = var.key_pair_name
  create_key_pair      = var.create_key_pair
  public_key           = var.public_key

  tags = merge(
    var.common_tags,
    {
      Region = "ap-southeast-1"
    }
  )
}

# Создаем провайдеры для каждого региона
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}

provider "aws" {
  alias  = "ap_southeast_1"
  region = "ap-southeast-1"
}

# Добавьте другие регионы по необходимости здесь

###############################################################################
# variables.tf
###############################################################################

variable "project_name" {
  description = "Имя проекта (используется в именах ресурсов)"
  type        = string
  default     = "my-project"
}

variable "regions" {
  description = "Конфигурация регионов и количества инстансов"
  type = map(object({
    provider_alias  = string
    instance_count  = number
  }))
  
  # Пример:
  # regions = {
  #   "us-east-1" = {
  #     provider_alias = "us_east_1"
  #     instance_count = 2
  #   }
  #   "eu-west-1" = {
  #     provider_alias = "eu_west_1"
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

# Конфигурация регионов
# ВАЖНО: provider_alias должен соответствовать alias в main.tf
regions = {
  "us-east-1" = {
    provider_alias = "us_east_1"
    instance_count = 2
  }
  "eu-west-1" = {
    provider_alias = "eu_west_1"
    instance_count = 3
  }
  "ap-southeast-1" = {
    provider_alias = "ap_southeast_1"
    instance_count = 1
  }
}

# Настройки инстансов
instance_type = "t3.micro"
ami_name      = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"

# SSH ключ
key_pair_name   = "my-keypair"
create_key_pair = true
# public_key    = "ssh-rsa AAAA..."  # Раскомментируйте и добавьте ваш ключ

# Теги
common_tags = {
  Environment = "production"
  ManagedBy   = "terraform"
  Project     = "infrastructure"
}

###############################################################################
# import.tf - Импорт существующих инстансов
###############################################################################

# Импорт существующих инстансов в state
#
# ДА, достаточно только ID инстанса!
# Terraform автоматически получит всю остальную информацию из AWS API
#
# Способ 1: Команда terraform import
# terraform import 'module.ec2["us-east-1"].aws_instance.main[0]' i-1234567890abcdef0
# terraform import 'module.ec2["us-east-1"].aws_instance.main[1]' i-0987654321fedcba0
#
# Способ 2: Import блоки (Terraform 1.5+)
# Раскомментируйте нужные блоки ниже:

# import {
#   to = module.ec2["us-east-1"].aws_instance.main[0]
#   id = "i-1234567890abcdef0"
# }

# import {
#   to = module.ec2["us-east-1"].aws_instance.main[1]
#   id = "i-0987654321fedcba0"
# }

# import {
#   to = module.ec2["eu-west-1"].aws_instance.main[0]
#   id = "i-aabbccdd11223344"
# }

# После импорта:
# 1. Terraform получит все параметры инстанса из AWS
# 2. При следующем apply Terraform может попытаться изменить инстанс, 
#    чтобы привести его к конфигурации в коде
# 3. Проверьте plan перед apply!

###############################################################################
# README.md
###############################################################################

# AWS EC2 Multi-Region Infrastructure

Terraform модуль для управления EC2 инстансами в нескольких AWS регионах.

## Структура проекта

```
.
├── modules/
│   ├── ec2/              # Модуль создания EC2 инстансов
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── versions.tf
│   └── quota-check/      # Модуль проверки квот
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── versions.tf
├── main.tf               # Основная конфигурация
├── variables.tf          # Переменные
├── outputs.tf            # Выходы
├── import.tf             # Импорт существующих ресурсов
├── terraform.tfvars.example
└── README.md
```

## Конфигурация регионов

Просто укажите в `terraform.tfvars` какие регионы и сколько инстансов:

```hcl
regions = {
  "us-east-1" = {
    provider_alias = "us_east_1"
    instance_count = 2
  }
  "eu-west-1" = {
    provider_alias = "eu_west_1"
    instance_count = 3
  }
  "ap-southeast-1" = {
    provider_alias = "ap_southeast_1"
    instance_count = 1
  }
}
```

**Важно:** Если добавляете новый регион, создайте для него provider в `main.tf`:

```hcl
provider "aws" {
  alias  = "eu_central_1"
  region = "eu-central-1"
}
```

## Быстрый старт

### 1. Проверка квот

```bash
terraform init

# Проверка квот без создания
terraform plan -target=module.quota_check

# Просмотр результатов
terraform apply -target=module.quota_check
terraform output quota_check_results
```

Вывод покажет для каждого региона:
```
{
  "us-east-1" = {
    available     = 45
    can_create    = true
    current_usage = 10
    quota_limit   = 55
    required_vcpu = 4
  }
  ...
}
```

### 2. Создание инстансов

```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Отредактируйте конфигурацию

terraform plan
terraform apply
```

### 3. Вывод информации

```bash
# Все инстансы по регионам
terraform output instances_by_region

# SSH команды
terraform output ssh_commands

# Все ID инстансов
terraform output all_instance_ids
```

## Импорт существующих инстансов

### Вопрос: Достаточно ли только ID инстанса для импорта?

**Ответ: ДА!** Terraform автоматически получит всю информацию через AWS API.

### Как импортировать

**Способ 1: Команда terraform import**

```bash
# Импортируем существующий инстанс в us-east-1
terraform import 'module.ec2["us-east-1"].aws_instance.main[0]' i-1234567890abcdef0

# Импортируем второй инстанс в us-east-1
terraform import 'module.ec2["us-east-1"].aws_instance.main[1]' i-0987654321fedcba0

# Импортируем инстанс в eu-west-1
terraform import 'module.ec2["eu-west-1"].aws_instance.main[0]' i-aabbccdd11223344
```

Что происходит:
1. Terraform запрашивает информацию об инстансе из AWS API
2. Получает все параметры (AMI, type, security groups, tags и т.д.)
3. Сохраняет в state
4. При следующем `plan` покажет, какие изменения нужны, чтобы привести инстанс к конфигурации в коде

**Способ 2: Import блоки (Terraform 1.5+)**

Добавьте в `import.tf`:

```hcl
import {
  to = module.ec2["us-east-1"].aws_instance.main[0]
  id = "i-1234567890abcdef0"
}

import {
  to = module.ec2["us-east-1"].aws_instance.main[1]
  id = "i-0987654321fedcba0"
}
```

Затем:
```bash
terraform plan   # Покажет что будет импортировано
terraform apply  # Импортирует в state
```

### Важно после импорта

После импорта **обязательно** проверьте plan:

```bash
terraform plan
```

Terraform может показать, что хочет изменить инстанс. Это происходит если:
- Теги отличаются от конфигурации
- Security group другой
- AMI или instance type отличаются

**Варианты действий:**

1. **Привести инстанс к конфигурации** - `terraform apply` изменит инстанс
2. **Изменить конфигурацию** - отредактируйте код под существующий инстанс
3. **Удалить из state** - `terraform state rm ...` если не хотите управлять

### Пример импорта

```bash
# Есть 3 ручных инстанса в us-east-1
# Хотим добавить их в Terraform и создать еще 2

# 1. Импортируем существующие
terraform import 'module.ec2["us-east-1"].aws_instance.main[0]' i-111111
terraform import 'module.ec2["us-east-1"].aws_instance.main[1]' i-222222
terraform import 'module.ec2["us-east-1"].aws_instance.main[2]' i-333333

# 2. В terraform.tfvars указываем 5 инстансов
regions = {
  "us-east-1" = {
    provider_alias = "us_east_1"
    instance_count = 5  # 3 импортированных + 2 новых
  }
}

# 3. Применяем - Terraform создаст еще 2 инстанса
terraform plan   # Покажет: 2 to add
terraform apply
```

## Управление State

### Просмотр state

```bash
# Все ресурсы
terraform state list

# Только EC2 инстансы
terraform state list | grep aws_instance

# Детали конкретного инстанса
terraform state show 'module.ec2["us-east-1"].aws_instance.main[0]'
```

### Удаление из state (без удаления в AWS)

```bash
# Убрать инстанс из управления Terraform
terraform state rm 'module.ec2["us-east-1"].aws_instance.main[1]'

# Инстанс останется в AWS, но Terraform больше не будет его управлять
```

### Remote State (для команд)

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "ec2/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

## Добавление нового региона

```hcl
# 1. В main.tf добавьте provider
provider "aws" {
  alias  = "ap_northeast_1"
  region = "ap-northeast-1"
}

# 2. В terraform.tfvars добавьте регион
regions = {
  # ... существующие регионы ...
  "ap-northeast-1" = {
    provider_alias = "ap_northeast_1"
    instance_count = 2
  }
}

# 3. Примените
terraform apply
```

## Переменные

| Переменная | Описание | Обязательно |
|-----------|----------|-------------|
| `project_name` | Имя проекта | Нет |
| `regions` | Map регионов и количества инстансов | Да |
| `instance_type` | Тип инстанса (default: t3.micro) | Нет |
| `ami_name` | Имя AMI для поиска | Нет |
| `key_pair_name` | Имя SSH ключа | Да |
| `create_key_pair` | Создать новый ключ? | Нет |
| `public_key` | Публичный SSH ключ | Если create_key_pair=true |

## Outputs

```bash
# Проверка квот
terraform output quota_check_results

# Инстансы по регионам
terraform output instances_by_region

# SSH команды
terraform output ssh_commands

# Все ID инстансов (плоский список)
terraform output all_instance_ids
```

## Troubleshooting

### "Quota exceeded"

```bash
# Проверьте квоты
terraform output quota_check_results

# Если недостаточно - запросите увеличение в AWS Console:
# Service Quotas -> EC2 -> Running On-Demand Standard instances
```

### "Provider not found"

Убедитесь что:
1. В `main.tf` есть provider с нужным alias
2. В `regions` указан правильный `provider_alias`

### После импорта Terraform хочет всё изменить

```bash
# Посмотрите что именно
terraform plan

# Вариант 1: Измените код под существующую конфигурацию
# Вариант 2: Примените изменения (осторожно!)
# Вариант 3: Удалите из state если не хотите управлять
terraform state rm 'module.ec2["us-east-1"].aws_instance.main[0]'
```

## Требования

- Terraform >= 1.0
- AWS CLI с настроенными credentials
- AWS Provider ~> 5.0

## Security

⚠️ **ВАЖНО:**
- Не коммитьте `terraform.tfvars` с приватными ключами
- Добавьте в `.gitignore`: `*.tfvars`, `*.tfstate*`
- Используйте remote state с шифрованием
- Ограничьте SSH доступ (0.0.0.0/0 только для примера!)

## Лицензия

MIT
