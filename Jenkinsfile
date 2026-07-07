pipeline {
    agent any

    parameters {
        choice(name: 'ACTION', choices: ['apply', 'destroy'], description: 'Choose whether to deploy (apply) or clean up (destroy) the infrastructure.')
    }

    environment {
        // AWS Credentials from Jenkins (using the existing ID 'aws-creds')
        AWS_CREDS             = credentials('aws-creds')
        AWS_DEFAULT_REGION    = 'ap-south-1'

        // SSH Private Key from Jenkins (using the existing ID 'ssh-key')
        SSH_KEY_FILE          = credentials('ssh-key')
    }

    stages {
        stage('Prerequisites Check') {
            steps {
                script {
                    echo "Checking installed tools in the Jenkins Agent..."
                    sh 'terraform version'
                    sh 'ansible --version'
                    sh 'ansible-lint --version'
                    sh 'aws --version'
                    
                    echo "Preparing SSH private key for Terraform and Ansible..."
                    sh 'cp "$SSH_KEY_FILE" sakshi.pem'
                    sh 'chmod 400 sakshi.pem'
                }
            }
        }

        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    sh 'terraform init'
                }
            }
        }

        stage('Static Analysis & Validation') {
            steps {
                script {
                    echo "Running Terraform validation..."
                    dir('terraform') {
                        sh 'terraform fmt -check -recursive'
                        sh 'terraform validate'
                    }
                    echo "Running Ansible lint & syntax validation..."
                    sh 'ansible-lint ha.yml'
                    sh 'ansible-playbook ha.yml --syntax-check'
                }
            }
        }

        stage('Terraform Plan') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                dir('terraform') {
                    echo "Generating Terraform execution plan (dry run)..."
                    sh '''
                        terraform plan \
                          -var="ingestion_asg_desired=0" \
                          -var="ingestion_asg_min=0" \
                          -var="query_asg_desired=0" \
                          -var="query_asg_min=0"
                    '''
                }
            }
        }

        stage('Manual Approval') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                script {
                    echo "Sending approval request email to rituc7707@gmail.com..."
                    try {
                        mail to: 'rituc7707@gmail.com',
                             subject: "APPROVAL REQUIRED: Job '${env.JOB_NAME}' [build #${env.BUILD_NUMBER}]",
                             body: "The deployment pipeline has completed the Terraform Plan stage and is waiting for your approval.\n\nPlease approve or abort the build here: ${env.BUILD_URL}"
                    } catch (Exception e) {
                        echo "Failed to send Approval email: ${e.getMessage()}"
                    }

                    input message: 'Do you want to proceed with the deployment?', ok: 'Deploy'
                }
            }
        }

        stage('Execute Action') {
            steps {
                script {
                    echo "Running action ${params.ACTION}..."
                    sh "chmod +x deploy.sh"
                    sh "./deploy.sh ${params.ACTION.toLowerCase()}"
                }
            }
        }
    }

    post {
        always {
            script {
                try {
                    echo "Cleaning up temporary private key file..."
                    sh 'rm -f sakshi.pem'
                } catch (Exception e) {
                    echo "Skipping file cleanup: No active agent node workspace found (${e.getMessage()})"
                }

                try {
                    echo "Creating S3 backup of Terraform state..."
                    sh 'aws s3 cp s3://victoriametrics-tfstate-bucket/terraform.tfstate s3://victoriametrics-tfstate-bucket/backup/terraform-${BUILD_NUMBER}.tfstate || echo "No state file found in S3 to backup."'
                } catch (Exception e) {
                    echo "Failed to backup state file to S3: ${e.getMessage()}"
                }
            }
        }
        success {
            script {
                echo "Pipeline action '${params.ACTION}' completed successfully!"
                
                // Send Email Notification
                try {
                    mail to: 'rituc7707@gmail.com',
                         subject: "SUCCESS: Job '${env.JOB_NAME}' [build #${env.BUILD_NUMBER}]",
                         body: "Pipeline action '${params.ACTION}' completed successfully.\nView build logs at: ${env.BUILD_URL}"
                } catch (Exception e) {
                    echo "Failed to send Email notification: ${e.getMessage()}"
                }
                
                // Send Slack Notification
                try {
                    slackSend(channel: '#all-ritu',
                              color: 'good',
                              message: "SUCCESS: Job '${env.JOB_NAME}' [build #${env.BUILD_NUMBER}] completed successfully.\nAction: ${params.ACTION}\nView logs: ${env.BUILD_URL}")
                } catch (Exception e) {
                    echo "Failed to send Slack notification: ${e.getMessage()}"
                }
            }
        }
        failure {
            script {
                echo "Pipeline action '${params.ACTION}' failed. Check stage logs for details."
                
                // Send Email Notification
                try {
                    mail to: 'rituc7707@gmail.com',
                         subject: "FAILURE: Job '${env.JOB_NAME}' [build #${env.BUILD_NUMBER}]",
                         body: "Pipeline action '${params.ACTION}' failed.\nView build logs at: ${env.BUILD_URL}"
                } catch (Exception e) {
                    echo "Failed to send Email notification: ${e.getMessage()}"
                }
                
                // Send Slack Notification
                try {
                    slackSend(channel: '#all-ritu',
                              color: 'danger',
                              message: "FAILURE: Job '${env.JOB_NAME}' [build #${env.BUILD_NUMBER}] failed.\nAction: ${params.ACTION}\nView logs: ${env.BUILD_URL}")
                } catch (Exception e) {
                    echo "Failed to send Slack notification: ${e.getMessage()}"
                }
            }
        }
    }
}
