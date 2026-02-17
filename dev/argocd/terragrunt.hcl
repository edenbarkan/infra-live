include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/argocd"
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_endpoint                    = "https://mock-eks-endpoint"
    cluster_certificate_authority_data  = "bW9jay1jZXJ0LWRhdGE="
  }
  mock_outputs_allowed_terraform_commands = ["destroy"]
}

# ArgoCD needs ingress-nginx to be deployed first (for UI access)
dependency "ingress_nginx" {
  config_path = "../ingress-nginx"

  mock_outputs = {
    ingress_nginx_output = "mock-value"
  }
  mock_outputs_allowed_terraform_commands = ["destroy"]
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

inputs = {
  cluster_name                        = local.env.locals.cluster_name
  cluster_endpoint                    = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data  = dependency.eks.outputs.cluster_certificate_authority_data
  environment                         = local.env.locals.environment
  namespaces                          = local.env.locals.namespaces
  helm_charts_repo_url                = "https://github.com/edenbarkan/helm-charts.git"
  auto_sync                           = true
  domain                              = "argocd.dev.example.com"
  tags                                = local.env.locals.tags
}
