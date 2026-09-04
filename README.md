# aks-platform-gitops

플랫폼 GitOps monorepo(계층 2) - hub-spoke AKS(`aks-reference-infra`) 위에서 ArgoCD가
pull로 reconcile하는 플랫폼 소관 매니페스트 저장소.

AWS 원본 `eks-platform-gitops`의 Azure 대응. 상세 설계는 착수 시 `deepinit` +
`aks-reference-infra`의 `.omc/plans/aks-platform-gitops-addon-selection.md`(GitOps
엔진·Ingress addon 선정 근거)를 입력으로 진행한다.

⏳ 스캐폴딩 전 단계.
