###############################################################################
# modules/ec2/main.tf - Модуль создания EC2 инстансов
###############################################################################

data "aws_region" "current" {}

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
  default     = "ec2-security-group"
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

output "instances" {
  description = "Полная информация об инстансах"
  value       = aws_instance.main
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

output "region" {
  description = "Регион"
  value       = var.region
}

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
# main.tf - Основная конфигурация проекта
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

# Основной провайдер
provider "aws" {
  region = var.primary_region
}

# Дополнительные провайдеры для multi-region
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}

# Проверка квот перед созданием инстансов
module "quota_check" {
  source   = "./modules/quota-check"
  for_each = toset(var.regions_to_check)

  providers = {
    aws = aws
  }

  region             = each.value
  instance_type      = var.instance_type
  required_instances = var.instances_per_region[each.value]
}

# Создание EC2 инстансов в primary регионе
module "ec2_primary" {
  source = "./modules/ec2"

  instance_type        = var.instance_type
  instance_count       = var.primary_instance_count
  instance_name_prefix = "${var.project_name}-primary"
  security_group_name  = "${var.project_name}-sg-primary"
  ami_name             = var.ami_name
  key_pair_name        = var.key_pair_name
  create_key_pair      = var.create_key_pair
  public_key           = var.public_key

  tags = merge(
    var.common_tags,
    {
      Region = var.primary_region
    }
  )
}

# Опционально: создание в secondary регионе
module "ec2_secondary" {
  count  = var.enable_secondary_region ? 1 : 0
  source = "./modules/ec2"

  providers = {
    aws = aws.secondary
  }

  instance_type        = var.instance_type
  instance_count       = var.secondary_instance_count
  instance_name_prefix = "${var.project_name}-secondary"
  security_group_name  = "${var.project_name}-sg-secondary"
  ami_name             = var.ami_name
  key_pair_name        = var.key_pair_name
  create_key_pair      = var.create_key_pair
  public_key           = var.public_key

  tags = merge(
    var.common_tags,
    {
      Region = var.secondary_region
    }
  )
}

# Data source для получения существующих инстансов (не управляемых Terraform)
data "aws_instances" "existing" {
  filter {
    name   = "tag:ManagedBy"
    values = ["manual"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

###############################################################################
# variables.tf - Переменные проекта
###############################################################################

variable "project_name" {
  description = "Имя проекта (используется в именах ресурсов)"
  type        = string
  default     = "my-project"
}

variable "primary_region" {
  description = "Основной AWS регион"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Дополнительный AWS регион"
  type        = string
  default     = "eu-west-1"
}

variable "enable_secondary_region" {
  description = "Создавать ли инстансы во втором регионе"
  type        = bool
  default     = false
}

variable "regions_to_check" {
  description = "Список регионов для проверки квот"
  type        = list(string)
  default     = ["us-east-1", "eu-west-1"]
}

variable "instances_per_region" {
  description = "Количество инстансов для каждого региона"
  type        = map(number)
  default = {
    "us-east-1" = 2
    "eu-west-1" = 1
  }
}

variable "instance_type" {
  description = "Тип EC2 инстанса"
  type        = string
  default     = "t3.micro"
}

variable "primary_instance_count" {
  description = "Количество инстансов в primary регионе"
  type        = number
  default     = 1
}

variable "secondary_instance_count" {
  description = "Количество инстансов в secondary регионе"
  type        = number
  default     = 1
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
    Project   = "ec2-infrastructure"
  }
}

###############################################################################
# outputs.tf - Выходные данные проекта
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

output "primary_instances" {
  description = "Инстансы в primary регионе"
  value = {
    region      = var.primary_region
    instance_ids = module.ec2_primary.instance_ids
    public_ips  = module.ec2_primary.instance_public_ips
    private_ips = module.ec2_primary.instance_private_ips
  }
}

output "secondary_instances" {
  description = "Инстансы в secondary регионе"
  value = var.enable_secondary_region ? {
    region      = var.secondary_region
    instance_ids = module.ec2_secondary[0].instance_ids
    public_ips  = module.ec2_secondary[0].instance_public_ips
    private_ips = module.ec2_secondary[0].instance_private_ips
  } : null
}

output "all_managed_instances" {
  description = "Все инстансы управляемые Terraform"
  value = concat(
    [for i in module.ec2_primary.instance_ids : {
      id     = i
      region = var.primary_region
    }],
    var.enable_secondary_region ? [
      for i in module.ec2_secondary[0].instance_ids : {
        id     = i
        region = var.secondary_region
      }
    ] : []
  )
}

output "existing_manual_instances" {
  description = "Существующие инстансы созданные вручную (по тегу ManagedBy=manual)"
  value       = data.aws_instances.existing.ids
}

output "ssh_commands" {
  description = "Команды для SSH подключения"
  value = {
    primary = [
      for ip in module.ec2_primary.instance_public_ips :
      "ssh -i ~/.ssh/${var.key_pair_name} ubuntu@${ip}"
    ]
    secondary = var.enable_secondary_region ? [
      for ip in module.ec2_secondary[0].instance_public_ips :
      "ssh -i ~/.ssh/${var.key_pair_name} ubuntu@${ip}"
    ] : []
  }
}

###############################################################################
# terraform.tfvars.example - Пример конфигурации
###############################################################################

# Скопируйте в terraform.tfvars и заполните своими значениями

project_name = "my-infrastructure"

# Регионы
primary_region   = "us-east-1"
secondary_region = "eu-west-1"
enable_secondary_region = false

# Проверка квот
regions_to_check = ["us-east-1", "eu-west-1", "ap-southeast-1"]
instances_per_region = {
  "us-east-1"      = 3
  "eu-west-1"      = 2
  "ap-southeast-1" = 1
}

# Инстансы
instance_type           = "t3.micro"
primary_instance_count   = 2
secondary_instance_count = 1

# AMI
ami_name = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"

# SSH Key
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
# import.tf - Импорт существующих ресурсов
###############################################################################

# Импорт существующих EC2 инстансов
# 
# Чтобы добавить существующий инстанс в state:
# 1. Создайте resource block для него (закомментированный)
# 2. Запустите: terraform import 'aws_instance.manual_instance["instance-1"]' i-1234567890abcdef0
# 3. Раскомментируйте resource block

# resource "aws_instance" "manual_instance" {
#   for_each = {
#     "instance-1" = "i-1234567890abcdef0"
#     "instance-2" = "i-0987654321fedcba0"
#   }
#   
#   # После импорта Terraform автоматически заполнит эти поля из state
#   # Но для начала можно оставить минимальную конфигурацию
# }

# Альтернатива: import блоки (Terraform 1.5+)
# import {
#   to = aws_instance.manual_instance["instance-1"]
#   id = "i-1234567890abcdef0"
# }

###############################################################################
# README.md - Документация проекта
###############################################################################

# AWS EC2 Infrastructure Terraform Module

Модульная инфраструктура для управления EC2 инстансами в AWS.

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
│       └── outputs.tf
├── main.tf               # Основная конфигурация
├── variables.tf          # Переменные проекта
├── outputs.tf            # Выходы проекта
├── import.tf             # Импорт существующих ресурсов
├── terraform.tfvars.example
└── README.md
```

## Быстрый старт

### 1. Проверка квот

Перед созданием инстансов проверьте доступные квоты:

```bash
# Инициализация
terraform init

# Проверка квот (без создания ресурсов)
terraform plan -target=module.quota_check

# Просмотр результатов
terraform apply -target=module.quota_check
terraform output quota_check_results
```

Вывод покажет для каждого региона:
- Лимит квоты (vCPU)
- Текущее использование
- Доступные ресурсы
- Возможность создания запрошенных инстансов

### 2. Создание инстансов

```bash
# Создайте конфигурацию
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars

# Примените конфигурацию
terraform plan
terraform apply
```

### 3. Импорт существующих инстансов

Если у вас есть инстансы созданные вручную, их можно добавить в Terraform state:

#### Способ 1: Terraform import (для Terraform < 1.5)

```bash
# Импортируйте инстанс
terraform import 'module.ec2_primary.aws_instance.main[0]' i-1234567890abcdef0

# Terraform автоматически добавит его в state
# Затем обновите код, чтобы он соответствовал существующей конфигурации
```

#### Способ 2: Import блоки (Terraform 1.5+)

Добавьте в конфигурацию:

```hcl
import {
  to = module.ec2_primary.aws_instance.main[2]
  id = "i-1234567890abcdef0"
}
```

Затем выполните:

```bash
terraform plan  # Покажет что будет импортировано
terraform apply # Импортирует инстанс в state
```

#### Способ 3: Чтение без управления (data source)

Если не хотите управлять инстансом через Terraform, но нужна информация:

```hcl
data "aws_instance" "manual" {
  instance_id = "i-1234567890abcdef0"
}

output "manual_instance_ip" {
  value = data.aws_instance.manual.public_ip
}
```

## Работа с State

### Что хранится в State?

State содержит информацию о всех ресурсах управляемых Terraform:
- EC2 инстансы созданные через terraform
- Security Groups
- Key Pairs
- Импортированные ресурсы

### Просмотр State

```bash
# Список всех ресурсов
terraform state list

# Детали конкретного ресурса
terraform state show 'module.ec2_primary.aws_instance.main[0]'

# Все EC2 инстансы
terraform state list | grep aws_instance
```

### Удаление ресурса из State (без удаления в AWS)

```bash
# Убрать из управления Terraform, но оставить в AWS
terraform state rm 'module.ec2_primary.aws_instance.main[1]'
```

### Remote State (рекомендуется для команд)

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "ec2-infrastructure/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

## Использование модулей отдельно

### Модуль EC2

```hcl
module "my_servers" {
  source = "./modules/ec2"

  instance_type        = "t3.micro"
  instance_count       = 3
  instance_name_prefix = "web-server"
  security_group_name  = "web-sg"
  key_pair_name        = "my-key"
  create_key_pair      = false
}
```

### Модуль проверки квот

```hcl
module "quota_us_east" {
  source = "./modules/quota-check"

  region             = "us-east-1"
  instance_type      = "t3.micro"
  required_instances = 5
}

output "can_create" {
  value = module.quota_us_east.can_create
}
```

## Переменные

| Переменная | Описание | По умолчанию |
|-----------|----------|--------------|
| `project_name` | Имя проекта | `my-project` |
| `primary_region` | Основной регион | `us-east-1` |
| `instance_type` | Тип инстанса | `t3.micro` |
| `primary_instance_count` | Количество инстансов | `1` |
| `key_pair_name` | Имя SSH key | - (обязательно) |
| `create_key_pair` | Создать новый key | `false` |

Полный список см. в `variables.tf`

## Выходные данные

```bash
# Все выходы
terraform output

# Конкретный вывод
terraform output primary_instances
terraform output ssh_commands
terraform output quota_check_results
```

## Multi-region deployment

```hcl
# terraform.tfvars
enable_secondary_region = true
secondary_region        = "eu-west-1"
secondary_instance_count = 2
```

## Теги для организации ресурсов

Все ресурсы созданные через Terraform имеют тег `ManagedBy = "terraform"`.

Для ручных инстансов рекомендуется использовать `ManagedBy = "manual"` - 
тогда они будут автоматически находиться через data source.

```bash
# Применить тег к существующему инстансу
aws ec2 create-tags \
  --resources i-1234567890abcdef0 \
  --tags Key=ManagedBy,Value=manual
```

## Troubleshooting

### Quota exceeded

```bash
# Проверьте квоты
terraform apply -target=module.quota_check
terraform output quota_check_results

# Запросите увеличение квоты в AWS Console:
# Service Quotas -> EC2 -> Running On-Demand Standard instances
```

### Import не работает

```bash
# Убедитесь что ресурс существует
aws ec2 describe-instances --instance-ids i-1234567890abcdef0

# Проверьте правильность пути в state
terraform state list
```

## Требования

- Terraform >= 1.0
- AWS CLI настроен с credentials
- AWS Provider ~> 5.0
- Достаточные права IAM для создания EC2, SG, Key Pairs

## Security

⚠️ **ВАЖНО:**
- Не коммитьте `terraform.tfvars` с приватными ключами
- Используйте `.gitignore` для чувствительных файлов
- Храните state в защищенном S3 bucket с шифрованием
- Ограничьте SSH доступ (0.0.0.0/0 только для примера!)

## Лицензия

MIT
