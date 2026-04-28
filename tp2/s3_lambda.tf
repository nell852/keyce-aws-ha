###############################################################
# TP2 – S3 + Lambda (Traitement serverless)
###############################################################

###############################################################
# BUCKET S3 – Stockage des logs VPN / configs Pritunl
###############################################################
resource "aws_s3_bucket" "keyce_bucket" {
  bucket = "${var.project_name}-storage-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "${var.project_name}-bucket"
    Project = var.project_name
  }
}

# Blocage de l'accès public
resource "aws_s3_bucket_public_access_block" "bucket_block" {
  bucket = aws_s3_bucket.keyce_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning activé
resource "aws_s3_bucket_versioning" "bucket_versioning" {
  bucket = aws_s3_bucket.keyce_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Chiffrement SSE-S3
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket_sse" {
  bucket = aws_s3_bucket.keyce_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Politique de cycle de vie : archivage après 30 jours, suppression après 90
resource "aws_s3_bucket_lifecycle_configuration" "bucket_lifecycle" {
  bucket = aws_s3_bucket.keyce_bucket.id

  rule {
    id     = "logs-lifecycle"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }
  }
}

# Notification S3 → Lambda (déclenchement automatique)
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.keyce_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.log_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "logs/"
    filter_suffix       = ".log"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

###############################################################
# IAM ROLE pour Lambda
###############################################################
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = { Project = var.project_name }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "${var.project_name}-lambda-s3"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = "${aws_s3_bucket.keyce_bucket.arn}/*"
    }]
  })
}

###############################################################
# CODE LAMBDA – Traitement des logs Pritunl (Python)
###############################################################
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content  = <<-PYTHON
      import json
      import boto3
      import gzip
      import urllib.parse
      import os
      from datetime import datetime

      s3 = boto3.client('s3')

      def lambda_handler(event, context):
          """
          Traitement serverless des logs Pritunl VPN.
          Déclenché à chaque upload de fichier .log dans s3://bucket/logs/
          """
          print(f"Event reçu : {json.dumps(event)}")
          
          results = []
          
          for record in event.get('Records', []):
              bucket_name = record['s3']['bucket']['name']
              object_key  = urllib.parse.unquote_plus(record['s3']['object']['key'])
              
              print(f"Traitement de : s3://{bucket_name}/{object_key}")
              
              try:
                  # Lecture du fichier log
                  response = s3.get_object(Bucket=bucket_name, Key=object_key)
                  content  = response['Body'].read().decode('utf-8')
                  
                  # Analyse basique des logs VPN
                  stats = analyze_vpn_log(content)
                  
                  # Sauvegarde du résumé
                  summary_key = object_key.replace('logs/', 'summaries/').replace('.log', '-summary.json')
                  s3.put_object(
                      Bucket=bucket_name,
                      Key=summary_key,
                      Body=json.dumps(stats, indent=2),
                      ContentType='application/json'
                  )
                  
                  results.append({
                      'file': object_key,
                      'status': 'processed',
                      'stats': stats
                  })
                  
                  print(f"Résumé sauvegardé : {summary_key}")
                  
              except Exception as e:
                  print(f"Erreur lors du traitement de {object_key}: {str(e)}")
                  results.append({'file': object_key, 'status': 'error', 'error': str(e)})
          
          return {
              'statusCode': 200,
              'body': json.dumps({
                  'message': f'{len(results)} fichier(s) traité(s)',
                  'timestamp': datetime.utcnow().isoformat(),
                  'results': results
              })
          }

      def analyze_vpn_log(content):
          """Analyse simple des logs VPN Pritunl."""
          lines = content.splitlines()
          
          connections    = [l for l in lines if 'Connected' in l or 'connected' in l]
          disconnections = [l for l in lines if 'Disconnected' in l or 'disconnected' in l]
          errors         = [l for l in lines if 'ERROR' in l or 'error' in l]
          
          return {
              'total_lines'       : len(lines),
              'connections'       : len(connections),
              'disconnections'    : len(disconnections),
              'errors'            : len(errors),
              'processed_at'      : datetime.utcnow().isoformat()
          }
    PYTHON
    filename = "lambda_function.py"
  }
}

###############################################################
# FONCTION LAMBDA
###############################################################
resource "aws_lambda_function" "log_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-log-processor"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256

  # Déployée dans le VPC pour accès aux ressources privées
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      S3_BUCKET    = aws_s3_bucket.keyce_bucket.id
      PROJECT_NAME = var.project_name
      ENVIRONMENT  = "tp2"
    }
  }

  tags = {
    Name    = "${var.project_name}-lambda"
    Project = var.project_name
  }
}

# Permission pour que S3 puisse déclencher Lambda
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.keyce_bucket.arn
}

# CloudWatch Log Group pour Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.log_processor.function_name}"
  retention_in_days = 14

  tags = { Project = var.project_name }
}
