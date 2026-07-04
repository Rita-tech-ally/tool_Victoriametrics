pipeline {
    agent any

    parameters {
        choice(name: 'ACTION', choices: ['apply', 'destroy'], description: 'Choose whether to deploy (apply) or clean up (destroy) the infrastructure.')
    }

    environment {
        // AWS Credentials from Jenkins (Credentials type: Secret text)
        AWS_ACCESS_KEY_ID     = credentials('AWS_ACCESS_KEY_ID')
        AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
        AWS_DEFAULT_REGION    = 'ap-south-1'

        // SSH Private Key from Jenkins (Credentials type: Secret file)
        SSH_KEY_FILE          = credentials('SAKSHI_SSH_KEY')
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

        stage('Terraform Apply (Standalone Nodes)') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                dir('terraform') {
                    // Stage 1: Deploy standalone VM instances only (ASGs scale set to 0)
                    sh '''
                        terraform apply -auto-approve \
                          -var="ingestion_asg_desired=0" \
                          -var="ingestion_asg_min=0" \
                          -var="query_asg_desired=0" \
                          -var="query_asg_min=0"
                    '''
                }
            }
        }

        stage('Wait for Standalone Boot') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                echo "Waiting 45 seconds for standalone VM instances to boot up and start SSH..."
                sleep time: 45, unit: 'SECONDS'
            }
        }

        stage('Ansible Dry Run') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                script {
                    echo "Running Ansible dry-run (check mode)..."
                    // Copy private key file to workspace with correct SSH permissions
                    sh '''
                        cp "${SSH_KEY_FILE}" sakshi.pem
                        chmod 400 sakshi.pem
                    '''
                    
                    // Run Ansible Playbook in check mode (dry-run)
                    // We allow this to fail/warn gracefully if some steps depend on actual files that aren't created in dry-run
                    sh 'ansible-playbook ha.yml --check || echo "Ansible Dry Run completed with warnings (expected on unprovisioned nodes)."'
                }
            }
        }

        stage('Ansible Provisioning') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                script {
                    // Copy private key file to workspace with correct SSH permissions
                    sh '''
                        cp "${SSH_KEY_FILE}" sakshi.pem
                        chmod 400 sakshi.pem
                    '''
                    
                    // Run Ansible Playbook to configure the VM instances
                    sh 'ansible-playbook ha.yml'
                }
            }
        }

        stage('Bake AMIs') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                script {
                    echo "Fetching standalone Instance IDs from Terraform outputs..."
                    def vminsertId = sh(script: "cd terraform && terraform output -raw vminsert_instance_id", returnStdout: true).trim()
                    def vmselectId = sh(script: "cd terraform && terraform output -raw vmselect_instance_id", returnStdout: true).trim()
                    
                    echo "vminsert Instance ID: ${vminsertId}"
                    echo "vmselect Instance ID: ${vmselectId}"
                    
                    def timestamp = sh(script: "date +%s", returnStdout: true).trim()
                    def ingestAmiName = "vminsert-baked-${timestamp}"
                    def queryAmiName = "vmselect-baked-${timestamp}"
                    
                    echo "Baking AMI for Ingestion: ${ingestAmiName}"
                    def ingestAmiId = sh(script: """
                        aws ec2 create-image \
                          --instance-id "${vminsertId}" \
                          --name "${ingestAmiName}" \
                          --no-reboot \
                          --query "ImageId" \
                          --output text
                    """, returnStdout: true).trim()
                    
                    echo "Baking AMI for Query: ${queryAmiName}"
                    def queryAmiId = sh(script: """
                        aws ec2 create-image \
                          --instance-id "${vmselectId}" \
                          --name "${queryAmiName}" \
                          --no-reboot \
                          --query "ImageId" \
                          --output text
                    """, returnStdout: true).trim()
                    
                    echo "Ingestion AMI ID: ${ingestAmiId}"
                    echo "Query AMI ID: ${queryAmiId}"
                    
                    // Store AMI IDs in env variables for the next stage
                    env.INGEST_AMI_ID = ingestAmiId
                    env.QUERY_AMI_ID = queryAmiId
                    
                    echo "Waiting for baked AMIs to become active/available..."
                    sh "aws ec2 wait image-available --image-ids ${ingestAmiId} ${queryAmiId}"
                    echo "AMIs are ready for ASG deployment!"
                }
            }
        }

        stage('Terraform Apply (Scale ASGs)') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                dir('terraform') {
                    // Stage 2: Scale ASGs to 1 using the newly baked AMIs
                    sh '''
                        terraform apply -auto-approve \
                          -var="ami_id_ingestion=${INGEST_AMI_ID}" \
                          -var="ami_id_query=${QUERY_AMI_ID}" \
                          -var="ingestion_asg_desired=1" \
                          -var="ingestion_asg_min=1" \
                          -var="query_asg_desired=1" \
                          -var="query_asg_min=1"
                    '''
                }
            }
        }

        stage('Terraform Destroy') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                dir('terraform') {
                    // Destroy all Terraform-managed infrastructure
                    sh 'terraform destroy -auto-approve'
                }
            }
        }

        stage('Clean Baked AMIs & Snapshots') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                script {
                    echo "Cleaning up baked AMIs and their snapshots from AWS..."
                    sh '''
                        # Find all AMI IDs starting with vminsert-baked- or vmselect-baked-
                        for ami_id in $(aws ec2 describe-images --owners self --filters "Name=name,Values=vminsert-baked-*,vmselect-baked-*" --query "Images[].ImageId" --output text); do
                            echo "Deregistering AMI: $ami_id"
                            # Find snapshot ID associated with the AMI
                            snapshot_ids=$(aws ec2 describe-images --image-ids "$ami_id" --query "Images[].BlockDeviceMappings[].Ebs.SnapshotId" --output text)
                            aws ec2 deregister-image --image-id "$ami_id"
                            
                            # Delete the EBS snapshots associated with the AMI
                            for snap in $snapshot_ids; do
                                if [ "$snap" != "None" ] && [ -n "$snap" ]; then
                                    echo "Deleting snapshot: $snap"
                                    aws ec2 delete-snapshot --snapshot-id "$snap"
                                fi
                            done
                        done
                    '''
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
            }
        }
        success {
            script {
                echo "Pipeline action '${params.ACTION}' completed successfully!"
                
                // Send Email Notification
                mail to: 'rituc7707@gmail.com',
                     subject: "SUCCESS: Job '${env.JOB_NAME}' [build #${env.BUILD_NUMBER}]",
                     body: "Pipeline action '${params.ACTION}' completed successfully.\nView build logs at: ${env.BUILD_URL}"
                
                // Send Slack Notification
                slackSend(channel: '#all-ritu',
                          color: 'good',
                          message: "SUCCESS: Job '${env.JOB_NAME}' [build #${env.BUILD_NUMBER}] completed successfully.\nAction: ${params.ACTION}\nView logs: ${env.BUILD_URL}")
            }
        }
        failure {
            script {
                echo "Pipeline action '${params.ACTION}' failed. Check stage logs for details."
                
                // Send Email Notification
                mail to: 'rituc7707@gmail.com',
                     subject: "FAILURE: Job '${env.JOB_NAME}' [build #${env.BUILD_NUMBER}]",
                     body: "Pipeline action '${params.ACTION}' failed.\nView build logs at: ${env.BUILD_URL}"
                
                // Send Slack Notification
                slackSend(channel: '#all-ritu',
                          color: 'danger',
                          message: "FAILURE: Job '${env.JOB_NAME}' [build #${env.BUILD_NUMBER}] failed.\nAction: ${params.ACTION}\nView logs: ${env.BUILD_URL}")
            }
        }
    }
}
