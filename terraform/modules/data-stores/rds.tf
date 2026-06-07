# RDS Postgres — loan/item state. Encrypted at rest (KMS), private-only, with
# a master password that RDS manages + rotates in Secrets Manager (compliance:
# secret rotation). Multi-AZ + PITR in prod satisfy RPO 1h / RTO 30m.

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Postgres 5432 from EKS nodes only"
  vpc_id      = var.vpc_id
  tags        = var.tags

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "db_ingress" {
  # Key by index, not by the SG id itself: the EKS node SG is created in the
  # same apply, so its id is unknown at plan time and can't be a for_each key.
  # The list length (statically known) is all Terraform needs up front.
  for_each                 = { for idx, sg in var.db_allowed_security_group_ids : idx => sg }
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = each.value
  description              = "Postgres from EKS nodes"
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-pg"
  engine         = "postgres"
  engine_version = var.db.engine_version
  instance_class = var.db.instance_class

  allocated_storage     = var.db.allocated_storage
  max_allocated_storage = var.db.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.data.arn

  db_name  = "saaf"
  username = "saaf_app"
  # RDS manages + rotates the master password as a Secrets Manager secret.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.data.key_id

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  multi_az               = var.db.multi_az
  publicly_accessible    = false

  # Durability — PITR via automated backups (RPO 1h is comfortably met).
  backup_retention_period = var.db.backup_retention_days
  backup_window           = "07:00-08:00"
  maintenance_window      = "sun:08:30-sun:09:30"
  copy_tags_to_snapshot   = true
  deletion_protection     = var.db.deletion_protection

  # Encrypted Performance Insights + enhanced logging.
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.data.arn
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  auto_minor_version_upgrade      = true

  skip_final_snapshot       = var.force_destroy
  final_snapshot_identifier = var.force_destroy ? null : "${var.name}-pg-final"

  tags = var.tags
}
