// =============================================================================
// Declarative Jenkins Pipeline — EKS CI/CD
// Auth    : EC2 Instance Profile (no hardcoded credentials)
// Registry: Amazon ECR
// Deploy  : EKS rolling update via kubectl
// Notify  : Slack (success / failure)
// =============================================================================

pipeline {

    // Run on any available agent (label it if you have dedicated build nodes)
    agent any

    // ── Tool installations ────────────────────────────────────────────────────
    // Names MUST match what is configured in:
    // Manage Jenkins → Tools → Maven installations / JDK installations
    tools {
        maven 'maven'   // adds /opt/maven/bin to PATH for every sh step
    }

    // ── Pipeline-level environment variables ─────────────────────────────────
    // Override these at build time via "Build with Parameters" or in the
    // Jenkins job configuration — never hardcode secrets here.
    environment {
        // ── AWS / ECR ─────────────────────────────────────────────────────
        AWS_ACCOUNT_ID  = "${params.AWS_ACCOUNT_ID}"
        REGION          = "${params.REGION}"
        ECR_REPO_NAME   = "${params.ECR_REPO_NAME}"
        ECR_REGISTRY    = "${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
        IMAGE_TAG       = "${BUILD_NUMBER}"
        FULL_IMAGE      = "${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}"

        // ── EKS ───────────────────────────────────────────────────────────
        CLUSTER_NAME    = "${params.CLUSTER_NAME}"
        K8S_NAMESPACE   = "${params.K8S_NAMESPACE}"
        APP_NAME        = "eks-cicd-app"

        // ── Slack ─────────────────────────────────────────────────────────
        SLACK_CHANNEL   = "${params.SLACK_CHANNEL}"
        // SLACK_CREDENTIAL is the ID of the Jenkins credential that stores
        // the Slack Bot token (added via "Manage Jenkins → Credentials").
        SLACK_CREDENTIAL = "slack-bot-token"
    }

    // ── User-overridable parameters ──────────────────────────────────────────
    parameters {
        string(name: 'AWS_ACCOUNT_ID',
               defaultValue: '655700896650',
               description: 'AWS Account ID (12 digits)')

        string(name: 'REGION',
               defaultValue: 'ap-south-1',
               description: 'AWS region where ECR and EKS live')

        string(name: 'ECR_REPO_NAME',
               defaultValue: 'eks-cicd',
               description: 'ECR repository name')

        string(name: 'CLUSTER_NAME',
               defaultValue: 'ekswithavinash',
               description: 'EKS cluster name')

        string(name: 'K8S_NAMESPACE',
               defaultValue: 'eks-cicd',
               description: 'Kubernetes namespace to deploy into')

        string(name: 'SLACK_CHANNEL',
               defaultValue: '#eks-cicd-alerts',
               description: 'Slack channel for build notifications')

        booleanParam(name: 'SKIP_TESTS',
                     defaultValue: false,
                     description: 'Skip Maven unit tests (not recommended for production)')
    }

    options {
        // Keep only the last 10 builds to save disk space
        buildDiscarder(logRotator(numToKeepStr: '10'))
        // Fail the build if it runs for more than 30 minutes
        timeout(time: 30, unit: 'MINUTES')
        // Add timestamps to all console output
        timestamps()
        // Do not allow concurrent builds of the same job
        disableConcurrentBuilds()
    }

    // ── Stages ───────────────────────────────────────────────────────────────
    stages {

        // ── 1. Checkout ───────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                echo "Checking out source code..."
                checkout scm
                // Print the commit SHA for traceability
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: "git rev-parse --short HEAD",
                        returnStdout: true
                    ).trim()
                    echo "Commit: ${env.GIT_COMMIT_SHORT}"
                }
            }
        }

        // ── 2. Build (Maven) ──────────────────────────────────────────────
        stage('Build') {
            steps {
                echo "Building application with Maven..."
                script {
                    def mvnFlags = params.SKIP_TESTS ? '-DskipTests' : ''
                    sh """
                        mvn clean package ${mvnFlags} -B \
                            --no-transfer-progress \
                            -Dapp.version=${BUILD_NUMBER}
                    """
                }
            }
            post {
                always {
                    // Archive the JAR so it is downloadable from Jenkins UI
                    archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
                }
                failure {
                    echo "Maven build failed — check the console output above."
                }
            }
        }

        // ── 3. Docker Build ───────────────────────────────────────────────
        stage('Docker Build') {
            steps {
                echo "Building Docker image: ${FULL_IMAGE}"
                sh """
                    docker build \
                        --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                        --label "git-commit=${env.GIT_COMMIT_SHORT}" \
                        --label "build-number=${BUILD_NUMBER}" \
                        --tag  ${FULL_IMAGE} \
                        --tag  ${ECR_REGISTRY}/${ECR_REPO_NAME}:latest \
                        .
                """
            }
        }

        // ── 4. ECR Login + Push ───────────────────────────────────────────
        stage('ECR Login & Push') {
            steps {
                echo "Authenticating with ECR and pushing image..."
                sh """
                    # Authenticate using the EC2 instance profile — no keys needed
                    aws ecr get-login-password --region ${REGION} | \
                        docker login --username AWS \
                                     --password-stdin ${ECR_REGISTRY}

                    # Push versioned tag
                    docker push ${FULL_IMAGE}

                    # Push :latest for convenience
                    docker push ${ECR_REGISTRY}/${ECR_REPO_NAME}:latest
                """
            }
            post {
                always {
                    // Remove local images to free disk space on the build agent
                    sh """
                        docker rmi ${FULL_IMAGE}                               || true
                        docker rmi ${ECR_REGISTRY}/${ECR_REPO_NAME}:latest     || true
                    """
                }
            }
        }

        // ── 5. Deploy to EKS ──────────────────────────────────────────────
        stage('Deploy to EKS') {
            steps {
                echo "Updating kubeconfig and deploying to EKS cluster: ${CLUSTER_NAME}"
                sh """
                    # Update local kubeconfig using instance profile (no keys needed)
                    aws eks update-kubeconfig \
                        --region       ${REGION} \
                        --name         ${CLUSTER_NAME}

                    # Ensure the namespace exists
                    kubectl apply -f k8s/namespace.yaml

                    # Substitute the image tag placeholder and apply manifests
                    sed 's|IMAGE_PLACEHOLDER|${FULL_IMAGE}|g' k8s/deployment.yaml | \
                        kubectl apply -f -

                    kubectl apply -f k8s/service.yaml

                    # Wait for the rollout to complete (max 5 minutes)
                    kubectl rollout status deployment/${APP_NAME} \
                        --namespace ${K8S_NAMESPACE} \
                        --timeout=5m
                """
            }
        }

        // ── 6. Smoke Test ─────────────────────────────────────────────────
        // Hits the NodePort (30080) on the first node's internal IP.
        // Jenkins EC2 must be in the same VPC as the EKS nodes.
        stage('Smoke Test') {
            steps {
                echo "Running post-deployment smoke test via NodePort..."
                script {
                    sleep(time: 10, unit: 'SECONDS')

                    def nodeIP = sh(
                        script: """
                            kubectl get nodes \
                                -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' \
                                --namespace ${K8S_NAMESPACE}
                        """,
                        returnStdout: true
                    ).trim()

                    if (nodeIP) {
                        sh "curl --fail --silent --max-time 10 http://${nodeIP}:30080/actuator/health"
                        echo "Smoke test passed — app is reachable on NodePort 30080."
                    } else {
                        echo "Could not resolve node IP; skipping smoke test."
                    }
                }
            }
        }
    }

    // ── Post-pipeline notifications ───────────────────────────────────────────
    post {
        success {
            echo "Pipeline completed successfully."
            slackSend(
                channel:     "${SLACK_CHANNEL}",
                color:       'good',
                tokenCredentialId: "${SLACK_CREDENTIAL}",
                message: """:white_check_mark: *BUILD SUCCESS*
*Job*      : ${env.JOB_NAME}
*Build*    : #${env.BUILD_NUMBER}
*Commit*   : ${env.GIT_COMMIT_SHORT}
*Image*    : `${FULL_IMAGE}`
*Duration* : ${currentBuild.durationString}
<${env.BUILD_URL}|View Build>"""
            )
        }

        failure {
            echo "Pipeline failed."
            slackSend(
                channel:     "${SLACK_CHANNEL}",
                color:       'danger',
                tokenCredentialId: "${SLACK_CREDENTIAL}",
                message: """:x: *BUILD FAILED*
*Job*      : ${env.JOB_NAME}
*Build*    : #${env.BUILD_NUMBER}
*Stage*    : ${env.STAGE_NAME ?: 'unknown'}
*Duration* : ${currentBuild.durationString}
<${env.BUILD_URL}console|View Console Log>"""
            )
        }

        unstable {
            slackSend(
                channel:     "${SLACK_CHANNEL}",
                color:       'warning',
                tokenCredentialId: "${SLACK_CREDENTIAL}",
                message: """:warning: *BUILD UNSTABLE*
*Job*   : ${env.JOB_NAME}
*Build* : #${env.BUILD_NUMBER}
<${env.BUILD_URL}|View Build>"""
            )
        }

        always {
            // Clean workspace to prevent stale artifacts across builds
            cleanWs()
        }
    }
}
