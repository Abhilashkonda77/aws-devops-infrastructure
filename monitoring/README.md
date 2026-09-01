# Monitoring

The CloudWatch dashboards and alarms for this project are provisioned as
Terraform resources — see `infrastructure/modules/cloudwatch/main.tf` — not
as standalone JSON files applied out-of-band. This keeps monitoring
config versioned and reproducible alongside the infrastructure it observes.

This directory exists as the conventional home for:

- `dashboards/` — drop exported dashboard JSON here if you ever want to
  hand-tweak a dashboard in the console and re-import it as a Terraform
  `dashboard_body` for reference/diffing. Empty by default.
- `alarms/` — same idea, for one-off alarm definitions you're prototyping
  before promoting them into `infrastructure/modules/cloudwatch/main.tf`.
  Empty by default.

To see the actual dashboard/alarm definitions, go to
`infrastructure/modules/cloudwatch/main.tf`. To view them live after
`terraform apply`, use the URLs in each environment's Terraform outputs:
`infrastructure_dashboard_url` and `application_dashboard_url`.
