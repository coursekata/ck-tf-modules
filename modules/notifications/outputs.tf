output "sns_topic_arn" {
  description = "The notification SNS topic ARN. Add a source by targeting this ARN (a CloudWatch alarm action, an EventBridge target, a CodeStar-notifications rule) — one topic, one Chatbot binding."
  value       = aws_sns_topic.this.arn
}

output "sns_topic_name" {
  description = "The SNS topic name (the rendered id)."
  value       = aws_sns_topic.this.name
}

output "chatbot_role_arn" {
  description = "ARN of the read-only-guardrailed AWS Chatbot channel role."
  value       = aws_iam_role.chatbot.arn
}

output "slack_channel_configuration_arn" {
  description = "The AWS Chatbot Slack channel configuration ARN."
  value       = aws_chatbot_slack_channel_configuration.this.chat_configuration_arn
}
