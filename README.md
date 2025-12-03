# eks-simple-deployer
Automate the creation of GitHub Actions and AWS EKS

* install terraform : <https://developer.hashicorp.com/terraform/install?product_intent=terraform>

설치 확인
```bash
terraform
```

VsCode 확장 프로그램
- Hashicorp HCL Extension <br>
  <https://marketplace.visualstudio.com/items?itemName=HashiCorp.HCL>
- Terraform <br>
  <https://marketplace.visualstudio.com/items?itemName=HashiCorp.terraform>

<br>


1. terraform
```
cd terraform

terraform init

terraform apply
```

<br>

2. bash
```
cd scripts

vim eks_automation.sh // Needs modification before running the shell script

chmod 700 eks_automation.sh

./eks_automation.sh
```

<br>

3. Github PAT(Personal access token) 생성
```
vim git_setting.sh // Needs modification before running the shell script

chmod 700 git_setting

./git_setting.sh
```