#!/bin/bash
set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="ap-northeast-2"
CLUSTER_NAME="must_input_eks_cluster_name"

sudo yum update -y

sudo yum install docker -y
sudo service docker start

sudo usermod -a -G docker ec2-user
sudo chmod 666 /var/run/docker.sock

cd /home/ec2-user

cat <<EOF > main.go
package main

import (
    "fmt"
    "net/http"
)

func hello(w http.ResponseWriter, req *http.Request) {
    fmt.Fprint(w, "Hello AWS")
}

func dummy(w http.ResponseWriter, req *http.Request) {
    fmt.Fprint(w, "BLUE")
}

func main() {
    http.HandleFunc("/hello", hello)
    http.HandleFunc("/v1/dummy", dummy)
    http.ListenAndServe(":80", nil)
}
EOF

cat <<EOF > Dockerfile
FROM golang:1.21.2

WORKDIR /app

COPY . .

RUN go build main.go

EXPOSE 80

CMD ["./main"]
EOF

aws ecr describe-repositories --repository-names dui-ecr-main >/dev/null 2>&1 || \
aws ecr create-repository --repository-name dui-ecr-main

aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$ACCOUNT_ID".dkr.ecr."$REGION".amazonaws.com
docker build -t dui-ecr-main .

docker tag dui-ecr-main:latest "$ACCOUNT_ID".dkr.ecr."$REGION".amazonaws.com/dui-ecr-main:latest
docker push "$ACCOUNT_ID".dkr.ecr."$REGION".amazonaws.com/dui-ecr-main:latest

# kubectl 설치
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.14/2025-08-03/bin/linux/amd64/kubectl
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.14/2025-08-03/bin/linux/amd64/kubectl.sha256

sha256sum -c kubectl.sha256
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH
echo 'export PATH=$HOME/bin:$PATH' >> ~/.bashrc
kubectl version --client

# eksctl 설치
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp

sudo mv /tmp/eksctl /usr/local/bin

eksctl version

# EKS 클러스터 kubeconfig 설정
aws eks update-kubeconfig --region $REGION --name "$CLUSTER_NAME"

sudo curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo unzip -u awscliv2.zip
sudo ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
sudo rm -rf /bin/aws
sudo ./aws/install -i /usr/local/aws -b /bin

aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

VPC_ID=$(aws eks describe-cluster \
  --region "$REGION" \
  --name "$CLUSTER_NAME" \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

oidc_id=$(aws eks describe-cluster \
  --region "$REGION" \
  --name "$CLUSTER_NAME" \
  --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)

aws iam list-open-id-connect-providers | grep "$oidc_id" | cut -d "/" -f4 || true
eksctl utils associate-iam-oidc-provider --cluster "$CLUSTER_NAME" --region "$REGION" --approve
aws iam list-open-id-connect-providers | grep "$oidc_id" | cut -d "/" -f4

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.7/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json || true

eksctl create iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --region "$REGION" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

# OIDC trust policy 갱신
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/oidc.eks.$REGION.amazonaws.com/id/$oidc_id"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.$REGION.amazonaws.com/id/$oidc_id:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }
  ]
}
EOF

aws iam update-assume-role-policy \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --policy-document file://trust-policy.json  

# ALB Controller용 EC2 Describe 권한 (VPC/Subnet/RT 등)
cat > alb-extra-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets",
        "ec2:DescribeRouteTables",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeInternetGateways"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --policy-name AWSLoadBalancerControllerExtraPolicy \
  --policy-document file://alb-extra-policy.json

# ★ 추가: ELB Describe 계열 권한 (DescribeListenerAttributes 에러 해결용)
cat > alb-elb-extra-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DescribeListenerAttributes",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:DescribeRules"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --policy-name AWSLoadBalancerControllerELBExtraPolicy \
  --policy-document file://alb-elb-extra-policy.json

kubectl -n kube-system get sa aws-load-balancer-controller >/dev/null 2>&1 || \
  kubectl create serviceaccount aws-load-balancer-controller -n kube-system

kubectl annotate serviceaccount aws-load-balancer-controller \
  -n kube-system \
  eks.amazonaws.com/role-arn=arn:aws:iam::$ACCOUNT_ID:role/AmazonEKSLoadBalancerControllerRole \
  --overwrite

# helm 설치 및 AWS Load Balancer Controller 배포
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > get_helm.sh
chmod 700 get_helm.sh
./get_helm.sh

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=180s || \
  echo "WARN: aws-load-balancer-controller rollout timed out, but Pods may still be running."

mkdir -p EKS

cat > EKS/namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: eks-main-app
EOF

cat > EKS/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: eks-main-app
  name: deployment-main
spec:
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: app-main
  template:
    metadata:
      labels:
        app.kubernetes.io/name: app-main
    spec:
      containers:
      - image: $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/dui-ecr-main:latest
        imagePullPolicy: Always
        name: app-main
        ports:
        - containerPort: 80
EOF

cat > EKS/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  namespace: eks-main-app
  name: service-main
spec:
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
  type: NodePort
  selector:
    app.kubernetes.io/name: app-main
EOF

cat > EKS/ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: eks-main-app
  name: ingress-main
  annotations:
    alb.ingress.kubernetes.io/healthcheck-path: /hello
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: service-main
              port:
                number: 80
EOF

kubectl apply -f EKS/namespace.yaml
kubectl apply -f EKS/deployment.yaml
kubectl apply -f EKS/service.yaml
kubectl apply -f EKS/ingress.yaml