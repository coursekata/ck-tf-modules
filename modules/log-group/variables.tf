variable "name" {
  description = "The `name` slot. Defaults to the module's opinionated name; override per group."
  type        = string
  default     = "log-group"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.name))
    error_message = "name must be lowercase alphanumerics with internal hyphens only (no leading/trailing hyphen)."
  }
}

variable "name_prefix" {
  description = <<-EOT
    Optional prefix prepended to the rendered name. Use for the AWS-mandated source prefixes
    ("/aws/lambda/", "/aws/ecs/") or a convention prefix ("/aws/cloudtrail/"). "" leaves the bare
    rendered id. Include the trailing slash. The classification still comes from the slots.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]*$", var.name_prefix))
    error_message = "name_prefix may contain only the characters CloudWatch log-group names allow (a-z A-Z 0-9 _ . / # -)."
  }
}

variable "retention_in_days" {
  description = "Log retention. No default — each caller chooses deliberately. Must be a CloudWatch-supported value."
  type        = number

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.retention_in_days)
    error_message = "retention_in_days must be one of the CloudWatch-supported retention values (1,3,5,7,14,30,60,90,120,150,180,365,400,545,731,1827,3653)."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN to encrypt the log group with a customer CMK. null (default) uses AWS-managed encryption. The key's policy must grant logs.<region>.amazonaws.com — set that on the caller side."
  type        = string
  default     = null
}
