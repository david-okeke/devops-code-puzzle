ENV ?= dev
TF_DIR := infrastructure/terraform

.PHONY: init fmt validate plan apply destroy output

init:
	cd $(TF_DIR) && terraform init

fmt:
	cd $(TF_DIR) && terraform fmt -recursive

validate: fmt
	cd $(TF_DIR) && terraform validate

plan: init validate
	cd $(TF_DIR) && terraform plan -var-file=environments/$(ENV).tfvars -out=$(ENV).tfplan

apply:
	cd $(TF_DIR) && terraform apply $(ENV).tfplan

destroy:
	cd $(TF_DIR) && terraform destroy -var-file=environments/$(ENV).tfvars

output:
	cd $(TF_DIR) && terraform output