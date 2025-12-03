# eks-simple-deployer
Automate the creation of GitHub Actions and AWS EKS

* install terraform : <https://developer.hashicorp.com/terraform/install?product_intent=terraform>

설치 확인
```bash
terraform
```

VsCode 확장 프로그램
- Haschicorp HCL Extension

    <https://marketplace.visualstudio.com/items?itemName=HashiCorp.HCL>
    
- Terraform

    <https://marketplace.visualstudio.com/items?itemName=HashiCorp.terraform>

1. terraform
```
cd terraform

terraform init

terraform apply
```

2. bash
```
cd scripts

vim eks_automation.sh

chmod 700 eks_automation.sh

./eks_automation.sh

vim git_setting.sh

chmod 700 git_setting

./git_setting.sh
```