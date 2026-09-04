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

✅ **매니페스트 작성 완료(2026-09-04), 실행 전.** `bootstrap/`·`projects/`·`clusters/hub/`·
`addons/`가 AWS 원본 1:1 대응으로 채워졌다(RALPLAN-DR로 설계, `aks-reference-infra`의
`.omc/plans/aks-platform-gitops-scaffold.md` Follow-up 1). ⏳ **실제 seed 실행은 아직**
- private cluster라 workbench가 필요한데, `aks-reference-infra`의
`live/hub/workbench`(별도 세션 진행 중)가 아직 완료 전이다.

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

## 레이아웃

```
bootstrap/    # App-of-Apps root(자기소멸/self-superseding) + ArgoCD 자기 관리 매니페스트
              #   + argocd-seed.sh(vendored, iac-module-library SSOT)
clusters/hub/aks-demo-hub-krc-main-01/  # cluster Secret + values.yaml(라벨에 못 담는 값)
projects/     # AppProject 가드레일 - platform.yaml
addons/baseline/  # 전 클러스터 팬아웃 ApplicationSet(environment 라벨) - alb-controller.yaml
addons/alb-controller/loadbalancer/  # ApplicationLoadBalancer CR 로컬 helm 차트
addons/catalog/   # opt-in 카탈로그 - 아직 후보 없음
```

AWS 원본에 있는 `addons/karpenter/nodepool/`(Karpenter 로컬 helm 차트)은 Azure에
대응물이 없어(Karpenter는 AWS 전용) 이 저장소엔 없다.

## root App 스캔에서 파일을 빼는 방법 — 마커, `exclude` 아님

`bootstrap/root-app.yaml`은 저장소 루트를 재귀로 스캔해 모든 `.yaml`/`.yml`/`.json`을
매니페스트로 적용한다. `addons/alb-controller/loadbalancer/`의 helm 템플릿(`{{
.Values.subnetId }}` 등 미치환 문법)처럼 **매니페스트가 아닌 파일**은 스캔에서 빠져야 한다.

⛔ **`root-app.yaml`의 `exclude` 목록을 늘리지 않는다.** 대신 파일 안에
`+argocd:skip-file-rendering` 마커를 넣는다(AWS 원본 `eks-platform-gitops`와 동일 규약).

- 평문 YAML(`Chart.yaml`): `# +argocd:skip-file-rendering`
- helm 템플릿: `{{- /* +argocd:skip-file-rendering … */ -}}`(파일 내용에는 남고 렌더
  출력에는 안 남는다)

🔴 **마커의 함정 — 마커를 설명하는 주석도 마커다.** 판정은 파일 전체의 단순 문자열 포함
검사라, 주석이든 문서든 그 문자열이 한 번이라도 나타나면 파일 전체가 스캔에서 빠진다.
`root-app.yaml` 자신의 주석에 마커 문자열을 그대로 적으면 **root-app이 자기 자신을
스캔에서 제외**한다 — 에러 없이 조용히, 영구 `OutOfSync`로만 드러난다.

⚠️ **마커는 root-app만 빼는 게 아니라 "Directory 타입으로 이 파일을 읽는 모든
Application"에서 뺀다.** `Chart.yaml`이 있는 디렉토리를 전담 소스로 참조하면 Helm
타입으로 인식돼 이 함정을 피한다(`addons/alb-controller/loadbalancer/`가 이 형태).

**`argocd-seed.sh`는 `.sh`라 애초에 directory 소스의 스캔 대상이 아니다.**

## 알려진 미해결 항목

- **matrix generator의 클러스터 수 확장성**: `addons/baseline/alb-controller.yaml`의
  `alb-loadbalancer` ApplicationSet은 cluster generator × git files generator의
  Cartesian product를 쓴다. 클러스터가 hub 하나뿐인 지금은 1×1=1이라 우연히 맞지만,
  dev를 두 번째 클러스터로 등록하면 재검증이 필요하다(해당 파일 헤더 주석 참고).
- **GitHub App 설치 범위**: repository Secret은 기존 `skax-ca-gitops-reader` App(원래
  `eks-platform-gitops`용)을 재사용한다(2026-09-04 결정) - 이 저장소를 GitHub App
  설치(installation) 범위에 추가하는 작업이 seed 실행 전 필요.

## 다음 단계

1. `aks-reference-infra`의 `live/hub/workbench`(별도 세션 진행 중) 완료 대기 -
   private cluster에서 `helm install`·`kubectl apply`를 실행할 환경.
2. GitHub App(`skax-ca-gitops-reader`) 설치 범위에 이 저장소 추가.
3. workbench 준비 후 `bootstrap/argocd-seed.sh --dry-run`으로 먼저 확인, 이어서
   `--to 4`(자기 관리 흡수 이전 단계)까지 실행해 `argocd app diff argocd --core`로
   diff를 실측 확인한 뒤에만 `bootstrap/argocd-app.yaml`의 `automated` 블록을 최종
   확정한다(AWS 원본과 동일 순서, 이 파일 자체 주석 참고).
