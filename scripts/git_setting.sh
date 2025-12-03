#!/bin/bash
set -e

sudo yum install -y yum-utils

sudo yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo

sudo yum install -y gh


#############################################
# Required settings
aws ssm put-parameter \
  --name "/github/test/pat" \
  --type "SecureString" \
  --value "your_PAT" \
  --overwrite

GH_TOKEN=$(aws ssm get-parameter \
  --name "/github/test/pat" \
  --with-decryption \
  --query "Parameter.Value" \
  --output text)

GITHUB_OWNER="your_username"
GITHUB_REPO="your_repository"
GITHUB_URL="https://github.com/$GITHUB_OWNER/$GITHUB_REPO.git"
#############################################

cd /home/ec2-user
rm -rf "$GITHUB_REPO"
git clone "$GITHUB_URL"
cd "$GITHUB_REPO"

mkdir -p .github/workflows

cp /home/ec2-user/Dockerfile .
cp /home/ec2-user/main.go .
cp -r /home/ec2-user/EKS .

cat > .github/workflows/build-and-deploy.yml << 'EOF'
name: Build and Deploy to EKS

on:
  push:
    branches: [ main ]   # 원하는 브랜치

permissions:
  id-token: write
  contents: read

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    env:
      AWS_REGION: ${{ secrets.AWS_REGION }}
      ECR_REGISTRY: ${{ secrets.ECR_REGISTRY }}
      ECR_REPOSITORY: ${{ secrets.ECR_REPOSITORY }}
      EKS_CLUSTER_NAME: ${{ secrets.EKS_CLUSTER_NAME }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      # 여기서 인증 방식 2가지 중 하나 선택
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-region: ${{ env.AWS_REGION }}

          # (A) 새 Access Key를 쓴다면 – GitHub Secrets에만 넣고 여기서 참조
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

          # (B) OIDC Role 쓸 거면 위 두 줄 지우고 아래 두 줄 사용
          # role-to-assume: arn:aws:iam::<ACCOUNT_ID>:role/GitHubActionsOIDCRole
          # role-session-name: github-actions

      - name: Install kubectl
        run: |
          curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.14/2025-08-03/bin/linux/amd64/kubectl
          curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.14/2025-08-03/bin/linux/amd64/kubectl.sha256
          sha256sum -c kubectl.sha256
          chmod +x ./kubectl
          mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
          echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
          kubectl version --client

      - name: Configure kubeconfig and login to ECR
        run: |
          aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME
          aws ecr get-login-password --region $AWS_REGION \
            | docker login --username AWS --password-stdin $ECR_REGISTRY

      - name: Build, tag, and push image
        run: |
          docker build -t $ECR_REPOSITORY .
          docker tag $ECR_REPOSITORY:latest $ECR_REGISTRY/$ECR_REPOSITORY:latest
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest

      - name: Deploy manifests to EKS
        run: |
          kubectl apply -f ./EKS/namespace.yaml
          kubectl apply -f ./EKS/deployment.yaml
          kubectl apply -f ./EKS/service.yaml
          kubectl apply -f ./EKS/ingress.yaml
EOF

git config user.name "automation-bot"
git config user.email "automation@example.com"

git add EKS
git add Dockerfile
git add main.go
git add .github/workflows/build-and-deploy.yml

git commit -m "Add EKS deploy workflow, application source, Dockerfile, and Kubernetes manifests"
git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git"
git push origin main
