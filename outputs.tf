output "travel-website_public_ip" {
  description = "Public IP of the travel-website EC2 instance"
  value       = aws_instance.travel-website_instance.public_ip
}

output "Nagios_public_ip" {
  description = "Public IP of the Nagios EC2 instance"
  value       = aws_instance.nagios_instance.public_ip
}

output "website_url" {
  description = "URL to access the Travel website"
  value       = "http://${aws_instance.travel-website_instance.public_ip}"
}
