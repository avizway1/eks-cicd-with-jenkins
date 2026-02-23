#!/usr/bin/env bash
# =============================================================================
# jenkins-setup.sh
# Run this ONCE on the Jenkins EC2 instance (Amazon Linux 2023) as ec2-user
# with sudo privileges to install all required tools.
# =============================================================================
set -euo pipefail

echo "=== 1. System update ==="
sudo dnf update -y

echo "=== 2. Java 17 (Jenkins dependency) ==="
sudo dnf install -y java-17-amazon-corretto

echo "=== 3. Jenkins ==="
sudo wget -O /etc/yum.repos.d/jenkins.repo \
    https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
sudo dnf install -y jenkins
sudo systemctl enable --now jenkins
echo "  Jenkins running on :8080"

echo "=== 4. Maven ==="
MAVEN_VERSION="3.9.6"
sudo wget -qO /tmp/maven.tar.gz \
    "https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
sudo tar -xzf /tmp/maven.tar.gz -C /opt/
sudo ln -sfn "/opt/apache-maven-${MAVEN_VERSION}" /opt/maven
sudo tee /etc/profile.d/maven.sh > /dev/null <<'EOF'
export M2_HOME=/opt/maven
export PATH=$PATH:$M2_HOME/bin
EOF
source /etc/profile.d/maven.sh
mvn --version

echo "=== 5. Docker ==="
sudo dnf install -y docker
sudo systemctl enable --now docker
# Allow jenkins user to run Docker without sudo
sudo usermod -aG docker jenkins
echo "  NOTE: restart Jenkins after this script for group change to take effect"

echo "=== 6. kubectl ==="
K8S_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
sudo curl -sLo /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl"
sudo chmod +x /usr/local/bin/kubectl
kubectl version --client

echo "=== 7. AWS CLI v2 ==="
curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp/
sudo /tmp/aws/install --update
aws --version

echo "=== 8. Restart Jenkins to pick up Docker group ==="
sudo systemctl restart jenkins

echo ""
echo "============================================================"
echo "  NEXT STEPS (manual — do these in the Jenkins UI)"
echo "============================================================"
echo ""
echo "  1. Unlock Jenkins:"
echo "     sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
echo ""
echo "  2. Install these plugins (Manage Jenkins → Plugins):"
echo "     - Pipeline"
echo "     - Git"
echo "     - Docker Pipeline"
echo "     - Slack Notification"
echo "     - Pipeline: Stage View"
echo ""
echo "  3. Configure tools (Manage Jenkins → Tools):"
echo "     - JDK: Name=JDK17, JAVA_HOME=/usr/lib/jvm/java-17-amazon-corretto"
echo "     - Maven: Name=Maven3, /opt/maven"
echo ""
echo "  4. Add Slack credential (Manage Jenkins → Credentials):"
echo "     - Kind   : Secret text"
echo "     - ID     : slack-bot-token"
echo "     - Secret : <your Slack Bot OAuth token>"
echo ""
echo "  5. Ensure the EC2 instance profile has these IAM policies:"
echo "     - AmazonECR_FullAccess  (or a scoped custom policy)"
echo "     - AmazonEKSWorkerNodePolicy"
echo "     - AmazonEKSClusterPolicy (for eks:DescribeCluster)"
echo "     - AmazonEC2ContainerRegistryReadOnly (on EKS nodes)"
echo ""
echo "  6. Grant Jenkins IAM role access to EKS:"
echo "     kubectl edit configmap aws-auth -n kube-system"
echo "     # Add under mapRoles:"
echo "     # - rolearn: arn:aws:iam::<ACCOUNT>:role/<JENKINS_INSTANCE_ROLE>"
echo "     #   username: jenkins"
echo "     #   groups:"
echo "     #     - system:masters"
echo ""
echo "  7. Create the Pipeline job pointing to your Git repo."
echo ""
echo "============================================================"
