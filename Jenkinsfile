pipeline {
    agent any

    parameters {
        booleanParam(
            name: 'DESTROY_INFRA',
            defaultValue: false,
            description: '⚠️ Destroy ALL Terraform-managed infrastructure (EKS, VPC, etc.)'
        )
    }

    environment {
        AWS_REGION = 'us-east-1'
        DOCKERHUB_USERNAME = 'peterukpabi4'
        
        IMAGE_NAME  = 'prime-choice-app'
        EKS_CLUSTER_NAME = 'my-cluster'
        TAG = "${env.BUILD_NUMBER}"  // dynamic image tag
    }

    stages {

        stage('Checkout Code') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Init & Apply (EKS)') {
            when { expression { params.DESTROY_INFRA == false } }
            steps {
                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: 'aws-credentials']
                ]) {
                    dir('Prime_Choice') {
                        sh '''
                          terraform init
                          terraform validate
                          terraform apply -auto-approve
                        '''
                    }
                }
            }
        }
        
stage('Configure AWS & EKS') {
    when { expression { params.DESTROY_INFRA == false } }
    steps {
        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-credentials']]) {
            sh '''
                export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
                export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
                export AWS_DEFAULT_REGION=$AWS_REGION

                aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME

                kubectl cluster-info
                kubectl get nodes
            '''
        }
    }
}


        stage('Docker Login') {
            when { expression { params.DESTROY_INFRA == false } }
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-credentials',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )
                ]) {
                    sh 'echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin'
                }
            }
        }

        stage('Build Docker Images') {
            when { expression { params.DESTROY_INFRA == false } }
            steps {
                dir('Prime_Choice') {
                    sh "docker build -t $DOCKERHUB_USERNAME/$IMAGE_NAME:$TAG ."
                }
                
            }
        }

        stage('Push Docker Images') {
            when { expression { params.DESTROY_INFRA == false } }
            steps {
                sh """
                  docker push $DOCKERHUB_USERNAME/$IMAGE_NAME:$TAG
                  
                """
            }
        }

        stage('Update YAMLs & Deploy to EKS') {
    when { expression { params.DESTROY_INFRA == false } }
    steps {
        dir('kubernetes') {
            sh """
              echo "Updating Django image tag..."

              # Update Docker image tag inside django-deployment.yaml
              sed -i "s|image: .*|image: $DOCKERHUB_USERNAME/$IMAGE_NAME:$TAG|g" django-deployment.yaml

              echo "Applying Kubernetes manifests..."

              # Create namespace first
              kubectl apply -f namespace.yaml

              # Apply secrets and config
              kubectl apply -f postgres-secret.yaml
              kubectl apply -f django-secret.yaml
              kubectl apply -f django-configmap.yaml

              # Apply storage
              kubectl apply -f postgres-pvc.yaml

              # Deploy database
              kubectl apply -f postgres-deployment.yaml
              kubectl apply -f postgres-service.yaml

              # Deploy Django app
              kubectl apply -f django-deployment.yaml
              kubectl apply -f django-service.yaml

              echo "Waiting for deployments to be ready..."

              kubectl rollout status deployment/postgres --timeout=300s
              kubectl rollout status deployment/django --timeout=300s
            """
        }
    }
}


        // stage('Update YAMLs & Deploy to EKS') {
        //     when { expression { params.DESTROY_INFRA == false } }
        //     steps {
        //         dir('Prime_Choice/kubernetes') {
        //             sh """
        //               # Update Docker image tags in YAML manifests
        //               sed -i 's|image: .*peterukpabi4/prime-choice-app:v1.*|image: $DOCKERHUB_USERNAME/$IMAGE_NAME:$TAG|g' django-deployment.yaml
                      
        //               # Apply all manifests
        //               kubectl apply -f ./django-configmap.yaml
        //               kubectl apply -f ./django-secret.yaml
        //               kubectl apply -f ./postgres-deployment.yaml
        //               kubectl apply -f ./mongo-service.yaml
        //               kubectl apply -f ./frontend.yaml
        //               kubectl apply -f ./backend.yaml

        //               # Wait for deployments
        //               kubectl rollout status deployment/react-todo-frontend --timeout=300s
        //               kubectl rollout status deployment/react-todo-backend --timeout=300s
        //               kubectl rollout status deployment/mongo --timeout=300s
        //             """
        //         }
        //     }
        // }

        /* ===============================
           DESTROY STAGE (MANUAL)
           =============================== */
        stage('Terraform Destroy (EKS & Infra)') {
            when { expression { params.DESTROY_INFRA == true } }
            steps {
                withCredentials([
                    [$class: 'AmazonWebServicesCredentialsBinding',
                     credentialsId: 'aws-credentials']
                ]) {
                    dir('Prime_Choice') {
                        sh '''
                          terraform init
                          terraform destroy -auto-approve
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            sh 'docker logout || true'
        }
        failure {
            echo '❌ Pipeline failed!'
        }
        success {
            echo '✅ Pipeline completed successfully!'
        }
    }
}
