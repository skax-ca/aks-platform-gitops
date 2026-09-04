# aks-platform-gitops

**읽는 사람**: 이 저장소의 매니페스트를 고치거나, 클러스터·addon을 새로 등록하는 사람.

**오너**: GitHub org [`skax-ca`](https://github.com/skax-ca) 소속. 클러스터·IAM 문의는
`aks-reference-infra` 쪽과 겹칠 수 있다.

**플랫폼 GitOps monorepo(계층 2)** - ArgoCD가 pull로 reconcile하는 플랫폼 소관
매니페스트 저장소. AWS 원본 [`eks-platform-gitops`](https://github.com/skax-ca/eks-platform-gitops)의
Azure 대응.

⛔ **설계 SSOT는 이 저장소가 아니다.** GitOps 엔진·Ingress addon 선정 같은 이
저장소 고유의 설계 판단은 `aks-reference-infra`의
`.omc/plans/aks-platform-gitops-addon-selection.md`가 갖는다(6라운드 공식 문서
리서치 근거 전문). 클러스터·네트워킹·bootstrap 자격증명은 `aks-reference-infra`
자체가 SSOT다.

⏳ **스캐폴딩 단계.** 디렉토리 레이아웃만 잡혀 있고 실제 매니페스트는 아직 없다.
plan/ralplan을 거쳐 채운다(CLAUDE.md 프로젝트 절차, `aks-reference-infra` 참고).

---

## 확정된 설계 (근거는 위 plans 문서)

| 갈림점 | AWS 원본 | 이 저장소(Azure) |
|---|---|---|
| GitOps 엔진 | self-managed ArgoCD | **self-managed ArgoCD**(관리형 확장은 Public Preview라 보류) |
| L7 Ingress(ALBC 대응) | aws-load-balancer-controller(helm, baseline) | **Application Gateway for Containers(AGFC/ALB Controller)**, self-managed Helm - AKS 관리형 add-on 경로 아님 |
| addon 배포 원칙 | Terraform=IAM만, 컨트롤러=Helm, CR=GitOps | 동일하게 유지(Managed Identity+federated credential+role assignment는 Terraform, `alb-controller` 컨트롤러는 Helm) |

## 이 저장소가 다루는 것 / 다루지 않는 것

AWS 원본과 동일한 3계층 소유 모델에서 **계층 2만** 담당한다.

| 계층 | 무엇 | 어디 |
|---|---|---|
| 1. Terraform | 클러스터·네트워킹·IAM(Managed Identity·role assignment) | `skax-ca/aks-reference-infra` |
| **2. 플랫폼 GitOps** | **helm addon · 클러스터 등록 · AppProject 가드레일** | **이 저장소** |
| 3. 앱 GitOps | 비즈니스 워크로드 | 앱팀별 repo(범위 밖) |

⛔ **`apps/` 디렉토리는 의도적으로 없다** - AWS 원본과 같은 이유(플랫폼 addon
업그레이드는 fleet 전체에, 앱 배포는 한 팀에만 영향을 준다).

## 레이아웃 (뼈대만, 내용 미작성)

```
bootstrap/    # App-of-Apps root(자기소멸/self-superseding) + ArgoCD 자기 관리 매니페스트
clusters/     # cluster Secret + per-cluster values. 새 클러스터 = 디렉토리 1개(O(1))
projects/     # AppProject 가드레일 - platform.yaml + <team>.yaml
addons/baseline/  # 전 클러스터 팬아웃 ApplicationSet(environment 라벨) - AGFC가 여기 온다
addons/catalog/   # opt-in 카탈로그 - 구독한 클러스터만
```

AWS 원본에 있는 `addons/karpenter/nodepool/`(Karpenter 로컬 helm 차트)은 Azure에
대응물이 없어(Karpenter는 AWS 전용) 이 저장소엔 없다.

## 다음 단계

1. plan/ralplan으로 이 저장소의 착수 설계를 확정한다 - 특히
   `aks-platform-gitops-addon-selection.md` 4절의 미해결 유보(Gateway API
   conformance 벤더선언 수준, private cluster canary 미실측)를 이 단계에서
   실측 계획에 포함시킨다.
2. `bootstrap/root-app.yaml`·`projects/platform.yaml`·
   `clusters/hub/aks-demo-hub-krc-main-01/cluster-secret.yaml`·
   `addons/baseline/alb-controller.yaml`을 AWS 원본 1:1 대응으로 작성한다.
3. `aks-reference-infra`의 bootstrap/live 루트에 AGFC용 Managed
   Identity·federated credential·role assignment를 추가한다(이 저장소의
   전제조건).
