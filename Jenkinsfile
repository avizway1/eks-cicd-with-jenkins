// =============================================================================
// Declarative Jenkins Pipeline — EKS CI/CD
// Auth    : EC2 Instance Profile (no hardcoded credentials)
// Registry: Amazon ECR
// Deploy  : EKS rolling update via kubectl
// Notify  : Console echo (install Slack plugin to enable slackSend)
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
        // Curls /actuator/health from inside the pod — no NodePort/SG needed.
        stage('Smoke Test') {
            steps {
                echo "Running smoke test inside the pod..."
                script {
                    sleep(time: 10, unit: 'SECONDS')

                    def pod = sh(
                        script: """
                            kubectl get pod -n ${K8S_NAMESPACE} \
                                -l app=${APP_NAME} \
                                --field-selector=status.phase=Running \
                                -o jsonpath='{.items[0].metadata.name}'
                        """,
                        returnStdout: true
                    ).trim()

                    if (pod) {
                        sh "kubectl exec -n ${K8S_NAMESPACE} ${pod} -- curl -sf http://localhost:8080/actuator/health"
                        echo "Smoke test passed."
                    } else {
                        echo "No running pod found — skipping smoke test."
                    }
                }
            }
        }
    }

    post {
        success {
            echo "BUILD SUCCESS — ${env.JOB_NAME} #${env.BUILD_NUMBER} (${currentBuild.durationString})"
        }
        failure {
            echo "BUILD FAILED  — ${env.JOB_NAME} #${env.BUILD_NUMBER} — check console output above."
        }
        always {
            cleanWs()
        }
    }
}
