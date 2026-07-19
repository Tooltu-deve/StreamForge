locals {
  gsi1_name = "GSI1"
}

resource "aws_dynamodb_table" "this" {
  name         = "${var.name_prefix}-metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  # Only key attributes are declared (table keys + GSI keys). All other
  # item fields (title, status, uploaded_at, ...) are schemaless.
  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  attribute {
    name = "GSI1PK"
    type = "S"
  }

  attribute {
    name = "GSI1SK"
    type = "S"
  }

  global_secondary_index {
    name = local.gsi1_name
    key_schema {
      attribute_name = "GSI1PK"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "GSI1SK"
      key_type       = "RANGE"
    }
    projection_type = "ALL"
  }

  # Ephemeral dev table: PITR intentionally disabled to avoid cost.
  point_in_time_recovery {
    enabled = false
  }

  tags = {
    "Name" = "${var.name_prefix}-metadata"
  }
}
