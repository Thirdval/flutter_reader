// CI on Jenkins (ci.tendvine.io; backend-ci-and-secrets-plan.md C6/E1): ci/jenkins-gate.sh on a runner with Flutter, for
// main and pull requests — the old .github/workflows/ci.yml, which goes once this is green.
pipeline {
  agent { label 'flutter' }
  options {
    timeout(time: 60, unit: 'MINUTES')
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '60'))
  }
  stages {
    stage('Gate') {
      steps { sh 'bash ci/jenkins-gate.sh' }
    }
  }
}
